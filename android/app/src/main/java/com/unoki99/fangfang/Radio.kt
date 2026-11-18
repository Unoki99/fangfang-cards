package com.unoki99.fangfang

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Metadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player as M3Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.extractor.metadata.icy.IcyInfo
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.*
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

// 電台's player (Android: ExoPlayer, playing on in the background with the media notification). The stations, Radio
// Browser, the formats and the lyrics are in RadioShared.kt, shared with the Windows app.

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
    private var player: ExoPlayer? = null
    private lateinit var ctx: Context

    fun init(c: Context) {
        ctx = c.applicationContext
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

    /** the player, made once (the media notification's service uses the same one) */
    fun player(c: Context): ExoPlayer {
        player?.let { return it }
        val p = ExoPlayer.Builder(c.applicationContext).build()
        p.volume = Prefs.radioVolume.value
        p.addListener(object : M3Player.Listener {
            override fun onMetadata(m: Metadata) {
                for (i in 0 until m.length()) {
                    val e = m.get(i)
                    val t = when (e) {
                        is IcyInfo -> e.title
                        is TextInformationFrame -> if (e.id == "TIT2") e.values.firstOrNull() else null
                        else -> null
                    }
                    if (!t.isNullOrBlank() && !t.lowercase().startsWith("http")) nowPlaying = t.trim()
                }
            }
            override fun onPlaybackStateChanged(s: Int) {
                if (s == M3Player.STATE_READY && current != null) state = State.PLAYING
            }
            override fun onPlayerError(error: PlaybackException) {
                if (state == State.PLAYING) { state = State.CONNECTING; current?.let { play(it) } }
            }
        })
        player = p
        return p
    }

    /** (電台 音量 changed, while playing) */
    fun radioVolumeChanged() { player?.volume = Prefs.radioVolume.value }

    fun toggle(s: RadioStation) { if (current?.id == s.id && state != State.IDLE && state != State.FAILED) stop() else play(s) }

    fun play(s: RadioStation) {
        job?.cancel()
        current = s; state = State.CONNECTING; nowPlaying = null
        // (the notification and playing on when the app is left)
        try { ctx.startService(Intent(ctx, RadioService::class.java)) } catch (_: Exception) {}
        job = scope.launch { connect(s) }
    }

    fun stop() {
        job?.cancel(); job = null
        player?.stop()
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

    /** the addresses to try, in order: the station as Radio Browser lists it now, then a search by its name, then
     *  the last address that worked */
    private suspend fun connect(s: RadioStation) {
        val tried = HashSet<String>()
        suspend fun attempt(u: String, found: RBStation?): Boolean {
            if (u.isEmpty() || !tried.add(u)) return false
            val stream = RadioDirectory.unwrap(u)
            if (!open(stream, s)) return false
            remember(s, u, found)
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
        player?.stop()
        state = State.FAILED
    }

    /** plays the address; true once sound is coming (false: it failed, or nothing came for 12 seconds) */
    private suspend fun open(address: String, s: RadioStation): Boolean {
        val p = player(ctx)
        p.setMediaItem(MediaItem.Builder().setUri(address)
            .setMediaMetadata(MediaMetadata.Builder().setTitle(s.name).setArtist(tr("方方詞卡 電台")).build()).build())
        p.prepare(); p.play()
        for (i in 0 until 120) {
            delay(100)
            if (p.playbackState == M3Player.STATE_READY) return true
            if (p.playerError != null) { p.stop(); return false }
        }
        p.stop()
        return false
    }

    private fun remember(s: RadioStation, url: String, found: RBStation?) {
        val i = stations.indexOfFirst { it.id == s.id }
        // (its format: what the player found in the stream, else what Radio Browser says)
        val p = player
        val heard = try {
            RadioFormat.fromStream(p?.audioFormat?.sampleMimeType, p?.audioFormat?.codecs,
                p?.currentManifest is androidx.media3.exoplayer.hls.HlsManifest || url.lowercase().contains(".m3u8"))
        } catch (_: Exception) { null }
        var t = s.copy(url = url, format = heard ?: found?.format ?: s.format)
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

/** keeps the radio playing when the app is left, with the usual media notification (play / pause) */
class RadioService : MediaSessionService() {
    private var session: MediaSession? = null
    override fun onCreate() {
        super.onCreate()
        Prefs.init(applicationContext)
        session = MediaSession.Builder(this, Radio.player(this)).build()
    }
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session
    override fun onTaskRemoved(rootIntent: Intent?) {
        val p = session?.player
        if (p == null || !p.playWhenReady || p.mediaItemCount == 0) stopSelf()
    }
    override fun onDestroy() {
        session?.release(); session = null
        super.onDestroy()
    }
}
