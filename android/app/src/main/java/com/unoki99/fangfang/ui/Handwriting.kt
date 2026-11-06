package com.unoki99.fangfang.ui

import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.R
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.*

// 不熟 → 手寫練習 (華語): pick the characters (不熟的漢字, an HSK / TOCFL character level, the ones you know, or your
// own), then write each one with a finger or a stylus while you see it, its reading and meaning. 描字 puts the
// character under the grid in 楷體 (霞鶩文楷, which has the simplified characters too), and a potion shows how
// closely the writing follows it. A round left half way carries on the next time.

// MARK: - a practice left half way

/** A practice left half way carries on where it was the next time it's opened. Each kind of practice keeps one, for
 *  台語 and 華語 apart, with the 練習範圍 it was started in; it's thrown away when finished, started again, or after two weeks. */
object PracticeSave {
    private fun key(name: String, zh: Boolean) = "practice.$name.${if (zh) "zh" else "tw"}"

    fun save(name: String, zh: Boolean, scope: Int, v: Map<String, Any?>) {
        val box = mapOf("t" to System.currentTimeMillis() / 1000.0, "scope" to scope, "v" to v)
        Prefs.sp.edit().putString(key(name, zh), JWriter.any(box)).apply()
    }

    @Suppress("UNCHECKED_CAST")
    fun load(name: String, zh: Boolean, scope: Int): Map<String, Any?>? {
        val s = Prefs.sp.getString(key(name, zh), null) ?: return null
        val b = try { JReader(s).any() as? Map<String, Any?> } catch (_: Exception) { null } ?: return null
        val t = (b["t"] as? Number)?.toDouble() ?: 0.0
        if ((b["scope"] as? Number)?.toInt() != scope || System.currentTimeMillis() / 1000.0 - t > 14 * 86400) { clear(name, zh); return null }
        return b["v"] as? Map<String, Any?>
    }

    fun clear(name: String, zh: Boolean) { Prefs.sp.edit().remove(key(name, zh)).apply() }

    // reading a saved value
    @Suppress("UNCHECKED_CAST")
    fun strings(v: Any?): List<String> = (v as? List<Any?>)?.filterIsInstance<String>() ?: emptyList()
    fun int(v: Any?): Int = (v as? Number)?.toInt() ?: 0
}

/** "接著上次的練習" for a moment at the top, after a practice has been picked up again */
@Composable
fun ResumedNote(shown: Boolean, onGone: () -> Unit) {
    if (!shown) return
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(2500); onGone() }
    Txt("接著上次的練習", ff(FF.Footnote, FontWeight.SemiBold), T.greenInk,
        Modifier.clip(RoundedCornerShape(50)).background(T.green).border(1.5.dp, T.greenEdge, RoundedCornerShape(50))
            .padding(horizontal = 12.dp, vertical = 5.dp))
}

// MARK: - 楷體 and how closely the writing follows it

private object Kai {
    private var face: Typeface? = null
    fun typeface(ctx: android.content.Context): Typeface {
        face?.let { return it }
        val f = try { androidx.core.content.res.ResourcesCompat.getFont(ctx, R.font.lxgw_wenkai_tc) } catch (_: Exception) { null } ?: Typeface.DEFAULT
        face = f
        return f
    }
    val family = FontFamily(Font(R.font.lxgw_wenkai_tc))

    /** where the character goes in a square of this side (centred on its own shape) */
    fun place(ch: String, side: Float, paint: Paint): Pair<Float, Float> {
        paint.textSize = side * 0.8f
        val b = Rect()
        paint.getTextBounds(ch, 0, ch.length, b)
        return Pair((side - b.width()) / 2f - b.left, (side - b.height()) / 2f - b.top)
    }

    const val N = 64

