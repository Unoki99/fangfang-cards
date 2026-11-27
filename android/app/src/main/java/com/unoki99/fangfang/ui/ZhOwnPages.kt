package com.unoki99.fangfang.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.ZhDict
import com.unoki99.fangfang.engine.ZhOwnWords
import com.unoki99.fangfang.tr

// MARK: - 詞典 → 自訂 in 華語, 粵語, 客語, 日語, 瑞典語 (the same as the iPhone app's ZhOwnPane): your own words, with
// a reading in the language's own spelling, a meaning and an example; found by the search, marked 自訂; 匯出 CSV.

@Composable
fun ZhOwnPane(z: ZhDict) {
    val nav = LocalNav.current
    val ctx = androidx.compose.ui.platform.LocalContext.current
    var adding by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    val saveCsv = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri -> writeTo(ctx, uri, pending) }
    val keys = Store.zhOwnKeys(z.lang)
    fun csv(): String {
        fun q(s: String) = if (s.any { it == ',' || it == '"' || it == '\n' || it == '\r' }) "\"" + s.replace("\"", "\"\"") + "\"" else s
        val rows = mutableListOf("word,reading,meaning,example")
        for (k in keys) {
            val i = Store.ownInfo(k)
            rows.add(listOf(ZhOwnWords.han(k), z.reading(ZhOwnWords.syllables(k), Prefs.zhRom.value).plain(), i.first, i.second).joinToString(",") { q(it) })
        }
        return "﻿" + rows.joinToString("\r\n") + "\r\n"
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
        item {
            SoftButton(onClick = { adding = true }, modifier = Modifier.fillMaxWidth()) { IconLabel(Icons.Filled.AddCircle, tr("加一個詞"), ff(FF.Headline), T.ownInk) }
            if (keys.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                SoftButton(onClick = {
                    pending = csv()
                    saveCsv.launch("方方-自訂詞-" + listOf("", "華語", "粵語", "客語", "日語", "瑞典語")[z.lang.coerceIn(0, 5)] + ".csv")
                }, modifier = Modifier.fillMaxWidth()) { IconLabel(Icons.Filled.IosShare, tr("匯出 CSV"), ff(FF.Headline), T.ownInk) }
            }
            message?.let { Txt(it, ff(FF.Footnote), T.muted, Modifier.padding(6.dp)) }
            Txt(tr("自己加的詞不是詞典的內容，用紫色和「自訂」標示。查詞找得到，也可以加到「不熟」練習。"), ff(FF.Footnote), T.muted, Modifier.padding(6.dp))
            if (keys.isNotEmpty()) SectionTitle(tr("{0} 個詞（往左滑刪除）", keys.size))
        }
        items(keys, key = { "zo|$it" }) { k ->
            val e = z.entry(k)
            SwipeRow(start = null, end = Pair(tr("刪除"), Color(0xFFB3261E)), onEnd = { Store.removeOwn(k) }, onClick = { if (e != null) nav.push(Route.ZhEntry(k)) }) {
                // (added just now: the dictionary is being read again)
                if (e != null) ZhWordRow(z, e)
                else Txt(ZhOwnWords.han(k), sz(20f, FontWeight.SemiBold), T.ownInk, Modifier.padding(14.dp))
            }
            RowDivider()
        }
    }
    if (adding) AddZhOwnDialog(z) { adding = false }
}

/** add a word: the word, its reading (in the language's spelling), meaning, example (word0…: filled in already) */
@Composable
fun AddZhOwnDialog(z: ZhDict, word0: String = "", reading0: String = "", meaning0: String = "", onDone: () -> Unit) {
    val lang = z.lang
    var word by remember { mutableStateOf(word0) }
    var reading by remember { mutableStateOf(reading0) }
    var meaning by remember { mutableStateOf(meaning0) }
    var example by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf<String?>(null) }
    val hint = when (lang) {
        2 -> tr("粵拼，要有聲調數字：sik6 faan6")
        3 -> tr("客語拼音，要有聲調類別的數字：siid8 fan3")
        4 -> tr("かな（可以不填，詞是かな的話）")
        5 -> ""
        else -> tr("拼音（chi1 fan4、chīfàn，聲調可以不打）或注音")
    }
    val parsed = remember(word, reading) {
        val w = word.trim()
        if (w.isEmpty() || (lang != 5 && lang != 4 && reading.isBlank())) null else ZhOwnWords.syllables(reading, w, lang, z)
    }
    AlertDialog(onDismissRequest = onDone, containerColor = T.bg,
        title = { Txt(tr("加一個詞"), ff(FF.Headline, FontWeight.SemiBold), T.glyph) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                GameField(word, { word = it }, if (lang == 5) tr("例：fika") else tr("例：吃飯"))
                if (lang != 5) {
                    GameField(reading, { reading = it }, hint, style = lat(17f))
                    parsed?.let { Txt(z.reading(it, Prefs.zhRom.value).annotated(), lat(16f), T.greenInk) }
                }
                GameField(meaning, { meaning = it }, tr("意思（可以不填）"))
                GameField(example, { example = it }, tr("例句（可以不填）"))
                problem?.let { Txt(it, ff(FF.Footnote), T.rustInk) }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val w = word.trim()
                val tw = parsed
                if (tw == null) { problem = tr("讀不懂這個讀音：") + hint; return@TextButton }
                val key = ZhOwnWords.key(lang, w, tw)
                if (Store.isOwn(key)) { problem = tr("這個詞已經在「自訂」裡了。"); return@TextButton }
                Store.addOwn(key, meaning, example)
                onDone()
            }, enabled = word.isNotBlank()) { Text(tr("加入"), color = T.btnInk) }
        },
        dismissButton = { TextButton(onClick = onDone) { Text(tr("取消"), color = T.muted) } })
}
