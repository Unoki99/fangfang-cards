package com.unoki99.fangfang.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.withStyle
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.R
import com.unoki99.fangfang.engine.EngineSettings
import com.unoki99.fangfang.engine.Styled

/** 主題: 方方之夜 is the original look; 女巫小屋 a candle-lit witch's cottage; 星空 deep space; 苔蘚小窩 goblincore. */
enum class AppTheme(val raw: String, val title: String) {
    NIGHT("night", "方方之夜"), WITCH("witch", "女巫小屋"), SPACE("space", "星空"), GOBLIN("goblin", "苔蘚小窩"), WINTER("winter", "雪夜");

    val fontFamily: FontFamily get() = when (this) { WITCH -> FontFamily.Serif; else -> FontFamily.Default }

    companion object {
        fun of(s: String) = entries.firstOrNull { it.raw == s } ?: NIGHT
        val current: AppTheme get() = of(Prefs.theme.value)
    }
}

class Palette(
    val bg: Long, val key: Long, val keyEdge: Long, val fn: Long, val fnEdge: Long, val glyph: Long, val muted: Long,
    val blue: Long, val blueEdge: Long, val blueInk: Long, val green: Long, val greenEdge: Long, val greenInk: Long,
    val purpleInk: Long, val olive: Long, val oliveEdge: Long, val oliveInk: Long, val rust: Long, val rustEdge: Long,
    val rustInk: Long, val pink: Long, val guessInk: Long, val swapInk: Long, val pinkEdge: Long, val pinkInk: Long,
    val ownInk: Long, val own: Long, val ownEdge: Long,
)

private object P {
    val night = Palette(0x1c1c1e, 0x4a4a4c, 0x6d6d70, 0x2b2b2d, 0x4b4b4e, 0xf2f2f2, 0xa3a3a8, 0x34405e, 0x3d4f9c, 0xc8cfff, 0x44503a, 0x4f6c32, 0xd4efc0, 0xe3c6f7, 0x5a5238, 0x8c7a38, 0xf1e3ae, 0x5b4136, 0x8b4a2d, 0xf3c9b2, 0x5e3a4f, 0xff7a6e, 0xff9fd2, 0xa04a78, 0xf8cbe2, 0xc39bff, 0x4c3a5b, 0x7b3c9b)
    val witch = Palette(0x1b1611, 0x4a3b2c, 0x7d6242, 0x2a221b, 0x5a4630, 0xf4ead5, 0xb5a88d, 0x2e3550, 0x56609a, 0xdcd6ff, 0x3b4a31, 0x6e823d, 0xe0ecc2, 0xe9cff1, 0x5e4a2a, 0xab853c, 0xf7dfab, 0x5f3a29, 0xa0532f, 0xf6c8a6, 0x5a3442, 0xff7a6e, 0xff9fd2, 0x9e4f6e, 0xf7cee0, 0xcfa8ff, 0x4b3557, 0x8150a3)
    val space = Palette(0x0b0e1a, 0x262e4a, 0x46578a, 0x161b2e, 0x2f3a5e, 0xeef1ff, 0x9aa3c7, 0x1f2d5c, 0x3b5bd6, 0xc6d4ff, 0x1d4446, 0x2f8f86, 0xc4f5ec, 0xe2ccff, 0x4f4220, 0xc9a43a, 0xffe9a8, 0x56283a, 0xb0446a, 0xffc2d4, 0x4a2858, 0xff7a6e, 0xff9fd2, 0xa14fc2, 0xf3cdfc, 0xc8b4ff, 0x372d66, 0x7a5cff)
    val winter = Palette(0x10161f, 0x2e3b4d, 0x5b7290, 0x1a2330, 0x354659, 0xeef5ff, 0x9fb0c4, 0x24395a, 0x4f7fc0, 0xcfe2ff, 0x1f3b3a, 0x3f8a83, 0xc9f1ea, 0xdcd2fa, 0x3d4656, 0x8fa6c4, 0xe6eefb, 0x4a2f3a, 0x9a5a6e, 0xf6cdd8, 0x40304f, 0xff7a6e, 0xff9fd2, 0x8b5a9e, 0xf0d6f7, 0xc6b4ff, 0x35304f, 0x6f5fb0)
    val goblin = Palette(0x17170f, 0x3d3a24, 0x6e683a, 0x25261a, 0x4d4a2c, 0xeee8d2, 0xaaa58a, 0x2c3a3a, 0x4f7470, 0xcfe3dc, 0x34431f, 0x6b8a2e, 0xdcedb4, 0xdcc7e6, 0x4f4520, 0x9c8a34, 0xf0e2a2, 0x523222, 0x9a5a2c, 0xf1caa6, 0x4d3038, 0xff7a6e, 0xff9fd2, 0x8e5464, 0xf0cfd6, 0xc9b0e0, 0x3e3348, 0x75568a)
    val now: Palette
        get() = when (AppTheme.current) { AppTheme.NIGHT -> night; AppTheme.WITCH -> witch; AppTheme.SPACE -> space; AppTheme.GOBLIN -> goblin; AppTheme.WINTER -> winter }
}

