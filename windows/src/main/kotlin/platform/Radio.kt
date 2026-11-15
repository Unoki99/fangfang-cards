package com.unoki99.fangfang

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.unoki99.fangfang.desktop.Mp3
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.*
import java.io.BufferedInputStream
import java.io.FilterInputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

// (Windows) the same radio as the Android app's Radio.kt (stations, Radio Browser, lyrics); only the player is
// Windows' own: mp3 streams through Java Sound, with the song's name the station sends in the stream (ICY), for 歌詞.
// (A station that only sends AAC or HLS can't be played here yet: the next address is tried, then it says it failed.)

// 電台: radio in the languages of the app, to listen to while practising (the same as the iPhone app's).
// The stations come from Radio Browser (radio-browser.info), a free directory checked every day. A station is kept by
// its Radio Browser id and the name it was found by: when a stream stops working, the app asks Radio Browser for the
// station's address again, then searches for it by name, and only then falls back to the last address that worked.
// It keeps playing when the app is left (with the usual media notification), until it's stopped.

/** a station in 我的電台 */
data class RadioStation(
    val id: String, val name: String, val lang: Int, val uuid: String? = null, val query: String? = null,
    val country: String? = null, val url: String? = null, val favicon: String? = null, val starter: Boolean = false,
) {
    fun toMap(): Map<String, Any?> = mapOf("id" to id, "name" to name, "lang" to lang, "uuid" to uuid, "query" to query,
        "country" to country, "url" to url, "favicon" to favicon, "starter" to starter)
    companion object {
        fun from(m: Map<String, Any?>): RadioStation? {
            val id = m["id"] as? String ?: return null
            val name = m["name"] as? String ?: return null
            return RadioStation(id, name, (m["lang"] as? Number)?.toInt() ?: 0, m["uuid"] as? String, m["query"] as? String,
                m["country"] as? String, m["url"] as? String, m["favicon"] as? String, m["starter"] as? Boolean ?: false)
        }
    }
}

/** a station as Radio Browser lists it */
class RBStation(val uuid: String, val name: String, val stream: String, val favicon: String, val tags: String, val language: String,
                val country: String, val codec: String, val bitrate: Int, val clicks: Int, val ok: Boolean)

object RadioDirectory {
    private val servers = listOf("https://de1.api.radio-browser.info", "https://de2.api.radio-browser.info",
        "https://nl1.api.radio-browser.info", "https://at1.api.radio-browser.info", "https://all.api.radio-browser.info")
    @Volatile private var good = 0

    private fun get(path: String): String {
        var last: Exception = Exception("no server")
        for (i in servers.indices) {
            val n = (good + i) % servers.size
            try {
                val c = URL(servers[n] + path).openConnection() as HttpURLConnection
                c.connectTimeout = 8000; c.readTimeout = 8000
                c.setRequestProperty("User-Agent", "FangfangCards/1.0")
                if (c.responseCode != 200) { c.disconnect(); throw Exception("HTTP ${c.responseCode}") }
                val t = c.inputStream.bufferedReader().use { it.readText() }
                c.disconnect()
                good = n
                return t
            } catch (e: Exception) { last = e }
        }
        throw last
    }

