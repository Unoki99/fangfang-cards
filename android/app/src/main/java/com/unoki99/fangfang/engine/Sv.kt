package com.unoki99.fangfang.engine

// MARK: - 瑞典語 (the computer version only): a word's morphemes (詞素), their colours, what each prefix, suffix and
// ending means and does, compounds and forms the dictionary doesn't have. The same as the iPhone app's
// SvMorphology.swift. sv.json (Install/swedish.js, Folkets lexikon) has the same shape as zh.json ("lang": "sv"):
// `tw` is the word's morphemes ("be:p tal:r:tala a:e"), `eq` its forms, `jp` its Chinese meanings, `pos` its class.

/** one morpheme of a Swedish word: its letters, what it is, and for a root the word it comes from (tal → tala). A
 *  phrase (hitta på) has its words' morphemes with a space between them ("_:w"). */
data class SvMorpheme(val id: Int, val text: String, val kind: Kind, val lemma: String = "") {
    enum class Kind(val code: String) { ROOT("r"), PREFIX("p"), SUFFIX("s"), LINK("l"), ENDING("e"), SPACE("w") }

    /** back to sv.json's way of writing it */
    val code: String get() = if (kind == Kind.SPACE) "_:w" else text + ":" + kind.code + (if (lemma.isEmpty()) "" else ":$lemma")
    /** the word to look up for a root (its lemma, or its own letters) */
    val word: String get() = (lemma.ifEmpty { text }).lowercase()
    /** what it is, in Chinese */
    val kindName: String get() = when (kind) {
        Kind.ROOT -> "詞根"; Kind.PREFIX -> "前綴"; Kind.SUFFIX -> "後綴"; Kind.LINK -> "連接音"; Kind.ENDING -> "詞尾"; Kind.SPACE -> ""
    }

    companion object {
        private val byCode = Kind.values().associateBy { it.code }

        /** "text:kind[:lemma]" each (empty strings: none) */
        fun parse(syl: List<String>): List<SvMorpheme> {
            val out = ArrayList<SvMorpheme>()
            for (s in syl) {
                if (s.isEmpty()) continue
                val p = s.split(":")
                if (p.size < 2 || p[0].isEmpty()) continue
                val k = byCode[p[1]] ?: continue
                out.add(SvMorpheme(out.size, if (k == Kind.SPACE) " " else p[0], k, if (p.size > 2) p[2] else ""))
            }
            return out
        }

        /** numbered again from 0 (after putting pieces together) */
        fun renumbered(ms: List<SvMorpheme>): List<SvMorpheme> = ms.mapIndexed { i, m -> m.copy(id = i) }

        /** a form of a word (betalade of betala, samtyckliga of samtycklig): the word's morphemes for the part the form
         *  shares with it, then the rest as an ending; the letters as the form writes them (Hittade) */
        fun forForm(form: String, lemma: String, ms0: List<SvMorpheme>): List<SvMorpheme> {
            val orig = form.cps()
            val low = orig.map { it.lowercase() }
            val ms = ms0.ifEmpty { listOf(SvMorpheme(0, lemma, Kind.ROOT)) }
            fun fits(list: List<SvMorpheme>): Boolean {
                val t = list.joinToString("") { it.text }.lowercase().cps()
                return list.isNotEmpty() && t.size <= low.size && t.indices.all { t[it] == low[it] }
            }
            // the word without its ending (tal-a → tal + ade), else the whole word (samtycklig + a), else the part they share
            var use = ms.toMutableList()
            while (use.lastOrNull()?.kind == Kind.ENDING) use.removeAt(use.size - 1)
            if (!fits(use) || form.lowercase() == lemma.lowercase()) use = ms.toMutableList()
            if (!fits(use)) {
                val t = ms.joinToString("") { it.text }.lowercase().cps()
                var n = 0
                while (n < t.size && n < low.size && t[n] == low[n]) n++
                val cut = ArrayList<SvMorpheme>(); var at = 0
                for (m in ms) {
                    if (at >= n) break
                    val mc = m.text.cps()
                    val take = minOf(mc.size, n - at)
                    cut.add(m.copy(text = mc.take(take).joinToString("")))
                    at += take
                }
                use = cut
            }
            val out = ArrayList<SvMorpheme>(); var at = 0
            for (m in use) {
                val n = m.text.cps().size
                if (at + n > orig.size) break
                out.add(m.copy(text = orig.subList(at, at + n).joinToString("")))
                at += n
            }
            if (at < orig.size) {
                val rest = orig.subList(at, orig.size).joinToString("")
                // (ta → tag-, dra → drag-: the stem's -g / -d stays with the root)
                val l = out.lastOrNull()
                if (rest.lowercase() in setOf("g", "d") && l != null && l.kind == Kind.ROOT && l.text.lastOrNull()?.let { it in "aeiouyåäöAEIOUYÅÄÖ" } == true) {
                    out[out.size - 1] = l.copy(text = l.text + rest)
                } else out.add(SvMorpheme(0, rest, Kind.ENDING))
            }
            return renumbered(out)
        }
    }
}

/** the colours: two for roots (one after the other in a compound: sjuk|hus), prefixes, suffixes, linking letters,
 *  endings. An affix on an affix takes the colour of the one next to it, darker */
object SvColors {
    val names = listOf("詞根", "第二個詞根", "前綴", "後綴", "連接音", "詞尾")
    val standard = intArrayOf(0xFFFFE991.toInt(), 0xFFFFB36B.toInt(), 0xFF6FE0CF.toInt(), 0xFFFF94C8.toInt(), 0xFFBDBDBD.toInt(), 0xFFC7A6FF.toInt())
    /** the colours chosen (設定), else the standard ones */
    @Volatile var picked: IntArray = standard.copyOf()
    fun color(i: Int): Int = picked.getOrElse(i) { standard[i] }

    private fun base(k: SvMorpheme.Kind): Int = when (k) {
        SvMorpheme.Kind.ROOT -> 0; SvMorpheme.Kind.PREFIX -> 2; SvMorpheme.Kind.SUFFIX -> 3
        SvMorpheme.Kind.LINK, SvMorpheme.Kind.SPACE -> 4; SvMorpheme.Kind.ENDING -> 5
    }

    /** which colour a morpheme takes in its word, and how many steps darker */
    fun style(m: SvMorpheme, ms: List<SvMorpheme>): Pair<Int, Int> {
        val i = ms.indexOfFirst { it.id == m.id }
        if (i < 0) return base(m.kind) to 0
        return when (m.kind) {
            SvMorpheme.Kind.ROOT -> {
                var n = 0; var j = i - 1
                while (j >= 0 && ms[j].kind != SvMorpheme.Kind.SPACE) { if (ms[j].kind == SvMorpheme.Kind.ROOT) n++; j-- }
                (if (n % 2 == 0) 0 else 1) to 0
            }
            SvMorpheme.Kind.PREFIX -> {
                var d = 0; var j = i + 1
                while (j < ms.size && ms[j].kind == SvMorpheme.Kind.PREFIX) { d++; j++ }
                2 to d
            }
            SvMorpheme.Kind.SUFFIX, SvMorpheme.Kind.ENDING -> {
                var st = i
                while (st > 0 && (ms[st - 1].kind == SvMorpheme.Kind.SUFFIX || ms[st - 1].kind == SvMorpheme.Kind.ENDING)) st--
                base(ms[st].kind) to (i - st)
            }
            else -> 4 to 0
        }
    }