fun hex(v: Long): Color = Color(0xFF000000 or v)
fun Color.argbInt(): Int = android.graphics.Color.argb((alpha * 255).toInt(), (red * 255).toInt(), (green * 255).toInt(), (blue * 255).toInt())

/** The app's colours (方方之夜 = the same as the 方方 website and Safari extension), in the chosen theme. */
object T {
    val bg get() = hex(P.now.bg)
    val key get() = hex(P.now.key)
    val keyEdge get() = hex(P.now.keyEdge)
    val fn get() = hex(P.now.fn)
    val fnEdge get() = hex(P.now.fnEdge)
    val glyph get() = hex(P.now.glyph)
    val muted get() = hex(P.now.muted)
    val blue get() = hex(P.now.blue)
    val blueEdge get() = hex(P.now.blueEdge)
    val blueInk get() = hex(P.now.blueInk)
    val green get() = hex(P.now.green)
    val greenEdge get() = hex(P.now.greenEdge)
    val greenInk get() = hex(P.now.greenInk)
    val purpleInk get() = hex(P.now.purpleInk)
    /** buttons (what used to be green): 華語 blue, 台語 purple */
    // 台語 purple, 華語 blue, 粵語 yellow
    val btn get() = when (com.unoki99.fangfang.Store.lang) { 3 -> hakFill; 2 -> olive; 1 -> blue; else -> own }
    val btnEdge get() = when (com.unoki99.fangfang.Store.lang) { 3 -> hakEdge; 2 -> oliveEdge; 1 -> blueEdge; else -> ownEdge }
    val btnInk get() = when (com.unoki99.fangfang.Store.lang) { 3 -> hakInk; 2 -> oliveInk; 1 -> blueInk; else -> purpleInk }
    /** 客語's orange (the same in every theme) */
    val hakFill = Color(0xFF5C3F1A); val hakEdge = Color(0xFFD9822B); val hakInk = Color(0xFFFFD29A)
    val olive get() = hex(P.now.olive)
    val oliveEdge get() = hex(P.now.oliveEdge)
    val oliveInk get() = hex(P.now.oliveInk)
    val rust get() = hex(P.now.rust)
    val rustEdge get() = hex(P.now.rustEdge)
    val rustInk get() = hex(P.now.rustInk)
    val pink get() = hex(P.now.pink)
    val guessInk get() = hex(P.now.guessInk)
    val swapInk get() = hex(P.now.swapInk)
    val pinkEdge get() = hex(P.now.pinkEdge)
    val pinkInk get() = hex(P.now.pinkInk)
    val ownInk get() = hex(P.now.ownInk)
    val own get() = hex(P.now.own)
    val ownEdge get() = hex(P.now.ownEdge)
    val placeFill = hex(0x4c3a5b)
    val placeEdge = hex(0x7b3c9b)

    /** 皓羅 / 台羅 / 白話字 text (DejaVu Sans subset, so the tone marks sit right) */
    val lat = FontFamily(Font(R.font.haolo))

    fun syncEngine() {
        EngineSettings.guessInk = guessInk.argbInt()
        EngineSettings.swapInk = swapInk.argbInt()
    }
}

val ROM_NAMES = listOf("皓羅", "台羅", "白話字")

/** the 10 places of the MOE dictionary's 語音差異, in the data's order (腔口 index = position) */
val PLACE_NAMES = listOf("鹿港偏泉腔", "三峽偏泉腔", "臺北偏泉腔", "宜蘭偏漳腔", "臺南混合腔",
    "高雄混合腔", "金門偏泉腔", "馬公偏泉腔", "新竹偏泉腔", "臺中偏漳腔")

object TextSize {
    val names = listOf("100%", "110%", "120%", "135%", "160%", "190%")
    val factors = listOf(1f, 1.1f, 1.2f, 1.35f, 1.6f, 1.9f)
    fun factor(level: Int) = factors[level.coerceIn(0, factors.size - 1)]
}

/** Styled text (from the engine) as text for the screen; coloured pieces glow a little when 聲調顏色 is on */
fun Styled.annotated(base: Color? = null, glow: Boolean = Prefs.toneSys.value != 0 && Prefs.toneGlow.value): AnnotatedString =
    buildAnnotatedString {
        for (s in this@annotated) {
            val c = s.c?.let { Color(it) }
            if (c != null) {
                withStyle(SpanStyle(color = c, shadow = if (glow) Shadow(c.copy(alpha = 0.85f), blurRadius = 12f) else null)) { append(s.t) }
            } else if (base != null) {
                withStyle(SpanStyle(color = base)) { append(s.t) }
            } else append(s.t)
        }
    }

@Composable
fun rememberAnnotated(s: Styled, base: Color? = null): AnnotatedString {
    val glow = Prefs.toneSys.value != 0 && Prefs.toneGlow.value
    return remember(s, base, glow) { s.annotated(base, glow) }
}
