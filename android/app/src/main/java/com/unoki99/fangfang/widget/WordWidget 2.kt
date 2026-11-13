package com.unoki99.fangfang.widget

import com.unoki99.fangfang.tr
import android.content.Context
import android.graphics.*
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.core.content.res.ResourcesCompat
import androidx.glance.*
import androidx.glance.ColorFilter
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.*
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.layout.*
import androidx.glance.unit.ColorProvider
import com.unoki99.fangfang.*
import com.unoki99.fangfang.R

/**
 * 分類詞卡: a word from the 分類 you pick, with its meaning, an example sentence, ▶, 收藏, ✓ and →.
 * A new word every hour. The texts are drawn as pictures, so they keep their tone colours and glow.
 */
class WordWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val widgetId = GlanceAppWidgetManager(context).getAppWidgetId(id)
        provideContent { WidgetContent(context, widgetId) }
    }

    companion object {
        suspend fun refreshAll(ctx: Context) { WordWidget().updateAll(ctx) }

        /** splitmix64: spreads the hour / → count over the whole list */
        fun mix(x0: Long): Long {
            var x = x0 + -0x61c8864680b583ebL
            x = (x xor (x ushr 30)) * -0x40a7b892e31b1a47L
            x = (x xor (x ushr 27)) * -0x6b2fb644ecceee15L
            return x xor (x ushr 31)
        }
    }
}

class WordWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = WordWidget()
}

private val KeyParam = ActionParameters.Key<String>("key")
private val PathParam = ActionParameters.Key<String>("path")

private const val BLUE_INK = 0xFFC8CFFF.toInt()
private const val GREEN_INK = 0xFFD4EFC0.toInt()
private const val PURPLE_INK = 0xFFE3C6F7.toInt()
private const val GLYPH = 0xFFF2F2F2.toInt()
private const val MUTED = 0xFFA3A3A8.toInt()
private const val OLIVE_INK = 0xFFF1E3AE.toInt()

