// (Windows stand-in, see AndroidContent.kt)
package androidx.core.content.res

import android.content.Context
import android.graphics.Typeface
import com.unoki99.fangfang.desktop.DesktopRes

object ResourcesCompat {
    @JvmStatic fun getFont(ctx: Context, id: Int): Typeface? = DesktopRes.typeface(id)
}
