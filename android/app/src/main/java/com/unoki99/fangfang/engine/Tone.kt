package com.unoki99.fangfang.engine

// 聲調顏色: with the 聲調 button on, every syllable (漢字, 羅馬字, 方音) is coloured by the tone it is
// actually said in, after tone sandhi.
//
// Every syllable takes its sandhi tone, except:
//  - the last syllable before punctuation or at the end (the end of a tone group)
//  - the last syllable of a noun (名詞, from the word's main meaning)
//  - the last syllable of a 時間詞
//  - the last syllable of a verb that ends with a noun (食飯: 飯 is a noun)
//  - the syllable before "--"
// Before 仔 a syllable takes its own change: 2, 3 → 1; 1, 5, 7, 8 and 4 ending in h → 7; 4 ending in p/t/k → 8.
// A syllable joined to the next one with a single "-" always changes, and a word listed as both 名詞 and 量詞
// right after a 數詞 or 代詞 is a 量詞 there (it changes too). Syllables after "--" are light: grey.
// Sandhi follows the 腔口: 通行 and the 漳 / 混合 places 2→1, 5→7, 8→4; the 泉 places 2→5, 5→3, 8→3. Tone 6 → 3.

/** the settings the engine reads while drawing (kept in step with 設定 by the app) */
object EngineSettings {
    /** 0 = off, 7 = 七聲, 5 = 五聲 */
    @Volatile var toneSystem = 0
    /** the tone marks show the tone after sandhi too */
    @Volatile var toneMarks = true
    /** 粵語 shown (Store) */
    @Volatile var yue = false
    /** 華語 or 粵語 shown (Store) */
    @Volatile var zhShown = false
    /** 設定 → 字形: 簡體字 */
    @Volatile var simplified = false
    // the theme's inks the engine colours with
    @Volatile var guessInk = 0xFFFF7A6E.toInt()
    @Volatile var swapInk = 0xFFFF9FD2.toInt()
}

object ToneColors {
    val red = 0xFFFF6B6B.toInt(); val purple = 0xFFC39BFF.toInt(); val blue = 0xFF6EAAFF.toInt()
    val orange = 0xFFFFA94D.toInt(); val green = 0xFF6FDC7F.toInt(); val yellow = 0xFFFFE066.toInt()
    val pink = 0xFFFF8CC6.toInt(); val light = 0xFF8E8E93.toInt()
    val teal = 0xFF4FD8C4.toInt()

    // MARK: colours you pick (設定 → 顏色與外觀 → 選聲調顏色)

    /** the tones that can have a colour of their own: 台語 1–8 and the light tone (0); 華語 1–4 and 輕聲 (0) */
    val twTones = listOf(1, 2, 3, 4, 5, 6, 7, 8, 0)
    val zhTones = listOf(1, 2, 3, 4, 0)
    val twStandard = mapOf(1 to red, 2 to purple, 3 to blue, 4 to orange, 5 to green, 6 to teal, 7 to yellow, 8 to pink, 0 to light)
    /** 華語: 1 red, 2 green (like 台語 5), 3 blue, 4 purple (like 台語 2), 輕聲 grey */
    val zhStandard = mapOf(1 to red, 2 to green, 3 to blue, 4 to purple, 0 to light)
    /** 粵語 1–6: 1 high level red, 2 high rising green, 3 mid level yellow, 4 low falling blue, 5 low rising purple,
     *  6 low level teal */
    val yueTones = listOf(1, 2, 3, 4, 5, 6)
    val yueStandard = mapOf(1 to red, 2 to green, 3 to yellow, 4 to blue, 5 to purple, 6 to teal)
    /** the tones of a set of colours: 0 台語, 1 華語, 2 粵語 */
    fun tones(set: Int) = when (set) { 2 -> yueTones; 1 -> zhTones; else -> twTones }
    /** the balls to pick from: one column per colour, in rainbow order, light at the top and dark at the bottom
     *  (the middle row is the standard colour) */
    val palette: List<Pair<String, List<Int>>> = listOf(
        "粉紅" to listOf(0xffcbe5, 0xffacd6, 0xff8cc6, 0xc76d9a, 0x945173),
        "紅" to listOf(0xffbcbc, 0xff9494, 0xff6b6b, 0xc75353, 0x943e3e),
        "橘" to listOf(0xffd8af, 0xffc17f, 0xffa94d, 0xc7843c, 0x94622d),
        "黃" to listOf(0xfff1ba, 0xffe991, 0xffe066, 0xc7af50, 0x94823b),
        "綠" to listOf(0xbeefc5, 0x97e6a3, 0x6fdc7f, 0x57ac63, 0x40804a),
        "青" to listOf(0xb0ede4, 0x80e3d5, 0x4fd8c4, 0x3ea899, 0x2e7d72),
        "藍" to listOf(0xbed9ff, 0x97c2ff, 0x6eaaff, 0x5685c7, 0x406394),
        "紫" to listOf(0xe4d2ff, 0xd4b7ff, 0xc39bff, 0x9879c7, 0x715a94),
        "灰" to listOf(0xd1d1d6, 0xaeaeb2, 0x8e8e93, 0x636366, 0x48484a),
    ).map { (n, l) -> n to l.map { (0xFF000000.toInt()) or it } }

