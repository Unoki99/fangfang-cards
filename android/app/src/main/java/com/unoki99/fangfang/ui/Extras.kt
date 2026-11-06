package com.unoki99.fangfang.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.delay

fun copyToClipboard(ctx: Context, s: String) {
    (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("方方", s))
}

/** a round button that copies (a check for a moment after) */
@Composable
fun CopyIconButton(label: String = "複製這個意思", text: () -> String) {
    val ctx = LocalContext.current
    var done by remember { mutableStateOf(false) }
    LaunchedEffect(done) { if (done) { delay(1200); done = false } }
    Box(Modifier.size(30.dp).clip(CircleShape).background(if (done) T.green else T.fn.copy(alpha = 0.8f))
        .border(1.5.dp, if (done) T.greenEdge else T.fnEdge, CircleShape)
        .clickable { copyToClipboard(ctx, text()); done = true }, contentAlignment = Alignment.Center) {
        Icon(if (done) Icons.Filled.Check else Icons.Filled.ContentCopy, if (done) "已複製" else label,
            tint = if (done) T.greenInk else T.muted, modifier = Modifier.size(16.dp))
    }
}

/** the bookmark on a meaning: save just this meaning (blue) */
@Composable
fun SenseSaveButton(item: SavedSense) {
    Store.rev
    val on = Store.isSaved(item)
    Box(Modifier.size(30.dp).clip(CircleShape).background(if (on) T.blue else T.fn.copy(alpha = 0.8f))
        .border(1.5.dp, if (on) T.blueEdge else T.fnEdge, CircleShape)
        .clickable { Store.toggleSaved(item) }, contentAlignment = Alignment.Center) {
        Icon(if (on) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder, if (on) "取消收藏這個意思" else "收藏這個意思",
            tint = if (on) T.blueInk else T.muted, modifier = Modifier.size(16.dp))
    }
}

private val toneRainbow: List<Color> get() = listOf(ToneColors.red, ToneColors.orange, ToneColors.yellow, ToneColors.green,
    ToneColors.teal, ToneColors.blue, ToneColors.purple, ToneColors.pink, ToneColors.red).map { Color(it) }

/** a little star in all the tone colours: under a word in 轉換 that's saved or in 不熟 (blue: only meanings saved) */
@Composable
fun ToneStar(size: Dp = 9.dp, blue: Boolean = false) {
    if (blue) Icon(Icons.Filled.Star, null, tint = Color(ToneColors.blue), modifier = Modifier.size(size))
    else Icon(Icons.Filled.Star, null, tint = Color.White, modifier = Modifier.size(size)
        .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
        .drawWithContent { drawContent(); drawRect(Brush.sweepGradient(toneRainbow), blendMode = BlendMode.SrcAtop) })
}

/** a half-width button (two to a row) */
@Composable
fun TileButton(icon: ImageVector, title: String, modifier: Modifier = Modifier, count: Int? = null, cap: Int = 0,
               ink: Color = T.oliveInk, enabled: Boolean = true, onClick: () -> Unit) {
    Row(modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = if (enabled) 0.7f else 0.4f))
        .border(1.dp, T.fnEdge, RoundedCornerShape(12.dp)).clickable(enabled = enabled, onClick = onClick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, tint = if (enabled) ink else T.muted, modifier = Modifier.size(20.dp))
        Text(title, style = ff(FF.Subheadline), color = if (enabled) T.glyph else T.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f))
        if (count != null) Text(if (cap > 0 && count >= cap) "$cap+" else "$count", style = ff(FF.Footnote), color = T.muted)
    }
}

/** buttons two to a row */
@Composable
fun TileGrid(count: Int, spacing: Dp = 10.dp, tile: @Composable (index: Int, modifier: Modifier) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(spacing)) {
        for (start in 0 until count step 2) Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(spacing)) {
            tile(start, Modifier.weight(1f).fillMaxHeight())
            if (start + 1 < count) tile(start + 1, Modifier.weight(1f).fillMaxHeight()) else Spacer(Modifier.weight(1f))
        }
    }
}

// MARK: - headword whose characters can be tapped

/** the characters of a text, one piece each (keeping their colours) */
fun splitCharacters(a: AnnotatedString): List<AnnotatedString> {
    val out = ArrayList<AnnotatedString>()
    var i = 0
    val s = a.text
    while (i < s.length) {
        val n = Character.charCount(s.codePointAt(i))
        out.add(a.subSequence(i, i + n))
        i += n
    }
    return out
}

/** a headword: each character that is a word of its own (read the same way) can be tapped to see it; the whole character is the button */
@Composable
fun TappableHeadword(text: AnnotatedString, targets: List<String?>, size: Float = 44f, color: Color = T.glyph, onTap: (String) -> Unit) {
    val chars = splitCharacters(text)
    Row {
        for ((i, ch) in chars.withIndex()) {
            val k = if (chars.size > 1) targets.getOrNull(i) else null
            if (k != null) {
                val src = remember { MutableInteractionSource() }
                val pressed by src.collectIsPressedAsState()
                Text(ch, style = sz(size, FontWeight.SemiBold), color = color,
                    modifier = Modifier.swell(pressed).clickable(interactionSource = src, indication = null) { onTap(k) })
            } else Text(ch, style = sz(size, FontWeight.SemiBold), color = color)
        }
    }
}

/** for each character of a 台語 headword: the single-character entry read the way this word reads it */
fun charKeys(d: Dict, key: String): List<String?> {
    val han = Dict.hanOf(key)
    val codes = Dict.codesOf(key).split(' ')
    val out = ArrayList<String?>()
    var n = 0
    for (c in han.cps()) {
        if (!ConvertEngine.isHan(c.firstCp())) { out.add(null); continue }
        val code = codes.getOrNull(n); n++
        val k = if (code != null && d.hanMap[c]?.contains(code) == true) d.keyOf(Opt(c, listOf(code))) else null
        out.add(if (k != null && d.raw.defs.m[k] != null && k != key) k else null)
    }
    return out
}

// MARK: - 倉頡 / 五筆 / 無蝦米

/** under the headword: each character with its codes (設定 → 輸入法拆碼) */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun InputCodesRow(han: String) {
    if (!Prefs.imeOn.value) return
    val ic = Store.inputCodes
    val systems = listOf(Prefs.imeCJ.value, Prefs.imeWB.value, Prefs.imeLiu.value).withIndex().filter { it.value }.map { it.index }
    val chars = han.cps().filter { Zhuyin.isHan(it.firstCp()) }
    if (systems.isEmpty() || chars.isEmpty()) return
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (ch in chars) {
            Column(Modifier.clip(RoundedCornerShape(10.dp)).background(T.fn.copy(alpha = 0.6f)).border(1.dp, T.fnEdge, RoundedCornerShape(10.dp))
                .padding(horizontal = 8.dp, vertical = 5.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Txt(ch, ff(FF.Subheadline, FontWeight.SemiBold), T.glyph)
                for (s in systems) Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Txt(InputCodes.short[s], ff(FF.Caption2, FontWeight.Bold), T.muted)
                    Txt(ic.code(ch, s) ?: "—", ff(FF.Caption).copy(fontFamily = FontFamily.Monospace), T.oliveInk)
                }
            }
        }
    }
}

/** the CSV / text save launcher's result: writes `text` to the file picked */
fun writeTo(ctx: Context, uri: android.net.Uri?, text: String) {
    if (uri != null) ctx.contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) }
}