    /** which cells of an n × n grid the character covers */
    fun target(ch: String, ctx: android.content.Context): BooleanArray {
        val bmp = Bitmap.createBitmap(N, N, Bitmap.Config.ARGB_8888)
        val c = android.graphics.Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = typeface(ctx); color = android.graphics.Color.WHITE }
        val (x, y) = place(ch, N.toFloat(), p)
        c.drawText(ch, x, y, p)
        return cells(bmp)
    }

    fun cells(bmp: Bitmap): BooleanArray {
        val px = IntArray(N * N)
        bmp.getPixels(px, 0, N, 0, 0, N, N)
        return BooleanArray(N * N) { (px[it] ushr 24) > 50 }
    }

    fun widen(g: BooleanArray, r: Int): BooleanArray {
        val out = g.copyOf()
        for (y in 0 until N) for (x in 0 until N) if (g[y * N + x]) {
            for (dy in -r..r) for (dx in -r..r) {
                val yy = y + dy; val xx = x + dx
                if (yy in 0 until N && xx in 0 until N) out[yy * N + xx] = true
            }
        }
        return out
    }

    /** 0–1: how much of the character is covered, and how much of the writing is on the character */
    fun score(target: BooleanArray, strokes: List<InkStroke>, side: Float): Double {
        if (side <= 0 || strokes.isEmpty() || target.size != N * N) return 0.0
        val bmp = Bitmap.createBitmap(N, N, Bitmap.Config.ARGB_8888)
        val c = android.graphics.Canvas(bmp)
        val k = N / side
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.WHITE; style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
        }
        for (s in strokes) {
            if (s.pts.size == 1) { p.strokeWidth = s.ws[0] * k; c.drawPoint(s.pts[0].x * k, s.pts[0].y * k, p); continue }
            for (i in 1 until s.pts.size) {
                p.strokeWidth = (s.ws[i - 1] + s.ws[i]) / 2 * k
                c.drawLine(s.pts[i - 1].x * k, s.pts[i - 1].y * k, s.pts[i].x * k, s.pts[i].y * k, p)
            }
        }
        val ink = cells(bmp)
        val wideInk = widen(ink, 2); val wideTarget = widen(target, 2)
        var t = 0; var covered = 0; var i = 0; var on = 0
        for (q in 0 until N * N) {
            if (target[q]) { t++; if (wideInk[q]) covered++ }
            if (ink[q]) { i++; if (wideTarget[q]) on++ }
        }
        if (t == 0 || i == 0) return 0.0
        val recall = covered.toDouble() / t; val precision = on.toDouble() / i
        return if (recall + precision > 0) 2 * recall * precision / (recall + precision) else 0.0
    }
}

/** one stroke of the writing: its points and how thick it is at each (from the stylus's pressure) */
class InkStroke(val pts: List<Offset>, val ws: List<Float>) {
    operator fun plus(x: Pair<Offset, Float>) = InkStroke(pts + x.first, ws + x.second)
}

/** the ink of 手寫練習: always the dark ink of the original theme, or (彩色) the app's rainbow along the strokes */
object HandInk {
    val dark = Color(0xFF1A1A1C)
    /** red, orange, yellow, green, teal, blue, purple, pink (the standard tone colours) */
    val rainbow: List<Color> = listOf(1, 2, 3, 4, 5, 6, 7, 0).map { Color(ToneColors.palette[it].second[2]) }
    /** the rainbow colour at a distance along the writing (one round every `period`) */
    fun color(d: Float, period: Float): Color {
        val n = rainbow.size
        val x = ((d / period) % 1f) * n
        val i = x.toInt() % n; val j = (i + 1) % n
        return androidx.compose.ui.graphics.lerp(rainbow[i], rainbow[j], x - kotlin.math.floor(x))
    }
    /** how thick at a pressure: sensitivity 0 = always the same, 1.5 = very sensitive (only a stylus presses) */
    fun width(base: Float, pressure: Float, stylus: Boolean, sensitivity: Float): Float {
        if (!stylus || pressure <= 0.01f) return base
        val f = (pressure / 0.5f).coerceIn(0.15f, 2.6f)
        return base * (1 + sensitivity * (f - 1)).coerceIn(0.25f, 2.6f)
    }
}

// MARK: - the practice

