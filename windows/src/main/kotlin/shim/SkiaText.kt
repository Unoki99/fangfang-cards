// (Windows) 手寫練習's faint character, drawn with an android.graphics.Paint on the picture's own canvas: on Windows
// that canvas is Skia's, so the same call is made here with Skia's font and paint. In the shared code's package, so it
// needs no import there.
package com.unoki99.fangfang.ui

import com.unoki99.fangfang.desktop.DesktopRes

fun org.jetbrains.skia.Canvas.drawText(text: String, x: Float, y: Float, p: android.graphics.Paint) {
    val font = org.jetbrains.skia.Font(DesktopRes.skiaTypeface(p.typeface), p.textSize)
    val paint = org.jetbrains.skia.Paint().apply { color = p.color; isAntiAlias = true }
    drawString(text, x, y, font, paint)
}
