package com.unoki99.fangfang.engine

import java.text.Normalizer

// The full 方方 dictionary (the same data as the website), for 轉換 and 詞典.
// A word is identified by its key "漢字\tcodes" (codes = the 通行 reading as syllable codes).

class CmpRow(val place: Int, val han: String, val codes: String)
class CmpEntry(val zh: String, val rows: List<CmpRow>)

/** how often each reading of a character appears in the example sentences, alone (u) and after (l) / before (r) another */
class CtxRaw(val u: Map<String, Int>, val l: Map<String, Int>, val r: Map<String, Int>)

class DefsRaw(val t: List<String>, val m: Map<String, Int>)

class DictRaw(
    val words: List<List<String>>,
    val syl: Map<String, List<String>>,
    val tl: Map<String, List<String>>,
    val pj: Map<String, String>,
    val defs: DefsRaw,
    val pos: Map<String, String>,
    val ex: Map<String, List<List<List<String>>>>,
    val reg: Map<String, String>,
    val own: List<String>,
    val au: Map<String, Int>,
    val gl: List<List<String>>,
    val freq: Map<String, Double>,
    val places: List<String>,
    val alt: Map<String, List<List<String>>>,
    val dia: Map<String, Map<String, String>>,
    val tok: Map<String, String>,
    val sub: List<String>,
    val typ: Map<String, Int>,
    val sy: Map<String, Map<String, List<String>>>,
    val an: Map<String, Map<String, List<String>>>,
    val variants: Map<String, List<String>>,
    val cmp: List<CmpEntry>,
    val names: Map<String, List<List<String>>>,
    val sur: Map<String, List<List<String>>>,
    val types: List<String>?,
    val cats: List<String>?,
    val cat: Map<String, List<Int>>?,
    val ctx: CtxRaw?,
    val dia2: Map<String, Map<String, List<String>>>?,
    val dex: Map<String, String>?,
    /** per meaning place readings: key -> meaning index -> place -> codes (足「非常」: 臺南 tsok) */
    val sdia: Map<String, Map<String, Map<String, String>>>? = null,
) {
    companion object {
        fun parse(text: String): DictRaw {
            val j = JReader(text)
            var words: List<List<String>> = emptyList()
            var syl: Map<String, List<String>> = emptyMap()
            var tl: Map<String, List<String>> = emptyMap()
            var pj: Map<String, String> = emptyMap()
            var defs = DefsRaw(emptyList(), emptyMap())
            var pos: Map<String, String> = emptyMap()
            var ex: Map<String, List<List<List<String>>>> = emptyMap()
            var reg: Map<String, String> = emptyMap()
            var own: List<String> = emptyList()
            var au: Map<String, Int> = emptyMap()
            var gl: List<List<String>> = emptyList()
            var freq: Map<String, Double> = emptyMap()
            var places: List<String> = emptyList()
            var alt: Map<String, List<List<String>>> = emptyMap()
            var dia: Map<String, Map<String, String>> = emptyMap()
            var tok: Map<String, String> = emptyMap()
            var sub: List<String> = emptyList()
            var typ: Map<String, Int> = emptyMap()
            var sy: Map<String, Map<String, List<String>>> = emptyMap()
            var an: Map<String, Map<String, List<String>>> = emptyMap()
            var variants: Map<String, List<String>> = emptyMap()
            var cmp: List<CmpEntry> = emptyList()
            var names: Map<String, List<List<String>>> = emptyMap()
            var sur: Map<String, List<List<String>>> = emptyMap()
            var types: List<String>? = null
            var cats: List<String>? = null
            var cat: Map<String, List<Int>>? = null
            var ctx: CtxRaw? = null
            var dia2: Map<String, Map<String, List<String>>>? = null
            var dex: Map<String, String>? = null
            var sdia: Map<String, Map<String, Map<String, String>>>? = null
            j.obj { k ->
                when (k) {
                    "words" -> words = j.strList2()
                    "syl" -> syl = j.strListMap()
                    "tl" -> tl = j.strListMap()
                    "pj" -> pj = j.strMap()
                    "defs" -> {
                        var t: List<String> = emptyList(); var m: Map<String, Int> = emptyMap()
                        j.obj { kk -> when (kk) { "t" -> t = j.strList(); "m" -> m = j.intMap(); else -> j.skip() } }
                        defs = DefsRaw(t, m)
                    }
                    "pos" -> pos = j.strMap()
                    "ex" -> ex = j.map { j.list { j.list { j.strList() } } }
                    "reg" -> reg = j.strMap()
                    "own" -> own = j.strList()
                    "au" -> au = j.intMap()
                    "gl" -> gl = j.strList2()
                    "freq" -> freq = j.doubleMap()
                    "places" -> places = j.strList()
                    "alt" -> alt = j.map { j.strList2() }
                    "dia" -> dia = j.map { j.strMap() }
                    "tok" -> tok = j.strMap()
                    "sub" -> sub = j.strList()
                    "typ" -> typ = j.intMap()
                    "sy" -> sy = j.map { j.strListMap() }
                    "an" -> an = j.map { j.strListMap() }
                    "var" -> variants = j.strListMap()
                    "cmp" -> cmp = j.list {
                        j.beginArray()
                        j.hasNext(); val zh = j.nextString()
                        j.hasNext()
                        val rows = j.list {
                            j.beginArray()
                            j.hasNext(); val p = j.nextInt()
                            j.hasNext(); val h = j.nextString()
                            j.hasNext(); val c = j.nextString()
                            while (j.hasNext()) j.skip()
                            j.endArray()
                            CmpRow(p, h, c)
                        }
                        while (j.hasNext()) j.skip()
                        j.endArray()
                        CmpEntry(zh, rows)
                    }
                    "names" -> names = j.map { j.strList2() }
                    "sur" -> sur = j.map { j.strList2() }
                    "types" -> types = j.strList()
                    "cats" -> cats = j.strList()
                    "cat" -> cat = j.map { j.intList() }
                    "ctx" -> {
                        var u: Map<String, Int> = emptyMap(); var l: Map<String, Int> = emptyMap(); var r: Map<String, Int> = emptyMap()
                        j.obj { kk -> when (kk) { "u" -> u = j.intMap(); "l" -> l = j.intMap(); "r" -> r = j.intMap(); else -> j.skip() } }
                        ctx = CtxRaw(u, l, r)
                    }
                    "dia2" -> dia2 = j.map { j.strListMap() }
                    "dex" -> dex = j.strMap()
                    "sdia" -> sdia = j.map { j.map { j.strMap() } }
                    else -> j.skip()
                }
            }
            return DictRaw(words, syl, tl, pj, defs, pos, ex, reg, own, au, gl, freq, places, alt, dia, tok, sub, typ,
                sy, an, variants, cmp, names, sur, types, cats, cat, ctx, dia2, dex, sdia)
        }
    }
}

