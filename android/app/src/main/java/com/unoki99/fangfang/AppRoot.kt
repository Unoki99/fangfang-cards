package com.unoki99.fangfang

// The app's screens, from the top: the theme, the tabs, the first-time language choice. The same code makes the
// Android app (MainActivity) and the Windows app (windows/, Main.kt): nothing here is Android's own.

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.ui.*

@Composable
fun App() {
    // (a dictionary made by an older version of the app: made again, with what's new)
    LaunchedEffect(Unit) { DictInstaller.updateOutdated() }
    val theme = Prefs.theme.value
    // the theme's colours are read while drawing: set it first, then draw everything again
    key(theme) {
        T.syncEngine()
        val scheme = darkColorScheme(primary = T.btnInk, onPrimary = T.bg, background = T.bg, surface = T.fn, onSurface = T.glyph,
            onBackground = T.glyph, surfaceVariant = T.fn, onSurfaceVariant = T.muted, secondary = T.oliveInk, outline = T.fnEdge)
        val base = LocalDensity.current
        val factor = TextSize.factor(Prefs.textSize.value)
        CompositionLocalProvider(LocalDensity provides Density(base.density, base.fontScale * factor)) {
            MaterialTheme(colorScheme = scheme) {
                ProvideTextStyle(TextStyle(fontFamily = AppTheme.of(theme).fontFamily, color = T.glyph)) {
                    Root()
                }
            }
        }
    }
}

@Composable
private fun Root() {
    LaunchedEffect(Unit) { Store.load() }
    // (設定 closed: it opens on its first page next time)
    LaunchedEffect(UI.settingsOpen) { if (!UI.settingsOpen) Kept.map.remove("settings.page") }
    // a place or tone colours chosen: the dictionary is needed (local readings, word classes)
    val place = Prefs.place.value; val tones = Prefs.toneSys.value; val rom = Prefs.rom.value
    LaunchedEffect(place, tones, Prefs.toneMarks.value, Prefs.hongimTone1.value, Prefs.hongimTone1Space.value, Prefs.hongimSpaceAll.value, Prefs.hongimLightKeep.value) {
        if (place >= 0 || tones != 0) Store.loadDict()
        if (Store.loaded) { WidgetBridge.writeState(); WidgetBridge.rebuildIfNeeded() }
    }
    LaunchedEffect(rom) { if (Store.loaded) WidgetBridge.writeState() }
    // (coming back to the app: the backup folder read again — in MainActivity.onResume, and the Windows window's focus)

    AppBackground {
        if (!Store.loaded) {
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                if (Store.loadError == null) CircularProgressIndicator(color = T.greenInk)
                Spacer(Modifier.height(14.dp))
                Txt(Store.loadError ?: Store.loadStep, ff(FF.Body), T.muted)
                if (Store.loadError == null) {
                    Spacer(Modifier.height(10.dp))
                    LinearProgressIndicator(progress = { Store.loadProgress }, modifier = Modifier.width(220.dp), color = T.greenInk, trackColor = T.fn)
                    Spacer(Modifier.height(8.dp))
                    Txt(tr("{0}%　第一次打開比較久，在模擬器上可能要一分鐘。", Math.round(Store.loadProgress * 100)), ff(FF.Footnote), T.muted)
                }
            }
        } else {
            Tabs()
            // no 台語 data yet: install it here
            TaigiMissingOverlay()
        }
    }
    Store.zhError?.let { e ->
        AlertDialog(onDismissRequest = { Store.zhError = null }, containerColor = T.fn,
            title = { Txt(tr("詞典"), ff(FF.Headline)) }, text = { Txt(e, ff(FF.Body)) },
            confirmButton = { TextButton(onClick = { Store.zhError = null }) { Text(tr("好"), color = T.btnInk) } })
    }
    Store.speechHint?.let { e ->
        AlertDialog(onDismissRequest = { Store.speechHint = null }, containerColor = T.fn,
            title = { Txt(tr("粵語的語音"), ff(FF.Headline)) }, text = { Txt(e, ff(FF.Body)) },
            confirmButton = { TextButton(onClick = { Store.speechHint = null }) { Text(tr("好"), color = T.btnInk) } })
    }
    UI.practice?.let { PracticeHost(it) }
    if (UI.radioOpen) RadioScreen()
    if (UI.settingsOpen) SettingsScreen()
    if (UI.profileOpen) { BackHandler { UI.profileOpen = false }; ProfileScreen { UI.profileOpen = false } }
    Sheets()
    // the very first time: which language to learn (later: 設定 → 語言). Not asked of someone who used the app
    // before this question was added.
    if (Store.loaded && !Prefs.pickedLanguage.value) {
        if (Store.seenCount > 0 || Prefs.lang.value != 0) SideEffect { Prefs.pickedLanguage.value = true }
        else LanguageWelcome { l -> Store.setLanguage(l); Prefs.pickedLanguage.value = true }
    }
}

