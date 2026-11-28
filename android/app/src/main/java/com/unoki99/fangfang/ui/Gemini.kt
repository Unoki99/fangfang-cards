package com.unoki99.fangfang.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.Card
import com.unoki99.fangfang.engine.Lang
import com.unoki99.fangfang.engine.Simp
import com.unoki99.fangfang.engine.Zhuyin
import com.unoki99.fangfang.engine.cps
import com.unoki99.fangfang.engine.firstCp
import com.unoki99.fangfang.engine.plain
import com.unoki99.fangfang.tr
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

// MARK: - Gemini (your own API key, 設定 → 詞典 → Gemini; the same as the iPhone app's Gemini.swift)
//
// Only used when you turn it on and give it your own key (from Google AI Studio): nothing is sent anywhere otherwise.
// 1. A dictionary search that finds nothing asks it for the words you most likely meant (Chinese words; 日語 and 瑞典語:
//    words of that language), shown as the dictionary's words. 華語: a Chinese term it knows can be added to 自訂.
// 2. 本週學習 → 造句: write a sentence with one of the week's words; it corrects how the word is used, then shows the
//    whole sentence corrected.

object Gemini {
    const val defaultModel = "gemini-3.8-flash"
    /** the Flash models to choose from (Google's list, November 2026): code, name. 2.5: only for keys that used it before */
    val models = listOf("gemini-3.8-flash" to "Gemini 3.8 Flash", "gemini-3.6-flash" to "Gemini 3.6 Flash", "gemini-3.5-flash-lite" to "Gemini 3.5 Flash-Lite",
        "gemini-3.1-flash-lite" to "Gemini 3.1 Flash-Lite", "gemini-3-flash-preview" to "Gemini 3 Flash (preview)",
        "gemini-2.5-flash" to "Gemini 2.5 Flash", "gemini-2.5-flash-lite" to "Gemini 2.5 Flash-Lite")
    val key: String get() = Prefs.geminiKey.value.trim()
    val model: String get() = Prefs.geminiModel.value.trim().ifEmpty { defaultModel }
    /** turned on, with a key */
    val on: Boolean get() = Prefs.geminiOn.value && key.isNotEmpty()

    class Failure(val code: Int, val msg: String) : Exception(msg)

    /** one question; the answer is JSON (an object) */
    suspend fun ask(prompt: String): JSONObject = withContext(Dispatchers.IO) {
        if (key.isEmpty()) throw Failure(-1, "")
        val c = URL("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent").openConnection() as HttpURLConnection
        c.requestMethod = "POST"; c.doOutput = true; c.connectTimeout = 15000; c.readTimeout = 40000
        c.setRequestProperty("Content-Type", "application/json"); c.setRequestProperty("x-goog-api-key", key)
        val body = JSONObject().put("contents", JSONArray().put(JSONObject().put("role", "user").put("parts", JSONArray().put(JSONObject().put("text", prompt)))))
            .put("generationConfig", JSONObject().put("responseMimeType", "application/json").put("temperature", 0.2))
        c.outputStream.use { it.write(body.toString().toByteArray()) }
        val code = c.responseCode
        if (code != 200) {
            val e = try { c.errorStream?.bufferedReader()?.use { it.readText() } } catch (_: Exception) { null }
            val m = try { JSONObject(e ?: "").optJSONObject("error")?.optString("message") ?: "" } catch (_: Exception) { "" }
            c.disconnect(); throw Failure(code, m)
        }
        val t = c.inputStream.bufferedReader().use { it.readText() }; c.disconnect()
        val parts = JSONObject(t).optJSONArray("candidates")?.optJSONObject(0)?.optJSONObject("content")?.optJSONArray("parts") ?: throw Failure(0, "")
        val text = (0 until parts.length()).joinToString("") { parts.optJSONObject(it)?.optString("text") ?: "" }
            .replace("```json", "").replace("```", "").trim()
        try { JSONObject(text) } catch (_: Exception) { throw Failure(0, "") }
    }

    fun message(e: Throwable): String = when {
        e is Failure && e.code == -1 -> tr("還沒有 Gemini 的 API 金鑰：設定 → 詞典 → Gemini。")
        e is Failure && (e.code == 400 || e.code == 401 || e.code == 403) -> tr("Gemini 不接受這個 API 金鑰（{0}）。", e.code) + if (e.msg.isEmpty()) "" else "\n" + e.msg
        e is Failure && e.code == 429 -> tr("Gemini 現在太忙，或是今天用完了免費的次數（429）。")
        e is Failure && e.code > 0 -> tr("Gemini 沒有回答（{0}）。", e.code) + if (e.msg.isEmpty()) "" else "\n" + e.msg
        e is Failure -> tr("Gemini 的回答讀不懂。")
        else -> tr("連不到 Gemini：") + (e.message ?: "")
    }