/** one meaning of a word, ready to show */
class DictSense(val n: Int, val pos: String, val text: String, val ex: List<List<String>>, val syn: List<String>, val ant: List<String>)

/** a reading choice for a word in the converter */
data class Opt(
    val han: String?,
    val codes: List<String>?,
    val parent: String? = null,   // the word's key, for alternative readings and variant characters
    val label: String? = null,    // 又 / 俗 / 合
    val tokens: String? = null,
)

class Gloss(val t: String, val ex: Boolean)

/** an example sentence that uses a word: [漢字, template, 華語, audio], and the entry it's listed under */
data class SentenceHit(val ex: List<String>, val entry: String, val word: String)

class VocabCandidate(val han: String, val codes: List<String>, var auto: Boolean)

class Localized(val han: String, val tpl: String, val swapped: Set<Int>, val words: Map<Int, String>)

/** a text piece: (text, mark) — mark 0 plain, 1 guessed, 2 a word the place says differently */
class Piece(val text: String, val mark: Int)

class Dict(val raw: DictRaw, private val prefs: KeyValue) {
    val baseKeys: Set<String> = raw.words.map { it[0] + "\t" + it[1] }.toHashSet()
    val own: Set<String> = raw.own.toHashSet()
    val subst: Set<String> = raw.sub.toHashSet()
    /** places where 台羅 o is always said ㄜ (臺南, 高雄) */
    val orPlaces: Set<Int> = raw.places.indices.filter { raw.places[it].startsWith("臺南") || raw.places[it].startsWith("高雄") }.toSet()
    val hanMap = HashMap<String, MutableList<String>>()       // 漢字 -> codes strings
    val codeMap = HashMap<String, MutableList<String>>()      // codes string -> 漢字
    val hanAlt = HashMap<String, MutableList<Opt>>()
    val altParent = HashMap<String, String>()
    var maxHan = 1; private set
    var maxSyl = 1; private set
    val zyRev = HashMap<String, MutableList<String>>()
    val zyRev0 = HashMap<String, MutableList<String>>()
    val latRev = HashMap<String, MutableList<String>>()
    val tlRev = HashMap<String, MutableList<String>>()
    val pojRev = HashMap<String, MutableList<String>>()
    var maxZy = 1; private set
    val plainRev = HashMap<String, MutableList<String>>()
    val gl = HashMap<String, List<Gloss>>()
    val termIndex = HashMap<String, MutableList<String>>()
    private val pairCount = HashMap<String, Int>()
    val catWords = HashMap<Int, MutableList<String>>()
    val catCounts: Map<Int, Int> get() = catWords.mapValues { it.value.size }