private class TabItem(val value: Int, val title: String, val icon: ImageVector, val on: ImageVector)

@Composable
private fun Tabs() {
    // order: 新詞 不熟 詞典 熟悉 轉換
    val items = listOf(
        TabItem(0, "新詞", Icons.Outlined.Layers, Icons.Filled.Layers),
        TabItem(1, "不熟", Icons.Outlined.HelpOutline, Icons.Filled.Help),
        TabItem(4, "詞典", Icons.Outlined.MenuBook, Icons.Filled.MenuBook),
        TabItem(2, "熟悉", Icons.Outlined.CheckCircle, Icons.Filled.CheckCircle),
        TabItem(3, "轉換", Icons.Outlined.SwapHoriz, Icons.Filled.SwapHoriz),
    )
    Column(Modifier.fillMaxSize().imePadding()) {
        Box(Modifier.weight(1f)) {
            val tab = UI.tab
            // 台語 ⇄ 華語 ⇄ 粵語: every page starts again with the other deck
            val zh = Store.lang
            val lv = Store.listVersion
            LaunchedEffect(zh) { for (t in UI.tabs) t.stack.clear() }
            key(tab, zh, lv, Prefs.uiLanguage.value) { StackHost(UI.tabs[tab]) {
                when (tab) {
                    0 -> NewDeckTab()
                    1 -> UnknownTab()
                    2 -> KnownTab()
                    3 -> ConverterTab()
                    else -> DictionaryTab()
                }
            } }
        }
        if (!(UI.hideTabs && UI.tab == 0)) NavigationBar(containerColor = T.fn.copy(alpha = 0.96f), tonalElevation = 0.dp) {
            for (it in items) {
                val on = UI.tab == it.value
                NavigationBarItem(
                    selected = on,
                    onClick = { if (on) UI.tabs[it.value].stack.clear() else UI.tab = it.value },
                    icon = { Icon(if (on) it.on else it.icon, tr(it.title)) },
                    label = { Text(tr(it.title)) },
                    colors = NavigationBarItemDefaults.colors(selectedIconColor = T.greenInk, selectedTextColor = T.greenInk,
                        indicatorColor = T.green, unselectedIconColor = T.muted, unselectedTextColor = T.muted),
                )
            }
        }
    }
}

/** the very first time the app opens: the app's language and each language's spelling, then which language to learn
 *  first; its dictionary is downloaded and made then (the app has none built in). Changed later in 設定. */
