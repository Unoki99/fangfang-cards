package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
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
    Txt(tr("接著上次的練習"), ff(FF.Footnote, FontWeight.SemiBold), T.btnInk,
        Modifier.clip(RoundedCornerShape(50)).background(T.btn).border(1.5.dp, T.btnEdge, RoundedCornerShape(50))
            .padding(horizontal = 12.dp, vertical = 5.dp))
}

// MARK: - 楷體 and how closely the writing follows it

object Kai {
    /** the fonts to choose from (設定 or the 字體 button in 手寫練習); what one doesn't have comes from the system's font */
    val names: List<String> get() = listOf(tr("文楷"), tr("芫荽"))
    // 霞鶩文楷 TC; 芫荽 Iansui (Taiwan's way of writing, for learning) — both SIL OFL
    private val files = listOf(R.font.lxgw_wenkai_tc, R.font.iansui)
    private val faces = HashMap<Int, Typeface>()
    private val families = HashMap<Int, FontFamily>()
    val style: Int get() = Prefs.handFont.value.coerceIn(0, files.size - 1)
    fun typeface(ctx: android.content.Context): Typeface {
        val s = style
        faces[s]?.let { return it }
        val f = try { androidx.core.content.res.ResourcesCompat.getFont(ctx, files[s]) } catch (_: Exception) { null } ?: Typeface.DEFAULT
        faces[s] = f
        return f
    }
    val family: FontFamily get() = families.getOrPut(style) { FontFamily(Font(files[style])) }

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
/** a stroke: its points, the thickness at each, and when each was written (uptime ms, for 筆跡延遲) */
class InkStroke(val pts: List<Offset>, val ws: List<Float>, val ts: List<Long> = emptyList()) {
    fun add(p: Offset, w: Float, t: Long) = InkStroke(pts + p, ws + w, ts + t)
}

/** the ink of 手寫練習: always the dark ink of the original theme, or (彩色) the app's rainbow along the strokes */
object HandInk {
    val dark = Color(0xFF1A1A1C)
    /** the ink when it isn't the rainbow: the colour picked (0xRRGGBB), or the dark ink */
    val solid: Color get() = Prefs.handInk.value.let { if (it > 0) Color(0xFF000000L or it.toLong()) else dark }
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
fun HandwritingScreen(only: List<String>? = null, onClose: () -> Unit) {
    // only: from a side card, just these characters (not saved, no 選字)
    var list by remember { mutableStateOf<List<String>?>(only) }
    var idx by remember { mutableIntStateOf(0) }
    var resumed by remember { mutableStateOf(false) }
    fun save() {
        val l = list
        if (l == null || idx >= l.size) PracticeSave.clear("handwriting", Store.isZh)
        else PracticeSave.save("handwriting", Store.isZh, 0, mapOf("chars" to l, "idx" to idx))
    }
    LaunchedEffect(Unit) {
        if (only != null) return@LaunchedEffect
        val s = PracticeSave.load("handwriting", Store.isZh, 0) ?: return@LaunchedEffect
        val cs = PracticeSave.strings(s["chars"]); val i = PracticeSave.int(s["idx"])
        if (cs.isNotEmpty() && i < cs.size) { list = cs; idx = i; resumed = true }
    }
    LaunchedEffect(idx, list) { if (list != null && only == null) save() }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("手寫練習"), onClose, close = true, settings = false) {
            if (list != null && only == null) TextButton(onClick = { PracticeSave.clear("handwriting", Store.isZh); list = null }) {
                Icon(Icons.Filled.GridView, null, tint = T.btnInk, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(4.dp)); Text(tr("選字"), color = T.btnInk)
            }
            // 中 / 英 (華語's meanings), standing up next to the spelling / 腔口 buttons
            if (list != null && Store.isZh) { Spacer(Modifier.width(4.dp)); MeaningSwitch(vertical = true) }
        }
        Box(Modifier.fillMaxSize()) {
            val l = list
            if (l == null) HandwritingSetup { chars -> idx = 0; list = chars }
            else HandwritingPad(l, idx, { idx = it }) { PracticeSave.clear("handwriting", Store.isZh); onClose() }
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
    val sources = if (!Store.isZh) {
        // 台語: the characters of your 不熟 / 熟悉 words
        val tw = twCharSets()
        listOf(Source("unknown", tr("不熟的詞的字"), tw.first), Source("known", tr("熟悉的詞的字"), tw.second),
            Source("own", tr("自己選的字"), own.cps().filter { Zhuyin.isHan(it.firstCp()) }.distinct()))
    } else buildList {
        val sets = Store.zhCharSets()
        add(Source("unknown", tr("不熟的漢字"), sets.all.filter { sets.unknown.contains(it) }))
        for (t in Store.topics) if (t.id > Lang.charTopicBase) add(Source("level${t.id}", t.name, Store.levelCards(t.id).mapNotNull { Lang.charOf(it.k) }))
        add(Source("known", tr("認識的漢字"), sets.all.filter { sets.known.contains(it) }))
        add(Source("own", tr("自己選的字"), own.cps().filter { Zhuyin.isHan(it.firstCp()) }.distinct()))
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
                    IconLabel(Icons.Filled.Edit, tr("開始寫（{0} 個字）", picked.size))
                }
                Row(Modifier.fillMaxWidth().clickable { shuffle = !shuffle }, verticalAlignment = Alignment.CenterVertically) {
                    Txt(tr("打亂順序"), ff(FF.Body), modifier = Modifier.weight(1f))
                    Switch(shuffle, { shuffle = it }, colors = SwitchDefaults.colors(checkedTrackColor = T.btnEdge, checkedThumbColor = T.btnInk))
                }
                Box {
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.7f)).border(1.dp, T.fnEdge, RoundedCornerShape(12.dp))
                        .clickable { menu = true }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Txt(tr("要寫的字"), ff(FF.Body), T.muted, Modifier.weight(1f))
                        Txt(if (src.id == "own") src.name else "${src.name}（${src.chars.size}）", ff(FF.Body), T.greenInk)
                        Icon(Icons.Filled.UnfoldMore, null, tint = T.muted, modifier = Modifier.size(18.dp))
                    }
                    DropdownMenu(menu, { menu = false }, containerColor = T.fn) {
                        for (s in sources) DropdownMenuItem(text = { Text(if (s.id == "own") s.name else "${s.name}（${s.chars.size}）", color = if (s.id == src.id) T.greenInk else T.glyph) },
                            onClick = { listID = s.id; off.clear(); menu = false })
                    }
                }
                if (src.id == "own") SearchField(own, { own = it }, tr("打你要寫的字，例如：龍鳳書寫"))
                if (src.chars.isEmpty()) Txt(if (src.id == "unknown") tr("還沒有不熟的漢字。") else if (src.id == "own") tr("在上面打字。") else tr("這裡沒有字。"), ff(FF.Footnote), T.muted)
                else Row(verticalAlignment = Alignment.CenterVertically) {
                    Txt(tr("點字可以不選它。選了 {0}／{1} 個", picked.size, src.chars.size), ff(FF.Footnote), T.muted, Modifier.weight(1f))
                    TextButton(onClick = { off.clear() }) { Text(tr("全選"), color = T.btnInk) }
                    TextButton(onClick = { off.clear(); off.addAll(src.chars) }) { Text(tr("全不選"), color = T.btnInk) }
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
    val fontStyle = Prefs.handFont.value
    val target = remember(ch, fontStyle) { Kai.target(ch, ctx) }
    val penWidth = with(androidx.compose.ui.platform.LocalDensity.current) { Prefs.handWidth.value.dp.toPx() }
    // 筆跡延遲: the writing shows up a moment after the pen (redrawn every frame while it's on)
    val delayMs = (Prefs.handDelay.value * 1000).toLong()
    val inkColor = HandInk.solid
    var frameNow by remember { mutableLongStateOf(0L) }
    LaunchedEffect(delayMs) {
        if (delayMs > 0) while (true) { withFrameMillis { }; frameNow = android.os.SystemClock.uptimeMillis() }
    }
    val score = if (trace) Kai.score(target, strokes.toList(), side) else 0.0
    LaunchedEffect(ch) { strokes.clear() }
    // what the character is like: reading, meaning
    // 華語: the character card; 台語: the character's own word (the one given from a side card, or the most common)
    val card = charCardFor(ch)
    val z = if (Store.isZh) Store.zh else null
    val entry = if (card == null) z?.entryForChar(ch, "") else null
    val reading = card?.let { (if (Store.isZh) Store.cardRom(it, 0, -1) else Store.cardRom(it, Prefs.rom.value, Prefs.place.value)).annotated() } ?: entry?.let { z!!.reading(it.syl(Prefs.zhPlace.value), Prefs.zhRom.value).annotated() }
    // 華語: the meanings in 華語 or English (the same switch as 設定 → 主要解釋, so the words follow it too)
    val english = Prefs.zhEnglish.value && Store.isZh
    val enDefs = if (english) z?.entryForChar(ch, "")?.takeIf { it.en != null }?.enList?.take(2)?.map { "" to it } else null
    val defs = enDefs ?: card?.d?.take(2)?.map { it.p to it.t } ?: entry?.senses?.take(2)?.map { "" to it.text } ?: emptyList()
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
            Box(Modifier.weight(1f)) { PotionBar((idx + 1).toDouble() / chars.size, 20.dp, showMarks = false, label = tr("手寫進度")) }
            Txt(tr("{0}／{1}", idx + 1, chars.size), lat(14f), T.muted)
            Row(Modifier.clip(RoundedCornerShape(50)).background(if (trace) T.btn else T.fn).border(1.5.dp, if (trace) T.btnEdge else T.fnEdge, RoundedCornerShape(50))
                .clickable { trace = !trace }.padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.TextFields, null, tint = if (trace) T.btnInk else T.muted, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(4.dp))
                Txt(tr("描字"), ff(FF.Footnote, FontWeight.SemiBold), if (trace) T.btnInk else T.muted)
            }
            // 字體: 文楷 or 芫荽 (the character at the top and the one to trace)
            Box {
                var fontMenu by remember { mutableStateOf(false) }
                Row(Modifier.clip(RoundedCornerShape(50)).background(T.fn).border(1.5.dp, T.fnEdge, RoundedCornerShape(50))
                    .clickable { fontMenu = true }.padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                    Txt(Kai.names[Kai.style], ff(FF.Footnote, FontWeight.SemiBold), T.muted)
                    Icon(Icons.Filled.ArrowDropDown, null, tint = T.muted, modifier = Modifier.size(16.dp))
                }
                DropdownMenu(fontMenu, { fontMenu = false }, containerColor = T.fn) {
                    for ((i, n) in Kai.names.withIndex()) DropdownMenuItem(
                        text = { Txt(n, ff(FF.Body), if (i == fontStyle) T.greenInk else T.glyph) },
                        leadingIcon = { if (i == fontStyle) Icon(Icons.Filled.Check, null, tint = T.greenInk) else Spacer(Modifier.size(24.dp)) },
                        onClick = { Prefs.handFont.value = i; fontMenu = false })
                }
            }
            // 筆: how thick, how much a stylus's pressure changes it
            Box {
                var penMenu by remember { mutableStateOf(false) }
                Row(Modifier.clip(RoundedCornerShape(50)).background(T.fn).border(1.5.dp, T.fnEdge, RoundedCornerShape(50))
                    .clickable { penMenu = true }.padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Edit, null, tint = T.muted, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(4.dp))
                    Txt(tr("筆"), ff(FF.Footnote, FontWeight.SemiBold), T.muted)
                }
                DropdownMenu(penMenu, { penMenu = false }, containerColor = T.fn) {
                    Column(Modifier.width(300.dp).padding(horizontal = 16.dp, vertical = 8.dp)) { PenControls() }
                }
            }
            // 顏色: the dark ink, the rainbow (a new colour along the writing) or a colour of its own
            Box {
                var colorMenu by remember { mutableStateOf(false) }
                Box(Modifier.clip(RoundedCornerShape(50)).background(T.fn).border(1.5.dp, T.fnEdge, RoundedCornerShape(50))
                    .clickable { colorMenu = true }.padding(horizontal = 10.dp, vertical = 5.dp)) { InkSwatch(18.dp) }
                DropdownMenu(colorMenu, { colorMenu = false }, containerColor = T.fn) {
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) { InkColorControls() }
                }
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
                    Txt(tr("看詞"), ff(FF.Caption2, FontWeight.SemiBold), T.muted)
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
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                PlayButton("tts:$ch", 40.dp)
                // 我會了: the character is known (its card 熟悉); tap again: 不熟
                if (card != null) KnowCharButton(card)
            }
        }
        // the grid to write in (米字格), the faint character to trace, and the writing
        val glyph = T.glyph; val edge = T.fnEdge
        val period = with(androidx.compose.ui.platform.LocalDensity.current) { 420.dp.toPx() }
        Box(Modifier.size(padSide.dp).clip(RoundedCornerShape(18.dp)).background(T.fn.copy(alpha = 0.75f))
            .border(1.5.dp, T.fnEdge, RoundedCornerShape(18.dp))) {
            Canvas(Modifier.fillMaxSize()
                .onSizeChanged { side = it.width.toFloat() }
                .pointerInput(ch, sensitivity, penWidth) {
                    // each touch is a stroke; a stylus's pressure makes it thicker or thinner
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        val stylus = down.type == PointerType.Stylus
                        down.consume()
                        strokes.add(InkStroke(listOf(down.position), listOf(HandInk.width(penWidth, down.pressure, stylus, sensitivity)), listOf(down.uptimeMillis)))
                        while (true) {
                            val e = awaitPointerEvent()
                            val c = e.changes.firstOrNull { it.id == down.id } ?: break
                            if (!c.pressed) break
                            c.consume()
                            if (strokes.isNotEmpty()) strokes[strokes.size - 1] = strokes.last().add(c.position, HandInk.width(penWidth, c.pressure, stylus, sensitivity), c.uptimeMillis)
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
                // 筆跡延遲: only what was written at least that long ago
                val until = if (delayMs > 0) frameNow - delayMs else Long.MAX_VALUE
                val ink = inkColor
                var dist = 0f
                for (s0 in strokes) {
                    val s = if (delayMs > 0 && s0.ts.size == s0.pts.size) {
                        val n = s0.ts.count { it <= until }
                        if (n == 0) continue
                        if (n < s0.pts.size) InkStroke(s0.pts.take(n), s0.ws.take(n)) else s0
                    } else s0
                    if (s.pts.size == 1) { drawCircle(if (rainbow) HandInk.color(dist, period) else ink, s.ws[0] / 2, s.pts[0]); continue }
                    for (i in 1 until s.pts.size) {
                        val a = s.pts[i - 1]; val b = s.pts[i]
                        val len = (b - a).getDistance()
                        drawLine(if (rainbow) HandInk.color(dist + len / 2, period) else ink, a, b,
                            (s.ws[i - 1] + s.ws[i]) / 2, cap = StrokeCap.Round)
                        dist += len
                    }
                }
            }
        }
        if (trace) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Txt(tr("描得像"), ff(FF.Footnote, FontWeight.SemiBold), T.muted)
            Box(Modifier.weight(1f)) { PotionBar(score, 22.dp, showMarks = false, label = tr("描得像")) }
            Txt(if (strokes.isEmpty()) "—" else "${Math.round(score * 100)}%", lat(15f), T.glyph)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SoftButton(onClick = { setIdx(maxOf(0, idx - 1)) }, Modifier.weight(1f), enabled = idx > 0) { IconLabel(Icons.Filled.ChevronLeft, tr("上一個"), ff(FF.Subheadline)) }
            SoftButton(onClick = { strokes.clear() }, Modifier.weight(1f)) { IconLabel(Icons.Filled.Clear, tr("清掉"), ff(FF.Subheadline)) }
            ProminentButton(onClick = { if (idx + 1 >= chars.size) finished() else setIdx(idx + 1) }, Modifier.weight(1f)) {
                IconLabel(Icons.Filled.ChevronRight, if (idx + 1 >= chars.size) tr("完成") else tr("下一個"), ff(FF.Subheadline))
            }
        }
        // 格子大小: the writing square, bigger or smaller (the shadow follows)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Filled.ZoomOut, tr("小一點"), tint = T.muted, modifier = Modifier.size(20.dp))
            Slider(padSide, { padSize = it }, Modifier.weight(1f), valueRange = 180f..maxOf(181f, maxPad),
                colors = SliderDefaults.colors(thumbColor = T.btnInk, activeTrackColor = T.btnEdge))
            Icon(Icons.Filled.ZoomIn, tr("大一點"), tint = T.muted, modifier = Modifier.size(20.dp))
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
            TextButton(onClick = { UI.closeSheet() }) { Text(tr("完成"), color = T.btnInk) }
            Spacer(Modifier.weight(1f))
            Txt(tr("有「{0}」的詞", ch), ff(FF.Headline, FontWeight.SemiBold), T.glyph)
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
        Txt(tr("有「{0}」的詞", ch), ff(FF.Headline, FontWeight.SemiBold), T.glyph, Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp))
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
                        Txt(tr("「{0}」這個字", ch), ff(FF.Body), T.glyph, Modifier.weight(1f))
                        Icon(Icons.Filled.ChevronRight, null, tint = T.muted)
                    }
                }
            }
            val l = zhList
            if (l == null) item(key = "wait") {
                Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = T.greenInk) }
            } else {
                item(key = "title") { SectionTitle(if (l.isEmpty()) tr("沒有找到有這個字的詞") else tr("有「{0}」的詞（{1}）", ch, l.size)) }
                itemsIndexed(l, key = { _, i -> "w|$i" }) { n, i ->
                    val e = z.entries[i]
                    rowBox(n, l.size, { UI.open(Sheet.ZhWord(e.k)) }) { ZhWordRow(z, e, meanings = 2) }
                }
            }
        } else {
            item(key = "title") { SectionTitle(if (cardWords.isEmpty()) tr("沒有找到有這個字的詞") else tr("有「{0}」的詞（{1}）", ch, cardWords.size)) }
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

/** 筆: 粗細, 筆跡延遲 and 筆壓 (a stylus); in 設定 and behind 筆 at the top of 手寫練習 */
@Composable
fun PenControls() {
    val w = Prefs.handWidth.value
    Row(verticalAlignment = Alignment.CenterVertically) {
        Txt(tr("粗細"), ff(FF.Body), T.glyph, Modifier.weight(1f))
        Txt("${w.toInt()}", lat(15f), T.muted)
    }
    Slider(w, { Prefs.handWidth.value = it }, valueRange = 3f..24f,
        colors = SliderDefaults.colors(thumbColor = T.btnInk, activeTrackColor = T.btnEdge))
    // how it looks
    val rainbow = Prefs.handRainbow.value
    Canvas(Modifier.fillMaxWidth().height(48.dp).clip(RoundedCornerShape(10.dp)).background(Color(0xFFF5F5F5))) {
        val p = Path()
        val n = 60
        for (k in 0..n) {
            val t = k / n.toFloat()
            val x = 12.dp.toPx() + t * (size.width - 24.dp.toPx())
            val y = size.height / 2 + kotlin.math.sin(t * Math.PI.toFloat() * 2) * size.height * 0.22f
            if (k == 0) p.moveTo(x, y) else p.lineTo(x, y)
        }
        drawPath(p, if (rainbow) HandInk.rainbow[0] else HandInk.solid, style = Stroke(w.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
    Spacer(Modifier.height(10.dp))
    // 筆跡延遲: the writing shows up a moment after the pen
    val dl = Prefs.handDelay.value
    Row(verticalAlignment = Alignment.CenterVertically) {
        Txt(tr("筆跡延遲"), ff(FF.Body), T.glyph, Modifier.weight(1f))
        Txt(if (dl < 0.025f) tr("馬上出現") else String.format(tr("%.1f 秒"), dl), ff(FF.Body), T.muted)
    }
    Slider(dl, { Prefs.handDelay.value = Math.round(it * 20) / 20f }, valueRange = 0f..1.5f,
        colors = SliderDefaults.colors(thumbColor = T.btnInk, activeTrackColor = T.btnEdge))
    Spacer(Modifier.height(10.dp))
    val s = Prefs.handPressure.value
    Row(verticalAlignment = Alignment.CenterVertically) {
        Txt(tr("觸控筆筆壓"), ff(FF.Body), T.glyph, Modifier.weight(1f))
        Txt(if (s < 0.05f) tr("粗細不變") else "${Math.round(s * 100)}%", ff(FF.Body), T.muted)
    }
    Slider(s, { Prefs.handPressure.value = it }, valueRange = 0f..1.5f,
        colors = SliderDefaults.colors(thumbColor = T.btnInk, activeTrackColor = T.btnEdge))
}

/** 中 | 英: 華語's meanings in 華語 or English (設定 → 主要解釋); standing up (中 over 英) in the top bar */
@Composable
fun MeaningSwitch(vertical: Boolean = false) {
    val en = Prefs.zhEnglish.value
    val m = Modifier.clip(RoundedCornerShape(50)).background(T.fn).border(1.5.dp, T.fnEdge, RoundedCornerShape(50))
        .clickable { Prefs.zhEnglish.value = !en }.padding(2.dp)
    @Composable
    fun part(e: Boolean) {
        val on = en == e
        Box(Modifier.size(width = if (vertical) 24.dp else 26.dp, height = if (vertical) 19.dp else 22.dp).clip(RoundedCornerShape(50))
            .background(if (on) T.btn else Color.Transparent), contentAlignment = Alignment.Center) {
            Txt(if (e) tr("英") else tr("中"), ff(FF.Caption, if (on) FontWeight.Bold else FontWeight.Normal), if (on) T.btnInk else T.muted)
        }
    }
    if (vertical) Column(m) { part(false); part(true) } else Row(m) { part(false); part(true) }
}

/** 手寫練習: 我會了. Tap: the character is known (its card 熟悉), yellow with little rainbow rays around it;
 *  tap again: 不熟. */
@Composable
private fun KnowCharButton(c: Card) {
    val known = Store.status(c) == 1
    val yellow = Color(0xFFF6C945)
    var pop by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (pop) 1.12f else 1f, spring(dampingRatio = 0.5f), label = "pop")
    val rays by animateFloatAsState(if (known) 1f else 0f, spring(dampingRatio = 0.6f), label = "rays")
    LaunchedEffect(pop) { if (pop) { kotlinx.coroutines.delay(350); pop = false } }
    val haptic = androidx.compose.ui.platform.LocalHapticFeedback.current
    Box(Modifier.size(58.dp).graphicsLayer { scaleX = scale; scaleY = scale }.clip(CircleShape)
        .clickable {
            val now = !known
            val ch = Lang.charOf(c.k)
            if (ch != null) Store.setCharKnown(ch, now) else Store.mark(c, now, undoable = false)
            if (now) pop = true
            haptic.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.TextHandleMove)
        }, contentAlignment = Alignment.Center) {
        // the rays: the rainbow, all the way round
        if (rays > 0.01f) Canvas(Modifier.fillMaxSize()) {
            val r0 = 21.dp.toPx() + (if (pop) 3.dp.toPx() else 0f)
            val len = 6.dp.toPx() * rays
            for (i in 0 until 12) {
                val a = Math.toRadians(i * 30.0 - 90)
                val cx = size.width / 2; val cy = size.height / 2
                val ux = kotlin.math.cos(a).toFloat(); val uy = kotlin.math.sin(a).toFloat()
                drawLine(HandInk.rainbow[i % HandInk.rainbow.size].copy(alpha = rays), Offset(cx + ux * r0, cy + uy * r0),
                    Offset(cx + ux * (r0 + len), cy + uy * (r0 + len)), strokeWidth = 2.5.dp.toPx(), cap = StrokeCap.Round)
            }
        }
        Box(Modifier.size(40.dp).clip(CircleShape).background(if (known) yellow else T.fn)
            .border(1.5.dp, if (known) yellow.copy(alpha = 0.6f) else T.fnEdge, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Check, if (known) tr("我會了（再點一下：不熟）") else tr("我會這個字"), tint = if (known) Color(0xFF3A2A00) else T.muted,
                modifier = Modifier.size(20.dp))
        }
    }
}

/** the ink's colour as a little ball: the colour, or the rainbow */
@Composable
fun InkSwatch(size: androidx.compose.ui.unit.Dp) {
    val rainbow = Prefs.handRainbow.value
    val ink = HandInk.solid
    Box(Modifier.size(size).clip(CircleShape).background(
        if (rainbow) androidx.compose.ui.graphics.Brush.sweepGradient(HandInk.rainbow + HandInk.rainbow[0])
        else androidx.compose.ui.graphics.SolidColor(ink)).border(1.dp, Color.White.copy(alpha = 0.55f), CircleShape))
}

/** 筆的顏色: 墨色 (the dark ink), 彩虹 or one colour from the grid of balls (the same colours as 選聲調顏色:
 *  one column per colour in rainbow order, light at the top and dark at the bottom) */
@Composable
fun InkColorControls() {
    val rainbow = Prefs.handRainbow.value
    val ink = Prefs.handInk.value
    Txt(tr("筆的顏色"), ff(FF.Footnote, FontWeight.SemiBold), T.muted, Modifier.padding(bottom = 8.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        @Composable
        fun mode(name: String, on: Boolean, brush: androidx.compose.ui.graphics.Brush, act: () -> Unit) {
            Row(Modifier.clip(RoundedCornerShape(50)).background(if (on) Color.White.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.05f))
                .border(if (on) 1.5.dp else 1.dp, Color.White.copy(alpha = if (on) 0.7f else 0.15f), RoundedCornerShape(50))
                .clickable(onClick = act).padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(16.dp).clip(CircleShape).background(brush)); Spacer(Modifier.width(8.dp))
                Txt(name, ff(FF.Subheadline, if (on) FontWeight.Bold else FontWeight.Normal), T.glyph)
            }
        }
        mode(tr("墨色"), !rainbow && ink == 0, androidx.compose.ui.graphics.SolidColor(HandInk.dark)) { Prefs.handRainbow.value = false; Prefs.handInk.value = 0 }
        mode(tr("彩虹"), rainbow, androidx.compose.ui.graphics.Brush.sweepGradient(HandInk.rainbow + HandInk.rainbow[0])) { Prefs.handRainbow.value = true }
    }
    Spacer(Modifier.height(12.dp))
    val cols = ToneColors.palette
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (row in 0 until 5) Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (c in cols) {
                val hex = c.second[row]
                val picked = !rainbow && ink == hex
                Box(Modifier.size(31.dp).clip(CircleShape).clickable { Prefs.handInk.value = hex; Prefs.handRainbow.value = false },
                    contentAlignment = Alignment.Center) {
                    if (picked) Box(Modifier.size(31.dp).border(2.5.dp, T.glyph, CircleShape))
                    Box(Modifier.size(25.dp).clip(CircleShape).background(Color(0xFF000000L or hex.toLong())))
                }
            }
        }
    }
    Txt(tr("中間那一排是原本的顏色，往上越淺，往下越深。"), ff(FF.Caption), T.muted, Modifier.padding(top = 8.dp))
}