    private fun script() = if (Simp.on) "Simplified" else "Traditional"
    private fun target(lang: Int): Pair<String, String> = when (lang) {
        4 -> "Japanese dictionary" to "Japanese words (dictionary forms, written as a Japanese dictionary would list them)"
        5 -> "Swedish dictionary" to "Swedish words (base forms, as a Swedish dictionary would list them: no article, no \"att\"; when the search is a meaning in Chinese, English or another language, the Swedish words for it)"
        6 -> "English dictionary" to "English words (base forms, as an English dictionary would list them: no article, no \"to\"; when the search is a meaning in Chinese, Swedish or another language, the English words for it)"
        0 -> "Taiwanese Hokkien dictionary that can also be searched with Mandarin words" to "Chinese words (Mandarin as used in Taiwan, ${script()} characters)"
        2 -> "Cantonese dictionary that can also be searched with Mandarin words" to "Chinese words (${script()} characters; Cantonese words or Mandarin ones)"
        3 -> "Taiwan Hakka dictionary that can also be searched with Mandarin words" to "Chinese words (Mandarin as used in Taiwan, ${script()} characters)"
        else -> "Mandarin Chinese dictionary" to "Chinese words (${script()} characters)"
    }

    /** 瑞典語, 英語: a word as a dictionary lists it, without the article or infinitive marker Gemini sometimes puts
     *  before it ("att springa" → springa, "to run" → run, "en bil" → bil) */
    fun latinHeadword(w: String): String {
        var s = w.trim().trim('.', ',', ';', '"', '\'')
        for (pre in listOf("att ", "en ", "ett ", "to ", "a ", "an ", "the ")) if (s.length > pre.length + 1 && s.startsWith(pre, ignoreCase = true)) { s = s.drop(pre.length); break }
        return s.trim()
    }

    class Term(val h: String, val pinyin: String, val meaning: String)
    class Suggestion(val words: List<String>, val note: String, val term: Term?)

    suspend fun suggest(q: String, lang: Int): Suggestion {
        val (dict, words) = target(lang)
        val han = q.cps().any { Zhuyin.isHan(it.firstCp()) }
        var p = """A learner searched a $dict for "$q" and it found nothing (or only rough matches). Work out what they most likely meant: it may be misspelt, typed in a romanisation (pinyin, zhuyin, Jyutping, Tâi-lô, Hakka pinyin, rōmaji…), written in English or another language, a description, slang, a name or a new expression.
Reply with JSON only: {"words": [...], "note": "..."}
"words": up to 8 $words, the most likely first; each one a single dictionary word or set phrase, nothing else (no readings, no explanations).
"note": at most one short sentence in ${script()} Chinese on what the search most likely was."""
        if (han && (lang == 1 || lang == 0)) p += """

If "$q" itself is a real Chinese word, expression, name or slang term, also add "term": {"pinyin": its Mandarin reading in pinyin with tone numbers, one syllable per character separated by spaces (e.g. "chi1 fan4"), "meaning": a short explanation in ${script()} Chinese}. Otherwise "term": null."""
        val j = ask(p)
        val ws = j.optJSONArray("words")
        val list = if (ws == null) emptyList() else (0 until ws.length()).map { ws.optString(it).trim() }
            .map { if (lang == 5 || lang == 6) latinHeadword(it) else it }.filter { it.isNotEmpty() && it != q }.distinct()
        val t = j.optJSONObject("term")
        val term = t?.optString("pinyin")?.takeIf { it.isNotEmpty() }?.let { Term(q, it, t.optString("meaning")) }
        return Suggestion(list, j.optString("note"), term)
    }

    class Correction(val usage: String, val corrected: String, val good: Boolean)
    suspend fun correct(word: String, reading: String, meaning: String, sentence: String, lang: Int): Correction {
        val language = listOf("Taiwanese Hokkien (written in Han characters as the Taiwan Ministry of Education does)", "Mandarin Chinese",
            "Cantonese", "Taiwan Hakka", "Japanese", "Swedish", "English")[lang.coerceIn(0, 6)]
        val p = """A learner of $language wrote a sentence to practise the word "$word"${if (reading.isEmpty()) "" else " ($reading)"}${if (meaning.isEmpty()) "" else ", meaning: $meaning"}.
Sentence: "$sentence"
Reply with JSON only: {"good": true or false, "usage": "...", "corrected": "..."}
"good": whether "$word" is used correctly and naturally.
"usage": 1–3 short sentences in ${script()} Chinese, only about how "$word" is used here: is it right, and if not, how it should be used (with a better way to say that part). Don't comment on the rest of the sentence here.
"corrected": the whole sentence corrected (grammar, word choice, punctuation) in $language, as natural as possible while keeping what the learner meant; the same sentence if it's already right."""
        val j = ask(p)
        val u = j.optString("usage").ifEmpty { throw Failure(0, "") }
        return Correction(u, j.optString("corrected").ifEmpty { sentence }, j.optBoolean("good"))
    }
}

