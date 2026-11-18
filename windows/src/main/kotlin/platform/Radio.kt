package com.unoki99.fangfang

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.unoki99.fangfang.desktop.Aac
import com.unoki99.fangfang.desktop.Ffmpeg
import com.unoki99.fangfang.desktop.HlsInput
import com.unoki99.fangfang.desktop.Mp3
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.*
import java.io.BufferedInputStream
import java.io.FilterInputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

// (Windows) 電台's player; the stations, Radio Browser, the formats and the lyrics are the Android app's own
// (RadioShared.kt). Plain mp3 and AAC streams play through Java Sound (Mp3.kt, Stream.kt), with the song's name the
// station sends in the stream (ICY) for 歌詞; HLS and every other kind (Ogg, Opus, FLAC, AAC in MP4…) through FFmpeg
// (Ffmpeg.kt), which install-windows.bat downloads. Without FFmpeg, HLS with mp3 or AAC in it is still tried in Java.

object Radio {
    enum class State { IDLE, CONNECTING, PLAYING, FAILED }
    var state by mutableStateOf(State.IDLE); private set
    var current by mutableStateOf<RadioStation?>(null); private set
    /** what the station says is playing ("周杰倫 - 晴天"), when it says */
    var nowPlaying by mutableStateOf<String?>(null); private set
    val stations = mutableStateListOf<RadioStation>()
    private var loaded = false
    private var job: Job? = null
    private val scope = MainScope()
    @Volatile private var playing: Mp3.Playing? = null
    @Volatile private var conn: HttpURLConnection? = null
    /** (the stream being played: closed when it stops, so an HLS stream waiting for its next piece ends too) */
    @Volatile private var stream: InputStream? = null

    fun init(c: Context) {
        if (loaded) return
        loaded = true
        @Suppress("UNCHECKED_CAST")
        val l = try { (JReader(Prefs.radioStations.value.ifEmpty { "[]" }).any() as? List<Any?>)?.mapNotNull { (it as? Map<String, Any?>)?.let(RadioStation::from) } } catch (_: Exception) { null }
        if (l.isNullOrEmpty() && !Prefs.radioStarted.value) { restoreStarters(); Prefs.radioStarted.value = true } else stations.addAll(l ?: emptyList())
    }
    private fun save() { Prefs.radioStations.value = JWriter.any(stations.map { it.toMap() }) }

    fun restoreStarters() {
        for ((lang, name, q) in RadioLang.starters) if (stations.none { it.starter && it.name == name })
            stations.add(RadioStation(java.util.UUID.randomUUID().toString(), name, lang, query = q.first, country = q.second, starter = true))
        save()
    }
    fun add(rb: RBStation, lang: Int) {
        if (stations.any { it.uuid == rb.uuid }) return
        stations.add(RadioStation(java.util.UUID.randomUUID().toString(), rb.name, lang, rb.uuid, rb.name, rb.country.ifEmpty { null }, rb.stream, rb.favicon,
            format = rb.format))
        save()
    }
    fun add(name: String, url: String, lang: Int) { stations.add(RadioStation(java.util.UUID.randomUUID().toString(), name, lang, url = url)); save() }
    fun remove(s: RadioStation) { if (current?.id == s.id) stop(); stations.removeAll { it.id == s.id }; save() }
    fun has(rb: RBStation) = stations.any { it.uuid == rb.uuid }

    fun toggle(s: RadioStation) { if (current?.id == s.id && state != State.IDLE && state != State.FAILED) stop() else play(s) }

    fun play(s: RadioStation) {
        job?.cancel()
        halt()
        current = s; state = State.CONNECTING; nowPlaying = null
        job = scope.launch { connect(s) }
    }

    private fun halt() {
        playing?.stop(); playing = null
        try { stream?.close() } catch (_: Exception) {}
        stream = null
        try { conn?.disconnect() } catch (_: Exception) {}
        conn = null
    }

    fun stop() {
        job?.cancel(); job = null
        halt()
        state = State.IDLE; nowPlaying = null
        sleep(null)
    }

    /** 睡眠計時: stops by itself after these minutes (null: off) */
    var sleepAt by mutableStateOf<Long?>(null); private set
    private var sleepJob: Job? = null
    fun sleep(minutes: Int?) {
        sleepJob?.cancel(); sleepJob = null
        if (minutes == null) { sleepAt = null; return }
        sleepAt = System.currentTimeMillis() + minutes * 60_000L
        sleepJob = scope.launch { delay(minutes * 60_000L); sleepAt = null; sleepJob = null; stop() }
    }

    /** (電台 音量 changed, while playing) */
    fun radioVolumeChanged() { playing?.volume = Prefs.radioVolume.value }