@Composable
fun HandwritingScreen(onClose: () -> Unit) {
    var list by remember { mutableStateOf<List<String>?>(null) }
    var idx by remember { mutableIntStateOf(0) }
    var resumed by remember { mutableStateOf(false) }
    fun save() {
        val l = list
        if (l == null || idx >= l.size) PracticeSave.clear("handwriting", true)
        else PracticeSave.save("handwriting", true, 0, mapOf("chars" to l, "idx" to idx))
    }
    LaunchedEffect(Unit) {
        val s = PracticeSave.load("handwriting", true, 0) ?: return@LaunchedEffect
        val cs = PracticeSave.strings(s["chars"]); val i = PracticeSave.int(s["idx"])
        if (cs.isNotEmpty() && i < cs.size) { list = cs; idx = i; resumed = true }
    }
    LaunchedEffect(idx, list) { if (list != null) save() }
    Column(Modifier.fillMaxSize()) {
        TopBar("手寫練習", onClose, close = true, settings = false) {
            if (list != null) TextButton(onClick = { PracticeSave.clear("handwriting", true); list = null }) {
                Icon(Icons.Filled.GridView, null, tint = T.greenInk, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(4.dp)); Text("選字", color = T.greenInk)
            }
        }
        Box(Modifier.fillMaxSize()) {
            val l = list
            if (l == null) HandwritingSetup { chars -> idx = 0; list = chars }
            else HandwritingPad(l, idx, { idx = it }) { PracticeSave.clear("handwriting", true); onClose() }
            Box(Modifier.fillMaxWidth().padding(top = 4.dp), contentAlignment = Alignment.TopCenter) { ResumedNote(resumed) { resumed = false } }
        }
    }
}

/** choosing what to write: a list, then the characters of it (all of them to start with) */
@Composable
private fun HandwritingSetup(start: (List<String>) -> Unit) {
    var listID by Prefs.handList
    var shuffle by Prefs.handShuffle
    var own by Prefs.handOwn
    val off = remember { mutableStateListOf<String>() }
    class Source(val id: String, val name: String, val chars: List<String>)
    val sets = Store.zhCharSets()
    val sources = buildList {
        add(Source("unknown", "不熟的漢字", sets.all.filter { sets.unknown.contains(it) }))
        for (t in Store.topics) if (t.id > Lang.charTopicBase) add(Source("level${t.id}", t.name, Store.levelCards(t.id).mapNotNull { Lang.charOf(it.k) }))
        add(Source("known", "認識的漢字", sets.all.filter { sets.known.contains(it) }))
        add(Source("own", "自己選的字", own.cps().filter { Zhuyin.isHan(it.firstCp()) }.distinct()))
    }
    val src = sources.firstOrNull { it.id == listID } ?: sources[0]
    val picked = src.chars.filter { it !in off }
    var menu by remember { mutableStateOf(false) }
    LazyVerticalGrid(GridCells.Adaptive(48.dp), Modifier.fillMaxSize().widthIn(max = 640.dp), contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                // start first, at the top (the list of characters can be long)
                ProminentButton(onClick = { start(if (shuffle) picked.shuffled() else picked) }, Modifier.fillMaxWidth(), enabled = picked.isNotEmpty()) {
                    IconLabel(Icons.Filled.Edit, "開始寫（${picked.size} 個字）")
                }
                Row(Modifier.fillMaxWidth().clickable { shuffle = !shuffle }, verticalAlignment = Alignment.CenterVertically) {
                    Txt("打亂順序", ff(FF.Body), modifier = Modifier.weight(1f))
                    Switch(shuffle, { shuffle = it }, colors = SwitchDefaults.colors(checkedTrackColor = T.greenEdge, checkedThumbColor = T.greenInk))
                }
                Box {
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.7f)).border(1.dp, T.fnEdge, RoundedCornerShape(12.dp))
                        .clickable { menu = true }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Txt("要寫的字", ff(FF.Body), T.muted, Modifier.weight(1f))
                        Txt(if (src.id == "own") src.name else "${src.name}（${src.chars.size}）", ff(FF.Body), T.greenInk)
                        Icon(Icons.Filled.UnfoldMore, null, tint = T.muted, modifier = Modifier.size(18.dp))
                    }
                    DropdownMenu(menu, { menu = false }, containerColor = T.fn) {
                        for (s in sources) DropdownMenuItem(text = { Text(if (s.id == "own") s.name else "${s.name}（${s.chars.size}）", color = if (s.id == src.id) T.greenInk else T.glyph) },
                            onClick = { listID = s.id; off.clear(); menu = false })
                    }
                }
                if (src.id == "own") SearchField(own, { own = it }, "打你要寫的字，例如：龍鳳書寫")
                if (src.chars.isEmpty()) Txt(if (src.id == "unknown") "還沒有不熟的漢字。" else if (src.id == "own") "在上面打字。" else "這裡沒有字。", ff(FF.Footnote), T.muted)
                else Row(verticalAlignment = Alignment.CenterVertically) {
                    Txt("點字可以不選它。選了 ${picked.size}／${src.chars.size} 個", ff(FF.Footnote), T.muted, Modifier.weight(1f))
                    TextButton(onClick = { off.clear() }) { Text("全選", color = T.greenInk) }
                    TextButton(onClick = { off.clear(); off.addAll(src.chars) }) { Text("全不選", color = T.greenInk) }
                }
            }
        }
        items(src.chars, key = { "hw|$it" }) { ch ->
            val on = ch !in off
            Box(Modifier.size(48.dp).clip(RoundedCornerShape(10.dp)).background(if (on) T.blue.copy(alpha = 0.6f) else T.fn.copy(alpha = 0.4f))
                .border(1.dp, if (on) T.blueEdge else T.fnEdge, RoundedCornerShape(10.dp))
                .clickable { if (on) off.add(ch) else off.remove(ch) }, contentAlignment = Alignment.Center) {
                Txt(ch, sz(24f), if (on) T.blueInk else T.muted.copy(alpha = 0.5f))
            }
        }
    }
}