    private val tw = HashMap<Int, Int>()
    private val zh = HashMap<Int, Int>()
    private val yue = HashMap<Int, Int>()
    /** changes when a colour is picked (for things that cache coloured text) */
    var version = 0; private set

    /** "1:ff6b6b,2:c39bff,…" → the picked colours */
    fun load(twS: String, zhS: String, yueS: String = "") {
        fun read(s: String, into: HashMap<Int, Int>) {
            into.clear()
            for (part in s.split(',')) {
                val kv = part.split(':')
                if (kv.size != 2) continue
                val t = kv[0].toIntOrNull() ?: continue
                val v = kv[1].toLongOrNull(16) ?: continue
                into[t] = (0xFF000000.toInt()) or (v.toInt() and 0xFFFFFF)
            }
        }
        read(twS, tw); read(zhS, zh); read(yueS, yue)
        version++
    }
    fun encode(m: Map<Int, Int>): String = m.entries.joinToString(",") { "${it.key}:" + String.format("%06x", it.value and 0xFFFFFF) }
    fun picked(zhSide: Boolean): Map<Int, Int> = HashMap(if (zhSide) zh else tw)
    fun picked(set: Int): Map<Int, Int> = HashMap(when (set) { 2 -> yue; 1 -> zh; else -> tw })
    /** a short text of all the colours (so the widgets know when they change) */
    val signature: String get() = encode(tw) + "|" + encode(zh) + "|" + encode(yue)

    fun twColor(t: Int): Int = tw[t] ?: twStandard[t] ?: light
    fun zhColor(t: Int): Int = zh[t] ?: zhStandard[t] ?: light
    fun yueColor(t: Int): Int = yue[t] ?: yueStandard[t] ?: light
    fun colorOf(set: Int, t: Int): Int = when (set) { 2 -> yueColor(t); 1 -> zhColor(t); else -> twColor(t) }

    /** the colour of a realized tone (0 = light tone); null = leave the text colour as it is */
    fun color(t: Int, sys: Int): Int? {
        if (t == 0) return twColor(0)
        if (sys == 5) return when (t) {
            1, 8 -> twColor(1); 3, 4 -> twColor(3); 2, 5, 6, 7 -> twColor(t); else -> null
        }
        return if (t in 1..8) twColor(t) else null
    }

    val all: List<Int> get() = listOf(1, 2, 3, 4, 5, 6, 7, 8).map { twColor(it) }
}

/** one syllable while working out the tones of a stretch of text */
class ToneUnit(
    var code: String,
    var light: Boolean = false,
    var beforeLight: Boolean = false,
    var keep: Boolean = false,
    var phraseEnd: Boolean = false,
    var beforeA: Boolean = false,
)

class ExampleTones(val han: String, val tpl: String, val tones: List<Int>)

private class HeadIndex { var map: Map<String, Pair<String, String>>? = null }
private val headIndices = java.util.WeakHashMap<Dict, HeadIndex>()