    /** a colour a few steps darker (ARGB) */
    fun shade(c: Int, depth: Int): Int {
        if (depth <= 0) return c
        val r = ((c shr 16) and 0xFF) / 255f; val g = ((c shr 8) and 0xFF) / 255f; val b = (c and 0xFF) / 255f
        val max = maxOf(r, g, b); val min = minOf(r, g, b); val d = max - min
        var h = when {
            d == 0f -> 0f
            max == r -> ((g - b) / d) % 6f
            max == g -> (b - r) / d + 2f
            else -> (r - g) / d + 4f
        } / 6f
        if (h < 0) h += 1f
        val s0 = if (max == 0f) 0f else d / max
        val f = Math.pow(0.74, depth.toDouble()).toFloat()
        val s = minOf(1f, s0 * (1 + 0.18f * depth)); val v = max * f
        // (back to RGB)
        val hh = h * 6f; val sector = hh.toInt() % 6; val fr = hh - hh.toInt()
        val p = v * (1 - s); val q = v * (1 - s * fr); val t = v * (1 - s * (1 - fr))
        val (rr, gg, bb) = when (sector) { 0 -> Triple(v, t, p); 1 -> Triple(q, v, p); 2 -> Triple(p, v, t); 3 -> Triple(p, q, v); 4 -> Triple(t, p, v); else -> Triple(v, p, q) }
        return (c and 0xFF000000.toInt()) or ((rr * 255).toInt().coerceIn(0, 255) shl 16) or ((gg * 255).toInt().coerceIn(0, 255) shl 8) or (bb * 255).toInt().coerceIn(0, 255)
    }

    fun colorOf(m: SvMorpheme, ms: List<SvMorpheme>): Int { val (i, d) = style(m, ms); return shade(color(i), d) }

    /** the morphemes as coloured text (one morpheme: in `base`) */
    fun styledOf(ms: List<SvMorpheme>, base: Int?, colours: Boolean): Styled {
        val b = StyledBuilder()
        val many = ms.count { it.kind != SvMorpheme.Kind.SPACE } > 1
        for (m in ms) b.add(m.text, if (colours && many && m.kind != SvMorpheme.Kind.SPACE) colorOf(m, ms) else base)
        return b.build()
    }

    /** the morphemes with a hyphen between them (be-tal-a), each in its colour */
    fun hyphened(ms: List<SvMorpheme>, base: Int?, colours: Boolean, dash: Int?): Styled {
        val b = StyledBuilder()
        for ((i, m) in ms.withIndex()) {
            if (m.kind == SvMorpheme.Kind.SPACE) { b.add(" ", base); continue }
            if (i > 0 && ms[i - 1].kind != SvMorpheme.Kind.SPACE) b.add("-", dash)
            b.add(m.text, if (colours && ms.size > 1) colorOf(m, ms) else base)
        }
        return b.build()
    }
}

/** what a prefix, suffix, linking letter or ending means and does (Chinese; what it does; English; an example) */
class SvAffix(val zh: String, val does: String, val en: String, val ex: String) {
    /** its English in short (in, into; -ness, -ity) */
    val enShort: String get() = en.substringBefore(":").substringBefore(" (").trim()
    /** its meaning in short, in the language the meanings are shown in (設定 → 瑞典語的意思: 只有英文 → English) */
    val gloss: String get() = if (SvGuess.show == 2) enShort else zh
}

object SvAffixes {
    val prefixes: Map<String, SvAffix> = mapOf(
        "o" to SvAffix("不、非", "加在形容詞或名詞前面，意思變成相反。", "un-, not: turns the meaning into its opposite", "lycklig 幸福 → olycklig 不幸"),
        "be" to SvAffix("（使動）", "把動詞變成及物動詞，或把名詞、形容詞變成動詞：對某物做某事。", "makes a verb take an object, or makes a verb of a noun or adjective", "tala 說 → betala 付錢；fri 自由 → befria 解放"),
        "för" to SvAffix("使…、過度、提前", "把形容詞或名詞變成動詞（使變得…），或表示過頭、在前。", "makes verbs (make something…), or means too much / before", "bättre 更好 → förbättra 改善"),
        "an" to SvAffix("向、對", "表示朝向、接觸或開始，常見於從德語借來的詞。", "towards, on (often in words from German)", "komma 來 → ankomma 到達"),
        "av" to SvAffix("離開、去掉", "表示分開、去除、結束。", "off, away, from", "bryta 折 → avbryta 打斷"),
        "in" to SvAffix("進、入", "表示向裡面。", "in, into", "gång 走 → ingång 入口"),
        "ut" to SvAffix("出、外", "表示向外面或做完。", "out", "gång 走 → utgång 出口"),
        "upp" to SvAffix("上、起", "表示向上、開始或完成。", "up", "gång 走 → uppgång 上升"),
        "till" to SvAffix("向、加", "表示到某處、加上或屬於。", "to, towards, added", "gång 走 → tillgång 取得、資源"),
        "över" to SvAffix("上方、超過", "表示在上面、越過或太多。", "over, above, too much", "gång 走 → övergång 過渡"),
        "under" to SvAffix("下方、不足", "表示在下面、少於。", "under, below", "gång 走 → undergång 滅亡"),
        "efter" to SvAffix("之後", "表示在後面、跟隨。", "after", "middag 午餐 → eftermiddag 下午"),
        "före" to SvAffix("之前", "表示在前面、先。", "before, fore-", "gå 走 → föregå 先於"),
        "fram" to SvAffix("向前", "表示向前、出來。", "forward, forth", "steg 步 → framsteg 進步"),
        "om" to SvAffix("重新、圍繞", "表示再一次、改變或環繞。", "re-, around, about", "göra 做 → omgöra 重做"),
        "mot" to SvAffix("相對、反", "表示對著、反對。", "against, counter-", "gift 毒 → motgift 解毒劑"),
        "med" to SvAffix("一起", "表示共同、跟隨。", "with, co-", "arbetare 工人 → medarbetare 同事"),
        "miss" to SvAffix("錯、失", "表示做錯或不好。", "mis-, wrongly", "förstå 了解 → missförstå 誤會"),
        "sam" to SvAffix("共同", "表示一起、合作。", "together, co-", "arbete 工作 → samarbete 合作"),
        "sär" to SvAffix("分開、特別", "表示分開或特殊。", "apart, special", "skilja 分 → särskilja 區分"),
        "van" to SvAffix("不好、錯", "表示不正確、不好的。", "mis-, bad", "tro 信仰 → vantro 不信"),
        "åter" to SvAffix("再、回", "表示再一次或回來。", "re-, back", "seende 見 → återseende 重逢"),
        "ur" to SvAffix("原、最初；出", "表示最早的、原始的，或向外。", "original, primeval; out of", "skog 森林 → urskog 原始森林"),
        "er" to SvAffix("（得到）", "表示得到、達到（從德語借來）。", "gain, achieve (from German)", "känna 知道 → erkänna 承認"),
        "ge" to SvAffix("（集合、完成）", "從德語借來的前綴，常沒有獨立意思。", "a prefix from German, often without its own meaning", "gemensam 共同的、gestalt 形狀"),
        "bi" to SvAffix("旁、副", "表示次要的、在旁邊的。", "by-, secondary", "sak 事 → bisak 次要的事"),
        "all" to SvAffix("全、非常", "表示全部或非常。", "all-, very", "makt 力量 → allmakt 全能"),
        "icke" to SvAffix("非", "表示不是、沒有。", "non-", "rökare 吸菸者 → icke-rökare 不吸菸的人"),
        "anti" to SvAffix("反", "表示反對、對抗。", "anti-", "kropp 身體 → antikropp 抗體"),
        "super" to SvAffix("超", "表示超過、非常。", "super-", "makt 力量 → supermakt 超級大國"),
        "mini" to SvAffix("小、迷你", "表示很小。", "mini-", "buss 巴士 → minibuss 小巴"),
        "multi" to SvAffix("多", "表示很多。", "multi-", "kulturell 文化的 → multikulturell 多元文化的"),
        "inter" to SvAffix("之間、國際", "表示在…之間。", "inter-, between", "nationell 國家的 → internationell 國際的"),
        "ex" to SvAffix("前、出", "表示以前的，或向外。", "ex-, former; out", "man 丈夫 → exman 前夫"),
        "re" to SvAffix("再、回", "表示再一次或回來。", "re-, again", "agera 行動 → reagera 反應"),
        "pre" to SvAffix("前", "表示之前。", "pre-, before", "historisk 歷史的 → prehistorisk 史前的"),
        "post" to SvAffix("後", "表示之後。", "post-, after", "modern 現代的 → postmodern 後現代的"),
        "sub" to SvAffix("下、次", "表示在下面、次一級。", "sub-, under", "kultur 文化 → subkultur 次文化"),
        "trans" to SvAffix("跨、越過", "表示穿過、轉到另一邊。", "trans-, across", "atlantisk 大西洋的 → transatlantisk 跨大西洋的"),
    )

