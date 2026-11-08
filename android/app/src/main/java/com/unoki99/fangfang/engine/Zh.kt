package com.unoki99.fangfang.engine

import java.text.Normalizer

// 華語 mode. The 華語 deck comes from 《兩岸常用詞典》 (中華文化總會), built into zh.json by
// tools/build_mandarin.py (the same file the iPhone app uses). The dictionary's 注音 is kept as it is;
// 漢語拼音 is spelled from it here, by rule.

object Lang {
    /** 0 台語, 1 華語, 2 粵語, 3 客語 (粵語 and 客語 use the 華語 pages, with their own dictionaries: yue.json, hak.json) */
    val names = listOf("台語", "華語", "粵語", "客語")
    const val count = 4
    val isYue: Boolean get() = EngineSettings.yue
    val isHak: Boolean get() = EngineSettings.hak
    /** 粵語 and 客語: no HSK / TOCFL lists (the words come in groups of how common they are) */
    val ownGroups: Boolean get() = isYue || isHak
    /** 客語's six accents */
    val hakAccents = listOf("四縣", "海陸", "大埔", "饒平", "詔安", "南四縣")
    /** 華語: 拼音 / 注音; 粵語: 粵拼 / 耶魯 */
    val romNames: List<String> get() = if (isYue) listOf("粵拼", "耶魯") else listOf("拼音", "注音")
    /** 粵語: the words and characters come in groups of how common they are (no official lists) */
    const val yueGroup = 500
    fun yueLevelName(l: Int) = "常用詞 ${(l - 1) * yueGroup + 1}–${l * yueGroup}"
    fun yueCharLevelName(l: Int) = "常用字 ${(l - 1) * yueGroup + 1}–${l * yueGroup}"
    val placeNames = listOf("臺灣", "大陸")
    val listNames = listOf("HSK", "TOCFL")
    private val tocflNames = listOf("", "準備一級", "準備二級", "入門級", "基礎級", "進階級", "高階級", "流利級")
    fun hskName(l: Int) = if (l >= 7) "HSK 7–9" else "HSK $l"
    fun tocflName(l: Int) = tocflNames.getOrElse(l) { "" }
    fun levelName(list: Int, l: Int) = if (ownGroups) yueLevelName(l) else if (list == 1) "TOCFL " + tocflName(l) else hskName(l)

    /** a character card's key: "字\t字" (粵語: "字\t粵字", 客語: "字\t客字") */
    fun charKey(ch: String, yue: Boolean = isYue, hak: Boolean = isHak) = ch + (if (yue) "\t粵字" else if (hak) "\t客字" else "\t字")
    /** the character of a character card's key (null = a word) */
    fun charOf(k: String): String? = if (k.endsWith("\t粵字") || k.endsWith("\t客字")) k.dropLast(3) else if (k.endsWith("\t字")) k.dropLast(2) else null
    /** the 新詞 topics of the character cards: 100 + level, 108 = more characters */
    const val charTopicBase = 100
    const val moreChars = 108
    /** 台語: the most common words, 500 a group (1000 + group), and the most common characters (2000 + group) */
    const val freqWordBase = 1000
    const val freqCharBase = 2000
    const val freqSize = 500
    fun isFreqTopic(t: Int) = t >= freqWordBase
    fun freqName(t: Int, count: Int): String {
        val g = if (t >= freqCharBase) t - freqCharBase else t - freqWordBase
        return (if (t >= freqCharBase) "常用字 " else "常用詞 ") + "${g * freqSize + 1}–${g * freqSize + count}"
    }

    /** a 華語 or 粵語 word's key: "漢字\t注音", "漢字\t粵jyut6 ping3" (台語 keys have syllable codes in letters after the tab) */
    fun isZhKey(k: String): Boolean {
        val t = k.indexOf('\t')
        if (t < 0 || t + 1 >= k.length) return false
        if (k.endsWith("\t字")) return true
        val c = k.codePointAt(t + 1)
        return c in 0x3100..0x312F || c in 0x31A0..0x31BF || c == '˙'.code || c == '粵'.code || c == '客'.code
    }
    /** a 粵語 word's or character's key ("漢字\t粵…") */
    fun isYueKey(k: String): Boolean { val t = k.indexOf('\t'); return t >= 0 && k.startsWith("粵", t + 1) }
    /** a 客語 word's or character's key ("漢字\t客…") */
    fun isHakKey(k: String): Boolean { val t = k.indexOf('\t'); return t >= 0 && k.startsWith("客", t + 1) }
    /** which language a key is of: 0 台語, 1 華語, 2 粵語, 3 客語 */
    fun kind(k: String): Int = if (isYueKey(k)) 2 else if (isHakKey(k)) 3 else if (isZhKey(k)) 1 else 0
}

/** 設定 → 字形: 華語 and 粵語 shown in 簡體字. The keys and the data stay 正體; what's shown is changed, character by
 *  character, with the pairs the dictionaries give (後→后, 開→开…) */
object Simp {
    private val table = java.util.concurrent.ConcurrentHashMap<Int, Int>()
    private val back = java.util.concurrent.ConcurrentHashMap<Int, Int>()
    val on: Boolean get() = EngineSettings.simplified && EngineSettings.zhShown && !EngineSettings.hak

    fun learn(pairs: List<Pair<String, String>>) {
        for ((h, a) in pairs) {
            val x = h.codePoints().toArray(); val y = a.codePoints().toArray()
            if (x.size != y.size) continue
            for (i in x.indices) if (x[i] != y[i]) { table.putIfAbsent(x[i], y[i]); back.putIfAbsent(y[i], x[i]) }
        }
    }
    fun show(s: String): String = if (on) convert(s) else s
    fun convert(s: String): String {
        if (table.isEmpty()) return s
        val sb = StringBuilder()
        s.codePoints().forEach { sb.appendCodePoint(table[it] ?: it) }
        return sb.toString()
    }
    /** a 簡體 character's 正體 one */
    fun reverse(cp: Int): Int? = back[cp]
}

/** 粵拼 → 耶魯 */
object Yale {
    private val marks = mapOf(1 to "\u0304", 2 to "\u0301", 3 to "", 4 to "\u0300", 5 to "\u0301", 6 to "")
    private val initials = listOf("gw", "kw", "ng", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "w", "z", "c", "s", "j")

    /** one Jyutping syllable in Yale with tone marks: goi1 → gōi, m4 → m̀h, sik6 → sihk, zyu1 → jyū */
    fun of(s: String): String {
        if (!Zhuyin.isJyut(s)) return s
        val t = s.last().digitToInt()
        val b = s.dropLast(1)
        var ini = initials.firstOrNull { b.startsWith(it) && b.length > it.length } ?: ""
        var fin = b.drop(ini.length)
        ini = mapOf("z" to "j", "c" to "ch", "j" to "y")[ini] ?: ini
        if (ini == "y" && fin.startsWith("yu")) ini = ""
        if (fin == "aa") fin = "a"
        if (fin.startsWith("eo") || fin.startsWith("oe")) fin = "eu" + fin.drop(2)
        val nasal = ini.isEmpty() && (fin == "m" || fin == "ng")
        val syl = ini + fin
        val v = if (nasal) 0 else syl.indexOfFirst { it in "aeiou" }.let { if (it < 0) ini.length else it }
        var out = syl.substring(0, v + 1) + (marks[t] ?: "")
        var rest = syl.substring(v + 1)
        if (t >= 4) {
            if (nasal) { out += rest + "h"; rest = "" } else {
                val vowels = rest.takeWhile { it in "aeiouy" }
                out += vowels + "h"; rest = rest.drop(vowels.length)
            }
        }
        return Normalizer.normalize(out + rest, Normalizer.Form.NFC)
    }
}

