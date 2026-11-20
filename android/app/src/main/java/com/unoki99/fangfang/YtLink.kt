package com.unoki99.fangfang

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

// YouTube 歌詞 (the Windows program): a song played on YouTube or YouTube Music in the browser, its lyrics here.
// The browser add-on (Firefox, 連到方方詞卡（Windows）) says twice a second which song is playing and where in it, to
// this computer only (127.0.0.1; desktop/YtServer.kt listens); its answer is what was pressed here (jump, pause, play,
// speed). On Android nothing listens: `available` stays false and the screen isn't offered.

/** the song playing in the browser, as the add-on last said it */
data class YtSong(val id: String, val title: String, val artist: String, val t: Double, val d: Double,
                  val playing: Boolean, val rate: Double, val tab: String, val site: String, val at: Long)

object YtLink {
    /** the program listens (the Windows program; never on Android) */
    var available by mutableStateOf(false)
    var song by mutableStateOf<YtSong?>(null)
    private val cmds = ArrayList<Map<String, Any?>>()

    /** the add-on said something in the last few seconds */
    fun live(): Boolean = song?.let { (System.nanoTime() - it.at) / 1_000_000 < 3000 } ?: false

    /** where in the song it is now (from what was last said, moved on by the time since) */
    fun position(): Double {
        val s = song ?: return 0.0
        if (!s.playing) return s.t
        val sec = (System.nanoTime() - s.at) / 1e9
        return (s.t + sec.coerceAtMost(2.0) * s.rate).coerceAtMost(if (s.d > 0) s.d else Double.MAX_VALUE)
    }

    // (pressed here a moment ago: what the add-on says until the browser has done it is older, so not taken)
    @Volatile private var mineUntil = 0L
    private fun send(c: Map<String, Any?>) { synchronized(cmds) { cmds.add(c) }; mineUntil = System.nanoTime() + 1_200_000_000L }
    fun seek(t: Double) {
        send(mapOf("op" to "seek", "t" to t.coerceAtLeast(0.0)))
        song = song?.copy(t = t.coerceAtLeast(0.0), at = System.nanoTime())
    }
    fun play() { send(mapOf("op" to "play")); song = song?.copy(playing = true, at = System.nanoTime()) }
    fun pause() { val p = position(); send(mapOf("op" to "pause")); song = song?.copy(playing = false, t = p, at = System.nanoTime()) }
    fun rate(r: Double) { send(mapOf("op" to "rate", "r" to r)) }

    /** a message from the add-on → the answer (what was pressed here since, for the tab followed) */
    @Suppress("UNCHECKED_CAST")
    fun receive(body: String): String {
        val m = (try { JReader(body).any() } catch (_: Exception) { null }) as? Map<String, Any?> ?: return """{"cmds":[]}"""
        if (m["ping"] == true) return """{"cmds":[],"app":"fangfang"}"""
        fun d(k: String) = (m[k] as? Number)?.toDouble() ?: 0.0
        val now = YtSong(m["id"] as? String ?: "", (m["title"] as? String ?: "").trim(), (m["artist"] as? String ?: "").trim(),
            d("t"), d("d"), m["playing"] == true, (m["rate"] as? Number)?.toDouble() ?: 1.0, m["tab"] as? String ?: "",
            m["site"] as? String ?: "", System.nanoTime())
        val cur = song
        // (several YouTube tabs: the one followed, or one that's playing when the followed one isn't)
        val follow = cur == null || cur.tab == now.tab || !live() || (now.playing && !cur.playing)
        if (!follow) return """{"cmds":[]}"""
        song = if (cur != null && cur.tab == now.tab && cur.id == now.id && System.nanoTime() < mineUntil)
            now.copy(t = position(), playing = cur.playing, at = System.nanoTime()) else now
        val out = synchronized(cmds) { val l = ArrayList(cmds); cmds.clear(); l }
        return "{\"cmds\":" + JWriter.any(out) + "}"
    }
}

/** a song's lyrics with their times: LRCLIB's (id its number), or your own (own: the LRC as saved) */
class TimedLyrics(val id: Int, val track: String, val artist: String, val duration: Double, val lines: List<TimedLine>, val own: OwnLyric? = null)

