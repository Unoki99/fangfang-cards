package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// MARK: - 轉換 → 讀音: a word in 台語, 華語, 粵語 and 客語 side by side

/** the 華語 and 粵語 dictionaries for 讀音: the one in use is the Store's; the other is read while the page is open */
@Composable
private fun rememberZhDict(kind: Int): ZhDict? {
    val have = Store.zh?.takeIf { it.lang == kind }
    val loaded by produceState<ZhDict?>(have, kind, have) {
        if (value != null) return@produceState
        value = withContext(Dispatchers.Default) {
            try { ZhDict(Store.app.assets.open(listOf("zh.json", "zh.json", "yue.json", "hak.json")[kind]).bufferedReader().use { it.readText() }) }
            catch (_: Exception) { null }
        }
    }
    return have ?: loaded
}

/** one row of the table: who says it (台語 purple, 華語 blue, 粵語 yellow), the reading (big, in tone colours) and the
 *  other spelling (small) */
private class ReadingRow(val lang: Int, val label: String, val main: AnnotatedString, val other: String, val note: String? = null)

@Composable
fun ReadingsPane() {
    var query by Prefs.readingsQuery
    val zh = rememberZhDict(1)
    val yue = rememberZhDict(2)
    val hak = rememberZhDict(3)
    val hakRom = if (Store.lang == 3) Prefs.zhRom.value else Prefs.hakRom.value
    val d = Store.dict
    val rom = Prefs.rom.value; val toneSys = Prefs.toneSys.value
    val zhRom = if (Store.lang == 1) Prefs.zhRom.value else Prefs.mandRom.value
    val yueRom = if (Store.lang == 2) Prefs.zhRom.value else Prefs.yueRom.value
    val tk = textKey()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SearchField(query, { query = it }, tr("漢字（詞或字），例如：學生、食飯、行"))
        val q = query.trim()
        if (q.isNotEmpty()) {
            val rows = remember(q, d, zh, yue, hak, rom, zhRom, yueRom, hakRom, toneSys, tk) {
                taigiRows(d, q, rom, toneSys) + zhRows(zh, q, 1, zhRom) + zhRows(yue, q, 2, yueRom) + hakRows(hak, q, hakRom)
            }
            for (r in rows) {
                val fill = listOf(T.own, T.blue, T.olive, T.hakFill)[r.lang]; val edge = listOf(T.ownEdge, T.blueEdge, T.oliveEdge, T.hakEdge)[r.lang]
                val ink = listOf(T.purpleInk, T.blueInk, T.oliveInk, T.hakInk)[r.lang]
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(fill.copy(alpha = 0.35f))
                    .border(2.dp, edge, RoundedCornerShape(10.dp)).height(IntrinsicSize.Min), verticalAlignment = Alignment.CenterVertically) {
                    Txt(r.label, ff(FF.Subheadline, FontWeight.Bold), ink, Modifier.width(LABEL_W).padding(start = 10.dp, top = 10.dp, bottom = 10.dp))
                    Box(Modifier.width(2.dp).fillMaxHeight().background(edge))      // (as thick as the border)
                    Column(Modifier.weight(1f).padding(horizontal = 12.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Txt(r.main, lat(20f), T.glyph)
                        if (r.other.isNotEmpty()) Txt(r.other, ff(FF.Footnote), T.muted)
                        r.note?.let { Txt(it, ff(FF.Caption2), T.muted) }
                    }
                }
            }
            if (zh == null || yue == null || d == null) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CircularProgressIndicator(Modifier.size(16.dp), color = T.greenInk, strokeWidth = 2.dp)
                Txt(tr("載入詞典…"), ff(FF.Footnote), T.muted)
            }
        }
        Txt(tr("台語照各地的讀音（教育部辭典寫的，或照規則推出來的）；華語分臺灣和大陸；粵語有幾個讀音就列幾個。詞典沒有這個詞的時候，照每個字的讀音排（「逐字」）。"),
            ff(FF.Caption2), T.muted)
        Spacer(Modifier.height(30.dp))
    }
}

private val LABEL_W = 112.dp

/** a word typed in 簡體: the 台語 dictionary's 正體 one */
private fun traditional(d: Dict, s: String): String {
    if (d.hanMap.containsKey(s)) return s
    val sb = StringBuilder()
    s.codePoints().forEach { cp ->
        val ch = String(Character.toChars(cp))
        sb.appendCodePoint(if (d.hanMap.containsKey(ch)) cp else Simp.reverse(cp) ?: cp)
    }
    return sb.toString()
}

// MARK: 台語: 通行, then the places that say it another way