object Zhuyin {
    private val initials = mapOf(
        'ㄅ' to "b", 'ㄆ' to "p", 'ㄇ' to "m", 'ㄈ' to "f", 'ㄉ' to "d", 'ㄊ' to "t", 'ㄋ' to "n", 'ㄌ' to "l", 'ㄍ' to "g", 'ㄎ' to "k",
        'ㄏ' to "h", 'ㄐ' to "j", 'ㄑ' to "q", 'ㄒ' to "x", 'ㄓ' to "zh", 'ㄔ' to "ch", 'ㄕ' to "sh", 'ㄖ' to "r", 'ㄗ' to "z", 'ㄘ' to "c", 'ㄙ' to "s")
    private val finals = mapOf(
        "" to "", "ㄚ" to "a", "ㄛ" to "o", "ㄜ" to "e", "ㄝ" to "ê", "ㄞ" to "ai", "ㄟ" to "ei", "ㄠ" to "ao", "ㄡ" to "ou",
        "ㄢ" to "an", "ㄣ" to "en", "ㄤ" to "ang", "ㄥ" to "eng", "ㄦ" to "er",
        "ㄧ" to "i", "ㄧㄚ" to "ia", "ㄧㄛ" to "io", "ㄧㄝ" to "ie", "ㄧㄞ" to "iai", "ㄧㄠ" to "iao", "ㄧㄡ" to "iu",
        "ㄧㄢ" to "ian", "ㄧㄣ" to "in", "ㄧㄤ" to "iang", "ㄧㄥ" to "ing",
        "ㄨ" to "u", "ㄨㄚ" to "ua", "ㄨㄛ" to "uo", "ㄨㄞ" to "uai", "ㄨㄟ" to "ui", "ㄨㄢ" to "uan", "ㄨㄣ" to "un",
        "ㄨㄤ" to "uang", "ㄨㄥ" to "ong",
        "ㄩ" to "ü", "ㄩㄝ" to "üe", "ㄩㄢ" to "üan", "ㄩㄣ" to "ün", "ㄩㄥ" to "iong")
    private val alone = mapOf(
        "i" to "yi", "ia" to "ya", "io" to "yo", "ie" to "ye", "iai" to "yai", "iao" to "yao", "iu" to "you", "ian" to "yan",
        "in" to "yin", "iang" to "yang", "ing" to "ying", "u" to "wu", "ua" to "wa", "uo" to "wo", "uai" to "wai",
        "ui" to "wei", "uan" to "wan", "un" to "wen", "uang" to "wang", "ong" to "weng", "ü" to "yu", "üe" to "yue",
        "üan" to "yuan", "ün" to "yun", "iong" to "yong")
    private val marks = mapOf(
        'a' to listOf("ā", "á", "ǎ", "à"), 'e' to listOf("ē", "é", "ě", "è"), 'i' to listOf("ī", "í", "ǐ", "ì"),
        'o' to listOf("ō", "ó", "ǒ", "ò"), 'u' to listOf("ū", "ú", "ǔ", "ù"), 'ü' to listOf("ǖ", "ǘ", "ǚ", "ǜ"),
        'ê' to listOf("ê̄", "ế", "ê̌", "ề"))
    private val cache = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val plainCache = java.util.concurrent.ConcurrentHashMap<String, String>()

    /** a 粵語 syllable (Jyutping: letters and a tone number, "goi1") */
    fun isJyut(s: String): Boolean = s.length >= 2 && s[0] in 'a'..'z' && s.last() in '1'..'6'

    /** a 客語 syllable: letters, the tone category (a superscript digit) and the accent (a subscript digit): "bau¹₀" */
    fun isHak(s: String): Boolean = s.isNotEmpty() && s.last() in '₀'..'₉'
    private const val SUPERS = "⁰¹²³⁴⁵⁶⁷⁸⁹"
    /** a 客語 syllable's parts: letters, tone category (1 陰平 2 上聲 3 去聲 4 陰入 5 陽平 7 陽去 8 陽入), accent */
    fun hakParts(s: String): Triple<String, Int, Int> {
        if (!isHak(s) || s.length < 3) return Triple(s, 0, 0)
        val acc = s.last() - '₀'
        val t = SUPERS.indexOf(s[s.length - 2]).coerceAtLeast(0)
        return Triple(s.dropLast(2), t, acc)
    }

    /** the tone of a syllable: 1–4, 0 = light tone (˙); 粵語 1–6; 客語 its category */
    fun tone(s: String): Int {
        if (isHak(s)) return hakParts(s).second
        if (isJyut(s)) return s.last().digitToInt()
        if (s.startsWith("˙") || s.endsWith("˙")) return 0
        return when (s.lastOrNull()) { 'ˊ' -> 2; 'ˇ' -> 3; 'ˋ' -> 4; else -> 1 }
    }

    fun bare(s: String): String = if (isHak(s)) hakParts(s).first else if (isJyut(s)) s.dropLast(1) else s.filter { it !in "ˊˇˋ˙" }

    fun withTone(s: String, t: Int): String {
        if (isHak(s)) { val p = hakParts(s); return p.first + SUPERS[t.coerceIn(0, 9)] + ('₀' + p.third) }
        if (isJyut(s)) return s.dropLast(1) + t
        val b = bare(s)
        return when (t) { 0 -> "˙$b"; 2 -> b + "ˊ"; 3 -> b + "ˇ"; 4 -> b + "ˋ"; else -> b }
    }

    /** one 注音 syllable in 拼音 with its tone mark */
    fun pinyin(s: String): String = if (isJyut(s) || isHak(s)) s else cache.getOrPut(s) { spell(s) }

    private fun spell(s0: String): String {
        val t = tone(s0)
        var s = bare(s0)
        if (s.isEmpty()) return ""
        var er = false
        if (s.length > 1 && s.endsWith("ㄦ")) { er = true; s = s.dropLast(1) }
        val ini = initials[s[0]] ?: ""
        val rest = if (ini.isEmpty()) s else s.drop(1)
        var f = finals[rest] ?: return s0
        var p: String
        if (ini.isNotEmpty()) {
            if (f.isEmpty()) {
                if (ini !in listOf("zh", "ch", "sh", "r", "z", "c", "s")) return s0
                f = "i"
            }
            if (ini in listOf("j", "q", "x")) f = f.replace("ü", "u")
            p = ini + f
        } else p = alone[f] ?: f
        if (er) p += "r"
        if (t !in 1..4) return p
        val i = when {
            p.contains('a') -> p.indexOf('a')
            p.contains('e') -> p.indexOf('e')
            p.contains('ê') -> p.indexOf('ê')
            p.contains("ou") -> p.indexOf('o')
            else -> p.indexOfLast { it in "iouü" }
        }
        if (i < 0) return p
        val m = marks[p[i]] ?: return p
        return p.substring(0, i) + m[t - 1] + p.substring(i + 1)
    }