    companion object {
        val taigiCommon: Set<String> = "阮咱恁怹伊我你佇欲咧予共佮毋袂會閣攏遮遐啥厝媠囝仔个的矣嘛猶抑煞較足誠真去來看講聽想做食飯人有無是佗遐爾按怎彼這".cps().toSet()

        private fun push(m: HashMap<String, MutableList<String>>, k: String, v: String) {
            val a = m[k]
            if (a != null) { if (!a.contains(v)) a.add(v) } else m[k] = mutableListOf(v)
        }

        fun nfc(s: String): String = Normalizer.normalize(s, Normalizer.Form.NFC)
        fun nfd(s: String): String = Normalizer.normalize(s, Normalizer.Form.NFD)

        /** a romanized syllable without tone: lower case, no marks, no tone number */
        fun plainKey(s: String): String {
            val t = ConvertEngine.pojOO(nfd(s.lowercase())).replace("ⁿ", "nn")
            val sb = StringBuilder()
            var i = 0
            while (i < t.length) {
                val cp = t.codePointAt(i)
                if (!(cp in 0x300..0x36F) && !(cp in '0'.code..'9'.code)) sb.appendCodePoint(cp)
                i += Character.charCount(cp)
            }
            return sb.toString()
        }

        private val ingRe = Regex("ing(?=\\d)")
        private val ikRe = Regex("ik(?=\\d)")
        fun tl2poj(s: String): String {
            var t = s
            if (t.startsWith("tsh")) t = "chh" + t.drop(3) else if (t.startsWith("ts")) t = "ch" + t.drop(2)
            t = t.replace("ua", "oa").replace("ue", "oe")
            t = ingRe.replaceFirst(t, "eng")
            t = ikRe.replaceFirst(t, "ek")
            return t
        }

        fun codesOf(key: String): String { val i = key.indexOf('\t'); return if (i < 0) "" else key.substring(i + 1) }
        fun hanOf(key: String): String { val i = key.indexOf('\t'); return if (i < 0) key else key.substring(0, i) }

        /** pairs where the 華語 meaning matches but the words don't mean the same in a sentence */
        val wrongPairs = setOf("無夠→較無一半", "穡頭→職業", "開講→畫虎𡳞", "烏白講→臭彈")
        /** words used in this many example sentences or more are never swapped */
        const val commonCutoff = 100

        private val bracketRe = Regex("[（(][^）)]*[）)]")
        /** a 各地講法 meaning's 華語 words: notes in brackets dropped, alternatives split */
        fun conceptTerms(zh: String): List<String> {
            val t = bracketRe.replace(zh, "")
            return t.split('、', '，', ',', ' ').filter { it.isNotEmpty() }
        }

        fun swapOffKey(han: String, place: Int) = "$place|$han"

        private val tplCodeRe = Regex("\\{\\^?([^}]*)\\}")
        private val tplSpanRe = Regex("\\{[^}]*\\}")

        /** the codes in a template (without ^) */
        fun tplCodes(tpl: String): List<String> = tplCodeRe.findAll(tpl).map { it.groupValues[1] }.toList()

        /** the template with syllables lower..<upper replaced by ＿＿ (for 例句填空) */
        fun blanked(tpl: String, lo: Int, hi: Int): String {
            val spans = tplSpanRe.findAll(tpl).map { it.range }.toList()
            if (lo < 0 || hi > spans.size || lo >= hi) return tpl
            return tpl.substring(0, spans[lo].first) + "＿＿" + tpl.substring(spans[hi - 1].last + 1)
        }

        /** words that look like 離合詞 but are normal verbs (picked by hand): their last syllable changes tone */
        val notVerbWithNoun: Set<String> = setOf(
            "不服\tpuD4 hoG8", "交流\tkU1 diu5", "代理\ttI7 di2", "佩服\tpue7 hoG8", "保領\tpø2 dNia2",
            "信任\tsiD3 ziB7", "修理\tsiu1 di2", "克服\tKiøG4 hoG8", "再會\tcI3 hue7", "包領\tpU1 dNia2",
            "委任\tui2 ziB7", "安眠\taD1 biD5", "對指\ttui3 ci2", "對相\ttui3 sioG3", "對頭誤\ttui3 TU5 go7",
            "徛黃\tKia7 G5", "必叉\tpiD4 Ce1", "拑牢牢\tKNi5 tiU5 tiU5", "指教\tci2 kU3", "掩崁\taB1 KaB3",
            "掰會\tpue2 hue7", "搬運\tpNua1 uD7", "撙節\tcuD2 caD4", "擔任\ttaB1 ziB7", "支理\tci1 di2",
            "敗露\tpI7 do7", "整理\tciøG2 di2", "料理\tdiU7 di2", "明品\tbiøG5 PiD2", "暗崁\taB3 KaB3",
            "暴露\tpoG8 do7", "檢點\tkiaB2 tiaB2", "毋知影\tB7 cI1 Nia2", "發表\thuaD4 piU2", "相干\tsioG1 kaD1",
            "相會\tsioG1 hue7", "知影\tcI1 Nia2", "管理\tkuaD2 di2", "纘袂牢\tcaD3 be7 tiU5", "處理\tCu2 di2",
            "請教\tCiøG2 kU3", "貓貓相\tdNiU1 dNiU1 sioG3", "負擔\thu7 taB1", "辦理\tpaD7 di2", "違背\tui5 pue7",
            "金金相\tkiB1 kiB1 sioG3", "體會\tTe2 hue7",
        )

        /** the word classes in the dictionary, plus 離合詞 (verbs that end in a noun: 洗身軀, 食飯) */
        val wordClasses = listOf("名詞", "動詞", "離合詞", "形容詞", "副詞", "量詞", "時間詞", "代詞", "數詞", "方位詞",
            "介詞", "連詞", "助詞", "疑問詞", "嘆詞", "擬聲詞", "擬態詞", "熟語")
    }

    init {
        // syllables for input
        for ((c, v) in raw.syl) {
            val z = v[0]; val l = v[1]
            push(zyRev, z, c)
            maxZy = maxOf(maxZy, z.codePointCount(0, z.length))
            if (c.contains("ø")) push(zyRev, z.replace("ㄜ", "ㄛ"), c)
            if (z.endsWith("ˉ")) push(zyRev0, z.dropLast(1), c)
            push(latRev, nfc(l).lowercase(), c)
        }
        for ((c, v) in raw.tl) {
            if (v.size <= 1) continue
            push(tlRev, v[1], c)
            push(pojRev, tl2poj(v[1]), c)
            push(plainRev, plainKey(v[1]), c)
            push(plainRev, plainKey(tl2poj(v[1])), c)
        }
        for ((c, v) in raw.syl) push(plainRev, plainKey(v[1]), c)
        // words
        for (w in raw.words) {
            if (w.size != 2) continue
            val h = w[0]; val c = w[1]
            push(hanMap, h, c); push(codeMap, c, h)
            maxHan = maxOf(maxHan, h.cpCount)
            maxSyl = maxOf(maxSyl, c.split(' ').size)
        }
        maxHan = minOf(maxHan, 12)
        for (w in raw.words) {
            if (w.size != 2) continue
            val hs = w[0].cps(); val cs = w[1].split(' ')
            if (hs.size != cs.size) continue
            for (k in hs.indices) { val key = hs[k] + "|" + cs[k]; pairCount[key] = (pairCount[key] ?: 0) + 1 }
        }
        for ((c, list) in codeMap) {
            val sorted = list.sortedByDescending { score(it, c) }
            list.clear(); list.addAll(sorted)
        }
        val rank = mapOf("白" to 0, "俗" to 1, "" to 2, "文" to 3)
        for ((h, list) in hanMap) {
            if (h.cpCount == 1 && list.size > 1) {
                val sorted = list.sortedBy { rank[raw.reg[h + "\t" + it] ?: ""] ?: 2 }
                list.clear(); list.addAll(sorted)
            }
        }
        // other readings and dialect readings: typing them finds the word too
        for (w in raw.words) {
            if (w.size != 2) continue
            val h = w[0]; val c = w[1]; val k = h + "\t" + c
            val extra = ArrayList<Opt>()
            for (a in raw.alt[k] ?: emptyList()) {
                if (a.isEmpty()) continue
                extra.add(Opt(h, a[0].split(' '), k, if (a.size > 1 && a[1].isNotEmpty()) a[1] else "又", if (a.size > 2) a[2] else null))
            }
            for ((_, dc) in raw.dia[k] ?: emptyMap()) {
                if (dc == c) continue
                altParent[h + "\t" + dc] = k
                push(codeMap, dc, h)
            }
            for (o in extra) {
                val cs = o.codes!!.joinToString(" ")
                if (cs == c) continue
                altParent[h + "\t" + cs] = k
                push(codeMap, cs, h)
                maxSyl = maxOf(maxSyl, o.codes.size)
                hanAlt.getOrPut(h) { ArrayList() }.add(o)
            }
        }
        // variant characters (異用字)
        for ((v, keys) in raw.variants) {
            if (hanMap[v] != null) continue
            for (k in keys) {
                val tab = k.indexOf('\t'); if (tab < 0) continue
                val c = k.substring(tab + 1)
                push(hanMap, v, c)
                altParent[v + "\t" + c] = k
                maxHan = maxOf(maxHan, v.cpCount)
            }
        }
        for ((k, cs) in raw.cat ?: emptyMap()) for (c in cs) catWords.getOrPut(c) { ArrayList() }.add(k)
        // 華語 glossary
        for (e in raw.gl) {
            if (e.size != 2) continue
            val arr = e[1].split('|').map { s -> if (s.startsWith("~")) Gloss(s.drop(1), true) else Gloss(s, false) }
            gl[e[0]] = arr
            for (x in arr) push(termIndex, x.t, e[0])
        }
    }

