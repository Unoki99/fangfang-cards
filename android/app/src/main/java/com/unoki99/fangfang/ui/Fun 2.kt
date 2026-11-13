package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.boundsInRoot
import kotlinx.coroutines.isActive
import com.unoki99.fangfang.engine.ToneColors
import kotlin.math.*
import kotlin.random.Random

// MARK: the potion bar

enum class PotionPalette { RAINBOW, BLUE }

private val rainbow = listOf(
    0f to Color(0xFFA66BFF), 0.04f to Color(0xFFFF5C9A), 0.10f to Color(0xFFFF9A4A),
    0.17f to Color(0xFFFFE066), 0.40f to Color(0xFF7EE081), 1f to Color(0xFF4FD8D0))
private val blues = listOf(
    0f to Color(0xFF3A3FD8), 0.35f to Color(0xFF4F7DFF), 0.65f to Color(0xFF6EAAFF), 0.9f to Color(0xFF9AD8FF), 1f to Color(0xFFC9F2FF))

/** A glowing potion in a glass tube, as a progress bar or a score: it fills up with a little splash, bubbles rise in it */
@Composable
fun PotionBar(value: Double, height: Dp = 30.dp, showMarks: Boolean = true, label: String = tr("通順程度"), palette: PotionPalette = PotionPalette.RAINBOW,
              modifier: Modifier = Modifier) {
    val level = remember { Animatable(0f) }
    LaunchedEffect(value) { level.animateTo(value.toFloat(), spring(dampingRatio = 0.62f, stiffness = 60f)) }
    var time by remember { mutableFloatStateOf(0f) }
    // 設定 → 主題動畫 off: the potion stands still
    val moving = com.unoki99.fangfang.Prefs.themeMotion.value
    LaunchedEffect(moving) {
        if (!moving) return@LaunchedEffect
        val start = withFrameNanos { it }
        while (isActive) withFrameNanos { time = (it - start) / 1e9f }
    }
    val stops = if (palette == PotionPalette.BLUE) blues else rainbow
    Canvas(modifier.fillMaxWidth().padding(vertical = 6.dp).height(height).semantics { contentDescription = "$label ${(value * 100).roundToInt()}%" }) {
        val w = size.width; val h = size.height
        val lvl = level.value.coerceIn(0f, 1.08f)
        val edge = max(w * min(lvl, 1f), if (lvl > 0.001f) 10f else 0f)
        val tube = RoundRect(0f, 0f, w, h, CornerRadius(h / 2, h / 2))
        val tubePath = Path().apply { addRoundRect(tube) }
        val brush = Brush.horizontalGradient(*stops.toTypedArray(), startX = 0f, endX = w)
        // the liquid, its right edge rippling
        val liquid = Path()
        if (edge > 0) {
            liquid.moveTo(0f, 0f)
            val amp = if (edge >= w - 1) 0f else 3f * density
            var y = 0f
            while (y <= h) {
                val x = edge + sin(y / h * PI * 2 + time * 3.2).toFloat() * amp + sin(y / h * PI * 5 - time * 4.7).toFloat() * amp * 0.35f
                liquid.lineTo(x, y); y += 2f
            }
            liquid.lineTo(0f, h); liquid.close()
        }
        // glow outside the glass (a soft wider copy)
        if (edge > 0) for (k in 1..3) {
            drawRoundRect(brush, Offset(-k * 3f, -k * 3f), Size(min(edge, w) + k * 6f, h + k * 6f), CornerRadius(h / 2 + k * 3f), alpha = 0.09f)
        }
        clipPath(tubePath) {
            drawRect(Color.Black.copy(alpha = 0.35f))
            if (edge > 0) {
                drawPath(liquid, brush)
                clipPath(liquid) {
                    drawRect(Color.White.copy(alpha = 0.16f), Offset.Zero, Size(edge + 6, h * 0.32f))
                    drawRect(Color.Black.copy(alpha = 0.14f), Offset(0f, h * 0.72f), Size(edge + 6, h * 0.28f))
                    for (i in 0 until 18) {
                        val s = i.toDouble()
                        fun frac(v: Double) = v - floor(v)
                        val fx = frac(sin(s * 12.9898) * 43758.5453)
                        val fs = frac(sin(s * 78.233) * 12345.678)
                        val speed = 0.18 + fs * 0.35
                        val phase = frac(time * speed + fx * 3.1)
                        val bx = (6 + fx * max(edge - 12.0, 1.0) + sin(time * 2 + s) * 1.5).toFloat()
                        val by = (h * (1.05 - phase * 1.1)).toFloat()
                        val r = ((1.0 + fs * 1.8) * density / 2).toFloat()
                        drawCircle(Color.White.copy(alpha = (0.6 * sin(phase * PI)).toFloat().coerceIn(0f, 1f)), r, Offset(bx, by), style = Stroke(0.8f * density))
                    }
                }
                if (edge < w - 4) {
                    val tw = 0.5f + 0.5f * sin(time * 5f)
                    val r = (2f + tw * 1.5f) * density / 2
                    drawCircle(Color.White.copy(alpha = 0.45f + 0.4f * tw), r, Offset(edge - r - 2, h * 0.28f))
                }
            }
            if (showMarks) for (x in listOf(0.04f, 0.15f)) {
                drawRect(Color.White.copy(alpha = 0.22f), Offset(w * x, h * 0.55f), Size(1.5f, h * 0.45f))
            }
        }
        drawPath(tubePath, Color.White.copy(alpha = 0.28f), style = Stroke(1.5f * density))
        drawRoundRect(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.35f), Color.Transparent), startY = 3f, endY = 3f + 7 * density),
            Offset(12 * density, 3 * density), Size(w - 24 * density, 7 * density), CornerRadius(4 * density))
    }
}