    val suffixes: Map<String, SvAffix> = mapOf(
        "het" to SvAffix("…性、…度", "把形容詞變成名詞（en-詞）：那種性質、狀態。", "-ness, -ity: makes a noun of an adjective", "fri 自由的 → frihet 自由"),
        "ning" to SvAffix("…的行為、結果", "把動詞變成名詞（en-詞）：那個動作或它的結果。", "-ing, -tion: makes a noun of a verb", "öppna 打開 → öppning 開口"),
        "ing" to SvAffix("…的行為、結果", "把動詞變成名詞（en-詞）：那個動作或它的結果。", "-ing: makes a noun of a verb", "parkera 停車 → parkering 停車場"),
        "are" to SvAffix("…的人、…器", "把動詞變成名詞（en-詞）：做這件事的人或工具。", "-er: the one who does it, or a tool", "läsa 讀 → läsare 讀者"),
        "ande" to SvAffix("…的人；…中的", "動詞的現在分詞：正在做的（形容詞），或做這件事的人、這個動作（名詞）。", "-ing (present participle), or a noun of a verb", "studera 讀書 → studerande 學生"),
        "ende" to SvAffix("…的人；…中的", "動詞的現在分詞（長母音結尾的動詞）：正在做的，或那個動作。", "-ing (present participle of verbs in a long vowel)", "bo 住 → boende 住所、居民"),
        "lig" to SvAffix("…的、像…的", "把名詞或動詞變成形容詞。", "-ly, -ful: makes an adjective", "vän 朋友 → vänlig 友善的"),
        "ig" to SvAffix("有…的、多…的", "把名詞變成形容詞：有那樣東西的。", "-y: makes an adjective of a noun", "sol 太陽 → solig 晴朗的"),
        "isk" to SvAffix("…的、…式的", "把名詞變成形容詞：屬於、像那樣的。", "-ic, -ish: makes an adjective", "Kina 中國 → kinesisk 中國的"),
        "bar" to SvAffix("可以…的", "把動詞變成形容詞：可以被那樣做的。", "-able: can be done", "äta 吃 → ätbar 可以吃的"),
        "sam" to SvAffix("有…傾向的", "把動詞或名詞變成形容詞：常常那樣、有那種性質的。", "-some, -ful: tending to", "arbeta 工作 → arbetsam 勤勞的"),
        "lös" to SvAffix("沒有…的、無…", "把名詞變成形容詞：沒有那樣東西的。", "-less: without", "arbete 工作 → arbetslös 失業的"),
        "fri" to SvAffix("無…的、免…", "把名詞變成形容詞：沒有、不用…的。", "-free: without", "alkohol 酒精 → alkoholfri 無酒精的"),
        "full" to SvAffix("充滿…的", "把名詞變成形容詞：有很多那樣東西的。", "-ful: full of", "hopp 希望 → hoppfull 充滿希望的"),
        "aktig" to SvAffix("像…的、有點…", "把名詞或形容詞變成形容詞：像那樣的、帶一點那樣的。", "-ish, -like", "barn 小孩 → barnaktig 幼稚的"),
        "mässig" to SvAffix("依…的、…方面的", "把名詞變成形容詞：按照、關於那樣東西的。", "according to, -wise", "regel 規則 → regelmässig 有規律的"),
        "skap" to SvAffix("…關係、…身分、…感", "把名詞或形容詞變成名詞（ett-詞）：一種關係、狀態或群體。", "-ship: a relation, state or group", "vän 朋友 → vänskap 友誼"),
        "dom" to SvAffix("…狀態、…時期", "把名詞或形容詞變成名詞（en-詞）：狀態、時期或領域。", "-dom, -hood", "ung 年輕 → ungdom 青春、青年"),
        "else" to SvAffix("…的行為、結果", "把動詞變成名詞（en- 或 ett-詞）：動作或它的結果。", "makes a noun of a verb (the act or its result)", "röra 動 → rörelse 運動"),
        "nad" to SvAffix("…的行為、結果", "把動詞變成名詞（en-詞）。", "makes a noun of a verb", "bygga 建 → byggnad 建築"),
        "eri" to SvAffix("…店、…業、…行為", "把名詞或動詞變成名詞（ett-詞）：地方、行業或一種行為。", "-ery: a place, trade or activity", "baka 烘焙 → bageri 麵包店"),
        "era" to SvAffix("（動詞）", "把外來的詞變成動詞（重音在 e 上）。", "makes a verb (often of words from other languages)", "studie 研究 → studera 讀書"),
        "ering" to SvAffix("…的行為", "-era 動詞的名詞：那個動作。", "the noun of an -era verb", "reparera 修理 → reparering 修理"),
        "tion" to SvAffix("…的行為、結果", "外來的名詞後綴（en-詞），常和 -era 動詞成對。", "-tion (from Latin)", "informera 告知 → information 資訊"),
        "sion" to SvAffix("…的行為、結果", "外來的名詞後綴（en-詞）。", "-sion (from Latin)", "diskutera 討論 → diskussion 討論"),
        "itet" to SvAffix("…性", "外來的名詞後綴（en-詞）：性質。", "-ity (from Latin)", "aktiv 活躍的 → aktivitet 活動"),
        "ism" to SvAffix("…主義", "名詞後綴（en-詞）：思想、主義。", "-ism", "social 社會的 → socialism 社會主義"),
        "ist" to SvAffix("…者、…家", "名詞後綴（en-詞）：做這件事或信這個主義的人。", "-ist: a person", "gitarr 吉他 → gitarrist 吉他手"),
        "inna" to SvAffix("女…", "把指人的名詞變成女性的。", "-ess: a woman", "lärare 老師 → lärarinna 女老師"),
        "ska" to SvAffix("女…；…語", "表示女性，或語言、學問。", "a woman; a language", "sångare 歌手 → sångerska 女歌手"),
        "ör" to SvAffix("…者", "外來的名詞後綴（en-詞）：做這件事的人。", "-eur, -or: a person", "regissera 導演 → regissör 導演"),
        "vis" to SvAffix("以…方式、按…", "把名詞或形容詞變成副詞：用那種方式、一個一個地。", "-wise, -ly: makes an adverb", "steg 步 → stegvis 逐步地"),
    )