/** the tone written in a syllable code, and whether a checked syllable ends in h (not p / t / k) */
fun Dict.toneOf(code: String): Pair<Int, Boolean> {
    val last = code.lastOrNull() ?: return Pair(0, false)
    if (last !in '0'..'9') return Pair(0, false)
    val t = last - '0'
    val body = code.dropLast(1)
    val hasVowel = body.any { "iuaoøeIUɨəɵ".contains(it) }
    val stop = hasVowel && (body.lastOrNull()?.let { "BDG".contains(it) } ?: false)
    return Pair(t, !stop)
}

/** the syllable written in the tone it's said in (when that spelling exists) */
fun Dict.sandhiCode(code: String, tone: Int): String {
    val (t, h) = toneOf(code)
    if (tone <= 0 || t == tone) return code
    if ((t == 4 || t == 8) && !h && !(tone == 4 || tone == 8)) return code
    val n = code.dropLast(1) + tone.toString()
    return if (isCode(n)) n else code
}

fun Dict.quanSandhi(place: Int) = place >= 0 && place < raw.places.size && raw.places[place].contains("泉")

fun Dict.sandhiTone(code: String, place: Int): Int {
    val (t, h) = toneOf(code)
    val quan = quanSandhi(place)
    return when (t) {
        1 -> 7
        2 -> if (quan) 5 else 1
        3 -> 2
        5 -> if (quan) 3 else 7
        7, 6 -> 3
        4 -> if (h) 2 else 8
        8 -> if (h) 3 else (if (quan) 3 else 4)
        else -> t
    }
}

fun Dict.aSandhiTone(code: String): Int {
    val (t, h) = toneOf(code)
    return when (t) {
        2, 3 -> 1
        1, 5, 6, 7, 8 -> 7
        4 -> if (h) 7 else 8
        else -> t
    }
}

fun Dict.realizedTones(units: List<ToneUnit>, place: Int): List<Int> = units.map { u ->
    when {
        u.light -> 0
        u.beforeA && !u.beforeLight -> aSandhiTone(u.code)
        u.keep || u.phraseEnd || u.beforeLight -> toneOf(u.code).first
        else -> sandhiTone(u.code, place)
    }
}

/** a word used as a 量詞 here, so its tone changes */
fun Dict.classifierHere(key: String?, prev: String?, next: String? = null): Boolean {
    if (key == null || prev == null) return false
    val pos = raw.pos[key] ?: return false
    if (!pos.contains("名詞")) return false
    val pp = raw.pos[prev] ?: return false
    if (pos.contains("量詞") && (pp.contains("數詞") || pp.contains("代詞"))) return true
    if (pp.contains("代詞") && Dict.codesOf(key).split(' ').size == 1 && next != null) {
        val np = raw.pos[next]
        if (np != null && np.contains("名詞")) return true
    }
    return false
}

/** nouns, 時間詞 and verbs ending in a noun keep the tone of their last syllable */
fun Dict.keepsLastTone(key: String?, prev: String? = null, next: String? = null, sense: String? = null): Boolean {
    if (key == null) return false
    val pos = raw.pos[key] ?: return false
    if (classifierHere(key, prev, next)) return false
    var main = pos.split("|")[0]
    if (!sense.isNullOrEmpty()) {
        main = sense
    } else {
        if (pos.contains("時間詞")) return true
        // a one-syllable word that is both a 名詞 and a 動詞 (相)
        if (main.contains("名詞") && pos.contains("動詞") && !Dict.codesOf(key).contains(" ")) {
            val pp = prev?.let { raw.pos[it] } ?: ""
            val nounHere = pp.contains("代詞") || pp.contains("數詞") || pp.contains("量詞")
            if (!nounHere) main = "動詞"
        }
    }
    if (main.contains("時間詞")) return true
    if (main.contains("名詞")) return true
    if (main.contains("動詞") && !Dict.notVerbWithNoun.contains(key)) {
        val hs = Dict.hanOf(key).cps(); val cs = Dict.codesOf(key).split(' ')
        if (hs.size != cs.size || hs.size <= 1) return false
        for (L in 1 until hs.size) {
            val k = hs.takeLast(L).joinToString("") + "\t" + cs.takeLast(L).joinToString(" ")
            val p = raw.pos[k]
            if (p != null && baseKeys.contains(k) && p.split("|")[0].contains("名詞")) return true
        }
    }
    return false
}

