// Windows stand-ins for android.graphics (see AndroidContent.kt), drawn with Java2D: what 手寫練習 uses to see how
// closely the writing follows the character (a small picture of the character and of the writing, compared), and the
// cards' falling-apart picture.
package android.graphics

import java.awt.BasicStroke
import java.awt.RenderingHints
import java.awt.font.FontRenderContext
import java.awt.geom.Ellipse2D
import java.awt.geom.Line2D
import java.awt.image.BufferedImage
import kotlin.math.ceil
import kotlin.math.floor

object Color {
    const val WHITE: Int = -1
    const val BLACK: Int = -0x1000000
    const val TRANSPARENT: Int = 0
    @JvmStatic fun argb(a: Int, r: Int, g: Int, b: Int): Int = (a and 0xff shl 24) or (r and 0xff shl 16) or (g and 0xff shl 8) or (b and 0xff)
    @JvmStatic fun rgb(r: Int, g: Int, b: Int): Int = argb(255, r, g, b)
}

/** a font: Java2D's (to measure and draw into pictures) and its bytes (for Compose's own drawing, Skia) */
class Typeface(val awt: java.awt.Font?, val bytes: ByteArray?) {
    companion object {
        @JvmField val DEFAULT = Typeface(java.awt.Font(java.awt.Font.SANS_SERIF, java.awt.Font.PLAIN, 12), null)
        fun fromBytes(b: ByteArray): Typeface = try {
            Typeface(java.awt.Font.createFont(java.awt.Font.TRUETYPE_FONT, b.inputStream()), b)
        } catch (_: Exception) { DEFAULT }
    }
}

class Rect(@JvmField var left: Int = 0, @JvmField var top: Int = 0, @JvmField var right: Int = 0, @JvmField var bottom: Int = 0) {
    fun width() = right - left
    fun height() = bottom - top
}

class Paint(flags: Int = 0) {
    enum class Style { FILL, STROKE, FILL_AND_STROKE }
    enum class Cap { BUTT, ROUND, SQUARE }
    enum class Join { MITER, ROUND, BEVEL }

    var isAntiAlias = flags and ANTI_ALIAS_FLAG != 0
    var typeface: Typeface? = null
    var color: Int = Color.BLACK
    var textSize: Float = 12f
    var style: Style = Style.FILL
    var strokeWidth: Float = 0f
    var strokeCap: Cap = Cap.BUTT
    var strokeJoin: Join = Join.MITER

    fun awtFont(): java.awt.Font = (typeface?.awt ?: Typeface.DEFAULT.awt!!).deriveFont(textSize)

    /** the ink's bounds of the text, from its start on the baseline (as Android measures them) */
    fun getTextBounds(text: String, start: Int, end: Int, bounds: Rect) {
        val gv = awtFont().createGlyphVector(FontRenderContext(null, true, true), text.substring(start, end))
        val r = gv.visualBounds
        bounds.left = floor(r.x).toInt(); bounds.top = floor(r.y).toInt()
        bounds.right = ceil(r.x + r.width).toInt(); bounds.bottom = ceil(r.y + r.height).toInt()
    }

    fun measureText(text: String): Float =
        awtFont().getStringBounds(text, FontRenderContext(null, true, true)).width.toFloat()

    companion object {
        const val ANTI_ALIAS_FLAG = 1
    }
}

class Bitmap(val img: BufferedImage) {
    enum class Config { ALPHA_8, RGB_565, ARGB_4444, ARGB_8888, HARDWARE }
    val config: Config get() = Config.ARGB_8888
    val width: Int get() = img.width
    val height: Int get() = img.height

    fun copy(c: Config, mutable: Boolean): Bitmap {
        val out = BufferedImage(img.width, img.height, BufferedImage.TYPE_INT_ARGB)
        out.createGraphics().apply { drawImage(img, 0, 0, null); dispose() }
        return Bitmap(out)
    }

    fun getPixels(px: IntArray, offset: Int, stride: Int, x: Int, y: Int, w: Int, h: Int) {
        img.getRGB(x, y, w, h, px, offset, stride)
    }

    companion object {
        @JvmStatic fun createBitmap(w: Int, h: Int, c: Config): Bitmap = Bitmap(BufferedImage(maxOf(1, w), maxOf(1, h), BufferedImage.TYPE_INT_ARGB))
        @JvmStatic fun createScaledBitmap(src: Bitmap, w: Int, h: Int, filter: Boolean): Bitmap {
            val out = BufferedImage(maxOf(1, w), maxOf(1, h), BufferedImage.TYPE_INT_ARGB)
            val g = out.createGraphics()
            if (filter) g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
            g.drawImage(src.img, 0, 0, out.width, out.height, null)
            g.dispose()
            return Bitmap(out)
        }
    }
}

class Canvas(private val bmp: Bitmap) {
    private fun g(p: Paint): java.awt.Graphics2D {
        val g = bmp.img.createGraphics()
        if (p.isAntiAlias) {
            g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
            g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON)
        }
        g.color = java.awt.Color(p.color, true)
        val cap = when (p.strokeCap) { Paint.Cap.ROUND -> BasicStroke.CAP_ROUND; Paint.Cap.SQUARE -> BasicStroke.CAP_SQUARE; else -> BasicStroke.CAP_BUTT }
        val join = when (p.strokeJoin) { Paint.Join.ROUND -> BasicStroke.JOIN_ROUND; Paint.Join.BEVEL -> BasicStroke.JOIN_BEVEL; else -> BasicStroke.JOIN_MITER }
        g.stroke = BasicStroke(maxOf(p.strokeWidth, 1f), cap, join)
        return g
    }

    fun drawText(text: String, x: Float, y: Float, p: Paint) {
        val g = g(p); g.font = p.awtFont(); g.drawString(text, x, y); g.dispose()
    }

    fun drawLine(x1: Float, y1: Float, x2: Float, y2: Float, p: Paint) {
        val g = g(p); g.draw(Line2D.Float(x1, y1, x2, y2)); g.dispose()
    }

    fun drawPoint(x: Float, y: Float, p: Paint) {
        val g = g(p)
        val d = maxOf(p.strokeWidth, 1f)
        g.fill(Ellipse2D.Float(x - d / 2, y - d / 2, d, d))
        g.dispose()
    }
}