/** 設定 → 詞典 → Gemini */
@Composable
fun GeminiSettings() {
    var testing by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(14.dp)) {
        Row(Modifier.fillMaxWidth().clickable { Prefs.geminiOn.value = !Prefs.geminiOn.value }, verticalAlignment = Alignment.CenterVertically) {
            Txt(tr("用 Gemini 幫忙"), ff(FF.Body), T.glyph, modifier = Modifier.weight(1f))
            Switch(Prefs.geminiOn.value, { Prefs.geminiOn.value = it }, colors = SwitchDefaults.colors(checkedTrackColor = T.btnEdge, checkedThumbColor = T.btnInk))
        }
        GameField(Prefs.geminiKey.value, { Prefs.geminiKey.value = it }, tr("API 金鑰"), style = lat(15f))
        var open by remember { mutableStateOf(false) }
        Box {
            val cur = Gemini.model
            SoftButton({ open = true }, Modifier.fillMaxWidth()) { Text(tr("模型") + "：" + (Gemini.models.firstOrNull { it.first == cur }?.second ?: cur)) }
            DropdownMenu(open, { open = false }, containerColor = T.fn) {
                for ((code, name) in Gemini.models) DropdownMenuItem(text = { Text(name, color = if (code == cur) T.greenInk else T.glyph) }, onClick = { Prefs.geminiModel.value = code; open = false })
            }
        }
        SoftButton({
            testing = true; result = null
            scope.launch {
                result = try { val s = Gemini.suggest("chifan", 1); tr("可以用了。（chifan → {0}）", s.words.take(3).joinToString("、")) } catch (e: Throwable) { Gemini.message(e) }
                testing = false
            }
        }, Modifier.fillMaxWidth(), enabled = !testing && Prefs.geminiKey.value.isNotBlank()) { Text(if (testing) tr("試試看中…") else tr("試試看")) }
        result?.let { Txt(it, ff(FF.Footnote), T.muted) }
        Txt(tr("用你自己的 Google Gemini API 金鑰（在 Google AI Studio 免費申請）。打開以後：查詞找不到的時候，會問 Gemini 你可能要找的詞，再用詞典找出來；華語可以把它認得的詞加到「自訂」；本週學習多一個「造句」練習，Gemini 改你的句子。只有用到的時候才會把你查的字或寫的句子送給 Google。金鑰只存在這台裝置上。"),
            ff(FF.Caption), T.muted)
    }
}

/** a search that found nothing: the words Gemini thinks were meant (when it's turned on); tapping one searches the
 *  dictionary for it. `addTerm`: 華語's add-to-自訂 */
@Composable
fun <K> GeminiSuggestions(query: String, lang: Int, search: (String) -> Unit, addTerm: ((Gemini.Term) -> Unit)? = null,
                      /** a word Gemini gave that the dictionary doesn't have (has: whether it does): saved as your own
                       *  word (自訂), its meaning what was searched */
                      has: (String) -> Boolean = { false }, addOwn: ((String) -> Unit)? = null,
                      /** the dictionary's entries for a word Gemini gave, shown as they are in the list (no need to
                       *  search it again); a word with none is a button that searches it */
                      found: (String) -> List<K> = { emptyList() }, row: (@Composable (K) -> Unit)? = null) {
    if (!Gemini.on) return
    var got by remember { mutableStateOf<Gemini.Suggestion?>(null) }
    var gotFor by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf<String?>(null) }
    // (each word's entries, looked up in the background before the words are shown)
    var foundMap by remember { mutableStateOf<Map<String, List<K>>>(emptyMap()) }
    LaunchedEffect(query) {
        val q = query.trim()
        if (q.isEmpty() || gotFor == query) return@LaunchedEffect
        failed = null
        // (only once typing has stopped for a moment: a new query cancels this)
        delay(900)
        try {
            val s = Gemini.suggest(q, lang)
            foundMap = if (row == null) emptyMap() else withContext(Dispatchers.Default) { s.words.associateWith { runCatching { found(it).take(3) }.getOrDefault(emptyList()) } }
            got = s; gotFor = query
        } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Throwable) { failed = Gemini.message(e) }
    }
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.6f)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Txt(tr("Gemini 猜你要找的詞"), ff(FF.Caption, FontWeight.Bold), T.muted)
        val g = got
        val f = failed
        if (f != null) Txt(f, ff(FF.Footnote), T.rustInk)
        else if (g == null || gotFor != query) Txt(tr("問 Gemini 中…"), ff(FF.Footnote), T.muted)
        else {
            if (g.note.isNotEmpty()) Txt(g.note, ff(FF.Footnote), T.muted)
            for (w in g.words) {
                val idx = foundMap[w].orEmpty()
                if (row != null && idx.isNotEmpty()) idx.forEach { row(it) }
                else Row(Modifier.fillMaxWidth().clickable { search(w) }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Txt(w, ff(FF.Title3, FontWeight.SemiBold), T.glyph, Modifier.weight(1f))
                    if (addOwn != null && (if (row != null) idx.isEmpty() else !has(w))) TextButton(onClick = { addOwn(w) }) { Text(tr("＋存成自訂詞"), color = T.ownInk) }
                    Txt("⌕", ff(FF.Title3), T.btnInk)
                }
            }
            if (g.words.isEmpty()) Txt(tr("Gemini 也不知道。"), ff(FF.Footnote), T.muted)
            val t = g.term
            if (t != null && addTerm != null) TextButton(onClick = { addTerm(t) }) { Text(tr("把「{0}」加到自訂（{1}）", t.h, t.pinyin), color = T.ownInk) }
        }
        Txt(if (row != null) (if (addOwn == null) tr("Gemini 猜的詞，詞典有的直接列出來；沒有的，點一下再查。")
                else tr("Gemini 猜的詞，詞典有的直接列出來；沒有的，按旁邊的＋存成自訂詞（意思先填你查的「{0}」）。", query))
            else if (addOwn == null) tr("Gemini 猜的，不是詞典的內容：點一個詞，再用詞典查。")
            else tr("Gemini 猜的，不是詞典的內容：點一個詞，再用詞典查。詞典沒有的詞，按旁邊的＋存成自訂詞（意思先填你查的「{0}」）。", query), ff(FF.Caption2), T.muted)
    }
}

