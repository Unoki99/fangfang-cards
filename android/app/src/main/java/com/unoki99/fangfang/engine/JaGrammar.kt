package com.unoki99.fangfang.engine

// MARK: - 日語 grammar: the colours, conjugation (活用), the suffixes the 實驗室 chains, and finding a word's
// dictionary form (食べなかった → 食べる). (The same as the iPhone app's JaGrammar.swift.)

/** the colours: kanji, hiragana, katakana, particles, grammatical suffixes (設定 in 日語 → 日語的顏色) */
object JaColors {
    val names = listOf("漢字", "平假名", "片假名", "助詞", "語尾（助動詞）")
    val standard = listOf(0xffe991, 0x97e6a3, 0x97c2ff, 0xff9494, 0xd4b7ff).map { (0xFF000000.toInt()) or it }
    /** the colours picked (-1 = the standard one); set from Prefs.jaColors */
    @Volatile var picked = IntArray(5) { -1 }
    @Volatile var version = 0
    fun load(vs: List<Int>) { picked = IntArray(5) { vs.getOrElse(it) { -1 } }; version++ }
    fun color(i: Int): Int = picked.getOrElse(i) { -1 }.let { if (it == -1) standard[i] else (0xFF000000.toInt()) or (it and 0xFFFFFF) }
    val kanji get() = color(0)
    val hira get() = color(1)
    val kata get() = color(2)
    val particle get() = color(3)
    val suffix get() = color(4)

    /** a character's colour (null: not kana or kanji, the text's own colour) */
    fun of(ch: String): Int? {
        val cp = ch.firstCp()
        if (JaKana.isKanji(cp)) return kanji
        if (JaKana.isKatakana(cp)) return kata
        if (JaKana.isHiragana(cp)) return hira
        return null
    }
}

/** a piece of a word or sentence, coloured by what it is */
data class JaPiece(
    val text: String,
    val kind: Kind,
    /** what it is (語幹, 使役, 否定…) */
    val label: String = "",
    /** what it does (a sentence) */
    val note: String = "",
    /** its dictionary form (食べる, させる…): the part both have stays, the rest is what changed */
    val dict: String = "",
) {
    enum class Kind { WORD, SUFFIX, PARTICLE, PLAIN }
}

object JaInk {
    /** the pieces as coloured text: words by their script, suffixes and particles in their own colours */
    fun styled(pieces: List<JaPiece>, base: Int? = null): Styled {
        val b = StyledBuilder()
        for (p in pieces) when (p.kind) {
            JaPiece.Kind.SUFFIX -> b.add(p.text, JaColors.suffix)
            JaPiece.Kind.PARTICLE -> b.add(p.text, JaColors.particle)
            else -> for (ch in p.text.cps()) b.add(ch, JaColors.of(ch) ?: base)
        }
        return b.build()
    }
    fun word(s: String, base: Int? = null): Styled = styled(listOf(JaPiece(s, JaPiece.Kind.WORD)), base)

    /** a sentence written with marks: [は] a particle, {ます} a suffix, the rest by script */
    fun marked(s: String): List<JaPiece> {
        val out = ArrayList<JaPiece>()
        val cur = StringBuilder()
        var kind = JaPiece.Kind.WORD
        fun flush() { if (cur.isNotEmpty()) out.add(JaPiece(cur.toString(), kind)); cur.setLength(0) }
        for (ch in s) when (ch) {
            '[' -> { flush(); kind = JaPiece.Kind.PARTICLE }
            '{' -> { flush(); kind = JaPiece.Kind.SUFFIX }
            ']', '}' -> { flush(); kind = JaPiece.Kind.WORD }
            else -> cur.append(ch)
        }
        flush()
        return out
    }
    fun plainText(marked: String): String = marked.filter { it !in "[]{}" }
}

// MARK: conjugation

enum class JaSpecial { NONE, IKU, ARU, NASARU, US }

sealed class JaClass {
    data class Godan(val k: String, val sp: JaSpecial = JaSpecial.NONE) : JaClass()
    object Ichidan : JaClass()
    object Suru : JaClass()
    object Kuru : JaClass()
    object AdjI : JaClass()
    object AdjII : JaClass()
    object AdjNa : JaClass()
    object Masu : JaClass()
    object Masen : JaClass()
    object Te : JaClass()
    object Done : JaClass()

    val isVerb: Boolean get() = this is Godan || this === Ichidan || this === Suru || this === Kuru
    val isAdj: Boolean get() = this === AdjI || this === AdjII
    val isAru: Boolean get() = this is Godan && sp == JaSpecial.ARU
    val name: String get() = when (this) {
        is Godan -> "五段動詞"
        Ichidan -> "一段動詞"
        Suru -> "サ變動詞（する）"
        Kuru -> "カ變動詞（来る）"
        AdjI, AdjII -> "い形容詞"
        AdjNa -> "な形容詞"
        else -> ""
    }
}

enum class JaForm(val title: String) {
    A("未然形"), A_SA("未然形"), I("連用形"), U("終止形（辭書形）"), E("假定形"), O("意向形"),
    TE("て形"), TA("た形"), IMP("命令形"), BARE("語幹")
}

object JaGrammar {
    val rows: Map<String, List<String>> = mapOf(
        "く" to listOf("か", "き", "く", "け", "こ"), "ぐ" to listOf("が", "ぎ", "ぐ", "げ", "ご"), "す" to listOf("さ", "し", "す", "せ", "そ"),
        "つ" to listOf("た", "ち", "つ", "て", "と"), "ぬ" to listOf("な", "に", "ぬ", "ね", "の"), "ぶ" to listOf("ば", "び", "ぶ", "べ", "ぼ"),
        "む" to listOf("ま", "み", "む", "め", "も"), "る" to listOf("ら", "り", "る", "れ", "ろ"), "う" to listOf("わ", "い", "う", "え", "お"),
    )
    val vowelRow = listOf("あ段", "い段", "う段", "え段", "お段")

