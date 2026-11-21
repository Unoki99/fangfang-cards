package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.launch
import kotlin.math.cos
import kotlin.math.roundToInt

// MARK: - two pages side by side (swipe between them, or tap a tab): both take the room of the taller one, so
// nothing below them moves when you switch

@Composable
fun SwipePages(titles: List<String>, keptId: String, content: @Composable (Int) -> Unit) {
    var page by rememberKept(keptId) { 0 }
    val scope = rememberCoroutineScope()
    val at = remember { Animatable(page.toFloat()) }
    var width by remember { mutableIntStateOf(1) }
    LaunchedEffect(page) { if (at.value != page.toFloat()) at.animateTo(page.toFloat(), tween(260)) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            for ((i, t) in titles.withIndex()) {
                val on = page == i
                Txt(t, ff(FF.Caption, FontWeight.Bold), if (on) T.twInk else T.muted,
                    Modifier.clip(CircleShape).background(if (on) T.twFill else T.fn.copy(alpha = 0.6f)).clickable { page = i }.hand()
                        .padding(horizontal = 10.dp, vertical = 4.dp))
            }
            Spacer(Modifier.weight(1f))
            // (where you are: a dot for each page)
            for (i in titles.indices) Box(Modifier.size(6.dp).background(if (page == i) T.twInk else T.muted.copy(alpha = 0.4f), CircleShape))
        }
        // (one Box per page, in order: made in the content itself, not as a list of composable lambdas, which the
        // computer version couldn't load: "Illegal method name <anonymous>")
        Layout(
            content = { for (i in titles.indices) Box { content(i) } },
            modifier = Modifier.fillMaxWidth().clipToBounds().onSizeChanged { width = maxOf(1, it.width) }
                .draggable(rememberDraggableState { delta ->
                    scope.launch { at.snapTo((at.value - delta / width).coerceIn(0f, (titles.size - 1).toFloat())) }
                }, Orientation.Horizontal, onDragStopped = { v ->
                    val target = when {
                        v < -600f -> kotlin.math.ceil(at.value.toDouble()).toInt()
                        v > 600f -> kotlin.math.floor(at.value.toDouble()).toInt()
                        else -> at.value.roundToInt()
                    }.coerceIn(0, titles.size - 1)
                    if (target == page) at.animateTo(target.toFloat(), tween(220)) else page = target
                })
        ) { measurables, constraints ->
            val w = constraints.maxWidth
            val ps = measurables.map { it.measure(Constraints(minWidth = w, maxWidth = w)) }
            // (as tall as the page shown, not the taller one: going from one to the other while swiping)
            val a = at.value.coerceIn(0f, (ps.size - 1).toFloat())
            val lo = kotlin.math.floor(a).toInt()
            val hi = minOf(lo + 1, ps.size - 1)
            val f = a - lo
            val h = (ps[lo].height + (ps[hi].height - ps[lo].height) * f).roundToInt()
            layout(w, h) {
                for ((i, p) in ps.withIndex()) p.placeRelative(((i - at.value) * w).roundToInt(), 0)
            }
        }
    }
}

// MARK: - a map of Taiwan: the outline, and where each 腔口 of the dictionary was recorded (the reading there)

/** the coast (longitude, latitude), going round from 富貴角; drawn simply, for showing where the places are */
private val TAIWAN = listOf(
    121.54 to 25.30, 121.64 to 25.21, 121.75 to 25.15, 121.84 to 25.12, 122.00 to 25.01, 121.92 to 24.93, 121.86 to 24.87,
    121.83 to 24.72, 121.87 to 24.59, 121.84 to 24.52, 121.80 to 24.44, 121.72 to 24.28, 121.68 to 24.18, 121.62 to 23.98,
    121.58 to 23.80, 121.52 to 23.60, 121.47 to 23.40, 121.40 to 23.18, 121.35 to 23.06, 121.22 to 22.88, 121.15 to 22.75,
    121.03 to 22.62, 120.92 to 22.40, 120.88 to 22.25, 120.86 to 22.06, 120.85 to 21.90, 120.79 to 21.94, 120.73 to 21.93,
    120.70 to 22.02, 120.70 to 22.10, 120.62 to 22.27, 120.58 to 22.37, 120.45 to 22.46, 120.35 to 22.55, 120.28 to 22.62,
    120.24 to 22.75, 120.20 to 22.86, 120.15 to 23.00, 120.08 to 23.10, 120.09 to 23.22, 120.14 to 23.35, 120.15 to 23.46,
    120.17 to 23.62, 120.21 to 23.73, 120.26 to 23.86, 120.36 to 23.98, 120.43 to 24.07, 120.51 to 24.20, 120.55 to 24.30,
    120.61 to 24.42, 120.67 to 24.51, 120.74 to 24.60, 120.83 to 24.68, 120.90 to 24.78, 120.96 to 24.86, 121.02 to 24.95,
    121.10 to 25.05, 121.20 to 25.10, 121.33 to 25.14, 121.40 to 25.18, 121.47 to 25.25,
)
private val PENGHU = listOf(119.54 to 23.70, 119.62 to 23.68, 119.70 to 23.62, 119.66 to 23.53, 119.58 to 23.54, 119.52 to 23.60)
/** 金門 (drawn in the box at the top left: it's far to the west) */
private val KINMEN = listOf(118.24 to 24.45, 118.31 to 24.50, 118.40 to 24.50, 118.47 to 24.46, 118.44 to 24.41, 118.36 to 24.40, 118.29 to 24.42)
private const val KINMEN_DX = 0.80
private const val KINMEN_DY = 0.55