/** 本週學習 → 造句 */
@Composable
fun UsagePracticeScreen(words: List<Card>, onClose: () -> Unit) {
    var i by remember { mutableIntStateOf(0) }
    var sentence by remember { mutableStateOf("") }
    var result by remember { mutableStateOf<Gemini.Correction?>(null) }
    var failed by remember { mutableStateOf<String?>(null) }
    var asking by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val rom = Prefs.rom.value; val place = Prefs.place.value
    val c = if (words.isEmpty()) null else words[i % words.size]
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("造句"), onClose, close = true, settings = false) {
            TextButton(onClick = { i++; sentence = ""; result = null; failed = null }, enabled = words.size > 1) { Text(tr("換一個詞"), color = T.btnInk) }
        }
        Column(Modifier.fillMaxSize().dragScrollY(rememberScrollState()).padding(16.dp).widthIn(max = 680.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            if (!Gemini.on) Txt(tr("這個練習要用 Gemini：在 設定 → 詞典 → Gemini 打開，填你自己的 API 金鑰。"), ff(FF.Body), T.muted)
            if (c != null) {
                Txt(tr("用這個詞造一個句子（{0}／{1}）", i % words.size + 1, words.size), ff(FF.Caption), T.muted)
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.7f)).padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Txt(c.h, ff(FF.LargeTitle, FontWeight.Bold), T.glyph)
                    Txt(Store.cardRom(c, rom, place).plain(), lat(18f), T.greenInk)
                    for ((n, d) in c.d.take(2).withIndex()) Txt((if (c.d.size > 1) "${n + 1}. " else "") + d.t, ff(FF.Subheadline), T.muted)
                }
                GameField(sentence, { sentence = it }, tr("你的句子"))
                ProminentButton({
                    asking = true; failed = null; result = null
                    val s = sentence.trim(); val reading = Store.cardRom(c, rom, place).plain(); val meaning = c.d.take(2).joinToString("；") { it.t }
                    scope.launch {
                        try { result = Gemini.correct(c.h, reading, meaning, s, Lang.kind(c.k)) } catch (e: Throwable) { failed = Gemini.message(e) }
                        asking = false
                    }
                }, Modifier.fillMaxWidth(), enabled = !asking && sentence.isNotBlank() && Gemini.on) { Text(if (asking) tr("Gemini 改句子中…") else tr("請 Gemini 改")) }
                failed?.let { Txt(it, ff(FF.Footnote), T.rustInk) }
                result?.let { r ->
                    Txt(if (r.good) tr("用對了") else tr("用法要改"), ff(FF.Headline), if (r.good) T.greenInk else T.rustInk)
                    Txt(tr("這個詞的用法"), ff(FF.Caption, FontWeight.Bold), T.muted)
                    Txt(r.usage, ff(FF.Body), T.glyph)
                    Txt(tr("整句改好"), ff(FF.Caption, FontWeight.Bold), T.muted)
                    Txt(r.corrected, ff(FF.Title3), T.glyph)
                    SoftButton({ i++; sentence = ""; result = null; failed = null }, Modifier.fillMaxWidth()) { Text(tr("下一個詞")) }
                }
            }
        }
    }
}
