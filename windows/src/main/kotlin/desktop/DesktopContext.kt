package com.unoki99.fangfang.desktop

import android.content.Context
import android.content.FilePreferences
import android.content.SharedPreferences
import android.content.res.AssetManager
import java.io.File

/** where 方方詞卡 keeps things on this computer:
 *  %LOCALAPPDATA%\FangfangCards\data — the dictionaries install-windows.bat made (the same as the Android build's)
 *  %LOCALAPPDATA%\FangfangCards\app — the progress, the settings, the dictionaries installed in the app, the cache */
object DesktopContext : Context() {
    val base: File = File(System.getenv("LOCALAPPDATA") ?: (System.getProperty("user.home") + "\\AppData\\Local"), "FangfangCards")
    val dataDir: File get() = File(base, "data")
    private val appDir: File get() = File(base, "app").apply { mkdirs() }
    override val filesDir: File get() = File(appDir, "files").apply { mkdirs() }
    override val cacheDir: File get() = File(appDir, "cache").apply { mkdirs() }
    override val assets: AssetManager by lazy { AssetManager(dataDir) }
    private val prefs = HashMap<String, SharedPreferences>()
    override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
        synchronized(prefs) { prefs.getOrPut(name) { FilePreferences(File(appDir, "prefs-$name.properties")) } }
}
