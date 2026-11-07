package com.unoki99.fangfang.engine

import com.unoki99.fangfang.tr

/** Copying one meaning of a word to the clipboard, in a layout set in 設定 (複製意思的格式). */
object SenseCopy {
    class Preset(val name: String, val tpl: String, val ex: String, val sep: Int)
    val presets = listOf(
        Preset("簡單",
            "{漢字}　{羅馬字}　{方音}\n{號}. 〔{詞類}〕{意思}\n{所有例句}",
            "・{例句}\n　{例句羅馬字}\n　{例句華語}", 0),
        Preset("Discord",
            "## {漢字}\n**{羅馬字}**　{方音}\n> {號}. *{詞類}* {意思}\n{所有例句}",
            "- {例句}\n  {例句羅馬字}\n  -# {例句華語}", 0),
        Preset("一行（Tab 分開）",
            "{漢字}\t{羅馬字}\t{方音}\t{詞類}\t{意思}\t{所有例句}\t{詞音檔}",
            "{例句}（{例句羅馬字}）{例句華語}", 2),
    )
    val seps = listOf("換行", "空一行", "<br>", "；")
    private val sepText = listOf("\n", "\n\n", "<br>", "；")

    val wordTokens = listOf("{漢字}", "{羅馬字}", "{皓羅}", "{台羅}", "{白話字}", "{方音}", "{華語}", "{號}", "{詞類}", "{意思}", "{詞音檔}", "{所有例句}")
    val exTokens = listOf("{例句}", "{例句羅馬字}", "{例句皓羅}", "{例句台羅}", "{例句白話字}", "{例句方音}", "{例句華語}", "{例句音檔}")

    private val trimChars = " \t　-#>*_・.。:：".toSet()

    /** fills a template. An empty value takes the brackets or ** around it along with it,
     *  and a line left with nothing on it is dropped. */
    fun fill(t: String, v: Map<String, String>): String {
        val out = ArrayList<String>()
        for (line in t.split("\n")) {
            var s = line
            for ((k, value) in v) {
                if (!s.contains(k)) continue
                s = if (value.isEmpty()) s.replace(Regex("[〔（(\\[「*_~]*" + Regex.escape(k) + "[〕）)\\]」*_~]*"), "")
                else s.replace(k, value)
            }
            // a line that only had empty values on it goes; a line left blank on purpose stays
            if (s != line && s.all { it in trimChars }) continue
            out.add(s)
        }
        return out.joinToString("\n")
    }

    private fun sepOf(sep: Int) = sepText[sep.coerceIn(0, sepText.size - 1)]

    private fun finish(tpl: String, v: Map<String, String>, body: String): String {
        var out = fill(tpl, v)
        if (out.contains("{所有例句}")) {
            out = if (body.isEmpty()) fill(out, mapOf("{所有例句}" to "")) else out.replace("{所有例句}", body)
        } else if (body.isNotEmpty()) out += "\n" + body
        return out
    }

    fun text(d: Dict, key: String, i: Int, rom: Int, place: Int, tpl: String, exTpl: String, sep: Int): String {
        val all = d.senses(key)
        if (i < 0 || i >= all.size) return ""
        val m = all[i]
        val r = rom.coerceIn(0, 2)
        val exs = m.ex.map { x ->
            val tp = x.getOrElse(1) { "" }
            fun s(sys: Int) = if (tp.isEmpty()) "" else d.sentence(tp, sys, place, x[0])
            fill(exTpl, linkedMapOf(
                "{例句羅馬字}" to s(r), "{例句皓羅}" to s(0), "{例句台羅}" to s(1), "{例句白話字}" to s(2), "{例句方音}" to s(3),
                "{例句華語}" to x.getOrElse(2) { "" }, "{例句音檔}" to x.getOrElse(3) { "" }, "{例句}" to x[0],
            ))
        }
        val gl = (d.gl[key] ?: emptyList()).joinToString("、") { it.t }
        // the sentences are put in last, so what they contain is never read as a token
        val v = linkedMapOf(
            "{羅馬字}" to d.word(key, r, place), "{皓羅}" to d.word(key, 0, place), "{台羅}" to d.word(key, 1, place),
            "{白話字}" to d.word(key, 2, place), "{方音}" to d.word(key, 3, place), "{華語}" to gl,
            "{號}" to "${m.n}", "{詞類}" to m.pos, "{意思}" to m.text,
            "{詞音檔}" to (d.raw.au[key]?.let { "$it(1)" } ?: ""), "{漢字}" to Dict.hanOf(key),
        )
        return finish(tpl, v, exs.joinToString(sepOf(sep)))
    }