/** writing the characters one by one */
@Composable
private fun HandwritingPad(chars: List<String>, idx: Int, setIdx: (Int) -> Unit, finished: () -> Unit) {
    val ctx = LocalContext.current
    val ch = chars[idx.coerceIn(0, chars.size - 1)]
    var trace by Prefs.handTrace
    val strokes = remember { mutableStateListOf<InkStroke>() }
    val rainbow = Prefs.handRainbow.value
    val sensitivity = Prefs.handPressure.value
    var side by remember { mutableFloatStateOf(0f) }
    val target = remember(ch) { Kai.target(ch, ctx) }
    val penWidth = with(androidx.compose.ui.platform.LocalDensity.current) { 14.dp.toPx() }
    val score = if (trace) Kai.score(target, strokes.toList(), side) else 0.0
    LaunchedEffect(ch) { strokes.clear() }
    // what the character is like: reading, meaning
    val card = Store.cardFor(Lang.charKey(ch))
    val z = Store.zh
    val entry = if (card == null) z?.entryForChar(ch, "") else null
    val reading = card?.let { Store.cardRom(it, 0, -1).annotated() } ?: entry?.let { z!!.reading(it.syl(Prefs.zhPlace.value), Prefs.zhRom.value).annotated() }
    val defs = card?.d?.take(2)?.map { it.p to it.t } ?: entry?.senses?.take(2)?.map { "" to it.text } ?: emptyList()
    var padSize by Prefs.handPad
    // the biggest square that leaves room for everything else on this screen
    BoxWithConstraints(Modifier.fillMaxSize()) {
    // a tablet: the words with the character beside the square, to learn it in context
    val wide = maxWidth >= 800.dp
    val sideW = 330f
    val maxPad = maxOf(200f, minOf(maxWidth.value - 32f - (if (wide) sideW + 16f else 0f), maxHeight.value - (if (trace) 360f else 320f)))
    val padSide = padSize.coerceIn(180f, maxOf(181f, maxPad))
    LaunchedEffect(padSide) { strokes.clear() }      // (the old writing wouldn't fit the new size)
    Row(Modifier.fillMaxSize()) {
    if (wide) CharWordsPanel(ch, Modifier.width(sideW.dp).fillMaxHeight().padding(start = 16.dp, top = 16.dp, bottom = 16.dp))
    Column(Modifier.weight(1f).fillMaxHeight().widthIn(max = maxOf(640f, padSide + 32f).dp).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.weight(1f)) { PotionBar((idx + 1).toDouble() / chars.size, 20.dp, showMarks = false, label = "手寫進度") }
            Txt("${idx + 1}／${chars.size}", lat(14f), T.muted)
            Row(Modifier.clip(RoundedCornerShape(50)).background(if (trace) T.green else T.fn).border(1.5.dp, if (trace) T.greenEdge else T.fnEdge, RoundedCornerShape(50))
                .clickable { trace = !trace }.padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.TextFields, null, tint = if (trace) T.greenInk else T.muted, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(4.dp))
                Txt("描字", ff(FF.Footnote, FontWeight.SemiBold), if (trace) T.greenInk else T.muted)
            }
            // 彩色: the writing in the rainbow instead of the dark ink
            Row(Modifier.clip(RoundedCornerShape(50)).background(if (rainbow) T.green else T.fn).border(1.5.dp, if (rainbow) T.greenEdge else T.fnEdge, RoundedCornerShape(50))
                .clickable { Prefs.handRainbow.value = !rainbow }.padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Palette, null, tint = if (rainbow) T.greenInk else T.muted, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(4.dp))
                Txt("彩色", ff(FF.Footnote, FontWeight.SemiBold), if (rainbow) T.greenInk else T.muted)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            // tap: the words with this character (to learn it in context); on a tablet they're beside the square
            if (wide) Text(ch, style = sz(64f, FontWeight.Medium).copy(fontFamily = Kai.family), color = T.blueInk)
            else Column(Modifier.clip(RoundedCornerShape(12.dp)).clickable { UI.open(Sheet.CharWords(ch)) }.padding(horizontal = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally) {
                Text(ch, style = sz(64f, FontWeight.Medium).copy(fontFamily = Kai.family), color = T.blueInk)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Search, null, tint = T.muted, modifier = Modifier.size(12.dp)); Spacer(Modifier.width(2.dp))
                    Txt("看詞", ff(FF.Caption2, FontWeight.SemiBold), T.muted)
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (reading != null) Txt(reading, lat(24f), T.greenInk)
                for ((n, d) in defs.withIndex()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (defs.size > 1) NumBadge(n + 1)
                    if (d.first.isNotEmpty()) Chip(d.first)
                    Txt(d.second, ff(FF.Subheadline), T.glyph, maxLines = 2)
                }
            }
            PlayButton("tts:$ch", 40.dp)
        }
        // the grid to write in (米字格), the faint character to trace, and the writing
        val glyph = T.glyph; val edge = T.fnEdge
        val period = with(androidx.compose.ui.platform.LocalDensity.current) { 420.dp.toPx() }
        Box(Modifier.size(padSide.dp).clip(RoundedCornerShape(18.dp)).background(T.fn.copy(alpha = 0.75f))
            .border(1.5.dp, T.fnEdge, RoundedCornerShape(18.dp))) {
            Canvas(Modifier.fillMaxSize()
                .onSizeChanged { side = it.width.toFloat() }
                .pointerInput(ch, sensitivity) {
                    // each touch is a stroke; a stylus's pressure makes it thicker or thinner
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        val stylus = down.type == PointerType.Stylus
                        down.consume()
                        strokes.add(InkStroke(listOf(down.position), listOf(HandInk.width(penWidth, down.pressure, stylus, sensitivity))))
                        while (true) {
                            val e = awaitPointerEvent()
                            val c = e.changes.firstOrNull { it.id == down.id } ?: break
                            if (!c.pressed) break
                            c.consume()
                            if (strokes.isNotEmpty()) strokes[strokes.size - 1] = strokes.last() + (c.position to HandInk.width(penWidth, c.pressure, stylus, sensitivity))
                        }
                    }
                }) {
                val w = size.width; val h = size.height
                val dash = PathEffect.dashPathEffect(floatArrayOf(6 * density, 6 * density))
                drawLine(edge, Offset(w / 2, 0f), Offset(w / 2, h), 1 * density, pathEffect = dash)
                drawLine(edge, Offset(0f, h / 2), Offset(w, h / 2), 1 * density, pathEffect = dash)
                drawLine(edge, Offset(0f, 0f), Offset(w, h), 1 * density, pathEffect = dash)
                drawLine(edge, Offset(w, 0f), Offset(0f, h), 1 * density, pathEffect = dash)
                if (trace) drawIntoCanvas { c ->
                    // the same placing as the measuring
                    val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Kai.typeface(ctx); color = glyph.copy(alpha = 0.16f).argbInt() }
                    val (x, y) = Kai.place(ch, w, p)
                    c.nativeCanvas.drawText(ch, x, y, p)
                }
                // the writing: the dark ink, or (彩色) the rainbow along the whole writing
                var dist = 0f
                for (s in strokes) {
                    if (s.pts.size == 1) { drawCircle(if (rainbow) HandInk.color(dist, period) else HandInk.dark, s.ws[0] / 2, s.pts[0]); continue }
                    for (i in 1 until s.pts.size) {
                        val a = s.pts[i - 1]; val b = s.pts[i]
                        val len = (b - a).getDistance()
                        drawLine(if (rainbow) HandInk.color(dist + len / 2, period) else HandInk.dark, a, b,
                            (s.ws[i - 1] + s.ws[i]) / 2, cap = StrokeCap.Round)
                        dist += len
                    }
                }
            }
        }
        if (trace) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Txt("描得像", ff(FF.Footnote, FontWeight.SemiBold), T.muted)
            Box(Modifier.weight(1f)) { PotionBar(score, 22.dp, showMarks = false, label = "描得像") }
            Txt(if (strokes.isEmpty()) "—" else "${Math.round(score * 100)}%", lat(15f), T.glyph)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SoftButton(onClick = { setIdx(maxOf(0, idx - 1)) }, Modifier.weight(1f), enabled = idx > 0) { IconLabel(Icons.Filled.ChevronLeft, "上一個", ff(FF.Subheadline)) }
            SoftButton(onClick = { strokes.clear() }, Modifier.weight(1f)) { IconLabel(Icons.Filled.Clear, "清掉", ff(FF.Subheadline)) }
            ProminentButton(onClick = { if (idx + 1 >= chars.size) finished() else setIdx(idx + 1) }, Modifier.weight(1f)) {
                IconLabel(Icons.Filled.ChevronRight, if (idx + 1 >= chars.size) "完成" else "下一個", ff(FF.Subheadline))
            }
        }
        // 格子大小: the writing square, bigger or smaller (the shadow follows)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Filled.ZoomOut, "小一點", tint = T.muted, modifier = Modifier.size(20.dp))
            Slider(padSide, { padSize = it }, Modifier.weight(1f), valueRange = 180f..maxOf(181f, maxPad),
                colors = SliderDefaults.colors(thumbColor = T.greenInk, activeTrackColor = T.greenEdge))
            Icon(Icons.Filled.ZoomIn, "大一點", tint = T.muted, modifier = Modifier.size(20.dp))
        }
    }
    }
    }
}


