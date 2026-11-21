package com.unoki99.fangfang

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.unoki99.fangfang.engine.*
import java.io.File

// Lyrics with their times (LRC), the way the iPhone / iPad app writes them (LyricsEditor.swift's LRC and OwnLyrics),
// so the two read each other's files: "[01:23.45]words", a word's own time inside a line "<01:23.45>", and at the top
// [ti:] [ar:] [length:] [by:] and [ff-untimed:] (the lines given a time only so the file has one).

/** one line: its words (without word times), when it's sung (null: not timed yet), and when each of its pieces is
 *  sung (LRC.pieces; null: spread over the line by their length). Text "" is a break between lines (間奏). */
data class TimedLine(val text: String, val t: Double?, val words: List<Double>? = null)

object LRC {
    /** 83.45 → "[01:23.45]" */
    fun stamp(t: Double): String {
        val cs = Math.round(maxOf(0.0, t) * 100).toInt()
        return "[%02d:%02d.%02d]".format(cs / 6000, (cs / 100) % 60, cs % 100)
    }
    /** 83.45 → "<01:23.45>" */
    fun wordStamp(t: Double): String = "<" + stamp(t).drop(1).dropLast(1) + ">"
    /** "1:23.4" for showing */
    fun shown(t: Double): String {
        val ds = Math.round(maxOf(0.0, t) * 10).toInt()
        return "%d:%02d.%d".format(ds / 600, (ds / 10) % 60, ds % 10)
    }

    private fun isCJK(v: Int) = v in 0x3040..0x30FF || v in 0x3400..0x4DBF || v in 0x4E00..0x9FFF || v in 0xF900..0xFAFF ||
        v in 0x20000..0x3134F || v in 0xAC00..0xD7AF

