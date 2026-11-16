package com.unoki99.fangfang.desktop

import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioSystem

// Radio streams that aren't plain mp3: AAC (sent as it is, "audio/aac"), and HLS (a playlist of short pieces, .ts or
// .aac, fetched one after another — many Taiwan stations send this). AAC is decoded with JAAD (in the program).

/** AAC (ADTS frames) to the speakers, like Mp3.play */
object Aac {
    fun play(input: InputStream, volume: Float, onEnd: () -> Unit = {}, onError: (Exception) -> Unit = {}): Mp3.Playing {
        val p = Mp3.Playing()
        p.volume = volume
        Thread({
            try {
                val adts = net.sourceforge.jaad.adts.ADTSDemultiplexer(input)
                val dec = net.sourceforge.jaad.aac.Decoder(adts.decoderSpecificInfo)
                val buf = net.sourceforge.jaad.aac.SampleBuffer()
                var line: javax.sound.sampled.SourceDataLine? = null
                while (!p.stopped) {
                    val frame = try { adts.readNextFrame() } catch (_: java.io.EOFException) { break }
                    try { dec.decodeFrame(frame, buf) } catch (_: Exception) { continue }
                    if (line == null) {
                        val fmt = AudioFormat(buf.sampleRate.toFloat(), buf.bitsPerSample, buf.channels, true, true)
                        line = AudioSystem.getSourceDataLine(fmt)
                        line.open(fmt)
                        p.line = line
                        p.volume = p.volume
                        line.start()
                    }
                    val b = buf.data
                    if (b.isNotEmpty()) { line.write(b, 0, b.size); p.sounding = true }
                }
                if (!p.stopped) line?.drain()
                try { line?.close() } catch (_: Exception) {}
                p.running = false
                if (!p.stopped) onEnd()
            } catch (e: Exception) {
                p.running = false
                if (!p.stopped) onError(e)
            } finally {
                try { input.close() } catch (_: Exception) {}
            }
        }, "fangfang-aac").apply { isDaemon = true }.start()
        return p
    }
}

/** an HLS stream as one stream of audio bytes (ADTS AAC or mp3): its pieces fetched in turn, the playlist read again
 *  for new ones; .ts pieces unpacked to their audio */
class HlsInput(private val playlistUrl: String) : InputStream() {
    @Volatile private var closed = false
    private var buf = ByteArray(0)
    private var pos = 0
    private val seen = HashSet<String>()
    private val queue = ArrayDeque<String>()
    private var media: String? = null
    private var target = 6000L
    private var lastLoad = 0L
    private var started = false

    private fun get(u: String): ByteArray {
        var url = URL(u)
        var hops = 0
        while (true) {
            val c = url.openConnection() as HttpURLConnection
            c.instanceFollowRedirects = false
            c.connectTimeout = 10000; c.readTimeout = 15000
            c.setRequestProperty("User-Agent", "FangfangCards/1.0")
            val code = c.responseCode
            if (code in 300..399 && hops < 6) { url = URL(url, c.getHeaderField("Location") ?: throw java.io.IOException("redirect")); hops++; c.disconnect(); continue }
            if (code !in 200..299) { c.disconnect(); throw java.io.IOException("HTTP $code") }
            return try { c.inputStream.use { it.readBytes() } } finally { c.disconnect() }
        }
    }

    /** the playlist: a list of streams (the first audio one is taken) or the pieces themselves */
    private fun load() {
        val base = media ?: playlistUrl
        val text = String(get(base), Charsets.UTF_8)
        lastLoad = System.currentTimeMillis()
        val lines = text.lines().map { it.trim() }
        if (lines.any { it.startsWith("#EXT-X-STREAM-INF") }) {
            // (the variants: the smallest bandwidth is enough for radio)
            var best: String? = null; var bestBw = Long.MAX_VALUE
            for (i in lines.indices) if (lines[i].startsWith("#EXT-X-STREAM-INF")) {
                val bw = Regex("BANDWIDTH=(\\d+)").find(lines[i])?.groupValues?.get(1)?.toLongOrNull() ?: Long.MAX_VALUE - 1
                val next = lines.drop(i + 1).firstOrNull { it.isNotEmpty() && !it.startsWith("#") } ?: continue
                if (bw < bestBw) { bestBw = bw; best = next }
            }
            media = URL(URL(base), best ?: throw java.io.IOException("no stream")).toString()
            load()
            return
        }
        Regex("#EXT-X-TARGETDURATION:(\\d+)").find(text)?.groupValues?.get(1)?.toLongOrNull()?.let { target = it * 1000 }
        val parts = lines.filter { it.isNotEmpty() && !it.startsWith("#") }.map { URL(URL(base), it).toString() }
        // (a live stream: start near its end, as players do)
        val fresh = parts.filter { it !in seen }
        val take = if (!started) fresh.takeLast(3) else fresh
        started = true
        for (p in parts) seen.add(p)
        queue.addAll(take)
    }