    fun joinPinyin(sy: List<String>): String {
        val sb = StringBuilder()
        for (p in sy) {
            if (p.isEmpty()) continue
            if (sb.isNotEmpty() && p[0] in "aāáǎàoōóǒòeēéěèê") sb.append('\'')
            sb.append(p)
        }
        return sb.toString()
    }

    /** 拼音 without tone marks, for searching: ü → v */
    fun plain(s: String): String {
        val a = s.lowercase().replace("ü", "v").replace("u:", "v")
        val n = Normalizer.normalize(a, Normalizer.Form.NFD).filter { Character.getType(it) != Character.NON_SPACING_MARK.toInt() }
        return n.filter { it.isLetterOrDigit() }
    }

    fun plainSyllable(s: String): String { if (isHak(s)) return hakParts(s).first; if (isJyut(s)) return s.dropLast(1); val b = bare(s); return plainCache.getOrPut(b) { plain(pinyin(b)) } }

    /** the colour of a 華語 tone (the 台語 colours: 1 red, 2 like 台語 5, 3 blue, 4 like 台語 2, light grey);
     *  粵語 1–6 in its own colours */
    fun color(t: Int, sys: Int, yue: Boolean = EngineSettings.yue, hak: Boolean = EngineSettings.hak): Int? {
        if (sys == 0) return null
        // 客語: its tone categories, in the colours picked for 客語
        if (hak) return if (t in ToneColors.hakTones) ToneColors.hakColor(t) else null
        if (yue) return if (t in 1..6) ToneColors.yueColor(t) else null
        return when (t) {
            0, 1, 2, 3, 4 -> ToneColors.zhColor(t); else -> null
        }
    }

    fun isHan(cp: Int) = cp in 0x3400..0x9FFF || cp in 0x20000..0x3FFFF || cp in 0xF900..0xFAFF
}

class ZhEx(val h: String, val src: String, val code: String)
class ZhSense(val n: Int, val text: String, val ex: List<ZhEx>)

class ZhEntry(
    val k: String, val h: String,
    /** 注音 syllables, one per 漢字 ("-" = 兒 sharing the syllable before) */
    val tw: List<String>,
    /** 大陸 reading, where it differs */
    val lu: List<String>?,
    /** 1 臺灣特有, 2 大陸特有 */
    val spec: Int,
    /** 簡化字 */
    val alt: String?,
    val senses: List<ZhSense>,
    val en: String?,
    val hsk: Int, val tocfl: Int,
    /** a word-list word the dictionary doesn't have (added, with the English meaning) */
    val extra: Boolean,
    /** 詞類 (from the HSK / TOCFL lists), in the 台語 dictionary's names */
    val pos: List<String> = emptyList(),
    /** 近義詞 / 反義詞 (教育部《重編國語辭典修訂本》) */
    val syn: List<String> = emptyList(),
    val ant: List<String> = emptyList(),
    /** 粵語: the 華語 words with the same meaning (Wiktionary's dialect tables) */
    val eq: List<String> = emptyList(),
    /** 粵語: a recording of the word (Wikimedia Commons), when there is one */
    val audio: String? = null,
    /** 客語: the reading in each accent (0 四縣 … 5 南四縣; null = that accent doesn't have the word); `tw` is the
     *  one of the accent chosen */
    val acc: List<List<String>?>? = null,
    /** 客語: the accents that say it with another word (accent → word) */
    val otherWords: Map<Int, String> = emptyMap(),
) {
    /** the English meanings, one each (CC-CEDICT separates them with ;) */
    val enList: List<String> by lazy { (en ?: "").split(";").map { it.trim() }.filter { it.isNotEmpty() } }
    fun syl(place: Int): List<String> = if (place == 1) (lu ?: tw) else tw
    fun level(list: Int) = if (list == 1) tocfl else hsk
}

/** a character with its meanings from 教育部《重編國語辭典修訂本》 (each reading: 注音, 拼音, [(詞類, meaning)]) */
class ZhChar(val h: String, val readings: List<Reading>, val hsk: Int, val tocfl: Int, val radical: String?, val strokes: Int?) {
    class Reading(val zy: String, val py: String, val defs: List<Pair<String, String>>, val label: String?)
    fun level(list: Int) = if (list == 1) tocfl else hsk
}

/** a radical and its characters (each with the strokes besides the radical), for looking a character up by its 部首 */
class ZhRadical(val radical: String, val strokes: Int, val chars: List<Pair<String, Int>>)

/** one word of a sentence: its characters and, for each character, its syllable ("_" = not a 漢字) */
class ZhPiece(val text: List<String>, val tw: List<String>?, val lu: List<String>?) {
    fun syl(place: Int): List<String>? = if (place == 1) (lu ?: tw) else tw
}

/** accent: 客語, the accent whose readings are used */
class ZhDict(text: String, val accent: Int = EngineSettings.hakAccent) {
    val entries: List<ZhEntry>
    /** the 粵語 dictionary (yue.json, tools/build_cantonese.py), not the 華語 one */
    var isYue = false; private set
    /** the 客語 dictionary (hak.json, tools/build_hakka.py) */
    var isHak = false; private set
    /** 1 華語, 2 粵語, 3 客語 */
    val lang: Int get() = if (isHak) 3 else if (isYue) 2 else 1
    /** 客語: each accent's tone marks (per tone category) and each syllable's 注音 */
    var hakMarks: List<List<String>> = emptyList(); private set
    var hakZy: Map<String, String> = emptyMap(); private set
    /** 粵語: a 華語 word → the 粵語 words for it */
    val byMandarin = HashMap<String, MutableList<Int>>()
    /** how many of the first entries are common words (the rest are rare words and references) */
    val cardCount: Int
    val index = HashMap<String, Int>()
    val byHan = HashMap<String, MutableList<Int>>()
    private val byPlain = HashMap<String, MutableList<Int>>()
    private val byToned = HashMap<String, MutableList<Int>>()
    private val byZy = HashMap<String, MutableList<Int>>()
    private val byZyToned = HashMap<String, MutableList<Int>>()
    val maxLen: Int

    /** the character cards (教育部《重編國語辭典修訂本》), the listed ones first, the more common first */
    val chars: List<ZhChar>
    val charIndex = HashMap<String, Int>()
    /** 部首 lookup: the radicals (fewest strokes first) with their characters */
    var radicals: List<ZhRadical>; private set
    /** 部首組合: radical → every character with it anywhere inside (fewest strokes first) */
    var radicalInside: Map<String, List<String>>; private set
    /** a character's number of strokes */
    val strokesOf = HashMap<String, Int>()
    private var radicalSetsCache: Map<String, Set<String>>? = null
    val radicalSets: Map<String, Set<String>> get() = radicalSetsCache ?: radicalInside.mapValues { it.value.toHashSet() }.also { radicalSetsCache = it }