    /** the pieces a line's word times go by: every 漢字 (or kana, hangul) its own, other words by the spaces;
     *  punctuation and spaces go with the piece before. Joined they're the line again. */
    fun pieces(text: String): List<String> {
        val out = ArrayList<String>()
        val cur = StringBuilder(); var letters = 0; var curCJK = false; var gap = false
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i); val ch = String(Character.toChars(cp)); i += Character.charCount(cp)
            if (!Character.isLetterOrDigit(cp)) {
                cur.append(ch)
                if (Character.isWhitespace(cp)) gap = true
                continue
            }
            val cjk = isCJK(cp)
            if (letters > 0 && (cjk || curCJK || gap)) { out.add(cur.toString()); cur.setLength(0); letters = 0 }
            cur.append(ch); letters++; curCJK = cjk; gap = false
        }
        if (cur.isNotEmpty()) { if (letters == 0 && out.isNotEmpty()) out[out.size - 1] = out.last() + cur else out.add(cur.toString()) }
        return out
    }
    private fun letters(s: String): Int { var n = 0; var i = 0; while (i < s.length) { val cp = s.codePointAt(i); if (Character.isLetterOrDigit(cp)) n++; i += Character.charCount(cp) }; return n }
    /** letters before each piece */
    fun pieceStarts(ps: List<String>): List<Int> { var acc = 0; return ps.map { p -> val a = acc; acc += letters(p); a } }

    /** the line's words with their word times in them (only when they were set) */
    fun withWords(l: TimedLine): String {
        val w = l.words ?: return l.text
        if (l.t == null) return l.text
        val ps = pieces(l.text)
        if (ps.size < 2 || ps.size != w.size) return l.text
        return ps.indices.joinToString("") { wordStamp(w[it]) + ps[it] }
    }

    /** the lines as an LRC file. Untimed lines get a time between their neighbours' (and are listed in [ff-untimed:]) */
    fun make(lines: List<TimedLine>, title: String, artist: String, length: Double?): String {
        val ls = lines.filter { !(it.text.isEmpty() && it.t == null) }.toMutableList()
        val guessed = ArrayList<Double>()
        var i = 0
        while (i < ls.size) {
            if (ls[i].t != null) { i++; continue }
            var j = i
            while (j < ls.size && ls[j].t == null) j++
            val before = if (i > 0) ls[i - 1].t ?: 0.0 else 0.0
            val after = if (j < ls.size) ls[j].t ?: (before + (j - i + 1) * 3.0) else before + (j - i + 1) * 3.0
            val step = (after - before) / (j - i + 1)
            for (k in i until j) {
                val t = Math.round((before + step * (k - i + 1)) * 100) / 100.0
                ls[k] = ls[k].copy(t = t); guessed.add(t)
            }
            i = j
        }
        val out = arrayListOf("[ti:$title]", "[ar:$artist]")
        if (length != null && length > 0) out.add("[length:%02d:%02d]".format(length.toInt() / 60, length.toInt() % 60))
        out.add("[by:方方詞卡]")
        if (guessed.isNotEmpty()) out.add("[ff-untimed:" + guessed.joinToString(",") { "%.2f".format(java.util.Locale.US, it) } + "]")
        for (l in ls) out.add(stamp(l.t ?: 0.0) + withWords(l))
        return out.joinToString("\n")
    }

    private val lineTag = Regex("\\[(\\d+):(\\d+(?:\\.\\d+)?)\\]")
    private val wordTag = Regex("<(\\d+):(\\d+(?:\\.\\d+)?)>")

    /** an LRC text → its lines with their times (and word times), breaks included, untimed ones untimed again */
    fun lines(lrc: String): List<TimedLine> {
        val out = ArrayList<TimedLine>()
        for (raw in lrc.lines()) {
            val times = lineTag.findAll(raw).map { it.groupValues[1].toInt() * 60 + it.groupValues[2].toDouble() }.toList()
            if (times.isEmpty()) continue
            val body = raw.replace(lineTag, "")
            // (word times: where in the line's letters each one is)
            val marks = ArrayList<Pair<Int, Double>>()
            val text = StringBuilder(); var at = 0; var k = 0
            for (m in wordTag.findAll(body)) {
                val before = body.substring(k, m.range.first); text.append(before); at += letters(before)
                marks.add(at to (m.groupValues[1].toInt() * 60 + m.groupValues[2].toDouble()))
                k = m.range.last + 1
            }
            text.append(body.substring(k))
            val clean = text.toString().trim()
            var words: List<Double>? = null
            if (times.size == 1 && marks.size >= 2) {
                val ps = pieces(clean)
                val ws = pieceStarts(ps).map { a -> marks.firstOrNull { it.first == a }?.second }
                if (ps.size >= 2 && ws.none { it == null }) words = ws.map { it!! }
            }
            for (t in times) out.add(TimedLine(clean, t, words))
        }
        out.sortBy { it.t ?: 0.0 }
        while (out.firstOrNull()?.text?.isEmpty() == true) out.removeAt(0)
        val u = Regex("\\[ff-untimed:([^\\]]*)\\]").find(lrc)
        if (u != null) {
            val gs = u.groupValues[1].split(",").mapNotNull { it.trim().toDoubleOrNull() }
            for (i in out.indices) { val t = out[i].t; if (t != null && gs.any { Math.abs(it - t) < 0.006 }) out[i] = out[i].copy(t = null) }
        }
        return out
    }

    /** typed text → lines (an empty line: a break; several in a row count once); times kept for lines that didn't change */
    fun linesFromText(text: String, old: List<TimedLine>): List<TimedLine> {
        val out = ArrayList<TimedLine>()
        for (raw in text.lines()) {
            val s = raw.trim()
            if (s.isEmpty() && (out.isEmpty() || out.last().text.isEmpty())) continue
            out.add(TimedLine(s, null))
        }
        for (i in out.indices) if (i < old.size && old[i].text == out[i].text) out[i] = out[i].copy(t = old[i].t, words = old[i].words)
        return out
    }

    /** a tag at the top: [ti:], [ar:], [length:] */
    fun tag(text: String, k: String): String? = Regex("\\[" + k + ":([^\\]]*)\\]").find(text)?.groupValues?.get(1)?.trim()
    fun length(text: String): Double? = tag(text, "length")?.split(":")?.mapNotNull { it.toDoubleOrNull() }?.takeIf { it.size == 2 }?.let { it[0] * 60 + it[1] }
}

/** lyrics of your own for one song. id: "yt-<the YouTube video>" (Windows); a number for the iPhone / iPad app's songs
 *  (the song in Apple's catalogue: kept, shown when the name matches, never changed here) */
data class OwnLyric(val id: String, val title: String, val artist: String, val duration: Double?, val lrc: String, val date: Long)

/** the songs' lyrics of your own: in a file of this device, and the backup folder's 歌詞 folder (one .lrc file a song,
 *  the same as the iPhone / iPad app's) */
object OwnLyrics {
    var version by mutableStateOf(0)
        private set
    private val items = HashMap<String, OwnLyric>()
    private val deleted = HashSet<String>()
    private var loaded = false
    private val file: File get() = File(Store.app.filesDir, "own-lyrics.json")

