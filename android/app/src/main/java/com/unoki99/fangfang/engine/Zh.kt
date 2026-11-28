package com.unoki99.fangfang.engine

import java.text.Normalizer

// 華語 mode. The 華語 deck comes from 《兩岸常用詞典》 (中華文化總會), built into zh.json by
// tools/build_mandarin.py (the same file the iPhone app uses). The dictionary's 注音 is kept as it is;
// 漢語拼音 is spelled from it here, by rule.

object Lang {
    /** 0 台語, 1 華語, 2 粵語, 3 客語, 4 日語 (粵語, 客語 and 日語 use the 華語 pages, with their own dictionaries:
     *  yue.json, hak.json, ja.json) */
    private val all = listOf("台語", "華語", "粵語", "客語", "日語", "瑞典語", "英語")
    /** (瑞典語 = 5 and 英語 = 6: the computer version only) */
    val names: List<String> get() = if (EngineSettings.desktop) all else all.subList(0, 5)
    val count: Int get() = names.size
    val isYue: Boolean get() = EngineSettings.yue
    val isHak: Boolean get() = EngineSettings.hak
    val isJa: Boolean get() = EngineSettings.ja
    /** 瑞典語 (sv.json, Folkets lexikon; the computer version): the same pages as 華語, each word in its morphemes.
     *  Also 英語 (the same pages: words in letters); isEn tells it apart */
    val isSv: Boolean get() = EngineSettings.sv
    /** 英語 (en.json, ECDICT; the computer version): read in IPA, British and American */
    val isEn: Boolean get() = EngineSettings.en
    /** 粵語, 客語, 日語 and 瑞典語: no HSK / TOCFL lists (the words come in groups of how common they are) */
    val ownGroups: Boolean get() = isYue || isHak || isJa || isSv
    /** 客語's six accents */
    val hakAccents = listOf("四縣", "海陸", "大埔", "饒平", "詔安", "南四縣")
    /** 華語: 拼音 / 注音; 粵語: 粵拼 / 耶魯 */
    val romNames: List<String> get() = if (isEn) listOf("英式＋美式", "美式", "英式", "不顯示") else if (isSv) listOf("詞素", "不顯示") else if (isJa) listOf("羅馬字", "假名") else if (isYue) listOf("粵拼", "耶魯") else listOf("拼音", "注音")
    /** 粵語: the words and characters come in groups of how common they are (no official lists) */
    const val yueGroup = 500
    fun yueLevelName(l: Int) = "常用詞 ${(l - 1) * yueGroup + 1}–${l * yueGroup}"
    fun yueCharLevelName(l: Int) = "常用字 ${(l - 1) * yueGroup + 1}–${l * yueGroup}"
    /** 華語's readings: 臺灣, 大陸 and (when its data is there: zh_sc.json, the computer version) 四川話 */
    val placeNames: List<String> get() = if (isEn) listOf("English") else if (isSv) listOf("Svenska") else if (isJa) listOf("日本語") else if (!isYue && !isHak && Sichuan.available) listOf("臺灣", "大陸", "四川話") else listOf("臺灣", "大陸")
    /** (英語 has its own: 常用度, Collins, 考試) */
    val listNames: List<String> get() = if (isEn) listOf("常用度", "Collins", "考試") else listOf("HSK", "TOCFL")
    /** 英語's exam lists (the first one a word is on) */
    val enExamNames = listOf("", "中考", "高考", "CET-4", "CET-6", "考研", "TOEFL／IELTS", "GRE")
    private val tocflNames = listOf("", "準備一級", "準備二級", "入門級", "基礎級", "進階級", "高階級", "流利級")
    fun hskName(l: Int) = if (l >= 7) "HSK 7–9" else "HSK $l"
    fun tocflName(l: Int) = tocflNames.getOrElse(l) { "" }
    fun levelName(list: Int, l: Int) = if (isEn) (when (list) {
            1 -> if (l in 1..5) "Collins " + "★".repeat(6 - l) else ""
            2 -> enExamNames.getOrElse(l) { "" }
            else -> yueLevelName(l)
        }) else if (ownGroups) yueLevelName(l) else if (list == 1) "TOCFL " + tocflName(l) else hskName(l)

    /** a character card's key: "字\t字" (粵語: "字\t粵字", 客語: "字\t客字", 日語: "字\t日字") */
    fun charKey(ch: String, yue: Boolean = isYue, hak: Boolean = isHak, ja: Boolean = isJa) =
        ch + (if (ja) "\t日字" else if (yue) "\t粵字" else if (hak) "\t客字" else "\t字")
    /** the character of a character card's key (null = a word) */
    fun charOf(k: String): String? = if (k.endsWith("\t粵字") || k.endsWith("\t客字") || k.endsWith("\t日字")) k.dropLast(3) else if (k.endsWith("\t字")) k.dropLast(2) else null
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
        return c in 0x3100..0x312F || c in 0x31A0..0x31BF || c == '˙'.code || c == '粵'.code || c == '客'.code || c == '日'.code || c == '瑞'.code || c == '英'.code
    }
    /** a 粵語 word's or character's key ("漢字\t粵…") */
    fun isYueKey(k: String): Boolean { val t = k.indexOf('\t'); return t >= 0 && k.startsWith("粵", t + 1) }
    /** a 客語 word's or character's key ("漢字\t客…") */
    fun isHakKey(k: String): Boolean { val t = k.indexOf('\t'); return t >= 0 && k.startsWith("客", t + 1) }
    /** a 日語 word's or character's key ("食べる\t日たべる", "食\t日字") */
    fun isJaKey(k: String): Boolean { val t = k.indexOf('\t'); return t >= 0 && k.startsWith("日", t + 1) }
    /** a 瑞典語 word's key ("läsa\t瑞vb") */
    fun isSvKey(k: String): Boolean { val t = k.indexOf('\t'); return t >= 0 && k.startsWith("瑞", t + 1) }
    /** a 英語 word's key ("run\t英") */
    fun isEnKey(k: String): Boolean { val t = k.indexOf('\t'); return t >= 0 && k.startsWith("英", t + 1) }
    /** which language a key is of: 0 台語, 1 華語, 2 粵語, 3 客語, 4 日語, 5 瑞典語, 6 英語 */
    fun kind(k: String): Int = if (isYueKey(k)) 2 else if (isHakKey(k)) 3 else if (isJaKey(k)) 4 else if (isSvKey(k)) 5 else if (isEnKey(k)) 6 else if (isZhKey(k)) 1 else 0
}

/** 設定 → 字形: 華語 and 粵語 shown in 簡體字. The keys and the data stay 正體; what's shown is changed, character by
 *  character, with the pairs the dictionaries give (後→后, 開→开…) */
object Simp {
    private val table = java.util.concurrent.ConcurrentHashMap<Int, Int>()
    private val back = java.util.concurrent.ConcurrentHashMap<Int, Int>()
    val on: Boolean get() = EngineSettings.simplified && EngineSettings.zhShown && !EngineSettings.hak && !EngineSettings.ja && !EngineSettings.sv

