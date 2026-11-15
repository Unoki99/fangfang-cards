package com.unoki99.fangfang.desktop

import android.graphics.Typeface
import com.unoki99.fangfang.R

/** the fonts in the program (the Android app's res/font): 皓羅 letters, and 手寫練習's 文楷 and 芫荽 */
object DesktopRes {
    private fun file(id: Int) = when (id) {
        R.font.haolo -> "haolo.ttf"
        R.font.lxgw_wenkai_tc -> "lxgw_wenkai_tc.ttf"
        R.font.iansui -> "iansui.ttf"
        else -> "haolo.ttf"
    }
    private val bytes = HashMap<Int, ByteArray>()
    fun fontBytes(id: Int): ByteArray = synchronized(bytes) {
        bytes.getOrPut(id) { DesktopRes::class.java.getResourceAsStream("/" + file(id))?.use { it.readBytes() } ?: ByteArray(0) }
    }
    private val faces = HashMap<Int, Typeface>()
    fun typeface(id: Int): Typeface = synchronized(faces) { faces.getOrPut(id) { fontBytes(id).let { if (it.isEmpty()) Typeface.DEFAULT else Typeface.fromBytes(it) } } }

    private val skia = HashMap<Typeface, org.jetbrains.skia.Typeface?>()
    /** the same font for Skia (Compose's drawing); null: the system's */
    fun skiaTypeface(t: Typeface?): org.jetbrains.skia.Typeface? {
        val b = t?.bytes ?: return null
        return synchronized(skia) {
            skia.getOrPut(t) { try { org.jetbrains.skia.FontMgr.default.makeFromData(org.jetbrains.skia.Data.makeFromBytes(b)) } catch (_: Throwable) { null } }
        }
    }
}
