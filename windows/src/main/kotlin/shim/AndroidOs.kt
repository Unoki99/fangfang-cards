// (Windows stand-ins, see AndroidContent.kt)
package android.os

object SystemClock {
    @JvmStatic fun uptimeMillis(): Long = System.nanoTime() / 1_000_000
    @JvmStatic fun elapsedRealtime(): Long = System.nanoTime() / 1_000_000
}

object Build {
    object VERSION {
        /** (not Android: the Android-only parts, like asking to show notifications, are skipped) */
        @JvmField val SDK_INT: Int = 0
    }
}