// MARK: stars that burst from your finger

class StarField {
    enum class Kind { STAR, MOON, LEAF, PLANET, MUSHROOM, ACORN }
    class Star(val start: Offset, val vx: Float, val vy: Float, val spin: Float, val size: Float, val color: Color, val born: Long, val kind: Kind)
    val stars = mutableStateListOf<Star>()
    /** where a tap doesn't make any (the squares to write in), in the window's coordinates */
    val noBursts = HashMap<String, Rect>()
    /** where the StarBox is in the window */
    var origin = Offset.Zero
    private val colors = ToneColors.all.map { Color(it) }

    private val kinds: List<Kind>
        get() = when (AppTheme.current) {
            AppTheme.NIGHT -> listOf(Kind.STAR)
            AppTheme.WITCH -> listOf(Kind.STAR, Kind.STAR, Kind.MOON, Kind.LEAF)
            AppTheme.SPACE -> listOf(Kind.STAR, Kind.STAR, Kind.PLANET)
            AppTheme.GOBLIN -> listOf(Kind.MUSHROOM, Kind.LEAF, Kind.ACORN, Kind.STAR)
            AppTheme.WINTER -> listOf(Kind.STAR, Kind.MOON)
        }

    fun burst(p: Offset, scale: Float) {
        val now = System.nanoTime()
        val n = Random.nextInt(5, 9)
        for (i in 0 until n) {
            val angle = -PI / 2 + Random.nextDouble(-1.1, 1.1)
            val speed = Random.nextDouble(180.0, 380.0).toFloat() * scale
            stars.add(Star(p, (cos(angle) * speed).toFloat(), (sin(angle) * speed).toFloat(), Random.nextDouble(-1.2, 1.2).toFloat(),
                Random.nextDouble(9.0, 16.0).toFloat() * scale, colors[(i + Random.nextInt(8)) % 8], now, kinds.random()))
        }
        if (stars.size > 160) stars.removeRange(0, stars.size - 160)
    }

    companion object { const val gravity = 900f }
}

/** tap anywhere: little things in the tone colours burst out and fall (the tap still reaches what's underneath) */
@Composable
fun StarBox(field: StarField, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val scale = LocalDensity.current.density
    Box(modifier.onGloballyPositioned { field.origin = it.positionInRoot() }.pointerInput(Unit) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            val at = down.position + field.origin
            if (field.noBursts.values.none { it.contains(at) }) field.burst(down.position, scale)
        }
    }) {
        CompositionLocalProvider(LocalStarField provides field) { content() }
        StarLayer(field)
    }
}