    /** 粵語: yue.json doesn't carry the radicals (they're the 華語 data's, whose licence doesn't allow sharing them in
     *  another file), so they're read from the beginning of zh.json when it's there */
    fun borrowRadicals(zhText: String) {
        if (radicals.isNotEmpty()) return
        val mi = zhText.indexOf(",\"e\":[\n"); if (mi < 0) return
        val rads = ArrayList<ZhRadical>(); val rx = HashMap<String, List<String>>()
        val j = JReader(zhText.substring(0, mi) + "}")
        j.obj { key ->
            when (key) {
                "r" -> j.arr {
                    j.beginArray()
                    j.hasNext(); val rad = j.nextString()
                    j.hasNext(); val n = j.nextInt()
                    j.hasNext(); val chs = j.nextString().cps()
                    j.hasNext(); val res = j.intList()
                    while (j.hasNext()) j.skip()
                    j.endArray()
                    rads.add(ZhRadical(rad, n, chs.zip(res)))
                }
                "rx" -> j.obj { r -> rx[r] = j.nextString().cps() }
                else -> j.skip()
            }
        }
        radicals = rads; radicalInside = rx; radicalSetsCache = null
        for (r in rads) for ((ch, rest) in r.chars) if (!strokesOf.containsKey(ch)) strokesOf[ch] = r.strokes + rest
    }

    /** the characters that have all these radicals inside them (fewest strokes first) */
    fun charsWith(rs: List<String>): List<String> {
        val first = rs.minByOrNull { radicalInside[it]?.size ?: 0 } ?: return emptyList()
        val base = radicalInside[first] ?: return emptyList()
        val others = rs.filter { it != first }.map { radicalSets[it] ?: emptySet() }
        return base.filter { c -> others.all { it.contains(c) } }
    }

    init {
        var nc = 0
        val cs = ArrayList<ZhChar>()
        val rads = ArrayList<ZhRadical>()
        val rx = HashMap<String, List<String>>()
        fun head(j: JReader, key: String): Boolean {
            when (key) {
                "nc" -> nc = j.nextInt()
                "lang" -> { val l = j.nextString(); isYue = l == "yue"; isHak = l == "hak" }
                "ht" -> { val m = ArrayList<List<String>>(); j.arr { m.add(j.strList()) }; hakMarks = m }
                "hz" -> { val m = HashMap<String, String>(); j.obj { k -> m[k] = j.nextString() }; hakZy = m }
                "r" -> j.arr {
                    j.beginArray()
                    j.hasNext(); val rad = j.nextString()
                    j.hasNext(); val n = j.nextInt()
                    j.hasNext(); val chs = j.nextString().cps()
                    j.hasNext(); val res = j.intList()
                    while (j.hasNext()) j.skip()
                    j.endArray()
                    rads.add(ZhRadical(rad, n, chs.zip(res)))
                }
                "rx" -> j.obj { r -> rx[r] = j.nextString().cps() }
                "c" -> j.arr {
                    var h = ""; var x = 0; var y = 0; var b: String? = null; var n: Int? = null
                    val rs = ArrayList<ZhChar.Reading>()
                    j.obj { f ->
                        when (f) {
                            "h" -> h = j.nextString(); "x" -> x = j.nextInt(); "y" -> y = j.nextInt()
                            "b" -> b = if (j.isNull()) null else j.nextString()
                            "n" -> n = if (j.isNull()) null else j.nextInt()
                            "m" -> j.arr {
                                j.beginArray()
                                j.hasNext(); var zy = j.nextString()
                                j.hasNext(); var py = j.nextString()
                                // 粵語: [耶魯, 粵拼, …]; the 粵拼 syllable is kept, the readings are made from it
                                if (isYue) zy = py
                                j.hasNext(); val ds = j.strList2().map { Pair(it.getOrElse(0) { "" }, it.getOrElse(1) { "" }) }
                                var label: String? = null
                                if (j.hasNext()) label = if (j.isNull()) null else j.nextString()
                                // 客語: [syllable, syllable, meanings, label, [the syllable in each accent]]: this accent's
                                if (j.hasNext()) {
                                    val v = ArrayList<String?>()
                                    if (!j.isNull()) j.arr { v.add(if (j.isNull()) null else j.nextString()) }
                                    v.getOrNull(accent)?.let { zy = it; py = it }
                                }
                                while (j.hasNext()) j.skip()
                                j.endArray()
                                rs.add(ZhChar.Reading(zy, py, ds, label))
                            }
                            else -> j.skip()
                        }
                    }
                    if (h.isNotEmpty() && rs.isNotEmpty()) cs.add(ZhChar(h, rs, x, y, b, n))
                }
                else -> return false
            }
            return true
        }
        val out = ArrayList<ZhEntry>()
        val marker = ",\"e\":[\n"
        val mi = text.indexOf(marker)
        if (mi >= 0) {
            // the entries are one per line after the rest: read in parts at the same time, on all the cores
            val hj = JReader(text.substring(0, mi) + "}")
            hj.obj { key -> if (!head(hj, key)) hj.skip() }
            val end = text.lastIndexOf("\n]}").let { if (it < mi) text.length else it }
            val lines = text.substring(mi + marker.length, end).split('\n')
            val parts = maxOf(4, Runtime.getRuntime().availableProcessors() * 2)
            val size = (lines.size + parts - 1) / parts
            val res = arrayOfNulls<List<ZhEntry>>(parts)
            val threads = (0 until parts).map { p ->
                Thread {
                    val l = ArrayList<ZhEntry>()
                    for (k in p * size until minOf(lines.size, (p + 1) * size)) {
                        val line = lines[k].trimEnd().removeSuffix(",")
                        if (line.isEmpty()) continue
                        readEntry(JReader(line))?.let { l.add(it) }
                    }
                    res[p] = l
                }.also { it.start() }
            }
            threads.forEach { it.join() }
            for (r in res) if (r != null) out.addAll(r)
        } else {
            val j = JReader(text)
            j.obj { key ->
                if (key == "e") j.arr { readEntry(j)?.let { out.add(it) } }
                else if (!head(j, key)) j.skip()
            }
        }
        chars = cs
        for ((i, c) in cs.withIndex()) charIndex[c.h] = i
        radicals = rads
        radicalInside = rx
        for (r in rads) for ((ch, rest) in r.chars) if (!strokesOf.containsKey(ch)) strokesOf[ch] = r.strokes + rest
        entries = out
        Simp.learn(out.mapNotNull { e -> e.alt?.let { e.h to it } })
        for ((i, e) in out.withIndex()) for (m in e.eq) { val l = byMandarin.getOrPut(m) { ArrayList() }; if (l.lastOrNull() != i) l.add(i) }
        cardCount = if (nc > 0) nc else out.size
        var m = 1
        for ((i, e) in out.withIndex()) {
            index[e.k] = i
            byHan.getOrPut(e.h) { ArrayList() }.add(i)
            if (e.alt != null && e.alt != e.h) byHan.getOrPut(e.alt) { ArrayList() }.add(i)
            m = maxOf(m, e.h.codePointCount(0, e.h.length))
            for (syl in listOfNotNull(e.tw, e.lu)) {
                val ss = syl.filter { it != "-" }
                val py = ss.map { Zhuyin.plainSyllable(it) }
                val toned = ss.zip(py).map { (z, p) -> p + (Zhuyin.tone(z).let { t -> if (t in 1..4 || Zhuyin.isJyut(z) || Zhuyin.isHak(z)) "$t" else "" }) }
                add(byPlain, py.joinToString(""), i)
                add(byToned, toned.joinToString(""), i)
                add(byZy, ss.joinToString("") { Zhuyin.bare(it) }, i)
                add(byZyToned, ss.joinToString(""), i)
            }
        }
        maxLen = minOf(m, 12)
    }