    /** the addresses to try, in order: the station as Radio Browser lists it now, then a search by its name, then
     *  the last address that worked */
    private suspend fun connect(s: RadioStation) {
        val tried = HashSet<String>()
        suspend fun attempt(u: String, found: RBStation?): Boolean {
            if (u.isEmpty() || !tried.add(u)) return false
            val stream = RadioDirectory.unwrap(u)
            if (!open(stream)) return false
            remember(s, u, found)
            watch(s)
            return true
        }
        s.uuid?.let { id -> RadioDirectory.station(id)?.let { rb -> if ((rb.ok || s.url == null) && attempt(rb.stream, rb)) return } }
        if (s.query == null && s.url != null && attempt(s.url, null)) return
        val q = s.query ?: if (s.uuid != null) s.name else null
        if (q != null) {
            val found = try { RadioDirectory.search(name = q, country = s.country, limit = 12) } catch (_: Exception) { emptyList() }
            val want = s.name.lowercase()
            for (rb in found.sortedWith(compareBy<RBStation> { it.name.lowercase() != want }.thenByDescending { it.clicks })) {
                if (rb.ok && attempt(rb.stream, rb)) return
            }
        }
        if (s.url != null && attempt(s.url, null)) return
        halt()
        state = State.FAILED
    }

    /** the stream stopped by itself (the station's server, the network): connected again */
    private fun watch(s: RadioStation) {
        val p = playing ?: return
        scope.launch {
            while (playing === p && p.running) delay(500)
            if (playing === p && current?.id == s.id && state == State.PLAYING) { state = State.CONNECTING; play(s) }
        }
    }

    /** the format the last stream that played turned out to be (RadioFormat) */
    @Volatile private var heard: String? = null

    /** plays the address; true once sound is coming (false: it failed, or nothing came for 15 seconds). Plain mp3
     *  and AAC: Java Sound; HLS and anything else: FFmpeg when it's there; Java Sound failing: FFmpeg too. */
    private suspend fun open(address: String): Boolean {
        halt()
        heard = null
        // (what it is: HLS, or a stream and its first bytes of sound)
        val probe = withContext(Dispatchers.IO) {
            try {
                var url = URL(address)
                var hops = 0
                var c: HttpURLConnection
                while (true) {
                    c = url.openConnection() as HttpURLConnection
                    c.instanceFollowRedirects = false
                    c.connectTimeout = 10000; c.readTimeout = 15000
                    c.setRequestProperty("User-Agent", "FangfangCards/1.0")
                    c.setRequestProperty("Icy-MetaData", "1")
                    val code = c.responseCode
                    if (code in 300..399 && hops < 6) { url = URL(url, c.getHeaderField("Location") ?: break); hops++; c.disconnect(); continue }
                    if (code !in 200..299) { c.disconnect(); return@withContext null }
                    break
                }
                val type = (c.contentType ?: "").lowercase()
                if (type.contains("mpegurl") || url.path.lowercase().endsWith(".m3u8")) { c.disconnect(); return@withContext Probe(url.toString(), true, null, null) }
                val metaInt = c.getHeaderFieldInt("icy-metaint", 0)
                val raw = BufferedInputStream(c.inputStream, 1 shl 16)
                val input: InputStream = if (metaInt > 0) Icy(raw, metaInt) { t -> scope.launch { nowPlaying = t } } else raw
                val b = BufferedInputStream(input, 1 shl 17)
                b.mark(1 shl 16)
                val head = ByteArray(4096)
                var n = 0
                while (n < head.size) { val r = b.read(head, n, head.size - n); if (r < 0) break; n += r }
                b.reset()
                val h = head.copyOf(n)
                val kind = when {
                    type.contains("aac") || HlsInput.isAdts(h) -> RadioFormat.AAC
                    type.contains("mpeg") || type.contains("mp3") || looksMp3(h) -> RadioFormat.MP3
                    else -> null
                }
                conn = c
                Probe(url.toString(), false, kind, b)
            } catch (_: Exception) { null }
        } ?: return withFfmpeg(address, false)
        // HLS: FFmpeg first (it plays every kind of HLS); else the pieces in Java
        if (probe.hls) {
            if (Ffmpeg.exe() != null && withFfmpeg(probe.url, true)) return true
            return withJava(HlsInput(probe.url), null, hls = true)
        }
        // a plain stream: mp3 or AAC in Java (with the song names); anything else, or Java failing: FFmpeg
        val input = probe.input ?: return withFfmpeg(probe.url, false)
        if (probe.kind != null && withJava(input, probe.kind, hls = false)) return true
        try { input.close() } catch (_: Exception) {}
        halt()
        return withFfmpeg(probe.url, false)
    }