@Composable
private fun WidgetContent(ctx: Context, widgetId: Int) {
    val size = LocalSize.current
    val density = ctx.resources.displayMetrics.density
    val cats = WidgetFiles.categories(ctx)
    val catID = WidgetFiles.category(ctx, widgetId) ?: cats.firstOrNull()?.i ?: -1
    val catName = cats.firstOrNull { it.i == catID }?.n ?: "常用詞"
    val st = WidgetFiles.state(ctx)
    val all = WidgetFiles.words(ctx, catID)
    val wPx = (size.width.value * density).toInt().coerceAtLeast(100)
    val hPx = (size.height.value * density).toInt().coerceAtLeast(100)

    if (all.isEmpty()) {
        Column(
            modifier = GlanceModifier.fillMaxSize().background(ImageProvider(background(wPx, hPx, density, st.bg, emptyList())))
                .clickable(actionStartActivity<MainActivity>()).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            textImage(ctx, null, "方方詞卡", GLYPH, 16f, wPx - (32 * density).toInt(), 1, bold = true)
            textImage(ctx, null, tr("打開方方詞卡一次，小工具就會載入詞。"), MUTED, 12f, wPx - (32 * density).toInt(), 3)
        }
        return
    }
    val known = WidgetFiles.knownNow(ctx)
    // 只顯示不熟的詞 (the 不熟 分類 are 不熟 words already)
    val unknownOnly = WidgetFiles.unknownOnly(ctx, widgetId) || catID == WidgetFiles.TW_UNKNOWN || catID == WidgetFiles.ZH_UNKNOWN
    val unknown = if (unknownOnly) WidgetFiles.unknownNow(ctx) else emptySet()
    if (unknownOnly && all.none { unknown.contains(it.k) }) {
        Column(
            modifier = GlanceModifier.fillMaxSize().background(ImageProvider(background(wPx, hPx, density, st.bg, emptyList())))
                .clickable(actionStartActivity<MainActivity>()).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            textImage(ctx, null, "方方詞卡", GLYPH, 16f, wPx - (32 * density).toInt(), 1, bold = true)
            textImage(ctx, null, tr("「{0}」現在沒有不熟的詞。", catName), MUTED, 12f, wPx - (32 * density).toInt(), 3)
        }
        return
    }
    val hourIndex = System.currentTimeMillis() / 3_600_000L
    val next = WidgetFiles.nextCount(ctx, widgetId)
    val slot = "$hourIndex|$next"
    val pinned = WidgetFiles.pinned(ctx, widgetId, slot)?.let { k -> all.firstOrNull { it.k == k } }
        ?.takeIf { !unknownOnly || unknown.contains(it.k) || known.contains(it.k) }
    val w = pinned ?: run {
        var pool = all.filter { !known.contains(it.k) && (!unknownOnly || unknown.contains(it.k)) }
        if (pool.isEmpty()) pool = all
        val n = WordWidget.mix(hourIndex * 0x9E3779B9L + catID * 0x85EBCA6BL + next * 0xC2B2AE35L)
        val pick = pool[((n % pool.size) + pool.size).toInt() % pool.size]
        WidgetFiles.pin(ctx, widgetId, slot, pick.k)
        pick
    }
    val saved = WidgetFiles.savedNow(ctx).contains(w.k)
    val isKnown = known.contains(w.k)
    val rom = st.rom.coerceIn(0, 2)
    val toneCols = (w.hc ?: emptyList()).mapNotNull { it.second }.distinct().map { parseHex(it) }
    val large = size.height.value > 250
    val pad = 14
    val inner = wPx - (2 * pad * density).toInt()
    val shadow = st.bg < 0.7

    Column(
        modifier = GlanceModifier.fillMaxSize().background(ImageProvider(background(wPx, hPx, density, st.bg, toneCols)))
            .clickable(actionStartActivity<MainActivity>()).padding(pad.dp),
    ) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                if (large) textImage(ctx, null, catName, OLIVE_INK, 11f, inner / 2, 1, bold = true, shadow = shadow)
                textImage(ctx, w.hc, w.h, BLUE_INK, if (large) 36f else 24f, inner - (150 * density).toInt(), 1, bold = true, shadow = shadow)
                textImage(ctx, w.rc?.getOrNull(rom), w.r.getOrElse(rom) { "" }, GREEN_INK, if (large) 19f else 14f, inner - (150 * density).toInt(), 1, latin = true, shadow = shadow)
                if (large) textImage(ctx, w.zc, w.z, PURPLE_INK, 14f, inner, 1, shadow = shadow)
            }
            Buttons(ctx, w, saved, isKnown, if (large) 34 else 30, density)
        }
        Spacer(GlanceModifier.height(4.dp))
        textImage(ctx, null, (if (w.p.isNotEmpty()) "〔${w.p}〕" else "") + w.m, GLYPH, if (large) 14f else 12f, inner, if (large) 3 else 1, shadow = shadow)
        if (w.xh != null) {
            Spacer(GlanceModifier.height(if (large) 10.dp else 4.dp))
            Row(verticalAlignment = Alignment.Top, modifier = GlanceModifier.fillMaxWidth()) {
                Column(modifier = GlanceModifier.defaultWeight()) {
                    textImage(ctx, w.xhc, w.xh, GLYPH, if (large) 15f else 12f, inner - (40 * density).toInt(), if (large) 2 else 1, shadow = shadow)
                    w.xr?.getOrNull(rom)?.let { textImage(ctx, w.xrc?.getOrNull(rom), it, GREEN_INK, if (large) 13f else 11f, inner - (40 * density).toInt(), if (large) 2 else 1, latin = true, shadow = shadow) }
                    w.xz?.let { textImage(ctx, null, it, MUTED, if (large) 12f else 10.5f, inner - (40 * density).toInt(), if (large) 2 else 1, shadow = shadow) }
                }
                if (large && w.xn != null) {
                    RoundButton(R.drawable.ic_play, 0x1AFFFFFF, 0x2EFFFFFF, GLYPH, 28, density,
                        actionRunCallback<PlayAction>(actionParametersOf(PathParam to com.unoki99.fangfang.engine.Audio.examplePath(w.xn))))
                }
            }
        }
    }
}

