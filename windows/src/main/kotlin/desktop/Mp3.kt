package com.unoki99.fangfang.desktop

import java.io.BufferedInputStream
import java.io.InputStream
import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioSystem
import javax.sound.sampled.FloatControl
import javax.sound.sampled.SourceDataLine
import kotlin.math.log10

/** mp3 (a file or a radio stream) through Java Sound: decoded by the mp3 decoder in the program (mp3spi) and played
 *  on a thread of its own */
object Mp3 {
    class Playing {
        @Volatile var running = true
        @Volatile var stopped = false
        @Volatile var line: SourceDataLine? = null
        /** 0–1 */
        @Volatile var volume: Float = 1f
            set(v) { field = v; gain(line, v) }
        /** sound has started coming */
        @Volatile var sounding = false
        fun stop() { stopped = true; running = false; try { line?.stop(); line?.flush(); line?.close() } catch (_: Exception) {} }
    }

    private fun gain(line: SourceDataLine?, v: Float) {
        val l = line ?: return
        try {
            val c = l.getControl(FloatControl.Type.MASTER_GAIN) as FloatControl
            val db = if (v <= 0.001f) c.minimum else (20 * log10(v.toDouble())).toFloat()
            c.value = db.coerceIn(c.minimum, c.maximum)
        } catch (_: Exception) {}
    }

    fun play(input: InputStream, volume: Float, onEnd: () -> Unit = {}, onError: (Exception) -> Unit = {}): Playing {
        val p = Playing()
        p.volume = volume
        Thread({
            try {
                val src = AudioSystem.getAudioInputStream(if (input.markSupported()) input else BufferedInputStream(input, 1 shl 16))
                val base = src.format
                val fmt = AudioFormat(AudioFormat.Encoding.PCM_SIGNED, base.sampleRate, 16, base.channels, base.channels * 2, base.sampleRate, false)
                val pcm = AudioSystem.getAudioInputStream(fmt, src)
                val line = AudioSystem.getSourceDataLine(fmt)
                line.open(fmt)
                p.line = line
                gain(line, p.volume)
                line.start()
                val buf = ByteArray(8192)
                while (!p.stopped) {
                    val n = pcm.read(buf, 0, buf.size)
                    if (n < 0) break
                    if (n > 0) { line.write(buf, 0, n); p.sounding = true }
                }
                if (!p.stopped) line.drain()
                try { line.close() } catch (_: Exception) {}
                try { pcm.close(); src.close() } catch (_: Exception) {}
                p.running = false
                if (!p.stopped) onEnd()
            } catch (e: Exception) {
                p.running = false
                try { input.close() } catch (_: Exception) {}
                if (!p.stopped) onError(e)
            }
        }, "fangfang-mp3").apply { isDaemon = true }.start()
        return p
    }
}