/** where each place is (by the first two characters of its name), and which side its label goes on */
private val SPOTS = mapOf(
    "鹿港" to Triple(120.43, 24.06, -1), "三峽" to Triple(121.37, 24.93, -1), "臺北" to Triple(121.52, 25.04, 1),
    "宜蘭" to Triple(121.75, 24.75, 1), "臺南" to Triple(120.20, 23.00, -1), "高雄" to Triple(120.30, 22.63, -1),
    "金門" to Triple(118.37 + KINMEN_DX, 24.45 + KINMEN_DY, 1), "馬公" to Triple(119.57, 23.57, 0),
    "新竹" to Triple(120.97, 24.80, -1), "臺中" to Triple(120.68, 24.15, 1),
)
private const val LON0 = 118.85
private const val LON1 = 122.25
private const val LAT0 = 25.45
private const val LAT1 = 21.80
private val KX = cos(Math.toRadians(23.7))

// (plain functions and a composable of their own for each place: no local functions or early returns inside the
// composable lambdas, which the computer version couldn't load: "Illegal method name <anonymous>")
private val MAP_W = (LON1 - LON0) * KX
private val MAP_H = LAT0 - LAT1

private fun mapX(lon: Double, width: Float): Float = ((lon - LON0) * KX / MAP_W * width).toFloat()
private fun mapY(lat: Double, height: Float): Float = ((LAT0 - lat) / MAP_H * height).toFloat()

private fun mapShape(ps: List<Pair<Double, Double>>, dx: Double, dy: Double, width: Float, height: Float): Path {
    val path = Path()
    for (i in ps.indices) {
        val x = mapX(ps[i].first + dx, width); val y = mapY(ps[i].second + dy, height)
        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    path.close()
    return path
}

private fun drawCoast(scope: androidx.compose.ui.graphics.drawscope.DrawScope, land: androidx.compose.ui.graphics.Color, edge: androidx.compose.ui.graphics.Color) {
    val wd = scope.size.width; val ht = scope.size.height
    val line = Stroke(width = 1.5f * scope.density)
    for (shape in listOf(mapShape(TAIWAN, 0.0, 0.0, wd, ht), mapShape(PENGHU, 0.0, 0.0, wd, ht), mapShape(KINMEN, KINMEN_DX, KINMEN_DY, wd, ht))) {
        scope.drawPath(shape, land.copy(alpha = 0.55f))
        scope.drawPath(shape, edge.copy(alpha = 0.8f), style = line)
    }
    // (金門's box)
    val ax = mapX(118.17 + KINMEN_DX, wd); val ay = mapY(24.58 + KINMEN_DY, ht)
    val bx = mapX(118.55 + KINMEN_DX, wd); val by = mapY(24.33 + KINMEN_DY, ht)
    scope.drawRect(edge.copy(alpha = 0.5f), Offset(ax, ay), androidx.compose.ui.geometry.Size(bx - ax, by - ay),
        style = Stroke(width = 1f * scope.density, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 5f))))
}

@Composable
fun TaiwanMap(d: Dict, key: String, modifier: Modifier = Modifier, height: androidx.compose.ui.unit.Dp = 300.dp, width: androidx.compose.ui.unit.Dp? = null) {
    if (d.raw.places.isEmpty()) return
    val local = d.raw.loc?.get(key)?.filter { it < d.raw.places.size }
    val shown = (local ?: d.raw.places.indices.toList()).toSet()
    val edge = T.muted; val land = T.fn
    var boxW by remember { mutableIntStateOf(0) }
    var boxH by remember { mutableIntStateOf(0) }
    val spots = d.raw.places.indices.filter { SPOTS.containsKey(d.raw.places[it].take(2)) }
    // (a width given: the map as big as fits in width × height, at the top; else as wide as the height makes it)
    val outer = if (width != null) modifier.width(width).height(height) else modifier.height(height)
    Box(outer, contentAlignment = Alignment.TopCenter) {
        Box(Modifier.aspectRatio((MAP_W / MAP_H).toFloat(), matchHeightConstraintsFirst = true).onSizeChanged { boxW = it.width; boxH = it.height }) {
            Canvas(Modifier.fillMaxSize()) { drawCoast(this, land, edge) }
            for (p in spots) MapSpot(d, key, p, p in shown, boxW, boxH)
        }
    }
}