// MARK: - the words with a character

/** 手寫練習 on a phone: tap the character at the top for the words with it */
@Composable
fun CharWordsSheetRoot(ch: String) {
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { UI.closeSheet() }) { Text("完成", color = T.greenInk) }
            Spacer(Modifier.weight(1f))
            Txt("有「$ch」的詞", ff(FF.Headline, FontWeight.SemiBold), T.glyph)
            Spacer(Modifier.weight(1f))
            BarButtons(settings = false)
        }
        CharWordsList(ch, Modifier.fillMaxSize())
    }
}

/** 手寫練習 on a tablet: the words with the character, beside the square */
@Composable
private fun CharWordsPanel(ch: String, modifier: Modifier) {
    Column(modifier.clip(RoundedCornerShape(18.dp)).background(T.fn.copy(alpha = 0.35f)).border(1.dp, T.fnEdge, RoundedCornerShape(18.dp))) {
        Txt("有「$ch」的詞", ff(FF.Headline, FontWeight.SemiBold), T.glyph, Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp))
        CharWordsList(ch, Modifier.fillMaxSize())
    }
}

/** the words with a character, so it can be learned in context, each with 1–2 meanings (in 華語 or English, as
 *  設定 → 主要解釋 says). 華語: the dictionary's words, the ones on the word lists (HSK / TOCFL) first, the easier
 *  levels first. 台語: the cards' words, in the word list's order. Tap one to open it. */