@Composable
private fun Buttons(ctx: Context, w: WidgetFiles.Word, saved: Boolean, known: Boolean, size: Int, density: Float) {
    val glass = 0x1AFFFFFF; val glassEdge = 0x2EFFFFFF
    Row {
        if (w.a != null) {
            RoundButton(R.drawable.ic_play, glass, glassEdge, GLYPH, size, density,
                actionRunCallback<PlayAction>(actionParametersOf(PathParam to com.unoki99.fangfang.engine.Audio.wordPath(w.a))))
            Spacer(GlanceModifier.width(5.dp))
        }
        RoundButton(if (saved) R.drawable.ic_bookmark_fill else R.drawable.ic_bookmark,
            if (saved) 0xFF5A5238.toInt() else glass, if (saved) 0xFF8C7A38.toInt() else glassEdge, if (saved) OLIVE_INK else GLYPH, size, density,
            actionRunCallback<SaveAction>(actionParametersOf(KeyParam to w.k)))
        Spacer(GlanceModifier.width(5.dp))
        RoundButton(R.drawable.ic_check,
            if (known) 0xFF5E3A4F.toInt() else glass, if (known) 0xFFA04A78.toInt() else glassEdge, if (known) 0xFFF8CBE2.toInt() else GLYPH, size, density,
            actionRunCallback<KnownAction>(actionParametersOf(KeyParam to w.k)))
        Spacer(GlanceModifier.width(5.dp))
        RoundButton(R.drawable.ic_arrow, glass, glassEdge, GLYPH, size, density, actionRunCallback<NextAction>())
    }
}

@Composable
private fun RoundButton(icon: Int, fill: Int, edge: Int, ink: Int, size: Int, density: Float, action: androidx.glance.action.Action) {
    Box(
        modifier = GlanceModifier.size(size.dp).background(ImageProvider(circle((size * density).toInt(), fill, edge, density))).clickable(action),
        contentAlignment = Alignment.Center,
    ) {
        Image(provider = ImageProvider(icon), contentDescription = null, modifier = GlanceModifier.size((size * 0.45f).dp),
            colorFilter = ColorFilter.tint(ColorProvider(Color(ink))))
    }
}

@Composable
private fun textImage(ctx: Context, segs: List<Pair<String, String?>>?, plain: String, ink: Int, sizeSp: Float, widthPx: Int, maxLines: Int,
                      latin: Boolean = false, bold: Boolean = false, shadow: Boolean = true) {
    if (plain.isEmpty()) return
    val bmp = textBitmap(ctx, segs, plain, ink, sizeSp, widthPx.coerceAtLeast(40), maxLines, latin, bold, shadow)
    val d = ctx.resources.displayMetrics.density
    Image(provider = ImageProvider(bmp), contentDescription = plain,
        modifier = GlanceModifier.width((bmp.width / d).dp).height((bmp.height / d).dp))
}

private fun parseHex(h: String): Int = (0xFF000000.toInt()) or (h.toIntOrNull(16) ?: 0xF2F2F2)

/** the text as a picture: each piece in its colour, a soft glow around coloured letters, a shadow for readability */
private fun textBitmap(ctx: Context, segs: List<Pair<String, String?>>?, plain: String, ink: Int, sizeSp: Float, widthPx: Int,
                       maxLines: Int, latin: Boolean, bold: Boolean, shadow: Boolean): Bitmap {
    val sb = SpannableStringBuilder()
    var glow = false
    if (segs.isNullOrEmpty()) sb.append(plain)
    else for ((t, c) in segs) {
        val st = sb.length
        sb.append(t)
        if (c != null) { sb.setSpan(ForegroundColorSpan(parseHex(c)), st, sb.length, 0); glow = true }
    }
    val paint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    paint.color = ink
    paint.textSize = sizeSp * ctx.resources.displayMetrics.scaledDensity
    paint.typeface = if (latin) (ResourcesCompat.getFont(ctx, R.font.haolo) ?: Typeface.DEFAULT) else if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
    val layout = StaticLayout.Builder.obtain(sb, 0, sb.length, paint, widthPx)
        .setAlignment(Layout.Alignment.ALIGN_NORMAL).setMaxLines(maxLines).setEllipsize(TextUtils.TruncateAt.END)
        .setIncludePad(true).build()
    var w = 1
    for (i in 0 until layout.lineCount) w = maxOf(w, Math.ceil(layout.getLineWidth(i).toDouble()).toInt())
    val padPx = (4 * ctx.resources.displayMetrics.density).toInt()
    val bmp = Bitmap.createBitmap(minOf(w + 2 * padPx, widthPx + 2 * padPx), layout.height + 2 * padPx, Bitmap.Config.ARGB_8888)
    val cv = Canvas(bmp)
    cv.translate(padPx.toFloat(), padPx.toFloat())
    if (glow) {
        val r = 2.2f * ctx.resources.displayMetrics.density
        for (i in 0 until 8) {
            val a = i * Math.PI / 4
            cv.save()
            cv.saveLayerAlpha(null, 46)
            cv.translate((r * Math.cos(a)).toFloat(), (r * Math.sin(a)).toFloat())
            layout.draw(cv)
            cv.restore()
            cv.restore()
        }
    }
    if (shadow) paint.setShadowLayer(3f, 0f, 1.5f, 0x8C000000.toInt())
    layout.draw(cv)
    return bmp
}

