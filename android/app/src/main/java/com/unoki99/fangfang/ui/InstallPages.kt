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
    6 -> Triple(EN_FILL, EN_EDGE, EN_INK)
    5 -> Triple(SV_FILL, SV_EDGE, SV_INK)
    4 -> Triple(T.jaFill, T.jaEdge, T.jaInk)
    3 -> Triple(T.hakFill, T.hakEdge, T.hakInk)
    2 -> Triple(Color(0xFF5A4A14), Color(0xFFC9A227), Color(0xFFFFE58A))
    1 -> Triple(Color(0xFF1F3D6B), Color(0xFF4F7DFF), Color(0xFF9AD0FF))
    else -> Triple(T.twFill, T.twEdge, T.twInk)
}

/** 瑞典語's teal (the same in every theme) */
val SV_FILL = Color(0xFF124A46)
val SV_EDGE = Color(0xFF2EC4B6)
val SV_INK = Color(0xFF9FF3E8)
/** 英語's orange (the same in every theme) */
val EN_FILL = Color(0xFF5A3214)
val EN_EDGE = Color(0xFFF08A3C)
val EN_INK = Color(0xFFFFD2A8)

@Composable
fun DictDataPage() {
    val v = DictInstaller.version     // (redrawn after installing or removing)
    var confirmRemove by remember { mutableStateOf<DictPack?>(null) }
    // 安裝全部: every dictionary not installed yet, one after another
    ListCard {
        val missing = remember(v, DictInstaller.busy) { DictInstaller.missing() }
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val r = DictInstaller.allRunning
            if (r != null) {
                Txt(tr("全部安裝：第 {0} / {1} 個", r.first, r.second), ff(FF.Subheadline), T.glyph)
                LinearProgressIndicator(progress = { (r.first - 1).toFloat() / maxOf(r.second, 1) }, Modifier.fillMaxWidth(), color = T.btnEdge, trackColor = T.fnEdge)
            } else {
                ProminentButton(onClick = { DictInstaller.installAll() }, tint = T.btnEdge, modifier = Modifier.fillMaxWidth(),
                    enabled = missing.isNotEmpty() && !DictInstaller.busy) {
                    Text(if (missing.isEmpty()) tr("全部詞典都安裝好了") else tr("安裝全部詞典（還有 {0} 個）", missing.size))
                }
            }
            Txt(tr("一個接一個下載和整理，全部要幾分鐘。整理的時候讓 App 開著。"), ff(FF.Caption), T.muted)
        }
    }
    Spacer(Modifier.height(10.dp))
    LockWordSettings()
    Spacer(Modifier.height(10.dp))
    ListCard {
        DictPack.all.forEachIndexed { i, p ->
            if (i > 0) RowDivider()
            key(p.id, v) { PackRow(p) { confirmRemove = p } }
        }
    }
    Txt(tr("詞典的授權不允許分享改過的版本，所以 App 下載原本的檔案（先從方方詞卡在 GitHub 上的資料儲存庫 fangfang-data，那裡沒有才從原本發布的地方），在這台裝置上自己整理（要網路，大概一兩分鐘）。不熟、熟悉和收藏的詞不會因為移除詞典而不見。"),
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
        if (st !is InstallState.Working && DictInstaller.isOutdated(p))
            Txt(tr("這是舊版的資料：按「重新安裝」換成新版（App 打開的時候也會自己更新）。"), ff(FF.Caption), Color(0xFFFF6B6B))
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
            Txt(listOf("台", "華", "粵", "客", "日", "瑞", "英")[lang.coerceIn(0, 6)], sz(54f, FontWeight.Bold), ink)
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


/** 設定 → 詞典資料 → 鎖定畫面的詞 (the iPhone's 動態島): on / off, and which words */
@Composable
fun LockWordSettings() {
    var on by Prefs.lockWord
    var src by Prefs.lockSource
    val ask = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { ok ->
        on = ok
    }
    SectionTitle(tr("鎖定畫面的詞"))
    ListCard {
        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Txt(tr("離開 App 的時候顯示"), ff(FF.Body), T.glyph, Modifier.weight(1f))
            Switch(on, { v ->
                if (v && android.os.Build.VERSION.SDK_INT >= 33) ask.launch(android.Manifest.permission.POST_NOTIFICATIONS) else on = v
            }, colors = SwitchDefaults.colors(checkedTrackColor = T.btnEdge))
        }
        RowDivider()
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Txt(tr("顯示哪些詞"), ff(FF.Subheadline), T.glyph)
            Segmented(listOf("" to tr("跟練習範圍一樣（{0}）", Store.practiceName), "unknown" to tr("全部不熟的詞")), src, { src = it })
        }
    }
    Txt(tr("離開 App 的時候，通知（也在鎖定畫面）顯示一個不熟的詞和它的讀音，平常是「不熟」的練習範圍裡的詞。拉開看得到意思，可以換下一個詞；點一下就打開那個詞的詞條。回到 App 的時候就收起來。"),
        ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
}