    val links: Map<String, SvAffix> = mapOf(
        "s" to SvAffix("（連接音）", "複合詞的兩個詞中間加的 -s-，本身沒有意思，只是把兩個詞接起來（前面的詞常已是複合詞，或以 -ing、-het、-tion 等結尾）。", "a linking -s- between the parts of a compound: no meaning of its own", "arbete + plats → arbetsplats 工作地點"),
        "e" to SvAffix("（連接音）", "複合詞的兩個詞中間加的 -e-，本身沒有意思。", "a linking -e-: no meaning of its own", "（較少見，多在舊詞裡）"),
        "a" to SvAffix("（連接音）", "複合詞的兩個詞中間加的 -a-，本身沒有意思（多是古老的用法）。", "a linking -a-: no meaning of its own", "gäst + bud → gästabud 宴會"),
        "u" to SvAffix("（連接音）", "複合詞的兩個詞中間加的 -u-，本身沒有意思（前面的詞原來以 -a 結尾）。", "a linking -u-: no meaning of its own", "gata + korsning → gatukorsning 十字路口"),
        "o" to SvAffix("（連接音）", "複合詞的兩個詞中間加的 -o-，本身沒有意思（前面的詞原來以 -a 結尾）。", "a linking -o-: no meaning of its own", "kvinna + rörelse → kvinnorörelse 婦女運動"),
        "es" to SvAffix("（連接音）", "複合詞的兩個詞中間加的 -es-，本身沒有意思。", "a linking -es-: no meaning of its own", "（很少見）"),
    )

    val endings: Map<String, SvAffix> = mapOf(
        "are" to SvAffix("更…（比較級）", "加在形容詞或副詞後面，變成比較級：比較兩個東西，「更…」。", "-er: the comparative of an adjective or adverb (more …)", "sen 晚 → senare 更晚、後來；snar 不久 → snarare 寧可、倒不如"),
        "ast" to SvAffix("最…（最高級）", "加在形容詞或副詞後面，變成最高級：「最…」。", "-est: the superlative (most …)", "sen 晚 → senast 最晚、最近；snabb 快 → snabbast 最快"),
        "aste" to SvAffix("最…（最高級，限定形）", "最高級的限定形，用在 den／det／de 或所有格後面。", "-est, the definite form (den snabbaste)", "snabb 快 → den snabbaste 最快的"),
        "a" to SvAffix("（不定式）", "動詞的原形（不定式）詞尾。變化時換成別的詞尾：-ar（現在）、-ade（過去）、-at（完成）。", "the infinitive ending of a verb (-ar now, -ade past, -at perfect)", "tal-a → talar 說、talade 說了"),
    )

    fun of(m: SvMorpheme): SvAffix? {
        val t = m.text.lowercase()
        return when (m.kind) {
            SvMorpheme.Kind.PREFIX -> prefixes[t]; SvMorpheme.Kind.SUFFIX -> suffixes[t]
            SvMorpheme.Kind.LINK -> links[t]; SvMorpheme.Kind.ENDING -> endings[t]
            else -> null
        }
    }
}

// MARK: words the dictionary doesn't have

/** one part of a compound: a word of the dictionary (entry), or a linking letter between two */
data class SvPart(val text: String, val entry: Int?, val link: Boolean)

/** a word class, for the rules: noun, verb, adjective, adverb; ANY: the dictionary doesn't say */
enum class SvCls(val label: String) {
    N("名詞"), V("動詞"), A("形容詞"), D("副詞"), ANY("");
    companion object {
        fun of(pos: List<String>): List<SvCls> {
            val out = ArrayList<SvCls>()
            for (p in pos) when (p) {
                "名詞", "專有名詞" -> out.add(N); "動詞" -> out.add(V); "形容詞", "序數詞" -> out.add(A); "副詞" -> out.add(D)
            }
            return out.ifEmpty { listOf(ANY) }
        }
    }
}

/** a suffix or ending the rules know: what it's added to, what the word is then, and what it does */
class SvRule(val text: String, val kind: SvMorpheme.Kind, val from: List<SvCls>, val to: SvCls, val zh: String, val en: String)

object SvRules {
    private val E = SvMorpheme.Kind.ENDING
    private val S = SvMorpheme.Kind.SUFFIX
    private fun r(t: String, k: SvMorpheme.Kind, f: List<SvCls>, to: SvCls, zh: String, en: String) = SvRule(t, k, f, to, zh, en)
    private val n = listOf(SvCls.N); private val v = listOf(SvCls.V); private val a = listOf(SvCls.A)
    val all: List<SvRule> = listOf(
        // nouns' endings
        r("arna", E, n, SvCls.N, "名詞複數的限定形（the …s）", "plural, definite (the …s)"),
        r("erna", E, n, SvCls.N, "名詞複數的限定形（the …s）", "plural, definite (the …s)"),
        r("orna", E, n, SvCls.N, "名詞複數的限定形（the …s）", "plural, definite (the …s)"),
        r("ar", E, n, SvCls.N, "名詞複數", "plural"),
        r("er", E, n, SvCls.N, "名詞複數", "plural"),
        r("or", E, n, SvCls.N, "名詞複數", "plural"),
        r("na", E, n, SvCls.N, "名詞複數的限定形", "plural, definite"),
        r("en", E, n, SvCls.N, "名詞單數的限定形（en-詞：the）", "singular, definite (en-word: the)"),
        r("et", E, n, SvCls.N, "名詞單數的限定形（ett-詞：the）", "singular, definite (ett-word: the)"),
        r("n", E, n, SvCls.N, "名詞的限定形（the）", "definite (the)"),
        r("t", E, n, SvCls.N, "名詞單數的限定形（ett-詞：the）", "singular, definite (ett-word: the)"),
        r("s", E, n, SvCls.N, "所有格（…的）", "genitive ('s)"),
        // adjectives' endings
        r("t", E, a, SvCls.A, "形容詞的中性（ett-詞）或副詞", "neuter (ett-word), or an adverb"),
        r("a", E, a, SvCls.A, "形容詞的複數或限定形", "plural or definite"),
        r("e", E, a, SvCls.A, "形容詞的限定形（男性）", "definite (masculine)"),
        r("are", E, listOf(SvCls.A, SvCls.D), SvCls.A, "比較級（更…）", "comparative (more …)"),
        r("ast", E, listOf(SvCls.A, SvCls.D), SvCls.A, "最高級（最…）", "superlative (most …)"),
        r("aste", E, a, SvCls.A, "最高級的限定形（最…的）", "superlative, definite"),
        // verbs' endings
        r("ar", E, v, SvCls.V, "動詞現在式", "present tense"),
        r("er", E, v, SvCls.V, "動詞現在式", "present tense"),
        r("r", E, v, SvCls.V, "動詞現在式", "present tense"),
        r("ade", E, v, SvCls.V, "動詞過去式", "past tense"),
        r("de", E, v, SvCls.V, "動詞過去式", "past tense"),
        r("te", E, v, SvCls.V, "動詞過去式", "past tense"),
        r("at", E, v, SvCls.V, "動詞完成式（har …at）", "supine (har …at)"),
        r("it", E, v, SvCls.V, "動詞完成式（har …it）", "supine (har …it)"),
        r("s", E, v, SvCls.V, "被動或相互（-s 動詞）", "passive or reciprocal (-s)"),
        r("ad", E, v, SvCls.A, "過去分詞（被…的）", "past participle"),
        r("en", E, v, SvCls.A, "過去分詞（被…的）", "past participle"),
        // suffixes that make another kind of word
        r("ande", S, v, SvCls.N, "把動詞變成名詞：那個動作（…的行為）", "makes a noun of a verb: the act"),
        r("ende", S, v, SvCls.N, "把動詞變成名詞：那個動作（…的行為）", "makes a noun of a verb: the act"),
        r("ning", S, v, SvCls.N, "把動詞變成名詞：動作或它的結果", "makes a noun of a verb: the act or its result"),
        r("ing", S, v, SvCls.N, "把動詞變成名詞：動作或它的結果", "makes a noun of a verb: the act or its result"),
        r("are", S, v, SvCls.N, "把動詞變成名詞：做這件事的人或工具", "makes a noun of a verb: one who does it"),
        r("else", S, v, SvCls.N, "把動詞變成名詞：動作或它的結果", "makes a noun of a verb"),
        r("nad", S, v, SvCls.N, "把動詞變成名詞：動作或它的結果", "makes a noun of a verb"),
        r("eri", S, listOf(SvCls.V, SvCls.N), SvCls.N, "名詞：地方、行業或一種行為", "a place, trade or activity"),
        r("bar", S, v, SvCls.A, "把動詞變成形容詞：可以被…的", "makes an adjective of a verb: can be done"),
        r("sam", S, listOf(SvCls.V, SvCls.N), SvCls.A, "變成形容詞：有…傾向的", "makes an adjective: tending to"),
        r("het", S, a, SvCls.N, "把形容詞變成名詞：…性、…度", "makes a noun of an adjective: -ness"),
        r("lig", S, listOf(SvCls.N, SvCls.V), SvCls.A, "變成形容詞：…的、像…的", "makes an adjective: -ly, -ful"),
        r("ig", S, n, SvCls.A, "把名詞變成形容詞：有…的", "makes an adjective of a noun: -y"),
        r("isk", S, n, SvCls.A, "把名詞變成形容詞：…的、…式的", "makes an adjective of a noun: -ic"),
        r("lös", S, n, SvCls.A, "把名詞變成形容詞：沒有…的", "makes an adjective of a noun: -less"),
        r("fri", S, n, SvCls.A, "把名詞變成形容詞：無…的", "makes an adjective of a noun: -free"),
        r("full", S, n, SvCls.A, "把名詞變成形容詞：充滿…的", "makes an adjective of a noun: -ful"),
        r("aktig", S, listOf(SvCls.N, SvCls.A), SvCls.A, "變成形容詞：像…的、有點…", "makes an adjective: -ish"),
        r("mässig", S, n, SvCls.A, "把名詞變成形容詞：依…的、…方面的", "makes an adjective of a noun: -wise"),
        r("skap", S, listOf(SvCls.N, SvCls.A), SvCls.N, "變成名詞：…關係、…身分", "makes a noun: -ship"),
        r("dom", S, listOf(SvCls.A, SvCls.N), SvCls.N, "變成名詞：…狀態、…時期", "makes a noun: -dom, -hood"),
        r("itet", S, a, SvCls.N, "把形容詞變成名詞：…性", "makes a noun of an adjective: -ity"),
        r("ism", S, listOf(SvCls.A, SvCls.N), SvCls.N, "變成名詞：…主義", "makes a noun: -ism"),
        r("ist", S, n, SvCls.N, "名詞：…者、…家", "a person: -ist"),
        r("inna", S, n, SvCls.N, "名詞：女…", "a woman: -ess"),
        r("vis", S, listOf(SvCls.N, SvCls.A), SvCls.D, "變成副詞：以…方式、按…", "makes an adverb: -wise"),
        r("era", S, n, SvCls.V, "把名詞變成動詞", "makes a verb of a noun"),
    )
}