    /** one entry of zh.json */
    private fun readEntry(j: JReader): ZhEntry? {
        var k = ""; var h = ""; var s = ""; var l: String? = null; var p = 0; var a: String? = null
        var en: String? = null; var x = 0; var y = 0; var q = 0
        var w: List<String> = emptyList(); var sy: List<String> = emptyList(); var an: List<String> = emptyList()
        var eq: List<String> = emptyList(); var u: String? = null
        var acc: List<List<String>?>? = null; val others = HashMap<Int, String>()
        val senses = ArrayList<ZhSense>()
        j.obj { f ->
            when (f) {
                "k" -> k = j.nextString(); "h" -> h = j.nextString(); "s" -> s = j.nextString()
                "l" -> l = j.nextString(); "p" -> p = j.nextInt(); "a" -> a = j.nextString()
                "n" -> en = j.nextString(); "x" -> x = j.nextInt(); "y" -> y = j.nextInt(); "q" -> q = j.nextInt()
                "w" -> w = j.strList(); "j" -> sy = j.strList(); "f" -> an = j.strList()
                "m" -> eq = j.strList(); "u" -> u = j.nextString()
                "v" -> { val v = ArrayList<List<String>?>(); j.arr { v.add(if (j.isNull()) null else j.nextString().split(" ")) }; acc = v }
                "o" -> j.obj { a -> val w = j.nextString(); a.toIntOrNull()?.let { others[it] = w } }
                "d" -> j.arr {
                    j.beginArray()
                    j.hasNext(); val t = j.nextString()
                    val xs = ArrayList<ZhEx>()
                    if (j.hasNext()) j.arr {
                        val parts = j.strList()
                        xs.add(ZhEx(parts[0], parts.getOrElse(1) { "" }, parts.getOrElse(2) { "" }))
                    }
                    while (j.hasNext()) j.skip()
                    j.endArray()
                    senses.add(ZhSense(senses.size + 1, t, xs))
                }
                else -> j.skip()
            }
        }
        if (k.isEmpty()) return null
        // 客語: this accent's reading (the main one when the accent doesn't have the word)
        val tw = acc?.getOrNull(accent) ?: s.split(" ")
        return ZhEntry(k, h, tw, l?.split(" "), p, a, senses, en, x, y, q == 1, w, sy, an, eq, u, acc, others)
    }

    private fun add(d: HashMap<String, MutableList<Int>>, k: String, i: Int) {
        val l = d.getOrPut(k) { ArrayList() }
        if (l.lastOrNull() != i) l.add(i)
    }

    fun entry(k: String): ZhEntry? = index[k]?.let { entries[it] }
    fun others(e: ZhEntry): List<ZhEntry> = (byHan[e.h] ?: emptyList<Int>()).map { entries[it] }.filter { it.k != e.k && it.h == e.h }

    // MARK: readings

    /** a word's reading: 0 = 拼音, 1 = 注音; in tone colours when they're on */
    fun reading(syl: List<String>, mode: Int, colours: Int = EngineSettings.toneSystem): Styled {
        val b = StyledBuilder()
        var first = true
        for (s in syl) {
            if (s == "-" || s == "_") continue
            val t = if (Zhuyin.isHak(s)) (if (first) "" else " ") + hakSyllable(s, mode)
            else if (Zhuyin.isJyut(s)) (if (first) "" else " ") + (if (mode == 1) Yale.of(s) else s)
            else if (mode == 1) (if (first) "" else " ") + s else {
                val p = Zhuyin.pinyin(s)
                (if (!first && p.isNotEmpty() && p[0] in "aāáǎàoōóǒòeēéěèê") "'" else "") + p
            }
            b.add(t, Zhuyin.color(Zhuyin.tone(s), colours, isYue, isHak))
            first = false
        }
        return b.build()
    }

    /** one 客語 syllable as it's shown: 拼音 (0) or 注音 (1), then its accent's tone mark ("bauˊ", "ㄅㄠˊ") */
    fun hakSyllable(s: String, mode: Int): String {
        val (letters, t, a) = Zhuyin.hakParts(s)
        val mark = hakMarks.getOrNull(a)?.getOrNull(t) ?: ""
        return (if (mode == 1) hakZy[letters] ?: letters else letters) + mark
    }

    fun readingPlain(syl: List<String>, mode: Int): String = reading(syl, mode, 0).plain()

    /** 漢字 in tone colours (one syllable per 漢字; 兒 after -ㄦ takes the colour before it) */
    fun hanText(han: String, syl: List<String>, base: Int?, colours: Int = EngineSettings.toneSystem): Styled {
        val b = StyledBuilder()
        var i = 0; var last = 1
        for (ch in Simp.show(han).cps()) {
            if (Zhuyin.isHan(ch.firstCp()) && i < syl.size) {
                val s = syl[i]; i++
                val t = if (s == "-") last else Zhuyin.tone(s)
                last = t
                b.add(ch, Zhuyin.color(t, colours, isYue, isHak) ?: base)
            } else b.add(ch, base)
        }
        return b.build()
    }

    // MARK: sentences

    companion object {
        fun pieces(x: ZhEx): List<ZhPiece> = pieces(x.h, x.code)

        fun pieces(text: String, code: String): List<ZhPiece> {
            val chars = text.cps()
            val out = ArrayList<ZhPiece>()
            var i = 0
            for (part in code.split("|")) {
                if (i >= chars.size) break
                if (part.isEmpty()) { out.add(ZhPiece(listOf(chars[i]), null, null)); i++; continue }
                val sides = part.split("/")
                val tw = sides[0].split(" ")
                val lu = if (sides.size > 1) sides[1].split(" ") else null
                val n = minOf(tw.size, chars.size - i)
                out.add(ZhPiece(chars.subList(i, i + n).toList(), tw, lu))
                i += n
            }
            while (i < chars.size) { out.add(ZhPiece(listOf(chars[i]), null, null)); i++ }
            return out
        }

        private val pinyinPunct = mapOf(
            "，" to ", ", "。" to ". ", "、" to ", ", "？" to "? ", "！" to "! ", "：" to ": ", "；" to "; ",
            "「" to "“", "」" to "” ", "『" to "‘", "』" to "’ ", "（" to " (", "）" to ") ", "─" to "—")

        /** one character on its own in a sentence: the reading it usually has there */
        val aloneReading = mapOf(
            "的" to "˙ㄉㄜ", "了" to "˙ㄌㄜ", "著" to "˙ㄓㄜ", "得" to "˙ㄉㄜ", "們" to "˙ㄇㄣ", "麼" to "˙ㄇㄜ", "嗎" to "˙ㄇㄚ",
            "呢" to "˙ㄋㄜ", "吧" to "˙ㄅㄚ", "啊" to "˙ㄚ", "都" to "ㄉㄡ", "還" to "ㄏㄞˊ", "個" to "ㄍㄜˋ", "沒" to "ㄇㄟˊ",
            "給" to "ㄍㄟˇ", "那" to "ㄋㄚˋ", "哪" to "ㄋㄚˇ", "誰" to "ㄕㄟˊ", "會" to "ㄏㄨㄟˋ", "要" to "ㄧㄠˋ", "說" to "ㄕㄨㄛ",
            "為" to "ㄨㄟˋ", "中" to "ㄓㄨㄥ", "好" to "ㄏㄠˇ", "看" to "ㄎㄢˋ", "只" to "ㄓˇ", "長" to "ㄔㄤˊ", "重" to "ㄓㄨㄥˋ",
            "地" to "ㄉㄧˋ", "大" to "ㄉㄚˋ", "和" to "ㄏㄜˊ", "把" to "ㄅㄚˇ", "少" to "ㄕㄠˇ", "種" to "ㄓㄨㄥˇ", "行" to "ㄒㄧㄥˊ")
    }