/** 手寫練習 from a 台語 side card: the character's word, read as in the big card's word */
var handwritingGiven: Map<String, Card> = emptyMap()

/** 華語: the character card; 台語: the character's own word (from a side card, or its most common reading) */
fun charCardFor(ch: String): Card? =
    if (Store.isZh) Store.cardFor(Lang.charKey(ch)) else handwritingGiven[ch] ?: twCharCard(ch)

private var twCache: Pair<Int, Map<String, Card>> = 0 to emptyMap()

/** 台語: a character as its own dictionary word, read the most common way (the word list is in order of use) */
fun twCharCard(ch: String): Card? {
    if (Store.isZh) return null
    val cs = Store.cards
    if (twCache.first != cs.size) {
        val m = HashMap<String, Card>()
        for (c in cs) if (c.h.codePointCount(0, c.h.length) == 1 && !m.containsKey(c.h)) m[c.h] = c
        twCache = cs.size to m
    }
    return twCache.second[ch]
}

/** 台語 手寫練習: the characters of your 不熟 and 熟悉 words (that have a word of their own), the latest first */
private fun twCharSets(): Pair<List<String>, List<String>> {
    val p = Store.progress
    val keys = p.status.entries.filter { !Lang.isZhKey(it.key) && Lang.charOf(it.key) == null }
        .sortedByDescending { p.added[it.key] ?: 0.0 }
    val unknown = LinkedHashSet<String>(); val known = LinkedHashSet<String>()
    for ((k, v) in keys) {
        val tab = k.indexOf('\t'); val h = if (tab < 0) k else k.substring(0, tab)
        for (ch in h.cps()) if (Zhuyin.isHan(ch.firstCp()) && twCharCard(ch) != null) {
            if (v == 2) unknown.add(ch) else if (v == 1) known.add(ch)
        }
    }
    return unknown.filter { it !in known } to known.filter { it !in unknown }
}