/** one step of working a word out: the suffix or ending added, what it does, and what the word is then */
data class SvStep(val text: String, val kind: SvMorpheme.Kind, val zh: String, val en: String, val cls: SvCls)

/** a word worked out: its base (one dictionary word, or a compound of several), what was added to it, and its
 *  morphemes; cost: how much is guessed (the fewer the better); adj: letters added to or taken off a base */
data class SvEstimate(val ms: List<SvMorpheme>, val cls: SvCls, val parts: List<SvPart>, val steps: List<SvStep>, val cost: Int, val adj: Int = 0)

/** 瑞典語: 華語 meanings guessed from the English ones (marked ≈ in sv.json): shown or not (設定 → 瑞典語) */
object SvGuess {
    @Volatile var on = true
    /** 瑞典語的意思: 0 中文和英文, 1 只有中文 (English only when there's no Chinese), 2 只有英文 */
    @Volatile var show = 0
}

/** 瑞典語: the Chinese meanings (the guessed ones only when 設定 says), searched (shown or not) */
val ZhEntry.svZhAll: List<String> get() { val g = SvGuess.on; return jp.mapNotNull { if (it.startsWith("≈")) (if (g) it.drop(1) else null) else it } }
/** 瑞典語: the Chinese meanings shown (none: 設定 says English only) */
val ZhEntry.svZh: List<String> get() = if (SvGuess.show == 2) emptyList() else svZhAll
/** (they're guessed from the English) */
val ZhEntry.svZhGuessed: Boolean get() = SvGuess.show != 2 && SvGuess.on && (jp.firstOrNull()?.startsWith("≈") ?: false)
/** 瑞典語, 只有中文: the English meanings not shown (when there are Chinese ones to show instead) */
val ZhEntry.svHideEnglish: Boolean get() = SvGuess.show == 1 && svZh.isNotEmpty()

/** 瑞典語: the words the last search found through the English of a 華語 word (their entries say so) */
class SvVia(val zh: String, val en: String) {
    companion object { @Volatile var found: Map<String, SvVia> = emptyMap() }
}

/** a word as written in a sentence: the punctuation before it, the word, the punctuation after it */
fun svSplitWord(s: String): Triple<String, String, String> {
    val lead = s.takeWhile { !it.isLetterOrDigit() }
    val rest = s.drop(lead.length)
    val tail = rest.reversed().takeWhile { !it.isLetterOrDigit() }.reversed()
    return Triple(lead, rest.dropLast(tail.length), tail)
}

// MARK: the dictionary's side

/** 瑞典語, when the dictionary is read: -are and -ast(e) on an adjective or adverb are its comparative and superlative
 *  (sen|are), not -are of a person (läs|are); splits that make two words better; o- that isn't "not"; -ning that's
 *  -ing on a verb in -n; verbs made of a short verb (omhänder|ta); a phrase without morphemes of its own gets its
 *  words'. (the entries' morphemes, `tw`, are changed) */
