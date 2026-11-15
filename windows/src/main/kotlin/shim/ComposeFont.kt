// (Windows stand-in, see AndroidContent.kt) Android's Font(R.font.…): the same fonts, from the program's own files
package androidx.compose.ui.text.font

import com.unoki99.fangfang.desktop.DesktopRes

fun Font(resId: Int, weight: FontWeight = FontWeight.Normal, style: FontStyle = FontStyle.Normal): Font =
    androidx.compose.ui.text.platform.Font("font-$resId", DesktopRes.fontBytes(resId), weight, style)
