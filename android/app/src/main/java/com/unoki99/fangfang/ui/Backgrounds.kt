package com.unoki99.fangfang.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import kotlin.math.*

/** every page's background, in the chosen theme (faint, and it never takes a touch) */
@Composable
fun AppBackground(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(modifier.fillMaxSize().background(T.bg)) {
        when (AppTheme.current) {
            AppTheme.WITCH -> WitchBackground()
            AppTheme.SPACE -> SpaceBackground()
            AppTheme.GOBLIN -> GoblinBackground()
            AppTheme.NIGHT -> NightBackground()
            AppTheme.WINTER -> WinterBackground()
            AppTheme.SAKURA -> FallingThingsBackground(true)
            AppTheme.MOMIJI -> FallingThingsBackground(false)
        }
        content()
    }
}

/** a value going back and forth (設定 → 主題動畫 off: it stays in the middle) */
@Composable
private fun drift(label: String, from: Float, to: Float, ms: Int): Float {
    if (!com.unoki99.fangfang.Prefs.themeMotion.value) return (from + to) / 2
    val v by rememberInfiniteTransition(label = label).animateFloat(from, to,
        infiniteRepeatable(tween(ms, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = label)
    return v
}

/** 雪夜: a winter night: snowy hills, pines, the moon, a faint aurora and falling snow */
@Composable
private fun WinterBackground() {
    val moving = com.unoki99.fangfang.Prefs.themeMotion.value
    var time by androidx.compose.runtime.remember { androidx.compose.runtime.mutableFloatStateOf(0f) }
    if (moving) androidx.compose.runtime.LaunchedEffect(Unit) {
        val start = androidx.compose.runtime.withFrameNanos { it }
        while (true) androidx.compose.runtime.withFrameNanos { time = (it - start) / 1e9f }
    }
    Canvas(Modifier.fillMaxSize()) {
        val w = size.width; val h = size.height; val d = density
        drawRect(Brush.verticalGradient(listOf(Color(0xFF16233A), Color(0xFF111A2A), Color(0xFF0C121C))))
        // the aurora and the moon's light
        glowAt(Color(0xFF4FD8A8), 0.10f, Offset(w * 0.3f, h * 0.08f), max(w, 300f) * 0.7f)
        glowAt(Color(0xFF8FB4FF), 0.14f, Offset(w * 0.85f, h * 0.12f), max(w, 300f) * 0.5f)
        val moon = Offset(w * 0.85f, 110 * d)
        glowAt(Color(0xFFCFE0FF), 0.25f, moon, 30 * d)
        drawCircle(Brush.radialGradient(listOf(Color(0xFFF4F8FF), Color(0xFFB9C8E6)), Offset(moon.x - 4 * d, moon.y - 5 * d), 24 * d), 18 * d, moon, alpha = 0.4f)
        // snowy hills and pines
        val hills = Path().apply {
            moveTo(0f, h - 90 * d)
            cubicTo(w * 0.25f, h - 150 * d, w * 0.45f, h - 60 * d, w * 0.65f, h - 110 * d)
            cubicTo(w * 0.8f, h - 145 * d, w * 0.92f, h - 95 * d, w, h - 120 * d)
            lineTo(w, h); lineTo(0f, h); close()
        }
        drawPath(hills, Brush.verticalGradient(listOf(Color(0xFFDFE9F7).copy(alpha = 0.16f), Color(0xFFDFE9F7).copy(alpha = 0.07f)), h - 150 * d, h))
        for ((x, ph) in listOf(0.08f to 58f, 0.15f to 40f, 0.82f to 64f, 0.9f to 44f, 0.6f to 30f)) {
            val bh = ph * d; val bw = bh * 0.6f
            val cx = w * x; val base = h - 92 * d + bh * 0.15f
            val pine = Path().apply {
                moveTo(cx, base - bh); lineTo(cx + bw * 0.35f, base - bh * 0.55f); lineTo(cx + bw * 0.2f, base - bh * 0.55f)
                lineTo(cx + bw * 0.5f, base - bh * 0.1f); lineTo(cx - bw * 0.5f, base - bh * 0.1f); lineTo(cx - bw * 0.2f, base - bh * 0.55f)
                lineTo(cx - bw * 0.35f, base - bh * 0.55f); close()
            }
            drawPath(pine, Color(0xFF9FC2C0).copy(alpha = 0.13f))
        }
        // falling snow (the same flakes every time)
        for (f in winterFlakes) {
            val y = ((f[3] + time * f[2]) % 1.1f) * h - 0.05f * h
            val x = w * f[0] + sin(time * 0.8f + f[3] * 10f) * f[4] * d
            drawCircle(Color.White.copy(alpha = 0.55f), f[1] * d, Offset(x, y))
        }
    }
}

private val winterFlakes: List<FloatArray> = run {
    var x = 0x9E3779B97F4A7C15uL
    fun next(): Float { x = x xor (x shl 13); x = x xor (x shr 7); x = x xor (x shl 17); return (x % 10000uL).toFloat() / 10000f }
    List(55) { floatArrayOf(next(), 0.8f + next() * 2.2f, 0.025f + next() * 0.04f, next(), 6f + next() * 14f) }
}

private fun DrawScope.glowAt(c: Color, alpha: Float, center: Offset, radius: Float) {
    drawRect(Brush.radialGradient(listOf(c.copy(alpha = alpha), Color.Transparent), center, radius.coerceAtLeast(1f)))
}

/** 方方之夜: soft, slowly drifting colour light */
@Composable
private fun NightBackground() {
    val t = drift("night", 0f, 1f, 14000)
    val blueEdge = T.blueEdge; val greenEdge = T.greenEdge; val oliveEdge = T.oliveEdge
    Canvas(Modifier.fillMaxSize()) {
        val w = size.width; val h = size.height; val m = max(w, 600f)
        fun lerp(a: Offset, b: Offset) = Offset(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
        glowAt(blueEdge, 0.30f, lerp(Offset(w * 0.25f, h * 0.15f), Offset(w * 0.75f, h * 0.28f)), m * 0.6f)
        glowAt(greenEdge, 0.26f, lerp(Offset(w * 0.8f, h * 0.75f), Offset(w * 0.3f, h * 0.9f)), m * 0.55f)
        glowAt(Color(0xFF7B3C9B), 0.20f, lerp(Offset(w * 0.6f, h * 0.5f), Offset(w * 0.4f, h * 0.45f)), m * 0.45f)
        glowAt(oliveEdge, 0.14f, lerp(Offset(w * 0.15f, h * 0.65f), Offset(w * 0.85f, h * 0.55f)), m * 0.38f)
    }
}

/** 女巫小屋: dusk sky into sooty wood, moonlight and candlelight, a crescent moon, stars, herbs, a toadstool, fireflies */
@Composable
private fun WitchBackground() {
    val drift = drift("witch", 0f, 1f, 8500)
    Canvas(Modifier.fillMaxSize()) {
        val w = size.width; val h = size.height; val d = density
        drawRect(Brush.verticalGradient(listOf(Color(0xFF231B29), Color(0xFF1E1815), Color(0xFF16110D))))
        glowAt(Color(0xFFCFC6FF), 0.13f, Offset(w * 0.92f, h * 0.04f), max(w, 300f) * 0.75f)
        glowAt(Color(0xFFFFAE55), 0.17f, Offset(w * 0.06f, h * 0.98f), max(w, 300f) * 0.95f)
        // crescent moon
        val mc = Offset(w - 58 * d, 96 * d); val r = 26 * d
        val moon = Path().apply { addOval(androidx.compose.ui.geometry.Rect(mc, r)) }
        val bite = Path().apply { addOval(androidx.compose.ui.geometry.Rect(Offset(mc.x + r * 0.45f, mc.y - r * 0.3f), r * 0.95f)) }
        val crescent = Path().apply { op(moon, bite, PathOperation.Difference) }
        glowAt(Color(0xFFF3E6C4), 0.12f, mc, r * 2.4f)
        drawPath(crescent, Color(0xFFF3E6C4).copy(alpha = 0.22f))
        for ((x, y, s) in listOf(Triple(0.62f, 0.05f, 9f), Triple(0.74f, 0.12f, 6f), Triple(0.55f, 0.14f, 5f), Triple(0.83f, 0.20f, 7f), Triple(0.70f, 0.26f, 4f), Triple(0.93f, 0.31f, 5f))) {
            drawSparkle(Offset(w * x, h * y), s * d * 0.6f, Color(0xFFFFF1C9).copy(alpha = 0.3f))
        }
        // herbs drying on a string, top left
        val herb = Color(0xFF8A9A52).copy(alpha = 0.22f)
        val top = Offset(24 * d, 6 * d); val knot = Offset(30 * d, 46 * d)
        drawLine(herb, top, knot, 2 * d, StrokeCap.Round)
        for ((i, a) in listOf(-0.5, -0.2, 0.1, 0.4).withIndex()) {
            val len = (82 - (i % 2) * 10) * d
            val end = Offset(knot.x + (sin(a) * len).toFloat(), knot.y + (cos(a) * len).toFloat())
            drawLine(herb, knot, end, 2 * d, StrokeCap.Round)
            for (k in 1..4) {
                val tt = k / 5f
                val base = Offset(knot.x + (end.x - knot.x) * tt, knot.y + (end.y - knot.y) * tt)
                val side = if (k % 2 == 0) 1 else -1
                val leaf = Path().apply { moveTo(base.x, base.y); quadraticTo(base.x + side * 8 * d, base.y - 2 * d, base.x + side * 9 * d, base.y + 6 * d) }
                drawPath(leaf, herb, style = Stroke(2 * d, cap = StrokeCap.Round))
            }
        }
        // a little toadstool
        drawToadstool(Offset(w - 86 * d, h - 66 * d), 34 * d, Color(0xFFC0563F).copy(alpha = 0.18f))
        // fireflies
        for ((x, y, dx, dy) in listOf(Q(0.12f, 0.62f, 30f, -24f), Q(0.30f, 0.80f, -26f, -18f), Q(0.48f, 0.70f, 22f, 26f), Q(0.70f, 0.86f, -30f, -12f),
            Q(0.86f, 0.66f, 18f, 30f), Q(0.22f, 0.45f, 24f, 20f), Q(0.78f, 0.48f, -22f, 18f), Q(0.58f, 0.93f, 26f, -22f))) {
            val p = Offset(w * x + dx * d * drift, h * y + dy * d * drift)
            glowAt(Color(0xFFFFC35A), 0.35f * (0.4f + drift * 0.6f), p, 9 * d)
            drawCircle(Color(0xFFFFD77D).copy(alpha = 0.25f + 0.5f * drift), 2 * d, p)
        }
    }
}

private data class Q(val a: Float, val b: Float, val c: Float, val d: Float)

private fun DrawScope.drawSparkle(c: Offset, r: Float, col: Color) {
    val p = Path().apply {
        moveTo(c.x, c.y - r * 2); quadraticTo(c.x, c.y, c.x + r * 2, c.y); quadraticTo(c.x, c.y, c.x, c.y + r * 2)
        quadraticTo(c.x, c.y, c.x - r * 2, c.y); quadraticTo(c.x, c.y, c.x, c.y - r * 2); close()
    }
    drawPath(p, col)
}

private fun DrawScope.drawToadstool(c: Offset, w: Float, col: Color) {
    val h = w * 0.9f
    val capBottom = c.y - h * 0.5f + h * 0.52f
    val cap = Path().apply {
        moveTo(c.x - w / 2, capBottom)
        quadraticTo(c.x, c.y - h / 2 - h * 0.5f, c.x + w / 2, capBottom); close()
    }
    drawPath(cap, col)
    drawRoundRect(col, Offset(c.x - w * 0.14f, capBottom - 1), Size(w * 0.28f, h * 0.48f), androidx.compose.ui.geometry.CornerRadius(4f))
}

private val spaceStars: List<FloatArray> = run {
    val out = ArrayList<FloatArray>()
    var x = 0x2545F4914F6CDD1DL
    fun next(): Float { x = x xor (x shl 13); x = x xor (x ushr 7); x = x xor (x shl 17); return ((x % 10000 + 10000) % 10000) / 10000f }
    for (i in 0 until 90) out.add(floatArrayOf(next(), next(), 0.5f + next() * 1.4f, if (i % 6 == 0) 1f else 0f))
    out
}

/** 星空: deep space with nebulas, twinkling stars, a ringed planet and a small moon */
@Composable
private fun SpaceBackground() {
    val tw = drift("space", 0.2f, 0.9f, 3000)
    Canvas(Modifier.fillMaxSize()) {
        val w = size.width; val h = size.height; val d = density
        drawRect(Brush.verticalGradient(listOf(Color(0xFF0D1024), Color(0xFF0A0C18), Color(0xFF07080F))))
        glowAt(Color(0xFF7A4CFF), 0.20f, Offset(w * 0.85f, h * 0.22f), max(w, 300f) * 0.7f)
        glowAt(Color(0xFF2FD3C0), 0.12f, Offset(w * 0.1f, h * 0.7f), max(w, 300f) * 0.8f)
        glowAt(Color(0xFFFF5CA8), 0.08f, Offset(w * 0.55f, h * 0.95f), max(w, 300f) * 0.6f)
        for (s in spaceStars) {
            val a = if (s[3] > 0) tw else 0.45f
            val p = Offset(w * s[0], h * s[1])
            if (s[3] > 0) glowAt(Color.White, 0.5f * tw, p, 4 * d)
            drawCircle(Color.White.copy(alpha = a), s[2] * d, p)
        }
        // a ringed planet, bottom right
        val pc = Offset(w - 50 * d, h - 150 * d)
        val ringW = 150 * d; val ringH = 40 * d
        rotate(-18f, pc) {
            drawOval(Color(0xFFFFD9A0).copy(alpha = 0.22f), Offset(pc.x - ringW / 2, pc.y - ringH / 2), Size(ringW, ringH), style = Stroke(5 * d))
        }
        drawCircle(Brush.radialGradient(listOf(Color(0xFFFFC28A), Color(0xFFB4507A), Color(0xFF3B2266)),
            Offset(pc.x - 14 * d, pc.y - 16 * d), 60 * d), 42 * d, pc, alpha = 0.32f)
        rotate(-18f, pc) {
            drawArc(Color(0xFFFFD9A0).copy(alpha = 0.26f), 0f, 180f, false, Offset(pc.x - ringW / 2, pc.y - ringH / 2), Size(ringW, ringH), style = Stroke(5 * d))
        }
        drawCircle(Brush.radialGradient(listOf(Color(0xFFC9D2FF), Color(0xFF6A74B8)), Offset(56 * d, 116 * d), 16 * d), 11 * d, Offset(60 * d, 120 * d), alpha = 0.35f)
    }
}

/** 苔蘚小窩: the forest floor: moss, ferns, toadstools, pebbles, a ladybug, a snail shell, a key, dewdrops */
@Composable
private fun GoblinBackground() {
    val glint = drift("goblin", 0.08f, 0.55f, 2600)
    Canvas(Modifier.fillMaxSize()) {
        val w = size.width; val h = size.height; val d = density
        drawRect(Brush.verticalGradient(listOf(Color(0xFF1C2016), Color(0xFF19190F), Color(0xFF15120C))))
        glowAt(Color(0xFF6F8F2A), 0.20f, Offset(w * 0.15f, h), max(w, 300f) * 0.7f)
        glowAt(Color(0xFF5C7D2B), 0.14f, Offset(w * 0.95f, h * 0.85f), max(w, 300f) * 0.55f)
        glowAt(Color(0xFF8AA53A), 0.08f, Offset(w * 0.7f, 0f), max(w, 300f) * 0.6f)
        // ferns along the sides
        val fern = Color(0xFF7A9A36)
        for (i in 0 until 3) {
            drawLeaf(Offset(18 * d + i * 10 * d, h * 0.32f + i * 46 * d), (46 - i * 8) * d / 2, 40f + i * 18f, fern.copy(alpha = 0.14f))
            drawLeaf(Offset(w - 18 * d - i * 10 * d, h * 0.18f + i * 44 * d), (40 - i * 7) * d / 2, -130f - i * 16f, fern.copy(alpha = 0.12f))
        }
        for ((x, s, c) in listOf(Triple(0.10f, 34f, 0xFFB5543C), Triple(0.17f, 22f, 0xFF9A7B4F), Triple(0.22f, 16f, 0xFFC0563F))) {
            drawToadstool(Offset(w * x, h - 52 * d - s * d * 0.3f), s * d, Color(c).copy(alpha = 0.22f))
        }
        for ((x, a, b) in listOf(Triple(0.42f, 18f, 10f), Triple(0.47f, 11f, 7f), Triple(0.80f, 15f, 9f), Triple(0.62f, 9f, 6f))) {
            drawOval(Color(0xFF8D8A7A).copy(alpha = 0.16f), Offset(w * x - a * d / 2, h - 40 * d - b * d / 2), Size(a * d, b * d))
        }
        // a ladybug
        val lb = Offset(w * 0.88f, h - 96 * d)
        drawCircle(Color(0xFFD0503C).copy(alpha = 0.3f), 7 * d, lb)
        drawCircle(Color(0xFF1A1410).copy(alpha = 0.3f), 3 * d, Offset(lb.x, lb.y - 6 * d))
        // a snail shell
        val sc = Offset(w * 0.70f, h - 64 * d)
        val spiral = Path()
        for (i in 0..90) {
            val t = i / 90.0; val a = t * 2.6 * 2 * PI; val rr = 12 * d * t
            val p = Offset(sc.x + (cos(a) * rr).toFloat(), sc.y + (sin(a) * rr).toFloat())
            if (i == 0) spiral.moveTo(p.x, p.y) else spiral.lineTo(p.x, p.y)
        }
        drawPath(spiral, Color(0xFFC9A46A).copy(alpha = 0.25f), style = Stroke(2.2f * d))
        // a key and a button
        val kc = Offset(w * 0.33f, h - 70 * d)
        translate(kc.x, kc.y) {
            rotate(30f, Offset.Zero) {
                val kcol = Color(0xFFD8B25A).copy(alpha = 0.26f)
                drawCircle(kcol, 4 * d, Offset(-6 * d, 0f), style = Stroke(1.8f * d))
                drawLine(kcol, Offset(-2 * d, 0f), Offset(8 * d, 0f), 1.8f * d)
                drawLine(kcol, Offset(6 * d, 0f), Offset(6 * d, 3 * d), 1.8f * d)
            }
        }
        drawCircle(Color(0xFFC78A6A).copy(alpha = 0.3f), 5 * d, Offset(w * 0.55f, h - 58 * d))
        // dewdrops catching the light
        for ((i, p) in listOf(0.25f to 0.86f, 0.58f to 0.78f, 0.84f to 0.9f, 0.12f to 0.55f, 0.9f to 0.42f).withIndex()) {
            val a = if (i % 2 == 0) glint else 0.63f - glint
            drawSparkle(Offset(w * p.first, h * p.second), 2.2f * d, Color(0xFFE8F2C8).copy(alpha = a))
        }
    }
}

private fun DrawScope.drawLeaf(c: Offset, r: Float, deg: Float, col: Color) {
    rotate(deg, c) {
        val p = Path().apply {
            moveTo(c.x, c.y - r); quadraticTo(c.x + r * 0.9f, c.y, c.x, c.y + r); quadraticTo(c.x - r * 0.9f, c.y, c.x, c.y - r); close()
        }
        drawPath(p, col)
    }
}


/** 夜櫻 (cherry petals drifting down past a blossoming branch) and 紅葉狩 (maple leaves falling over autumn hills) */
@Composable
private fun FallingThingsBackground(sakura: Boolean) {
    val moving = com.unoki99.fangfang.Prefs.themeMotion.value
    var time by androidx.compose.runtime.remember { androidx.compose.runtime.mutableFloatStateOf(0f) }
    if (moving) androidx.compose.runtime.LaunchedEffect(Unit) {
        val start = androidx.compose.runtime.withFrameNanos { it }
        while (true) androidx.compose.runtime.withFrameNanos { time = (it - start) / 1e9f }
    }
    Canvas(Modifier.fillMaxSize()) {
        val w = size.width; val h = size.height; val d = density
        drawRect(Brush.verticalGradient(if (sakura) listOf(Color(0xFF261A22), Color(0xFF1D1418), Color(0xFF150F12))
            else listOf(Color(0xFF2A1A12), Color(0xFF1C130F), Color(0xFF120C09))))
        glowAt(if (sakura) Color(0xFFFF9EC4) else Color(0xFFFF7A3A), 0.12f, Offset(w * 0.82f, h * 0.1f), max(w, 300f) * 0.6f)
        // a lantern-like moon
        val moon = Offset(w * 0.84f, 104 * d)
        drawCircle(Brush.radialGradient(if (sakura) listOf(Color(0xFFFFF4F8), Color(0xFFF3C9DA)) else listOf(Color(0xFFFFF0D8), Color(0xFFF2B77A)),
            Offset(moon.x - 3 * d, moon.y - 3 * d), 24 * d), 17 * d, moon, alpha = 0.35f)
        if (sakura) {
            // a branch with blossoms
            val br = Path().apply {
                moveTo(0f, 70 * d); quadraticTo(w * 0.3f, 80 * d, w * 0.55f, 150 * d)
                moveTo(w * 0.3f, 102 * d); quadraticTo(w * 0.4f, 90 * d, w * 0.42f, 60 * d)
            }
            drawPath(br, Color(0xFF6B4553).copy(alpha = 0.35f), style = Stroke(5 * d, cap = StrokeCap.Round))
            for (i in 0 until 9) drawCircle(Color(0xFFFFB7D0).copy(alpha = 0.18f), 9 * d, Offset(w * (0.05f + i * 0.055f), (72 + (i * 37) % 60) * d))
        } else {
            // autumn hills
            val hills = Path().apply {
                moveTo(0f, h - 110 * d)
                quadraticTo(w * 0.3f, h - 190 * d, w * 0.6f, h - 90 * d)
                quadraticTo(w * 0.85f, h - 170 * d, w, h - 120 * d)
                lineTo(w, h); lineTo(0f, h); close()
            }
            drawPath(hills, Brush.verticalGradient(listOf(Color(0xFFC0502A).copy(alpha = 0.18f), Color(0xFF7A2E18).copy(alpha = 0.10f)), h - 190 * d, h))
        }
        val colors = if (sakura) listOf(0xFFFFC4D8, 0xFFFFD9E6, 0xFFF7A8C4) else listOf(0xFFE4572E, 0xFFF08A24, 0xFFC0392B, 0xFFF2B134)
        for ((i, f) in fallingThings.withIndex()) {
            val p = (f[3] + time * f[2]) % 1f
            val y = p * (h + 30 * d) - 15 * d
            val x = f[0] * w + sin(time * 0.5f + f[3] * 6.28f) * f[4] * d
            translate(x, y) {
                rotate((time * f[5] + f[3] * 6.28f) * 57.3f, Offset.Zero) {
                    drawPath(if (sakura) petalPath(f[1] * d) else maplePath(f[1] * d * 1.3f), Color(colors[i % colors.size]).copy(alpha = if (sakura) 0.32f else 0.30f))
                }
            }
        }
    }
}

/** (x, size, speed, phase, sway, spin) of each petal or leaf: the same every time */
private val fallingThings: List<FloatArray> = run {
    var x = 0xC2B2AE3D27D4EB4FuL
    fun next(): Float { x = x xor (x shl 13); x = x xor (x shr 7); x = x xor (x shl 17); return (x % 10000uL).toFloat() / 10000f }
    List(34) { floatArrayOf(next(), 3f + next() * 5f, 0.018f + next() * 0.03f, next(), 10f + next() * 24f, next() * 2f - 1f) }
}