    /** the class of a dictionary word, and the text that conjugates (a する noun gets its する) */
    fun classOf(e: ZhEntry): Pair<JaClass, String>? = classOf(e.jp, e.h, e.tw.joinToString(""))

    fun classOf(pos: List<String>, head: String, reading: String): Pair<JaClass, String>? {
        val last = if (reading.isEmpty()) "" else reading.cps().last()
        for (p in pos) {
            when (p) {
                "v1", "v1-s" -> return JaClass.Ichidan to head
                "v5k-s" -> return JaClass.Godan("く", JaSpecial.IKU) to head
                "v5r-i" -> return JaClass.Godan("る", JaSpecial.ARU) to head
                "v5aru" -> return JaClass.Godan("る", JaSpecial.NASARU) to head
                "v5u-s" -> return JaClass.Godan("う", JaSpecial.US) to head
                "v5u", "v5k", "v5g", "v5s", "v5t", "v5n", "v5b", "v5m", "v5r" ->
                    return if (rows.containsKey(last)) JaClass.Godan(last) to head else null
                "vk" -> return JaClass.Kuru to head
                "vs-i", "vs-s" -> return if (head.endsWith("する") || head.endsWith("為る")) JaClass.Suru to head else null
                "adj-i" -> return if (head.endsWith("い")) JaClass.AdjI to head else null
                "adj-ix" -> return JaClass.AdjII to head
            }
        }
        if ("vs" in pos) return JaClass.Suru to head + "する"
        if ("adj-na" in pos) return JaClass.AdjNa to head
        return null
    }

    /** the same, for the reading (kana) */
    fun readingOf(e: ZhEntry, c: JaClass): String {
        val r = e.tw.joinToString("")
        if (c === JaClass.Suru && !e.h.endsWith("する") && !e.h.endsWith("為る")) return r + "する"
        return r
    }

    private fun drop(s: String, n: Int): String { val cs = s.cps(); return cs.take(maxOf(0, cs.size - n)).joinToString("") }
    fun voiced(c: JaClass): Boolean = c is JaClass.Godan && c.k in listOf("ぐ", "ぬ", "ぶ", "む")

    /** the text in a form ("書く", godan く, A → "書か"); null: no such form */
    fun stem(t: String, c: JaClass, f: JaForm): String? {
        when (c) {
            is JaClass.Godan -> {
                val r = rows[c.k] ?: return null
                val sp = c.sp
                val b = drop(t, 1)
                return when (f) {
                    JaForm.A, JaForm.A_SA -> if (sp == JaSpecial.ARU) drop(t, 2) else b + r[0]
                    JaForm.I -> if (sp == JaSpecial.NASARU) b + "い" else b + r[1]
                    JaForm.U -> t
                    JaForm.E -> b + r[3]
                    JaForm.O -> b + r[4]
                    JaForm.IMP -> if (sp == JaSpecial.NASARU) b + "い" else b + r[3]
                    JaForm.TE, JaForm.TA -> when {
                        sp == JaSpecial.IKU -> b + "っ"
                        sp == JaSpecial.US -> t
                        c.k == "く" || c.k == "ぐ" -> b + "い"
                        c.k == "す" -> b + "し"
                        c.k == "ぬ" || c.k == "ぶ" || c.k == "む" -> b + "ん"
                        else -> b + "っ"
                    }
                    JaForm.BARE -> b + r[1]
                }
            }
            JaClass.Ichidan -> {
                val b = drop(t, 1)
                return when (f) {
                    JaForm.A, JaForm.A_SA, JaForm.I, JaForm.TE, JaForm.TA, JaForm.BARE -> b
                    JaForm.U -> t
                    JaForm.E -> b + "れ"
                    JaForm.O -> b + "よ"
                    JaForm.IMP -> b + "ろ"
                }
            }
            JaClass.Suru -> {
                val b = drop(t, 2)
                return when (f) {
                    JaForm.A, JaForm.I, JaForm.TE, JaForm.TA -> b + "し"
                    JaForm.A_SA -> b + "さ"
                    JaForm.U -> t
                    JaForm.E -> b + "すれ"
                    JaForm.O -> b + "しよ"
                    JaForm.IMP -> b + "しろ"
                    JaForm.BARE -> b
                }
            }
            JaClass.Kuru -> {
                if (t.startsWith("来")) return when (f) {
                    JaForm.U -> t
                    JaForm.E -> "来れ"
                    JaForm.O -> "来よ"
                    JaForm.IMP -> "来い"
                    else -> "来"
                }
                return when (f) {
                    JaForm.A, JaForm.A_SA -> "こ"
                    JaForm.I, JaForm.TE, JaForm.TA, JaForm.BARE -> "き"
                    JaForm.U -> t
                    JaForm.E -> "くれ"
                    JaForm.O -> "こよ"
                    JaForm.IMP -> "こい"
                }
            }
            JaClass.AdjI, JaClass.AdjII -> {
                val b = if (c === JaClass.AdjII) (if (t.startsWith("良")) "良" else "よ") else drop(t, 1)
                return when (f) {
                    JaForm.A, JaForm.I, JaForm.TE -> b + "く"
                    JaForm.U -> t
                    JaForm.E -> b + "けれ"
                    JaForm.O -> b + "かろ"
                    JaForm.TA -> b + "かっ"
                    JaForm.BARE -> if (c === JaClass.AdjII) b + "さ" else b
                    else -> null
                }
            }
            JaClass.AdjNa -> return when (f) {
                JaForm.A -> t + "じゃ"
                JaForm.TA -> t + "だっ"
                JaForm.U, JaForm.BARE, JaForm.TE, JaForm.I -> t
                else -> null
            }
            JaClass.Masu -> return when (f) {
                JaForm.A -> "ませ"
                JaForm.I, JaForm.TE, JaForm.TA -> "まし"
                JaForm.U -> t
                JaForm.O -> "ましょ"
                else -> null
            }
            JaClass.Masen, JaClass.Te -> return if (f == JaForm.U) t else null
            JaClass.Done -> return null
        }
        return null
    }

