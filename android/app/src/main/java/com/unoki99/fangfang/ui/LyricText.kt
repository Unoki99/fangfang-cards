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
                         val pick: ((Int) -> Unit)? = null, val key: String? = null, val zh: Boolean = false)

/** where a word clicked in the lyrics opens: the app's sheet (null), or somewhere else (浮動歌詞: under its lines) */
internal val LocalLyricOpen = androidx.compose.runtime.staticCompositionLocalOf<((LyricWord) -> Unit)?> { null }

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
private fun readAsZh(z: ZhDict?): Boolean {
    if (z == null) return false
    // (the computer, the song tagged: its language decides, whatever the app is on. The 華語 dictionary kept loaded
    // in 台語 (for its 近義詞) is the app's own Store.zh, and was taken as "the app's, which is on 台語": the lyrics were
    // read as 台語 half the time)
    val tag = LyricPicks.lang
    if (EngineSettings.desktop && tag != null) return tag != 0
    return z !== Store.zh || (Store.isZh && (tag ?: Store.lang) != 0)
}

/** the dictionary that reads the lyrics: the song's language's (on the computer, whatever the app is on), else the
 *  app's; null: 台語 */
private fun lyricZh(): ZhDict? {
    val tag = LyricPicks.lang
    if (EngineSettings.desktop && tag != null) return if (tag == 0) null else LyricDicts.get(tag)
    return Store.zh
}

/** 歌的語言 on the computer: the dictionary of the song's language, read for the lyrics alone (the app's own stays as
 *  it is). One kept besides the app's. version (LyricPicks') bumped when it's read */
object LyricDicts {
    @Volatile private var held: ZhDict? = null
    @Volatile private var loading = -1
    fun get(lang: Int): ZhDict? {
        Store.zh?.let { if (it.lang == lang) return it }
        held?.let { if (it.lang == lang) return it }
        val name = listOf("zh", "zh", "yue", "hak", "ja", "sv", "en").getOrNull(lang) ?: return null
        if (loading != lang && DataFiles.has(name)) {
            loading = lang
            Thread {
                val d = try { DataFiles.reader(name)?.let { ZhDict(it, Prefs.hakAccent.value.coerceIn(0, 5)) } } catch (_: Throwable) { null }
                held = d ?: held
                loading = -1
                LyricPicks.version++
            }.apply { isDaemon = true }.start()
        }
        return null
    }
    /** the dictionary a word's key is of, when it's the lyrics' one and not the app's */
    fun forKey(k: String): ZhDict? {
        val kind = Lang.kind(k)
        if (Store.zh?.lang == kind) return null
        return held?.takeIf { it.lang == kind }
    }
}

/** (the computer) the song is tagged 華語, 粵語… and that dictionary is still being read: the line plain meanwhile, not
 *  read as 台語 */
private fun waitingForSongDict(): Boolean {
    val tag = LyricPicks.lang
    return EngineSettings.desktop && tag != null && tag != 0
}

/** the line's words, in their tone colours when those are on */
internal fun lyricWords(line: String): List<LyricWord> = try {
    val z = lyricZh(); val d = Store.dict
    if (d == null) Store.loadDict()
    if (readAsZh(z) && z!!.isSv) {
        // 瑞典語: each word in its morphemes' colours (tap it to open it)
        val colours = Prefs.toneSys.value != 0
        line.split(" ").filter { it.isNotEmpty() }.map { w ->
            val (lead, core, tail) = svSplitWord(w)
            val ms = if (core.isEmpty()) emptyList() else z.svMorphemes(core)
            val k = if (core.isEmpty()) null else z.svKey(core)
            val st = styled(lead, T.glyph.argbInt()) + (if (ms.isEmpty()) styled(core, T.glyph.argbInt()) else SvColors.styledOf(ms, T.glyph.argbInt(), colours)) +
                styled("$tail ", T.glyph.argbInt())
            val t = st.annotated()
            LyricWord(t, letters(t.text), if (k != null) ({ UI.open(Sheet.ZhWord(k)) }) else null, key = k, zh = true)
        }
    } else if (readAsZh(z)) {
        z!!.convertPieces(line).map { p ->
            val k = if (p.tw != null) z.entryFor(p)?.k else null
            val t = z.sentenceHan(listOf(p), Prefs.zhPlace.value, T.glyph.argbInt()).annotated()
            LyricWord(t, letters(t.text), if (k != null) ({ UI.open(Sheet.ZhWord(k)) }) else null, key = k, zh = true)
        }
    } else if (d != null && !waitingForSongDict()) {
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
                LyricWord(a, letters(t), if (k != null) ({ UI.openWord(k) }) else null, ch, item.sel, key = k, pick = { j ->
                    if (j in item.opts.indices) {
                        item.sel = j; item.likely = null
                        e.songKey = LyricPicks.songKey
                        e.remember(items, ii, line)
                        LyricPicks.version++
                    }
                })
            } else LyricWord(a, letters(t), if (k != null) ({ UI.openWord(k) }) else null, key = k)
        }
    } else emptyList()
} catch (_: Exception) { emptyList() }

/** the line's reading (華語: 拼音／注音; 台語: in the spelling chosen), in tone colours when they're on */
internal fun lyricReading(line: String): AnnotatedString? = try {
    val z = lyricZh(); val d = Store.dict
    if (readAsZh(z) && z!!.isSv) (if (Prefs.zhRom.value == 0) z.svSentence(line, true, T.greenInk.argbInt()).annotated() else null)
    else if (readAsZh(z)) z!!.sentence(z.convertPieces(line), Prefs.zhRom.value, Prefs.zhPlace.value).annotated()
    else if (d != null && !waitingForSongDict()) {
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


/** 歌詞 in 簡體 shown in 正體 (華語, 粵語, 客語; the app on 正體), as on the iPhone / iPad: the dictionary's words are
 *  正體, so the words are found and read too. keepSimplified: as the lyrics were written (the 簡 / 繁 button) */
object LyricsScript {
    var keepSimplified by mutableStateOf(false)
    private fun langNow() = LyricPicks.lang ?: Store.lang
    /** whether the lyrics are shown changed (only when they had 簡體 in them) */
    fun applies(): Boolean = langNow() in 1..3 && !Prefs.simplified.value
    fun shown(text: String): String = if (keepSimplified || !applies()) text else traditional(text)
    /** (lyrics that look 台語 are left as they are: 台語 writes 个 and 個 as two words) */
    fun traditional(text: String): String {
        if (looksTaiwanese(text)) return text
        val sb = StringBuilder()
        text.codePoints().forEach { sb.appendCodePoint(Simp.reverse(it) ?: it) }
        return sb.toString()
    }
    /** there's something to switch (the lyrics have 簡體 characters) */
    fun canSwitch(text: String): Boolean = applies() && traditional(text) != text

    /** words only 台語 writes (佇, 毋, 袂, 恁, 阮, 咧 …): three or more of them, the lyrics are 台語 */
    private val marks = "佇毋袂恁阮咧佮媠攏矣囝遮遐閣".toSet()
    fun looksTaiwanese(s: String): Boolean {
        var n = 0
        for (c in s) if (c in marks) { n++; if (n >= 3) return true }
        return false
    }
}
