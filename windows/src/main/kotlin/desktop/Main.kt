package com.unoki99.fangfang.desktop

import androidx.compose.foundation.background
import androidx.compose.foundation.window.WindowDraggableArea
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
import androidx.compose.ui.input.key.isAltPressed
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
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

// 方方詞卡 for Windows and the Mac: the window, with the same screens as the Android app (App(), AppRoot.kt). Esc (or the mouse's
// back button) is Android's back. Started again with a link (fangfangcards://… from the Firefox add-on's 傳到 App), it
// hands the link to the one already open (Links.kt).

/** a short message at the bottom of the window (the words a link brought) */
object Note {
    var text by mutableStateOf<String?>(null)
}

fun main(args: Array<String>) {
    // (the computer version: 瑞典語 and 四川話 too)
    com.unoki99.fangfang.engine.EngineSettings.desktop = true
    FreezeWatch.start()
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
    // (YouTube 歌詞: the browser add-on's song, heard on this computer only)
    YtServer.start()
    if (crashFile.exists()) {
        val t = try { crashFile.readText().take(1500) } catch (_: Exception) { "" }
        crashFile.delete()
        if (t.isNotBlank()) Store.zhError = "上次當掉了：\n$t"
    }
    Links.pending.addAll(args.filter { it.startsWith("fangfangcards:") })
    if (Os.mac) {
        // (a Mac hands a fangfangcards:// link to the app that's open, instead of starting it with the link)
        try {
            java.awt.Desktop.getDesktop().setOpenURIHandler { e ->
                javax.swing.SwingUtilities.invokeLater { Links.pending.add(e.uri.toString()); Links.version++ }
            }
        } catch (_: Exception) {}
        // (⌘Q: saved and backed up first, as closing the window does)
        try {
            java.awt.Desktop.getDesktop().setQuitHandler { _, r ->
                Quitting.prepare()
                r.performQuit()
            }
        } catch (_: Exception) {}
    }

    // the window's icon: the usual dark one or the light one (設定 → 顏色與外觀 → App 圖示)
    fun loadIcon(name: String) = try { Thread.currentThread().contextClassLoader.getResourceAsStream(name)?.use { BitmapPainter(loadImageBitmap(it)) } } catch (_: Exception) { null }
    val darkIcon = loadIcon("icon.png")
    // (each theme's too: picked in 設定, the window's (and the Dock's) changes at once)
    val icons = HashMap<Int, BitmapPainter?>()
    com.unoki99.fangfang.AppIcon.set(com.unoki99.fangfang.Prefs.appIcon.value)

    application {
        val iconAt = com.unoki99.fangfang.Prefs.appIcon.value
        val icon = icons.getOrPut(iconAt) { loadIcon(com.unoki99.fangfang.AppIcon.file(iconAt)) } ?: darkIcon
        val state = rememberWindowState(size = DpSize(1280.dp, 880.dp), position = WindowPosition(Alignment.Center))
        fun quit() {
            Quitting.prepare()
            exitApplication()
        }
        Window(onCloseRequest = ::quit, state = state, title = "方方詞卡", icon = icon,
            // (歌詞對時's 對時間 open: its keys first, before any button or field: 空白鍵, Enter, ↑ ↓, Backspace, Ctrl+Z)
            onPreviewKeyEvent = { e -> EditorKeys.handler?.invoke(e) ?: false },
            // (Escape: back. ← →: the card deck on screen swiped, like its buttons; not when a text field has them)
            onKeyEvent = { e ->
                // (⇧ pressed and let go by itself, nothing typed with it: the top card's 詳細 open / closed, as on the iPad)
                val shiftKey = e.key == Key.ShiftLeft || e.key == Key.ShiftRight
                if (e.type == KeyEventType.KeyDown) LoneShift.down = shiftKey && !e.isCtrlPressed && !e.isMetaPressed && !e.isAltPressed
                if (e.type == KeyEventType.KeyUp && shiftKey) { val lone = LoneShift.down; LoneShift.down = false; if (lone) SwipeKeys.shift() else false }
                else if (e.type != KeyEventType.KeyDown) false
                else when (e.key) {
                    Key.Escape -> Back.go()
                    Key.DirectionLeft -> SwipeKeys.arrow(false)
                    Key.DirectionRight -> SwipeKeys.arrow(true)
                    // (⌫: the last card back, as on the iPad; ⇧ by itself: see below)
                    Key.Backspace -> SwipeKeys.back()
                    // (⌘+ ⌘− ⌘0 / Ctrl: the app's text size bigger, smaller, back to 100%, as on the iPad and the Mac)
                    Key.Equals, Key.Plus, Key.NumPadAdd -> if (e.isCtrlPressed || e.isMetaPressed) {
                        Prefs.textSize.value = (Prefs.textSize.value + 1).coerceAtMost(TextSize.names.size - 1); true } else false
                    Key.Minus, Key.NumPadSubtract -> if (e.isCtrlPressed || e.isMetaPressed) {
                        Prefs.textSize.value = (Prefs.textSize.value - 1).coerceAtLeast(0); true } else false
                    Key.Zero, Key.NumPad0 -> if (e.isCtrlPressed || e.isMetaPressed) { Prefs.textSize.value = 0; true } else false
                    // (⌘F / Ctrl+F: the cursor into the search field on screen)
                    Key.F -> if (e.isCtrlPressed || e.isMetaPressed) SearchFocus.focus() else false
                    else -> false
                }
            }) {
            FilePick.window = window
            Links.window = window
            // (the window left: saved, and the backup folder written; coming back: the other devices' read)
            DisposableEffect(window) {
                var lastSync = 0L
                val l = object : WindowAdapter() {
                    override fun windowGainedFocus(e: WindowEvent?) {
                        if (!Store.loaded) return
                        val now = System.currentTimeMillis()
                        // (away from the window: a backup folder iCloud keeps can take long to read, and the window froze)
                        if (now - lastSync > 120_000) { lastSync = now; FocusWork.run { try { Backup.syncNow() } catch (_: Exception) {}; javax.swing.SwingUtilities.invokeLater { BrowserImport.apply() } } }
                    }
                    override fun windowLostFocus(e: WindowEvent?) {
                        if (!Store.loaded) return
                        val text = try { Store.progressJson() } catch (_: Exception) { null } ?: return
                        FocusWork.run { try { Store.writeProgress(text) } catch (_: Exception) {} }
                    }
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
        // 浮動歌詞: the line being sung in a small window of its own, over everything (drag it anywhere)
        if (UI.lyricsFloat) {
            val fs = rememberWindowState(size = DpSize(floatingLyricsWidth().dp, floatingLyricsHeight().dp), position = WindowPosition(Alignment.BottomCenter))
            // (just as tall as its lines, for the letters' size and the reading set in YouTube 歌詞; a word clicked: taller,
            // sliding down to show its entry, and kept on the screen)
            val wantH = floatingLyricsHeight() + if (FloatWord.key != null) FLOAT_DICT_HEIGHT else 0f
            val h by androidx.compose.animation.core.animateFloatAsState(wantH, androidx.compose.animation.core.tween(260), label = "float")
            LaunchedEffect(h, Prefs.lyricsFloatWidth.value) {
                // (the width set in YouTube 歌詞; the height the lines' own: smaller letters, a smaller window too)
                fs.size = DpSize(floatingLyricsWidth().dp, h.dp)
                val p = fs.position
                if (p is WindowPosition.Absolute) {
                    val screen = java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().maximumWindowBounds
                    // (the screen in the same units as the window's: Java gives them already scaled)
                    val bottom = (screen.y + screen.height).toFloat()
                    if (p.y.value + h > bottom) fs.position = WindowPosition(p.x, maxOf(0f, bottom - h).dp)
                }
            }
            Window(onCloseRequest = { UI.lyricsFloat = false; FloatWord.key = null }, state = fs, title = "浮動歌詞", icon = icon,
                alwaysOnTop = true, undecorated = true, transparent = true, resizable = false, onPreviewKeyEvent = { floatSpaceKey(it) }) {
                WindowDraggableArea(Modifier.fillMaxSize()) {
                    FloatingLyrics { UI.lyricsFloat = false }
                }
            }
        }
    }
}

/** when the program stops answering (the window frozen) for 8 seconds: what every part of it was doing is written to
 *  freeze-….txt next to the progress (~/Library/Application Support/FangfangCards on a Mac, %LOCALAPPDATA%\FangfangCards on
 *  Windows), to send to be fixed. The last 3 are kept */
object FreezeWatch {
    @Volatile private var answered = System.currentTimeMillis()
    @Volatile private var written = 0L
    fun start() {
        Thread({
            while (true) {
                try {
                    Thread.sleep(2000)
                    javax.swing.SwingUtilities.invokeLater { answered = System.currentTimeMillis() }
                    val now = System.currentTimeMillis()
                    if (now - answered > 8000 && now - written > 60000) { written = now; write(now - answered) }
                } catch (_: Throwable) {}
            }
        }, "freeze-watch").apply { isDaemon = true }.start()
    }
    private fun write(ms: Long) {
        val dir = DesktopContext.base.apply { mkdirs() }
        val f = File(dir, "freeze-" + java.text.SimpleDateFormat("yyyyMMdd-HHmmss").format(java.util.Date()) + ".txt")
        val sb = StringBuilder("方方詞卡 stopped answering for ${ms / 1000} s (${Os.name})\n\n")
        // (the window's thread first: the one that's stuck)
        val all = Thread.getAllStackTraces().entries.sortedBy { if (it.key.name.startsWith("AWT-EventQueue")) 0 else 1 }
        for ((t, st) in all) {
            sb.append("\"").append(t.name).append("\" ").append(t.state).append('\n')
            for (e in st.take(60)) sb.append("    at ").append(e).append('\n')
            sb.append('\n')
        }
        try {
            f.writeText(sb.toString())
            dir.listFiles { x -> x.name.startsWith("freeze-") }?.sortedByDescending { it.name }?.drop(3)?.forEach { it.delete() }
        } catch (_: Exception) {}
    }
}

/** what switching to and from the window does (saving, the backup folder): one thing at a time, away from the window */
object FocusWork {
    private val pool = java.util.concurrent.Executors.newSingleThreadExecutor { r -> Thread(r, "focus-work").apply { isDaemon = true } }
    fun run(f: () -> Unit) { pool.execute(f) }
}

/** quitting quickly: saved, this computer's backup file written (at most 3 seconds), the radio stopped; and the
 *  program ended for sure 2 seconds later (something still running kept it open a long while) */
object Quitting {
    fun prepare() {
        try { Store.saveNow() } catch (_: Exception) {}
        val t = Thread({ try { Backup.writeOwn() } catch (_: Exception) {} }, "quit-backup").apply { isDaemon = true; start() }
        try { t.join(3000) } catch (_: Exception) {}
        try { Radio.stop() } catch (_: Exception) {}
        Thread({ try { Thread.sleep(2000) } catch (_: Exception) {}; Runtime.getRuntime().halt(0) }, "quit-end").apply { isDaemon = true; start() }
    }
}

/** a ⇧ pressed with nothing else since (for 新詞's 詳細) */
private object LoneShift { var down = false }
