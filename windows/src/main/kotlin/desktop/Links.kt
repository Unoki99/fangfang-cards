package com.unoki99.fangfang.desktop

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import com.unoki99.fangfang.*
import com.unoki99.fangfang.engine.Lang
import com.unoki99.fangfang.ui.Sheet
import com.unoki99.fangfang.ui.UI
import java.awt.Frame
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentLinkedQueue
import javax.swing.SwingUtilities

/** fangfangcards:// links (the Firefox add-on's 傳到 App; Windows starts this program with the link), and keeping to
 *  one window: a second start hands its link to the first (through a local port) and ends. */
object Links {
    private const val PORT = 47613
    val pending = ConcurrentLinkedQueue<String>()
    var version by mutableIntStateOf(0)
    var window: Frame? = null

    /** true: this is the only one running (it listens for later starts); false: the link went to the one already open */
    fun firstOne(args: Array<String>): Boolean {
        val server = try { ServerSocket(PORT, 8, InetAddress.getLoopbackAddress()) } catch (_: Exception) { null }
        if (server == null) {
            try {
                Socket(InetAddress.getLoopbackAddress(), PORT).use { s ->
                    s.getOutputStream().write(((args.firstOrNull { it.startsWith("fangfangcards:") } ?: "show") + "\n").toByteArray(Charsets.UTF_8))
                }
                return false
            } catch (_: Exception) { return true }       // (the port's someone else's: just open)
        }
        Thread({
            while (true) {
                try {
                    server.accept().use { s ->
                        val line = s.getInputStream().bufferedReader(Charsets.UTF_8).readLine()?.trim().orEmpty()
                        SwingUtilities.invokeLater {
                            if (line.startsWith("fangfangcards:")) { pending.add(line); version++ }
                            window?.let { w -> w.isVisible = true; if (w.extendedState == Frame.ICONIFIED) w.extendedState = Frame.NORMAL; w.toFront(); w.requestFocus() }
                        }
                    }
                } catch (_: Exception) {}
            }
        }, "fangfang-links").apply { isDaemon = true }.start()
        return true
    }

    /** the links that came: their words in (as the Android app's MainActivity.takeLink) */
    fun takeAll() {
        while (true) {
            val s = pending.poll() ?: break
            val u = Uri.parse(s)
            if (u.host == "dict") {
                val l = u.getQueryParameter("lang")?.toIntOrNull()
                if (l != null && l != Store.lang && Store.loaded) Store.setLanguage(l)
                val w = u.getQueryParameter("word")
                if (!w.isNullOrEmpty()) UI.open(if (Lang.kind(w) == 0) Sheet.Word(w) else Sheet.ZhWord(w))
                continue
            }
            val n = BrowserImport.handle(u)
            if (n > 0) Note.text = tr("從瀏覽器查詞收到 {0} 個詞", n)
        }
    }
}
