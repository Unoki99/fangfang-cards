package com.unoki99.fangfang

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** (Windows, Mac) 華語 (and 粵語, 日語) read aloud with the computer's own voices (a Mac: the say command; Windows (System.Speech, through PowerShell): 臺灣 or 大陸
 *  as chosen. Without a voice for the language, it says how to add one in Windows' settings. */
object ZhSpeech {
    @Volatile private var proc: Process? = null

    private fun hint(lang: String) = com.unoki99.fangfang.tr(
        "這台電腦還沒有{0}的語音。到 Windows 的「設定 → 時間與語言 → 語音」，在「管理語音」按「新增語音」，加上{0}的語音，再回來就可以聽了。", lang)

    private fun macHint(lang: String) = com.unoki99.fangfang.tr(
        "這台 Mac 還沒有{0}的語音。到「系統設定 → 輔助使用 → 朗讀內容 → 系統語音 → 管理語音」，加上{0}的語音（例如美佳、婷婷、善怡、Kyoko），再回來就可以聽了。", lang)

    /** (a Mac) the voices it has: name → language ("Meijia" → "zh_TW"), from say -v ? */
    @Volatile private var macVoices: List<Pair<String, String>>? = null
    private fun voices(): List<Pair<String, String>> {
        macVoices?.let { return it }
        val out = try {
            val p = ProcessBuilder("say", "-v", "?").redirectErrorStream(true).start()
            p.inputStream.bufferedReader(Charsets.UTF_8).readLines().mapNotNull { l ->
                // "Meijia              zh_TW    # 你好…" (a name may have spaces: "Sin-ji", "Tingting (Enhanced)")
                val m = Regex("^(.+?)\\s+([a-z]{2}[_-][A-Z]{2})\\s+#").find(l) ?: return@mapNotNull null
                m.groupValues[1].trim() to m.groupValues[2].replace('-', '_')
            }.also { p.waitFor() }
        } catch (_: Exception) { emptyList() }
        macVoices = out
        return out
    }

    /** a Mac: with its own voices (the say command) */
    private suspend fun speakMac(text: String, cultures: List<String>, name: String): Boolean {
        val vs = voices()
        val voice = cultures.map { it.replace('-', '_') }.firstNotNullOfOrNull { c -> vs.firstOrNull { it.second == c }?.first }
        if (voice == null) { withContext(Dispatchers.Main) { Store.speechHint = macHint(name) }; return true }
        val vol = Prefs.volume.value.coerceIn(0f, 1f)
        return try {
            stop()
            val p = ProcessBuilder("say", "-v", voice, "-r", "160").redirectErrorStream(true).start()
            proc = p
            p.outputStream.use { it.write(("[[volm %.2f]] ".format(java.util.Locale.US, vol) + text).toByteArray(Charsets.UTF_8)) }
            p.inputStream.use { it.readBytes() }
            val code = p.waitFor()
            if (proc === p) proc = null
            code == 0
        } catch (_: Exception) { false }
    }

    /** speaks the text; false when it couldn't */
    suspend fun speakAndWait(text: String): Boolean = withContext(Dispatchers.IO) {
        val (cultures, name) = when {
            Store.isYue -> listOf("zh-HK") to com.unoki99.fangfang.tr("粵語（香港）")
            com.unoki99.fangfang.engine.Lang.isJa -> listOf("ja-JP") to com.unoki99.fangfang.tr("日語")
            // (英語: 美式 first when the reading is 美式, otherwise 英式)
            com.unoki99.fangfang.engine.Lang.isEn -> (if (Prefs.enRom.value == 1) listOf("en-US", "en-GB") else listOf("en-GB", "en-US")) to com.unoki99.fangfang.tr("英語")
            com.unoki99.fangfang.engine.Lang.isSv -> listOf("sv-SE") to com.unoki99.fangfang.tr("瑞典語")
            Prefs.zhPlace.value >= 1 -> listOf("zh-CN", "zh-TW", "zh-HK") to com.unoki99.fangfang.tr("中文")
            else -> listOf("zh-TW", "zh-CN", "zh-HK") to com.unoki99.fangfang.tr("中文（臺灣）")
        }
        if (com.unoki99.fangfang.desktop.Os.mac) return@withContext speakMac(text, cultures, name)
        val vol = (Prefs.volume.value * 100).toInt().coerceIn(0, 100)
        val d = "$"
        val script = """
[Console]::InputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Speech
${d}s = New-Object System.Speech.Synthesis.SpeechSynthesizer
${d}v = ${d}null
foreach (${d}c in @(${cultures.joinToString(", ") { "'$it'" }})) {
    ${d}v = ${d}s.GetInstalledVoices() | Where-Object { ${d}_.Enabled -and ${d}_.VoiceInfo.Culture.Name -eq ${d}c } | Select-Object -First 1
    if (${d}v) { break }
}
if (-not ${d}v) { exit 3 }
${d}s.SelectVoice(${d}v.VoiceInfo.Name)
${d}s.Volume = $vol
${d}s.Rate = -1
${d}t = [Console]::In.ReadToEnd()
${d}s.Speak(${d}t)
"""
        val enc = java.util.Base64.getEncoder().encodeToString(script.toByteArray(Charsets.UTF_16LE))
        try {
            stop()
            val p = ProcessBuilder("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", enc)
                .redirectErrorStream(true).start()
            proc = p
            p.outputStream.use { it.write(text.toByteArray(Charsets.UTF_8)) }
            p.inputStream.use { it.readBytes() }
            val code = p.waitFor()
            if (proc === p) proc = null
            if (code == 3) { withContext(Dispatchers.Main) { Store.speechHint = hint(name) }; return@withContext true }
            code == 0
        } catch (_: Exception) { false }
    }

    fun stop() { try { proc?.destroy() } catch (_: Exception) {}; proc = null }
}