    // MARK: the suffixes

    class Attach(val form: JaForm, val text: String, val makes: JaClass)

    class Suffix(
        val id: String,
        /** its name (中文) */
        val name: String,
        /** what it does (中文) */
        val note: String,
        val kind: JaPiece.Kind = JaPiece.Kind.SUFFIX,
        /** for the class before it: the form that class must be in, the suffix's text, and the class it makes */
        val attach: (JaClass) -> Attach?,
    )

    private fun a(f: JaForm, t: String, c: JaClass) = Attach(f, t, c)
    private val P = JaPiece.Kind.PARTICLE

    val suffixes: List<Suffix> = listOf(
        Suffix("nai", "否定 ない", "「不…」。接在未然形後面；ない自己像い形容詞一樣活用（なかった、なくて）。") { c ->
            if (c.isVerb || c.isAdj || c === JaClass.AdjNa) a(JaForm.A, "ない", JaClass.AdjI) else null
        },
        Suffix("masu", "禮貌 ます", "有禮貌的說法。接在連用形（ます形）後面。") { c -> if (c.isVerb) a(JaForm.I, "ます", JaClass.Masu) else null },
        Suffix("masen", "否定 ん", "ます的否定：ませ＋ん。") { c -> if (c === JaClass.Masu) a(JaForm.A, "ん", JaClass.Masen) else null },
        Suffix("deshita", "過去 でした", "ません的過去：ませんでした。") { c -> if (c === JaClass.Masen) a(JaForm.U, "でした", JaClass.Done) else null },
        Suffix("ta", "過去 た", "過去或完成。動詞用た形（音便：書いた、読んだ）。") { c ->
            when {
                c.isVerb -> a(JaForm.TA, if (voiced(c)) "だ" else "た", JaClass.Done)
                c.isAdj || c === JaClass.AdjNa || c === JaClass.Masu -> a(JaForm.TA, "た", JaClass.Done)
                else -> null
            }
        },
        Suffix("te", "て形 て", "連接下一個動作「…然後…」，也接いる、しまう、ください。") { c ->
            when {
                c.isVerb -> a(JaForm.TE, if (voiced(c)) "で" else "て", JaClass.Te)
                c.isAdj || c === JaClass.Masu -> a(JaForm.TE, "て", JaClass.Te)
                c === JaClass.AdjNa -> a(JaForm.TE, "で", JaClass.Te)
                else -> null
            }
        },
        Suffix("tara", "條件 たら", "「…了以後／要是…的話」。") { c ->
            when {
                c.isVerb -> a(JaForm.TA, if (voiced(c)) "だら" else "たら", JaClass.Done)
                c.isAdj || c === JaClass.AdjNa || c === JaClass.Masu -> a(JaForm.TA, "たら", JaClass.Done)
                else -> null
            }
        },
        Suffix("ba", "條件 ば", "「如果…」。接在假定形（え段）後面。") { c ->
            when {
                c.isVerb || c.isAdj -> a(JaForm.E, "ば", JaClass.Done)
                c === JaClass.AdjNa -> a(JaForm.U, "なら", JaClass.Done)
                else -> null
            }
        },
        Suffix("you", "意向 う／よう", "「…吧！（一起）」或「打算…」。接在意向形（お段）後面。") { c ->
            if (c.isVerb || c === JaClass.Masu) a(JaForm.O, "う", JaClass.Done) else null
        },
        Suffix("imp", "命令", "命令「…！」。五段動詞用え段，一段動詞加ろ。") { c -> if (c.isVerb) a(JaForm.IMP, "", JaClass.Done) else null },
        Suffix("tai", "願望 たい", "「想…」。接在連用形後面；たい像い形容詞一樣活用。") { c -> if (c.isVerb) a(JaForm.I, "たい", JaClass.AdjI) else null },
        Suffix("seru", "使役 せる／させる", "「讓（人）…、叫（人）…」。五段動詞＋せる，其他＋させる；變成一段動詞。") { c ->
            when (c) {
                is JaClass.Godan -> a(JaForm.A, "せる", JaClass.Ichidan)
                JaClass.Ichidan, JaClass.Kuru -> a(JaForm.A, "させる", JaClass.Ichidan)
                JaClass.Suru -> a(JaForm.A_SA, "せる", JaClass.Ichidan)
                else -> null
            }
        },
        Suffix("reru", "被動 れる／られる", "「被…」（也是尊敬）。五段動詞＋れる，其他＋られる；變成一段動詞。") { c ->
            when (c) {
                is JaClass.Godan -> a(JaForm.A, "れる", JaClass.Ichidan)
                JaClass.Ichidan, JaClass.Kuru -> a(JaForm.A, "られる", JaClass.Ichidan)
                JaClass.Suru -> a(JaForm.A_SA, "れる", JaClass.Ichidan)
                else -> null
            }
        },
        Suffix("pot", "可能", "「能…、會…」。五段動詞：え段＋る；一段動詞：＋られる；する → できる。") { c ->
            when {
                c is JaClass.Godan && c.sp != JaSpecial.ARU -> a(JaForm.E, "る", JaClass.Ichidan)
                c === JaClass.Ichidan || c === JaClass.Kuru -> a(JaForm.A, "られる", JaClass.Ichidan)
                c === JaClass.Suru -> a(JaForm.BARE, "できる", JaClass.Ichidan)
                else -> null
            }
        },
        Suffix("nagara", "同時 ながら", "「一邊…一邊…」。接在連用形後面。") { c -> if (c.isVerb) a(JaForm.I, "ながら", JaClass.Done) else null },
        Suffix("naide", "ないで", "「不…（就）…、別…」。") { c -> if (c.isVerb) a(JaForm.A, "ないで", JaClass.Done) else null },
        Suffix("sou", "樣態 そう", "「看起來好像…」。動詞接連用形，形容詞接語幹。") { c ->
            when {
                c.isVerb -> a(JaForm.I, "そう", JaClass.AdjNa)
                c.isAdj -> a(JaForm.BARE, "そう", JaClass.AdjNa)
                c === JaClass.AdjNa -> a(JaForm.U, "そう", JaClass.AdjNa)
                else -> null
            }
        },
        Suffix("naru", "變成 なる", "「變得…」。い形容詞く＋なる，な形容詞に＋なる。") { c ->
            when {
                c.isAdj -> a(JaForm.I, "なる", JaClass.Godan("る"))
                c === JaClass.AdjNa -> a(JaForm.U, "になる", JaClass.Godan("る"))
                else -> null
            }
        },
        Suffix("iru", "持續 いる", "「正在…、…著」。て形＋いる；變成一段動詞。") { c -> if (c === JaClass.Te) a(JaForm.U, "いる", JaClass.Ichidan) else null },
        Suffix("shimau", "完了 しまう", "「…完了、不小心…了」。て形＋しまう。") { c -> if (c === JaClass.Te) a(JaForm.U, "しまう", JaClass.Godan("う")) else null },
        Suffix("miru", "嘗試 みる", "「…看看」。て形＋みる。") { c -> if (c === JaClass.Te) a(JaForm.U, "みる", JaClass.Ichidan) else null },
        Suffix("kudasai", "請求 ください", "「請…」。て形＋ください。") { c -> if (c === JaClass.Te) a(JaForm.U, "ください", JaClass.Done) else null },
        Suffix("desu", "禮貌 です", "形容詞的禮貌說法。") { c -> if (c.isAdj || c === JaClass.AdjNa) a(JaForm.U, "です", JaClass.Done) else null },
        Suffix("da", "斷定 だ", "な形容詞的普通說法「是…的」。") { c -> if (c === JaClass.AdjNa) a(JaForm.U, "だ", JaClass.Done) else null },
        Suffix("na", "連體 な", "放在名詞前面修飾名詞（静かな部屋）。", P) { c -> if (c === JaClass.AdjNa) a(JaForm.U, "な", JaClass.Done) else null },
        Suffix("kara", "原因 から", "「因為…」。", P) { c ->
            if (c.isVerb || c.isAdj || c === JaClass.Masu || c === JaClass.Masen) a(JaForm.U, "から", JaClass.Done) else null
        },
        Suffix("tekara", "之後 から", "「…之後（再…）」。て形＋から。", P) { c -> if (c === JaClass.Te) a(JaForm.U, "から", JaClass.Done) else null },
        Suffix("to", "條件 と", "「一…就…」（每次都會這樣）。", P) { c ->
            if (c.isVerb || c.isAdj || c === JaClass.Masu) a(JaForm.U, "と", JaClass.Done) else null
        },
    )
    fun suffix(id: String): Suffix? = suffixes.firstOrNull { it.id == id }

