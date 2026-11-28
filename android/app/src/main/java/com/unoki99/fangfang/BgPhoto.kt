package com.unoki99.fangfang

import androidx.compose.ui.graphics.ImageBitmap

/** 背景照片: on the computer (BgPhoto.kt there); not on Android yet */
object BgPhoto {
    const val canPick = false
    val exists get() = false
    fun image(version: Int): ImageBitmap? = null
    fun pick(): Boolean = false
    fun remove() {}
}
