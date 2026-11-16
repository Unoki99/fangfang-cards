package com.unoki99.fangfang.desktop

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.isBackPressed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.Configuration
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.loadImageBitmap
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import com.unoki99.fangfang.*
import com.unoki99.fangfang.ui.*
import kotlinx.coroutines.delay
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

// 方方詞卡 for Windows: the window, with the same screens as the Android app (App(), AppRoot.kt). Esc (or the mouse's
// back button) is Android's back. Started again with a link (fangfangcards://… from the Firefox add-on's 傳到 App), it
// hands the link to the one already open (Links.kt).

/** a short message at the bottom of the window (the words a link brought) */
object Note {
    var text by mutableStateOf<String?>(null)
}

fun main(args: Array<String>) {
    // a crash is written down, and shown the next time the program opens (so it can be sent to be fixed)
    val crashFile = File(DesktopContext.filesDir, "last-crash.txt")
    Thread.setDefaultUncaughtExceptionHandler { t, e ->
        try {
            val sw = StringWriter(); e.printStackTrace(PrintWriter(sw))
            crashFile.writeText("${e.javaClass.simpleName}: ${e.message}\n(${t.name})\n" + sw.toString().lines().take(25).joinToString("\n"))
        } catch (_: Throwable) {}
        e.printStackTrace()
    }
    // (already open: the link goes to it, and this one ends)
    if (!Links.firstOne(args)) return

    Prefs.init(DesktopContext)
    // (a mouse: words swell under the pointer, and the lyrics open word by word)
    com.unoki99.fangfang.ui.PointerUI.mouse = true
    Store.init(DesktopContext)
    Radio.init(DesktopContext)
    if (crashFile.exists()) {
        val t = try { crashFile.readText().take(1500) } catch (_: Exception) { "" }
        crashFile.delete()
        if (t.isNotBlank()) Store.zhError = "上次當掉了（可以把這段傳給 Claude）：\n$t"
    }
    Links.pending.addAll(args.filter { it.startsWith("fangfangcards:") })

    val icon = try { Thread.currentThread().contextClassLoader.getResourceAsStream("icon.png")?.use { BitmapPainter(loadImageBitmap(it)) } } catch (_: Exception) { null }

    application {
        val state = rememberWindowState(size = DpSize(1280.dp, 880.dp), position = WindowPosition(Alignment.Center))
        fun quit() {
            try { Store.saveNow() } catch (_: Exception) {}
            try { Backup.syncNow() } catch (_: Exception) {}
            try { Radio.stop() } catch (_: Exception) {}
            exitApplication()
        }
        Window(onCloseRequest = ::quit, state = state, title = "方方詞卡", icon = icon,
            onKeyEvent = { e -> if (e.type == KeyEventType.KeyDown && e.key == Key.Escape) Back.go() else false }) {
            FilePick.window = window
            Links.window = window
            // (the window left: saved, and the backup folder written; coming back: the other devices' read)
            DisposableEffect(window) {
                var lastSync = 0L
                val l = object : WindowAdapter() {
                    override fun windowGainedFocus(e: WindowEvent?) {
                        if (!Store.loaded) return
                        val now = System.currentTimeMillis()
                        if (now - lastSync > 120_000) { lastSync = now; try { Backup.syncNow() } catch (_: Exception) {}; BrowserImport.apply() }
                    }
                    override fun windowLostFocus(e: WindowEvent?) { if (Store.loaded) try { Store.saveNow() } catch (_: Exception) {} }
                }
                window.addWindowFocusListener(l)
                onDispose { window.removeWindowFocusListener(l) }
            }
            // links that came (at the start, or from a second start), once the words are loaded
            LaunchedEffect(Store.loaded, Links.version) {
                if (Store.loaded) Links.takeAll()
            }
            BoxWithConstraints(Modifier.fillMaxSize().pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        val e = awaitPointerEvent(PointerEventPass.Initial)
                        if (e.type == PointerEventType.Press && e.buttons.isBackPressed) Back.go()
                    }
                }
            }) {
                val conf = Configuration(maxWidth.value.toInt(), maxHeight.value.toInt())
                CompositionLocalProvider(LocalConfiguration provides conf) {
                    App()
                }
                Note.text?.let { t ->
                    LaunchedEffect(t) { delay(3500); Note.text = null }
                    Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 96.dp).clip(RoundedCornerShape(14.dp))
                        .background(T.fn).border(1.5.dp, T.fnEdge, RoundedCornerShape(14.dp)).padding(horizontal = 18.dp, vertical = 10.dp)) {
                        Txt(t, ff(FF.Body), T.glyph)
                    }
                }
            }
        }
    }
}
