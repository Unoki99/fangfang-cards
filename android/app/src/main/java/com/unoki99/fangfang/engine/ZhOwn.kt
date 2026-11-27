package com.unoki99.fangfang.engine

import java.text.Normalizer

// MARK: - 自訂: your own words in 華語, 粵語, 客語, 日語 and 瑞典語 (the same as the iPhone app's ZhOwn.swift)
//
// The same list as 台語's 自訂 (Progress.own and .ownInfo, so they sync and go in the backup), with keys of the
// dictionary's own kind and "#自" at the end: "吃飯\tㄔ ㄈㄢˋ#自", "食飯\t粵sik6 faan6#自", "hej\t瑞hej:r#自". When a
// dictionary is read, its language's words are put after its own (ZhDict's init), so they're found like any word.

object ZhOwnWords {
    class Word(val key: String, val h: String, val tw: List<String>, val meaning: String, val example: String)
    /** what ZhDict reads your words from (a copy: the dictionary is read in the background) */
    @Volatile var words: Map<Int, List<Word>> = emptyMap()

    const val SUFFIX = "#自"
    private val marker = listOf("", "", "粵", "客", "日", "瑞")
    fun key(lang: Int, h: String, tw: List<String>): String = h + "\t" + marker[lang.coerceIn(0, 5)] + tw.joinToString(" ") + SUFFIX
    fun isOwn(k: String): Boolean = k.endsWith(SUFFIX) && Lang.kind(k) >= 1
    fun han(k: String): String = k.substringBefore('\t')
    /** the syllables back from a key */
    fun syllables(k: String): List<String> {
        val t = k.indexOf('\t'); if (t < 0) return emptyList()
        var r = k.substring(t + 1).removeSuffix(SUFFIX)
        if (Lang.kind(k) >= 2 && r.isNotEmpty()) r = r.drop(1)
        return r.split(' ').filter { it.isNotEmpty() }
    }

    /** a reading as you type it (華語: 拼音 with or without tones, or 注音; 粵語: 粵拼 with tone numbers; 客語: 客語
     *  拼音 with tone numbers, siid8 fan3; 日語: かな; 瑞典語: nothing) → the dictionary's syllables; null: can't be read */
    fun syllables(typed0: String, han: String, lang: Int, dict: ZhDict): List<String>? {
        val typed = typed0.trim()
        val hans = han.cps().filter { Zhuyin.isHan(it.firstCp()) }
        when (lang) {
            5 -> {
                val ws = han.split(' ').filter { it.isNotEmpty() }.map { it.lowercase() + ":r" }
                if (ws.isEmpty()) return null
                val out = ArrayList<String>(); for ((i, w) in ws.withIndex()) { if (i > 0) out.add("_:w"); out.add(w) }
                return out
            }
            4 -> { val k = JaKana.hiragana(typed.ifEmpty { han }); return if (k.isEmpty()) null else listOf(k) }
            2 -> {
                val t = typed.lowercase()
                val ps = if (t.contains(' ')) t.split(' ').filter { it.isNotEmpty() } else Regex("[a-z]+[1-6]").findAll(t).map { it.value }.toList()
                if (ps.isEmpty() || !ps.all { Zhuyin.isJyut(it) } || (hans.isNotEmpty() && ps.size != hans.size)) return null
                return ps
            }
            3 -> {
                val t = typed.lowercase()
                val ps = if (t.contains(' ')) t.split(' ').filter { it.isNotEmpty() } else Regex("[a-z]+[1-8]").findAll(t).map { it.value }.toList()
                val sup = listOf("⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹")
                val acc = String(Character.toChars(0x2080 + EngineSettings.hakAccent.coerceIn(0, 9)))
                val out = ArrayList<String>()
                for (p in ps) {
                    val d = p.last().digitToIntOrNull() ?: return null
                    if (d !in 1..8) return null
                    val letters = p.dropLast(1)
                    if (letters.isEmpty() || !letters.all { it.isLetter() }) return null
                    out.add(letters + sup[d] + acc)
                }
                if (out.isEmpty() || (hans.isNotEmpty() && out.size != hans.size)) return null
                return out
            }
            else -> return dict.zhuyinOf(typed, hans)
        }
    }
}

/** 拼音 letters → tone → 注音, from the dictionary's own syllables (made once) */
private object PinyinTable {
    @Volatile var table: Map<String, Map<Int, String>>? = null
}