    private class Probe(val url: String, val hls: Boolean, val kind: String?, val input: InputStream?)

    /** mp3 frames: 0xFFE…, with a layer (not 00, which is AAC's ADTS) */
    private fun looksMp3(h: ByteArray): Boolean {
        for (i in 0 until h.size - 1) if (h[i] == 0xFF.toByte()) {
            val b = h[i + 1].toInt() and 0xff
            if (b and 0xE0 == 0xE0 && (b shr 1) and 3 != 0) return true
        }
        return false
    }

    private suspend fun withJava(input0: InputStream, kind: String?, hls: Boolean): Boolean {
        var input = input0
        var aac = kind == RadioFormat.AAC
        if (hls) {
            // (HLS in Java: AAC or mp3, by its first bytes)
            val b = withContext(Dispatchers.IO) {
                try {
                    val b = BufferedInputStream(input, 1 shl 17)
                    b.mark(1 shl 16)
                    val head = ByteArray(4096); var n = 0
                    while (n < head.size) { val r = b.read(head, n, head.size - n); if (r < 0) break; n += r }
                    b.reset()
                    aac = HlsInput.isAdts(head.copyOf(n))
                    b
                } catch (_: Exception) { null }
            } ?: return false
            input = b
        }
        stream = input
        var failed = false
        val p = if (aac) Aac.play(input, Prefs.radioVolume.value, onError = { failed = true })
                else Mp3.play(input, Prefs.radioVolume.value, onError = { failed = true })
        playing = p
        for (i in 0 until 150) {
            delay(100)
            if (p.sounding) { heard = if (hls) RadioFormat.HLS else kind; return true }
            if (failed || !p.running) break
        }
        try { input.close() } catch (_: Exception) {}
        halt()
        return false
    }

    private suspend fun withFfmpeg(url: String, hls: Boolean): Boolean {
        if (Ffmpeg.exe() == null) return false
        halt()
        var failed = false
        var found: String? = null
        val p = Ffmpeg.play(url, Prefs.radioVolume.value,
            onFormat = { f -> found = f },
            onTitle = { t -> scope.launch { nowPlaying = t } },
            onError = { failed = true }) ?: return false
        playing = p
        for (i in 0 until 200) {
            delay(100)
            if (p.sounding) { heard = if (hls) RadioFormat.HLS else found; return true }
            if (failed || !p.running) break
        }
        halt()
        return false
    }

    private fun remember(s: RadioStation, url: String, found: RBStation?) {
        val i = stations.indexOfFirst { it.id == s.id }
        // (its format: what it turned out to be when it played, else what Radio Browser says)
        val said = found?.format ?: s.format
        // (Java Sound can't tell AAC+ from AAC: Radio Browser's word is taken for that)
        val f = if (heard == RadioFormat.AAC && said == RadioFormat.AACP) said else heard ?: said
        var t = s.copy(url = url, format = f)
        if (found != null) {
            t = t.copy(uuid = found.uuid, query = t.query ?: t.name, country = t.country ?: found.country.ifEmpty { null },
                favicon = t.favicon ?: found.favicon.ifEmpty { null })
            RadioDirectory.clicked(found.uuid)
        }
        if (i >= 0 && stations[i] != t) { stations[i] = t; save() }
        current = t
        state = State.PLAYING
    }
}

/** a SHOUTcast / Icecast stream with the song's name in it (every metaInt bytes of sound, a block "StreamTitle='…';"):
 *  only the sound goes on, the name to onTitle */
private class Icy(input: InputStream, private val metaInt: Int, private val onTitle: (String) -> Unit) : FilterInputStream(input) {
    private var left = metaInt
    private fun readMeta() {
        val n = `in`.read()
        if (n <= 0) { left = metaInt; return }
        val b = ByteArray(n * 16)
        var got = 0
        while (got < b.size) { val r = `in`.read(b, got, b.size - got); if (r < 0) break; got += r }
        val text = try { String(b, 0, got, Charsets.UTF_8) } catch (_: Exception) { "" }
        Regex("StreamTitle='(.*?)';").find(text)?.groupValues?.get(1)?.trim()?.let { t ->
            if (t.isNotEmpty() && !t.lowercase().startsWith("http")) onTitle(t)
        }
        left = metaInt
    }
    override fun read(): Int {
        if (left == 0) readMeta()
        val v = `in`.read()
        if (v >= 0) left--
        return v
    }
    override fun read(b: ByteArray, off: Int, len: Int): Int {
        if (left == 0) readMeta()
        val n = `in`.read(b, off, minOf(len, left))
        if (n > 0) left -= n
        return n
    }
    override fun markSupported() = false
}
