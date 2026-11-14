package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.DataFiles
import com.unoki99.fangfang.DictInstaller

// MARK: - 說文解字 (段玉裁《說文解字注》, from cjkvi-dict, GPLv2)
//
// Installed like a dictionary (設定 → 詞典資料 → 說文解字): the phone downloads swjz.xml and makes shuowen.json
// (install/shuowen.js). A single character's entry shows 許慎's text, 段玉裁's notes (folded away), and its 六書.

object Shuowen {
    class Item(val text: String, val notes: String?, val liushu: String?)
    @Volatile private var table: Map<String, List<Item>>? = null
    @Volatile private var readAt = -1

    private val all: Map<String, List<Item>>
        @Synchronized get() {
            // (read again after installing or removing it)
            val v = DictInstaller.version
            table?.let { if (readAt == v) return it }
            val t = HashMap<String, List<Item>>()
            try {
                DataFiles.readText("shuowen")?.let { text ->
                    val c = org.json.JSONObject(text).optJSONObject("c")
                    if (c != null) for (ch in c.keys()) {
                        val arr = c.getJSONArray(ch)
                        t[ch] = (0 until arr.length()).mapNotNull { i ->
                            val o = arr.getJSONObject(i)
                            if (!o.has("e")) null else Item(o.getString("e"), o.optString("d").ifEmpty { null }, o.optString("l").ifEmpty { null })
                        }
                    }
                }
            } catch (_: Throwable) {}
            table = t; readAt = v
            return t
        }

    fun of(ch: String): List<Item> = all[ch] ?: emptyList()
    /** the character's 六書 (null: not known) */
    fun liushu(ch: String): String? = of(ch).firstNotNullOfOrNull { it.liushu }
}

/** a character's 說文解字: under its meanings (nothing when 說文解字 isn't installed) */
@Composable
fun ShuowenBlock(ch: String) {
    val v = DictInstaller.version
    val items = remember(ch, v) { Shuowen.of(ch) }
    if (items.isEmpty()) return
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.55f)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Txt(tr("《說文解字》"), ff(FF.Caption, FontWeight.Bold), T.muted)
            Shuowen.liushu(ch)?.let { Chip(tr("六書：") + it, T.olive, T.oliveEdge, T.oliveInk) }
        }
        for (it in items) Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Txt(it.text, ff(FF.Body), T.glyph)
            val n = it.notes
            if (!n.isNullOrEmpty()) {
                var open by remember { mutableStateOf(false) }
                Row(Modifier.clip(RoundedCornerShape(6.dp)).clickable { open = !open }.padding(vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Txt(tr("段玉裁注"), ff(FF.Footnote, FontWeight.SemiBold), T.muted)
                    Icon(if (open) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown, null, tint = T.muted, modifier = Modifier.size(16.dp))
                }
                if (open) Txt(n, ff(FF.Footnote), T.glyph.copy(alpha = 0.85f))
            }
        }
        Txt(tr("資料：段玉裁《說文解字注》（cjkvi-dict，GPLv2）。六書照說文的寫法判斷（「…聲」為形聲），可能有誤。"), ff(FF.Caption2), T.muted)
    }
}