object YtLyrics {
    @Suppress("UNCHECKED_CAST")
    private suspend fun search(q: String): List<TimedLyrics> = withContext(Dispatchers.IO) {
        try {
            val c = URL("https://lrclib.net/api/search?q=" + URLEncoder.encode(q, "UTF-8")).openConnection() as HttpURLConnection
            c.connectTimeout = 10000; c.readTimeout = 10000
            c.setRequestProperty("User-Agent", "FangfangCards/1.0")
            if (c.responseCode != 200) { c.disconnect(); return@withContext emptyList() }
            val t = c.inputStream.bufferedReader().use { it.readText() }; c.disconnect()
            ((JReader(t).any() as? List<Any?>) ?: emptyList()).mapNotNull { o ->
                val m = o as? Map<String, Any?> ?: return@mapNotNull null
                val synced = m["syncedLyrics"] as? String ?: ""
                val lines = if (synced.isNotBlank()) LRC.lines(synced)
                    // (only plain lyrics: there, untimed, to time in 歌詞對時)
                    else (m["plainLyrics"] as? String ?: "").let { if (it.isBlank()) emptyList() else LRC.linesFromText(it, emptyList()) }
                if (lines.isEmpty()) null
                else TimedLyrics((m["id"] as? Number)?.toInt() ?: 0, m["trackName"] as? String ?: "", m["artistName"] as? String ?: "",
                    (m["duration"] as? Number)?.toDouble() ?: 0.0, lines)
            }
        } catch (_: Exception) { emptyList() }
    }

    /** your own lyrics as lyrics to show */
    fun ofOwn(x: OwnLyric) = TimedLyrics(-1, x.title, x.artist, x.duration ?: 0.0, LRC.lines(x.lrc), x)

    /** a YouTube video's name (and channel) → what to search for: the name without "Official MV" and the like, then
     *  each part of it, with and without the singer */
    fun queries(title: String, artist: String, music: Boolean): List<String> {
        val singer = artist.replace(Regex("(?i)\\s*-\\s*topic$|vevo$|官方頻道|official( channel)?|頻道"), "").trim()
        var s = title
        for (junk in listOf("(?i)official\\s*(music\\s*)?(video|mv|audio|lyric(s)?\\s*video)", "(?i)\\b(mv|m/v|hd|4k|lyrics?|audio|live)\\b",
                "官方(完整版)?|完整版|動態歌詞|歌詞版|字幕版|高音質|MV", "(?i)\\bfeat\\.?.*$", "\\([^)]*\\)", "（[^）]*）"))
            s = s.replace(Regex(junk), " ")
        val parts = s.split(Regex("[-–—/|｜【】\\[\\]「」『』《》]")).map { it.trim().trim('"', '\'') }.filter { it.isNotEmpty() }
        val out = ArrayList<String>()
        if (music && singer.isNotEmpty()) out.add("$title $singer")
        val whole = parts.joinToString(" ")
        if (singer.isNotEmpty() && !whole.contains(singer)) out.add("$whole $singer")
        out.add(whole)
        for (p in parts.sortedByDescending { it.length }) { if (singer.isNotEmpty() && !p.contains(singer)) out.add("$p $singer"); out.add(p) }
        val seen = HashSet<String>()
        return out.map { it.replace(Regex("\\s+"), " ").trim() }.filter { it.isNotEmpty() && seen.add(it.lowercase()) }.take(8)
    }

    /** the song's lyrics: the first search that finds any; timed ones first, then those about as long as the video */
    suspend fun find(title: String, artist: String, duration: Double, music: Boolean): List<TimedLyrics> {
        for (q in queries(title, artist, music)) {
            val r = search(q)
            if (r.isEmpty()) continue
            return r.sortedWith(compareBy<TimedLyrics> { l -> if (l.lines.any { it.t != null }) 0 else 1 }
                .thenBy { if (duration > 0 && it.duration > 0) Math.abs(it.duration - duration) else 60.0 })
        }
        return emptyList()
    }
}