@Composable
private fun StarLayer(field: StarField) {
    if (field.stars.isEmpty()) return
    var now by remember { mutableLongStateOf(System.nanoTime()) }
    LaunchedEffect(field.stars.size > 0) {
        while (isActive && field.stars.isNotEmpty()) {
            withFrameNanos { now = it }
            // gone off the bottom by now
            field.stars.removeAll { now - it.born > 3_500_000_000L }
        }
    }
    Canvas(Modifier.fillMaxSize()) {
        for (s in field.stars.toList()) {
            val t = ((now - s.born) / 1e9f).coerceAtLeast(0f)
            val g = StarField.gravity * density
            val p = Offset(s.start.x + s.vx * t, s.start.y + s.vy * t + g * t * t / 2)
            if (p.y > size.height + 40 * density) continue
            translate(p.x, p.y) {
                rotate(t * s.spin * 360f, Offset.Zero) {
                    val path = shape(s.kind, s.size)
                    drawPath(path, s.color.copy(alpha = 0.35f), style = Stroke(s.size * 0.5f, join = StrokeJoin.Round))
                    drawPath(path, s.color)
                    if (s.kind == StarField.Kind.PLANET) {
                        rotate(-20f, Offset.Zero) {
                            drawOval(s.color.copy(alpha = 0.9f), Offset(-s.size * 1.15f, -s.size * 0.32f), Size(s.size * 2.3f, s.size * 0.64f),
                                style = Stroke(max(1.5f, s.size * 0.14f)))
                        }
                    }
                }
            }
        }
    }
}

private fun shape(k: StarField.Kind, r: Float): Path = when (k) {
    StarField.Kind.STAR -> Path().apply {
        for (i in 0 until 10) {
            val a = -PI / 2 + i * PI / 5
            val rr = if (i % 2 == 0) r else r * 0.45f
            val x = (cos(a) * rr).toFloat(); val y = (sin(a) * rr).toFloat()
            if (i == 0) moveTo(x, y) else lineTo(x, y)
        }
        close()
    }
    StarField.Kind.MOON -> {
        val a = Path().apply { addOval(Rect(-r, -r, r, r)) }
        val b = Path().apply { addOval(Rect(-r * 0.45f, -r * 1.05f, -r * 0.45f + 1.9f * r, -r * 1.05f + 1.9f * r)) }
        Path().apply { op(a, b, PathOperation.Difference) }
    }
    StarField.Kind.LEAF -> Path().apply {
        moveTo(0f, -r); quadraticTo(r * 0.95f, 0f, 0f, r); quadraticTo(-r * 0.95f, 0f, 0f, -r); close()
    }
    StarField.Kind.PLANET -> Path().apply { val pr = r * 0.62f; addOval(Rect(-pr, -pr, pr, pr)) }
    StarField.Kind.MUSHROOM -> Path().apply {
        moveTo(-r, 0f); quadraticTo(0f, -r * 1.5f, r, 0f); close()
        addRoundRect(RoundRect(-r * 0.28f, -1f, r * 0.28f, r * 0.95f, CornerRadius(3f)))
    }
    StarField.Kind.ACORN -> Path().apply {
        addOval(Rect(-r * 0.55f, -r * 0.35f, r * 0.55f, r))
        addRoundRect(RoundRect(-r * 0.72f, -r * 0.62f, r * 0.72f, -r * 0.17f, CornerRadius(r * 0.2f)))
        addRect(Rect(-r * 0.06f, -r * 0.9f, r * 0.06f, -r * 0.6f))
    }
}

/** the StarField of the practice screen this is in (null: none) */
val LocalStarField = staticCompositionLocalOf<StarField?> { null }

/** no little things from taps here (a square to write in) */
@Composable
fun Modifier.noStarBursts(): Modifier {
    val field = LocalStarField.current ?: return this
    val key = remember { java.util.UUID.randomUUID().toString() }
    DisposableEffect(key) { onDispose { field.noBursts.remove(key) } }
    return this.onGloballyPositioned { field.noBursts[key] = it.boundsInRoot() }
}
