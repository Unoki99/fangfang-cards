package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import kotlinx.coroutines.launch
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.*
import com.unoki99.fangfang.engine.Dict
import com.unoki99.fangfang.engine.Lang
import com.unoki99.fangfang.engine.SavedSense
import com.unoki99.fangfang.engine.SenseCopy
import com.unoki99.fangfang.engine.ToneColors
import androidx.compose.foundation.border
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import java.text.DateFormat
import java.util.Date

@Composable
fun SettingsScreen() {
    val ctx = LocalContext.current
    var page by remember { mutableStateOf<Int?>(null) }
    BackHandler { if (page == 9) page = 3 else if (page == 10) page = 0 else if (page != null) page = null else UI.settingsOpen = false }
    var message by remember { mutableStateOf<String?>(null) }
    var confirmReset by remember { mutableStateOf(false) }
    var copyZh by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf("") }
    val saveFile = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("*/*")) { uri ->
        if (uri != null) try {
            ctx.contentResolver.openOutputStream(uri)?.use { it.write(pending.toByteArray()) }
            message = tr("已儲存。")
        } catch (e: Exception) { message = tr("匯出失敗。") }
    }
    /** importing a backup: how far it is (null = not importing) */
    var importing by remember { mutableStateOf<Float?>(null) }
    val scope = rememberCoroutineScope()
    val openFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            val text = try { ctx.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) } } catch (_: Exception) { null }
            if (text == null) message = tr("讀不到這個檔案。")
            else {
                importing = 0f
                scope.launch {
                    val m = Store.importBackupWithProgress(text) { importing = it }
                    kotlinx.coroutines.delay(450)       // let the potion fill up before it goes
                    importing = null
                    message = m
                }
            }
        }
    }
    val pickFolder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) message = Backup.setFolder(uri)
    }

    val titles = listOf("顏色與外觀", "語言與讀音", "卡片與練習", "詞典", "聲音", "備份與同步", "匯出與匯入", "關於與資料來源").map { tr(it) }
    AppBackground(Modifier.background(T.bg)) {
        Column(Modifier.fillMaxSize().navigationBarsPadding().imePadding()) {
            Row(Modifier.fillMaxWidth().statusBarsPadding().height(52.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                val p = page
                if (p != null) IconButton(onClick = { page = if (p == 9) 3 else if (p == 10) 0 else null }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, tr("返回"), tint = T.glyph)
                } else Spacer(Modifier.width(12.dp))
                Txt(if (p == null) tr("設定") else if (p == 9) tr(if (copyZh) "複製意思的格式（華語）" else "複製意思的格式（台語）") else if (p == 10) tr("選聲調顏色") else titles[p], ff(FF.Headline), T.glyph, Modifier.weight(1f))
                TextButton(onClick = { UI.settingsOpen = false }) { Text(tr("完成"), color = T.btnInk) }
            }
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).widthIn(max = 700.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                when (page) {
                    null -> SettingsGrid(titles) { page = it }
                    0 -> LookPage { page = 10 }
                    10 -> ToneColorPickerBody()
                    1 -> LanguagePage()
                    2 -> {
                        Group {
                            SwitchRow(tr("卡片先隱藏意思（點一下才顯示）"), Prefs.hideMeaning)
                            RowDivider(); SwitchRow(tr("卡片先隱藏讀音（點一下才顯示）"), Prefs.hideReading)
                            RowDivider()
                            MenuRow(tr("華語卡片的解釋"), if (Prefs.zhEnglish.value) "英文" else "華語", listOf(false to "華語", true to "英文")) { Prefs.zhEnglish.value = it }
                            RowDivider()
                            Column(Modifier.padding(14.dp)) {
                                Txt(tr("手寫：筆"), ff(FF.Footnote, FontWeight.SemiBold), T.muted, Modifier.padding(bottom = 6.dp))
                                PenControls()
                            }
                            RowDivider()
                            Column(Modifier.padding(14.dp)) { InkColorControls() }
                            RowDivider()
                            MenuRow(tr("手寫：字體"), Kai.names[Kai.style], Kai.names.withIndex().map { it.index to it.value }) { Prefs.handFont.value = it }
                            RowDivider(); StepRow(tr("連續答對 {0} 次算學會", Prefs.goal.value), Prefs.goal, 1, 6, 1)
                            RowDivider(); StepRow(tr("每次練習 {0} 個詞", Prefs.sessionSize.value), Prefs.sessionSize, 5, 40, 5)
                            RowDivider(); SwitchRow(tr("寫字題"), Prefs.practiceWrite)
                        }
                        Txt(tr("開始練習和本週學習裡，看意思和讀音把整個詞寫出來，寫完自己對答案。"), ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp, vertical = 4.dp))
                        Spacer(Modifier.height(10.dp))
                        Group { ActionRow(tr("全部重來"), danger = true) { confirmReset = true } }
                        Txt(tr("所有的「熟悉」和「不熟」都清掉，從頭開始。"), ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
                    }
                    3 -> {
                        Group {
                            SwitchRow(tr("例句的詞分開一點"), Prefs.wordGap)
                            RowDivider()
                            Row(Modifier.fillMaxWidth().clickable { copyZh = false; page = 9 }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                Txt(tr("複製意思的格式（台語）"), ff(FF.Body), modifier = Modifier.weight(1f))
                                Txt(copyStyleName(false), ff(FF.Body), T.muted)
                                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted)
                            }
                            RowDivider()
                            Row(Modifier.fillMaxWidth().clickable { copyZh = true; page = 9 }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                Txt(tr("複製意思的格式（華語）"), ff(FF.Body), modifier = Modifier.weight(1f))
                                Txt(copyStyleName(true), ff(FF.Body), T.muted)
                                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted)
                            }
                        }
                        Txt(tr("台語和華語各有自己的複製格式。華語可以加英文解釋：{英文} 或 {英文列表}。"), ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
                        SectionTitle(tr("華語詞典：卡片和列表上的解釋"))
                        Group {
                            Column(Modifier.padding(14.dp)) {
                                Segmented(listOf(false to tr("華語"), true to tr("英文")), Prefs.zhEnglish.value, { Prefs.zhEnglish.value = it })
                            }
                        }
                        Txt(tr("卡片和查詞列表上先顯示哪一種解釋。點進一個詞以後兩種都看得到。"), ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
                        SectionTitle(tr("輸入法拆碼"))
                        Group {
                            SwitchRow(tr("在詞典顯示輸入法拆碼"), Prefs.imeOn)
                            if (Prefs.imeOn.value) {
                                RowDivider(); SwitchRow(tr("倉頡"), Prefs.imeCJ)
                                RowDivider(); SwitchRow(tr("五筆（86 版）"), Prefs.imeWB)
                                if (Store.inputCodes.has(2)) { RowDivider(); SwitchRow(tr("無蝦米"), Prefs.imeLiu) }
                            }
                        }
                        Txt(if (Store.inputCodes.has(2)) tr("顯示在詞典每個詞的上面。")
                            else tr("顯示在詞典每個詞的上面。無蝦米要用自己的碼表：把 .cin 檔放到 iOS 專案的 tools 資料夾，執行 build-data.sh ime，再把 inputcodes.json 放到 app/src/main/assets。"),
                            ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
                    }
                    4 -> {
                        Group {
                            SwitchRow(tr("新卡片自動播放發音"), Prefs.autoPlay)
                            RowDivider()
                            Row(Modifier.padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.VolumeMute, null, tint = T.muted)
                                Slider(Prefs.volume.value, { Prefs.volume.value = it }, Modifier.weight(1f), colors = SliderDefaults.colors(thumbColor = T.btnInk, activeTrackColor = T.btnEdge))
                                Icon(Icons.Filled.VolumeUp, null, tint = T.muted)
                            }
                            RowDivider()
                            var base by Prefs.audioBase
                            val fBase = remember { androidx.compose.ui.focus.FocusRequester() }
                            TextField(base, { base = it }, Modifier.fillMaxWidth().focusRequester(fBase), label = { Text(tr("音檔來源")) }, singleLine = true,
                                trailingIcon = { ClearIcon(base, { base = it }, fBase) },
                                colors = TextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent))
                            RowDivider()
                            ActionRow(tr("清除已下載的音檔")) { Player.clearCache(); message = tr("已清除。") }
                        }
                        Txt(tr("華語用手機內建的語音（設定 → 系統 → 語言 → 文字轉語音）。"), ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
                    }
                    5 -> {
                        Group {
                            val name = Backup.folderName
                            if (name != null) {
                                InfoRow(tr("資料夾"), name)
                                Prefs.lastBackup.value.toLongOrNull()?.let { RowDivider(); InfoRow(tr("上次備份"), DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(it))) }
                                RowDivider(); SwitchRow(tr("跟其他裝置同步"), Prefs.syncDevices)
                                RowDivider(); ActionRow(tr("立即備份")) { message = Backup.syncNow() }
                                RowDivider(); ActionRow(tr("換資料夾")) { pickFolder.launch(null) }
                                RowDivider(); ActionRow(tr("停止自動備份"), danger = true) { Backup.clearFolder() }
                            } else ActionRow(tr("選擇備份資料夾…")) { pickFolder.launch(null) }
                        }
                        Txt(tr("選一個資料夾（例如 Google 雲端硬碟或手機裡的資料夾），每次打開和離開 App 都會自動備份。其他裝置選同一個資料夾，進度就會互相同步（跟 iPhone／iPad 版的備份檔一樣）。每天另外存一份到「方方詞卡舊備份」，保留 14 天。"),
                            ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
                    }
                    6 -> {
                        Group {
                            ActionRow(tr("匯出「不熟」CSV")) { pending = Store.csv(Store.unknownCards); saveFile.launch(tr("方方-不熟.csv")) }
                            RowDivider(); ActionRow(tr("匯出「熟悉」CSV")) { pending = Store.csv(Store.knownCards); saveFile.launch(tr("方方-熟悉.csv")) }
                            RowDivider(); ActionRow(tr("備份檔另存")) { pending = Store.backupData(); saveFile.launch(tr("方方詞卡備份.json")) }
                            RowDivider(); ActionRow(tr("匯入備份／方方收藏")) { openFile.launch(arrayOf("application/json", "text/plain", "*/*")) }
                        }
                        Txt(tr("CSV 跟方方網站的收藏格式一樣（分號分隔，九欄）。用備份可以把進度搬到另一台裝置。匯入方方網站或 Safari 擴充功能的備份，收藏的詞會加到「不熟」。"),
                            ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
                    }
                    7 -> AboutPage()
                    9 -> SenseCopyEditor(copyZh)
                }
                Spacer(Modifier.height(60.dp))
            }
        }
    }
    importing?.let { v ->
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)).clickable(enabled = true) {}, contentAlignment = Alignment.Center) {
            Column(Modifier.widthIn(max = 360.dp).padding(30.dp).clip(RoundedCornerShape(22.dp)).background(T.fn)
                .border(1.5.dp, T.fnEdge, RoundedCornerShape(22.dp)).padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Txt(tr("匯入備份中…"), ff(FF.Headline), T.glyph)
                PotionBar(v.toDouble(), 28.dp, showMarks = false, label = tr("匯入進度"))
                Txt("${Math.round(v * 100)}%", lat(15f), T.muted)
                Txt(tr("資料很多的時候要等一下，請不要關掉 App。"), ff(FF.Caption), T.muted)
            }
        }
    }
    message?.let { m ->
        AlertDialog(onDismissRequest = { message = null }, containerColor = T.fn, text = { Txt(m, ff(FF.Body)) },
            confirmButton = { TextButton(onClick = { message = null }) { Text(tr("好"), color = T.btnInk) } })
    }
    if (confirmReset) AlertDialog(onDismissRequest = { confirmReset = false }, containerColor = T.fn,
        text = { Txt(tr("所有的「熟悉」和「不熟」都會清掉，從頭開始。"), ff(FF.Body)) },
        confirmButton = { TextButton(onClick = { Store.resetAll(); confirmReset = false }) { Text(tr("全部重來"), color = Color(0xFFFF6B6B)) } },
        dismissButton = { TextButton(onClick = { confirmReset = false }) { Text(tr("取消"), color = T.muted) } })
}

