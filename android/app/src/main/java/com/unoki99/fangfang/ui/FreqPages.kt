package com.unoki99.fangfang.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CheckCircleOutline
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.tr
import com.unoki99.fangfang.engine.Lang
import androidx.compose.foundation.focusable
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// 常用度: the hollow ring beside each word (as full as the word is common, the same as the iPhone app's),
// 依常用度列出 (a dictionary's words in five steps by how full the ring is), and an entry's 加到「不熟」 / 認識 buttons.

/** the ring: how full (rank 0 → 1, 100 → about 0.8, 1000 → 0.6, 10 000 → 0.3, 60 000 and past → nearly empty) and its
 *  colour, from full to nearly empty: pink, red, orange, yellow, green, teal, blue, purple (and the shades between) */
object FrequencyRing {
    fun fill(rank: Int): Double {
        val x = Math.log(rank.toDouble() + 1) / Math.log(60000.0)
        return (1 - x * x).coerceIn(0.04, 1.0)
    }
    private val stops = listOf(
        Triple(0.58f, 0.38f, 0.86f),   // purple
        Triple(0.24f, 0.48f, 0.95f),   // blue
        Triple(0.10f, 0.68f, 0.70f),   // teal
        Triple(0.30f, 0.72f, 0.32f),   // green
        Triple(0.95f, 0.78f, 0.16f),   // yellow
        Triple(0.97f, 0.55f, 0.14f),   // orange
        Triple(0.90f, 0.22f, 0.20f),   // red
        Triple(0.96f, 0.36f, 0.62f),   // pink
    )
    fun color(f: Double): androidx.compose.ui.graphics.Color {
        val x = f.coerceIn(0.0, 1.0) * (stops.size - 1)
        val i = minOf(x.toInt(), stops.size - 2); val t = (x - i).toFloat()
        val p = stops[i]; val q = stops[i + 1]
        return androidx.compose.ui.graphics.Color(p.first + (q.first - p.first) * t, p.second + (q.second - p.second) * t, p.third + (q.third - p.third) * t)
    }
}

/** the ring itself: as full as `fill` (or the place's), in its colour */
@Composable
fun FrequencyRingView(rank: Int = 0, size: androidx.compose.ui.unit.Dp = 16.dp, line: androidx.compose.ui.unit.Dp = 3.dp, fill: Double? = null) {
    val f = fill ?: FrequencyRing.fill(rank)
    val c = FrequencyRing.color(f)
    val track = T.fnEdge.copy(alpha = 0.6f)
    androidx.compose.foundation.Canvas(Modifier.size(size)) {
        val w = line.toPx()
        val inset = w / 2
        val box = androidx.compose.ui.geometry.Size(this.size.width - w, this.size.height - w)
        val at = androidx.compose.ui.geometry.Offset(inset, inset)
        drawArc(track, 0f, 360f, false, at, box, style = androidx.compose.ui.graphics.drawscope.Stroke(w))
        drawArc(c, -90f, (360 * f).toFloat(), false, at, box,
            style = androidx.compose.ui.graphics.drawscope.Stroke(w, cap = androidx.compose.ui.graphics.StrokeCap.Round))
    }
}

