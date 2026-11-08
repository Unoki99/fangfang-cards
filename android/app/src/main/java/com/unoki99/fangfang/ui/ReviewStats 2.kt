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