    /** a sentence's reading (0 拼音, 1 注音); `blank` = the word to leave out (例句填空) */
    fun sentence(ps: List<ZhPiece>, mode: Int, place: Int, blank: String? = null, colours: Int = EngineSettings.toneSystem): Styled {
        val b = StyledBuilder()
        var prevWord = false
        var started = false
        fun put(t: String, c: Int? = null) {
            var s = t
            if (!started) { s = s.trimStart(); if (s.isEmpty()) return }
            // a sentence in 拼音 starts with a capital letter
            if (!started && mode == 0 && lang == 1) {
                val i = s.indexOfFirst { it.isLetter() }
                if (i >= 0) { s = s.substring(0, i) + s[i].uppercaseChar() + s.substring(i + 1); started = true }
                else started = s.isNotEmpty()
            } else started = true
            b.add(s, c)
        }
        for (p in ps) {
            val syl = p.syl(place)
            if (syl != null) {
                if (prevWord) put(" ")
                if (blank != null && p.text.joinToString("") == blank) { put("＿＿") } else {
                    var sy = ArrayList<String>()
                    fun flush() { if (sy.isNotEmpty()) { for (seg in reading(sy, mode, colours)) put(seg.t, seg.c); sy = ArrayList() } }
                    for ((i, s) in syl.withIndex()) {
                        if (s == "_") {
                            flush()
                            val ch = p.text.getOrElse(i) { "" }
                            put(if (mode == 0) (pinyinPunct[ch] ?: ch) else ch)
                        } else sy.add(s)
                    }
                    flush()
                }
                prevWord = true
            } else {
                val ch = p.text.joinToString("")
                if (mode == 0) {
                    val q = pinyinPunct[ch]
                    if (q != null) { put(q); prevWord = false; continue }
                    if (ch.all { it.isLetterOrDigit() }) { if (prevWord) put(" "); put(ch); prevWord = true; continue }
                }
                put(ch); prevWord = false
            }
        }
        // tidy the spaces: none before punctuation, never two
        val out = ArrayList<Seg>()
        for (seg in b.build()) {
            var t = seg.t.replace(Regex(" {2,}"), " ")
            if (out.isNotEmpty() && out.last().t.endsWith(" ") && t.startsWith(" ")) t = t.trimStart()
            if (t.isNotEmpty() && t[0] in ",.?!:;)”’" && out.isNotEmpty() && out.last().t.endsWith(" ")) {
                val l = out.last(); out[out.size - 1] = Seg(l.t.trimEnd(), l.c)
            }
            if (t.isNotEmpty()) out.add(Seg(t, seg.c))
        }
        if (out.isNotEmpty()) { val l = out.last(); out[out.size - 1] = Seg(l.t.trimEnd(), l.c) }
        return out.filter { it.t.isNotEmpty() }
    }

    /** a sentence's 漢字, in tone colours when they're on */
    fun sentenceHan(ps: List<ZhPiece>, place: Int, base: Int, blank: String? = null, colours: Int = EngineSettings.toneSystem): Styled {
        val b = StyledBuilder()
        for (p in ps) {
            if (blank != null && p.text.joinToString("") == blank) { b.add("＿＿", base); continue }
            var last = 1
            val syl = p.syl(place)
            for ((i, ch) in p.text.withIndex()) {
                if (syl != null && i < syl.size && syl[i] != "_") {
                    val t = if (syl[i] == "-") last else Zhuyin.tone(syl[i])
                    last = t
                    b.add(Simp.show(ch), Zhuyin.color(t, colours, isYue, isHak) ?: base)
                } else b.add(Simp.show(ch), base)
            }
        }
        return b.build()
    }

    // MARK: cards

    /** the entry as a card (the same shape as a 台語 card); cats = its level on the word list */
    fun card(i: Int, list: Int): Card {
        val e = entries[i]
        val defs = e.senses.map { s ->
            Def("", s.text, s.ex.map { x ->
                // (客語: the sentences aren't split into words, they're written for the word; no voice reads them)
                val blankable = x.h != e.h && x.h.contains(e.h) && (isHak || pieces(x).any { it.text.joinToString("") == e.h })
                Example(Simp.show(x.h), listOf(""), x.src, if (isHak) "" else "tts:" + x.h,
                    if (blankable) Simp.show(x.h.replace(e.h, "＿＿")) else null, if (blankable) listOf("") else null, x.code.ifEmpty { null })
            })
        }
        val variant = e.lu?.let { lu -> mapOf("1" to Variant(listOf(readingPlain(lu, 0)), readingPlain(lu, 1))) }
        val lvl = e.level(list)
        return Card(e.k, Simp.show(e.h), listOf(readingPlain(e.tw, 0)), readingPlain(e.tw, 1), null, "", defs,
            null, null, variant, null, null,
            if (e.spec == 1) "臺灣特有" else if (e.spec == 2) "大陸特有" else null,
            null, null, if (lvl > 0) listOf(lvl) else null, e.tw, e.lu, e.audio)
    }

    /** a character as a card: its readings and meanings from 《重編國語辭典修訂本》; cats = its character level */
    fun charCard(i: Int, list: Int, reading: Int = 0): Card {
        val c = chars[i]
        val r = if (reading in c.readings.indices) reading else 0
        val main = c.readings[r]
        val defs = main.defs.map { Def(it.first, it.second, emptyList()) }
        val others = c.readings.filterIndexed { n, _ -> n != r }.map { Other(it.label ?: "又", listOf(if (isHak) readingPlain(listOf(it.zy), 0) else it.py),
            if (isYue) Yale.of(it.zy) else if (isHak) readingPlain(listOf(it.zy), 1) else it.zy) }
        val l = c.level(list)
        val topic = if (l > 0) Lang.charTopicBase + l else Lang.moreChars
        return Card(Lang.charKey(c.h, isYue, isHak), Simp.show(c.h), listOf(if (isHak) readingPlain(listOf(main.zy), 0) else main.py),
            if (isYue) Yale.of(main.zy) else if (isHak) readingPlain(listOf(main.zy), 1) else main.zy, null, "", defs, null, null, null,
            others.ifEmpty { null }, null, "漢字", null, null, listOf(topic), listOf(main.zy), null)
    }