/** dark glass with a soft light from the word's tone colours and an edge in them */
private fun background(w: Int, h: Int, density: Float, bg: Double, cols: List<Int>): Bitmap {
    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val cv = Canvas(bmp)
    val r = 22 * density
    val rect = RectF(0f, 0f, w.toFloat(), h.toFloat())
    val path = Path().apply { addRoundRect(rect, r, r, Path.Direction.CW) }
    cv.clipPath(path)
    val a = bg.coerceIn(0.0, 1.0)
    val p = Paint(Paint.ANTI_ALIAS_FLAG)
    p.shader = LinearGradient(0f, 0f, w.toFloat(), h.toFloat(),
        Color(0.15f, 0.15f, 0.17f, a.toFloat()).toArgbInt(), Color(0.085f, 0.085f, 0.095f, minOf(1.0, a + 0.1).toFloat()).toArgbInt(), Shader.TileMode.CLAMP)
    cv.drawRect(rect, p)
    val cs = if (cols.isEmpty()) listOf(0xFF4B4B4E.toInt(), 0xFF4B4B4E.toInt()) else if (cols.size == 1) listOf(cols[0], cols[0]) else cols
    fun glow(cx: Float, cy: Float, c: Int, alpha: Float) {
        val q = Paint(Paint.ANTI_ALIAS_FLAG)
        q.shader = RadialGradient(cx, cy, 230 * density, (c and 0xFFFFFF) or ((alpha * 255).toInt() shl 24), c and 0xFFFFFF, Shader.TileMode.CLAMP)
        cv.drawRect(rect, q)
    }
    glow(0f, 0f, cs.first(), 0.22f)
    glow(w.toFloat(), h.toFloat(), cs.last(), 0.16f)
    val shine = Paint(Paint.ANTI_ALIAS_FLAG)
    shine.shader = LinearGradient(0f, 0f, 0f, h / 2f, 0x12FFFFFF, 0x00FFFFFF, Shader.TileMode.CLAMP)
    cv.drawRect(rect, shine)
    val edge = Paint(Paint.ANTI_ALIAS_FLAG)
    edge.style = Paint.Style.STROKE
    edge.strokeWidth = 2 * density
    edge.shader = LinearGradient(0f, 0f, w.toFloat(), 0f, cs.toIntArray(), null, Shader.TileMode.CLAMP)
    edge.alpha = 217
    val inset = density
    cv.drawRoundRect(RectF(inset, inset, w - inset, h - inset), r - inset, r - inset, edge)
    return bmp
}

private fun Color.toArgbInt(): Int = android.graphics.Color.argb((alpha * 255).toInt(), (red * 255).toInt(), (green * 255).toInt(), (blue * 255).toInt())

private fun circle(px: Int, fill: Int, edge: Int, density: Float): Bitmap {
    val bmp = Bitmap.createBitmap(px.coerceAtLeast(1), px.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
    val cv = Canvas(bmp)
    val p = Paint(Paint.ANTI_ALIAS_FLAG)
    p.color = fill
    cv.drawCircle(px / 2f, px / 2f, px / 2f - density, p)
    p.style = Paint.Style.STROKE; p.strokeWidth = 1.5f * density; p.color = edge
    cv.drawCircle(px / 2f, px / 2f, px / 2f - density, p)
    return bmp
}

// MARK: buttons

private fun prepare(ctx: Context) {
    Prefs.init(ctx.applicationContext)
    Store.init(ctx.applicationContext)
}

private suspend fun afterChange(ctx: Context, id: GlanceId) {
    if (Store.loaded) kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) { WidgetBridge.mergeInbox(); WidgetBridge.writeState() }
    WordWidget().update(ctx, id)
}

class PlayAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        prepare(context)
        val path = parameters[PathParam] ?: return
        Player.playAndWait(path)
    }
}

class SaveAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        prepare(context)
        WidgetFiles.toggleSaved(context, parameters[KeyParam] ?: return)
        afterChange(context, glanceId)
    }
}

class KnownAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        prepare(context)
        WidgetFiles.toggleKnown(context, parameters[KeyParam] ?: return)
        afterChange(context, glanceId)
    }
}

class NextAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val id = GlanceAppWidgetManager(context).getAppWidgetId(glanceId)
        WidgetFiles.bumpNext(context, id)
        WordWidget().update(context, glanceId)
    }
}
