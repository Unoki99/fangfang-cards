package com.unoki99.fangfang.desktop

import android.content.Context
import android.content.FilePreferences
import android.content.SharedPreferences
import android.content.res.AssetManager
import java.io.File

/** where 方方詞卡 keeps things on this computer (Windows: %LOCALAPPDATA%\FangfangCards; a Mac:
 *  ~/Library/Application Support/FangfangCards):
 *  data — the dictionaries the installer made (the same as the Android build's)
 *  app — the progress, the settings, the dictionaries installed in the app, the cache
 *  On a Mac the dictionaries the iPad app's install.sh made (~/FangfangCards/data) are used too, when there */
object DesktopContext : Context() {
    val base: File = if (Os.mac) File(System.getProperty("user.home"), "Library/Application Support/FangfangCards")
        else File(System.getenv("LOCALAPPDATA") ?: (System.getProperty("user.home") + "\\AppData\\Local"), "FangfangCards")
    val dataDir: File get() = File(base, "data")
    private val appDir: File get() = File(base, "app").apply { mkdirs() }
    override val filesDir: File get() = File(appDir, "files").apply { mkdirs() }
    override val cacheDir: File get() = File(appDir, "cache").apply { mkdirs() }
    override val assets: AssetManager by lazy {
        AssetManager(dataDir, if (Os.mac) listOf(File(System.getProperty("user.home"), "FangfangCards/data")) else emptyList())
    }
    private val prefs = HashMap<String, SharedPreferences>()
    override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
        synchronized(prefs) { prefs.getOrPut(name) { FilePreferences(File(appDir, "prefs-$name.properties")) } }
}