    fun charScore(ch: String, c: String): Double =
        Math.log(1.0 + (pairCount["$ch|$c"] ?: 0)) + 0.45 * (raw.freq[ch] ?: 0.0) + (if (taigiCommon.contains(ch)) 6.0 else 0.0)

    fun score(h: String, c: String): Double {
        val hs = h.cps(); val cs = c.split(' ')
        if (hs.size != cs.size || hs.isEmpty()) return 0.0
        var s = 0.0
        for (i in hs.indices) s += charScore(hs[i], cs[i])
        return s / hs.size
    }

    // MARK: 自訂 (your own words)

    var userKeys: Set<String> = emptySet(); private set
    fun isUser(key: String) = userKeys.contains(key)

    @Synchronized
    fun setUserWords(keys: Set<String>) {
        val wanted = keys.filter { !baseKeys.contains(it) && altParent[it] == null && it.contains('\t') }.toSet()
        if (wanted == userKeys) return
        for (k in userKeys - wanted) {
            val h = hanOf(k); val c = codesOf(k)
            hanMap[h]?.remove(c); if (hanMap[h]?.isEmpty() == true) hanMap.remove(h)
            codeMap[c]?.remove(h); if (codeMap[c]?.isEmpty() == true) codeMap.remove(c)
        }
        for (k in wanted - userKeys) {
            val h = hanOf(k); val c = codesOf(k)
            if (hanMap[h]?.contains(c) != true) hanMap.getOrPut(h) { ArrayList() }.add(c)
            if (codeMap[c]?.contains(h) != true) codeMap.getOrPut(c) { ArrayList() }.add(h)
            maxHan = maxOf(maxHan, minOf(h.cpCount, 12))
            maxSyl = maxOf(maxSyl, c.split(' ').size)
        }
        userKeys = wanted
    }

    // MARK: keys

    fun keyOf(o: Opt): String? {
        val h = o.han ?: return null
        val codes = o.codes ?: return null
        if (o.parent != null) return o.parent
        val k = h + "\t" + codes.joinToString(" ")
        return if (baseKeys.contains(k)) k else (altParent[k] ?: k)
    }

    // MARK: rendering (same rules as fangcore.js)

    /** sys: 0 皓羅, 1 台羅, 2 白話字, 3 方音; place: -1 = 通行 */
    fun syl(c: String, sys: Int, place: Int): String {
        val s = raw.syl[c] ?: return c
        return when (sys) {
            3 -> if (place >= 0 && c.contains("ø") && !orPlaces.contains(place)) s[0].replace("ㄜ", "ㄛ") else s[0]
            1 -> raw.tl[c]?.firstOrNull() ?: s[1]
            2 -> raw.pj[c] ?: s[1]
            else -> s[1]
        }
    }
    fun isCode(t: String) = raw.syl.containsKey(t)

    fun codesFor(key: String, place: Int): String {
        if (place >= 0) raw.dia[key]?.get(place.toString())?.let { return it }
        return codesOf(key)
    }

    fun tokensFor(key: String, place: Int, codes: String? = null): List<String> {
        val cs = (codes ?: codesFor(key, place)).split(' ').filter { it.isNotEmpty() }
        val base = raw.tok[key] ?: return cs
        var i = 0
        return base.split(' ').filter { it.isNotEmpty() }.map { t ->
            val cap = t.startsWith("^"); val c = if (cap) t.drop(1) else t
            if (!isCode(c)) t else {
                val n = if (i < cs.size) cs[i] else c
                i++
                (if (cap) "^" else "") + n
            }
        }
    }

    private fun cap1(s: String): String = if (s.isEmpty()) s else {
        val n = Character.charCount(s.codePointAt(0))
        s.substring(0, n).uppercase() + s.substring(n)
    }

    fun render(tokens: List<String>, sys: Int, place: Int): String {
        val out = StringBuilder()
        var prevCode = false
        for (t in tokens) {
            val cap = t.startsWith("^"); val c = if (cap) t.drop(1) else t
            if (isCode(c)) {
                if (sys != 3 && prevCode) out.append("-")
                var s = syl(c, sys, place)
                if (cap && sys != 3) s = cap1(s)
                out.append(s); prevCode = true
            } else if (t == "--") { if (sys != 3) out.append("--"); prevCode = false }
            else if (t == "_") { out.append(" "); prevCode = false }
            else if (t.startsWith("~")) { out.append(t.drop(1)); prevCode = false }
            else { out.append(t); prevCode = false }
        }
        return out.toString()
    }

    fun word(key: String, sys: Int, place: Int): String = render(tokensFor(key, place), sys, place)

    fun sameSound(common: String, local: String, place: Int): Boolean =
        common == local || (orPlaces.contains(place) && common.replace("ø", "ɵ") == local)

    fun differsFromCommon(key: String, place: Int): Boolean {
        if (place < 0) return false
        val dc = raw.dia[key]?.get(place.toString()) ?: return false
        val a = codesOf(key).split(' '); val b = dc.split(' ')
        if (a.size != b.size) return true
        return b.indices.any { !sameSound(a[it], b[it], place) }
    }