    /** which of a character's readings a syllable is (the one in a word: 中 in 中獎 is ㄓㄨㄥˋ, not ㄓㄨㄥ); the
     *  syllables are tried in order (臺灣's, then 大陸's), each first as it is, then without the tone */
    fun readingIndex(i: Int, syllables: List<String>): Int? {
        val rs = chars[i].readings
        val ss = syllables.filter { it.isNotEmpty() && it != "-" && it != "_" }
        for (s in ss) rs.indexOfFirst { it.zy == s }.takeIf { it >= 0 }?.let { return it }
        for (s in ss) {
            val b = Zhuyin.plainSyllable(s)
            rs.indexOfFirst { Zhuyin.plainSyllable(it.zy) == b }.takeIf { it >= 0 }?.let { return it }
        }
        return null
    }

    /** the dictionary entry of a character read a certain way */
    fun entryForChar(ch: String, zy: String): ZhEntry? {
        val es = (byHan[ch] ?: emptyList<Int>()).map { entries[it] }.filter { it.h == ch }
        return es.firstOrNull { it.tw.firstOrNull() == zy } ?: es.firstOrNull()
    }

    /** the usual entry for a word */
    fun usualEntry(han: String): ZhEntry? = usual(han)?.let { entries[it] }

    /** the words of a 詞類 (the more common first) */
    fun wordsOfClass(c: String): List<Int> = entries.indices.filter { entries[it].pos.contains(c) }

    // MARK: looking up

    class Found {
        val words = ArrayList<Int>(); val starts = ArrayList<Int>(); val contains = ArrayList<Int>()
        val defs = ArrayList<Int>(); val english = ArrayList<Int>(); val tones = ArrayList<Int>()
        var toneLabel = ""
        /** several words searched at once (陰謀論 → 陰謀, 論; or 陰謀 論): each word and its entries */
        var parts: List<String> = emptyList()
        var partWords: List<List<Int>> = emptyList()
        /** 粵語: the words for this 華語 word (華語 → 粵語) */
        val mandarin = ArrayList<Int>()
        /** the English meanings shown before the readings ("me", "I") */
        var englishFirst = false
        val empty: Boolean get() = mandarin.isEmpty() && parts.isEmpty() && words.isEmpty() && starts.isEmpty() && contains.isEmpty() && defs.isEmpty() && english.isEmpty() && tones.isEmpty()
    }

    fun toneDigits(e: ZhEntry, place: Int): String =
        e.syl(place).filter { it != "-" && it != "_" }.joinToString("") { Zhuyin.tone(it).toString() }

    fun search(q0: String, place: Int = 0): Found {
        val q = q0.trim()
        val f = Found()
        if (q.isEmpty()) return f
        // only tone numbers: words with those tones (0 or 5 = light tone): 34、3-4、1 0
        if (q.all { it in "012345678 -,，、" } && q.any { it.isDigit() }) {
            val want = if (lang != 1) q.filter { it.isDigit() } else q.filter { it.isDigit() }.map { if (it == '5') '0' else it }.joinToString("")
            f.toneLabel = want.toList().joinToString("-")
            for ((i, e) in entries.withIndex()) {
                if (e.senses.all { it.text.startsWith("參見") }) continue
                if (toneDigits(e, place) == want) { f.tones.add(i); if (f.tones.size >= 500) break }
            }
            return f
        }
        // * = one or more characters, ? = exactly one (the same as in 台語)
        val wild = q.replace("＊", "*").replace("？", "?")
        if (wild.contains('*') || wild.contains('?')) {
            val pat = StringBuilder("^")
            for (ch in wild.cps()) pat.append(when (ch) { "*" -> ".+"; "?" -> "."; else -> Regex.escape(ch) })
            pat.append("$")
            val re = Regex(pat.toString())
            for ((i, e) in entries.withIndex()) {
                if (re.matches(e.h) || (e.alt?.let { re.matches(it) } ?: false)) { f.words.add(i); if (f.words.size >= 500) break }
            }
            return f
        }
        // 粵語: the words for a 華語 word (聊天 → 傾偈, 吹水…)
        if (isYue) byMandarin[q]?.let { f.mandarin.addAll(it) }
        Segmenter.parts(q, maxLen) { byHan.containsKey(it) }?.let { ps ->
            f.parts = ps
            f.partWords = ps.map { byHan[it] ?: emptyList<Int>() }
            // (陰謀論 itself may still be inside longer words)
            if (!q.any { it.isWhitespace() }) for ((i, e) in entries.withIndex()) {
                if (e.h.contains(q) || (e.alt?.contains(q) ?: false)) { f.contains.add(i); if (f.contains.size >= 150) break }
            }
            return f
        }
        if (q.cps().any { Zhuyin.isHan(it.firstCp()) }) {
            byHan[q]?.let { f.words.addAll(it) }
            val seen = HashSet(f.words)
            for ((i, e) in entries.withIndex()) {
                if (e.h == q) continue
                if (e.h.startsWith(q) || (e.alt?.startsWith(q) ?: false)) {
                    if (f.starts.size < 150 && seen.add(i)) f.starts.add(i)
                } else if (e.h.contains(q) || (e.alt?.contains(q) ?: false)) {
                    if (f.contains.size < 150 && seen.add(i)) f.contains.add(i)
                }
                if (f.starts.size >= 150 && f.contains.size >= 150) break
            }
            for ((i, e) in entries.withIndex()) {
                if (seen.contains(i)) continue
                if (e.senses.any { it.text.contains(q) }) { f.defs.add(i); if (f.defs.size >= 80) break }
            }
            return f
        }
        if (q.any { it.code in 0x3100..0x312F }) {
            val z = q.filter { !it.isWhitespace() }
            val toned = z.any { it in "ˊˇˋ˙" }
            (if (toned) byZyToned[z] else byZy[Zhuyin.bare(z)])?.let { f.words.addAll(it) }
            return f
        }
        // 拼音 (with or without tone numbers), and English
        val p = if (lang != 1) Zhuyin.plain(q) else Zhuyin.plain(q).replace("5", "").replace("0", "")
        val toned = p.any { it.isDigit() }
        (if (toned) byToned[p] else byPlain[p])?.let { f.words.addAll(it) }
        if (!toned && f.words.size < 30) {
            val seen = HashSet(f.words)
            for ((k, v) in byPlain) {
                if (k.startsWith(p) && k != p) for (i in v) if (seen.add(i)) f.starts.add(i)
                if (f.starts.size > 120) break
            }
            f.starts.sort()
        }
        if (!toned) {
            val (list, best) = englishHits(q)
            f.english.addAll(list)
            f.englishFirst = best <= 1
        }
        return f
    }

