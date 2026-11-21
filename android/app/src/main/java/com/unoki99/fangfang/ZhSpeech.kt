package com.unoki99.fangfang

import kotlinx.coroutines.CompletableDeferred
import java.util.Locale

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
        } else if (com.unoki99.fangfang.engine.Lang.isJa) {
            // 日語: a Japanese voice
            if (t.setLanguage(Locale.JAPAN) in bad) {
                Store.speechHint = com.unoki99.fangfang.tr("這支手機還沒有日語的語音。到「設定 → 系統 → 語言 → 文字轉語音輸出」，在語音引擎的設定裡安裝「日語」的語音，再回來就可以聽了。")
                return true
            }
        } else {
        val loc = if (Prefs.zhPlace.value >= 1) Locale.CHINA else Locale.TAIWAN
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