private fun copyStyleName(zh: Boolean = Store.isZh): String =
    if (zh) SenseCopy.styleName(true, Prefs.zhCopyTpl.value, Prefs.zhCopyEx.value, Prefs.zhCopySep.value)
    else SenseCopy.styleName(false, Prefs.copyTpl.value, Prefs.copyEx.value, Prefs.copySep.value)

/** the topics, two to a row, each with what's set in it; with tone colours on, each tile is one of the tone colours */
@Composable
private fun SettingsGrid(titles: List<String>, open: (Int) -> Unit) {
    val ts = Prefs.toneSys.value
    val tones = when (ts) { 7 -> tr("七聲"); 5 -> tr("五聲"); else -> tr("聲調顏色關") }
    val lang = if (Store.isYue) tr("粵語") + "・" + tr(Lang.romNames[Prefs.zhRom.value.coerceIn(0, 1)])
        else if (Store.isZh) tr("華語") + "・" + tr(Lang.romNames[Prefs.zhRom.value.coerceIn(0, 1)]) + "・" + tr(Lang.placeNames[Prefs.zhPlace.value.coerceIn(0, 1)]) +
        "・" + Lang.listNames[Prefs.zhList.value.coerceIn(0, 1)]
        else tr("台語") + "・" + tr(ROM_NAMES[Prefs.rom.value.coerceIn(0, 2)]) + "・" + (if (Prefs.place.value in PLACE_NAMES.indices) tr(PLACE_NAMES[Prefs.place.value].take(2)) else tr("通行"))
    val summaries = listOf(
        tr(AppTheme.of(Prefs.theme.value).title) + "・" + tones,
        lang,
        tr("答對 {0} 次・每次 {1} 個", Prefs.goal.value, Prefs.sessionSize.value),
        tr("複製：{0}・拆碼{1}", copyStyleName(), if (Prefs.imeOn.value) tr("開") else tr("關")),
        tr("自動播放{0}・音量 {1}%", if (Prefs.autoPlay.value) tr("開") else tr("關"), Math.round(Prefs.volume.value * 100)),
        Backup.folderName ?: tr("還沒設定"),
        tr("CSV・備份檔"),
        tr("資料、授權"),
    )
    val icons = listOf(Icons.Filled.Palette, Icons.Filled.Translate, Icons.Filled.Layers, Icons.Filled.MenuBook,
        Icons.Filled.VolumeUp, Icons.Filled.Sync, Icons.Filled.IosShare, Icons.Filled.Info)
    TileGrid(titles.size, spacing = 12.dp) { i, m ->
        val c = if (ts != 0) ToneColors.color(listOf(1, 2, 3, 4, 5, 6, 7, 8)[i % 8], 7)?.let { Color(it) } else null
        Column(m.heightIn(min = 104.dp).clip(RoundedCornerShape(18.dp)).background(c?.copy(alpha = 0.16f) ?: T.fn.copy(alpha = 0.7f))
            .border(1.5.dp, c?.copy(alpha = 0.7f) ?: T.fnEdge, RoundedCornerShape(18.dp)).clickable { open(i) }.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icons[i], null, tint = c ?: T.oliveInk, modifier = Modifier.size(24.dp))
            Txt(titles[i], ff(FF.Headline), c ?: T.glyph, maxLines = 1)
            Txt(summaries[i], ff(FF.Caption), T.muted, maxLines = 2)
        }
    }
}