    /** what can really follow each ending (the class alone lets through things nobody says: ない after ない gives
     *  食べなくなくない…, させ after させ, られ after られ). Not here: after the word itself, everything its class takes. */
    val after: Map<String, Set<String>> = mapOf(
        // 使役 (食べさせる): + 被動 = 使役受身 (食べさせられる); not 使役 again, not 可能
        "seru" to setOf("nai", "masu", "ta", "te", "tara", "ba", "you", "imp", "tai", "reru", "nagara", "naide", "sou", "kara", "to"),
        // 被動 (食べられる): not 使役 or 被動 again, no 命令 / 意向
        "reru" to setOf("nai", "masu", "ta", "te", "tara", "ba", "tai", "nagara", "naide", "sou", "kara", "to"),
        // 可能 (書ける): a state: no 命令, 意向, 願望, ながら
        "pot" to setOf("nai", "masu", "ta", "te", "tara", "ba", "sou", "kara", "to"),
        // ない: なかった, なくて, なければ, なかったら, ないです, なくなる (not ない again)
        "nai" to setOf("ta", "te", "ba", "tara", "desu", "naru", "kara", "to"),
        "tai" to setOf("nai", "ta", "te", "ba", "tara", "desu", "naru", "kara", "to"),
        "naru" to setOf("nai", "masu", "ta", "te", "tara", "ba", "you", "tai", "sou", "pot", "kara", "to"),
        "masu" to setOf("masen", "ta", "te", "tara", "you", "kara", "to"),
        "masen" to setOf("deshita", "kara"),
        "te" to setOf("iru", "shimau", "miru", "kudasai", "tekara"),
        "iru" to setOf("nai", "masu", "ta", "te", "tara", "ba", "you", "tai", "kara", "to"),
        "shimau" to setOf("nai", "masu", "ta", "te", "tara", "ba", "you", "tai", "sou", "kara", "to"),
        "miru" to setOf("nai", "masu", "ta", "te", "tara", "ba", "you", "tai", "kara", "to"),
        "sou" to setOf("da", "desu", "na", "ta", "te", "ba", "naru"),
    )
    /** ある: no 使役, 被動, 可能, 命令, 願望, 意向 */
    private val notAfterAru = setOf("seru", "reru", "pot", "imp", "tai", "you")

    /** can this ending come after the chain as it is? */
    fun allowed(c: Chain, id: String): Boolean {
        // each ending once (て may come twice: ていて)
        if (id != "te" && id in c.ops) return false
        if (c.ops.lastOrNull() == "te") {
            val prev = c.ops.dropLast(1).lastOrNull()
            var verbal = if (prev != null) prev in setOf("seru", "reru", "pot", "naru", "shimau") else c.base.isVerb
            if (c.base.isAru && prev == null) verbal = false
            if (verbal) return id in setOf("iru", "shimau", "miru", "kudasai", "tekara")
            if (prev == "iru" || prev == "miru") return id in setOf("kudasai", "tekara")
            return false
        }
        c.ops.lastOrNull()?.let { return after[it]?.contains(id) ?: false }
        if (c.cls.isAru && id in notAfterAru) return false
        return true
    }

