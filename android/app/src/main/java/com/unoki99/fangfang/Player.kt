package com.unoki99.fangfang

import android.media.AudioAttributes
import android.media.MediaPlayer
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.*
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** downloads a URL (GET, or POST with a form body) */
object Net {
    fun get(url: String, timeoutMs: Int = 20000): ByteArray {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = timeoutMs; c.readTimeout = timeoutMs
        try {
            if (c.responseCode != 200) throw java.io.IOException("HTTP ${c.responseCode}")
            return c.inputStream.use { it.readBytes() }
        } finally { c.disconnect() }
    }

    fun postForm(url: String, body: String, timeoutMs: Int = 20000): String {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = timeoutMs; c.readTimeout = timeoutMs
        c.requestMethod = "POST"; c.doOutput = true
        c.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=utf-8")
        try {
            c.outputStream.use { it.write(body.toByteArray()) }
            if (c.responseCode != 200) throw java.io.IOException("HTTP ${c.responseCode}")
            return c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
        } finally { c.disconnect() }
    }
}

/** plays an mp3 file; returns when it has finished (or was stopped) */
private suspend fun playFile(f: File, volume: Float, hold: (MediaPlayer) -> Unit) {
    val done = CompletableDeferred<Unit>()
    val mp = MediaPlayer()
    try {
        mp.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
        mp.setDataSource(f.absolutePath)
        mp.setVolume(volume, volume)
        mp.setOnCompletionListener { done.complete(Unit) }
        mp.setOnErrorListener { _, _, _ -> done.complete(Unit); true }
        withContext(Dispatchers.IO) { mp.prepare() }
        hold(mp)
        mp.start()
        done.await()
    } finally {
        try { mp.release() } catch (_: Exception) {}
    }
}

/** 華語 read aloud with the device's text-to-speech (臺灣 or 大陸 voice, as chosen) */
object ZhSpeech {
    private var tts: android.speech.tts.TextToSpeech? = null
    private var ready: CompletableDeferred<Boolean>? = null
    private val waiting = java.util.concurrent.ConcurrentHashMap<String, CompletableDeferred<Unit>>()
    private var n = 0

    private suspend fun engine(): android.speech.tts.TextToSpeech? {
        val r = ready ?: CompletableDeferred<Boolean>().also { d ->
            ready = d
            tts = android.speech.tts.TextToSpeech(Store.app) { status -> d.complete(status == android.speech.tts.TextToSpeech.SUCCESS) }
            tts?.setOnUtteranceProgressListener(object : android.speech.tts.UtteranceProgressListener() {
                override fun onStart(id: String?) {}
                override fun onDone(id: String?) { id?.let { waiting.remove(it)?.complete(Unit) } }
                @Deprecated("old API") override fun onError(id: String?) { id?.let { waiting.remove(it)?.complete(Unit) } }
                override fun onStop(id: String?, interrupted: Boolean) { id?.let { waiting.remove(it)?.complete(Unit) } }
            })
        }
        return if (r.await()) tts else null
    }

    /** speaks the text; false when the device has no Chinese voice */
    suspend fun speakAndWait(text: String): Boolean {
        val t = engine() ?: return false
        val bad = listOf(android.speech.tts.TextToSpeech.LANG_MISSING_DATA, android.speech.tts.TextToSpeech.LANG_NOT_SUPPORTED)
        if (Store.isYue) {
            // 粵語: a Cantonese (香港) voice; none: say how to get one (instead of reading it in 華語)
            val got = listOf(Locale("yue", "HK"), Locale("zh", "HK")).any { t.setLanguage(it) !in bad }
            if (!got) {
                Store.speechHint = com.unoki99.fangfang.tr("這支手機還沒有粵語的語音。到「設定 → 系統 → 語言 → 文字轉語音輸出」，在語音引擎的設定裡安裝「粵語（香港）」的語音，再回來就可以聽了。")
                return true
            }
        } else {
        val loc = if (Prefs.zhPlace.value == 1) Locale.CHINA else Locale.TAIWAN
        val ok = t.setLanguage(loc)
        if (ok in bad) {
            val o2 = t.setLanguage(Locale.CHINESE)
            if (o2 in bad) return false
        }
        }
        t.setSpeechRate(0.9f)
        val id = "zh" + (++n)
        val done = CompletableDeferred<Unit>()
        waiting[id] = done
        val params = android.os.Bundle().apply { putFloat(android.speech.tts.TextToSpeech.Engine.KEY_PARAM_VOLUME, Prefs.volume.value) }
        if (t.speak(text, android.speech.tts.TextToSpeech.QUEUE_FLUSH, params, id) != android.speech.tts.TextToSpeech.SUCCESS) {
            waiting.remove(id); return false
        }
        try { done.await() } finally { waiting.remove(id) }
        return true
    }

