package com.unoki99.fangfang

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import java.io.File

/** 背景照片 (設定 → 顏色與外觀): a photo from the computer behind the whole app, over the theme; how much of it shows.
 *  Kept in the app's own folder, at most 2048 pixels on its long side */
object BgPhoto {
    const val canPick = true
    private val file get() = File(Store.app.filesDir, "background.jpg")
    val exists get() = file.exists()
    private var cache: Pair<Int, ImageBitmap?>? = null
    /** the photo (read again when the version changes) */
    fun image(version: Int): ImageBitmap? {
        cache?.let { if (it.first == version) return it.second }
        val img = try { if (file.exists()) javax.imageio.ImageIO.read(file)?.toComposeImageBitmap() else null } catch (_: Exception) { null }
        cache = version to img
        return img
    }
    /** a photo picked on the computer: made smaller when it's big, and kept (false: none picked, or not a picture) */
    fun pick(): Boolean {
        val f = com.unoki99.fangfang.desktop.FilePick.open() ?: return false
        return try {
            val src = javax.imageio.ImageIO.read(f) ?: return false
            val side = maxOf(src.width, src.height); val most = 2048
            val k = if (side > most) most.toDouble() / side else 1.0
            val w = (src.width * k).toInt().coerceAtLeast(1); val h = (src.height * k).toInt().coerceAtLeast(1)
            val out = java.awt.image.BufferedImage(w, h, java.awt.image.BufferedImage.TYPE_INT_RGB)
            val g = out.createGraphics()
            g.setRenderingHint(java.awt.RenderingHints.KEY_INTERPOLATION, java.awt.RenderingHints.VALUE_INTERPOLATION_BICUBIC)
            g.drawImage(src, 0, 0, w, h, null); g.dispose()
            file.parentFile?.mkdirs()
            javax.imageio.ImageIO.write(out, "jpg", file)
        } catch (_: Exception) { false }
    }
    fun remove() { file.delete() }
}