    /** a conjugation being built: the pieces, and the class of the last one (the one that conjugates next) */
    class Chain private constructor(val pieces: List<JaPiece>, val cls: JaClass, val ops: List<String>, val base: JaClass) {
        constructor(text: String, cls: JaClass, label: String = "") :
            this(listOf(JaPiece(text, JaPiece.Kind.WORD, label.ifEmpty { cls.name }, "", text)), cls, emptyList(), cls)

        /** the suffixes that can come next */
        val next: List<Suffix> get() = suffixes.filter { it.attach(cls) != null && allowed(this, it.id) }

        /** with one more suffix (null: it can't come here) */
        fun adding(id: String): Chain? {
            if (!allowed(this, id)) return null
            val s = suffix(id) ?: return null
            val at = s.attach(cls) ?: return null
            val last = pieces.lastOrNull() ?: return null
            val st = stem(last.text, cls, at.form) ?: return null
            var form = at.form.title
            if (cls is JaClass.Godan && at.form in setOf(JaForm.A, JaForm.I, JaForm.E, JaForm.O, JaForm.IMP)) {
                val r = rows[cls.k]
                val i = r?.indexOfFirst { st.endsWith(it) } ?: -1
                if (i >= 0) form += "（" + vowelRow[i] + "）"
            }
            val p = last.copy(text = st, note = (if (last.note.isEmpty()) "" else last.note + "　") + "→ " + form)
            val ps = pieces.dropLast(1) + p + JaPiece(at.text, s.kind, s.name, s.note, at.text)
            return Chain(ps, at.makes, ops + id, base)
        }
        fun adding(ids: List<String>): Chain? {
            var c: Chain? = this
            for (i in ids) c = c?.adding(i)
            return c
        }
        val text: String get() = pieces.joinToString("") { it.text }
    }

    /** the rows of the 活用 table: (name, English, suffixes) */
    fun table(c: JaClass): List<Triple<String, String, List<String>>> {
        fun t(a: String, b: String, vararg s: String) = Triple(a, b, s.toList())
        if (c.isVerb) {
            val l = mutableListOf(
                t("辭書形", "dictionary"), t("ます形", "polite", "masu"),
                t("ない形", "negative", "nai"), t("ません", "polite negative", "masu", "masen"),
                t("た形", "past", "ta"), t("ました", "polite past", "masu", "ta"),
                t("なかった", "past negative", "nai", "ta"), t("ませんでした", "polite past negative", "masu", "masen", "deshita"),
                t("て形", "te-form", "te"), t("ている", "progressive", "te", "iru"),
                t("ないで", "without doing", "naide"), t("たい", "want to", "tai"),
                t("可能形", "potential", "pot"), t("受身形", "passive", "reru"),
                t("使役形", "causative", "seru"), t("使役受身", "causative-passive", "seru", "reru"),
                t("意向形", "volitional", "you"), t("ましょう", "polite volitional", "masu", "you"),
                t("命令形", "imperative", "imp"), t("ば形", "conditional", "ba"),
                t("たら", "if / when", "tara"), t("ながら", "while", "nagara"),
            )
            if (c.isAru) l.removeAll { it.third == listOf("pot") }
            return l
        }
        if (c.isAdj) return listOf(t("辭書形", "dictionary"), t("です", "polite", "desu"), t("否定", "negative", "nai"),
            t("過去", "past", "ta"), t("過去否定", "past negative", "nai", "ta"), t("て形", "te-form", "te"),
            t("ば形", "conditional", "ba"), t("たら", "if / when", "tara"), t("～そう", "looks", "sou"), t("～なる", "become", "naru"))
        if (c === JaClass.AdjNa) return listOf(t("～だ", "plain", "da"), t("～です", "polite", "desu"), t("～な＋名詞", "before a noun", "na"),
            t("否定", "negative", "nai"), t("過去", "past", "ta"), t("過去否定", "past negative", "nai", "ta"),
            t("て形", "te-form", "te"), t("なら", "if", "ba"), t("～そう", "looks", "sou"), t("～になる", "become", "naru"))
        return emptyList()
    }

    /** the 活用 table in groups: forms that belong together (plain and polite, the voices, the conditionals) side by side */
    class ConjGroup(val name: String, val en: String, val color: Int, val rows: List<Triple<String, String, List<String>>>)

    fun groups(c: JaClass): List<ConjGroup> {
        val t = table(c)
        fun g(name: String, en: String, color: Int, names: List<String>): ConjGroup? {
            val rows = names.mapNotNull { n -> t.firstOrNull { it.first == n } }
            return if (rows.isEmpty()) null else ConjGroup(name, en, (0xFF000000.toInt()) or color, rows)
        }
        val green = 0x5fd38d; val red = 0xff6b6b; val yellow = 0xffd95a; val blue = 0x6eaaff
        val purple = 0xb38bff; val pink = 0xff8cc6; val orange = 0xffa94d; val teal = 0x4fd8c4
        val wine = 0xd0577a; val olive = 0x9ccc5a; val violet = 0x8f6bd8
        val out = if (c.isVerb) listOf(
            g("現在", "present", green, listOf("辭書形", "ます形")),
            g("否定", "negative", red, listOf("ない形", "ません")),
            g("過去", "past", yellow, listOf("た形", "ました")),
            g("過去否定", "past negative", blue, listOf("なかった", "ませんでした")),
            g("て形", "te-form", purple, listOf("て形", "ている")),
            g("意向", "volitional", wine, listOf("意向形", "ましょう")),
            g("可能・受身・使役", "potential, passive, causative", orange, listOf("可能形", "受身形", "使役形", "使役受身")),
            g("條件・同時", "conditional, while", teal, listOf("ば形", "たら", "ながら")),
            g("ないで", "without", pink, listOf("ないで")),
            g("願望", "want", olive, listOf("たい")),
            g("命令", "imperative", violet, listOf("命令形")),
        ) else if (c.isAdj) listOf(
            g("現在", "present", green, listOf("辭書形", "です")),
            g("否定・過去", "negative, past", red, listOf("否定", "過去", "過去否定")),
            g("て形", "te-form", purple, listOf("て形")),
            g("條件", "conditional", teal, listOf("ば形", "たら")),
            g("樣子・變化", "looks, become", orange, listOf("～そう", "～なる")),
        ) else listOf(
            g("現在", "present", green, listOf("～だ", "～です", "～な＋名詞")),
            g("否定・過去", "negative, past", red, listOf("否定", "過去", "過去否定")),
            g("て形", "te-form", purple, listOf("て形")),
            g("條件", "conditional", teal, listOf("なら")),
            g("樣子・變化", "looks, become", orange, listOf("～そう", "～になる")),
        )
        return out.filterNotNull()
    }

