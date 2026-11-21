package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.History
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.engine.*
import java.util.Calendar
import java.util.Date

// MARK: - 複習 (spaced review) and 練習統計

/** 不熟: how many words are due for review, and the button to the statistics */
@Composable
fun ReviewBar(due: Int, onStats: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.7f))
        .border(1.dp, T.fnEdge, RoundedCornerShape(12.dp)).clickable(onClick = onStats).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Filled.History, null, tint = T.btnInk, modifier = Modifier.size(20.dp))
        if (due > 0) {
            Txt(tr("要複習的詞"), ff(FF.Subheadline), T.glyph)
            Txt("$due", ff(FF.Subheadline, FontWeight.Bold), T.btnInk)
        } else Txt(tr("現在沒有要複習的詞"), ff(FF.Subheadline), T.muted)
        Spacer(Modifier.weight(1f))
        Icon(Icons.Filled.BarChart, null, tint = T.btnInk, modifier = Modifier.size(20.dp))
        Txt(tr("統計"), ff(FF.Subheadline), T.glyph)
    }
}

private class Counts { var unknown = 0; var learning = 0; var young = 0; var mature = 0; var due = 0; var swiped = 0 }

/** 練習統計: where the words of the language shown are, what's coming back when, and the answers of the last 30 days */
@Composable
fun ReviewStatsScreen(onClose: () -> Unit) {
    Store.rev
    val p = Store.progress
    val lang = Store.lang
    val now = System.currentTimeMillis() / 1000.0
    val c = Counts()
    for ((k, st) in p.status) {
        if (Lang.kind(k) != lang) continue
        if (st == 2) { if ((p.streak[k] ?: 0) > 0) c.learning++ else c.unknown++ }
        else if (st == 1) {
            val s = p.srs[k]
            if (s != null && s.size >= 2 && s[1] >= 1) {
                if (s[1] >= SRS.MATURE_DAYS) c.mature++ else c.young++
                if (s[0] <= now) c.due++
            } else c.swiped++
        }
    }
    // the words coming back on each of the next 7 days (today: also the ones waiting)
    val today0 = startOfDay(Date())
    val next = IntArray(7)
    for ((k, s) in p.srs) {
        if (s.size < 2 || s[1] < 1 || p.status[k] != 1 || Lang.kind(k) != lang) continue
        val d = Math.round((startOfDay(Date((s[0] * 1000).toLong())) - today0) / 86_400_000.0).toInt()
        if (d < 7) next[maxOf(0, d)]++
    }
    // right / wrong / learned on each of the last 30 days (oldest first)
    val name = Lang.names[lang]
    val last = (29 downTo 0).map { back ->
        val l = p.log[SRS.dayKey(name, dayFrom(-back))] ?: emptyList<Int>()
        Triple(l.getOrElse(0) { 0 }, l.getOrElse(1) { 0 }, l.getOrElse(2) { 0 })
    }
    val today = last.last()
    val total = last.sumOf { it.first + it.second }
    val right = last.sumOf { it.first }

    Column(Modifier.fillMaxSize()) {
        TopBar(tr("練習統計"), onClose, close = true, settings = false)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).widthIn(max = 700.dp).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            // where the words are
            val tiles = listOf(Triple(tr("要複習"), c.due, T.btnInk), Triple(tr("不熟"), c.unknown, T.rustInk),
                Triple(tr("學習中"), c.learning, T.oliveInk), Triple(tr("複習中"), c.young, T.blueInk),
                Triple(tr("記熟了"), c.mature, T.greenInk), Triple(tr("滑過去的熟悉"), c.swiped, T.muted))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for (row in tiles.chunked(2)) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    for ((t, n, ink) in row) Column(Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.7f))
                        .border(1.dp, T.fnEdge, RoundedCornerShape(12.dp)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Txt(t, ff(FF.Footnote), T.muted)
                        Txt("$n", ff(FF.Title2, FontWeight.Bold), ink)
                    }
                }
            }
            Txt(tr("學習中：答對過，還沒學會。複習中：練習學會的詞，會照時間回來複習。記熟了：三個禮拜以上才回來一次。滑過去的熟悉：在「新詞」往右滑的詞，不會回來複習。"),
                ff(FF.Caption), T.muted)

            StatSection(tr("今天")) {
                Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    Stat(tr("答對"), today.first, T.greenInk)
                    Stat(tr("答錯"), today.second, T.rustInk)
                    Stat(tr("學會"), today.third, T.btnInk)
                }
            }
            StatSection(tr("接下來 7 天要複習的詞")) {
                Bars(next.map { it.toDouble() to 0.0 }, (0 until 7).map { if (it == 0) tr("今天") else dayLabel(it) }, true)
            }
            StatSection(tr("最近 30 天的答題")) {
                Bars(last.map { it.first.toDouble() to it.second.toDouble() }, (0 until 30).map { if (it % 7 == 2) dayLabel(it - 29) else "" }, false)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Legend(T.greenInk, tr("答對")); Legend(T.rustInk, tr("答錯"))
                    Spacer(Modifier.weight(1f))
                    if (total > 0) Txt(tr("答對率 {0}%", Math.round(right * 100.0 / total).toInt()), ff(FF.Subheadline, FontWeight.Bold), T.glyph)
                }
            }
            Txt(tr("複習的間隔照 SM-2 的方法：學會以後 1 天、3 天，再來每次大約 2.5 倍；答錯就回到「不熟」重新學，以後的間隔也短一點。Algorithm SM-2, (C) Copyright SuperMemo World, 1991."),
                ff(FF.Caption2), T.muted)
            Spacer(Modifier.height(30.dp))
        }
    }
}

