package com.unoki99.fangfang

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.res.loadImageBitmap

/** the window's (and a Mac's Dock) icon (設定 → 顏色與外觀 → App 圖示): the dark one, the light one, and one for each
 *  theme. Main.kt reads Prefs.appIcon, so it changes at once */
object AppIcon {
    /** each one's name, and its picture in the app's files */
    val names = listOf("方方之夜", "淺色", "女巫小屋", "星空", "苔蘚小窩", "雪夜", "夜櫻", "紅葉狩")
    private val files = listOf("icon.png", "icon-light.png", "icon-witch.png", "icon-space.png", "icon-goblin.png",
        "icon-winter.png", "icon-sakura.png", "icon-momiji.png")
    fun file(i: Int) = files[i.coerceIn(0, files.size - 1)]
    private val cache = HashMap<Int, ImageBitmap?>()
    /** the icon's picture (for the choices in 設定, and the window) */
    fun preview(i: Int): ImageBitmap? = cache.getOrPut(i) {
        try { Thread.currentThread().contextClassLoader.getResourceAsStream(file(i))?.use { loadImageBitmap(it) } } catch (_: Exception) { null }
    }
    fun set(i: Int) {
        Prefs.appIcon.value = i
        // (a Mac: the Dock's icon too)
        try {
            if (java.awt.Taskbar.isTaskbarSupported() && java.awt.Taskbar.getTaskbar().isSupported(java.awt.Taskbar.Feature.ICON_IMAGE))
                Thread.currentThread().contextClassLoader.getResourceAsStream(file(i))?.use {
                    java.awt.Taskbar.getTaskbar().iconImage = javax.imageio.ImageIO.read(it)
                }
        } catch (_: Exception) {}
    }
}