    fun guessedSyllables(key: String, place: Int): Set<Int> {
        if (place < 0 || isStated(key, place)) return emptySet()
        val dc = raw.dia[key]?.get(place.toString()) ?: return emptySet()
        val a = codesOf(key).split(' '); val b = dc.split(' ')
        if (a.size != b.size) return b.indices.toSet()
        return b.indices.filter { !sameSound(a[it], b[it], place) }.toSet()
    }

    /** the word as (text, guessed) pieces, so guessed syllables can be coloured */
    fun wordPieces(key: String, sys: Int, place: Int): List<Pair<String, Boolean>> {
        val g = guessedSyllables(key, place)
        if (g.isEmpty()) return listOf(Pair(word(key, sys, place), false))
        val out = ArrayList<Pair<String, Boolean>>()
        fun put(t: String, guessed: Boolean) {
            if (t.isEmpty()) return
            val l = out.lastOrNull()
            if (l != null && l.second == guessed) out[out.size - 1] = Pair(l.first + t, guessed) else out.add(Pair(t, guessed))
        }
        var prevCode = false; var n = 0
        for (t in tokensFor(key, place)) {
            val cap = t.startsWith("^"); val c = if (cap) t.drop(1) else t
            if (isCode(c)) {
                if (sys != 3 && prevCode) put("-", false)
                var s = syl(c, sys, place)
                if (cap && sys != 3) s = cap1(s)
                put(s, g.contains(n)); n++; prevCode = true
            } else if (t == "--") { if (sys != 3) put("--", false); prevCode = false }
            else if (t == "_") { put(" ", false); prevCode = false }
            else if (t.startsWith("~")) { put(t.drop(1), false); prevCode = false }
            else { put(t, false); prevCode = false }
        }
        return out
    }

    fun codes(cs: String, sys: Int, place: Int, tokens: String? = null): String =
        render((tokens ?: cs).split(' ').filter { it.isNotEmpty() }, sys, place)

    fun isStated(key: String, place: Int): Boolean {
        if (place < 0) return false
        val s = raw.dex?.get(key) ?: return false
        return s.contains(place.toString())
    }

    fun sentencePieces(tpl: String, sys: Int, place: Int = -1, han: String? = null): List<Pair<String, Boolean>> =
        examplePieces(tpl, sys, place, han, null).map { Pair(it.text, it.mark == 1) }

    /** an example sentence in 羅馬字 as pieces: mark 0 plain, 1 guessed local reading, 2 a word the place says differently */
    fun examplePieces(tpl: String, sys: Int, place: Int = -1, han: String? = null, zh: String? = null): List<Piece> {
        var t = tpl
        if (place >= 0 && han != null) {
            val loc = localizedExample(han, tpl, place, zh)
            t = dialectTemplate(loc.han, loc.tpl, place)
        }
        val out = ArrayList<Piece>()
        fun put(x: String, m: Int) {
            if (x.isEmpty()) return
            val l = out.lastOrNull()
            if (l != null && l.mark == m) out[out.size - 1] = Piece(l.text + x, m) else out.add(Piece(x, m))
        }
        var i = 0
        while (true) {
            val open = t.indexOf('{', i); if (open < 0) break
            val close = t.indexOf('}', open); if (close < 0) break
            put(t.substring(i, open), 0)
            var c = t.substring(open + 1, close)
            val cap = c.startsWith("^")
            if (cap) c = c.drop(1)
            var m = 0
            if (c.startsWith("?")) { m = 1; c = c.drop(1) } else if (c.startsWith("!")) { m = 2; c = c.drop(1) }
            var s = if (isCode(c)) syl(c, sys, place) else c
            if (cap) s = cap1(s)
            put(s, m)
            i = close + 1
        }
        put(t.substring(i), 0)
        return out
    }

    // MARK: words each place says differently (各地講法)

    private val vocabLock = Any()
    private var vocabIndex: Map<String, List<Int>>? = null
    private var synHan: Map<String, Set<String>> = emptyMap()

    private fun ensureVocabIndexLocked() {
        if (vocabIndex != null) return
        val idx = HashMap<String, MutableList<Int>>()
        for ((i, e) in raw.cmp.withIndex()) for (h in e.rows.map { it.han }.toSet()) idx.getOrPut(h) { ArrayList() }.add(i)
        vocabIndex = idx
        val syn = HashMap<String, MutableSet<String>>()
        for ((k, m) in raw.sy) {
            val a = hanOf(k)
            for (list in m.values) for (other in list) {
                val b = hanOf(other)
                if (a != b) { syn.getOrPut(a) { HashSet() }.add(b); syn.getOrPut(b) { HashSet() }.add(a) }
            }
        }
        synHan = syn
    }

    fun vocabCandidates(word: String, place: Int, zh: String?): List<VocabCandidate> {
        if (zh.isNullOrEmpty()) return emptyList()
        if (sentenceCount(word) >= commonCutoff) return emptyList()
        val concepts: List<Int>; val syns: Set<String>
        synchronized(vocabLock) {
            ensureVocabIndexLocked()
            concepts = vocabIndex?.get(word) ?: emptyList()
            syns = synHan[word] ?: emptySet()
        }
        val out = ArrayList<VocabCandidate>()
        for (i in concepts) {
            val matched = conceptTerms(raw.cmp[i].zh).filter { zh.contains(it) }
            if (matched.isEmpty()) continue
            val rows = raw.cmp[i].rows.filter { it.place == place }
            if (rows.isEmpty()) continue
            if (rows.any { it.han == word }) return emptyList()
            val strong = matched.any { it.cpCount > 1 } && raw.cmp[i].rows.map { it.han }.toSet().size < 6
            for (r in rows) {
                if (wrongPairs.contains(word + "→" + r.han)) continue
                val codes = r.codes.split(' ').filter { it.isNotEmpty() }
                if (codes.isEmpty() || codes.size != r.han.cpCount || !codes.all { isCode(it) }) continue
                val auto = strong && !r.han.contains(word) && !word.contains(r.han) && !syns.contains(r.han)
                val j = out.indexOfFirst { it.han == r.han }
                if (j >= 0) out[j].auto = out[j].auto || auto else out.add(VocabCandidate(r.han, codes, auto))
            }
        }
        return out
    }