private fun startOfDay(d: Date): Long = Calendar.getInstance().apply {
    time = d; set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
}.timeInMillis

private fun dayFrom(offset: Int): Date = Calendar.getInstance().apply { add(Calendar.DAY_OF_MONTH, offset) }.time

private fun dayLabel(offset: Int): String {
    val c = Calendar.getInstance().apply { add(Calendar.DAY_OF_MONTH, offset) }
    return "${c.get(Calendar.MONTH) + 1}/${c.get(Calendar.DAY_OF_MONTH)}"
}

@Composable
private fun StatSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.7f))
        .border(1.dp, T.fnEdge, RoundedCornerShape(14.dp)).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Txt(title, ff(FF.Subheadline, FontWeight.Bold), T.glyph)
        content()
    }
}

@Composable
private fun Stat(title: String, n: Int, ink: Color) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Txt("$n", ff(FF.Title3, FontWeight.Bold), ink)
        Txt(title, ff(FF.Caption), T.muted)
    }
}

@Composable
private fun Legend(c: Color, t: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Box(Modifier.size(10.dp).clip(RoundedCornerShape(2.dp)).background(c))
        Txt(t, ff(FF.Caption), T.muted)
    }
}

/** a bar for each value (first: the language's colour / green, second: red on top of it) */
@Composable
private fun Bars(values: List<Pair<Double, Double>>, labels: List<String>, showNumbers: Boolean) {
    val top = maxOf(1.0, values.maxOfOrNull { it.first + it.second } ?: 1.0)
    Row(Modifier.fillMaxWidth().height(if (showNumbers) 150.dp else 135.dp), verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(if (values.size > 10) 3.dp else 8.dp)) {
        for ((i, v) in values.withIndex()) Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (showNumbers) Txt(if (v.first > 0) "${v.first.toInt()}" else "", ff(FF.Caption2), T.muted)
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(3.dp))) {
                if (v.second > 0) Box(Modifier.fillMaxWidth().height((110 * v.second / top).dp).background(T.rustInk))
                val h = 110 * v.first / top
                if (v.first > 0) Box(Modifier.fillMaxWidth().height(maxOf(2.0, h).dp).background(if (showNumbers) T.btnInk else T.greenInk))
            }
            Box(Modifier.height(14.dp).wrapContentWidth(unbounded = true)) { Txt(labels[i], ff(FF.Caption2), T.muted, maxLines = 1) }
        }
    }
}

