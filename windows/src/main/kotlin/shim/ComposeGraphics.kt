// (Windows stand-in, see AndroidContent.kt) a Compose picture as an android.graphics.Bitmap: the cards' falling-apart
// picture reads its colours this way
package androidx.compose.ui.graphics

fun ImageBitmap.asAndroidBitmap(): android.graphics.Bitmap = android.graphics.Bitmap(this.toAwtImage())
