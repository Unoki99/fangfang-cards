package com.unoki99.fangfang

import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.*
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

// 電台: radio in the languages of the app, to listen to while practising (the same as the iPhone app's).
// The stations come from Radio Browser (radio-browser.info), a free directory checked every day. A station is kept by
// its Radio Browser id and the name it was found by: when a stream stops working, the app asks Radio Browser for the
// station's address again, then searches for it by name, and only then falls back to the last address that worked.
// It keeps playing when the app is left (with the usual media notification), until it's stopped.
// (This file: the stations, Radio Browser, the formats and the lyrics, shared by the Android and Windows apps; the
// player itself is Radio.kt, one for each.)

/** a station in 我的電台 */
data class RadioStation(
    val id: String, val name: String, val lang: Int, val uuid: String? = null, val query: String? = null,
    val country: String? = null, val url: String? = null, val favicon: String? = null, val starter: Boolean = false,
    /** MP3, AAC, AAC+, HLS or 其他 (RadioFormat): from Radio Browser, or found the first time it played; null: not known yet */
    val format: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf("id" to id, "name" to name, "lang" to lang, "uuid" to uuid, "query" to query,
        "country" to country, "url" to url, "favicon" to favicon, "starter" to starter, "format" to format)
    companion object {
        fun from(m: Map<String, Any?>): RadioStation? {
            val id = m["id"] as? String ?: return null
            val name = m["name"] as? String ?: return null
            return RadioStation(id, name, (m["lang"] as? Number)?.toInt() ?: 0, m["uuid"] as? String, m["query"] as? String,
                m["country"] as? String, m["url"] as? String, m["favicon"] as? String, m["starter"] as? Boolean ?: false,
                m["format"] as? String)
        }
    }
}

/** a station as Radio Browser lists it */
class RBStation(val uuid: String, val name: String, val stream: String, val favicon: String, val tags: String, val language: String,
                val country: String, val codec: String, val bitrate: Int, val clicks: Int, val ok: Boolean,
                /** sent as HLS (a playlist of short pieces) */
                val hls: Boolean = false) {
    /** its format, as RadioFormat names them */
    val format: String? get() = RadioFormat.of(codec, hls)
}

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
            ((m["lastcheckok"] as? Number)?.toInt() ?: 1) == 1, ((m["hls"] as? Number)?.toInt() ?: 0) == 1)
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

/** the kinds of stream a station can send, for grouping 我的電台 by them: plain MP3 or AAC, AAC+ (HE-AAC, AAC made for
 *  low bitrates), HLS (a playlist of short pieces, often AAC) and the rest (Ogg Vorbis, Opus, FLAC) */
object RadioFormat {
    const val MP3 = "MP3"
    const val AAC = "AAC"
    const val AACP = "AAC+"
    const val HLS = "HLS"
    const val OTHER = "other"
    private val order = listOf(MP3, AAC, AACP, HLS, OTHER)

    /** from Radio Browser's codec name ("MP3", "AAC+", "OGG"…) and whether it's HLS; null: it doesn't say */
    fun of(codec: String?, hls: Boolean): String? {
        if (hls) return HLS
        val c = codec?.trim()?.uppercase() ?: return null
        return when {
            c.isEmpty() || c == "UNKNOWN" -> null
            c.contains("AAC+") || c.contains("AACP") || c.contains("HE-AAC") -> AACP
            c.contains("AAC") -> AAC
            c.contains("MP3") || c == "MPEG" -> MP3
            else -> OTHER
        }
    }

    /** from what the player found in the stream (its MIME type and codec string), or that it came as HLS */
    fun fromStream(mime: String?, codecs: String?, hls: Boolean): String? {
        if (hls) return HLS
        val m = mime?.lowercase() ?: return null
        val c = codecs?.lowercase() ?: ""
        return when {
            m.contains("mp4a") || m.contains("aac") -> if (c.contains("40.5") || c.contains("40.29")) AACP else AAC
            m.contains("mpeg") -> MP3
            m.contains("opus") || m.contains("vorbis") || m.contains("flac") || m.contains("ogg") -> OTHER
            else -> null
        }
    }

    /** the order the groups come in (not known yet last) */
    fun rank(f: String?): Int = order.indexOf(f).let { if (it < 0) order.size else it }

    /** a group's heading */
    fun title(f: String?): String = when (f) {
        MP3 -> "MP3"
        AAC -> "AAC"
        AACP -> "AAC+（HE-AAC）"
        HLS -> tr("HLS（一段一段送的串流）")
        OTHER -> tr("其他格式（Ogg、Opus、FLAC）")
        else -> tr("格式還不知道（播一次就知道）")
    }
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