// MARK: - 我的進度 (the profile page, from the button at the top left of the main pages), the same as the iPhone / iPad's

/** 我的進度: everything about what you know and how you've been learning, in tiles (side by side when there's room) */
@Composable
fun ProfileScreen(onClose: () -> Unit) {
    Store.rev
    AppBackground {
        Column(Modifier.fillMaxSize()) {
            TopBar(tr("我的進度"), onClose, close = true, settings = false)
            androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
                val cols = maxOf(1, minOf(3, (maxWidth.value / 340f).toInt()))
                val tiles = buildList<Pair<String, @Composable () -> Unit>> {
                    add(tr("認識的詞") to { WordsTile() })
                    if (Store.isZh || Store.freqTopics.isNotEmpty()) add(levelTitle() to { LevelTile() })
                    add(tr("最近 30 天的練習") to { PracticeTile() })
                    add(tr("聽的時間") to { ListenTile() })
                    add(tr("影片懂多少") to { VideoTile() })
                    add(tr("複習") to { ReviewTile() })
                }
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(14.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    for (row in tiles.chunked(cols)) Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        for ((title, body) in row) Column(Modifier.weight(1f).clip(RoundedCornerShape(18.dp)).background(T.fn.copy(alpha = 0.6f))
                            .border(1.dp, T.fnEdge, RoundedCornerShape(18.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Txt(title, ff(FF.Headline), T.glyph)
                            body()
                        }
                        repeat(cols - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                    Spacer(Modifier.height(30.dp))
                }
            }
        }
    }
}

@Composable
private fun RowScope.Big(n: String, label: String, c: Color = T.btnInk) {
    Column(Modifier.weight(1f)) {
        Txt(n, ff(FF.Title2, FontWeight.Bold), c)
        Txt(label, ff(FF.Caption), T.muted)
    }
}

/** 認識的詞, by language */
@Composable
private fun WordsTile() {
    val p = Store.progress
    val n = Lang.names.size
    val known = IntArray(n); val unknown = IntArray(n)
    for ((k, s) in p.status) {
        val l = Lang.kind(k).coerceIn(0, n - 1)
        if (s == 1) known[l]++ else if (s == 2) unknown[l]++
    }
    Row { Big("${known.sum()}", tr("熟悉")); Big("${unknown.sum()}", tr("不熟"), T.oliveInk); Big("${p.saved.values.count { it > 0 }}", tr("收藏"), T.blueInk) }
    for (l in 0 until n) if (known[l] + unknown[l] > 0) {
        val t = (known[l] + unknown[l]).toDouble()
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Txt(tr(Lang.names[l]), ff(FF.Subheadline, FontWeight.SemiBold), T.glyph, Modifier.widthIn(min = 52.dp))
            Box(Modifier.weight(1f)) { SplitPotionBar(known[l] / t, unknown[l] / t, levelColor(l + 1), 18.dp, tr(Lang.names[l])) }
            Txt("${known[l]}／${unknown[l]}", ff(FF.Caption), T.muted)
        }
    }
}

private fun levelTitle(): String =
    if (Store.lang == 1) tr("{0} 等級", Lang.listNames[Prefs.zhList.value.coerceIn(0, 1)]) else if (Store.isZh) tr("常用詞") else tr("常用詞和常用字")

/** HSK / TOCFL (華語) or 常用詞 (台語): each level, and the level you're at */
@Composable
private fun LevelTile() {
    val topics = if (Store.isZh) Store.topics else Store.freqTopics
    val all = Store.allTopicProgress()
    val words = topics.filter { if (Store.isZh) it.id < Lang.charTopicBase else it.id < Lang.freqCharBase }
    val chars = topics.filter { if (Store.isZh) it.id > Lang.charTopicBase else it.id >= Lang.freqCharBase }
    // (the level you're at: the highest one whose words, and every one before it, you know 80% of)
    fun reached(ts: List<Topic>): String? {
        var last: String? = null
        for (t in ts) {
            val p = all[t.id] ?: break
            if (p.total <= 0 || p.known.toDouble() / p.total < 0.8) break
            last = t.name
        }
        return last
    }
    Row { Big(reached(words) ?: "—", tr("詞的等級")); if (chars.isNotEmpty()) Big(reached(chars) ?: "—", tr("字的等級"), T.blueInk) }
    for (t in words + chars) {
        val p = all[t.id] ?: Store.LevelProgress(0, 0, 0)
        val k = if (p.total > 0) p.known.toDouble() / p.total else 0.0
        val u = if (p.total > 0) p.unknown.toDouble() / p.total else 0.0
        Column {
            Row { Txt(t.name, ff(FF.Caption, FontWeight.SemiBold), T.glyph, Modifier.weight(1f)); Txt("${Math.round(k * 100)}%", ff(FF.Caption), levelColor(t.id)) }
            SplitPotionBar(k, u, levelColor(t.id), 16.dp, t.name)
        }
    }
    Txt(tr("等級：那一級（和前面每一級）的詞你認識八成以上。"), ff(FF.Caption2), T.muted)
}

/** the last 30 days, oldest first */
private val last30: List<Date> get() = (29 downTo 0).map { dayFrom(-it) }
private fun dayString(d: Date) = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(d)

/** practice, the last 30 days (every language) */
@Composable
private fun PracticeTile() {
    val p = Store.progress
    val per = last30.map { d ->
        var r = 0; var w = 0; var l = 0
        for (n in Lang.names) { val v = p.log[SRS.dayKey(n, d)] ?: continue; r += v.getOrElse(0) { 0 }; w += v.getOrElse(1) { 0 }; l += v.getOrElse(2) { 0 } }
        Triple(r, w, l)
    }
    val right = per.sumOf { it.first }; val wrong = per.sumOf { it.second }
    // (days in a row with practice, up to today; today without practice yet doesn't break it)
    var streak = 0
    for ((i, x) in per.asReversed().withIndex()) { if (x.first + x.second > 0) streak++ else if (i > 0) break }
    Row {
        Big("${right + wrong}", tr("題"))
        Big(if (right + wrong > 0) "${Math.round(100.0 * right / (right + wrong))}%" else "—", tr("答對"), T.oliveInk)
        Big("${per.sumOf { it.third }}", tr("學會"), T.blueInk)
        Big("$streak", tr("連續天數"), T.pinkInk)
    }
    DayBars(per.map { it.first.toDouble() to it.second.toDouble() }, T.btnEdge, T.muted.copy(alpha = 0.5f))
    Txt(tr("綠：答對　灰：答錯（每一天一條，最右邊是今天）"), ff(FF.Caption2), T.muted)
}

/** listening: the radio and videos (with the add-on's subtitle panel) */
@Composable
private fun ListenTile() {
    val p = Store.progress
    val per = last30.map { d -> p.listen[dayString(d)] ?: listOf(0.0, 0.0) }
    val radio = per.sumOf { it.getOrElse(0) { 0.0 } }; val video = per.sumOf { it.getOrElse(1) { 0.0 } }
    val all = p.listen.values.sumOf { it.sum() }
    Row { Big("${Math.round(radio)}", tr("分鐘電台")); Big("${Math.round(video)}", tr("分鐘影片"), T.blueInk); Big("${Math.round(all / 60)}", tr("小時（全部）"), T.oliveInk) }
    DayBars(per.map { it.getOrElse(0) { 0.0 } to it.getOrElse(1) { 0.0 } }, T.btnEdge, T.blueEdge)
    Txt(tr("綠：電台　藍：影片（最近 30 天）"), ff(FF.Caption2), T.muted)
}

/** one bar a day: the first value at the bottom, the second on top of it */
@Composable
private fun DayBars(days: List<Pair<Double, Double>>, low: Color, high: Color) {
    val top = maxOf(1.0, days.maxOfOrNull { it.first + it.second } ?: 1.0)
    Row(Modifier.fillMaxWidth().height(60.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        for ((a, b) in days) Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.Bottom) {
            if (b > 0) Box(Modifier.fillMaxWidth().height((60 * b / top).dp).background(high))
            if (a > 0) Box(Modifier.fillMaxWidth().height((60 * a / top).dp).background(low))
        }
    }
}

/** videos: how much of each one's words you knew when you watched it (the add-on's 懂 %), and of the words you
 *  picked from it (影片詞組), how many you know now; oldest first */
@Composable
private fun VideoTile() {
    val p = Store.progress
    val words = HashMap<String, MutableList<String>>()
    for ((wk, t) in p.groupWords) if (t > 0) { val i = wk.indexOf('\u0001'); if (i > 0) words.getOrPut(wk.substring(0, i)) { ArrayList() }.add(wk.substring(i + 1)) }
    val seen = p.seen.filter { it.value.size >= 2 }
    val ids = HashSet(seen.keys)
    for ((id, t) in p.groupTime) if (t > 0 && !words[id].isNullOrEmpty()) ids.add(id)
    data class V(val name: String, val pct: Double?, val k: Int, val n: Int, val date: Double)
    val rows = ids.map { id ->
        val ws = words[id] ?: emptyList<String>()
        V(Store.groupName(id), seen[id]?.let { it[0] / 100 }, ws.count { p.status[it] == 1 }, ws.size, seen[id]?.get(1) ?: Math.abs(p.groupTime[id] ?: 0.0))
    }.sortedBy { it.date }
    if (rows.isEmpty()) { Txt(tr("還沒有影片。用查詞看影片字幕，再按「傳到 App」，就會有每個影片你懂多少。"), ff(FF.Footnote), T.muted); return }
    // (each video a bar: how much of it you understood; one with only picked words: how many of those you know, paler)
    Row(Modifier.fillMaxWidth().height(70.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        for (r in rows.takeLast(40)) {
            val v = r.pct ?: (r.k.toDouble() / maxOf(1, r.n))
            Box(Modifier.weight(1f).height(maxOf(3.0, 70 * v).dp).clip(RoundedCornerShape(2.dp))
                .background(levelColor((v * 7).toInt() + 1).copy(alpha = if (r.pct == null) 0.45f else 1f)))
        }
    }
    val fmt = java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM)
    for (r in rows.takeLast(6).asReversed()) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Txt(r.name, ff(FF.Caption), T.glyph, Modifier.weight(1f), maxLines = 1)
        if (r.n > 0) Txt(tr("選的詞") + " ${r.k}/${r.n}", ff(FF.Caption2), T.muted)
        Txt(r.pct?.let { tr("懂") + " ${Math.round(it * 100)}%" } ?: "—", ff(FF.Caption, FontWeight.SemiBold), T.glyph)
        Txt(fmt.format(Date((r.date * 1000).toLong())), ff(FF.Caption2), T.muted)
    }
    Txt(tr("每一條是一個影片（從左到右，舊到新）：懂 = 看的時候字幕裡的詞你認識多少；選的詞 = 你從那裡選的詞，現在認識幾個。"), ff(FF.Caption2), T.muted)
}

/** spaced review, every language */
@Composable
private fun ReviewTile() {
    val p = Store.progress
    val now = System.currentTimeMillis() / 1000.0
    val srs = p.srs.filter { it.value.size >= 2 && it.value[1] >= 1 }
    Row {
        Big("${srs.size}", tr("在複習裡"))
        Big("${srs.count { it.value[1] >= SRS.MATURE_DAYS }}", tr("記熟了"), T.oliveInk)
        Big("${srs.count { it.value[0] <= now && p.status[it.key] == 1 }}", tr("要複習"), T.pinkInk)
    }
}