fun Dict.toneUnits(tokens: List<String>, key: String?, prev: String? = null, next: String? = null): MutableList<ToneUnit> {
    val out = ArrayList<ToneUnit>()
    var lightNext = false
    for (t in tokens) {
        val c = if (t.startsWith("^")) t.drop(1) else t
        if (isCode(c)) out.add(ToneUnit(c, light = lightNext))
        else if (t == "--") { out.lastOrNull()?.beforeLight = true; lightNext = true }
        else if (t == "_") lightNext = false
    }
    if (keepsLastTone(key, prev, next) && out.isNotEmpty()) out.last().keep = true
    if (key != null) {
        val hs = Dict.hanOf(key).cps()
        if (hs.size == out.size) for (i in 0 until out.size - 1) if (hs[i + 1] == "仔") out[i].beforeA = true
    }
    return out
}

fun Dict.wordTones(key: String, place: Int): List<Int> {
    val u = toneUnits(tokensFor(key, place), key)
    if (u.isNotEmpty()) u.last().phraseEnd = true
    return realizedTones(u, place)
}

private fun cap1(s: String): String = if (s.isEmpty()) s else {
    val n = Character.charCount(s.codePointAt(0))
    s.substring(0, n).uppercase() + s.substring(n)
}

/** a reading drawn syllable by syllable in its tone colours (same text as render) */
fun Dict.toneText(tokens: List<String>, sys: Int, place: Int, tones: List<Int>, system: Int): Styled {
    val b = StyledBuilder()
    var prevCode = false; var n = 0
    for (t in tokens) {
        val cap = t.startsWith("^"); val c = if (cap) t.drop(1) else t
        if (isCode(c)) {
            if (sys != 3 && prevCode) b.add("-")
            val shown = if (EngineSettings.toneMarks && n < tones.size) sandhiCode(c, tones[n]) else c
            var s = syl(shown, sys, place)
            if (cap && sys != 3) s = cap1(s)
            b.add(s, if (n < tones.size) ToneColors.color(tones[n], system) else null)
            n++; prevCode = true
        } else if (t == "--") { if (sys != 3) b.add("--"); prevCode = false }
        else if (t == "_") { b.add(" "); prevCode = false }
        else if (t.startsWith("~")) { b.add(t.drop(1)); prevCode = false }
        else { b.add(t); prevCode = false }
    }
    return b.build()
}

/** 漢字 coloured one character per syllable (characters that aren't 漢字 keep the base colour) */
fun hanToneText(han: String, tones: List<Int>, system: Int, base: Int? = null): Styled {
    val b = StyledBuilder()
    var n = 0
    for (ch in han.cps()) {
        if (ConvertEngine.isHan(ch.firstCp())) {
            val col = if (n < tones.size) ToneColors.color(tones[n], system) else null
            b.add(ch, col ?: base)
            n++
        } else b.add(ch, base)
    }
    return b.build()
}

fun Dict.wordToneText(key: String, sys: Int, place: Int, system: Int): Styled =
    toneText(tokensFor(key, place), sys, place, wordTones(key, place), system)

fun Dict.wordHanToneText(key: String, place: Int, system: Int, base: Int? = null): Styled =
    hanToneText(Dict.hanOf(key), wordTones(key, place), system, base)

/** the entry an example sentence is listed under, and the word class of that meaning */
fun Dict.exampleHead(han: String, tpl: String): Pair<String, String>? {
    val idx = synchronized(headIndices) { headIndices.getOrPut(this) { HeadIndex() } }
    synchronized(idx) {
        if (idx.map == null) {
            val m = HashMap<String, Pair<String, String>>()
            for ((entry, senses) in raw.ex) {
                val pos = (raw.pos[entry] ?: "").split("|")
                for ((i, exs) in senses.withIndex()) {
                    val p = if (i < pos.size) pos[i] else ""
                    for (e in exs) if (e.size > 1) m[e[0] + "\u0001" + e[1]] = Pair(entry, p)
                }
            }
            idx.map = m
        }
        return idx.map?.get(han + "\u0001" + tpl)
    }
}

