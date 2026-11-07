package com.unoki99.fangfang

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.unoki99.fangfang.ui.*

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Prefs.init(applicationContext)
        Store.init(applicationContext)
        enableEdgeToEdge()
        setContent { App() }
    }

    override fun onPause() {
        super.onPause()
        Store.saveNow()
        Backup.syncNow()
    }
}

@Composable
fun App() {
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
    // a place or tone colours chosen: the dictionary is needed (local readings, word classes)
    val place = Prefs.place.value; val tones = Prefs.toneSys.value; val rom = Prefs.rom.value
    LaunchedEffect(place, tones, Prefs.toneMarks.value) {
        if (place >= 0 || tones != 0) Store.loadDict()
        if (Store.loaded) { WidgetBridge.writeState(); WidgetBridge.rebuildIfNeeded() }
    }
    LaunchedEffect(rom) { if (Store.loaded) WidgetBridge.writeState() }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val obs = LifecycleEventObserver { _, e ->
            if (e == Lifecycle.Event.ON_RESUME && Store.loaded) { Backup.syncNow(); WidgetBridge.appOpened() }
        }
        owner.lifecycle.addObserver(obs)
        onDispose { owner.lifecycle.removeObserver(obs) }
    }

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
        } else Tabs()
    }
    Store.zhError?.let { e ->
        AlertDialog(onDismissRequest = { Store.zhError = null }, containerColor = T.fn,
            title = { Txt(tr("華語"), ff(FF.Headline)) }, text = { Txt(e, ff(FF.Body)) },
            confirmButton = { TextButton(onClick = { Store.zhError = null }) { Text(tr("好"), color = T.btnInk) } })
    }
    UI.practice?.let { PracticeHost(it) }
    if (UI.settingsOpen) SettingsScreen()
    Sheets()
    // the very first time: which language to learn (later: 設定 → 語言). Not asked of someone who used the app
    // before this question was added.
    if (Store.loaded && !Prefs.pickedLanguage.value) {
        if (Store.seenCount > 0 || Prefs.lang.value == 1) SideEffect { Prefs.pickedLanguage.value = true }
        else LanguageWelcome { zh -> Store.setLanguage(zh); Prefs.pickedLanguage.value = true }
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
            // 台語 ⇄ 華語: every page starts again with the other deck
            val zh = Store.isZh
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

/** the very first time the app opens: 台語 or 華語 (can be changed any time in 設定 → 語言) */
@Composable
private fun LanguageWelcome(pick: (Boolean) -> Unit) {
    BackHandler { }
    AppBackground {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Txt(tr("方方詞卡"), ff(FF.LargeTitle, FontWeight.Bold), T.glyph)
                Txt(tr("你想先學哪一種？"), ff(FF.Title3), T.muted)
                Txt("Which language would you like to start with?", ff(FF.Subheadline), T.muted)
            }
            Column(Modifier.widthIn(max = 520.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                for (zh in listOf(false, true)) {
                    val fill = if (zh) T.blue else T.own; val edge = if (zh) T.blueEdge else T.ownEdge; val ink = if (zh) T.blueInk else T.purpleInk
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(fill).border(2.dp, edge, RoundedCornerShape(22.dp))
                        .clickable { pick(zh) }.padding(18.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                        Box(Modifier.size(70.dp).clip(CircleShape).background(edge.copy(alpha = 0.35f)), contentAlignment = Alignment.Center) {
                            Txt(if (zh) "華" else "台", sz(44f, FontWeight.Bold), ink)
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Txt(if (zh) "華語" else "台語", ff(FF.Title2, FontWeight.Bold), ink)
                                if (!UILang.english) Txt(if (zh) "Mandarin" else "Taiwanese", ff(FF.Subheadline), ink.copy(alpha = 0.8f))
                                else Txt(if (zh) "Mandarin" else "Taiwanese", ff(FF.Subheadline, FontWeight.SemiBold), ink)
                            }
                            Txt(tr(if (zh) "《兩岸常用詞典》的詞，HSK／TOCFL，拼音或注音" else "教育部《臺灣台語常用詞辭典》的詞，皓羅、台羅、白話字或方音"),
                                ff(FF.Footnote), T.glyph.copy(alpha = 0.85f))
                        }
                        Icon(Icons.Filled.ChevronRight, null, tint = ink.copy(alpha = 0.7f))
                    }
                }
            }
            Txt(tr("之後可以在「設定 → 語言與讀音」換。"), ff(FF.Footnote), T.muted)
        }
    }
}
