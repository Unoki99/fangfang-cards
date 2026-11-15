// (Windows stand-ins, see AndroidContent.kt) Android's LocalContext and LocalConfiguration: the app's Context, and the
// window's size (Main.kt keeps it up to date)
package androidx.compose.ui.platform

import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.staticCompositionLocalOf
import com.unoki99.fangfang.desktop.DesktopContext

val LocalContext = staticCompositionLocalOf<android.content.Context> { DesktopContext }

class Configuration(@JvmField var screenWidthDp: Int = 1200, @JvmField var screenHeightDp: Int = 800) {
    val orientation: Int get() = if (screenWidthDp >= screenHeightDp) ORIENTATION_LANDSCAPE else ORIENTATION_PORTRAIT
    companion object {
        const val ORIENTATION_PORTRAIT = 1
        const val ORIENTATION_LANDSCAPE = 2
    }
}

val LocalConfiguration = compositionLocalOf { Configuration() }