    // MARK: back to the dictionary form (for search)

    private val endings: List<Pair<String, String>> = run {
        val r = mutableListOf(
            // 一段
            "ませんでした" to "る", "ました" to "る", "ません" to "る", "ます" to "る", "なかった" to "る", "ない" to "る",
            "させられる" to "る", "られる" to "る", "させる" to "る", "たい" to "る", "よう" to "る", "れば" to "る",
            "ている" to "る", "た" to "る", "て" to "る", "ろ" to "る", "ながら" to "る",
            // い形容詞
            "くなかった" to "い", "かった" to "い", "くない" to "い", "くて" to "い", "ければ" to "い", "く" to "い", "さ" to "い", "そう" to "い",
            // する・来る
            "しませんでした" to "する", "しました" to "する", "しません" to "する", "します" to "する", "しない" to "する",
            "した" to "する", "して" to "する", "させる" to "する", "される" to "する", "しよう" to "する", "すれば" to "する",
            "しろ" to "する", "できる" to "する", "したい" to "する", "している" to "する",
            "きます" to "くる", "こない" to "くる", "きた" to "くる", "きて" to "くる", "こよう" to "くる", "くれば" to "くる", "こい" to "くる",
            "来ます" to "来る", "来ない" to "来る", "来た" to "来る", "来て" to "来る", "来よう" to "来る", "来れば" to "来る", "来い" to "来る",
            // 五段 て/た
            "いて" to "く", "いた" to "く", "いで" to "ぐ", "いだ" to "ぐ", "して" to "す", "した" to "す",
            "って" to "う", "った" to "う", "って" to "つ", "った" to "つ", "って" to "る", "った" to "る", "って" to "く", "った" to "く",
            "んで" to "む", "んだ" to "む", "んで" to "ぶ", "んだ" to "ぶ", "んで" to "ぬ", "んだ" to "ぬ",
        )
        for ((u, row) in rows) {
            r += row[1] + "ませんでした" to u; r += row[1] + "ました" to u; r += row[1] + "ません" to u
            r += row[1] + "ます" to u; r += row[1] + "たい" to u; r += row[1] + "ながら" to u
            r += row[0] + "なかった" to u; r += row[0] + "ない" to u; r += row[0] + "れる" to u; r += row[0] + "せる" to u
            r += row[0] + "される" to u; r += row[3] + "ば" to u; r += row[3] + "る" to u; r += row[4] + "う" to u
            r += row[3] to u
        }
        r.sortedByDescending { it.first.length }
    }

    /** the dictionary forms a word can be a form of (two steps: 食べさせなかった → 食べさせる → 食べる) */
    fun deinflect(s: String): List<Pair<String, String>> {
        val out = ArrayList<Pair<String, String>>()
        val seen = HashSet<String>()
        var todo = listOf(s)
        repeat(3) {
            val next = ArrayList<String>()
            for (w in todo) {
                for ((end, base) in endings) {
                    if (!w.endsWith(end)) continue
                    if (w.length <= end.length - (if (base == "する" || base == "くる") 1 else 0)) continue
                    val stemPart = w.dropLast(end.length)
                    val b = stemPart + base
                    if (b != w && seen.add(b)) { out.add(b to end); next.add(b) }
                    if (base == "する" && stemPart.isNotEmpty() && seen.add(stemPart)) out.add(stemPart to end)
                }
            }
            todo = next
        }
        return out
    }
}

// MARK: the meaning of a chain in English (roughly: 大意)

object JaEnglish {
    private val irregular: Map<String, Pair<String, String>> = mapOf(
        "be" to ("was" to "been"), "eat" to ("ate" to "eaten"), "go" to ("went" to "gone"), "come" to ("came" to "come"), "see" to ("saw" to "seen"),
        "do" to ("did" to "done"), "make" to ("made" to "made"), "take" to ("took" to "taken"), "give" to ("gave" to "given"), "write" to ("wrote" to "written"),
        "read" to ("read" to "read"), "speak" to ("spoke" to "spoken"), "say" to ("said" to "said"), "buy" to ("bought" to "bought"), "drink" to ("drank" to "drunk"),
        "know" to ("knew" to "known"), "think" to ("thought" to "thought"), "teach" to ("taught" to "taught"), "find" to ("found" to "found"), "tell" to ("told" to "told"),
        "get" to ("got" to "gotten"), "hold" to ("held" to "held"), "leave" to ("left" to "left"), "lose" to ("lost" to "lost"), "meet" to ("met" to "met"),
        "pay" to ("paid" to "paid"), "sell" to ("sold" to "sold"), "send" to ("sent" to "sent"), "stand" to ("stood" to "stood"), "understand" to ("understood" to "understood"),
        "break" to ("broke" to "broken"), "choose" to ("chose" to "chosen"), "forget" to ("forgot" to "forgotten"), "wake" to ("woke" to "woken"),
        "wear" to ("wore" to "worn"), "sleep" to ("slept" to "slept"), "sit" to ("sat" to "sat"), "run" to ("ran" to "run"), "swim" to ("swam" to "swum"),
        "sing" to ("sang" to "sung"), "begin" to ("began" to "begun"), "bring" to ("brought" to "brought"), "build" to ("built" to "built"), "catch" to ("caught" to "caught"),
        "fall" to ("fell" to "fallen"), "feel" to ("felt" to "felt"), "fly" to ("flew" to "flown"), "grow" to ("grew" to "grown"), "hide" to ("hid" to "hidden"),
        "keep" to ("kept" to "kept"), "put" to ("put" to "put"), "ride" to ("rode" to "ridden"), "rise" to ("rose" to "risen"), "shut" to ("shut" to "shut"),
        "steal" to ("stole" to "stolen"), "throw" to ("threw" to "thrown"), "win" to ("won" to "won"), "hear" to ("heard" to "heard"), "have" to ("had" to "had"),
        "let" to ("let" to "let"), "cut" to ("cut" to "cut"), "hit" to ("hit" to "hit"), "lend" to ("lent" to "lent"), "spend" to ("spent" to "spent"),
        "draw" to ("drew" to "drawn"), "become" to ("became" to "become"), "forgive" to ("forgave" to "forgiven"), "lie" to ("lay" to "lain"), "show" to ("showed" to "shown"),
        "want" to ("wanted" to "wanted"), "try" to ("tried" to "tried"), "can" to ("could" to "could"),
    )
    private val doubling = setOf("run", "swim", "sit", "stop", "get", "put", "cut", "begin", "shop", "plan", "hit", "win", "drop", "chat", "jog", "hug", "nod", "rob", "beg", "dig", "let", "set")