@Composable
private fun LookPage(openColors: () -> Unit) {
    Txt(tr("主題動畫關掉的話，背景（螢火蟲、星星、雪）和藥水條都不會動，比較省電。"), ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
    Group {
        var theme by Prefs.theme
        MenuRow(tr("主題"), tr(AppTheme.of(theme).title), AppTheme.entries.map { it.raw to tr(it.title) }) { theme = it }
        RowDivider(); SwitchRow(tr("主題動畫"), Prefs.themeMotion)
        RowDivider()
        val ts = Prefs.toneSys.value
        MenuRow(tr("聲調顏色"), when (ts) { 7 -> "七聲"; 5 -> "五聲"; else -> "關" }, listOf(0 to "關", 7 to "七聲", 5 to "五聲")) { Prefs.toneSys.value = it }
        if (ts != 0) {
            RowDivider(); SwitchRow(tr("聲調符號照變調寫"), Prefs.toneMarks)
            RowDivider(); SwitchRow(tr("聲調光暈"), Prefs.toneGlow)
        }
        RowDivider()
        Row(Modifier.fillMaxWidth().clickable { openColors() }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Txt(tr("選聲調顏色"), ff(FF.Body), modifier = Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                for (t in ToneColors.twTones) Box(Modifier.size(7.dp).clip(androidx.compose.foundation.shape.CircleShape).background(Color(ToneColors.twColor(t))))
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted)
        }
        RowDivider(); SwitchRow(tr("畫成圖再放大"), Prefs.swellAnim)
        RowDivider()
        Column(Modifier.padding(14.dp)) {
            val lvl = Prefs.textSize.value
            Row { Txt(tr("文字大小"), ff(FF.Body), modifier = Modifier.weight(1f)); Txt(TextSize.names[lvl.coerceIn(0, TextSize.names.size - 1)], ff(FF.Body), T.muted) }
            Slider(lvl.toFloat(), { Prefs.textSize.value = Math.round(it) }, valueRange = 0f..(TextSize.names.size - 1).toFloat(),
                steps = TextSize.names.size - 2, colors = SliderDefaults.colors(thumbColor = T.btnInk, activeTrackColor = T.btnEdge))
            Txt(tr("也會跟著手機的字型大小。"), ff(FF.Footnote), T.muted)
        }
    }
    SectionTitle(tr("小工具"))
    Group {
        Column(Modifier.padding(14.dp)) {
            val bg = Prefs.widgetBG.value
            Row {
                Txt(tr("背景"), ff(FF.Body), modifier = Modifier.weight(1f))
                Txt(if (bg < 0.05f) tr("透明") else if (bg > 0.95f) tr("不透明") else "${Math.round(bg * 100)}%", ff(FF.Body), T.muted)
            }
            Slider(bg, { Prefs.widgetBG.value = (Math.round(it * 20) / 20f) }, onValueChangeFinished = { WidgetBridge.writeState() },
                colors = SliderDefaults.colors(thumbColor = T.btnInk, activeTrackColor = T.btnEdge))
            Txt(tr("越往左越透明，看得到桌布。字會加一點陰影，比較好讀。在桌面長按 → 小工具 → 方方詞卡，可以加「分類詞卡」。"), ff(FF.Footnote), T.muted)
        }
    }
}

@Composable
private fun LanguagePage() {
    Group {
        Column(Modifier.padding(14.dp)) {
            Txt(tr("要學的語言"), ff(FF.Body))
            Spacer(Modifier.height(6.dp))
            Segmented(listOf(0 to tr("台語"), 1 to tr("華語"), 2 to tr("粵語")), Store.lang, { Store.setLanguage(it) })
        }
        RowDivider()
        Column(Modifier.padding(14.dp)) {
            Txt(tr("介面語言"), ff(FF.Body))
            Spacer(Modifier.height(6.dp))
            Segmented(listOf(0 to "中文", 1 to "English"), Prefs.uiLanguage.value, { Prefs.uiLanguage.value = it })
            Spacer(Modifier.height(6.dp))
            Txt(tr("按鈕、選單和說明的語言。詞典的內容（意思、例句）不會變。"), ff(FF.Footnote), T.muted)
        }
    }
    SectionTitle(tr("台語"))
    Group {
        Column(Modifier.padding(14.dp)) {
            Txt(tr("羅馬字"), ff(FF.Body))
            Spacer(Modifier.height(6.dp))
            Segmented(listOf(0 to tr("皓羅"), 1 to tr("台羅"), 2 to tr("白話字")), Prefs.rom.value, { Prefs.rom.value = it })
        }
        RowDivider()
        val place = Prefs.place.value
        MenuRow(tr("腔口"), if (place in PLACE_NAMES.indices) tr(PLACE_NAMES[place]) else tr("通行"), listOf(-1 to tr("通行")) + PLACE_NAMES.mapIndexed { i, p -> i to tr(p) }) {
            Prefs.place.value = it
        }
    }
    SectionTitle(tr("字形"))
    Group {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Segmented(listOf(false to tr("正體字"), true to tr("簡體字")), Prefs.simplified.value, {
                Prefs.simplified.value = it; Store.simplifiedChanged()
            })
            Txt(tr("華語和粵語的卡片、詞典和例句用哪一種字寫。台語一直用正體字；手寫練習也是正體字。"), ff(FF.Footnote), T.muted)
        }
    }
    // (each of 華語 and 粵語 has its own spelling; Prefs.zhRom is the one of the language shown)
    SectionTitle(tr("華語"))
    Group {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Txt(tr("拼寫"), ff(FF.Body))
            Segmented(listOf(0 to tr("拼音"), 1 to tr("注音")), if (Store.lang == 1) Prefs.zhRom.value else Prefs.mandRom.value,
                { if (Store.lang == 1) Prefs.zhRom.value = it else Prefs.mandRom.value = it })
            Txt(tr("讀音"), ff(FF.Body))
            Segmented(Lang.placeNames.mapIndexed { i, n -> i to tr(n) }, Prefs.zhPlace.value, { Prefs.zhPlace.value = it })
            Txt(tr("詞表"), ff(FF.Body))
            Segmented(Lang.listNames.mapIndexed { i, n -> i to n }, Prefs.zhList.value, { Store.setZhList(it) })
        }
    }
    SectionTitle(tr("粵語"))
    Group {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Txt(tr("拼寫"), ff(FF.Body))
            Segmented(listOf(0 to tr("粵拼"), 1 to tr("耶魯")), if (Store.lang == 2) Prefs.zhRom.value else Prefs.yueRom.value,
                { if (Store.lang == 2) Prefs.zhRom.value = it else Prefs.yueRom.value = it })
            Txt(tr("粵拼（香港語言學學會）或耶魯拼音。詞是照常用的程度分組，每組 500 個。"), ff(FF.Footnote), T.muted)
        }
    }
}