private val punctChars: (Int) -> Boolean = { cp ->
    val t = Character.getType(cp).toByte()
    t == Character.CONNECTOR_PUNCTUATION || t == Character.DASH_PUNCTUATION || t == Character.START_PUNCTUATION ||
        t == Character.END_PUNCTUATION || t == Character.INITIAL_QUOTE_PUNCTUATION || t == Character.FINAL_QUOTE_PUNCTUATION ||
        t == Character.OTHER_PUNCTUATION
}

/** an example as shown for the place, with the tone of every syllable */
fun Dict.exampleTones(han: String, tpl: String, place: Int, zh: String?): ExampleTones {
    val head = exampleHead(han, tpl)
    var h = han; var t = tpl
    if (place >= 0) {
        val loc = localizedExample(han, tpl, place, zh)
        h = loc.han
        t = dialectTemplate(loc.han, loc.tpl, place)
    }
    val codes = ArrayList<String>(); val seps = ArrayList<String>()
    var i = 0; var prevEnd = 0
    while (true) {
        val open = t.indexOf('{', i); if (open < 0) break
        val close = t.indexOf('}', open); if (close < 0) break
        var c = t.substring(open + 1, close)
        if (c.startsWith("^")) c = c.drop(1)
        if (c.startsWith("?") || c.startsWith("!")) c = c.drop(1)
        codes.add(c); seps.add(t.substring(prevEnd, open))
        prevEnd = close + 1; i = prevEnd
    }
    val tail = t.substring(prevEnd)
    if (codes.isEmpty()) return ExampleTones(h, t, emptyList())
    val clean = t.replace("{?", "{").replace("{!", "{").replace("{^?", "{^").replace("{^!", "{^")
    val keepAt = HashSet<Int>()
    var n = 0
    class W(val key: String?, val count: Int, val afterPunct: Boolean)
    val words = ArrayList<W>()
    var sawPunct = false
    for (p in exampleWords(h, clean)) {
        val count = p.first.cps().count { ConvertEngine.isHan(it.firstCp()) }
        if (count == 0) {
            if (p.first.codePoints().anyMatch(punctChars)) sawPunct = true
            continue
        }
        words.add(W(p.second, count, sawPunct)); sawPunct = false
    }
    for ((w, word) in words.withIndex()) {
        val prevKey = if (w > 0 && !word.afterPunct) words[w - 1].key else null
        val nextKey = if (w + 1 < words.size && !words[w + 1].afterPunct) words[w + 1].key else null
        val sense = if (word.key != null && word.key == head?.first) head.second else null
        if (keepsLastTone(word.key, prevKey, nextKey, sense)) keepAt.add(n + word.count - 1)
        n += word.count
    }
    val hanChars = h.cps().filter { ConvertEngine.isHan(it.firstCp()) }
    val units = ArrayList<ToneUnit>()
    for ((j, c) in codes.withIndex()) {
        val u = ToneUnit(c)
        val sep = seps[j]
        u.light = sep == "--" || (sep == "-" && (units.lastOrNull()?.light ?: false))
        val next = if (j + 1 < codes.size) seps[j + 1] else tail
        u.beforeLight = next == "--"
        u.phraseEnd = j + 1 == codes.size || next.any { !" -".contains(it) }
        u.keep = keepAt.contains(j) && next != "-"
        u.beforeA = j + 1 < hanChars.size && hanChars[j + 1] == "仔"
        units.add(u)
    }
    return ExampleTones(h, t, realizedTones(units, place))
}