    private fun split(p: String): Pair<String, String> { val sp = p.indexOf(' '); return if (sp < 0) p to "" else p.substring(0, sp) to p.substring(sp) }
    fun past(v: String): String {
        irregular[v]?.let { return it.first }
        if (v in doubling && v.isNotEmpty()) return v + v.last() + "ed"
        if (v.endsWith("e")) return v + "d"
        if (v.endsWith("y") && v.length >= 2 && v[v.length - 2] !in "aeiou") return v.dropLast(1) + "ied"
        return v + "ed"
    }
    fun participle(v: String): String = irregular[v]?.second ?: past(v)
    fun gerund(v: String): String {
        if (v == "be") return "being"
        if (v.endsWith("ie")) return v.dropLast(2) + "ying"
        if (v in doubling && v.isNotEmpty()) return v + v.last() + "ing"
        if (v.endsWith("e") && !v.endsWith("ee") && v.length > 2) return v.dropLast(1) + "ing"
        return v + "ing"
    }
    private fun onFirst(p: String, f: (String) -> String): String { val (a, b) = split(p); return f(a) + b }

    /** the first meaning, as a bare verb phrase ("to eat" → "eat"; an adjective: "be big") */
    fun base(e: ZhEntry, c: JaClass): String {
        var g = (e.senses.firstOrNull()?.text ?: "").split(";").first()
        val r = g.indexOf(" ("); if (r >= 0) g = g.substring(0, r)
        if (g.startsWith("to ")) g = g.drop(3)
        if (c.isAdj || c === JaClass.AdjNa) return "be $g"
        return g
    }

    fun compose(base: String, ops: List<String>): String {
        var p = base
        var neg = false; var pastT = false; var polite = false
        var mode = ""
        fun pushNeg() { if (neg) { p = "not $p"; neg = false } }
        for (op in ops) when (op) {
            "seru" -> { pushNeg(); p = "make (someone) $p" }
            "reru" -> { pushNeg(); p = if (p.startsWith("make (someone) ")) "be made to " + p.drop(15) else "be " + onFirst(p, ::participle) }
            "pot" -> { pushNeg(); p = "be able to $p" }
            "tai" -> { pushNeg(); p = "want to $p" }
            "naru" -> { pushNeg(); p = if (p.startsWith("be ")) "become " + p.drop(3) else "come to $p" }
            "iru" -> { pushNeg(); p = "be " + onFirst(p, ::gerund) }
            "shimau" -> { pushNeg(); p += " (completely / regrettably)" }
            "miru" -> { pushNeg(); p = "try " + onFirst(p, ::gerund) }
            "sou" -> { pushNeg(); p = if (p.startsWith("be ")) "seem " + p.drop(3) else "seem about to $p" }
            "nai" -> neg = !neg
            "masen" -> { neg = !neg; polite = true }
            "masu", "desu" -> polite = true
            "ta", "deshita" -> pastT = true
            "te" -> mode = "te"
            "tara" -> mode = "tara"
            "ba" -> mode = "if"
            "you" -> mode = "lets"
            "imp" -> mode = "imp"
            "nagara" -> mode = "while"
            "naide" -> mode = "without"
            "kudasai" -> mode = "please"
            "kara" -> mode = "because"
            "tekara" -> mode = "after"
            "to" -> mode = "when"
        }
        if (p.startsWith("not ")) { p = p.drop(4); neg = !neg }
        fun finite(isPast: Boolean): String {
            val (v, rest) = split(p)
            if (v == "be") return (if (isPast) "was" else "is") + (if (neg) " not" else "") + rest
            if (neg) return (if (isPast) "did not " else "does not ") + p
            return if (isPast) past(v) + rest else p
        }
        val out = when (mode) {
            "te" -> (if (neg) "not " else "") + onFirst(p, ::gerund) + " and…"
            "tara" -> "if / when (it) " + finite(true)
            "if" -> "if (it) " + finite(false)
            "lets" -> "let's $p"
            "imp" -> "$p!"
            "while" -> "while " + onFirst(p, ::gerund)
            "without" -> "without " + onFirst(p, ::gerund)
            "please" -> "please " + (if (neg) "don't " else "") + p
            "because" -> "because (it) " + finite(pastT)
            "after" -> "after " + onFirst(p, ::gerund)
            "when" -> "when (it) " + finite(pastT)
            else -> finite(pastT)
        }
        return out + (if (polite) " (polite)" else "")
    }
}

// MARK: - 助詞: what each does, examples (written for this app), and where they sit in a sentence (the map)
// In the examples, [ ] marks a particle and { } a grammatical suffix, so they get their colours.