    /** words whose English meaning has the word(s): a meaning that is just the word first ("eat", "to eat"),
     *  then meanings that start with it, then the rest. Within each: words that give it as their first meaning
     *  first, then the more common words. A meaning with a note in brackets ("(computing) (coll.) slow") counts
     *  one step lower, so 慢 comes before 卡 for "slow". "to park" (a verb) puts "to park" before "park" (a noun). */
    fun english(q0: String): List<Int> = englishHits(q0).first

    /** each entry's English, in small letters (粵語: Wiktionary's meanings too), for the English search: made the
     *  first time it's needed, not every search (127,000 粵語 words made the search slow) */
    private val englishTexts: List<String> by lazy {
        entries.map { e -> (if (isYue) e.senses.joinToString(";") { it.text } + ";" + (e.en ?: "") else (e.en ?: "")).lowercase() }
    }
    /** (made ahead of the first English search, when the dictionary page opens) */
    fun warmEnglish() { englishTexts.size }

    /** (and how close the best one is: 0 = a meaning that's exactly the words) */
    fun englishHits(q0: String): Pair<List<Int>, Int> {
        val q = q0.lowercase().trim()
        if (q.length < 2 && q != "i" && q != "a") return emptyList<Int>() to 9
        val wantVerb = q.startsWith("to ")
        val bare = if (wantVerb) q.drop(3) else q
        val wordRe = Regex("[^a-z]" + Regex.escape(bare) + "[^a-z]")
        val paren = Regex("\\([^()]*\\)")
        class Hit(val tier: Int, val later: Int, val i: Int)
        val hits = ArrayList<Hit>()
        val texts = englishTexts
        for (i in texts.indices) {
            // (粵語: Wiktionary's meanings are the senses, CC-Canto's / CC-CEDICT's the English)
            val en = texts[i]
            if (en.isEmpty() || !en.contains(bare)) continue
            var best = 9; var bestPos = 1
            for ((pos, g0) in en.split(";").withIndex()) {
                var g = g0
                var noted = false
                while (paren.containsMatchIn(g)) { g = paren.replace(g, ""); noted = true }
                g = g.trim()
                val isVerb = g.startsWith("to ")
                val v = if (isVerb) g.drop(3) else g
                var t = when {
                    v == bare -> 0
                    v.startsWith("$bare ") || v.startsWith("$bare,") -> 2
                    wordRe.containsMatchIn(" $v ") -> 4
                    else -> 9
                }
                if (t < 9 && isVerb != wantVerb && (wantVerb || t == 0)) t += if (wantVerb) 2 else 1
                if (t < 9 && noted) t += 1
                val p = if (pos == 0) 0 else 1
                if (t < best || (t == best && p < bestPos)) { best = t; bestPos = p }
            }
            if (best <= 5) hits.add(Hit(best, bestPos, i))
        }
        hits.sortWith(compareBy<Hit>({ it.tier }, { it.later }, { it.i }))
        return hits.take(250).map { it.i } to (hits.firstOrNull()?.tier ?: 9)
    }

    /** the entry for a word of a sentence: the one read the way the sentence reads it */
    fun entryFor(p: ZhPiece): ZhEntry? {
        val text = p.text.joinToString("")
        val cands = (byHan[text] ?: emptyList<Int>()).filter { entries[it].h == text || entries[it].alt == text }
        val tw = (p.tw ?: emptyList()).filter { it != "_" }
        cands.firstOrNull { entries[it].tw.filter { s -> s != "_" } == tw }?.let { return entries[it] }
        return usual(text)?.let { entries[it] }
    }

    // MARK: 轉換

    fun usual(han: String): Int? {
        val l = (byHan[han] ?: return null).filter { entries[it].h == han || entries[it].alt == han }
        if (l.isEmpty()) return null
        if (l.size == 1) return l[0]
        if (lang == 1) aloneReading[han]?.let { want -> l.firstOrNull { entries[it].tw.firstOrNull() == want }?.let { return it } }
        return l.maxByOrNull { entries[it].senses.size }
    }

    /** text split into the dictionary's words (fewest words; then the more common ones) */
    fun convert(text: String): List<Pair<String, Int?>> {
        val chars = text.cps()
        val n = chars.size
        if (n == 0) return emptyList()
        val best = arrayOfNulls<Pair<Int, Int>>(n + 1)
        val back = Array(n + 1) { Pair(0, null as Int?) }
        best[0] = Pair(0, 0)
        for (i in 0 until n) {
            val cur = best[i] ?: continue
            val cands = ArrayList<Pair<Int, Int?>>()
            if (Zhuyin.isHan(chars[i].firstCp())) {
                var len = minOf(maxLen, n - i)
                while (len >= 1) {
                    val w = chars.subList(i, i + len).joinToString("")
                    usual(w)?.let { cands.add(Pair(i + len, it)) }
                    len--
                }
            }
            if (cands.isEmpty()) cands.add(Pair(i + 1, null))
            for ((j, e) in cands) {
                val ns = Pair(cur.first + 1, cur.second + (e ?: entries.size))
                val b = best[j]
                if (b == null || ns.first < b.first || (ns.first == b.first && ns.second < b.second)) { best[j] = ns; back[j] = Pair(i, e) }
            }
        }
        val out = ArrayList<Pair<String, Int?>>()
        var j = n
        while (j > 0) { val (i, e) = back[j]; out.add(Pair(chars.subList(i, j).joinToString(""), e)); j = i }
        return out.reversed()
    }

    /** 轉換: the text as pieces with readings (一 / 不 change their tone before another syllable) */
    fun convertPieces(text: String): List<ZhPiece> {
        val ps = ArrayList<ZhPiece>()
        for ((t, e) in convert(text)) {
            val chars = t.cps()
            if (e != null) {
                val en = entries[e]
                val tw = ArrayList<String>(); val lu = ArrayList<String>(); var k = 0
                for (ch in chars) {
                    if (Zhuyin.isHan(ch.firstCp()) && k < en.tw.size) {
                        tw.add(en.tw[k]); lu.add(en.lu?.getOrNull(k) ?: en.tw[k]); k++
                    } else { tw.add("_"); lu.add("_") }
                }
                ps.add(ZhPiece(chars, tw, if (en.lu == null) null else lu))
            } else for (ch in chars) ps.add(ZhPiece(listOf(ch), null, null))
        }
        if (lang != 1) return ps       // (一 / 不 changing tone is 華語's)
        val num = "〇零一二三四五六七八九十百千萬億兩第".map { it.toString() }.toSet()
        for (i in ps.indices) {
            if (ps[i].text != listOf("一") && ps[i].text != listOf("不")) continue
            val next = ps.getOrNull(i + 1)?.tw?.firstOrNull() ?: continue
            if (next == "_") continue
            if (ps[i].text == listOf("一") && ((i > 0 && ps[i - 1].text.lastOrNull() in num) || ps[i + 1].text.firstOrNull() in num)) continue
            val t = Zhuyin.tone(next)
            val new = if (ps[i].text == listOf("不")) (if (t == 4) "ㄅㄨˊ" else null)
                else if (t == 4) "ㄧˊ" else if (t in 1..3) "ㄧˋ" else null
            if (new != null) ps[i] = ZhPiece(ps[i].text, listOf(new), null)
        }
        return ps
    }
}