    fun vocabOptions(word: String, place: Int, zh: String?): List<Pair<String, List<String>>> =
        vocabCandidates(word, place, zh).map { Pair(it.han, it.codes) }

    private var wordCounts: Map<String, Int>? = null

    fun sentenceCount(word: String): Int {
        synchronized(vocabLock) {
            ensureVocabIndexLocked()
            if (wordCounts == null) {
                val counts = HashMap<String, Int>()
                val listed = vocabIndex ?: emptyMap()
                for (senses in raw.ex.values) for (exs in senses) for (e in exs) {
                    if (e.size <= 1) continue
                    for (w in sentenceWords(e[0], e[1]).toSet()) if (listed.containsKey(w)) counts[w] = (counts[w] ?: 0) + 1
                }
                wordCounts = counts
            }
            return wordCounts?.get(word) ?: 0
        }
    }

    /** a template's syllables: codes (without ^), whether capitalised, the text before each, and where each sits */
    class TplToken(val start: Int, val end: Int, val codeStart: Int, val code: String, val cap: Boolean, val sep: String)

    fun tplTokens(tpl: String): List<TplToken> {
        val out = ArrayList<TplToken>()
        var i = 0; var prevEnd = 0
        while (true) {
            val open = tpl.indexOf('{', i); if (open < 0) break
            val close = tpl.indexOf('}', open); if (close < 0) break
            var start = open + 1
            val cap = start < close && tpl[start] == '^'
            if (cap) start++
            out.add(TplToken(open, close + 1, start, tpl.substring(start, close), cap, tpl.substring(prevEnd, open)))
            prevEnd = close + 1; i = prevEnd
        }
        return out
    }

    private fun hanIndices(chars: List<String>): List<Int> = chars.indices.filter { ConvertEngine.isHan(chars[it].firstCp()) }

    /** syllables grouped into words by the dashes */
    private fun groupsOf(seps: List<String>): List<MutableList<Int>> {
        val groups = ArrayList<MutableList<Int>>()
        for (n in seps.indices) {
            if (n > 0 && (seps[n] == "-" || seps[n] == "--")) groups[groups.size - 1].add(n) else groups.add(mutableListOf(n))
        }
        return groups
    }

    private fun sentenceWords(han: String, tpl: String): List<String> {
        val chars = han.cps()
        val hanIdx = hanIndices(chars)
        val tks = tplTokens(tpl)
        if (tks.isEmpty() || tks.size != hanIdx.size) return emptyList()
        val codes = tks.map { it.code }
        val groups = groupsOf(tks.map { it.sep })
        val out = ArrayList<String>()
        for (g in groups) {
            var a = 0
            while (a < g.size) {
                var step = 1
                for (L in (g.size - a) downTo 1) {
                    val seg = g.subList(a, a + L)
                    val w = seg.joinToString("") { chars[hanIdx[it]] }
                    val k = w + "\t" + seg.joinToString(" ") { codes[it] }
                    if (baseKeys.contains(k) || altParent[k] != null) { out.add(w); step = L; break }
                }
                a += step
            }
        }
        return out
    }

    // your choices in the word picker: "place|original word" -> chosen word (the original = keep it)
    private var choiceCache: Pair<String, Map<String, String>> = Pair("", emptyMap())
    fun swapChoices(): Map<String, String> {
        val r = prefs.getString("ff-swaps") ?: ""
        synchronized(vocabLock) {
            if (r != choiceCache.first) {
                val m = try { if (r.isEmpty()) emptyMap() else JReader(r).strMap() } catch (_: Exception) { emptyMap() }
                choiceCache = Pair(r, m)
            }
            return choiceCache.second
        }
    }

    private var offCache: Pair<String, Set<String>> = Pair("", emptySet())
    fun swapsOff(): Set<String> {
        val r = prefs.getString("ff-swap-off") ?: ""
        synchronized(vocabLock) {
            if (r != offCache.first) {
                val s = try { if (r.isEmpty()) emptySet() else JReader(r).strList().toSet() } catch (_: Exception) { emptySet() }
                offCache = Pair(r, s)
            }
            return offCache.second
        }
    }

    fun vocabSwap(word: String, place: Int, zh: String?): Pair<String, List<String>>? {
        val cands = vocabCandidates(word, place, zh)
        if (cands.isEmpty()) return null
        swapChoices()["$place|$word"]?.let { c ->
            if (c == word) return null
            cands.firstOrNull { it.han == c }?.let { return Pair(it.han, it.codes) }
        }
        return cands.firstOrNull { it.auto }?.let { Pair(it.han, it.codes) }
    }