/** 華語: 拼音 (chi1 fan4, chīfàn, chifan) or 注音 (ㄔ ㄈㄢˋ) → 注音 syllables, one a character. A syllable without a
 *  tone takes the character's own reading with those letters (飯 fan → ㄈㄢˋ); 5 or 0 = light tone. */
fun ZhDict.zhuyinOf(typed: String, han: List<String>): List<String>? {
    val n = han.size
    // 注音 as it is (with spaces, or ending at each tone mark)
    if (typed.any { it in '㄀'..'ㄯ' }) {
        var ps = typed.split(' ').filter { it.isNotEmpty() }
        if (ps.size != n) {
            val out = ArrayList<String>(); var cur = StringBuilder()
            for (ch in typed) {
                if (ch == ' ') continue
                if (ch == '˙') { if (cur.isNotEmpty()) out.add(cur.toString()); cur = StringBuilder("˙"); continue }
                cur.append(ch)
                if (ch in "ˊˇˋ") { out.add(cur.toString()); cur = StringBuilder() }
            }
            if (cur.isNotEmpty()) out.add(cur.toString())
            ps = out
        }
        return if (ps.size == n || n == 0) ps else null
    }
    val table = PinyinTable.table ?: run {
        val t = HashMap<String, HashMap<Int, String>>()
        for (e in entries.take(60_000)) for (z in e.tw) {
            if (z == "-" || z == "_" || z.isEmpty()) continue
            val p = Zhuyin.plainSyllable(z)
            if (p.isEmpty() || !p.all { it.isLetter() }) continue
            t.getOrPut(p) { HashMap() }.putIfAbsent(Zhuyin.tone(z), z)
        }
        PinyinTable.table = t
        t
    }
    // 拼音: letters and their tones (a mark on a vowel, or a number after the syllable)
    val letters = ArrayList<Char>()
    val toneAt = HashMap<Int, Int>()
    val breaks = HashSet<Int>()
    val marks = mapOf(0x304 to 1, 0x301 to 2, 0x30C to 3, 0x300 to 4)
    val low = typed.lowercase().replace("u:", "v").replace("ü", "v")
    for (u in Normalizer.normalize(low, Normalizer.Form.NFD)) {
        val m = marks[u.code]
        if (m != null) { toneAt[maxOf(letters.size - 1, 0)] = m; continue }
        if (u.code == 0x308) { if (letters.lastOrNull() == 'u') letters[letters.size - 1] = 'v'; continue }
        if (u in '0'..'5') { val d = u - '0'; toneAt[maxOf(letters.size - 1, 0)] = if (d == 5) 0 else d; breaks.add(letters.size); continue }
        if (u == ' ' || u == '\'' || u == '-') { breaks.add(letters.size); continue }
        if (u.isLetter()) letters.add(u)
    }
    // the letters split into syllables: at the spaces and numbers first, the longest syllable that fits
    val syls = ArrayList<Pair<String, Int?>>()
    var i = 0
    while (i < letters.size) {
        var best = 0
        for (len in minOf(6, letters.size - i) downTo 1) {
            if ((i + 1 until i + len).any { it in breaks }) continue
            if (table.containsKey(String(letters.subList(i, i + len).toCharArray()))) { best = len; break }
        }
        if (best == 0) return null
        val t = (i until i + best).firstNotNullOfOrNull { toneAt[it] }
        syls.add(String(letters.subList(i, i + best).toCharArray()) to t)
        i += best
    }
    if (syls.isEmpty() || (n != 0 && syls.size != n)) return null
    val out = ArrayList<String>()
    for ((j, s) in syls.withIndex()) {
        val (p, t) = s
        val byTone = table[p] ?: return null
        if (t != null) {
            val exact = byTone[t]
            if (exact != null) { out.add(exact); continue }
            val any = listOf(1, 2, 3, 4, 0).firstNotNullOfOrNull { byTone[it] } ?: return null
            out.add(Zhuyin.withTone(any, t)); continue
        }
        // (no tone: the character's own reading with these letters, else the first tone there is)
        if (n > 0) {
            val own = (byHan[han[j]] ?: emptyList<Int>()).map { entries[it] }.firstOrNull { it.tw.size == 1 && Zhuyin.plainSyllable(it.tw[0]) == p }
            if (own != null) { out.add(own.tw[0]); continue }
        }
        out.add(listOf(1, 2, 3, 4, 0).firstNotNullOfOrNull { byTone[it] } ?: return null)
    }
    return out
}