    @Suppress("UNCHECKED_CAST")
    private fun load() {
        if (loaded) return
        loaded = true
        try {
            val o = JReader(file.readText()).any() as? Map<String, Any?> ?: return
            for (x in (o["items"] as? List<Any?>) ?: emptyList()) {
                val m = x as? Map<String, Any?> ?: continue
                val id = m["id"] as? String ?: continue
                items[id] = OwnLyric(id, m["title"] as? String ?: "", m["artist"] as? String ?: "", (m["duration"] as? Number)?.toDouble(),
                    m["lrc"] as? String ?: "", (m["date"] as? Number)?.toLong() ?: 0L)
            }
            for (x in (o["deleted"] as? List<Any?>) ?: emptyList()) (x as? String)?.let { deleted.add(it) }
        } catch (_: Exception) {}
    }
    private fun write() {
        try {
            val all = items.values.map { mapOf("id" to it.id, "title" to it.title, "artist" to it.artist, "duration" to it.duration, "lrc" to it.lrc, "date" to it.date) }
            file.writeText(JWriter.any(mapOf("items" to all, "deleted" to deleted.toList())))
        } catch (_: Exception) {}
        version++
    }

    fun get(id: String): OwnLyric? { load(); return items[id] }
    /** the iPhone / iPad's lyrics of a song of the same name (and singer, when both have one) */
    fun byName(title: String, artist: String): OwnLyric? {
        load()
        fun n(s: String) = s.lowercase().replace(Regex("[\\s\\p{Punct}「」『』《》【】（）]"), "")
        val t = n(title); if (t.isEmpty()) return null
        return items.values.filter { !it.id.startsWith("yt-") }.firstOrNull { x ->
            val xt = n(x.title)
            xt.isNotEmpty() && (t.contains(xt) || xt.contains(t)) && (artist.isEmpty() || x.artist.isEmpty() || n(artist).contains(n(x.artist)) || n(x.artist).contains(n(artist)))
        }
    }
    fun set(x: OwnLyric) { load(); items[x.id] = x; deleted.remove(x.id); write() }
    fun remove(id: String) { load(); if (items.remove(id) != null) { deleted.add(id); write() } }

    /** "繁華夢 - 黃齡 [yt-abc123].lrc" */
    fun fileName(x: OwnLyric): String {
        fun clean(s: String) = s.replace(Regex("[/\\\\:*?\"<>|\\n\\r]"), " ").trim()
        return clean(x.title) + " - " + clean(x.artist) + " [" + x.id + "].lrc"
    }
    private fun idOf(name: String): String? {
        if (!name.endsWith(".lrc")) return null
        val a = name.lastIndexOf('['); val b = name.lastIndexOf(']')
        return if (a >= 0 && b > a) name.substring(a + 1, b) else null
    }

    /** (the backup's sync) the 歌詞 folder: lyrics newer there come in, ours go out, deleted ones go everywhere;
     *  how many came in. The same rules as the iPhone / iPad app's. The iPad's own songs (a number) are only read. */
    /** the 歌詞 folder last written to (where your lyrics are): null, no backup folder yet */
    var lastDir: File? = null
    fun sync(dir: File): Int {
        lastDir = dir
        load()
        dir.mkdirs()
        val files = HashMap<String, File>()
        val marks = HashMap<String, Long>()
        for (f in dir.listFiles() ?: emptyArray()) {
            val n = f.name
            if (n.endsWith(".deleted")) { marks[n.removeSuffix(".deleted")] = f.lastModified(); continue }
            idOf(n)?.let { files[it] = f }
        }
        var came = 0; var changed = false
        for (id in deleted) {
            files.remove(id)?.delete()
            try { File(dir, "$id.deleted").writeText("") } catch (_: Exception) {}
        }
        if (deleted.isNotEmpty()) { deleted.clear(); changed = true }
        for ((id, when_) in marks) { val x = items[id]; if (x != null && x.date < when_) { items.remove(id); changed = true; came++ } }
        for ((id, f) in files) {
            val mark = marks[id]
            if (mark != null && mark >= f.lastModified()) continue
            val text = try { f.readText() } catch (_: Exception) { continue }
            val x = items[id]
            if (x != null && (x.lrc == text || x.date >= f.lastModified() - 1000)) continue
            items[id] = OwnLyric(id, LRC.tag(text, "ti") ?: x?.title ?: "", LRC.tag(text, "ar") ?: x?.artist ?: "", LRC.length(text), text, f.lastModified())
            changed = true; came++
        }
        // ours out (only this device's own kind: the iPad's are its to write)
        for ((id, x) in items) {
            if (!id.startsWith("yt-")) continue
            val f = files[id]
            if (f != null) {
                val same = try { f.readText() == x.lrc } catch (_: Exception) { false }
                if (same || f.lastModified() > x.date + 1000) continue
                if (f.name != fileName(x)) f.delete()
            }
            val out = File(dir, fileName(x))
            try { out.writeText(x.lrc); out.setLastModified(x.date) } catch (_: Exception) {}
            File(dir, "$id.deleted").delete()
        }
        if (changed) write()
        return came
    }
}