internal fun svFix(es: List<ZhEntry>, byPlain: Map<String, List<Int>>) {
    fun idx(w: String) = byPlain[w.lowercase()] ?: emptyList()
    val orig = es.map { it.tw }
    fun describes(w: String) = idx(w).any { i -> es[i].pos.any { it == "形容詞" || it == "副詞" } }
    fun noun(e: ZhEntry) = e.pos.contains("名詞") || e.pos.contains("動詞")
    for (e in es) {
        if (e.h.contains(" ")) continue
        val ms = SvMorpheme.parse(e.tw).toMutableList()
        val low = e.h.lowercase()
        val last = ms.lastOrNull()
        if (last != null && last.kind == SvMorpheme.Kind.SUFFIX && last.text.lowercase() == "are" && ms.size >= 2 && !noun(e)) {
            val stem = ms.dropLast(1).joinToString("") { it.text }
            if (e.pos.any { it == "形容詞" || it == "副詞" } || describes(stem) || describes(ms[ms.size - 2].word)) {
                ms[ms.size - 1] = last.copy(kind = SvMorpheme.Kind.ENDING)
                e.tw = ms.map { it.code }
            }
        } else if (ms.isEmpty() && !noun(e)) {
            for (end in listOf("aste", "ast", "are")) {
                if (!(low.endsWith(end) && low.length > end.length + 1)) continue
                val stem = e.h.dropLast(end.length)
                if (describes(stem)) { e.tw = listOf(stem + ":r:" + stem.lowercase(), e.h.takeLast(end.length) + ":e"); break }
            }
        }
    }
    fun headword(w: String) = idx(w).any { es[it].h.lowercase() == w.lowercase() && !es[it].h.contains(" ") }
    // splits that make two words better: det|s|amma → det|samma, allt|ing → all|ting
    for (e in es) {
        val ms = SvMorpheme.parse(e.tw).toMutableList()
        if (ms.size < 2) continue
        var changed = false
        var j = 0
        while (j + 1 < ms.size) {
            if (ms[j].kind == SvMorpheme.Kind.LINK && ms[j].text.lowercase() == "s" && ms[j + 1].kind == SvMorpheme.Kind.ROOT && j > 0 &&
                headword("s" + ms[j + 1].text) && ms[j + 1].text.length >= 3) {
                val t = ms[j].text + ms[j + 1].text
                ms[j + 1] = ms[j + 1].copy(text = t, lemma = t.lowercase())
                ms.removeAt(j)
                changed = true
                continue
            }
            if (ms[j].kind == SvMorpheme.Kind.ROOT && ms[j + 1].kind == SvMorpheme.Kind.SUFFIX && ms[j].text.length >= 4 && j + 2 == ms.size) {
                val x = ms[j].text; val sfx = ms[j + 1].text
                val a = x.dropLast(1); val w2 = x.takeLast(1) + sfx
                if (a.length >= 3 && w2.length >= 4 && headword(a) && headword(w2)) {
                    ms[j] = ms[j].copy(text = a, lemma = a.lowercase())
                    ms[j + 1] = SvMorpheme(0, w2, SvMorpheme.Kind.ROOT, w2.lowercase())
                    changed = true
                }
            }
            j++
        }
        if (changed) e.tw = SvMorpheme.renumbered(ms).map { it.code }
    }
    // o- that isn't "not": only where the dictionary has the o-word both ways (ovan "above" and o|van)
    val negative = Regex("\\b(un|in|im|ir|il|non|dis|mis)\\w|\\bnot\\b|\\bwithout\\b|\\bno\\b|\\bbad|不|非|無|沒|未|失", RegexOption.IGNORE_CASE)
    fun negated(e: ZhEntry) = negative.containsMatchIn((listOf(e.en ?: "") + e.jp).joinToString(" "))
    fun bothWays(w: String): Boolean {
        val l = idx(w).map { es[it] }.filter { it.h.lowercase() == w.lowercase() }
        return l.any { !negated(it) } && l.any { negated(it) }
    }
    for (e in es) {
        val ms = SvMorpheme.parse(e.tw).toMutableList()
        if (ms.size < 2 || ms[0].kind != SvMorpheme.Kind.PREFIX || ms[0].text.lowercase() != "o" || ms[1].kind != SvMorpheme.Kind.ROOT) continue
        if (!bothWays("o" + ms[1].text) || negated(e)) continue
        val t = ms[0].text + ms[1].text
        ms[1] = ms[1].copy(text = t, lemma = t.lowercase())
        ms.removeAt(0)
        e.tw = SvMorpheme.renumbered(ms).map { it.code }
    }
    // -ning that's -ing on a verb ending in -n (var|ning → varn|ing: varna, not vara)
    fun verb(w: String) = idx(w).any { es[it].pos.contains("動詞") && es[it].h.lowercase() == w.lowercase() }
    for (e in es) {
        val ms = SvMorpheme.parse(e.tw).toMutableList()
        if (ms.size < 2) continue
        var changed = false
        for (j in 1 until ms.size) {
            if (ms[j].kind == SvMorpheme.Kind.SUFFIX && ms[j].text.lowercase() == "ning" && ms[j - 1].kind == SvMorpheme.Kind.ROOT) {
                val stem = ms[j - 1].text + "n"
                if (verb(stem + "a")) {
                    ms[j - 1] = ms[j - 1].copy(text = stem, lemma = (stem + "a").lowercase())
                    ms[j] = ms[j].copy(text = ms[j].text.drop(1))
                    changed = true
                }
            }
        }
        if (changed) e.tw = ms.map { it.code }
    }
    // verbs made of a short verb (omhänder|ta, an|ta, upp|dra): its forms say so (omhändertog)
    val short = listOf("ta" to "tog", "dra" to "drog", "ge" to "gav", "be" to "bad", "gå" to "gick", "se" to "såg",
        "få" to "fick", "stå" to "stod", "slå" to "slog", "dö" to "dog", "le" to "log")
    val prefixesLong = SvAffixes.prefixes.keys.sortedByDescending { it.length }
    for ((i, e) in es.withIndex()) {
        if (!e.pos.contains("動詞") || e.h.contains(" ")) continue
        val low = e.h.lowercase()
        val ms = SvMorpheme.parse(e.tw)
        if (!(ms.isEmpty() || ms.last().kind == SvMorpheme.Kind.ENDING)) continue
        for ((v, past) in short) {
            if (!(low.endsWith(v) && low.length > v.length + 1)) continue
            val front = e.h.dropLast(v.length)
            if (!e.eq.any { it.lowercase().replace("|", "") == front.lowercase() + past }) continue
            var pm = svWordMorphemes(front, es, idx(front), orig)
            if (pm.isEmpty()) {
                val fl = front.lowercase()
                val p = prefixesLong.firstOrNull { fl.startsWith(it) && fl.length - it.length >= 3 && idx(fl.drop(it.length)).isNotEmpty() }
                pm = if (p != null) listOf(SvMorpheme(0, front.take(p.length), SvMorpheme.Kind.PREFIX), SvMorpheme(0, front.drop(p.length), SvMorpheme.Kind.ROOT))
                else listOf(SvMorpheme(0, front, SvMorpheme.Kind.ROOT))
            }
            es[i].tw = (pm + SvMorpheme(0, e.h.takeLast(v.length), SvMorpheme.Kind.ROOT, v)).map { it.code }
            break
        }
    }
    for (e in es) if (e.h.contains(" ") && SvMorpheme.parse(e.tw).isEmpty()) svPhrase(e.h, es, byPlain)?.let { e.tw = it }
}

/** 瑞典語: a phrase without morphemes of its own (hitta på, skiljer sig): each word's, a space between them */
internal fun svPhrase(h: String, es: List<ZhEntry>, byPlain: Map<String, List<Int>>): List<String>? {
    val words = h.split(" ").filter { it.isNotEmpty() }
    if (words.size < 2) return null
    val out = ArrayList<SvMorpheme>()
    for ((i, w) in words.withIndex()) {
        if (i > 0) out.add(SvMorpheme(0, " ", SvMorpheme.Kind.SPACE))
        val ms = svWordMorphemes(w, es, byPlain[w.lowercase()] ?: emptyList())
        out.addAll(ms.ifEmpty { listOf(SvMorpheme(0, w, SvMorpheme.Kind.ROOT)) })
    }
    return out.map { it.code }
}

/** 瑞典語: a word as written (Hittade, bilarna, på): the morphemes of the entry it's the word or a form of (the form's
 *  ending added), in its own letters; [] when the dictionary doesn't have it. (tws: the morphemes to use, when they're
 *  being changed) */
internal fun svWordMorphemes(w: String, es: List<ZhEntry>, idx: List<Int>, tws: List<List<String>>? = null): List<SvMorpheme> {
    if (w.isEmpty() || idx.isEmpty()) return emptyList()
    val low = w.lowercase()
    val i = idx.firstOrNull { es[it].h.lowercase() == low && !es[it].h.contains(" ") } ?: idx.firstOrNull { !es[it].h.contains(" ") } ?: return emptyList()
    val e = es[i]
    val ms = SvMorpheme.parse(tws?.getOrNull(i) ?: e.tw)
    if (e.h.lowercase() == low) {
        if (ms.isEmpty()) return listOf(SvMorpheme(0, w, SvMorpheme.Kind.ROOT))
        if (ms.joinToString("") { it.text }.lowercase() == low) return SvMorpheme.forForm(w, e.h, ms)
        return listOf(SvMorpheme(0, w, SvMorpheme.Kind.ROOT))
    }
    return SvMorpheme.forForm(w, e.h, ms)
}