    @Suppress("UNCHECKED_CAST")
    private fun parse(t: String): List<RBStation> = ((JReader(t).any() as? List<Any?>) ?: emptyList()).mapNotNull { o ->
        val m = o as? Map<String, Any?> ?: return@mapNotNull null
        val url = m["url"] as? String ?: ""; val res = m["url_resolved"] as? String ?: ""
        RBStation(m["stationuuid"] as? String ?: return@mapNotNull null, (m["name"] as? String ?: "").trim(), res.ifEmpty { url },
            m["favicon"] as? String ?: "", m["tags"] as? String ?: "", m["language"] as? String ?: "", m["countrycode"] as? String ?: "",
            m["codec"] as? String ?: "", (m["bitrate"] as? Number)?.toInt() ?: 0, (m["clickcount"] as? Number)?.toInt() ?: 0,
            ((m["lastcheckok"] as? Number)?.toInt() ?: 1) == 1)
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    /** search by name, language (Radio Browser's English name, e.g. "cantonese") and/or country (e.g. "TW") */
    suspend fun search(name: String? = null, language: String? = null, country: String? = null, limit: Int = 40): List<RBStation> = withContext(Dispatchers.IO) {
        var q = "hidebroken=true&order=clickcount&reverse=true&limit=$limit"
        if (!name.isNullOrEmpty()) q += "&name=" + enc(name)
        if (!language.isNullOrEmpty()) q += "&language=" + enc(language)
        if (!country.isNullOrEmpty()) q += "&countrycode=" + enc(country)
        val seen = HashSet<String>()
        // (one station is often listed more than once: the most played one is kept)
        parse(get("/json/stations/search?$q")).filter { it.stream.isNotEmpty() && seen.add(it.name.lowercase() + "|" + it.stream) }
    }

    suspend fun station(uuid: String): RBStation? = withContext(Dispatchers.IO) { try { parse(get("/json/stations/byuuid/$uuid")).firstOrNull() } catch (_: Exception) { null } }

    /** tells Radio Browser the station was played (its list of popular stations is made from these) */
    fun clicked(uuid: String) { CoroutineScope(Dispatchers.IO).launch { try { get("/json/url/$uuid") } catch (_: Exception) {} } }

    /** a playlist address (.pls / .m3u): the first stream in it */
    suspend fun unwrap(s: String): String = withContext(Dispatchers.IO) {
        val low = s.lowercase()
        if (!(low.endsWith(".pls") || low.endsWith(".m3u")) || !low.startsWith("http")) return@withContext s
        try {
            val t = URL(s).readText()
            for (line0 in t.lines()) {
                var l = line0.trim()
                if (l.lowercase().startsWith("file") && l.contains("=")) l = l.substringAfter("=")
                if (l.startsWith("http")) return@withContext l
            }
        } catch (_: Exception) {}
        s
    }
}

/** the words to search Radio Browser with, for each language of the app */
object RadioLang {
    val languages = listOf(listOf("taiwanese", "hokkien", "min nan", "台語"), listOf("mandarin", "chinese", "華語", "國語"),
        listOf("cantonese", "粵語", "廣東話"), listOf("hakka", "客家", "客語"), listOf("japanese"))
    val countries = listOf(listOf("TW"), listOf("TW", "CN"), listOf("HK", "MO"), listOf("TW"), listOf("JP"))
    /** the stations a language starts with: found by name in Radio Browser the first time they're played */
    val starters = listOf(
        Triple(0, "國立教育廣播電台", "教育廣播" to "TW"), Triple(0, "寶島聯播網", "寶島" to "TW"), Triple(0, "Rti 中央廣播電臺", "Rti" to "TW"),
        Triple(1, "飛碟電台 UFO", "飛碟" to "TW"), Triple(1, "Hit FM", "Hit FM" to "TW"), Triple(1, "中廣流行網 i like radio", "中廣" to "TW"),
        Triple(1, "中國之聲", "中国之声" to "CN"),
        Triple(2, "香港電台第一台", "RTHK Radio 1" to "HK"), Triple(2, "香港電台第二台", "RTHK Radio 2" to "HK"), Triple(2, "商業電台 叱咤903", "903" to "HK"),
        Triple(3, "講客廣播電台", "講客" to "TW"), Triple(3, "寶島客家廣播電台", "客家" to "TW"),
        Triple(4, "NHK ラジオ第1", "NHK" to "JP"), Triple(4, "J-WAVE", "J-WAVE" to "JP"),
    )
}

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
        stations.add(RadioStation(java.util.UUID.randomUUID().toString(), rb.name, lang, rb.uuid, rb.name, rb.country.ifEmpty { null }, rb.stream, rb.favicon))
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

    /** (the volume set in 設定 → 聲音, while playing) */
    fun volumeChanged() { playing?.volume = Prefs.volume.value }

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