    /** every word with its 簡體 (the same when it has none). A character is made 簡體 only when most words change it,
     *  and to what most of them change it to: a word whose 簡體 is another way of writing it (瞳人 → 瞳仁, 菜子 →
     *  菜籽) made every 人 仁 and every 子 籽 */
    fun learn(pairs: List<Pair<String, String>>) {
        val changed = HashMap<Int, HashMap<Int, Int>>()
        val kept = HashMap<Int, Int>()
        for ((h, a) in pairs) {
            val x = h.codePoints().toArray(); val y = a.codePoints().toArray()
            if (x.size != y.size) continue
            for (i in x.indices) {
                if (x[i] != y[i]) { val m = changed.getOrPut(x[i]) { HashMap() }; m[y[i]] = (m[y[i]] ?: 0) + 1 }
                else kept[x[i]] = (kept[x[i]] ?: 0) + 1
            }
        }
        val backVotes = HashMap<Int, Pair<Int, Int>>()
        for ((x, m) in changed) {
            val best = m.maxByOrNull { it.value } ?: continue
            if (best.value <= (kept[x] ?: 0)) continue
            table.putIfAbsent(x, best.key)
            // (back to 正體 only when the 簡體 character isn't a 正體 one of its own in more words: 法 stays 法, not
            // 灋, though 灋's 簡體 is 法)
            if (best.value <= (kept[best.key] ?: 0)) continue
            val b = backVotes[best.key]
            if (b == null || best.value > b.second) backVotes[best.key] = Pair(x, best.value)
        }
        for ((s, t) in backVotes) back.putIfAbsent(s, t.first)
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

/** 四川話 (成都) readings for the 華語 dictionary: zh_sc.json (tools/build_sichuan.py, from Wiktionary). `source`
 *  is set by the app (the file is only made for the computer version); no file = no 四川話 */
object Sichuan {
    class Word(val h: String, val s: String, val z: String, val m: List<String>, val e: List<String>, val k: Int)
    class Data(
        /** an entry's key → (its reading, "ce1 …"; how it's known: 0 Wiktionary, 1 guessed from the characters, 2 predicted) */
        val readings: Map<String, Pair<String, Int>> = emptyMap(),
        /** 四川話's own words (耍朋友, 日白 …) */
        val words: List<Word> = emptyList(),
        /** the dictionary's words that 成都 says, with the 華語 words for them (擺龍門陣 → 聊天) */
        val eq: Map<String, List<String>> = emptyMap())
    /** 四川話's own words have this `spec` (shown only when 讀音 = 四川話) */
    const val spec = 3
    var source: (() -> java.io.Reader?)? = null
    @Volatile private var cached: Data? = null
    fun data(): Data {
        cached?.let { return it }
        val src = source ?: return Data()
        val d = try {
            val text = src()?.use { it.readText() }
            if (text == null) Data() else {
                val rs = HashMap<String, Pair<String, Int>>(); val ws = ArrayList<Word>(); var eq: Map<String, List<String>> = emptyMap()
                val j = JReader(text)
                val got = HashMap<String, HashMap<String, String>>()
                j.obj { key ->
                    when (key) {
                        "p", "g", "s" -> { val m = HashMap<String, String>(); j.obj { k -> m[k] = j.nextString() }; got[key] = m }
                        "w" -> j.arr {
                            var h = ""; var sy = ""; var z = ""; var m: List<String> = emptyList(); var e: List<String> = emptyList(); var k = 2
                            j.obj { f -> when (f) { "h" -> h = j.nextString(); "s" -> sy = j.nextString(); "z" -> z = j.nextString()
                                "m" -> m = j.strList(); "e" -> e = j.strList(); "k" -> k = j.nextInt(); else -> j.skip() } }
                            if (h.isNotEmpty() && sy.isNotEmpty() && z.isNotEmpty()) ws.add(Word(h, sy, z, m, e, k))
                        }
                        "q" -> eq = j.strListMap()
                        else -> j.skip()
                    }
                }
                // (Wiktionary's over the guessed, the guessed over the predicted)
                for ((k, v) in got["p"] ?: emptyMap()) rs[k] = v to 2
                for ((k, v) in got["g"] ?: emptyMap()) rs[k] = v to 1
                for ((k, v) in got["s"] ?: emptyMap()) rs[k] = v to 0
                Data(rs, ws, eq)
            }
        } catch (_: Exception) { Data() }
        cached = d
        return d
    }
    val available: Boolean get() = data().readings.isNotEmpty()

    /** a syllable as it's shown: a mark on the vowel for how the tone sounds ("ce1" → "cē"):
     *  1 high level ā, 2 low falling a̱ (a line under it), 3 high falling à, 4 low dipping ǎ, 5 (入聲) like 2 */
    fun pinyin(s0: String): String {
        val s = v(s0)
        val d = s.lastOrNull()?.digitToIntOrNull() ?: return s
        val letters = s.dropLast(1)
        val mark = when (d) { 1 -> "\u0304"; 2, 5 -> "\u0331"; 3 -> "\u0300"; 4 -> "\u030C"; else -> return letters }
        // where the mark goes, as in 拼音: a, e (ê), o in ou, else the last vowel (no vowel: the first letter, ng̀)
        var i = letters.indexOf('a')
        if (i < 0) i = letters.indexOfFirst { it == 'e' || it == 'ê' }
        if (i < 0) { val o = letters.indexOf('o'); if (o >= 0 && o + 1 < letters.length && letters[o + 1] == 'u') i = o }
        if (i < 0) i = letters.indexOfLast { it in "iouüv" }
        if (i < 0) i = 0
        if (i >= letters.length) return letters
        return Normalizer.normalize(letters.substring(0, i + 1) + mark + letters.substring(i + 1), Normalizer.Form.NFC)
    }

    /** an initial w before u, e or o is v (wu → vu, wo → vo, wei → vei); wa, wai, wan… stay */
    fun v(s: String): String =
        if (s.length >= 2 && (s[0] == 'w' || s[0] == 'W') && s[1] in "ueo") (if (s[0] == 'W') "V" else "v") + s.substring(1) else s

    private val zInits = listOf("zh" to "ㄓ", "ch" to "ㄔ", "sh" to "ㄕ", "ng" to "ㄫ", "nh" to "ㄬ", "ny" to "ㄬ",
        "b" to "ㄅ", "p" to "ㄆ", "m" to "ㄇ", "f" to "ㄈ", "v" to "ㄪ", "d" to "ㄉ", "t" to "ㄊ",
        "n" to "ㄋ", "l" to "ㄌ", "g" to "ㄍ", "k" to "ㄎ", "h" to "ㄏ", "j" to "ㄐ", "q" to "ㄑ",
        "x" to "ㄒ", "z" to "ㄗ", "c" to "ㄘ", "s" to "ㄙ", "r" to "ㆡ")
    private val zFinals = mapOf(
        "" to "", "a" to "ㄚ", "o" to "ㄛ", "e" to "ㆤ", "ê" to "ㆤ", "er" to "ㄦ", "ai" to "ㄞ", "ei" to "ㄟ", "ao" to "ㄠ", "ou" to "ㄜㄨ",
        "an" to "ㄢ", "en" to "ㄣ", "ang" to "ㄤ", "eng" to "ㄥ", "ong" to "ㄨㄥ", "ung" to "ㄨㄥ",
        "i" to "ㄧ", "ia" to "ㄧㄚ", "io" to "ㄧㄛ", "ie" to "ㄧㆤ", "iai" to "ㄧㄞ", "iao" to "ㄧㄠ", "iu" to "ㄧㄜㄨ", "iou" to "ㄧㄜㄨ",
        "ian" to "ㄧㄢ", "in" to "ㄧㄣ", "iang" to "ㄧㄤ", "ing" to "ㄧㄥ", "iong" to "ㄩㄥ", "iung" to "ㄩㄥ",
        "u" to "ㄨ", "ua" to "ㄨㄚ", "uo" to "ㄨㄛ", "ue" to "ㄨㆤ", "uai" to "ㄨㄞ", "ui" to "ㄨㄟ", "uei" to "ㄨㄟ", "uan" to "ㄨㄢ",
        "un" to "ㄨㄣ", "uen" to "ㄨㄣ", "uang" to "ㄨㄤ",
        "ü" to "ㄩ", "üe" to "ㄩㆤ", "üo" to "ㄩㄛ", "üan" to "ㄩㄢ", "ün" to "ㄩㄣ")

    /** a syllable in 注音 ("ce1" → "ㄘㆤ"): as 國語's, with 台語's and 客語's letters for the sounds 國語 doesn't have:
     *  ng- ㄫ, ni- ㄬ, v- ㄪ, r- ㆡ; a final e ㆤ; ou ㄜㄨ. The tones: 1 none, 2 ˨˩ (and 5), 3 ˋ, 4 ˇ */
    fun zhuyin(s0: String): String {
        val s = v(s0)
        val d = s.lastOrNull()?.digitToIntOrNull() ?: return s
        var x = s.dropLast(1).lowercase()
        x = when {
            x.startsWith("yu") -> "ü" + x.drop(2); x.startsWith("yi") -> "i" + x.drop(2); x.startsWith("y") -> "i" + x.drop(1)
            x.startsWith("wu") -> "u" + x.drop(2); x.startsWith("w") -> "u" + x.drop(1); else -> x
        }
        var ini = ""; var zi = ""; var rest = x
        for ((l, z) in zInits) if (x.startsWith(l)) { ini = l; zi = z; rest = x.drop(l.length); break }
        if (rest.startsWith("v")) rest = "ü" + rest.drop(1)
        if (ini == "n" && (rest.startsWith("i") || rest.startsWith("ü"))) zi = "ㄬ"
        if ((ini == "nh" || ini == "ny") && !(rest.startsWith("i") || rest.startsWith("ü"))) rest = "i" + rest
        if (ini in listOf("j", "q", "x") && rest.startsWith("u")) rest = "ü" + rest.drop(1)
        val f = if (rest == "i" && ini in listOf("z", "c", "s", "zh", "ch", "sh", "r")) "" else zFinals[rest] ?: return pinyin(s)
        if (ini.isEmpty() && f.isEmpty()) return pinyin(s)
        val mark = if (d == 2 || d == 5) "˨˩" else if (d == 3) "ˋ" else if (d == 4) "ˇ" else ""
        return zi + f + mark
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
        // (ü with a tone mark is a letter of its own, ǜ: v too, or 綠 lǜ was "lu" and "lv" didn't find it)
        val a = Normalizer.normalize(s.lowercase().replace("u:", "v"), Normalizer.Form.NFD).replace("u\u0308", "v")
        val n = a.filter { Character.getType(it) != Character.NON_SPACING_MARK.toInt() }
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
    /** 注音 syllables, one per 漢字 ("-" = 兒 sharing the syllable before); 瑞典語: the morphemes ("läs:r a:e") */
    var tw: List<String>,
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
    var eq: List<String> = emptyList(),
    /** 粵語: a recording of the word (Wikimedia Commons), when there is one */
    val audio: String? = null,
    /** 客語: the reading in each accent (0 四縣 … 5 南四縣; null = that accent doesn't have the word); `tw` is the
     *  one of the accent chosen */
    val acc: List<List<String>?>? = null,
    /** 客語: the accents that say it with another word (accent → word) */
    val otherWords: Map<Int, String> = emptyMap(),
    /** 日語: JMdict's codes (v1, v5k, adj-i…, "*uk" for its notes), for 活用 */
    val jp: List<String> = emptyList(),
    /** 客語: the accent chosen doesn't have the word: its reading is made character by character (fillAccent) */
    val hakGuess: Boolean = false,
) {
    fun withTw(t: List<String>, guess: Boolean) = ZhEntry(k, h, t, lu, spec, alt, senses, en, hsk, tocfl, extra, pos, syn, ant, eq,
        audio, acc, otherWords, jp, guess).also { it.exam = exam; it.sw = sw; it.oxford = oxford; it.rank = rank }
    /** the English meanings, one each (CC-CEDICT separates them with ;) */
    val enList: List<String> by lazy { (en ?: "").split(";").map { it.trim() }.filter { it.isNotEmpty() } }
    /** 四川話 (成都): the reading ("ce1 …", zh_sc.json), nil = none; how it's known (0 Wiktionary, 1 guessed, 2 predicted) */
    var sc: List<String>? = null
    var scKind = 0
    fun syl(place: Int): List<String> = if (place == 2) (sc ?: lu ?: tw) else if (place == 1) (lu ?: tw) else tw
    /** 英語: hsk is the group of how common (500 a group), tocfl the Collins level (1 ★★★★★ … 5 ★), exam the first
     *  exam list it's on (1 中考 … 7 GRE); the Swedish words, on the Oxford 3000, its rank (0 not known) */
    var exam = 0
    var sw: List<String> = emptyList()
    var oxford = false
    var rank = 0
    /** the level on a word list (0 HSK, 1 TOCFL; 英語: 0 常用度, 1 Collins, 2 考試) */
    fun level(list: Int) = if (list == 2) exam else if (list == 1) tocfl else hsk
    /** a word you added yourself (詞典 → 自訂), not from the dictionary */
    var own = false
}

/** a character with its meanings from 教育部《重編國語辭典修訂本》 (each reading: 注音, 拼音, [(詞類, meaning)]) */
class ZhChar(val h: String, val readings: List<Reading>, val hsk: Int, val tocfl: Int, val radical: String?, val strokes: Int?) {
    class Reading(val zy: String, val py: String, val defs: List<Pair<String, String>>, val label: String?)
    fun level(list: Int) = if (list == 1) tocfl else hsk
}

/** a radical and its characters (each with the strokes besides the radical), for looking a character up by its 部首 */
class ZhRadical(val radical: String, val strokes: Int, val chars: List<Pair<String, Int>>)

/** one word of a sentence: its characters and, for each character, its syllable ("_" = not a 漢字) */
class ZhPiece(val text: List<String>, val tw: List<String>?, val lu: List<String>?,
              /** 日語: the word's entry (a conjugated word: its dictionary form's), and its parts coloured */
              val e: Int? = null, val ja: List<JaPiece>? = null) {
    fun syl(place: Int): List<String>? = if (place >= 1) (lu ?: tw) else tw
}

/** accent: 客語, the accent whose readings are used */
/** (the line the entries start after, and how many lines are read in one batch) */
private const val ENTRIES = ",\"e\":["
private const val BATCH = 3000

class ZhDict(src: java.io.BufferedReader, val accent: Int = EngineSettings.hakAccent) {
    /** (from text in memory: small files, tests) */
    constructor(text: String, accent: Int = EngineSettings.hakAccent) : this(java.io.BufferedReader(java.io.StringReader(text)), accent)
    val entries: List<ZhEntry>
    /** the 粵語 dictionary (yue.json, tools/build_cantonese.py), not the 華語 one */
    var isYue = false; private set
    /** the 客語 dictionary (hak.json, tools/build_hakka.py) */
    var isHak = false; private set
    /** the 日語 dictionary (ja.json: JMdict and KANJIDIC2, made in the app by Install/japanese.js) */
    var isJa = false; private set
    /** the 瑞典語 dictionary (sv.json, Install/swedish.js; the computer version): `tw` is the word's morphemes, `eq` its
     *  forms, `jp` its Chinese meanings */
    var isSv = false; private set
    /** the 英語 dictionary (en.json, Install/english.js; isSv too, for the pages they share): `tw` is the British and
     *  the American reading in IPA ("-" for none), `jp` its Chinese meanings, `sw` its Swedish words */
    var isEn = false; private set
    /** 瑞典語: 華語 → English (CC-CEDICT, sv.json's "ce"), for looking Swedish words up in Chinese through the English */
    var svCE: Map<String, String> = emptyMap(); private set
    /** 瑞典語: words worked out by the rules, kept (the lists and sentences ask often) */
    internal val svCache = java.util.concurrent.ConcurrentHashMap<String, List<SvMorpheme>>()
    internal val svSylCache = java.util.concurrent.ConcurrentHashMap<String, List<String>>()
    /** 1 華語, 2 粵語, 3 客語, 4 日語, 5 瑞典語 */
    val lang: Int get() = if (isEn) 6 else if (isSv) 5 else if (isJa) 4 else if (isHak) 3 else if (isYue) 2 else 1
    /** 日語: each entry's reading in hiragana (for searching by the start of the reading) */
    var jaKana: List<String> = emptyList(); private set
    /** 客語: each accent's tone marks (per tone category) and each syllable's 注音 */
    var hakMarks: List<List<String>> = emptyList(); private set
    var hakZy: Map<String, String> = emptyMap(); private set
    /** 粵語: a 華語 word → the 粵語 words for it */
    val byMandarin = HashMap<String, MutableList<Int>>()
    /** 四川話: a word's reading by its 漢字 and 國語 reading ("車\tㄔㄜ" → ["ce1"]), for the sentences */
    private val scByWord = HashMap<String, List<String>>()
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
    fun borrowRadicals(zh: java.io.BufferedReader) {
        if (radicals.isNotEmpty()) { zh.close(); return }
        // (only the part before the entries is read)
        val sb = StringBuilder()
        var found = false
        zh.use { r ->
            while (true) {
                val line = r.readLine() ?: break
                if (line.endsWith(ENTRIES)) { sb.append(line, 0, line.length - ENTRIES.length); found = true; break }
                sb.append(line).append('\n')
            }
        }
        if (!found) return
        val rads = ArrayList<ZhRadical>(); val rx = HashMap<String, List<String>>()
        val j = JReader(sb.append('}').toString())
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
                "lang" -> { val l = j.nextString(); isYue = l == "yue"; isHak = l == "hak"; isJa = l == "ja"; isEn = l == "en"; isSv = l == "sv" || isEn }
                "ce" -> { val m = HashMap<String, String>(); j.obj { k -> m[k] = j.nextString() }; svCE = m }
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
                                if (isJa) py = JaKana.romaji(zy)
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
        // The file is read line by line, never whole (the big ones, 日語, would need hundreds of MB as one text):
        // the part before the entries, then the entries one per line, read in batches at the same time on all the
        // cores (a few batches at a time, so the lines don't pile up)
        val headSb = StringBuilder()
        var inEntries = false
        src.use { r ->
            while (true) {
                val line = r.readLine() ?: break
                if (line.endsWith(ENTRIES)) { headSb.append(line, 0, line.length - ENTRIES.length); inEntries = true; break }
                headSb.append(line).append('\n')
            }
            if (inEntries) {
                val hj = JReader(headSb.append('}').toString())
                headSb.setLength(0)
                hj.obj { key -> if (!head(hj, key)) hj.skip() }
                val cores = maxOf(2, Runtime.getRuntime().availableProcessors())
                val pool = java.util.concurrent.Executors.newFixedThreadPool(cores)
                try {
                    val pending = java.util.ArrayDeque<java.util.concurrent.Future<List<ZhEntry>>>()
                    var batch = ArrayList<String>(BATCH)
                    fun flush() {
                        if (batch.isEmpty()) return
                        val b = batch
                        batch = ArrayList(BATCH)
                        pending.add(pool.submit<List<ZhEntry>> {
                            val l = ArrayList<ZhEntry>(b.size)
                            for (raw in b) {
                                val line = raw.trimEnd().removeSuffix(",")
                                if (line.isEmpty()) continue
                                readEntry(JReader(line))?.let { l.add(it) }
                            }
                            l
                        })
                        while (pending.size > cores * 2) out.addAll(pending.poll()!!.get())
                    }
                    while (true) {
                        val line = r.readLine() ?: break
                        if (line.startsWith("]}")) break
                        batch.add(line)
                        if (batch.size >= BATCH) flush()
                    }
                    flush()
                    while (pending.isNotEmpty()) out.addAll(pending.poll()!!.get())
                } finally { pool.shutdown() }
            } else {
                // (an older file, not one entry per line: read whole)
                val j = JReader(headSb.toString())
                headSb.setLength(0)
                j.obj { key ->
                    if (key == "e") j.arr { readEntry(j)?.let { out.add(it) } }
                    else if (!head(j, key)) j.skip()
                }
            }
        }
        chars = cs
        for ((i, c) in cs.withIndex()) charIndex[c.h] = i
        radicals = rads
        radicalInside = rx
        for (r in rads) for ((ch, rest) in r.chars) if (!strokesOf.containsKey(ch)) strokesOf[ch] = r.strokes + rest
        // 客語: a word the accent chosen doesn't have (惜圓): each character read the way this accent reads it
        if (isHak) fillAccent(out)
        val dictCount = out.size
        // 華語: an HSK word the 兩岸 dictionary doesn't have: its characters in their Taiwan readings
        if (!isYue && !isHak && !isJa && !isSv) { fillTaiwan(out); addSichuan(out) }
        // your own words (詞典 → 自訂), after the dictionary's (so they're never study cards)
        for (w in ZhOwnWords.words[lang] ?: emptyList()) {
            if (w.h.isEmpty() || w.tw.isEmpty()) continue
            val ex = if (w.example.isEmpty()) emptyList() else listOf(ZhEx(w.example, "", ""))
            // (瑞典語, 英語: a meaning in Chinese is the word's Chinese meaning, so searching it in Chinese finds it)
            val zhMeaning = lang >= 5 && w.meaning.codePoints().anyMatch { Zhuyin.isHan(it) }
            out.add(ZhEntry(w.key, w.h, w.tw, null, 0, null, listOf(ZhSense(1, w.meaning.ifEmpty { "（自己加的詞）" }, ex)), null, 0, 0, false,
                jp = if (zhMeaning) listOf(w.meaning) else emptyList()).also { it.own = true })
        }
        entries = out
        Simp.learn(out.map { e -> e.h to (e.alt ?: e.h) })
        for ((i, e) in out.withIndex()) for (m in e.eq) { val l = byMandarin.getOrPut(m) { ArrayList() }; if (l.lastOrNull() != i) l.add(i) }
        cardCount = if (nc > 0) nc else dictCount
        var m = 1
        val jk = if (isJa) ArrayList<String>(out.size) else null
        for ((i, e) in out.withIndex()) {
            index[e.k] = i
            byHan.getOrPut(e.h) { ArrayList() }.add(i)
            if (e.alt != null && e.alt != e.h) byHan.getOrPut(e.alt) { ArrayList() }.add(i)
            m = maxOf(m, e.h.codePointCount(0, e.h.length))
            // 瑞典語: the word and its forms, in small letters (bil, bilen, bilar)
            if (isSv) {
                add(byPlain, e.h.lowercase(), i)
                for (o in e.eq) add(byPlain, o.lowercase(), i)
                continue
            }
            if (jk != null) {
                // 日語: by the reading in hiragana and in rōmaji, and by the other spellings
                val kana = JaKana.hiragana(e.tw.joinToString(""))
                jk.add(kana)
                add(byPlain, kana, i)
                add(byPlain, JaKana.romaji(kana).filter { it.isLetter() }, i)
                for (o in e.eq) { byHan.getOrPut(o) { ArrayList() }.add(i); add(byPlain, JaKana.hiragana(o), i) }
                continue
            }
            for (syl in listOfNotNull(e.tw, e.lu, e.sc)) {
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
        if (jk != null) jaKana = jk
        // 瑞典語: comparatives (sen|are) and phrases (hitta på) as their parts
        if (isSv && !isEn) svFix(out, byPlain)
    }

    /** 客語: a word the accent chosen doesn't have is shown in another accent's reading (`tw` is the first accent that
     *  has it). Instead, each character gets the reading this accent has for it: from the words both accents have,
     *  "惜 in 四縣 siag is xiag in this accent" (the most common one when there are several). A character no word tells
     *  keeps the other accent's reading. */
    private fun fillAccent(out: MutableList<ZhEntry>) {
        val map = HashMap<String, HashMap<String, Int>>()
        fun chars(h: String) = h.cps().filter { Zhuyin.isHan(it.firstCp()) }
        for (e in out) {
            val acc = e.acc ?: continue
            val mine = acc.getOrNull(accent) ?: continue
            val cs = chars(e.h)
            if (cs.size != mine.size) continue
            for ((a, other) in acc.withIndex()) {
                if (a == accent || other == null || other.size != cs.size) continue
                for (i in cs.indices) { val m = map.getOrPut("$a\u0001${cs[i]}\u0001${other[i]}") { HashMap() }; m[mine[i]] = (m[mine[i]] ?: 0) + 1 }
            }
        }
        for (i in out.indices) {
            val acc = out[i].acc ?: continue
            if (accent >= acc.size || acc[accent] != null) continue
            val cs = chars(out[i].h)
            val tw = out[i].tw.toMutableList()
            if (cs.size != tw.size) continue
            var changed = false
            for (n in cs.indices) {
                if (!Zhuyin.isHak(tw[n])) continue
                val a = Zhuyin.hakParts(tw[n]).third
                val hits = map["$a\u0001${cs[n]}\u0001${tw[n]}"] ?: continue
                val best = hits.entries.sortedWith(compareBy<Map.Entry<String, Int>>({ -it.value }, { it.key })).firstOrNull()?.key ?: continue
                tw[n] = best; changed = true
            }
            if (changed) out[i] = out[i].withTw(tw, true)
        }
    }

    /** two readings of one character that are the same word said two ways (擊 jí / jī, 垃 lè / lā): the same letters
     *  at the start, or the same at the end; not two different words (台 tái / yí) */
    private fun alike(a: String, b: String): Boolean {
        val p = Zhuyin.plainSyllable(a); val q = Zhuyin.plainSyllable(b)
        if (p == q) return true
        val vowels = "aeiouvü"
        val ia = p.takeWhile { it !in vowels }; val ib = q.takeWhile { it !in vowels }
        val fa = p.drop(ia.length); val fb = q.drop(ib.length)
        return (ia.isNotEmpty() && ia == ib) || (fa.isNotEmpty() && fa == fb)
    }

    /** 華語: an HSK word the 兩岸 dictionary doesn't have (extra) has CC-CEDICT's mainland reading: each character
     *  gets its Taiwan one, where the dictionary says that character is said another way in 大陸 (擊 ㄐㄧˊ, 大陸 ㄐㄧ)
     *  and the two are alike; the mainland reading is kept as 大陸's. A reading the character also has in Taiwan
     *  stays (比比皆是's 比 ㄅㄧˇ). */
    private fun fillTaiwan(out: MutableList<ZhEntry>) {
        val map = HashMap<String, HashSet<String>>(); val own = HashMap<String, HashSet<String>>()
        for (e in out) {
            if (e.extra || e.tw.size != 1 || e.h.codePointCount(0, e.h.length) != 1) continue
            val t = e.tw[0]
            // (a character's readings under its simplified form too: 臺 ㄊㄞˊ is also 台's, so 電台 keeps ㄊㄞˊ)
            for (c in setOfNotNull(e.h, e.alt)) {
                own.getOrPut(c) { HashSet() }.add(t)
                // (only a reading the dictionary says is said another way in 大陸)
                val m = e.lu?.firstOrNull()
                if (m != null && m != t) map.getOrPut(c + "\u0001" + m) { HashSet() }.add(t)
            }
        }
        for (i in out.indices) {
            val e = out[i]
            if (!e.extra) continue
            val cs = e.h.cps()
            val tw = e.tw.toMutableList()
            if (cs.size != tw.size) continue
            var changed = false
            for (n in cs.indices) {
                val syl = tw[n]
                if (own[cs[n]]?.contains(syl) == true) continue
                val ts = map[cs[n] + "\u0001" + syl] ?: continue
                if (ts.size != 1) continue
                val t = ts.first()
                if (t == syl || !alike(t, syl)) continue
                tw[n] = t; changed = true
            }
            if (!changed) continue
            out[i] = ZhEntry(e.k, e.h, tw, e.lu ?: e.tw, e.spec, e.alt, e.senses, e.en, e.hsk, e.tocfl, e.extra, e.pos, e.syn, e.ant,
                e.eq, e.audio, e.acc, e.otherWords, e.jp, e.hakGuess)
        }
    }

    /** 華語: the 四川話 readings of zh_sc.json; then 四川話's own words, after the dictionary's (so they're never study
     *  cards); and the 華語 words for the dictionary's words that 成都 says */
    private fun addSichuan(out: MutableList<ZhEntry>) {
        val sd = Sichuan.data()
        if (sd.readings.isEmpty()) return
        for (e in out) {
            val (s, kind) = sd.readings[e.k] ?: continue
            val sy = s.split(" ")
            if (sy.size == e.tw.size && sy.all { Zhuyin.isJyut(it) }) {
                e.sc = sy; e.scKind = kind
                scByWord[e.h + "\t" + e.tw.joinToString(" ")] = sy
            }
        }
        if (sd.eq.isNotEmpty()) for (e in out) sd.eq[e.h]?.let { e.eq = it }
        for (w in sd.words) {
            val sy = w.s.split(" "); val tw = w.z.split(" ")
            if (sy.size != tw.size || !sy.all { Zhuyin.isJyut(it) }) continue
            val text = if (w.m.isEmpty()) "四川話的詞。" else "四川話，意思同「" + w.m.take(3).joinToString("」、「") + "」。"
            val e = ZhEntry(w.h + "\t" + w.z + "#川", w.h, tw, null, Sichuan.spec, null, listOf(ZhSense(1, text, emptyList())),
                if (w.e.isEmpty()) null else w.e.joinToString("; ") { it.replace(";", ",") }, 0, 0, false, eq = w.m)
            e.sc = sy; e.scKind = w.k
            out.add(e)
        }
    }

    /** a word of a sentence's syllables (四川話: the dictionary word's 四川話 reading, when it has one) */
    fun pieceSyl(p: ZhPiece, place: Int): List<String>? {
        if (place == 2) p.tw?.let { tw -> scByWord[p.text.joinToString("") + "\t" + tw.joinToString(" ")]?.let { return it } }
        return p.syl(place)
    }

    /** 四川話's own words, those with a reading from Wiktionary first (then the guessed, then the predicted) */
    val sichuanWords: List<Int> by lazy {
        entries.indices.filter { entries[it].spec == Sichuan.spec }.sortedWith(compareBy({ entries[it].scKind }, { it }))
    }

    /** one entry of zh.json */
    private fun readEntry(j: JReader): ZhEntry? {
        var k = ""; var h = ""; var s = ""; var l: String? = null; var p = 0; var a: String? = null
        var en: String? = null; var x = 0; var y = 0; var q = 0
        var w: List<String> = emptyList(); var sy: List<String> = emptyList(); var an: List<String> = emptyList()
        var eq: List<String> = emptyList(); var u: String? = null
        var g = 0; var rk = 0; var ox = 0; var sw: List<String> = emptyList()
        var acc: List<List<String>?>? = null; val others = HashMap<Int, String>(); var jp: List<String> = emptyList()
        val senses = ArrayList<ZhSense>()
        j.obj { f ->
            when (f) {
                "k" -> k = j.nextString(); "h" -> h = j.nextString(); "s" -> s = j.nextString()
                "l" -> l = j.nextString(); "p" -> p = j.nextInt(); "a" -> a = j.nextString()
                "n" -> en = j.nextString(); "x" -> x = j.nextInt(); "y" -> y = j.nextInt(); "q" -> q = j.nextInt()
                "w" -> w = j.strList(); "j" -> sy = j.strList(); "f" -> an = j.strList()
                "m" -> eq = j.strList(); "u" -> u = j.nextString(); "jp" -> jp = j.strList()
                // 英語: g the group of how common, r its rank, ox on the Oxford 3000, sw the Swedish words
                "g" -> g = j.nextInt(); "r" -> rk = j.nextInt(); "ox" -> ox = j.nextInt(); "sw" -> sw = j.strList()
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
        // 英語: hsk is the group of how common, tocfl the Collins level, exam the exam list
        if (Lang.isEnKey(k)) return ZhEntry(k, h, tw, null, 0, null, senses, en, g, x, false, w, sy, an, eq, u, null, emptyMap(), jp)
            .also { it.exam = y; it.sw = sw; it.oxford = ox == 1; it.rank = rk }
        return ZhEntry(k, h, tw, l?.split(" "), p, a, senses, en, x, y, q == 1, w, sy, an, eq, u, acc, others, jp)
    }

    private fun add(d: HashMap<String, MutableList<Int>>, k: String, i: Int) {
        val l = d.getOrPut(k) { ArrayList() }
        if (l.lastOrNull() != i) l.add(i)
    }

    fun entry(k: String): ZhEntry? = index[k]?.let { entries[it] }
    /** whether the dictionary has the word (as written; 瑞典語 / 英語: in small letters, or one of its forms) */
    fun has(w: String): Boolean = wordIndices(w).isNotEmpty()
    /** the entries of a word (as written, or in 正體; 瑞典語 / 英語: in small letters, or the word it's a form of: ran → run) */
    fun wordIndices(w: String): List<Int> {
        byHan[w]?.let { return it }
        byHan[buildString { w.codePoints().forEach { appendCodePoint(Simp.reverse(it) ?: it) } }]?.let { return it }
        if (isSv) {
            byPlain[w.lowercase()]?.let { return it }
            svKey(w)?.let { k -> index[k]?.let { return listOf(it) } }
        }
        return emptyList()
    }
    fun others(e: ZhEntry): List<ZhEntry> = (byHan[e.h] ?: emptyList<Int>()).map { entries[it] }.filter { it.k != e.k && it.h == e.h }

    // MARK: readings

    /** a word's reading: 0 = 拼音, 1 = 注音; in tone colours when they're on */
    fun reading(syl: List<String>, mode: Int, colours: Int = EngineSettings.toneSystem): Styled {
        // 英語: the IPA, British and American as 設定 → 英語 says (whatever the mode)
        if (isEn) return styled(enIpa(syl))
        // 瑞典語: the morphemes with a hyphen between them (be-tal-a), each in its colour (1: nothing)
        if (isSv) {
            if (mode != 0) return emptyList()
            val ms = SvMorpheme.parse(syl)
            if (ms.size <= 1) return emptyList()
            return SvColors.hyphened(ms, null, colours != 0, 0xB38E8E93.toInt())
        }
        if (isJa) {
            // 日語: 0 = rōmaji, 1 = kana (in the script colours when colours are on)
            val kana = syl.filter { it != "-" && it != "_" }.joinToString("")
            if (mode == 0) return styled(JaKana.romaji(kana))
            return if (colours != 0) JaInk.word(kana) else styled(kana)
        }
        val b = StyledBuilder()
        var first = true
        val hak = hakTints(syl, colours)
        for ((si, s) in syl.withIndex()) {
            if (s == "-" || s == "_") continue
            val t = if (Zhuyin.isHak(s)) (if (first) "" else " ") + hakSyllable(s, mode)
            // 四川話: 四川話拼音 with the tone on the vowel ("cē"), or 注音 ("ㄘㆤ")
            else if (Zhuyin.isJyut(s) && !isYue) (if (mode == 1) (if (first) "" else "\u2009") + Sichuan.zhuyin(s) else (if (first) "" else " ") + Sichuan.pinyin(s))
            else if (Zhuyin.isJyut(s)) (if (first) "" else " ") + (if (mode == 1) Yale.of(s) else s)
            else if (mode == 1) (if (first) "" else " ") + s else {
                val p = Zhuyin.pinyin(s)
                (if (!first && p.isNotEmpty() && p[0] in "aāáǎàoōóǒòeēéěèê") "'" else "") + p
            }
            b.add(t, hak?.get(si) ?: Zhuyin.color(Zhuyin.tone(s), colours, isYue, isHak))
            first = false
        }
        return b.build()
    }

    /** 客語: each syllable's colour by the pitch it's said in within the word (the accent's tone changes, HakSandhi) */
    private fun hakTints(syl: List<String>, colours: Int): Map<Int, Int>? {
        if (!isHak || colours == 0) return null
        val idx = syl.indices.filter { Zhuyin.isHak(syl[it]) }
        val first = idx.firstOrNull() ?: return null
        val accent = Zhuyin.hakParts(syl[first]).third
        val parts = idx.map { i ->
            val p = Zhuyin.hakParts(syl[i]); val l = p.first
            p.second to ((l.lastOrNull()?.let { it in "bdg" } ?: false) && !l.endsWith("ng"))
        }
        val ps = HakSandhi.pitches(parts, accent)
        val out = HashMap<Int, Int>()
        for ((n, i) in idx.withIndex()) {
            val p = ps[n] ?: continue
            ToneColors.hakPitchColor(p.first, p.second, colours != 5)?.let { out[i] = it }
        }
        return out
    }

    /** one 客語 syllable as it's shown: 拼音 (0) or 注音 (1), then its accent's tone mark ("bauˊ", "ㄅㄠˊ") */
    fun hakSyllable(s: String, mode: Int): String {
        val (letters, t, a) = Zhuyin.hakParts(s)
        val mark = hakMarks.getOrNull(a)?.getOrNull(t) ?: ""
        return (if (mode == 1) hakZhuyin(letters, t) ?: hakZy[letters] ?: letters else letters) + mark
    }

    private val hakIni = listOf("zh" to "ㄓ", "ch" to "ㄔ", "sh" to "ㄕ", "rh" to "ㄖ", "ng" to "ㄫ", "bb" to "ㆠ",
        "b" to "ㄅ", "p" to "ㄆ", "m" to "ㄇ", "f" to "ㄈ", "v" to "ㄪ", "d" to "ㄉ", "t" to "ㄊ", "n" to "ㄋ", "l" to "ㄌ", "g" to "ㄍ",
        "k" to "ㄎ", "h" to "ㄏ", "z" to "ㄗ", "c" to "ㄘ", "s" to "ㄙ", "j" to "ㄐ", "q" to "ㄑ", "x" to "ㄒ")
    private val hakFin = listOf("ang" to "ㄤ", "ai" to "ㄞ", "au" to "ㄠ", "an" to "ㄢ", "ien" to "ㄧㄢ", "ii" to "ㄭ",
        "ee" to "ㆤ", "oo" to "ㆦ", "er" to "ㄜ", "nn" to "ⁿ", "ng" to "ㄥ", "a" to "ㄚ", "e" to "ㄝ", "i" to "ㄧ", "o" to "ㄛ",
        "u" to "ㄨ", "m" to "ㄇ", "n" to "ㄣ")

    /** a 客語 syllable in 臺灣方音符號 (the dictionary file's table was made when it was installed; these rules on top):
     *  ii ㄭ; m by itself ㆬ, ng by itself ㆭ; the 入聲 endings b d g are ㆴ ㆵ ㆻ, with a dot over them in 陽入
     *  (ㆴ̇ ㆵ̇ ㆻ̇), not ㄅ ㄉ ㄍ */
    fun hakZhuyin(letters: String, tone: Int): String? {
        if (letters == "m") return "ㆬ"
        if (letters == "ng") return "ㆭ"
        var rest = letters
        var out = ""
        var stop = ""
        val l = rest.lastOrNull()
        if (l != null && l in "bdg" && rest.length > 1) {
            stop = when (l) { 'b' -> "ㆴ"; 'd' -> "ㆵ"; else -> "ㆻ" }
            if (tone == 8) stop += "\u0307"
            rest = rest.dropLast(1)
        }
        hakIni.firstOrNull { rest.startsWith(it.first) && rest.length > it.first.length }?.let { out = it.second; rest = rest.drop(it.first.length) }
        while (rest.isNotEmpty()) {
            val m = hakFin.firstOrNull { rest.startsWith(it.first) } ?: return null
            out += m.second; rest = rest.drop(m.first.length)
        }
        return out + stop
    }

    fun readingPlain(syl: List<String>, mode: Int): String = reading(syl, mode, 0).plain()

    /** 英語: a word's readings ([British, American], "-" for none) as 設定 → 英語 → 讀音 says: "UK /…/ · US /…/" */
    fun enIpa(syl: List<String>): String {
        val uk = syl.getOrNull(0)?.takeIf { it != "-" && it.isNotEmpty() }
        val us = syl.getOrNull(1)?.takeIf { it != "-" && it.isNotEmpty() }
        return when (EngineSettings.enRom) {
            1 -> (us ?: uk)?.let { "/$it/" } ?: ""
            2 -> (uk ?: us)?.let { "/$it/" } ?: ""
            3 -> ""
            else -> if (uk != null && us != null && uk != us) "UK /$uk/ · US /$us/" else (uk ?: us)?.let { "/$it/" } ?: ""
        }
    }

    /** 漢字 in tone colours (one syllable per 漢字; 兒 after -ㄦ takes the colour before it) */
    fun hanText(han: String, syl: List<String>, base: Int?, colours: Int = EngineSettings.toneSystem): Styled {
        // 英語: the word as it is
        if (isEn) return styled(han, base)
        // 瑞典語: each morpheme in its colour (the root, a prefix, a suffix, the linking letter, the ending)
        if (isSv) {
            var ms = SvMorpheme.parse(syl)
            if (colours != 0 && ms.size <= 1) { val w = SvMorpheme.parse(svWordSyl(han)); if (w.size > 1) ms = w }
            if (colours == 0 || ms.size <= 1 || ms.joinToString("") { it.text } != han) return styled(han, base)
            return SvColors.styledOf(ms, base, true)
        }
        val b = StyledBuilder()
        if (isJa) {
            // 日語: kanji, hiragana and katakana each in their colour
            for (ch in han.cps()) b.add(ch, if (colours != 0) (JaColors.of(ch) ?: base) else base)
            return b.build()
        }
        var i = 0; var last = 1
        val hak = hakTints(syl, colours)
        var lastHak: Int? = null
        for (ch in Simp.show(han).cps()) {
            if (Zhuyin.isHan(ch.firstCp()) && i < syl.size) {
                val s = syl[i]; i++
                val t = if (s == "-") last else Zhuyin.tone(s)
                last = t
                if (s != "-") lastHak = hak?.get(i - 1)
                b.add(ch, lastHak ?: Zhuyin.color(t, colours, isYue, isHak) ?: base)
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
            val syl = pieceSyl(p, place)
            // (日語 in rōmaji: the particles は, へ, を said wa, e, o)
            if (isJa && mode == 0 && syl != null && p.ja?.singleOrNull()?.kind == JaPiece.Kind.PARTICLE) {
                val said = mapOf("は" to "wa", "へ" to "e", "を" to "o")[p.text.joinToString("")]
                if (said != null) { if (prevWord) put(" "); for (seg in styled(said)) put(seg.t, seg.c); prevWord = true; continue }
            }
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
        if (isJa) {
            // 日語: as in the dictionary: kanji, hiragana and katakana each in their colour, particles and the
            // conjugated endings in theirs
            for (p in ps) {
                val t = p.text.joinToString("")
                if (blank != null && t == blank) { b.add("＿＿", base); continue }
                if (colours == 0) { b.add(t, base); continue }
                for (seg in JaInk.styled(p.ja ?: listOf(JaPiece(t, JaPiece.Kind.WORD)), base)) b.add(seg.t, seg.c)
            }
            return b.build()
        }
        for (p in ps) {
            if (blank != null && p.text.joinToString("") == blank) { b.add("＿＿", base); continue }
            var last = 1
            val syl = pieceSyl(p, place)
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
        val defs0 = e.senses.map { s ->
            Def("", s.text, s.ex.map { x ->
                // (客語: the sentences aren't split into words, they're written for the word; no voice reads them)
                val blankable = x.h != e.h && x.h.contains(e.h) && (isHak || isSv || pieces(x).any { it.text.joinToString("") == e.h })
                Example(Simp.show(x.h), listOf(""), x.src, if (isHak) "" else "tts:" + x.h,
                    if (blankable) Simp.show(x.h.replace(e.h, "＿＿")) else null, if (blankable) listOf("") else null, x.code.ifEmpty { null })
            })
        }
        // 瑞典語: the Chinese meanings (when there are) before the English ones
        val zh = if (isSv) e.svZh else emptyList()
        // (只有中文: the English meanings' sentences kept, without the English)
        val defs1 = if (isSv && e.svHideEnglish) defs0.map { Def(it.p, "", it.x) }.filter { it.x.isNotEmpty() } else defs0
        var defs = if (zh.isNotEmpty()) listOf(Def(if (e.svZhGuessed) "中≈" else "中", zh.joinToString(if (isEn) "；" else "、"), emptyList())) + defs1 else defs1
        // 英語: the Swedish words after the Chinese
        if (isEn && e.enSv.isNotEmpty()) defs = defs.toMutableList().also { it.add(if (zh.isEmpty()) 0 else 1, Def("瑞", e.enSv.joinToString("、"), emptyList())) }
        if (defs.isEmpty()) defs = defs0
        val variant = e.lu?.let { lu -> mapOf("1" to Variant(listOf(readingPlain(lu, 0)), readingPlain(lu, 1))) }
        val lvl = e.level(list)
        return Card(e.k, Simp.show(e.h), listOf(readingPlain(e.tw, 0)), if (isEn) "" else readingPlain(e.tw, 1), null, "", defs,
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
        return Card(Lang.charKey(c.h, isYue, isHak, isJa), Simp.show(c.h), listOf(if (isHak) readingPlain(listOf(main.zy), 0) else main.py),
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
        /** 瑞典語: a compound the dictionary doesn't have, in its parts */
        var svEst: SvEstimate? = null
        /** 瑞典語: words found through the English of a 華語 word (汽車 → car → bil), and that English */
        val svVia = ArrayList<Int>()
        var svViaEnglish = ""
        /** 瑞典語, 英語: no word found as it was searched (only a compound worked out, or words with it inside): Gemini is
         *  asked too */
        /** only your own words found, nothing of the dictionary's (Gemini is asked too) */
        var onlyOwn = false
        val weak: Boolean get() = words.isEmpty() && starts.isEmpty() && svVia.isEmpty() && mandarin.isEmpty() && defs.isEmpty() && english.isEmpty() && parts.isEmpty() && tones.isEmpty()
        val empty: Boolean get() = svEst == null && svVia.isEmpty() && mandarin.isEmpty() && parts.isEmpty() && words.isEmpty() && starts.isEmpty() && contains.isEmpty() && defs.isEmpty() && english.isEmpty() && tones.isEmpty()
    }

    fun toneDigits(e: ZhEntry, place: Int): String =
        e.syl(place).filter { it != "-" && it != "_" }.joinToString("") { Zhuyin.tone(it).toString() }

    /** (設定 → 詞典 → 搜尋結果的順序: 自己排) */
    /** your own words (自訂) whose word or meaning has the search (as typed, or in small letters): listed first, so a
     *  word you added always shows */
    fun ownHits(q0: String): List<Int> {
        val q = q0.trim()
        if (q.isEmpty() || q.any { it in "*＊?？" } || Regex("^[0-9\\s-]+$").matches(q)) return emptyList()
        val low = q.lowercase()
        val out = ArrayList<Int>()
        var i = entries.size - 1
        while (i >= 0 && entries[i].own) {
            val e = entries[i]
            if (e.h.lowercase().contains(low) || (e.alt?.contains(q) == true) || e.senses.any { it.text.lowercase().contains(low) }
                || e.jp.any { it.contains(q) } || (e.en?.lowercase()?.contains(low) == true)) out.add(i)
            i--
        }
        return out.reversed()
    }

    fun search(q0: String, place: Int = 0): Found {
        val f = searchSorted(q0, place)
        withOwn(f, q0)
        val all = f.words + f.starts + f.contains + f.defs + f.english + f.mandarin + f.svVia + f.tones + f.partWords.flatten()
        f.onlyOwn = all.isNotEmpty() && all.all { it < entries.size && entries[it].own } && f.svEst == null
        return f
    }

    private fun withOwn(f: Found, q0: String) {
        // (one found already stays in its place, moved to the front of its list; the others go first in 「…」)
        val own = ownHits(q0)
        if (own.isEmpty()) return
        val s = own.toSet()
        for (l in listOf(f.words, f.english, f.svVia, f.mandarin, f.starts, f.contains, f.defs)) {
            val mine = l.filter { it in s }; if (mine.isEmpty()) continue
            val others = l.filter { it !in s }; l.clear(); l.addAll(mine + others)
        }
        val shown = (f.words + f.english + f.svVia + f.mandarin + f.starts + f.contains + f.defs + f.tones).toSet()
        val rest = own.filter { it !in shown }
        if (rest.isNotEmpty()) f.words.addAll(0, rest)
    }

    private fun searchSorted(q0: String, place: Int = 0): Found {
        val f = search0(q0, place)
        // (四川話's own words: only when 讀音 is 四川話)
        if (lang == 1 && place != 2 && sichuanWords.isNotEmpty()) {
            val drop: (Int) -> Boolean = { entries[it].spec == Sichuan.spec }
            for (l in listOf(f.words, f.starts, f.contains, f.defs, f.english, f.tones)) l.removeAll(drop)
            f.partWords = f.partWords.map { l -> l.filterNot(drop) }
        }
        if (EngineSettings.searchOrder.isEmpty()) return f
        val q = q0.trim()
        val m: (String, Int) -> Double = { k, i ->
            val e = entries[i]
            when (k) {
                "freq" -> i.toDouble()
                "exact" -> if (e.h == q || e.alt == q || (e.senses.firstOrNull()?.text?.substringBefore("。") ?: "") == q) 0.0 else 1.0
                "short" -> e.h.codePointCount(0, e.h.length).toDouble()
                "level" -> { val l = if (EngineSettings.zhList == 1) e.tocfl else e.hsk; if (l > 0) l.toDouble() else 99.0 }
                else -> 0.0
            }
        }
        for (list in listOf(f.words, f.starts, f.contains, f.defs, f.english, f.mandarin)) {
            val sorted = SearchOrder.sort(list.toList(), m)
            list.clear(); list.addAll(sorted)
        }
        return f
    }

    private fun search0(q0: String, place: Int = 0): Found {
        val q = q0.trim()
        val f = Found()
        if (q.isEmpty()) return f
        if (isJa && !q.any { it in "*?＊？" }) return searchJa(q)
        if (isSv && !q.any { it in "*?＊？" }) return searchSv(q)
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
        if (isYue || (lang == 1 && place == 2)) byMandarin[q]?.let { f.mandarin.addAll(it) }
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

    /** 日語: the word itself (kanji, kana or rōmaji), the dictionary forms of a conjugated word (食べなかった →
     *  食べる), words that start with it, words with it inside, and English */
    /** 瑞典語: the entries of a word or one of its forms (bilarna → bil) */
    fun svIndices(word: String): List<Int> = byPlain[word.lowercase()] ?: emptyList()

    /** 瑞典語: the word or one of its forms (bilarna → bil), words that start with it, words with it inside, English,
     *  and the Chinese meanings (汽車 → bil) */
    private fun searchSv(q: String): Found {
        val f = Found()
        val seen = HashSet<Int>()
        fun take(l: List<Int>): List<Int> = l.sorted().filter { seen.add(it) }
        val low = q.lowercase()
        SvVia.found = emptyMap()
        if (q.cps().any { Zhuyin.isHan(it.firstCp()) }) {
            // Chinese: the words with it in their Chinese meanings (the ones that are just it first)
            val exact = ArrayList<Int>(); val inside = ArrayList<Int>()
            val seps = Regex("[、，,；;]")
            // (英語: the Chinese lines start with the class, "n. 跑、賽跑")
            val cls = Regex("^\\s*([a-z]+\\.\\s*)+")
            fun bare(p: String) = if (isEn) p.trim().replace(cls, "") else p.trim()
            for ((i, e) in entries.withIndex()) {
                val zh = e.svZhAll
                if (!zh.any { it.contains(q) }) continue
                if (zh.any { it == q || it.split(seps).any { p -> bare(p) == q } }) exact.add(i) else if (inside.size < 200) inside.add(i)
            }
            f.english.addAll(take(exact)); f.english.addAll(take(inside))
            f.englishFirst = true
            // 華語 → English → 瑞典語 (汽車 → car → bil): marked as guessed
            svCE[q]?.let { en ->
                val terms = ArrayList<String>()
                for (t in en.split("; ")) { val x = if (t.startsWith("to ")) t.drop(3) else t; if (x.isNotEmpty() && x !in terms) terms.add(x) }
                val via = ArrayList<Int>()
                for (t in terms.take(3)) via.addAll(englishHits(t).first.take(15))
                f.svVia.addAll(take(via))
                f.svViaEnglish = terms.take(3).joinToString("; ")
                val note = SvVia(q, f.svViaEnglish)
                val direct = f.english.map { entries[it].k }.toSet()
                SvVia.found = f.svVia.filter { entries[it].k !in direct }.associate { entries[it].k to note }
            }
            return f
        }
        f.words.addAll(take(byPlain[low] ?: emptyList()))
        // 英語: the words whose Swedish is it (springa → run)
        if (isEn) {
            val sv = ArrayList<Int>()
            for ((i, e) in entries.withIndex()) if (e.sw.any { it.lowercase() == low }) { sv.add(i); if (sv.size >= 60) break }
            f.svVia.addAll(take(sv))
        }
        // (a form the dictionary doesn't list: its word; a compound it doesn't have: its parts)
        if (!isEn && f.words.isEmpty()) svEstimate(q.trim())?.let { est ->
            f.svEst = est
            if (est.parts.size == 1) est.parts[0].entry?.let { f.words.addAll(take(listOf(it))) }
        }
        if (!isEn && f.words.isEmpty() && f.svEst == null) svInflected(low)?.let { f.words.addAll(take(listOf(it))) }
        val starts = ArrayList<Int>(); val inside = ArrayList<Int>()
        for ((i, e) in entries.withIndex()) {
            if (i in seen) continue
            val h = e.h.lowercase()
            if (h.startsWith(low)) { if (starts.size < 150) starts.add(i) }
            else if (low.length >= 3 && h.contains(low) && inside.size < 150) inside.add(i)
            if (starts.size >= 150 && inside.size >= 150) break
        }
        f.starts.addAll(take(starts)); f.contains.addAll(take(inside))
        if (low.length >= 2) {
            val (list, best) = englishHits(q)
            f.english.addAll(list.filter { it !in seen })
            f.englishFirst = best <= 1 && (f.words.isEmpty() || best == 0)
        }
        return f
    }

    private fun searchJa(q: String): Found {
        val f = Found()
        val seen = HashSet<Int>()
        fun take(l: List<Int>): List<Int> = l.sorted().filter { seen.add(it) }
        val latin = q.all { it.code < 128 }
        val letters = q.lowercase().filter { it.isLetter() }
        var kana = JaKana.hiragana(q)
        val fromRom = if (latin) JaKana.fromRomaji(letters) else null
        if (fromRom != null) kana = fromRom
        val exact = ArrayList<Int>()
        byHan[q]?.let { exact.addAll(it) }
        byPlain[kana]?.let { exact.addAll(it) }
        if (latin) byPlain[letters]?.let { exact.addAll(it) }
        f.words.addAll(take(exact))
        val forms = ArrayList<Int>()
        for (key in setOf(q, kana)) {
            for ((base, _) in JaGrammar.deinflect(key)) {
                for (i in (byHan[base] ?: emptyList<Int>()) + (byPlain[base] ?: emptyList())) if (JaGrammar.classOf(entries[i]) != null) forms.add(i)
            }
        }
        f.words.addAll(take(forms))
        // (a whole sentence, or several words: each word, conjugated ones by their dictionary form)
        if (f.words.isEmpty() && !latin && q.cps().size >= 3) {
            val segs = jaSegments(q).filter { it.text.isNotBlank() }
            if (segs.size >= 2 && segs.count { it.entry != null } >= 2) {
                f.parts = segs.map { it.text }
                f.partWords = segs.map { g -> listOfNotNull(g.entry) }
                return f
            }
        }
        if (!latin || fromRom != null) {
            val starts = ArrayList<Int>(); val inside = ArrayList<Int>()
            for ((i, e) in entries.withIndex()) {
                if (seen.contains(i)) continue
                val r = jaKana.getOrElse(i) { "" }
                if (e.h.startsWith(q) || (kana.isNotEmpty() && r.startsWith(kana))) {
                    if (starts.size < 150) starts.add(i)
                } else if (!latin && e.h.contains(q) && inside.size < 150) inside.add(i)
                if (starts.size >= 150 && (latin || inside.size >= 150)) break
            }
            f.starts.addAll(take(starts))
            f.contains.addAll(take(inside))
        }
        if (latin && letters.isNotEmpty()) {
            val (list, best) = englishHits(q)
            f.english.addAll(list)
            f.englishFirst = best <= 1 && (f.words.isEmpty() || best == 0)
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
        entries.map { e -> (if (isYue) e.senses.joinToString(";") { it.text } + ";" + (e.en ?: "") else (e.en ?: "")).enFold() }
    }
    /** (made ahead of the first English search, when the dictionary page opens) */
    fun warmEnglish() { englishTexts.size }

    /** (and how close the best one is: 0 = a meaning that's exactly the words) */
    fun englishHits(q0: String): Pair<List<Int>, Int> {
        val q = q0.enFold().trim()
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
        p.e?.let { return entries.getOrNull(it) }
        val text = p.text.joinToString("")
        val cands = (byHan[text] ?: emptyList<Int>()).filter { entries[it].h == text || entries[it].alt == text }
        val tw = (p.tw ?: emptyList()).filter { it != "_" }
        cands.firstOrNull { entries[it].tw.filter { s -> s != "_" } == tw }?.let { return entries[it] }
        return usual(text)?.let { entries[it] }
    }

    // MARK: 日語: text into words

    /** a piece of 日語 text: the word's entry (a conjugated word: its dictionary form's), its reading in kana, and its
     *  parts coloured (the word, the ending that changed, a particle) */
    class JaSeg(val text: String, val entry: Int?, val reading: String?, val pieces: List<JaPiece>)

    private fun isKanaCp(c: String): Boolean { val v = c.firstCp(); return JaKana.isHiragana(v) || JaKana.isKatakana(v) || c == "ー" }
    private fun isJaCp(c: String): Boolean { val v = c.firstCp(); return isKanaCp(c) || JaKana.isKanji(v) }

    /** the entry for a spelling: written so (the commoner first; kana written words for kana), or, for kana, a word
     *  read so that's usually written in kana (いる → 居る) */
    private fun jaLook(w: String, conj: Boolean): Int? = jaFind(w, conj)?.first

    /** the very common kana words that have several entries: the one meant nearly always */
    private val jaUsual = mapOf("いる" to "居る", "ある" to "有る", "なる" to "成る", "できる" to "出来る", "いう" to "言う",
        "いく" to "行く", "ゆく" to "行く", "みる" to "見る", "くる" to "来る", "おく" to "置く", "もらう" to "貰う", "くれる" to "呉れる",
        "あげる" to "上げる", "しまう" to "仕舞う", "あなた" to "貴方", "いい" to "良い", "よい" to "良い", "ない" to "無い", "こと" to "事",
        "もの" to "物", "とき" to "時", "ところ" to "所", "ため" to "為", "わけ" to "訳", "ほう" to "方", "まま" to "儘", "ほしい" to "欲しい")

    /** the entry for a spelling, and how sure (0: written so or usually written in kana; 1: written so in kanji
     *  only as another spelling; 2: a kana word not usually written in kana) */
    private fun jaFind(w: String, conj: Boolean, end: String? = null): Pair<Int, Int>? {
        val kana = w.cps().all { isKanaCp(it) }
        fun ok(i: Int): Boolean {
            if (!conj) return true
            val c = JaGrammar.classOf(entries[i])?.first ?: return false
            return end == null || JaGrammar.fits(c, end)
        }
        val spelt = byHan[w]?.filter { ok(it) } ?: emptyList()
        if (!kana) return spelt.minOrNull()?.let { it to 0 }
        // kana: a word written so, or usually written in kana (いる → 居る); a single kana a particle first (で, に);
        // a kana word not usually written so only for longer ones and never conjugated (いたんだ is いた + んだ, not 悼む)
        val read = (byPlain[JaKana.hiragana(w)] ?: emptyList()).filter { ok(it) }
        val grammar = setOf("prt", "aux-v", "aux", "aux-adj", "cop", "conj", "exp")
        fun rank(i: Int): Int {
            val e = entries[i]
            return when {
                e.h == w || "*uk" in e.jp -> 0
                i in spelt -> 1
                else -> 2
            }
        }
        val cands = (spelt + read).distinct().filter { rank(it) < 2 || (w.cps().size >= 3 && !conj) }
        if (cands.isEmpty()) return null
        jaUsual[JaKana.hiragana(w)]?.let { h ->
            (cands.firstOrNull { entries[it].h == h } ?: cands.firstOrNull { entries[it].h == w })?.let { return it to 0 }
        }
        val one = w.cps().size == 1
        val best = cands.minWithOrNull(compareBy({ rank(it) }, { if (one && entries[it].jp.firstOrNull() !in grammar) 1 else 0 }, { it },
            { if (entries[it].jp.firstOrNull() in grammar) 0 else 1 })) ?: return null
        return best to rank(best)
    }

    /** a word's reading in kana */
    private fun jaReadingOf(i: Int): String = entries[i].tw.filter { it != "-" && it != "_" }.joinToString("")

    /** 日語 text split into words: fewest words, kana words and conjugated ones too (食べなかった → 食べる), the
     *  commoner word when two fit */
    fun jaSegments(text: String): List<JaSeg> {
        val cs = text.cps()
        val n = cs.size
        if (n == 0) return emptyList()
        class Cand(val end: Int, val entry: Int?, val base: String?, val unsure: Boolean = false)
        val cost = DoubleArray(n + 1) { Double.MAX_VALUE }
        val from = arrayOfNulls<Pair<Int, Cand>>(n + 1)
        cost[0] = 0.0
        for (i in 0 until n) {
            if (cost[i] == Double.MAX_VALUE) continue
            val cands = ArrayList<Cand>()
            if (isJaCp(cs[i])) {
                var len = minOf(16, n - i)
                while (len >= 1) {
                    if (!isJaCp(cs[i + len - 1])) { len--; continue }
                    val w = cs.subList(i, i + len).joinToString("")
                    val exact = jaFind(w, false)
                    if (exact != null) cands.add(Cand(i + len, exact.first, null, exact.second == 2))
                    // (conjugated: when no word is written so, or only a kana word not usually written in kana:
                    // いれば is いる, not 入れ歯)
                    if ((exact == null || exact.second == 2) && len >= 2 && JaKana.isHiragana(cs[i + len - 1].firstCp())) {
                        var best: Pair<Int, String>? = null
                        for ((b, end) in JaGrammar.deinflect(w)) {
                            val e = jaFind(b, true, end)?.first ?: continue
                            if (best == null || e < best.first) best = e to b
                        }
                        best?.let { cands.add(Cand(i + len, it.first, it.second)) }
                    }
                    len--
                }
            }
            if (cands.none { it.end == i + 1 }) cands.add(Cand(i + 1, null, null))
            for (c in cands) {
                // (a word: 1; the commoner a little less; a character no word has: more, so words are taken first)
                val add = if (c.entry != null) (if (c.unsure) 1.3 else 1.0) + c.entry * 1e-9 else if (isJaCp(cs[i])) 1.6 else 0.5
                if (cost[i] + add < cost[c.end]) { cost[c.end] = cost[i] + add; from[c.end] = i to c }
            }
        }
        val out = ArrayList<JaSeg>()
        var j = n
        while (j > 0) {
            val (i, c) = from[j] ?: break
            val t = cs.subList(i, j).joinToString("")
            out.add(jaSeg(t, c.entry, c.base))
            j = i
        }
        return out.reversed()
    }

    private fun jaSeg(t: String, e: Int?, base: String?): JaSeg {
        val tc = t.cps()
        if (e == null) {
            // (kana no word has: its own reading)
            return JaSeg(t, null, if (tc.all { isKanaCp(it) }) t else null, listOf(JaPiece(t, JaPiece.Kind.WORD)))
        }
        val en = entries[e]
        val read = jaReadingOf(e)
        val allHira = tc.all { JaKana.isHiragana(it.firstCp()) }
        if (base == null) {
            val kind = when {
                allHira && en.jp.firstOrNull() == "prt" -> JaPiece.Kind.PARTICLE
                allHira && en.jp.firstOrNull().let { it == "aux-v" || it == "aux" || it == "aux-adj" || it == "cop" } -> JaPiece.Kind.SUFFIX
                else -> JaPiece.Kind.WORD
            }
            val r = if (tc.all { isKanaCp(it) }) t else read
            return JaSeg(t, e, r.ifEmpty { null }, listOf(JaPiece(t, kind)))
        }
        // conjugated: the part it shares with the dictionary form stays the word's, the rest is the ending
        val bc = base.cps()
        var k = 0
        while (k < tc.size && k < bc.size && tc[k] == bc[k]) k++
        val stem = tc.take(k).joinToString(""); val ending = tc.drop(k).joinToString("")
        val baseTail = bc.drop(k).joinToString("")
        val reading = when {
            tc.all { isKanaCp(it) } -> t
            read.endsWith(JaKana.hiragana(baseTail)) -> read.dropLast(JaKana.hiragana(baseTail).length) + ending
            else -> read
        }
        val pieces = if (k == 0 || ending.isEmpty()) listOf(JaPiece(t, JaPiece.Kind.WORD))
            else listOf(JaPiece(stem, JaPiece.Kind.WORD), JaPiece(ending, JaPiece.Kind.SUFFIX))
        return JaSeg(t, e, reading.ifEmpty { null }, pieces)
    }

    // MARK: 轉換

    /** a word's 近／反 words (教育部 keys them by the written word, not the reading): with two readings written the same
     *  (睡覺 ㄕㄨㄟˋ ㄐㄧㄠˋ / ㄕㄨㄟˋ ㄐㄧㄠˋ…), each reading keeps the ones whose meaning is closest to its own; nothing
     *  to tell them apart, or a tie: the word's usual reading keeps them */
    fun links(e: ZhEntry): Pair<List<String>, List<String>> {
        if (e.syn.isEmpty() && e.ant.isEmpty()) return e.syn to e.ant
        val sibs = (byHan[e.h] ?: return e.syn to e.ant).filter { entries[it].h == e.h && entries[it].k != e.k && (entries[it].syn.isNotEmpty() || entries[it].ant.isNotEmpty()) }
        if (sibs.isEmpty()) return e.syn to e.ant
        fun hans(t: String): Set<String> = t.cps().filter { Zhuyin.isHan(it.firstCp()) }.toSet()
        fun meaning(x: ZhEntry): Set<String> = hans(x.senses.joinToString("") { it.text }) - hans(e.h)
        val mine = (listOf(e) + sibs.map { entries[it] }).map { meaning(it) }
        fun keep(w: String): Boolean {
            val i = usual(w) ?: return true
            val other = meaning(entries[i]) + hans(w)
            val scores = mine.map { (it intersect other).size }
            val best = scores.maxOrNull() ?: 0
            if (best == 0 || scores.count { it == best } > 1) return usual(e.h)?.let { entries[it].k == e.k } ?: true
            return scores[0] == best
        }
        return e.syn.filter { keep(it) } to e.ant.filter { keep(it) }
    }

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
        // 日語: its own way (kana words too, and conjugated words found by their dictionary form)
        if (isJa) return jaSegments(text).map { g ->
            val cs = g.text.cps()
            ZhPiece(cs, g.reading?.let { r -> listOf(r) + List(cs.size - 1) { "-" } }, null, g.entry, g.pieces)
        }
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