/** an example's 羅馬字 / 方音 in tone colours */
fun Dict.sentenceToneText(han: String, tpl: String, sys: Int, place: Int, zh: String?, system: Int): Styled {
    val ex = exampleTones(han, tpl, place, zh)
    val b = StyledBuilder()
    val t = ex.tpl
    var i = 0; var n = 0
    while (true) {
        val open = t.indexOf('{', i); if (open < 0) break
        val close = t.indexOf('}', open); if (close < 0) break
        b.add(t.substring(i, open))
        var c = t.substring(open + 1, close)
        val cap = c.startsWith("^")
        if (cap) c = c.drop(1)
        if (c.startsWith("?") || c.startsWith("!")) c = c.drop(1)
        if (EngineSettings.toneMarks && n < ex.tones.size && isCode(c)) c = sandhiCode(c, ex.tones[n])
        var s = if (isCode(c)) syl(c, sys, place) else c
        if (cap) s = cap1(s)
        b.add(s, if (n < ex.tones.size) ToneColors.color(ex.tones[n], system) else null)
        n++
        i = close + 1
    }
    b.add(t.substring(i))
    return b.build()
}

fun Dict.sentenceHanToneText(han: String, tpl: String, place: Int, zh: String?, system: Int, base: Int? = null): Styled {
    val ex = exampleTones(han, tpl, place, zh)
    return hanToneText(ex.han, ex.tones, system, base)
}

// MARK: texts as the app shows them (tone colours when on, guessed readings in red, the place's own words in pink)

fun guessColored(pieces: List<Pair<String, Boolean>>, ink: Int? = null, guess: Int = EngineSettings.guessInk): Styled {
    val b = StyledBuilder()
    for ((t, g) in pieces) b.add(t, if (g) guess else ink)
    return b.build()
}

/** 羅馬字 of an example; readings guessed by rule are red, the place's own words pink */
fun Dict.sentenceText(tpl: String, sys: Int, place: Int, han: String, zh: String? = null): Styled {
    val ts = EngineSettings.toneSystem
    if (ts != 0) return sentenceToneText(han, tpl, sys, place, zh, ts)
    val b = StyledBuilder()
    for (p in examplePieces(tpl, sys, place, han, zh)) {
        b.add(p.text, when (p.mark) { 1 -> EngineSettings.guessInk; 2 -> EngineSettings.swapInk; else -> null })
    }
    return b.build()
}

/** an example's 漢字 for a place: words the place says differently swapped in, in pink */
fun Dict.exampleHanText(han: String, tpl: String, place: Int, zh: String?, base: Int): Styled {
    val ts = EngineSettings.toneSystem
    if (ts != 0) return sentenceHanToneText(han, tpl, place, zh, ts, base)
    if (place < 0) return styled(han, base)
    val loc = localizedExample(han, tpl, place, zh)
    val b = StyledBuilder()
    for ((i, ch) in loc.han.cps().withIndex()) b.add(ch, if (loc.swapped.contains(i)) EngineSettings.swapInk else base)
    return b.build()
}

/** a word's reading with guessed place readings in red (tone colours when on) */
fun Dict.wordText(key: String, sys: Int, place: Int): Styled {
    val ts = EngineSettings.toneSystem
    if (ts != 0) return wordToneText(key, sys, place, ts)
    return guessColored(wordPieces(key, sys, place))
}

/** a word spelled as in `place`, with its tones changed as in `tonesIn` (各地讀音: the 通行 box for 泉 places) */
fun Dict.wordText(key: String, sys: Int, place: Int, tonesIn: Int): Styled {
    val ts = EngineSettings.toneSystem
    if (ts == 0 || tonesIn == place) return wordText(key, sys, place)
    val tok = tokensFor(key, place)
    val tones = wordTones(key, tonesIn)
    val n = tok.count { isCode(if (it.startsWith("^")) it.drop(1) else it) }
    if (n != tones.size) return wordText(key, sys, place)
    return toneText(tok, sys, place, tones, ts)
}

/** a word's 漢字: in tone colours when on, else in `base` */
fun Dict.hanText(key: String, place: Int, base: Int): Styled {
    val ts = EngineSettings.toneSystem
    if (ts != 0) return wordHanToneText(key, place, ts, base)
    return styled(Dict.hanOf(key), base)
}