class JaParticle(val p: String, val group: String, val zh: String, val en: String, val ex: List<Pair<String, String>>)

object JaParticles {
    /** the groups of the map, in sentence order */
    val groups = listOf(
        "主題・主語" to "who / what the sentence is about",
        "時間・地點" to "when / where / from / to",
        "對象" to "the object, the person",
        "方法・一起" to "how, with what, with whom",
        "連接・修飾" to "joining nouns",
        "限定・強調" to "only, also, even",
        "句末語氣" to "at the end: question, feeling",
    )
    val all = listOf(
        JaParticle("は", "主題・主語", "主題：「說到…」。整句話在說它。唸 wa。", "topic marker: \"as for…\" (read wa)",
            listOf("私[は]学生{です}。" to "I am a student.", "今日[は]暑い{です}[ね]。" to "It's hot today, isn't it.")),
        JaParticle("が", "主題・主語", "主語：誰／什麼做了這件事，或新的訊息、喜歡／會的對象。", "subject marker; new information; the object of 好き・できる",
            listOf("猫[が]寝{て}{いる}。" to "A cat is sleeping.", "私[は]寿司[が]好き{です}。" to "I like sushi.")),
        JaParticle("も", "限定・強調", "「也、都」。代替は、が、を。", "\"also, too\" (takes the place of は・が・を)",
            listOf("私[も]行き{ます}。" to "I'm going too.", "肉[も]魚[も]食べ{ます}。" to "I eat both meat and fish.")),
        JaParticle("を", "對象", "受詞：動作的對象；也表示經過的地方。唸 o。", "direct object; the place passed through (read o)",
            listOf("水[を]飲み{ます}。" to "I drink water.", "公園[を]散歩する。" to "I take a walk through the park.")),
        JaParticle("に", "時間・地點", "時間點、存在的地方、去的目的地、給的對象。", "point in time, where something is, destination, to whom",
            listOf("七時[に]起き{ます}。" to "I get up at seven.", "友達[に]本[を]あげ{た}。" to "I gave my friend a book.")),
        JaParticle("で", "時間・地點", "動作發生的地方；也表示工具、方法、原因。", "where an action happens; by means of; because of",
            listOf("図書館[で]勉強する。" to "I study at the library.", "バス[で]行き{ます}。" to "I go by bus.")),
        JaParticle("へ", "時間・地點", "方向「往…」。唸 e。", "direction: \"towards\" (read e)",
            listOf("日本[へ]行き{たい}。" to "I want to go to Japan.")),
        JaParticle("から", "時間・地點", "起點「從…」；接在句子後面是「因為…」。", "\"from\"; after a clause: \"because\"",
            listOf("九時[から]働き{ます}。" to "I work from nine.", "雨{だ}[から]、行か{ない}。" to "It's raining, so I won't go.")),
        JaParticle("まで", "時間・地點", "終點「到…」。", "\"until, as far as\"",
            listOf("駅[まで]歩き{ます}。" to "I walk to the station.", "五時[まで]待っ{た}。" to "I waited until five.")),
        JaParticle("と", "方法・一起", "「和…（一起）」；完整列舉「A 和 B」；引用。", "\"with (someone)\"; \"A and B\" (all of them); quoting",
            listOf("母[と]話し{た}。" to "I talked with my mother.", "ペン[と]紙[が]要る。" to "I need a pen and paper.")),
        JaParticle("や", "連接・修飾", "不完整列舉「A 啦 B 啦（等等）」。", "\"A, B and so on\" (some of them)",
            listOf("りんご[や]バナナ[を]買っ{た}。" to "I bought apples, bananas and such.")),
        JaParticle("の", "連接・修飾", "「的」：連接兩個名詞。", "\"'s, of\": joins two nouns",
            listOf("私[の]本" to "my book", "日本語[の]先生" to "a Japanese teacher")),
        JaParticle("だけ", "限定・強調", "「只有、只」（中性）。", "\"only, just\" (neutral)",
            listOf("水[だけ]飲ん{だ}。" to "I only drank water.")),
        JaParticle("しか", "限定・強調", "「只…（不夠）」，後面一定是否定。", "\"nothing but\" (always with a negative verb)",
            listOf("百円[しか]ない。" to "I only have a hundred yen.")),
        JaParticle("か", "句末語氣", "疑問「…嗎？」；在名詞中間是「或」。", "question marker; between nouns: \"or\"",
            listOf("これ[は]何{です}[か]。" to "What is this?", "お茶[か]コーヒー" to "tea or coffee")),
        JaParticle("ね", "句末語氣", "「…吧、…呢」：希望對方同意。", "\"…isn't it?\": looking for agreement",
            listOf("いい天気{です}[ね]。" to "Nice weather, isn't it.")),
        JaParticle("よ", "句末語氣", "「…喔、…啦」：告訴對方他不知道的事。", "\"you know\": telling something new",
            listOf("この店[は]安い{です}[よ]。" to "This shop is cheap, you know.")),
    )
    /** the sentence the map draws: each particle in its place */
    const val mapSentence = "私[は]昨日友達[と]駅[から]学校[まで]バス[で]行っ{た}。"
    const val mapEnglish = "Yesterday I went from the station to school by bus with a friend."
    val order = listOf(
        "誰／什麼" to listOf("は", "が", "も"), "什麼時候" to listOf("に", "から", "まで"), "在哪裡" to listOf("で", "に"),
        "往哪裡" to listOf("へ", "に", "まで"), "和誰" to listOf("と"), "用什麼" to listOf("で"), "對什麼" to listOf("を", "に"), "句末" to listOf("か", "ね", "よ"),
    )
    fun role(p: String): String = when (p) {
        "は" -> "主題"; "が" -> "主語"; "と" -> "和誰"; "から" -> "從"; "まで" -> "到"; "で" -> "用什麼"; "を" -> "受詞"; "に" -> "時間／目的地"
        else -> ""
    }
}