    /** the example with the words the place says differently swapped in */
    fun localizedExample(han: String, tpl: String, place: Int, zh: String?): Localized {
        val chars = han.cps()
        val hanIdx = hanIndices(chars)
        val tks = tplTokens(tpl)
        if (tks.isEmpty() || tks.size != hanIdx.size) return Localized(han, tpl, emptySet(), emptyMap())
        val off = swapsOff().contains(swapOffKey(han, place))
        val groups = groupsOf(tks.map { it.sep })
        val origin = HashMap<Int, String>()
        class Swap(val len: Int, val han: String, val codes: List<String>)
        val swaps = HashMap<Int, Swap>()
        val kept = HashMap<Int, Pair<Int, String>>()
        for (g in groups) {
            var a = 0
            while (a < g.size) {
                var step = 1
                for (L in (g.size - a) downTo 1) {
                    val seg = g.subList(a, a + L)
                    val w = seg.joinToString("") { chars[hanIdx[it]] }
                    val k = w + "\t" + seg.joinToString(" ") { tks[it].code }
                    if (baseKeys.contains(k) || altParent[k] != null) {
                        val r = if (!off) vocabSwap(w, place, zh) else null
                        if (r != null) { swaps[seg[0]] = Swap(L, r.first, r.second); origin[seg[0]] = w }
                        else if (vocabOptions(w, place, zh).isNotEmpty()) kept[seg[0]] = Pair(L, w)
                        step = L; break
                    }
                }
                a += step
            }
        }
        if (swaps.isEmpty() && kept.isEmpty()) return Localized(han, tpl, emptySet(), emptyMap())
        // new template
        val outT = StringBuilder()
        var n = 0
        while (n < tks.size) {
            outT.append(tks[n].sep)
            val s = swaps[n]
            if (s != null) {
                outT.append(s.codes.withIndex().joinToString("-") { (j, c) -> "{" + (if (j == 0 && tks[n].cap) "^" else "") + "!" + c + "}" })
                n += s.len
            } else {
                outT.append(tpl.substring(tks[n].start, tks[n].end))
                n++
            }
        }
        outT.append(tpl.substring(tks[tks.size - 1].end))
        // new 漢字
        val outH = ArrayList<String>()
        val swapped = HashSet<Int>(); val skip = HashSet<Int>(); val words = HashMap<Int, String>()
        val pos = HashMap<Int, Int>()
        for ((s, ci) in hanIdx.withIndex()) pos[ci] = s
        for ((ci, ch) in chars.withIndex()) {
            if (skip.contains(ci)) continue
            val syl = pos[ci]
            if (syl != null) {
                val k = kept[syl]
                if (k != null) {
                    for (j in 0 until k.first) {
                        if (syl + j >= hanIdx.size) break
                        words[outH.size] = k.second; outH.add(chars[hanIdx[syl + j]]); if (j > 0) skip.add(hanIdx[syl + j])
                    }
                    continue
                }
                val s = swaps[syl]
                if (s != null) {
                    for (c in s.han.cps()) { swapped.add(outH.size); words[outH.size] = origin[syl] ?: ""; outH.add(c) }
                    for (j in 1 until maxOf(s.len, 1)) if (syl + j < hanIdx.size) skip.add(hanIdx[syl + j])
                    continue
                }
            }
            outH.add(ch)
        }
        return Localized(outH.joinToString(""), outT.toString(), swapped, words)
    }

    fun sentence(tpl: String, sys: Int, place: Int = -1, han: String? = null): String =
        sentencePieces(tpl, sys, place, han).joinToString("") { it.first }

    /** an example sentence's 漢字 split into words: (text, dictionary key or null) */
    fun exampleWords(han: String, tpl: String): List<Pair<String, String?>> {
        val tks = tplTokens(tpl)
        val codes = tks.map { it.code }
        val chars = han.cps()
        val hanIdx = hanIndices(chars)
        if (codes.isEmpty() || codes.size != hanIdx.size) return listOf(Pair(han, null))
        val keyOf = arrayOfNulls<String>(codes.size)
        val groups = groupsOf(tks.map { it.sep })
        fun key(seg: List<Int>) = seg.joinToString("") { chars[hanIdx[it]] } + "\t" + seg.joinToString(" ") { codes[it] }
        fun found(k: String): String? = if (baseKeys.contains(k)) k else altParent[k]
        for (g in groups) {
            var a = 0
            while (a < g.size) {
                var step = 1
                for (L in (g.size - a) downTo 1) {
                    val k = found(key(g.subList(a, a + L)))
                    if (k != null) {
                        for (n in g.subList(a, a + L)) keyOf[n] = k
                        step = L; break
                    }
                }
                a += step
            }
        }
        val out = ArrayList<Pair<String, String?>>()
        var n = 0; var lastGroup = -1
        val groupOf = IntArray(codes.size)
        for ((gi, g) in groups.withIndex()) for (x in g) groupOf[x] = gi
        for ((i, ch) in chars.withIndex()) {
            if (n < hanIdx.size && hanIdx[n] == i) {
                val k = keyOf[n]
                val last = out.lastOrNull()
                if (last != null && last.second == k && k != null && groupOf[n] == lastGroup) {
                    out[out.size - 1] = Pair(last.first + ch, k)
                } else out.add(Pair(ch, k))
                lastGroup = groupOf[n]
                n++
            } else {
                val last = out.lastOrNull()
                if (last != null && last.second == null) out[out.size - 1] = Pair(last.first + ch, null) else out.add(Pair(ch, null))
                lastGroup = -1
            }
        }
        return out
    }

    /** 例句填空 sentence in 羅馬字 for a place: the word's syllables blanked out, the rest in local readings */
    fun blankSentencePieces(tpl: String, han: String, codes: List<String>, sys: Int, place: Int): List<Pair<String, Boolean>>? {
        val base = tplCodes(tpl)
        if (codes.isEmpty() || base.size < codes.size) return null
        val at = (0..(base.size - codes.size)).firstOrNull { base.subList(it, it + codes.size) == codes } ?: return null
        val t = if (place >= 0) dialectTemplate(han, tpl, place) else tpl
        return sentencePieces(blanked(t, at, at + codes.size), sys, place)
    }

    fun hasGuess(tpl: String, han: String, place: Int): Boolean {
        if (place < 0) return false
        val t = dialectTemplate(han, tpl, place)
        return t.contains("{?") || t.contains("{^?")
    }

    private val dialectCache = HashMap<String, String>()

    fun dialectTemplate(han: String, tpl: String, place: Int): String {
        val ck = "$place|$tpl"
        synchronized(dialectCache) { dialectCache[ck]?.let { return it } }
        val r = makeDialectTemplate(han, tpl, place)
        synchronized(dialectCache) { dialectCache[ck] = r }
        return r
    }

