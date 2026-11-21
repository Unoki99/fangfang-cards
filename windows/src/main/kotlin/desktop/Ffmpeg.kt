package com.unoki99.fangfang.desktop

import com.unoki99.fangfang.RadioFormat
import java.io.File
import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioSystem

/** radio streams of every kind (HLS of every sort, Ogg Vorbis, Opus, FLAC, AAC in MP4…) through FFmpeg: it reads the
 *  stream and hands over plain sound (16-bit, 44.1 kHz, stereo), which plays through Java Sound. install-windows.bat
 *  downloads FFmpeg into %LOCALAPPDATA%\FangfangCards\ffmpeg; one on the PATH works too. */
object Ffmpeg {
    @Volatile private var found: File? = null
    @Volatile private var looked = 0L

    fun exe(): File? {
        found?.let { if (it.isFile) return it }
        val now = System.currentTimeMillis()
        if (now - looked < 30_000) return null
        looked = now
        val f = Os.find("ffmpeg", File(DesktopContext.base, "ffmpeg"))
        found = f
        return f
    }

    /** the format FFmpeg says the sound is ("Audio: aac (HE-AAC)", "Audio: mp3", "Audio: opus"…) */
    private fun formatOf(line: String): String? {
        val a = line.substringAfter("Audio:", "").trim().lowercase()
        if (a.isEmpty()) return null
        return when {
            a.startsWith("aac") -> if (a.contains("he-aac")) RadioFormat.AACP else RadioFormat.AAC
            a.startsWith("mp3") || a.startsWith("mp2") -> RadioFormat.MP3
            else -> RadioFormat.OTHER
        }
    }

    fun play(url: String, volume: Float, onFormat: (String) -> Unit, onTitle: (String) -> Unit, onError: (Exception) -> Unit): Mp3.Playing? {
        val exe = exe() ?: return null
        val net = url.startsWith("http")
        val cmd = mutableListOf(exe.path, "-nostdin", "-hide_banner", "-loglevel", "info")
        if (net) cmd += listOf("-user_agent", "FangfangCards/1.0", "-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "5")
        cmd += listOf("-i", url, "-vn", "-ac", "2", "-ar", "44100", "-f", "s16le", "pipe:1")
        val proc = try { ProcessBuilder(cmd).start() } catch (e: Exception) { onError(e); return null }
        val p = Mp3.Playing()
        p.volume = volume
        // what FFmpeg says: the format, and the song's name when the station sends one
        Thread({
            try {
                proc.errorStream.bufferedReader(Charsets.UTF_8).forEachLine { line ->
                    if (line.contains("Audio:")) formatOf(line)?.let(onFormat)
                    Regex("StreamTitle\\s*:\\s*(.+)").find(line)?.groupValues?.get(1)?.trim()?.let { t ->
                        if (t.isNotEmpty() && !t.lowercase().startsWith("http")) onTitle(t)
                    }
                }
            } catch (_: Exception) {}
        }, "fangfang-ffmpeg-log").apply { isDaemon = true }.start()
        Thread({
            val fmt = AudioFormat(44100f, 16, 2, true, false)
            try {
                val line = AudioSystem.getSourceDataLine(fmt)
                line.open(fmt)
                p.line = line
                p.volume = p.volume
                line.start()
                val buf = ByteArray(8192)
                val out = proc.inputStream
                while (!p.stopped) {
                    val n = out.read(buf)
                    if (n < 0) break
                    if (n > 0) { line.write(buf, 0, n - n % 4); p.sounding = true }
                }
                try { line.stop(); line.close() } catch (_: Exception) {}
                p.running = false
                if (!p.stopped) onError(Exception("FFmpeg stopped"))
            } catch (e: Exception) {
                p.running = false
                if (!p.stopped) onError(e)
            } finally {
                try { proc.destroy() } catch (_: Exception) {}
            }
        }, "fangfang-ffmpeg").apply { isDaemon = true }.start()
        // (stopping: FFmpeg ends too)
        p.onStop = { try { proc.destroy() } catch (_: Exception) {} }
        return p
    }
}