@Composable
private fun AboutPage() {
    Group {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Credit(tr("詞條、讀音、釋義、例句、音檔、近反義詞、異用字、腔口差異、各地講法、分類、華語對照詞"), "教育部《臺灣台語常用詞辭典》（創用CC 姓名標示-禁止改作 3.0 臺灣）。釋義、例句原文照錄，音檔未經修改；讀音依規則由台羅轉成皓羅、方音、白話字。")
            Credit(tr("推算的內容"), "辭典沒寫的腔口讀音和例句的腔口讀音是本 App 依規則推算的，不是教育部的資料，用紅色和「推測」標示。")
            Credit(tr("華語詞典"), "中華文化總會《兩岸常用詞典》（創用CC 姓名標示-非商業性-禁止改作）。拼音依注音照規則轉寫；例句的讀音依詞典的詞推算。")
            Credit(tr("英文解釋、補充讀音"), "CC-CEDICT（創用CC 姓名標示-相同方式分享 4.0）")
            Credit(tr("華語詞表"), "HSK 3.0（2021，ivankra/hsk30，MIT）、TOCFL 華語八千詞（2023，ivankra/tocfl）")
            Credit(tr("漢字卡、近義詞、反義詞"), "教育部《重編國語辭典修訂本》（創用CC 姓名標示-禁止改作 3.0 臺灣），g0v 萌典整理。解釋和用例照錄。")
            Credit(tr("部首組合"), "字的組成：cjkvi-ids（CHISE IDS，GPLv2）")
            Credit(tr("詞條、粵拼、英文解釋"), "CC-Canto（Pleco，CC BY-SA 3.0）、CC-CEDICT（CC BY-SA 4.0）")
            Credit(tr("意思、例句、華語對照、錄音"), "維基詞典（Wiktionary，經 kaikki.org wiktextract 整理，CC BY-SA 4.0）；錄音來自 Wikimedia Commons")
            Credit(tr("讀音、詞頻"), "rime-cantonese（CC BY 4.0／ODbL）")
            Credit(tr("漢字卡的字義"), "開放詞典《開放粵語字典》（kfcd/yyzd，CC BY 3.0）")
            Credit(tr("複習的間隔"), "照 SM-2 的方法自己寫的：Algorithm SM-2, (C) Copyright SuperMemo World, 1991. www.supermemo.com")
            Credit(tr("手寫練習的字體"), "文楷：霞鶩文楷 TC（Copyright 2022-2024 LXGW、2020 The Klee Project Authors）；芫荽：Iansui（Copyright 2025 The Iansui Project Authors）。都是 SIL Open Font License 1.1。")
            Credit(tr("輸入法拆碼"), "Rime 倉頡、五筆（rime-cangjie、rime-wubi）")
            Credit(tr("音節編碼"), "YuRen-tw《rime-taigi-tps》的拼音系統（經作者同意使用）")
            Credit(tr("轉換的朗讀"), TaigiSpeech.credit)
            Credit(tr("皓羅拼寫系統"), "Unoki99")
            Credit(tr("自補詞條"), "Unoki99 自行補充，非教育部辭典內容")
            Credit(tr("皓羅字型"), "DejaVu Sans（自由授權字型）")
            Credit(tr("方音"), "臺灣方音符號")
            Credit(tr("詞頻"), "依教育部辭典例句出現次數排序，Rime《八股文》（LGPL-3.0）輔助")
            Txt(tr("本 App 與教育部無關，不是官方產品。"), ff(FF.Footnote), T.muted)
        }
    }
}