    private fun makeDialectTemplate(han: String, tpl: String, place: Int): String {
        val hs = han.cps().filter { ConvertEngine.isHan(it.firstCp()) }
        val tks = tplTokens(tpl)
        if (tks.isEmpty() || tks.size != hs.size) return tpl
        val groups = groupsOf(tks.map { it.sep })
        val rep = HashMap<Int, String>()
        fun key(seg: List<Int>) = seg.joinToString("") { hs[it] } + "\t" + seg.joinToString(" ") { tks[it].code }
        fun use(seg: List<Int>, k: String, whole: Boolean) {
            val dc = raw.dia[k]?.get(place.toString()) ?: return
            val cs = dc.split(' ')
            if (cs.size != seg.size) return
            val sure = whole && isStated(k, place)
            for ((j, n) in seg.withIndex()) rep[n] = if (sure || sameSound(tks[n].code, cs[j], place)) cs[j] else "?" + cs[j]
        }
        for (g in groups) {
            if (baseKeys.contains(key(g))) { use(g, key(g), true); continue }
            val parts = ArrayList<List<Int>>()
            var from = 0
            for ((j, n) in g.withIndex()) if (j > 0 && tks[n].sep == "--") { parts.add(g.subList(from, j)); from = j }
            parts.add(g.subList(from, g.size))
            for (part in parts) {
                if (baseKeys.contains(key(part))) { use(part, key(part), true); continue }
                var a = 0
                while (a < part.size) {
                    var step = 1
                    for (L in (part.size - a) downTo 1) {
                        val seg = part.subList(a, a + L); val k = key(seg)
                        if (baseKeys.contains(k)) { use(seg, k, false); step = L; break }
                    }
                    a += step
                }
            }
        }
        if (rep.isEmpty()) return tpl
        val sb = StringBuilder(tpl)
        for (n in tks.indices.reversed()) {
            val c = rep[n] ?: continue
            sb.replace(tks[n].codeStart, tks[n].end - 1, c)
        }
        return sb.toString()
    }

    /** the place's other way(s) of saying the word, as codes */
    fun alsoSaid(key: String, place: Int): List<String> = if (place < 0) emptyList() else raw.dia2?.get(key)?.get(place.toString()) ?: emptyList()

    class OtherReading(val label: String, val codes: String, val tokens: String?)

    fun others(key: String, place: Int): List<OtherReading> {
        val out = ArrayList<OtherReading>()
        val main = codesOf(key); val shown = codesFor(key, place)
        for (x in alsoSaid(key, place)) if (x != shown) out.add(OtherReading("也講", x, null))
        if (differsFromCommon(key, place) && !alsoSaid(key, place).contains(main)) out.add(OtherReading("通行", main, raw.tok[key]))
        for (a in raw.alt[key] ?: emptyList()) {
            if (a.isEmpty() || a[0] == shown) continue
            out.add(OtherReading(if (a.size > 1 && a[1].isNotEmpty()) a[1] else "又", a[0], if (a.size > 2) a[2] else null))
        }
        return out
    }

    // MARK: sentences with a word

    private var sentenceIndex: Map<String, List<Pair<List<String>, String>>>? = null

    fun sentences(keys: List<String>, limit: Int = 300): List<SentenceHit> {
        if (keys.isEmpty()) return emptyList()
        val idx: Map<String, List<Pair<List<String>, String>>>
        synchronized(this) {
            if (sentenceIndex == null) {
                val m = HashMap<String, MutableList<Pair<List<String>, String>>>()
                for ((entry, senses) in raw.ex) for (exs in senses) for (e in exs) {
                    if (e.size <= 1) continue
                    val seen = HashSet<String>()
                    for (p in exampleWords(e[0], e[1])) {
                        val k = p.second ?: continue
                        if (seen.add(k)) m.getOrPut(k) { ArrayList() }.add(Pair(e, entry))
                    }
                }
                sentenceIndex = m
            }
            idx = sentenceIndex!!
        }
        val out = ArrayList<SentenceHit>(); val seenHan = HashSet<String>()
        for (k in keys) for (h in idx[k] ?: emptyList()) if (seenHan.add(h.first[0])) out.add(SentenceHit(h.first, h.second, k))
        return out.sortedBy { it.ex[0].cpCount }.take(limit)
    }

    // MARK: meanings

    private val numRe = Regex("^\\d+\\.\\s*")

    fun senses(key: String): List<DictSense> {
        val di = raw.defs.m[key] ?: return emptyList()
        val pos = (raw.pos[key] ?: "").split("|")
        val sy = raw.sy[key] ?: emptyMap(); val an = raw.an[key] ?: emptyMap()
        return raw.defs.t[di].split("\n").withIndex().map { (i, line) ->
            val text = numRe.find(line)?.let { line.substring(it.range.last + 1) } ?: line
            val exs = raw.ex[key]?.let { if (i < it.size) it[i] else null } ?: emptyList()
            DictSense(i + 1, if (i < pos.size) pos[i] else "", text, exs, sy[i.toString()] ?: emptyList(), an[i.toString()] ?: emptyList())
        }
    }

    fun wordLinks(key: String): Pair<List<String>, List<String>> {
        fun pick(m: Map<String, List<String>>?): List<String> {
            if (m == null) return emptyList()
            return (m["e"] ?: emptyList()).filter { x -> !m.any { it.key != "e" && it.value.contains(x) } }
        }
        return Pair(pick(raw.sy[key]), pick(raw.an[key]))
    }

    fun defText(key: String): String? = raw.defs.m[key]?.let { raw.defs.t[it] }

    // MARK: word classes

    fun isVerbWithNoun(key: String): Boolean {
        if (notVerbWithNoun.contains(key)) return false
        val pos = raw.pos[key] ?: return false
        if (!pos.split("|")[0].contains("動詞")) return false
        val hs = hanOf(key).cps(); val cs = codesOf(key).split(' ')
        if (hs.size != cs.size || hs.size <= 1) return false
        for (L in 1 until hs.size) {
            val k = hs.takeLast(L).joinToString("") + "\t" + cs.takeLast(L).joinToString(" ")
            val p = raw.pos[k]
            if (baseKeys.contains(k) && p != null && p.split("|")[0].contains("名詞")) return true
        }
        return false
    }

    private val classCache = HashMap<String, List<String>>()
    fun wordsOfClass(c: String): List<String> = synchronized(classCache) {
        classCache.getOrPut(c) {
            if (c == "離合詞") raw.pos.keys.filter { isVerbWithNoun(it) }
            else raw.pos.mapNotNull { (k, v) -> if (v.split("|").any { it.contains(c) }) k else null }
        }
    }
}

/** a tiny key-value store (the app's settings), so the engine doesn't depend on Android */
interface KeyValue {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
}