    private fun fill(): Boolean {
        while (!closed) {
            val next = queue.removeFirstOrNull()
            if (next != null) {
                val data = try { get(next) } catch (_: Exception) { continue }
                buf = audio(data); pos = 0
                if (buf.isNotEmpty()) return true
                continue
            }
            val wait = target / 2 - (System.currentTimeMillis() - lastLoad)
            if (wait > 0) Thread.sleep(minOf(wait, 3000))
            if (closed) return false
            try { load() } catch (e: Exception) { if (!started) throw e; Thread.sleep(1000) }
        }
        return false
    }

    override fun read(): Int {
        if (pos >= buf.size && !fill()) return -1
        return buf[pos++].toInt() and 0xff
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        if (len == 0) return 0
        if (pos >= buf.size && !fill()) return -1
        val n = minOf(len, buf.size - pos)
        System.arraycopy(buf, pos, b, off, n)
        pos += n
        return n
    }

    override fun close() { closed = true }

    companion object {
        /** a piece's audio: .ts unpacked; a leading ID3 tag (packed audio) skipped */
        fun audio(d: ByteArray): ByteArray {
            if (d.size >= 188 && d[0] == 0x47.toByte() && (d.size < 376 || d[188] == 0x47.toByte())) return ts(d)
            return skipId3(d)
        }

        private fun skipId3(d: ByteArray): ByteArray {
            var at = 0
            while (d.size - at > 10 && d[at] == 'I'.code.toByte() && d[at + 1] == 'D'.code.toByte() && d[at + 2] == '3'.code.toByte()) {
                val size = ((d[at + 6].toInt() and 0x7f) shl 21) or ((d[at + 7].toInt() and 0x7f) shl 14) or
                    ((d[at + 8].toInt() and 0x7f) shl 7) or (d[at + 9].toInt() and 0x7f)
                at += 10 + size
            }
            return if (at == 0) d else d.copyOfRange(minOf(at, d.size), d.size)
        }

        /** MPEG-TS: the audio stream's payloads (its PES headers taken off) */
        private fun ts(d: ByteArray): ByteArray {
            val out = java.io.ByteArrayOutputStream(d.size)
            var audioPid = -1
            var i = 0
            while (i + 188 <= d.size) {
                if (d[i] != 0x47.toByte()) { i++; continue }
                val pusi = (d[i + 1].toInt() and 0x40) != 0
                val pid = ((d[i + 1].toInt() and 0x1f) shl 8) or (d[i + 2].toInt() and 0xff)
                val afc = (d[i + 3].toInt() shr 4) and 3
                var p = i + 4
                if (afc == 2 || afc == 0) { i += 188; continue }
                if (afc == 3) p += 1 + (d[p].toInt() and 0xff)
                val end = i + 188
                if (p < end) {
                    if (pusi && end - p >= 9 && d[p] == 0.toByte() && d[p + 1] == 0.toByte() && d[p + 2] == 1.toByte()) {
                        val sid = d[p + 3].toInt() and 0xff
                        if (audioPid < 0 && sid in 0xC0..0xDF) audioPid = pid
                        if (pid == audioPid) {
                            val h = 9 + (d[p + 8].toInt() and 0xff)
                            if (p + h < end) out.write(d, p + h, end - p - h)
                        }
                    } else if (pid == audioPid) out.write(d, p, end - p)
                }
                i += 188
            }
            return out.toByteArray()
        }

        /** the first bytes of audio: AAC (ADTS) or mp3 */
        fun isAdts(head: ByteArray): Boolean {
            for (i in 0 until head.size - 1) if (head[i] == 0xFF.toByte()) {
                val b = head[i + 1].toInt() and 0xff
                if (b and 0xF0 == 0xF0 && (b shr 1) and 3 == 0) return true
                if (b and 0xE0 == 0xE0) return false
            }
            return false
        }
    }
}
