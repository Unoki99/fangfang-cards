package com.unoki99.fangfang.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.*
import com.unoki99.fangfang.engine.Lang

// MARK: - 設定 → 詞典資料, and installing a language's dictionary where it's needed

/** each language's capsule colours: fill, edge, ink (台語 green, 華語 blue, 粵語 yellow, 客語 red, 日語 pink) */
fun langColors(l: Int): Triple<Color, Color, Color> = when (l) {
    4 -> Triple(T.jaFill, T.jaEdge, T.jaInk)
    3 -> Triple(T.hakFill, T.hakEdge, T.hakInk)
    2 -> Triple(Color(0xFF5A4A14), Color(0xFFC9A227), Color(0xFFFFE58A))
    1 -> Triple(Color(0xFF1F3D6B), Color(0xFF4F7DFF), Color(0xFF9AD0FF))
    else -> Triple(T.twFill, T.twEdge, T.twInk)
}

@Composable
fun DictDataPage() {
    val v = DictInstaller.version     // (redrawn after installing or removing)
    var confirmRemove by remember { mutableStateOf<DictPack?>(null) }
    ListCard {
        DictPack.all.forEachIndexed { i, p ->
            if (i > 0) RowDivider()
            key(p.id, v) { PackRow(p) { confirmRemove = p } }
        }
    }
    Txt(tr("詞典的授權不允許分享改過的版本，所以 App 從原本發布的地方下載檔案，在這台裝置上自己整理（要網路，大概一兩分鐘）。不熟、熟悉和收藏的詞不會因為移除詞典而不見。"),
        ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
    Spacer(Modifier.height(6.dp))
    Txt(tr("App 裡面沒有內建任何詞典：第一次選語言的時候會自動下載安裝，之後在這裡安裝其他語言的。維基詞典的資料（粵語的例句和錄音、台語詞的英文、華語的四川話讀音）檔案太大（2.5 GB），不在手機上整理。"),
        ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
    confirmRemove?.let { p ->
        AlertDialog(onDismissRequest = { confirmRemove = null }, containerColor = T.fn,
            title = { Txt(tr("移除這個詞典？"), ff(FF.Headline)) },
            text = { Txt(tr("之後可以再安裝。不熟、熟悉和收藏的詞會留著。"), ff(FF.Body)) },
            confirmButton = { TextButton(onClick = { DictInstaller.remove(p); confirmRemove = null }) { Text(tr("移除{0}詞典", tr(p.name)), color = Color(0xFFFF6B6B)) } },
            dismissButton = { TextButton(onClick = { confirmRemove = null }) { Text(tr("取消"), color = T.muted) } })
    }
}

@Composable
private fun PackRow(p: DictPack, remove: () -> Unit) {
    val (fill, edge, ink) = if (p.lang >= 0) langColors(p.lang) else Triple(T.fn, T.fnEdge, T.glyph)
    val main = p.outputs.first()
    val st = DictInstaller.state(p)
    Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Txt(tr(p.name), ff(FF.Headline), ink, Modifier.clip(RoundedCornerShape(8.dp)).background(fill).border(1.dp, edge, RoundedCornerShape(8.dp))
                .padding(horizontal = 8.dp, vertical = 2.dp))
            Spacer(Modifier.width(10.dp))
            val have = DataFiles.isInstalled(main)
            Txt(if (have) tr("已安裝・{0}", sizeText(p.outputs.sumOf { DataFiles.size(it) })) else if (DataFiles.isBuiltIn(main)) tr("App 內建") else tr("還沒安裝"),
                ff(FF.Footnote), T.muted, Modifier.weight(1f))
            when (st) {
                is InstallState.Working -> {}
                else -> if (DataFiles.isInstalled(main)) {
                    TextButton(onClick = { DictInstaller.install(p) }) { Text(tr("重新安裝"), color = T.btnInk) }
                    TextButton(onClick = remove) { Text(tr("移除"), color = Color(0xFFFF6B6B)) }
                } else {
                    ProminentButton(onClick = { DictInstaller.install(p) }, tint = edge) { Text(tr("安裝")) }
                }
            }
        }
        Txt(tr(p.from) + "　" + tr(p.download), ff(FF.Caption), T.muted)
        when (st) {
            is InstallState.Working -> {
                LinearProgressIndicator(progress = { st.fraction.toFloat() }, Modifier.fillMaxWidth(), color = edge, trackColor = T.fnEdge)
                Txt(st.text, ff(FF.Caption), T.muted)
            }
            is InstallState.Failed -> Txt(st.message, ff(FF.Footnote), Color(0xFFFF6B6B))
            else -> {}
        }
    }
}