@Composable
private fun LanguageWelcome(pick: (Int) -> Unit) {
    BackHandler { }
    var step by remember { mutableStateOf(0) }
    var installing by remember { mutableStateOf<Int?>(null) }
    // made: into the app, in that language
    val v = DictInstaller.version
    LaunchedEffect(v, installing) {
        val l = installing ?: return@LaunchedEffect
        val p = DictPack.of(l) ?: return@LaunchedEffect
        if (DataFiles.has(p.outputs.first())) pick(l)
    }
    fun choose(l: Int) {
        val p = DictPack.of(l)
        if (p == null || DataFiles.has(p.outputs.first())) { pick(l); return }
        installing = l
        if (DictInstaller.state(p) !is InstallState.Working) DictInstaller.install(p)
    }
    AppBackground {
        val l = installing
        if (l != null) {
            Column(Modifier.fillMaxSize().dragScrollY(rememberScrollState()), verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally) {
                InstallPanel(l, onSkip = { pick(l) }, onBack = { installing = null })
            }
        } else if (step < SETUP_STEPS) {
            // the steps before choosing the language (the same as the iPhone app's): 0 the app's language and 正體 /
            // 簡體; 1 the meanings and each language's spelling; 2 each language's 腔口 / reading; 3 tone colours and 方音
            fun meaningsEnglish(en: Boolean) { Prefs.zhEnglish.value = en; Prefs.twEnglish.value = en; Prefs.hakEnglish.value = en }
            LaunchedEffect(Unit) { if (Prefs.uiLanguage.value == 1) meaningsEnglish(true) }
            Column(Modifier.fillMaxSize().dragScrollY(rememberScrollState()).padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(22.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
                Row(Modifier.widthIn(max = 520.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    if (step > 0) TextButton(onClick = { step -= 1 }) { Text(tr("上一步"), color = T.muted) }
                    Spacer(Modifier.weight(1f))
                    Txt("${step + 1}／${SETUP_STEPS + 1}", ff(FF.Caption), T.muted)
                }
                Txt(tr("方方詞卡"), ff(FF.LargeTitle, FontWeight.Bold), T.glyph)
                Column(Modifier.widthIn(max = 520.dp).clip(RoundedCornerShape(22.dp)).background(T.fn.copy(alpha = 0.8f))
                    .border(1.5.dp, T.fnEdge, RoundedCornerShape(22.dp)).padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    when (step) {
                        0 -> {
                            SetupHeading(tr("App 的語言"), tr("按鈕、選單和說明的語言。"))
                            Segmented(listOf(0 to "中文", 1 to "English"), Prefs.uiLanguage.value, { Prefs.uiLanguage.value = it; meaningsEnglish(it == 1) })
                            SetupHeading(tr("字形"), tr("華語、粵語和日語的漢字用正體字還是簡體字（台語和客語的詞典是正體字）。"))
                            Segmented(listOf(false to tr("正體字"), true to tr("簡體字")), Prefs.simplified.value, { Prefs.simplified.value = it; Store.simplifiedChanged() })
                        }
                        1 -> {
                            SetupHeading(tr("解釋先用哪一種語言？"), tr("卡片和列表上先顯示的解釋（粵語的解釋是英文）。點進一個詞兩種都看得到。"))
                            Segmented(listOf(false to tr("華語"), true to tr("英文")), Prefs.zhEnglish.value, { meaningsEnglish(it) })
                            SetupHeading(tr("每個語言用哪一種拼寫？"), tr("台語選「方音」的話只顯示方音；其他的下面會再加一行方音。"))
                            Spelling(0, Prefs.rom, listOf("皓羅", "台羅", "白話字", "方音"))
                            Spelling(1, Prefs.mandRom, listOf("拼音", "注音"))
                            Spelling(2, Prefs.yueRom, listOf("粵拼", "耶魯"))
                            Spelling(3, Prefs.hakRom, listOf("拼音", "注音"))
                            Spelling(4, Prefs.jaRom, listOf("羅馬字", "假名"))
                            Spelling(5, Prefs.svRom, listOf("詞素", "不顯示"))
                        }
                        2 -> {
                            SetupHeading(tr("每個語言照哪裡的讀音？"), tr("台語的「通行」是教育部辭典的讀音；選一個地方的話，詞典有記錄的地方讀音會換成那裡的。"))
                            val place = Prefs.place.value
                            SetupMenu(0, if (place in PLACE_NAMES.indices) tr(PLACE_NAMES[place]) else tr("通行"), listOf(-1 to tr("通行")) + PLACE_NAMES.mapIndexed { i, p -> i to tr(p) }) { Prefs.place.value = it }
                            Spelling(1, Prefs.zhPlace, listOf("臺灣", "大陸"))
                            SetupMenu(3, tr(com.unoki99.fangfang.engine.Lang.hakAccents.getOrElse(Prefs.hakAccent.value) { "四縣" }),
                                com.unoki99.fangfang.engine.Lang.hakAccents.mapIndexed { i, p -> i to tr(p) }) { Prefs.hakAccent.value = it }
                        }
                        else -> {
                            SetupHeading(tr("聲調顏色"), tr("每個字照聲調上顏色。七聲、五聲只差在台語：五聲把台語的聲調合成五種顏色；其他語言打開就是照自己的聲調。"))
                            Segmented(listOf(0 to tr("關"), 7 to tr("七聲"), 5 to tr("五聲")), Prefs.toneSys.value, { Prefs.toneSys.value = it })
                            SetupHeading(tr("方音（台語的注音）"))
                            SetupSwitch(tr("方音標第一聲（ˉ）"), Prefs.hongimTone1)
                            SetupSwitch(tr("第一聲的地方空一格"), Prefs.hongimTone1Space, enabled = !Prefs.hongimTone1.value)
                            SetupSwitch(tr("方音每個音節中間空一格"), Prefs.hongimSpaceAll)
                            SetupSwitch(tr("方音輕聲保留原本的調號"), Prefs.hongimLightKeep)
                            // (what it looks like: 食飯, 一寡; read again whenever one of them changes)
                            Prefs.hongimTone1.value; Prefs.hongimTone1Space.value; Prefs.hongimSpaceAll.value; Prefs.hongimLightKeep.value
                            val e = com.unoki99.fangfang.engine.EngineSettings
                            val sample = e.hongim("ㄐㄧㄚㆷ˙ㄅㆭ˫") + "　" + e.hongim("ㄐㄧㆵ˙") + (if (Prefs.hongimSpaceAll.value) " " else "") + e.hongimLight("ㄍㄨㄚˋ")
                            Txt(tr("例：") + sample, ff(FF.Title3), T.purpleInk)
                        }
                    }
                }
                ProminentButton(onClick = { step += 1 }, modifier = Modifier.widthIn(min = 240.dp)) { Text(tr("下一步")) }
                Txt(tr("這些之後都可以在「設定」改。"), ff(FF.Caption), T.muted)
            }
        } else {
            Column(Modifier.fillMaxSize().dragScrollY(rememberScrollState()).padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
                Row(Modifier.widthIn(max = 520.dp).fillMaxWidth()) {
                    TextButton(onClick = { step = SETUP_STEPS - 1 }) { Text(tr("上一步"), color = T.muted) }
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Txt(tr("方方詞卡"), ff(FF.LargeTitle, FontWeight.Bold), T.glyph)
                    Txt(tr("你想先學哪一種？"), ff(FF.Title3), T.muted)
                }
                Column(Modifier.widthIn(max = 520.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    for (n in 0..4) {
                        val (fill, edge, ink) = langColors(n)
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(fill).border(2.dp, edge, RoundedCornerShape(22.dp))
                            .clickable { choose(n) }.padding(18.dp), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                            Box(Modifier.size(70.dp).clip(CircleShape).background(edge.copy(alpha = 0.35f)), contentAlignment = Alignment.Center) {
                                Txt(listOf("台", "華", "粵", "客", "日")[n], sz(44f, FontWeight.Bold), ink)
                            }
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Txt(listOf("台語", "華語", "粵語", "客語", "日語")[n], ff(FF.Title2, FontWeight.Bold), ink)
                                    Txt(listOf("Taiwanese", "Mandarin", "Cantonese", "Hakka", "Japanese")[n], ff(FF.Subheadline), ink.copy(alpha = 0.8f))
                                }
                                Txt(tr(listOf("教育部《臺灣台語常用詞辭典》的詞，皓羅、台羅、白話字或方音", "《兩岸常用詞典》的詞，HSK／TOCFL，拼音或注音",
                                    "CC-Canto、CC-CEDICT 和 rime-cantonese 的詞，粵拼或耶魯拼音", "教育部《臺灣客語辭典》的詞，六個腔，拼音或注音",
                                    "JMdict 和 KANJIDIC2 的詞和漢字，假名或羅馬字")[n]), ff(FF.Footnote), T.glyph.copy(alpha = 0.85f))
                            }
                            Icon(Icons.Filled.ChevronRight, null, tint = ink.copy(alpha = 0.7f))
                        }
                    }
                }
                Txt(tr("選了以後會下載那個語言的詞典，在這台裝置上整理好（App 裡面沒有內建詞典）。之後可以在「設定 → 語言與讀音」換，其他語言的詞典在「設定 → 詞典資料」安裝。"),
                    ff(FF.Footnote), T.muted, Modifier.widthIn(max = 520.dp))
            }
        }
    }
}