// MARK: ZhDict (瑞典語)

/** 瑞典語: the entries of a word (or one of its forms) */
fun ZhDict.svEntries(word: String): List<ZhEntry> = svIndices(word).map { entries[it] }

/** 瑞典語: the other words with the same morpheme (the same root, or the same prefix or suffix), common ones first */
fun ZhDict.svWords(m: SvMorpheme, except: String, limit: Int = 60): List<ZhEntry> {
    val out = ArrayList<ZhEntry>()
    val t = m.text.lowercase(); val w = m.word
    for (e in entries) {
        if (e.k == except) continue
        for (o in SvMorpheme.parse(e.tw)) {
            if (o.kind != m.kind) continue
            val same = if (m.kind == SvMorpheme.Kind.ROOT) (o.word == w || o.text.lowercase() == t) else o.text.lowercase() == t
            if (same) { out.add(e); break }
        }
        if (out.size >= limit) break
    }
    return out
}

/** 瑞典語: a word the dictionary has without its parts (jobbigt, Arvsfonden), its parts worked out by the rules
 *  ("text:kind" each; [] when there's nothing to work out); kept */
fun ZhDict.svWordSyl(w: String): List<String> {
    if (!isSv || w.length < 5 || w.contains(" ")) return emptyList()
    svSylCache[w]?.let { return it }
    val est = svEstimate(w, skipSelf = true)
    val out = if (est != null && est.ms.size > 1) est.ms.map { it.code } else emptyList()
    if (svSylCache.size > 6000) svSylCache.clear()
    svSylCache[w] = out
    return out
}

/** 瑞典語: a word as written in a sentence, in its morphemes (Hittade → Hitt|ade; a compound the dictionary doesn't
 *  have: its parts', varning|s|område|t); [] when it can't be worked out */
fun ZhDict.svMorphemes(w: String): List<SvMorpheme> {
    val r = svWordMorphemes(w, entries, svIndices(w))
    if (r.isNotEmpty()) return r
    svCache[w]?.let { return it }
    val est = svEstimate(w)
    val out = if (est != null) est.ms else svInflected(w)?.let { i -> SvMorpheme.forForm(w, entries[i].h, SvMorpheme.parse(entries[i].tw)) } ?: emptyList()
    if (svCache.size > 4000) svCache.clear()
    svCache[w] = out
    return out
}

/** 瑞典語: a sentence with each word in its morphemes' colours (hyphens: split, sam-tyck-lig-a); punctuation and
 *  words the dictionary doesn't have in `base` */
fun ZhDict.svSentence(text: String, hyphens: Boolean, base: Int?, colours: Boolean = EngineSettings.toneSystem != 0, dash: Int? = 0xB38E8E93.toInt()): Styled {
    val b = StyledBuilder()
    for ((li, line) in text.split("\n").withIndex()) {
        if (li > 0) b.add("\n", base)
        for ((n, t) in line.split(" ").filter { it.isNotEmpty() }.withIndex()) {
            if (n > 0) b.add(" ", base)
            val (lead, core, tail) = svSplitWord(t)
            b.add(lead, base)
            val ms = if (core.isEmpty()) emptyList() else svMorphemes(core)
            if (ms.size > 1 && hyphens) for (seg in SvColors.hyphened(ms, base, colours, dash)) b.add(seg.t, seg.c)
            else if (ms.size > 1) for (seg in SvColors.styledOf(ms, base, colours)) b.add(seg.t, seg.c)
            else b.add(core, base)
            b.add(tail, base)
        }
    }
    return b.build()
}

/** 瑞典語: a word the dictionary doesn't have, split into words it has: each part before another is a word (varning) or
 *  a word without its last -a / -e (flick|vän ← flicka), a linking letter (s, e, a, u, o) may come between two, and the
 *  last part is a word or one of its forms (området). The fewest parts win, then the fewest linking letters, then the
 *  longest first part. null: no way to split it into two words or more */
fun ZhDict.svCompound(word: String, skipWhole: Boolean = false): List<SvPart>? {
    val orig = word.cps()
    val low = word.lowercase().cps()
    val n = low.size
    if (n < 6 || n > 40 || low.size != orig.size || low.contains(" ")) return null
    fun key(a: Int, b: Int) = low.subList(a, b).joinToString("")
    fun shown(a: Int, b: Int) = orig.subList(a, b).joinToString("")
    fun headword(s: String): Int? = svIndices(s).firstOrNull { entries[it].h.lowercase() == s && !entries[it].h.contains(" ") }
    fun front(s: String): Int? = headword(s) ?: headword(s + "a") ?: headword(s + "e")
    // (a form of a shorter word first: områden → område + n)
    fun last(s: String): Int? {
        svIndices(s).firstOrNull { val h = entries[it].h.lowercase(); h.length < s.length && s.startsWith(h) && !h.contains(" ") }?.let { return it }
        return headword(s) ?: svIndices(s).firstOrNull { !entries[it].h.contains(" ") }
    }
    fun words(c: List<SvPart>) = c.count { !it.link }
    fun links(c: List<SvPart>) = c.count { it.link }
    fun better(c: List<SvPart>, t: List<SvPart>?): Boolean {
        if (t == null) return true
        if (words(c) != words(t)) return words(c) < words(t)
        if (links(c) != links(t)) return links(c) < links(t)
        return c[0].text.length > t[0].text.length
    }
    val memo = HashMap<Int, List<SvPart>?>()
    fun best(i: Int): List<SvPart>? {
        if (memo.containsKey(i)) return memo[i]
        memo[i] = null
        var top: List<SvPart>? = null
        // (skipWhole: the word itself is in the dictionary without its parts, ingenting: not the answer)
        if (n - i >= 3 && !(skipWhole && i == 0)) last(key(i, n))?.let { top = listOf(SvPart(shown(i, n), it, false)) }
        if (n - i >= 6) {
            for (j in (n - 3) downTo (i + 3)) {
                val e = front(key(i, j)) ?: continue
                val head = SvPart(shown(i, j), e, false)
                best(j)?.let { r -> val c = listOf(head) + r; if (better(c, top)) top = c }
                if (j < n - 3 && low[j] in listOf("s", "e", "a", "u", "o")) best(j + 1)?.let { r ->
                    val c = listOf(head, SvPart(shown(j, j + 1), null, true)) + r
                    if (better(c, top)) top = c
                }
            }
        }
        memo[i] = top
        return top
    }
    val r = best(0) ?: return null
    return if (words(r) >= 2) r else null
}

/** 瑞典語: a form the dictionary doesn't list (bussarna, vännen): the word left when a usual ending is taken off */
fun ZhDict.svInflected(s0: String): Int? {
    val s = s0.lowercase()
    fun headword(w: String): Int? = svIndices(w).firstOrNull { entries[it].h.lowercase() == w && !entries[it].h.contains(" ") }
    for (end in listOf("arnas", "ernas", "ornas", "arna", "erna", "orna", "ens", "ets", "en", "et", "na", "ar", "er", "or", "ade", "de", "te", "t", "n", "s")) {
        if (!s.endsWith(end) || s.length - end.length < 2) continue
        val st = s.dropLast(end.length)
        val tries = arrayListOf(st)
        if (st.length > 2 && st[st.length - 1] == st[st.length - 2]) tries.add(st.dropLast(1))
        if (end == "n") tries.add(st + "e")
        for (t in tries) headword(t)?.let { return it }
    }
    return null
}