object FreqLevels {
    val names = mapOf(5 to "很常用", 4 to "常用", 3 to "一般", 2 to "不常用", 1 to "少見")
    fun name(l: Int): String = tr(names[l] ?: "")
    /** where the ring crosses 80, 60, 40 and 20 % (about 136, 1046, 5029, 18 800) */
    val cuts: List<Int> = listOf(0.8, 0.6, 0.4, 0.2).map { f -> maxOf(1, Math.pow(60000.0, Math.sqrt(1 - f)).toInt() - 1) }
    /** a step's 圓圈 % and its places */
    fun range(l: Int): String {
        val pc = listOf("", "0–20%", "20–40%", "40–60%", "60–80%", "80–100%")[l.coerceIn(1, 5)]
        val b = bounds(l)
        val at = if (b.last == Int.MAX_VALUE - 1) tr("{0} 以後", b.first) else if (b.first == 0) tr("前 {0} 個", b.last + 1) else "${b.first + 1}–${b.last + 1}"
        return tr("圓圈 {0}・", pc) + at
    }
    /** the step a place is in: by how full its ring is */
    fun level(rank: Int): Int = when {
        rank < cuts[0] -> 5; rank < cuts[1] -> 4; rank < cuts[2] -> 3; rank < cuts[3] -> 2; else -> 1
    }
    /** the places (from 0) of a step's words */
    fun bounds(l: Int): IntRange = when (l) {
        5 -> 0 until cuts[0]; 4 -> cuts[0] until cuts[1]; 3 -> cuts[1] until cuts[2]; 2 -> cuts[2] until cuts[3]; else -> cuts[3] until Int.MAX_VALUE
    }
}

/** a step's icon: the ring as full as the step's middle (like the ring beside each word) */
@Composable
fun FreqLevelBars(level: Int, kind: Int, small: Boolean = true) {
    FrequencyRingView(size = if (small) 18.dp else 22.dp, line = if (small) 3.dp else 3.5.dp, fill = listOf(0.0, 0.1, 0.3, 0.5, 0.7, 0.92)[level.coerceIn(0, 5)])
}

/** the ring beside a word in a list (nothing for a word without a place) */
@Composable
fun FrequencyBars(key: String) {
    val r = remember(key, Store.zh) { Store.freqRank(key) }
    if (r != Int.MAX_VALUE) FrequencyRingView(r)
}

/** 加到「不熟」 and 認識 for a word, showing where it is now (also for a word that isn't one of the cards) */
@Composable
fun MarkButtons(key: String) {
    Store.rev
    val st = Store.wordStatus(key)
    CapsuleButton(if (st == 2) tr("在「不熟」") else tr("加到「不熟」"), if (st == 2) Icons.Filled.Star else Icons.Filled.StarBorder,
        st == 2, T.rust, T.rustEdge, T.rustInk) { Store.toggleUnknownWord(key) }
    CapsuleButton(if (st == 1) tr("熟悉") else tr("認識"), if (st == 1) Icons.Filled.CheckCircle else Icons.Filled.CheckCircleOutline,
        st == 1, T.green, T.greenEdge, T.greenInk) { Store.toggleKnown(key) }
}

/** the words of the language shown, the most common first (zh: the dictionary's keys; 台語: the cards') */
private fun freqKeys(zh: Boolean): List<String> =
    if (zh) Store.zh?.entries?.map { it.k } ?: emptyList() else Store.cards.map { it.k }