private fun sizeText(b: Long): String = if (b >= 1_000_000) "%.1f MB".format(b / 1_000_000.0) else "${b / 1000} KB"

/** a language's dictionary isn't there: install it here (the 台語 pages, or the first start) */
@Composable
fun InstallPanel(lang: Int, modifier: Modifier = Modifier, onSkip: (() -> Unit)? = null, skipText: String = tr("先不要，進入 App"),
                 onBack: (() -> Unit)? = null) {
    val p = DictPack.of(lang) ?: return
    val (_, edge, ink) = langColors(lang)
    val st = DictInstaller.state(p)
    Column(modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(Modifier.size(96.dp).clip(CircleShape).background(edge.copy(alpha = 0.35f)), contentAlignment = Alignment.Center) {
            Txt(listOf("台", "華", "粵", "客", "日")[lang.coerceIn(0, 4)], sz(54f, FontWeight.Bold), ink)
        }
        Txt(tr("安裝{0}詞典", tr(Lang.names[lang])), ff(FF.Title2, FontWeight.Bold), T.glyph)
        Txt(tr(p.from) + "\n" + tr(p.download), ff(FF.Footnote), T.muted, Modifier.widthIn(max = 460.dp))
        when (st) {
            is InstallState.Working -> {
                LinearProgressIndicator(progress = { st.fraction.toFloat() }, Modifier.widthIn(max = 320.dp).fillMaxWidth(), color = edge, trackColor = T.fnEdge)
                Txt(st.text, ff(FF.Footnote), T.muted)
                Txt(tr("要網路，大概一兩分鐘。請讓 App 開著。"), ff(FF.Caption), T.muted)
            }
            is InstallState.Failed -> {
                Txt(st.message, ff(FF.Footnote), Color(0xFFFF6B6B), Modifier.widthIn(max = 460.dp))
                ProminentButton(onClick = { DictInstaller.install(p) }, tint = edge) { Text(tr("再試一次")) }
            }
            else -> ProminentButton(onClick = { DictInstaller.install(p) }, tint = edge, modifier = Modifier.widthIn(min = 220.dp)) { Text(tr("下載並安裝")) }
        }
        if (onBack != null || onSkip != null) Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            onBack?.let { b -> TextButton(onClick = b) { Text(tr("換一種語言"), color = T.muted) } }
            onSkip?.let { s -> TextButton(onClick = s) { Text(skipText, color = T.muted) } }
        }
    }
}

/** shown over the 台語 pages while 台語's dictionary isn't installed */
@Composable
fun TaigiMissingOverlay() {
    if (!Store.loaded || Store.lang != 0 || !Store.taigiMissing) return
    Box(Modifier.fillMaxSize().background(T.bg.copy(alpha = 0.9f)), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Txt(tr("還沒有{0}詞典", tr("台語")), ff(FF.Title3, FontWeight.Bold), T.glyph, Modifier.padding(top = 20.dp))
            InstallPanel(0)
            Txt(tr("也可以在「設定 → 語言與讀音」換成其他語言。"), ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 24.dp))
        }
    }
}

/** (a line of text centred, for the install panels) */
@Composable
private fun Centered(text: String) = Text(text, textAlign = TextAlign.Center)