    // 華語: a layout of its own (設定 → 詞典 → 複製意思的格式（華語）)
    val zhPresets = listOf(
        Preset("簡單",
            "{漢字}　{羅馬字}　{注音}\n{號}. 〔{詞類}〕{意思}\n{英文}\n{所有例句}",
            "・{例句}\n　{例句羅馬字}\n　{例句出處}", 0),
        Preset("Discord",
            "## {漢字}\n**{羅馬字}**　{注音}\n> {號}. *{詞類}* {意思}\n> {英文}\n{所有例句}",
            "- {例句}\n  {例句羅馬字}\n  -# {例句出處}", 0),
        Preset("一行（Tab 分開）",
            "{漢字}\t{拼音}\t{注音}\t{詞類}\t{意思}\t{英文}\t{所有例句}",
            "{例句}（{例句拼音}）", 2),
    )
    val zhWordTokens = listOf("{漢字}", "{簡體}", "{羅馬字}", "{拼音}", "{注音}", "{號}", "{詞類}", "{意思}", "{英文}", "{英文列表}", "{所有例句}")
    val zhExTokens = listOf("{例句}", "{例句羅馬字}", "{例句拼音}", "{例句注音}", "{例句出處}")

    /** the name of a layout (or 自訂) */
    fun styleName(zh: Boolean, tpl: String, ex: String, sep: Int): String =
        (if (zh) zhPresets else presets).firstOrNull { it.tpl == tpl && it.ex == ex && it.sep == sep }?.name?.let { tr(it) } ?: tr("自訂")

    /** a 華語 meaning, in the 華語 layout: {羅馬字} = 拼音 or 注音 as shown, {拼音}, {注音}, {英文}, {詞類} (from the word
     *  lists). The 台語 names still work ({方音} = 注音, {皓羅}/{台羅}/{白話字} = 拼音, {例句華語} = where it's from). */
    fun zhText(d: ZhDict, key: String, i: Int, rom: Int, place: Int, tpl: String, exTpl: String, sep: Int): String {
        val e = d.entry(key) ?: return ""
        if (i < 0 || i >= e.senses.size) return ""
        val m = e.senses[i]
        val syl = e.syl(place)
        val exs = m.ex.map { x ->
            val ps = ZhDict.pieces(x)
            fun s(mode: Int) = d.sentence(ps, mode, place, colours = 0).plain()
            val py = s(0); val zy = s(1)
            fill(exTpl, linkedMapOf(
                "{例句羅馬字}" to s(rom), "{例句拼音}" to py, "{例句注音}" to zy, "{例句出處}" to x.src,
                "{例句皓羅}" to py, "{例句台羅}" to py, "{例句白話字}" to py, "{例句方音}" to zy,
                "{例句華語}" to x.src, "{例句音檔}" to "", "{例句}" to x.h,
            ))
        }
        val py = d.readingPlain(syl, 0); val zy = d.readingPlain(syl, 1)
        val ens = e.enList
        val v = linkedMapOf(
            "{羅馬字}" to d.readingPlain(syl, rom), "{拼音}" to py, "{注音}" to zy, "{皓羅}" to py, "{台羅}" to py, "{白話字}" to py,
            "{方音}" to zy, "{華語}" to "", "{簡體}" to (e.alt?.takeIf { it != e.h } ?: ""),
            "{號}" to "${m.n}", "{詞類}" to e.pos.joinToString("、"), "{意思}" to m.text, "{詞音檔}" to "",
            "{英文列表}" to ens.withIndex().joinToString("\n") { "${it.index + 1}. ${it.value}" },
            "{英文}" to ens.joinToString("; "), "{漢字}" to e.h,
        )
        return finish(tpl, v, exs.joinToString(sepOf(sep)))
    }
}