/** 依常用度列出: the five steps, each with how many of its words are 熟悉 / 不熟 */
@Composable
fun FreqBandsPage(zh: Boolean, onBack: () -> Unit) {
    val nav = LocalNav.current
    Store.rev
    val kind = if (zh) (Store.zh?.lang ?: 1) else 0
    // (known / unknown / all of each step, counted away from the screen)
    var counts by remember { mutableStateOf<Map<Int, IntArray>?>(null) }
    LaunchedEffect(zh, Store.rev) {
        counts = withContext(Dispatchers.Default) {
            val keys = freqKeys(zh)
            val out = HashMap<Int, IntArray>()
            for (l in 1..5) {
                val b = FreqLevels.bounds(l)
                val a = IntArray(3)
                for (i in b.first until minOf(b.last + 1, keys.size).coerceAtLeast(b.first)) {
                    a[0]++
                    when (Store.wordStatus(keys[i])) { 1 -> a[1]++; 2 -> a[2]++ }
                }
                out[l] = a
            }
            out
        }
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("依常用度列出"), onBack, settings = false)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
            item {
                ListCard {
                    var first = true
                    for (l in listOf(5, 4, 3, 2, 1)) {
                        val a = counts?.get(l)
                        if (a != null && a[0] == 0) continue
                        if (!first) RowDivider()
                        first = false
                        Column(Modifier.fillMaxWidth().clickable { nav.push(Route.FreqBand(zh, l)) }.padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                FreqLevelBars(l, kind, small = false)
                                Txt(FreqLevels.name(l), ff(FF.Body, FontWeight.SemiBold), T.glyph)
                                Txt(FreqLevels.range(l), ff(FF.Caption), T.muted, Modifier.weight(1f))
                                if (a != null) Txt(tr("{0} 個詞", a[0]), ff(FF.Caption), T.muted)
                                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted)
                            }
                            if (a != null) {
                                val n = maxOf(a[0], 1).toFloat()
                                Row(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(T.fnEdge.copy(alpha = 0.5f))) {
                                    if (a[1] > 0) Box(Modifier.fillMaxHeight().weight(a[1] / n).background(T.greenEdge))
                                    if (a[2] > 0) Box(Modifier.fillMaxHeight().weight(a[2] / n).background(T.rustEdge))
                                    val rest = (a[0] - a[1] - a[2]) / n
                                    if (rest > 0f) Spacer(Modifier.weight(rest))
                                }
                                Txt(tr("熟悉 {0}・不熟 {1}", a[1], a[2]), ff(FF.Caption2), T.muted)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                Txt(tr("和每個詞旁邊的常用度一樣分五級。綠色是熟悉的詞，紅色是不熟的詞。"), ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
            }
        }
    }
}

/** one step's words, with 全部 / 新詞 / 不熟 / 熟悉 */
@Composable
fun FreqBandPage(zh: Boolean, level: Int, onBack: () -> Unit) {
    Store.rev
    var show by remember { mutableIntStateOf(-1) }
    val all = remember(zh, level, Store.zh) {
        val keys = freqKeys(zh)
        val b = FreqLevels.bounds(level)
        if (b.first >= keys.size) emptyList() else keys.subList(b.first, minOf(b.last + 1, keys.size).coerceAtLeast(b.first))
    }
    val list = if (show < 0) all else all.filter { Store.wordStatus(it) == show }
    Column(Modifier.fillMaxSize()) {
        TopBar(FreqLevels.name(level), onBack, settings = false)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
            item {
                Segmented(listOf(-1 to tr("全部"), 0 to tr("新詞"), 2 to tr("不熟"), 1 to tr("熟悉")), show, { show = it })
                Spacer(Modifier.height(8.dp))
            }
            if (zh) {
                val z = Store.zh
                if (z != null) zhItems(z, tr("{0} 個詞", list.size), list.take(3000).mapNotNull { z.index[it] }, limit = 3000)
            } else {
                val d = Store.dict
                if (d != null) keyItems(d, tr("{0} 個詞", list.size), list.take(3000))
            }
            item { Spacer(Modifier.height(40.dp)) }
        }
    }
}


/** an entry with a keyboard (a tablet's): A = 認識 (熟悉), S = 不熟 and 收藏, as in the browser add-on. The entry takes
 *  the keys when it opens; typing in a search field keeps them letters there. */
@Composable
fun Modifier.entryKeys(key: String): Modifier {
    val fr = remember { FocusRequester() }
    LaunchedEffect(key) { try { fr.requestFocus() } catch (_: Exception) {} }
    return this.focusRequester(fr).focusable().onKeyEvent { e ->
        if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
        when (e.key) {
            Key.A -> { Store.keyKnown(key); true }
            Key.S -> { Store.keyUnknown(key); true }
            else -> false
        }
    }
}

/** a tablet's 查詞: a word tapped in the list on the left is shown on the right (null: opened as a page) */
val LocalSplitPick = androidx.compose.runtime.compositionLocalOf<((String) -> Unit)?> { null }

/** wide enough for the list and the entry side by side: a tablet, or a big phone on its side */
fun splitWide(w: androidx.compose.ui.unit.Dp, h: androidx.compose.ui.unit.Dp): Boolean = w >= 840.dp || (w > h && w >= 700.dp)