/** 設定 → 詞典 → 複製意思的格式 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SenseCopyEditor(zh: Boolean = false) {
    var tpl by if (zh) Prefs.zhCopyTpl else Prefs.copyTpl
    var ex by if (zh) Prefs.zhCopyEx else Prefs.copyEx
    var sep by if (zh) Prefs.zhCopySep else Prefs.copySep
    val rom = Prefs.rom.value; val place = Prefs.place.value
    LaunchedEffect(Unit) { if (zh) Store.preloadZh() else Store.loadDict() }
    SectionTitle(tr("樣式"))
    Group {
        for ((i, p) in (if (zh) SenseCopy.zhPresets else SenseCopy.presets).withIndex()) {
            if (i > 0) RowDivider()
            Row(Modifier.fillMaxWidth().clickable { tpl = p.tpl; ex = p.ex; sep = p.sep }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Txt(tr(p.name), ff(FF.Body), modifier = Modifier.weight(1f))
                if (tpl == p.tpl && ex == p.ex && sep == p.sep) Icon(Icons.Filled.Check, null, tint = T.greenInk)
            }
        }
    }
    val mono = ff(FF.Footnote).copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, color = T.glyph)
    @Composable fun tokens(list: List<String>, add: (String) -> Unit) {
        FlowRow(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (t in list) Txt(t, ff(FF.Caption), T.oliveInk, Modifier.clip(RoundedCornerShape(50)).background(T.fn)
                .border(1.dp, T.fnEdge, RoundedCornerShape(50)).clickable { add(t) }.padding(horizontal = 8.dp, vertical = 3.dp))
        }
    }
    SectionTitle(tr("整個意思"))
    Group {
        val fTpl = remember { androidx.compose.ui.focus.FocusRequester() }
        TextField(tpl, { tpl = it }, Modifier.fillMaxWidth().heightIn(min = 110.dp).focusRequester(fTpl), textStyle = mono,
            trailingIcon = { ClearIcon(tpl, { tpl = it }, fTpl) },
            colors = TextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent))
        tokens(if (zh) SenseCopy.zhWordTokens else SenseCopy.wordTokens) { tpl += it }
    }
    Txt(tr("{所有例句} 是例句放的位置（沒寫就放在最後）。值是空的時候，旁邊的括號或 ** 也會一起拿掉。點下面的名字可以加到最後面。"), ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
    SectionTitle(tr("每個例句"))
    Group {
        val fEx = remember { androidx.compose.ui.focus.FocusRequester() }
        TextField(ex, { ex = it }, Modifier.fillMaxWidth().heightIn(min = 80.dp).focusRequester(fEx), textStyle = mono,
            trailingIcon = { ClearIcon(ex, { ex = it }, fEx) },
            colors = TextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent))
        tokens(if (zh) SenseCopy.zhExTokens else SenseCopy.exTokens) { ex += it }
        RowDivider()
        MenuRow(tr("例句跟例句中間"), SenseCopy.seps[sep.coerceIn(0, SenseCopy.seps.size - 1)], SenseCopy.seps.mapIndexed { i, n -> i to n }) { sep = it }
    }
    Txt((if (zh) tr("{羅馬字} 和 {例句羅馬字} 跟著上面選的拼音或注音；也可以直接用 {拼音}、{注音}。{英文} 是英文解釋（用 ; 分開），{英文列表} 是一行一個、有編號。")
        else tr("{羅馬字} 和 {例句羅馬字} 跟著設定裡選的羅馬字；也可以直接用 {皓羅}、{台羅}、{白話字}。")) + tr("Discord 看得懂 **粗體**、*斜體*、## 標題、> 引用、- 清單、-# 小字。"),
        ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
    SectionTitle(tr("預覽"))
    Group {
        val preview: String? = run {
            val z = Store.zh; val d = Store.dict
            if (zh && z != null) {
                val s = Store.savedSenses.firstOrNull { Lang.isZhKey(it.key) && Lang.charOf(it.key) == null }
                    ?: z.entries.firstOrNull { it.h == "吃飯" }?.let { SavedSense(it.k, 0) }
                s?.let { SenseCopy.zhText(z, it.key, it.sense, Prefs.zhRom.value, Prefs.zhPlace.value, tpl, ex, sep) }
            } else if (!zh && d != null) {
                val s = Store.savedSenses.firstOrNull { !Lang.isZhKey(it.key) } ?: listOf("食飯", "食", "行").firstNotNullOfOrNull { h -> d.raw.defs.m.keys.firstOrNull { Dict.hanOf(it) == h } }?.let { SavedSense(it, 0) }
                s?.let { SenseCopy.text(d, it.key, it.sense, rom, place, tpl, ex, sep) }
            } else null
        }
        Txt(preview ?: "詞典載入中…", mono, if (preview == null) T.muted else T.glyph, Modifier.fillMaxWidth().padding(14.dp))
    }
}

/** the same editor as a page of its own */
@Composable
fun SenseCopySettingsPage(onBack: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("複製意思的格式") + (if (Store.isZh) "（華語）" else "（台語）"), onBack, settings = false)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            SenseCopyEditor(Store.isZh)
            Spacer(Modifier.height(40.dp))
        }
    }
}