@Composable
private fun CharWordsList(ch: String, modifier: Modifier) {
    val z = if (Store.isZh) Store.zh else null
    Store.rev
    var zhList by remember(ch, z) { mutableStateOf<List<Int>?>(null) }
    LaunchedEffect(ch, z) {
        if (z == null) return@LaunchedEffect
        zhList = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            val listed = ArrayList<Pair<Int, Int>>(); val other = ArrayList<Int>(); val seen = HashSet<String>()
            for ((i, e) in z.entries.withIndex()) {
                if (e.h == ch || e.h.length < 2 || !e.h.contains(ch) || !seen.add(e.h)) continue
                val lv = listOf(e.hsk, e.tocfl).filter { it > 0 }.minOrNull() ?: 0
                if (lv > 0) listed.add(lv to i) else if (other.size < 150) other.add(i)
            }
            listed.sortedWith(compareBy({ it.first }, { it.second })).map { it.second } + other
        }
    }
    val cardWords = remember(ch, z, Store.cards) {
        if (z != null) emptyList() else Store.cards.filter { Lang.charOf(it.k) == null && it.h.length > 1 && it.h.contains(ch) }
    }
    @Composable
    fun rowBox(n: Int, size: Int, onClick: () -> Unit, content: @Composable () -> Unit) {
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(
            topStart = if (n == 0) 14.dp else 0.dp, topEnd = if (n == 0) 14.dp else 0.dp,
            bottomStart = if (n == size - 1) 14.dp else 0.dp, bottomEnd = if (n == size - 1) 14.dp else 0.dp))
            .background(T.fn.copy(alpha = 0.7f)).clickable(onClick = onClick)) {
            if (n > 0) HorizontalDivider(color = T.fnEdge)
            content()
        }
    }
    LazyColumn(modifier, contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 60.dp)) {
        if (z != null) {
            // the character itself
            val ce = z.entryForChar(ch, "")
            if (ce != null) item(key = "char") {
                ListCard(Modifier.padding(top = 8.dp)) {
                    Row(Modifier.fillMaxWidth().clickable { UI.open(Sheet.ZhWord(ce.k)) }.padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.MenuBook, null, tint = T.oliveInk, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(8.dp))
                        Txt("「$ch」這個字", ff(FF.Body), T.glyph, Modifier.weight(1f))
                        Icon(Icons.Filled.ChevronRight, null, tint = T.muted)
                    }
                }
            }
            val l = zhList
            if (l == null) item(key = "wait") {
                Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = T.greenInk) }
            } else {
                item(key = "title") { SectionTitle(if (l.isEmpty()) "沒有找到有這個字的詞" else "有「$ch」的詞（${l.size}）") }
                itemsIndexed(l, key = { _, i -> "w|$i" }) { n, i ->
                    val e = z.entries[i]
                    rowBox(n, l.size, { UI.open(Sheet.ZhWord(e.k)) }) { ZhWordRow(z, e, meanings = 2) }
                }
            }
        } else {
            item(key = "title") { SectionTitle(if (cardWords.isEmpty()) "沒有找到有這個字的詞" else "有「$ch」的詞（${cardWords.size}）") }
            itemsIndexed(cardWords, key = { _, c -> "c|${c.k}" }) { n, c ->
                rowBox(n, cardWords.size, { UI.open(Sheet.CardSheet(c)) }) { CharWordCardRow(c) }
            }
        }
    }
}

/** a 台語 word card with its reading and 1–2 meanings */
@Composable
private fun CharWordCardRow(c: Card) {
    val rom = Prefs.rom.value; val place = Prefs.place.value
    val tk = textKey()
    Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Txt(c.h, sz(20f, FontWeight.SemiBold), T.blueInk)
            Txt(remember(c.k, tk, rom, place) { Store.cardRom(c, rom, place).annotated() }, lat(16f), T.greenInk, maxLines = 1)
        }
        val ds = c.d.take(2)
        for ((i, d) in ds.withIndex()) Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            if (ds.size > 1) Txt("${i + 1}.", ff(FF.Caption, FontWeight.Bold), T.muted)
            Txt(d.t, ff(FF.Footnote), T.muted, maxLines = 2)
        }
    }
}
