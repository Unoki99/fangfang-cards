// (Windows stand-ins, see AndroidContent.kt)
package android.util

/** messages for finding problems: to the program's output (and the log file Main.kt keeps) */
object Log {
    @JvmStatic fun i(tag: String, msg: String): Int { println("[$tag] $msg"); return 0 }
    @JvmStatic fun d(tag: String, msg: String): Int { println("[$tag] $msg"); return 0 }
    @JvmStatic fun w(tag: String, msg: String): Int { System.err.println("[$tag] $msg"); return 0 }
    @JvmStatic fun w(tag: String, msg: String, tr: Throwable?): Int { System.err.println("[$tag] $msg: $tr"); return 0 }
    @JvmStatic fun e(tag: String, msg: String): Int { System.err.println("[$tag] $msg"); return 0 }
    @JvmStatic fun e(tag: String, msg: String, tr: Throwable?): Int { System.err.println("[$tag] $msg"); tr?.printStackTrace(); return 0 }
}