@Composable
private fun Group(content: @Composable ColumnScope.() -> Unit) = ListCard(content = content)

@Composable
private fun SwitchRow(title: String, pref: Pref<Boolean>) {
    Row(Modifier.fillMaxWidth().clickable { pref.value = !pref.value }.padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Txt(title, ff(FF.Body), modifier = Modifier.weight(1f))
        Switch(pref.value, { pref.value = it }, colors = SwitchDefaults.colors(checkedTrackColor = T.btnEdge, checkedThumbColor = T.btnInk))
    }
}

@Composable
private fun <V> MenuRow(title: String, current: String, options: List<Pair<V, String>>, onPick: (V) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.fillMaxWidth().clickable { open = true }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Txt(title, ff(FF.Body), modifier = Modifier.weight(1f))
            Txt(current, ff(FF.Body), T.greenInk)
            Icon(Icons.Filled.UnfoldMore, null, tint = T.muted, modifier = Modifier.size(18.dp))
        }
        DropdownMenu(open, { open = false }, containerColor = T.fn) {
            for ((v, name) in options) DropdownMenuItem(text = { Text(name, color = if (name == current) T.greenInk else T.glyph) }, onClick = { onPick(v); open = false })
        }
    }
}

@Composable
private fun StepRow(title: String, pref: Pref<Int>, min: Int, max: Int, step: Int) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Txt(title, ff(FF.Body), modifier = Modifier.weight(1f))
        IconButton(onClick = { pref.value = maxOf(min, pref.value - step) }, enabled = pref.value > min) { Icon(Icons.Filled.Remove, tr("少"), tint = T.glyph) }
        IconButton(onClick = { pref.value = minOf(max, pref.value + step) }, enabled = pref.value < max) { Icon(Icons.Filled.Add, tr("多"), tint = T.glyph) }
    }
}

@Composable
private fun ActionRow(title: String, danger: Boolean = false, onClick: () -> Unit) {
    Txt(title, ff(FF.Body), if (danger) Color(0xFFFF6B6B) else T.greenInk, Modifier.fillMaxWidth().clickable(onClick = onClick).padding(14.dp))
}

@Composable
private fun InfoRow(title: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(14.dp)) { Txt(title, ff(FF.Body), modifier = Modifier.weight(1f)); Txt(value, ff(FF.Body), T.muted) }
}

@Composable
private fun Credit(what: String, who: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Txt(what, ff(FF.Caption), T.muted)
        Txt(who, ff(FF.Footnote), T.glyph)
    }
}
