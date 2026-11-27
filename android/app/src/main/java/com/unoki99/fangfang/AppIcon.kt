package com.unoki99.fangfang

import android.content.ComponentName
import android.content.pm.PackageManager

/** the home screen icon (設定 → 顏色與外觀 → App 圖示): 0 the usual dark one, 1 the light one (white, a black 方).
 *  Two launcher entries in the manifest (.LauncherDark, .LauncherLight); one is turned on. The launcher may take a
 *  moment to show the new one. (The computer version: its window icon, in Main.kt.) */
object AppIcon {
    fun set(light: Int) {
        Prefs.appIcon.value = light
        val ctx = Store.app
        val pm = ctx.packageManager
        val on = PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        val off = PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        try {
            pm.setComponentEnabledSetting(ComponentName(ctx, "com.unoki99.fangfang.LauncherLight"), if (light == 1) on else off, PackageManager.DONT_KILL_APP)
            pm.setComponentEnabledSetting(ComponentName(ctx, "com.unoki99.fangfang.LauncherDark"), if (light == 1) off else on, PackageManager.DONT_KILL_APP)
        } catch (_: Exception) {}
    }
}