private fun taigiRows(d: Dict?, q0: String, rom: Int, toneSys: Int): List<ReadingRow> {
    if (d == null) return emptyList()
    val q = traditional(d, q0)
    val colours = toneSys != 0
    val out = ArrayList<ReadingRow>()
    val codesList = d.hanMap[q] ?: emptyList<String>()
    if (codesList.isEmpty()) {
        // not a word of the dictionary: each character's first reading
        val cs = q.codePoints().toArray().map { d.hanMap[String(Character.toChars(it))]?.firstOrNull() }
        if (cs.isNotEmpty() && cs.all { it != null }) {
            val codes = cs.filterNotNull().joinToString(" ")
            out.add(ReadingRow(0, tr("台語") + "・" + tr("通行"), AnnotatedString(d.codes(codes, rom, -1)), d.codes(codes, 3, -1), tr("逐字")))
        } else out.add(ReadingRow(0, tr("台語"), AnnotatedString("—"), "", tr("台語詞典沒有這個詞")))
        return out
    }
    for ((n, codes) in codesList.take(4).withIndex()) {
        val key = q + "\t" + codes
        val alt = if (n > 0) "（" + tr("又") + "）" else ""
        out.add(ReadingRow(0, tr("臺") + "・" + tr("通行") + alt, d.wordText(key, rom, -1).annotated(), d.wordText(key, 3, -1).plain()))
        // the places that say it differently (or, with tone colours, change its tones differently)
        class G(val codes: String, val tones: List<Int>, val places: MutableList<Int>)
        val groups = ArrayList<G>()
        val common = Dict.codesOf(key)
        val commonTones = if (colours) d.wordTones(key, -1) else emptyList()
        for (p in d.raw.places.indices) {
            val c = if (d.differsFromCommon(key, p)) d.codesFor(key, p) else common
            val t = if (colours) d.wordTones(key, p) else emptyList()
            if (c == common && t == commonTones) continue
            val i = groups.indexOfFirst { it.codes == c && it.tones == t }
            if (i >= 0) groups[i].places.add(p) else groups.add(G(c, t, mutableListOf(p)))
        }
        for (g in groups) {
            val names = g.places.joinToString("、") { tr(d.raw.places[it].take(2)) }
            val shownIn = if (g.codes == common) -1 else g.places[0]
            out.add(ReadingRow(0, tr("臺") + "・" + names, d.wordText(key, rom, shownIn, g.places[0]).annotated(),
                d.wordText(key, 3, shownIn, g.places[0]).plain(), if (d.guessedSyllables(key, g.places[0]).isEmpty()) null else tr("推測")))
        }
    }
    return out
}

// MARK: 華語 (臺灣, 大陸) and 粵語

private fun zhRows(d: ZhDict?, q: String, kind: Int, mode: Int): List<ReadingRow> {
    if (d == null) return emptyList()
    val es = (d.byHan[q] ?: emptyList<Int>()).map { d.entries[it] }.filter { it.h == q || it.alt == q }
    val seen = HashSet<List<String>>()
    val out = ArrayList<ReadingRow>()
    for (e in es) {
        if (!seen.add(e.tw)) continue
        val alt = if (out.isNotEmpty()) "（" + tr("又") + "）" else ""
        if (kind == 1) {
            out.add(ReadingRow(1, tr("華") + "・" + tr("臺灣") + alt, d.reading(e.tw, mode).annotated(), d.readingPlain(e.tw, 1 - mode)))
            val lu = e.lu
            if (lu != null && lu != e.tw) out.add(ReadingRow(1, tr("華") + "・" + tr("大陸") + alt, d.reading(lu, mode).annotated(), d.readingPlain(lu, 1 - mode)))
        } else out.add(ReadingRow(2, tr("粵語") + alt, d.reading(e.tw, mode).annotated(), d.readingPlain(e.tw, 1 - mode)))
        if (out.size >= 6) break
    }
    if (out.isEmpty()) {
        // not a word of the dictionary: each character's usual reading
        val syl = ArrayList<String>()
        for (cp in q.codePoints().toArray()) {
            val c = String(Character.toChars(cp))
            val i = (d.byHan[c] ?: emptyList<Int>()).firstOrNull { d.entries[it].h == c || d.entries[it].alt == c }
            val s = i?.let { d.entries[it].tw.firstOrNull() }
            if (s == null) { syl.clear(); break }
            syl.add(s)
        }
        val name = if (kind == 2) tr("粵語") else tr("華語")
        out.add(if (syl.isNotEmpty()) ReadingRow(kind, name, d.reading(syl, mode).annotated(), d.readingPlain(syl, 1 - mode), tr("逐字"))
            else ReadingRow(kind, name, AnnotatedString("—"), "", if (kind == 2) tr("粵語詞典沒有這個詞") else tr("華語詞典沒有這個詞")))
    }
    return out
}

// MARK: 客語: each accent (the ones that read it the same together)

private fun hakRows(d: ZhDict?, q: String, mode: Int): List<ReadingRow> {
    if (d == null) return emptyList()
    val es = (d.byHan[q] ?: emptyList<Int>()).map { d.entries[it] }.filter { it.h == q }
    val out = ArrayList<ReadingRow>()
    for ((n, e) in es.take(3).withIndex()) {
        val alt = if (n > 0) "（" + tr("又") + "）" else ""
        val acc = e.acc ?: listOf(e.tw)
        // the accents with the same reading (letters and tone category) in one row
        class G(val key: String, val syl: List<String>, val names: MutableList<String>)
        val groups = ArrayList<G>()
        for ((a, syl) in acc.withIndex()) {
            if (syl == null) continue
            val key = syl.joinToString(" ") { val p = Zhuyin.hakParts(it); p.first + p.second }
            val name = tr(Lang.hakAccents.getOrElse(a) { "" })
            val g = groups.firstOrNull { it.key == key }
            if (g != null) g.names.add(name) else groups.add(G(key, syl, mutableListOf(name)))
        }
        for (g in groups) out.add(ReadingRow(3, tr("客") + "・" + g.names.joinToString("、") + alt, d.reading(g.syl, mode).annotated(), d.readingPlain(g.syl, 1 - mode)))
    }
    if (out.isEmpty()) out.add(ReadingRow(3, tr("客語"), AnnotatedString("—"), "", tr("客語詞典沒有這個詞")))
    return out
}