    /** plays the address; true once sound is coming (false: it failed, or nothing came for 12 seconds) */
    private suspend fun open(address: String): Boolean {
        halt()
        val c = withContext(Dispatchers.IO) {
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
                // (AAC and HLS: not playable here yet)
                if (type.contains("aac") || type.contains("mpegurl") || type.contains("mp4") || address.lowercase().contains(".m3u8")) {
                    c.disconnect(); return@withContext null
                }
                c
            } catch (_: Exception) { null }
        } ?: return false
        conn = c
        val metaInt = c.getHeaderFieldInt("icy-metaint", 0)
        val raw = BufferedInputStream(c.inputStream, 1 shl 16)
        val input: InputStream = if (metaInt > 0) Icy(raw, metaInt) { t -> scope.launch { nowPlaying = t } } else raw
        var failed = false
        val p = Mp3.play(BufferedInputStream(input, 1 shl 17), Prefs.volume.value, onError = { failed = true })
        playing = p
        for (i in 0 until 120) {
            delay(100)
            if (p.sounding) return true
            if (failed || !p.running) break
        }
        halt()
        return false
    }

    private fun remember(s: RadioStation, url: String, found: RBStation?) {
        val i = stations.indexOfFirst { it.id == s.id }
        var t = s.copy(url = url)
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

// MARK: - 歌詞: the playing song's lyrics from LRCLIB (lrclib.net, a free lyrics database); only shown, never kept

class LyricHit(val id: Int, val track: String, val artist: String, val text: String)

object LyricsSource {
    @Suppress("UNCHECKED_CAST")
    suspend fun search(q: String): List<LyricHit> = withContext(Dispatchers.IO) {
        val c = URL("https://lrclib.net/api/search?q=" + URLEncoder.encode(q, "UTF-8")).openConnection() as HttpURLConnection
        c.connectTimeout = 10000; c.readTimeout = 10000
        c.setRequestProperty("User-Agent", "FangfangCards/1.0")
        if (c.responseCode != 200) { c.disconnect(); return@withContext emptyList() }
        val t = c.inputStream.bufferedReader().use { it.readText() }; c.disconnect()
        ((JReader(t).any() as? List<Any?>) ?: emptyList()).mapNotNull { o ->
            val m = o as? Map<String, Any?> ?: return@mapNotNull null
            if (m["instrumental"] == true) return@mapNotNull null
            val plain = (m["plainLyrics"] as? String)?.trim().orEmpty()
            val text = plain.ifEmpty {
                (m["syncedLyrics"] as? String).orEmpty().lines().joinToString("\n") { it.replace(Regex("^(\\[[0-9:.]+\\]\\s*)+"), "") }.trim()
            }
            if (text.isEmpty()) null
            else LyricHit((m["id"] as? Number)?.toInt() ?: 0, m["trackName"] as? String ?: "", m["artistName"] as? String ?: "", text)
        }
    }

    /** what a station says is playing → what to search for: the whole of it, then each part on its own */
    fun queries(playing: String): List<String> {
        var s = playing
        for (junk in listOf("\\([^)]*\\)", "（[^）]*）", "\\[[^\\]]*\\]", "【[^】]*】", "(?i)\\b(now playing|on air|live)\\b:?"))
            s = s.replace(Regex(junk), " ")
        val parts = s.split(Regex("[-–—/|]")).map { it.trim().trim('"', '\'', '「', '」', '『', '』', '《', '》') }.filter { it.isNotEmpty() }
        val out = ArrayList<String>()
        out.add(parts.joinToString(" "))
        if (parts.size > 1) out.addAll(parts.sortedByDescending { it.length })
        val seen = HashSet<String>()
        return out.filter { it.isNotEmpty() && seen.add(it.lowercase()) }
    }

    /** songs for what's playing: the first search that finds any */
    suspend fun find(playing: String): List<LyricHit> {
        for (q in queries(playing)) {
            val r = try { search(q) } catch (_: Exception) { emptyList() }
            if (r.isNotEmpty()) return r
        }
        return emptyList()
    }
}