    fun stop() { try { tts?.stop() } catch (_: Exception) {} }
}

/** Plays MOE recordings from the 方方 website; every clip played once is kept for offline use. */
object Player {
    var playing by mutableStateOf<String?>(null); private set
    var failed by mutableStateOf<String?>(null); private set
    private val scope = MainScope()
    private var job: Job? = null
    private var current: MediaPlayer? = null

    private val cacheDir: File get() = File(Store.app.cacheDir, "audio").apply { mkdirs() }

    fun play(path: String) {
        // (客語: no voice to read it)
        if (path.isEmpty() || (com.unoki99.fangfang.engine.Lang.isHak && path.startsWith("tts:"))) return
        stop()
        playing = path; failed = null
        job = scope.launch {
            try {
                if (path.startsWith("tts:")) {
                    // 華語: the device's own voice
                    if (!ZhSpeech.speakAndWait(path.removePrefix("tts:"))) throw java.io.IOException("no voice")
                    if (playing == path) playing = null
                    return@launch
                }
                val f = load(path)
                playFile(f, Prefs.volume.value) { current = it }
                if (playing == path) playing = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (playing == path) { playing = null; failed = path }
            }
            current = null
        }
    }

    fun stop() {
        job?.cancel()
        try { current?.stop() } catch (_: Exception) {}
        ZhSpeech.stop()
        current = null
        playing = null
    }

    suspend fun load(path: String): File = withContext(Dispatchers.IO) {
        // a whole web address (粵語 recordings on Wikimedia Commons) or a file of the 台語 recordings
        val web = path.startsWith("https://")
        val f = File(cacheDir, (if (web) "web-" + path.substringAfterLast('/') else path.replace("/", "_")).takeLast(200))
        if (f.exists() && f.length() > 0) return@withContext f
        val data = if (web) Net.get(path) else {
            val base = Prefs.audioBase.value.let { if (it.endsWith("/")) it else "$it/" }
            val enc = path.split("/").joinToString("/") { URLEncoder.encode(it, "UTF-8").replace("+", "%20").replace("%28", "(").replace("%29", ")") }
            Net.get(base + enc)
        }
        if (data.isEmpty()) throw java.io.IOException("empty")
        f.writeBytes(data)
        f
    }

    /** for the widget's ▶: plays and waits until the recording has finished */
    suspend fun playAndWait(path: String) {
        withContext(Dispatchers.Main) { stop() }
        if (path.startsWith("tts:")) { withContext(Dispatchers.Main) { ZhSpeech.speakAndWait(path.removePrefix("tts:")) }; return }
        try {
            val f = load(path)
            withContext(Dispatchers.Main) { playFile(f, Prefs.volume.value) { current = it } }
        } catch (_: Exception) {}
    }

    fun clearCache() { cacheDir.deleteRecursively() }
}

/**
 * 轉換 read aloud with 鬥拍字 (意傳科技, suisiann.ithuan.tw). The voice is their online service; nothing of it is
 * included in this app. Clips are kept for the day only.
 */
object TaigiSpeech {
    enum class Phase { IDLE, LOADING, PLAYING, FAILED }
    var phase by mutableStateOf(Phase.IDLE); private set
    var text by mutableStateOf<String?>(null); private set
    private val scope = MainScope()
    private var job: Job? = null
    private var current: MediaPlayer? = null
    const val credit = "意傳科技《鬥拍字》台語語音合成（suisiann.ithuan.tw），連線使用，語音不包含在本 App 裡。"

    fun phaseFor(t: String) = if (text == t) phase else Phase.IDLE

    fun toggle(t: String) { if (text == t && (phase == Phase.LOADING || phase == Phase.PLAYING)) stop() else speak(t) }

