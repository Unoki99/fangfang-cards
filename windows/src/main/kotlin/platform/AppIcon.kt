package com.unoki99.fangfang

/** the window's icon (設定 → 顏色與外觀 → App 圖示): Main.kt reads Prefs.appIcon, so it changes at once */
object AppIcon {
    fun set(light: Int) { Prefs.appIcon.value = light }
}
