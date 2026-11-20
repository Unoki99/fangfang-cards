package com.unoki99.fangfang.desktop

import com.unoki99.fangfang.YtLink
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

// YouTube 歌詞: what the browser add-on (連到方方詞卡（Windows）) says about the song playing on YouTube, heard on this
// computer only (127.0.0.1, port 47291: nothing from other computers reaches it). Only the add-on is answered: a
// request from a web page (an http(s) Origin) is turned away, so a website can't talk to the program. Each request:
// POST /now with the song (JSON) → the answer YtLink gives (what was pressed in the 歌詞 screen).
object YtServer {
    const val PORT = 47291

    fun start() {
        thread(isDaemon = true, name = "yt-link") {
            try {
                ServerSocket(PORT, 16, InetAddress.getByName("127.0.0.1")).use { ss ->
                    YtLink.available = true
                    while (true) {
                        val s = ss.accept()
                        thread(isDaemon = true) { try { handle(s) } catch (_: Exception) {} finally { try { s.close() } catch (_: Exception) {} } }
                    }
                }
            } catch (_: Exception) {
                // (the port taken: another copy of the program is open, or something else uses it)
                YtLink.available = false
            }
        }
    }

    private fun handle(s: Socket) {
        s.soTimeout = 3000
        val inp = BufferedInputStream(s.getInputStream())
        // the request line and the headers (up to a blank line)
        val head = ByteArrayOutputStream()
        var last4 = 0
        while (true) {
            val b = inp.read()
            if (b < 0) return
            head.write(b)
            last4 = (last4 shl 8) or b
            if (last4 == 0x0D0A0D0A) break
            if (head.size() > 16384) return
        }
        val lines = head.toString(Charsets.UTF_8.name()).split("\r\n")
        val first = lines.firstOrNull()?.split(" ") ?: return
        val method = first.getOrNull(0) ?: return
        val path = first.getOrNull(1) ?: return
        val headers = lines.drop(1).mapNotNull { l -> l.indexOf(':').takeIf { it > 0 }?.let { l.substring(0, it).trim().lowercase() to l.substring(it + 1).trim() } }.toMap()
        // (only the add-on: its requests come from moz-extension:// or chrome-extension://, a web page's from http(s)://)
        val origin = headers["origin"] ?: ""
        if (origin.startsWith("http://") || origin.startsWith("https://")) { reply(s, 403, "{}"); return }
        if (method == "OPTIONS") { reply(s, 204, ""); return }
        if (method != "POST" || path != "/now") { reply(s, 404, "{}"); return }
        val len = headers["content-length"]?.toIntOrNull() ?: 0
        if (len < 0 || len > 65536) { reply(s, 413, "{}"); return }
        val body = ByteArray(len)
        var got = 0
        while (got < len) { val n = inp.read(body, got, len - got); if (n < 0) break; got += n }
        reply(s, 200, YtLink.receive(String(body, 0, got, Charsets.UTF_8)))
    }

    private fun reply(s: Socket, code: Int, body: String) {
        val b = body.toByteArray(Charsets.UTF_8)
        val status = when (code) { 200 -> "OK"; 204 -> "No Content"; 403 -> "Forbidden"; 404 -> "Not Found"; else -> "Error" }
        val h = "HTTP/1.1 $code $status\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: ${b.size}\r\n" +
            "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n" +
            "Connection: close\r\n\r\n"
        val out = s.getOutputStream()
        out.write(h.toByteArray(Charsets.US_ASCII)); out.write(b); out.flush()
    }
}
