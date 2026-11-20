package com.unoki99.fangfang.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.buildAnnotatedString
import com.unoki99.fangfang.*
import com.unoki99.fangfang.engine.*

// A line of lyrics for the 歌詞 screens (the radio's and YouTube's): its words in their tone colours (華語's from the
// 華語 dictionary; 台語's worked out the way 轉換 does, with the tone changes), what clicking each opens, and the
// line's reading in tone colours too. (台語's words and readings had no colours before: only 華語's did.)

/** one word of a line: how it's shown, how many letters it has (for the time it's sung), what clicking it opens;
 *  台語 words with more than one reading: the readings to pick from (漢字 and reading), the one chosen, and pick(i) */
internal class LyricWord(val text: AnnotatedString, val letters: Int, val open: (() -> Unit)?,
                         val choices: List<Pair<String, AnnotatedString>> = emptyList(), val chosen: Int = 0,
                         val pick: ((Int) -> Unit)? = null)

/** the readings picked in a song's lyrics (台語): kept for that song (title and singer, or the YouTube video) and
 *  used wherever its lyrics show, like on the iPhone / iPad. version: a pick made (the lyrics drawn again) */
object LyricPicks {
    var songKey by mutableStateOf<String?>(null)
    var version by mutableIntStateOf(0)
    fun keyOf(title: String, artist: String) = (title + "|" + artist).lowercase().trim()
    /** 歌的語言 of the song whose lyrics show (null: the app's language) */
    var lang by mutableStateOf<Int?>(null)
}

/** 歌的語言: a song tagged with the language it's sung in. Its lyrics are read in that language (the words, their tone
 *  colours, the reading and its spelling) whatever language the app is on, like the iPhone / iPad's. Untagged: the
 *  app's language, as before */
object SongLangs {
    private var tags: HashMap<String, Int>? = null
    var version by mutableIntStateOf(0); private set
    private fun load(): HashMap<String, Int> = tags ?: HashMap<String, Int>().also { m ->
        try {
            @Suppress("UNCHECKED_CAST")
            (JReader(Prefs.songLanguages.value).any() as? Map<String, Any?>)?.forEach { (k, v) -> (v as? Number)?.let { m[k] = it.toInt() } }
        } catch (_: Exception) {}
        tags = m
    }
    fun get(key: String?): Int? = key?.let { load()[it] }
    fun set(key: String, lang: Int?) {
        val m = load()
        if (lang == null) m.remove(key) else m[key] = lang
        Prefs.songLanguages.value = JWriter.any(m)
        version++
    }
}

private var engineFor: Pair<Dict, ConvertEngine>? = null
/** 台語's converter, made once for the dictionary in use */
private fun twEngine(d: Dict): ConvertEngine {
    engineFor?.let { if (it.first === d) return it.second }
    return ConvertEngine(d, Prefs).also { engineFor = d to it }
}

private fun letters(s: String): Int {
    var n = 0; var i = 0
    while (i < s.length) { val cp = s.codePointAt(i); if (Character.isLetterOrDigit(cp)) n++; i += Character.charCount(cp) }
    return n
}

/** read the lyrics with the 華語 / 粵語 / 客語 dictionary (the app on it, and the song not tagged 台語); else as 台語
 *  (its dictionary is always there) */
private fun readAsZh(z: ZhDict?): Boolean = z != null && Store.isZh && (LyricPicks.lang ?: Store.lang) != 0

/** the line's words, in their tone colours when those are on */
internal fun lyricWords(line: String): List<LyricWord> = try {
    val z = Store.zh; val d = Store.dict
    if (d == null) Store.loadDict()
    if (readAsZh(z)) {
        z!!.convertPieces(line).map { p ->
            val k = if (p.tw != null) z.entryFor(p)?.k else null
            val t = z.sentenceHan(listOf(p), Prefs.zhPlace.value, T.glyph.argbInt()).annotated()
            LyricWord(t, letters(t.text), if (k != null) ({ UI.open(Sheet.ZhWord(k)) }) else null)
        }
    } else if (d != null) {
        val e = twEngine(d)
        e.songKey = LyricPicks.songKey
        val items = e.convert(line).items
        val toneSys = Prefs.toneSys.value; val place = Prefs.place.value; val glow = Prefs.toneGlow.value; val rom = Prefs.rom.value
        val tones = if (toneSys != 0) itemTones(d, items, place) else emptyMap()
        e.pieces(items, 0, rom, place).filter { it.text != "\n" }.map { p ->
            val i = p.item
            val k = if (i != null && i >= 0) d.keyOf(items[i].current) else null
            val tt = if (i != null && i >= 0) tones[i] else null
            val lead = p.text.takeWhile { it == ' ' }
            val t = p.text.drop(lead.length)
            val a = if (tt != null) buildAnnotatedString {
                append(lead); append(hanToneText(t, tt.second, toneSys, T.glyph.argbInt()).annotated(T.glyph, glow))
            } else AnnotatedString(p.text)
            // (several readings: picked here, and kept for this song)
            val ii = if (i != null && i >= 0) i else -1
            val item = items.getOrNull(ii)
            if (item != null && item.opts.size > 1 && LyricPicks.songKey != null) {
                val ch = item.opts.map { o -> (o.han ?: "") to e.wordPieces(o, 1, rom, place).let { ps -> AnnotatedString(ps.joinToString("") { x -> x.first }) } }
                LyricWord(a, letters(t), if (k != null) ({ UI.openWord(k) }) else null, ch, item.sel) { j ->
                    if (j in item.opts.indices) {
                        item.sel = j; item.likely = null
                        e.songKey = LyricPicks.songKey
                        e.remember(items, ii)
                        LyricPicks.version++
                    }
                }
            } else LyricWord(a, letters(t), if (k != null) ({ UI.openWord(k) }) else null)
        }
    } else emptyList()
} catch (_: Exception) { emptyList() }

/** the line's reading (華語: 拼音／注音; 台語: in the spelling chosen), in tone colours when they're on */
internal fun lyricReading(line: String): AnnotatedString? = try {
    val z = Store.zh; val d = Store.dict
    if (readAsZh(z)) z!!.sentence(z.convertPieces(line), Prefs.zhRom.value, Prefs.zhPlace.value).annotated()
    else if (d != null) {
        val e = twEngine(d)
        e.songKey = LyricPicks.songKey
        val items = e.convert(line).items
        val toneSys = Prefs.toneSys.value; val place = Prefs.place.value; val rom = Prefs.rom.value; val glow = Prefs.toneGlow.value
        val tones = if (toneSys != 0) itemTones(d, items, place) else emptyMap()
        buildAnnotatedString {
            for (p in e.pieces(items, 1, rom, place)) {
                if (p.text == "\n") continue
                val i = p.item
                val tt = if (i != null && i >= 0) tones[i] else null
                val lead = p.text.takeWhile { it == ' ' }
                append(lead)
                if (tt != null) append(d.toneText(tt.first, rom, place, tt.second, toneSys).annotated(T.greenInk, glow))
                else append(p.text.drop(lead.length))
            }
        }
    } else null
} catch (_: Exception) { null }
