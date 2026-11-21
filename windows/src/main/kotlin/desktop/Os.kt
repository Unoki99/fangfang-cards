package com.unoki99.fangfang.desktop

import java.io.File

/** the computer the program runs on: Windows or a Mac (the same program on both) */
object Os {
    val mac: Boolean = System.getProperty("os.name", "").lowercase().contains("mac")
    /** the name the backup file and the messages use */
    val name: String get() = if (mac) "Mac" else "Windows"
    /** the installer to run again ("install-windows.bat" / "install-mac.command") */
    val installer: String get() = if (mac) "install-mac.command" else "install-windows.bat"

    /** a program (node, ffmpeg): in our own folder first, then on the PATH; on a Mac also where Homebrew puts them
     *  (a program opened from the Finder doesn't get the Terminal's PATH) */
    fun find(prog: String, own: File?): File? {
        val file = if (mac) prog else "$prog.exe"
        if (own != null && own.isDirectory) {
            val hits = own.walkTopDown().maxDepth(4).filter { it.isFile && it.name.equals(file, true) }.toList()
            // (a Node.js folder has more than one file called node: the one in bin/)
            (hits.firstOrNull { it.parentFile?.name == "bin" } ?: hits.firstOrNull())?.let { return it }
        }
        val dirs = (System.getenv("PATH") ?: "").split(File.pathSeparator) +
            if (mac) listOf("/opt/homebrew/bin", "/usr/local/bin") else emptyList()
        return dirs.filter { it.isNotBlank() }.map { File(it.trim('"'), file) }.firstOrNull { it.isFile }
    }
}
