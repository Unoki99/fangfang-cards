package com.unoki99.fangfang

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
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
        val scheme = darkColorScheme(primary = T.greenInk, onPrimary = T.bg, background = T.bg, surface = T.fn, onSurface = T.glyph,
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
                    Txt("${Math.round(Store.loadProgress * 100)}%　第一次打開比較久，在模擬器上可能要一分鐘。", ff(FF.Footnote), T.muted)
                }
            }
        } else Tabs()
    }
    Store.zhError?.let { e ->
        AlertDialog(onDismissRequest = { Store.zhError = null }, containerColor = T.fn,
            title = { Txt("華語", ff(FF.Headline)) }, text = { Txt(e, ff(FF.Body)) },
            confirmButton = { TextButton(onClick = { Store.zhError = null }) { Text("好", color = T.greenInk) } })
    }
    UI.practice?.let { PracticeHost(it) }
    if (UI.settingsOpen) SettingsScreen()
    Sheets()
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
            key(tab, zh, lv) { StackHost(UI.tabs[tab]) {
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
                    icon = { Icon(if (on) it.on else it.icon, it.title) },
                    label = { Text(it.title) },
                    colors = NavigationBarItemDefaults.colors(selectedIconColor = T.greenInk, selectedTextColor = T.greenInk,
                        indicatorColor = T.green, unselectedIconColor = T.muted, unselectedTextColor = T.muted),
                )
            }
        }
    }
}