/** 瑞典語: the entry a word as written is (the word, one of its forms, or a form the dictionary doesn't list) */
fun ZhDict.svKey(w: String): String? = svEntries(w).firstOrNull()?.k ?: svInflected(w)?.let { entries[it].k }

/** the morphemes of a compound's parts (each part's own, the last part's form ending after it) */
fun ZhDict.svCompoundMorphemes(parts: List<SvPart>): List<SvMorpheme> {
    val out = ArrayList<SvMorpheme>()
    for (p in parts) {
        if (p.link) { out.add(SvMorpheme(0, p.text, SvMorpheme.Kind.LINK)); continue }
        val i = p.entry ?: continue
        val e = entries[i]
        out.addAll(SvMorpheme.forForm(p.text, e.h, emptyList()).map { m -> if (m.kind == SvMorpheme.Kind.ROOT) m.copy(lemma = e.h) else m })
    }
    return SvMorpheme.renumbered(out)
}

/** a short meaning of an entry: its first Chinese one, else its first English one */
fun ZhDict.svGloss(e: ZhEntry): String = e.svZh.firstOrNull() ?: e.en?.split(";")?.firstOrNull()?.trim() ?: e.senses.firstOrNull()?.text ?: ""

/** 瑞典語: a word's morphemes: its own, or for a word the dictionary has without them (Arvsfonden), worked out */
fun ZhDict.svSyl(e: ZhEntry): List<String> {
    if (!isSv || SvMorpheme.parse(e.tw).size > 1 || e.h.contains(" ")) return e.tw
    return svWordSyl(e.h).ifEmpty { e.tw }
}

/** a word's short meaning: the first one of each entry it has (grund: 膚淺／基礎) */
fun ZhDict.svWordGloss(w: String): String? {
    val low = w.lowercase()
    var es = svEntries(low).filter { it.h.lowercase() == low }
    if (es.isEmpty()) es = svEntries(low).take(1)
    val gs = ArrayList<String>()
    for (e in es) { val g = svGloss(e); if (g.isNotEmpty() && g !in gs) gs.add(g) }
    return if (gs.isEmpty()) null else gs.take(2).joinToString("／")
}

/** a short meaning for a part: a root's word's, an affix's meaning */
fun ZhDict.svPartGloss(m: SvMorpheme): String? = if (m.kind == SvMorpheme.Kind.ROOT) svWordGloss(m.word) else SvAffixes.of(m)?.gloss

/** 瑞典語: a word the dictionary doesn't have, worked out from words it has and the rules: the base word (or a compound
 *  of words, or a prefix and a word), then the suffixes and endings each fitting the kind of word it's added to.
 *  null: no way to */
fun ZhDict.svEstimate(word: String, skipSelf: Boolean = false): SvEstimate? {
    val w = word.lowercase()
    if (w.length < 3 || w.length > 40 || w.length != word.length || w.contains(" ")) return null
    val memo = HashMap<String, List<SvEstimate>>()
    fun headwords(s: String) = svIndices(s).filter { !entries[it].h.contains(" ") }
    val prefixesLong = SvAffixes.prefixes.entries.sortedByDescending { it.key.length }
    fun core(s: String, prefixOK: Boolean = true): List<SvEstimate> {
        val out = ArrayList<SvEstimate>()
        for (i in (if (skipSelf && s == w) emptyList() else headwords(s))) {
            val e = entries[i]
            val ms = SvMorpheme.forForm(s, e.h, SvMorpheme.parse(e.tw))
            for (c in SvCls.of(e.pos)) out.add(SvEstimate(ms, c, listOf(SvPart(s, i, false)), emptyList(), if (c == SvCls.ANY) 1 else 0))
        }
        if (out.isNotEmpty()) return out
        svCompound(s, skipWhole = skipSelf && s == w)?.let { p ->
            val ms = svCompoundMorphemes(p)
            val cls = p.lastOrNull()?.entry?.let { SvCls.of(entries[it].pos) } ?: listOf(SvCls.ANY)
            val joins = p.count { !it.link } - 1
            return cls.map { c -> SvEstimate(ms, c, p, emptyList(), 3 * joins) }
        }
        if (prefixOK) for ((pre, a) in prefixesLong) {
            if (!(s.startsWith(pre) && s.length - pre.length >= 3)) continue
            for (r in core(s.drop(pre.length), false)) {
                out.add(r.copy(ms = SvMorpheme.renumbered(listOf(SvMorpheme(0, pre, SvMorpheme.Kind.PREFIX)) + r.ms),
                    steps = listOf(SvStep(pre, SvMorpheme.Kind.PREFIX, "前綴：" + a.zh, a.en, r.cls)) + r.steps, cost = r.cost + 2))
            }
            if (out.isNotEmpty()) break
        }
        return out
    }
    fun onto(base: String, b: String, ms: List<SvMorpheme>): List<SvMorpheme> {
        if (b == base) return ms
        val out = SvMorpheme.forForm(base, b, ms).toMutableList()
        val l = out.lastOrNull()
        if (out.size >= 2 && l != null && l.kind == SvMorpheme.Kind.ENDING && l.text.length == 1 && out[out.size - 2].kind == SvMorpheme.Kind.ROOT) {
            out[out.size - 2] = out[out.size - 2].copy(text = out[out.size - 2].text + l.text)
            out.removeAt(out.size - 1)
        }
        return out
    }
    fun better(x: SvEstimate, y: SvEstimate): Boolean {
        if (x.cost != y.cost) return x.cost < y.cost
        if (x.adj != y.adj) return x.adj < y.adj
        return x.ms.size < y.ms.size
    }
    fun analyze(s: String): List<SvEstimate> {
        memo[s]?.let { return it }
        memo[s] = emptyList()
        val best = HashMap<SvCls, SvEstimate>()
        fun keep(x: SvEstimate) { val o = best[x.cls]; if (o != null && !better(x, o)) return; best[x.cls] = x }
        for (x in core(s)) keep(x)
        for (rule in SvRules.all) {
            if (!(s.endsWith(rule.text) && s.length - rule.text.length >= 2)) continue
            val base = s.dropLast(rule.text.length)
            val cands = arrayListOf(base)
            if (SvCls.V in rule.from || SvCls.N in rule.from) cands.add(base + "a")
            if (SvCls.N in rule.from) cands.add(base + "e")
            if (SvCls.V in rule.from && (base.endsWith("g") || base.endsWith("d")) && base.length > 2) cands.add(base.dropLast(1))
            if (base.length > 3 && base[base.length - 1] == base[base.length - 2] && base.last() !in "aeiouyåäö") cands.add(base.dropLast(1))
            for (b in cands) for (r in analyze(b)) {
                if (!(r.cls in rule.from || r.cls == SvCls.ANY)) continue
                keep(SvEstimate(SvMorpheme.renumbered(onto(base, b, r.ms) + SvMorpheme(0, rule.text, rule.kind)), rule.to, r.parts,
                    r.steps + SvStep(rule.text, rule.kind, rule.zh, rule.en, rule.to), r.cost + 1 + (if (r.cls == SvCls.ANY) 1 else 0),
                    r.adj + (if (b == base) 0 else 1)))
            }
        }
        val out = best.values.sortedWith { x, y -> if (better(x, y)) -1 else if (better(y, x)) 1 else 0 }
        memo[s] = out
        return out
    }
    val top = analyze(w).firstOrNull() ?: return null
    if (top.steps.isEmpty() && top.parts.size <= 1) return null
    // (in the letters as written: Omhändertagandet)
    val orig = word.cps()
    var at = 0
    val ms = top.ms.map { m ->
        val n = m.text.cps().size
        val t = if (at + n <= orig.size) orig.subList(at, at + n).joinToString("") else m.text
        at += n
        m.copy(text = t)
    }
    return top.copy(ms = ms)
}
