package com.unoki99.fangfang

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** (Windows) 華語 (and 粵語, 日語) read aloud with Windows' own voices (System.Speech, through PowerShell): 臺灣 or 大陸
 *  as chosen. Without a voice for the language, it says how to add one in Windows' settings. */
object ZhSpeech {
    @Volatile private var proc: Process? = null

    private fun hint(lang: String) = com.unoki99.fangfang.tr(
        "這台電腦還沒有{0}的語音。到 Windows 的「設定 → 時間與語言 → 語音」，在「管理語音」按「新增語音」，加上{0}的語音，再回來就可以聽了。", lang)

    /** speaks the text; false when it couldn't */
    suspend fun speakAndWait(text: String): Boolean = withContext(Dispatchers.IO) {
        val (cultures, name) = when {
            Store.isYue -> listOf("zh-HK") to com.unoki99.fangfang.tr("粵語（香港）")
            com.unoki99.fangfang.engine.Lang.isJa -> listOf("ja-JP") to com.unoki99.fangfang.tr("日語")
            Prefs.zhPlace.value == 1 -> listOf("zh-CN", "zh-TW", "zh-HK") to com.unoki99.fangfang.tr("中文")
            else -> listOf("zh-TW", "zh-CN", "zh-HK") to com.unoki99.fangfang.tr("中文（臺灣）")
        }
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