    fun stop() {
        job?.cancel()
        try { current?.stop() } catch (_: Exception) {}
        phase = Phase.IDLE; text = null
    }

    fun speak(t: String) {
        val parts = chunks(t)
        if (parts.isEmpty()) return
        stop()
        text = t; phase = Phase.LOADING
        job = scope.launch {
            try {
                var next: Deferred<File>? = async(Dispatchers.IO) { audio(parts[0]) }
                for (i in parts.indices) {
                    val f = next?.await() ?: break
                    next = if (i + 1 < parts.size) async(Dispatchers.IO) { audio(parts[i + 1]) } else null
                    phase = Phase.PLAYING
                    playFile(f, Prefs.volume.value) { current = it }
                }
                phase = Phase.IDLE; text = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                phase = Phase.FAILED
                delay(2000)
                phase = Phase.IDLE; text = null
            }
        }
    }

    /** sentences, and long sentences cut at commas or every 28 syllables */
    fun chunks(s: String): List<String> {
        val sentences = ArrayList<String>()
        val cur = StringBuilder()
        for (ch in s) {
            cur.append(ch)
            if ("。！？!?；;\n.".contains(ch)) { sentences.add(cur.toString()); cur.setLength(0) }
        }
        sentences.add(cur.toString())
        fun syllables(x: String) = x.split(' ', '-', '\t', '\n').count { w -> w.any { it.isLetter() } }
        val limit = 28
        val out = ArrayList<String>()
        for (sen in sentences) {
            val t = sen.trim()
            if (!t.any { it.isLetter() }) continue
            if (syllables(t) <= limit) { out.add(t); continue }
            val parts = ArrayList<String>(); val p = StringBuilder()
            for (ch in t) { p.append(ch); if ("，,、：:".contains(ch)) { parts.add(p.toString()); p.setLength(0) } }
            parts.add(p.toString())
            var acc = ""
            for (part in parts) {
                if (acc.isNotEmpty() && syllables(acc + part) > limit) { out.add(acc); acc = "" }
                acc += part
                while (syllables(acc) > limit) {
                    val words = acc.split(' ').filter { it.isNotEmpty() }
                    var head = ""; var n = 0; var k = 0
                    while (k < words.size && (n + syllables(words[k]) <= limit || head.isEmpty())) {
                        head += (if (head.isEmpty()) "" else " ") + words[k]; n += syllables(words[k]); k++
                    }
                    out.add(head)
                    acc = words.drop(k).joinToString(" ")
                }
            }
            if (acc.any { it.isLetter() }) out.add(acc.trim())
        }
        return out.filter { it.isNotEmpty() }
    }

    private val rootDir: File get() = File(Store.app.cacheDir, "tts")
    private val cacheDir: File
        get() {
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            return File(rootDir, today).apply { mkdirs() }
        }

    fun dropOldDays() {
        val keep = cacheDir.name
        rootDir.listFiles()?.forEach { if (it.name != keep) it.deleteRecursively() }
    }

    private fun audio(piece: String): File {
        dropOldDays()
        val name = MessageDigest.getInstance("SHA-256").digest(piece.toByteArray()).joinToString("") { "%02x".format(it) }
        val f = File(cacheDir, "$name.mp3")
        if (f.exists() && f.length() > 0) return f
        val direct = try { bangtsam(piece) } catch (_: Exception) { null }
        if (direct != null) { f.writeBytes(direct); return f }
        var kip = piece
        try {
            val r = Net.postForm("https://hokbu.ithuan.tw/tau", "taibun=" + URLEncoder.encode(piece, "UTF-8"))
            val obj = com.unoki99.fangfang.engine.JReader(r).any() as? Map<*, *>
            (obj?.get("KIP") as? String)?.takeIf { it.isNotEmpty() }?.let { kip = it }
        } catch (_: Exception) {}
        val data = bangtsam(kip)
        f.writeBytes(data)
        return f
    }

    private fun bangtsam(taibun: String): ByteArray {
        val data = Net.get("https://hapsing.ithuan.tw/bangtsam?taibun=" + URLEncoder.encode(taibun, "UTF-8").replace("+", "%20"), 30000)
        if (data.size <= 200) throw java.io.IOException("short")
        return data
    }
}