private const val SETUP_STEPS = 4

@Composable
private fun SetupHeading(t: String, note: String? = null) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Txt(t, ff(FF.Headline), T.glyph)
        if (note != null) Txt(note, ff(FF.Caption), T.muted)
    }
}

@Composable
private fun SetupSwitch(t: String, pref: Pref<Boolean>, enabled: Boolean = true) {
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled) { pref.value = !pref.value }, verticalAlignment = Alignment.CenterVertically) {
        Txt(t, ff(FF.Body), if (enabled) T.glyph else T.muted, Modifier.weight(1f))
        Switch(pref.value, { pref.value = it }, enabled = enabled, colors = SwitchDefaults.colors(checkedTrackColor = T.btnEdge, checkedThumbColor = T.btnInk))
    }
}

/** one language's 腔口, as a menu */
@Composable
private fun <V> SetupMenu(l: Int, current: String, options: List<Pair<V, String>>, onPick: (V) -> Unit) {
    val (_, _, ink) = langColors(l)
    var open by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Txt(tr(listOf("台語", "華語", "粵語", "客語", "日語", "瑞典語")[l]), ff(FF.Subheadline, FontWeight.Bold), ink, Modifier.width(64.dp))
        Box(Modifier.weight(1f)) {
            SoftButton({ open = true }, Modifier.fillMaxWidth()) { Text(current) }
            DropdownMenu(open, { open = false }, containerColor = T.fn) {
                for ((v, n) in options) DropdownMenuItem(text = { Text(n, color = T.glyph) }, onClick = { onPick(v); open = false })
            }
        }
    }
}

/** one language's spelling, on the first screen */
@Composable
private fun Spelling(l: Int, pref: Pref<Int>, names: List<String>) {
    val (_, _, ink) = langColors(l)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Txt(tr(listOf("台語", "華語", "粵語", "客語", "日語", "瑞典語")[l]), ff(FF.Subheadline, FontWeight.Bold), ink, Modifier.width(64.dp))
        Box(Modifier.weight(1f)) {
            Segmented(names.indices.map { it to tr(names[it]) }, pref.value.coerceIn(0, names.size - 1), { pref.value = it })
        }
    }
}
