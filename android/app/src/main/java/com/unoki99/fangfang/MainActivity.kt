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
import com.unoki99.fangfang.ui.*

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // a crash is written down, and shown the next time the app opens (so it can be sent to be fixed)
        val crashFile = java.io.File(applicationContext.filesDir, "last-crash.txt")
        val before = Thread.getDefaultUncaughtExceptionHandler()
        if (before !is CrashNote) Thread.setDefaultUncaughtExceptionHandler(CrashNote(crashFile, before))
        Prefs.init(applicationContext)
        Store.init(applicationContext)
        Radio.init(applicationContext)
        if (crashFile.exists()) {
            val t = try { crashFile.readText().take(1500) } catch (_: Exception) { "" }
            crashFile.delete()
            if (t.isNotBlank()) Store.zhError = "上次當掉了（可以把這段傳給 Claude）：\n$t"
        }
        enableEdgeToEdge()
        setContent { App() }
        takeLink(intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        takeLink(intent)
    }

    /** the browser add-on's 傳到 App (fangfangcards://safari?…): its words */
    private fun takeLink(i: android.content.Intent?) {
        // text selected in another app → 方方查詞: looked up in 詞典 (several words at once too)
        if (i?.action == android.content.Intent.ACTION_PROCESS_TEXT) {
            val t = i.getCharSequenceExtra(android.content.Intent.EXTRA_PROCESS_TEXT)?.toString()?.trim().orEmpty()
            if (t.isNotEmpty()) {
                Prefs.lookupQuery.value = t.take(60)
                UI.settingsOpen = false; UI.radioOpen = false; UI.practice = null
                UI.tabs[4].stack.clear()
                UI.tab = 4
            }
            return
        }
        val u = i?.data ?: return
        // 鎖定畫面的詞 tapped: the word's entry (in its language)
        if (u.scheme == "fangfangcards" && u.host == "dict") {
            val l = u.getQueryParameter("lang")?.toIntOrNull()
            if (l != null && l != Store.lang && Store.loaded) Store.setLanguage(l)
            val w = u.getQueryParameter("word")
            if (!w.isNullOrEmpty()) UI.open(if (com.unoki99.fangfang.engine.Lang.kind(w) == 0) Sheet.Word(w) else Sheet.ZhWord(w))
            return
        }
        if (u.scheme == "fangfangcards") {
            val n = BrowserImport.handle(u)
            if (n > 0) android.widget.Toast.makeText(this, tr("從瀏覽器查詞收到 {0} 個詞", n), android.widget.Toast.LENGTH_LONG).show()
        }
    }

    override fun onStart() {
        super.onStart()
        LockWord.end(this)
    }

    override fun onStop() {
        super.onStop()
        // (leaving the app: a word on the lock screen, when that's on)
        if (!isChangingConfigurations) LockWord.start(this)
    }

    override fun onResume() {
        super.onResume()
        // (back in the app: the other devices' backups read again)
        if (Store.loaded) { Backup.syncNow(); WidgetBridge.appOpened() }
    }

    override fun onPause() {
        super.onPause()
        Store.saveNow()
        Backup.syncNow()
        WidgetBridge.flush()
    }
}

/** writes an uncaught crash down (the error and where it happened), then lets it crash as before */
private class CrashNote(val file: java.io.File, val next: Thread.UncaughtExceptionHandler?) : Thread.UncaughtExceptionHandler {
    override fun uncaughtException(t: Thread, e: Throwable) {
        try {
            val sw = java.io.StringWriter()
            e.printStackTrace(java.io.PrintWriter(sw))
            file.writeText("${e.javaClass.simpleName}: ${e.message}\n(${t.name})\n" + sw.toString().lines().take(25).joinToString("\n"))
        } catch (_: Throwable) {}
        next?.uncaughtException(t, e)
    }
}