/** one place on the map: its dot, its name and the reading there */
@Composable
private fun MapSpot(d: Dict, key: String, p: Int, on: Boolean, boxW: Int, boxH: Int) {
    val name = d.raw.places[p].take(2)
    val s = SPOTS[name] ?: Triple(121.0, 24.0, 0)
    val mine = p == Prefs.place.value
    val rom = Prefs.rom.value.coerceIn(0, 2)
    val tk = textKey()
    val density = LocalDensity.current
    val x = mapX(s.first, boxW.toFloat()); val y = mapY(s.second, boxH.toFloat())
    val dot = 10f * density.density
    val gap = 8f * density.density
    val up = 9f * density.density
    // (the dot in its 腔's colour: every place's with 通行 in 設定, else only the place chosen)
    val lit = if (on && twLit(p, Prefs.place.value)) twGroupColor(d, p) else null
    Box(Modifier.offset { IntOffset((x - dot / 2).roundToInt(), (y - dot / 2).roundToInt()) }.size(10.dp)
        .background(lit ?: if (on) T.muted.copy(alpha = 0.75f) else T.muted.copy(alpha = 0.3f), CircleShape))
    val reading = remember(key, p, tk) { if (on) d.wordText(key, rom, p).plain() else "" }
    var lw by remember { mutableIntStateOf(0) }
    val lx = if (s.third == -1) x - gap - lw else if (s.third == 1) x + gap else x - lw / 2f
    val ly = if (s.third == 0) y + gap else y - up
    Column(Modifier.offset { IntOffset(lx.roundToInt(), ly.roundToInt()) }.onSizeChanged { lw = it.width },
        horizontalAlignment = if (s.third == -1) Alignment.End else if (s.third == 1) Alignment.Start else Alignment.CenterHorizontally) {
        Txt(tr(name), ff(FF.Caption2, FontWeight.Bold), if (mine) (lit ?: T.twInk) else if (on) T.glyph else T.muted.copy(alpha = 0.6f), maxLines = 1)
        if (reading.isNotEmpty()) Txt(reading, lat(11f), if (mine) (lit ?: T.twInk) else T.greenInk, maxLines = 1)
    }
}

/** the readings of every 腔口 and the map: side by side when there's room, the map under them when not */
@Composable
fun TwPlacesAndMap(d: Dict, key: String) {
    BoxWithConstraints {
        // (wide: 通行 on top, then the three groups (泉, 混, 漳) with the map beside them, just as tall as they are)
        if (maxWidth > 620.dp) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            TwPlaceRows(d, key, groups = false)
            var groupsH by remember { mutableIntStateOf(0) }
            val density = LocalDensity.current
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.Top) {
                Box(Modifier.weight(1f).onSizeChanged { groupsH = it.height }) { TwPlaceRows(d, key, common = false) }
                // (a set width: the groups beside it don't change width as it grows, so nothing goes round in circles)
                TaiwanMap(d, key, height = with(density) { groupsH.toDp() }.coerceIn(200.dp, 420.dp), width = 260.dp)
            }
        } else Column(verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            TwPlaceRows(d, key)
            TaiwanMap(d, key, height = 280.dp)
        }
    }
    Txt(tr("地圖上的點是辭典記錄各地讀音的地方，不是腔口的界線。"), ff(FF.Caption2), T.muted)
}

/** the three 腔 the places lean to, each in a colour of its own: 泉 teal (台語's 6th tone), 混 orange, 漳 purple */
fun twKindColor(kind: String): Color = when (kind) {
    "泉" -> Color(0xFF4FD8C4)
    "混" -> Color(0xFFFFA94D)
    else -> Color(0xFFC39BFF)
}

/** a place's 腔 colour (none for 通行) */
fun twGroupColor(d: Dict, p: Int): Color? {
    val n = d.raw.places.getOrNull(p) ?: return null
    for (k in listOf("泉", "混", "漳")) if (n.contains(k)) return twKindColor(k)
    return null
}

/** in colour: every place when 通行 is the one chosen, else only the chosen place */
fun twLit(p: Int, chosen: Int): Boolean = chosen == -1 || (p >= 0 && p == chosen)
