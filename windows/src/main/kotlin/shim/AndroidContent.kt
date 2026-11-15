// Windows stand-ins for the few Android classes the shared code (../android/app/src/main/java) uses: the same names
// and the parts of them it calls, done the Windows way. (The real ones are Android's; these are only for this build.)
package android.content

import android.content.res.AssetManager
import android.net.Uri
import java.awt.Toolkit
import java.awt.datatransfer.DataFlavor
import java.awt.datatransfer.StringSelection
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.Properties

/** the app's place on this computer: its files, its cache, its settings, the clipboard */
abstract class Context {
    abstract val filesDir: File
    abstract val cacheDir: File
    abstract val assets: AssetManager
    open val applicationContext: Context get() = this
    open val contentResolver: ContentResolver get() = ContentResolver
    abstract fun getSharedPreferences(name: String, mode: Int): SharedPreferences
    open fun getSystemService(name: String): Any? = if (name == CLIPBOARD_SERVICE) ClipboardManager() else null

    companion object {
        const val CLIPBOARD_SERVICE = "clipboard"
        const val MODE_PRIVATE = 0
    }
}

/** files picked in a file dialog (file: addresses) */
object ContentResolver {
    fun openOutputStream(uri: Uri, mode: String = "w"): OutputStream? = uri.toFile()?.let { f ->
        f.parentFile?.mkdirs()
        if (mode.contains("a")) java.io.FileOutputStream(f, true) else java.io.FileOutputStream(f)
    }
    fun openInputStream(uri: Uri): InputStream? = uri.toFile()?.takeIf { it.exists() }?.inputStream()
}

/** the Windows clipboard (text only) */
class ClipboardManager {
    fun setPrimaryClip(c: ClipData) {
        try { Toolkit.getDefaultToolkit().systemClipboard.setContents(StringSelection(c.text.toString()), null) } catch (_: Exception) {}
    }
    val primaryClip: ClipData?
        get() = try {
            val t = Toolkit.getDefaultToolkit().systemClipboard.getData(DataFlavor.stringFlavor) as? String
            t?.let { ClipData(it) }
        } catch (_: Exception) { null }
}

class ClipData(val text: CharSequence) {
    class Item(val text: CharSequence) { fun coerceToText(ctx: Context?): CharSequence = text }
    fun getItemAt(i: Int): Item = Item(text)
    val itemCount: Int get() = 1
    companion object {
        @JvmStatic fun newPlainText(label: CharSequence?, text: CharSequence): ClipData = ClipData(text)
    }
}

/** settings: kept in a file (prefs-<name>.properties in the app's folder), written each time one changes */
interface SharedPreferences {
    fun getInt(key: String, def: Int): Int
    fun getLong(key: String, def: Long): Long
    fun getBoolean(key: String, def: Boolean): Boolean
    fun getFloat(key: String, def: Float): Float
    fun getString(key: String, def: String?): String?
    fun contains(key: String): Boolean
    fun edit(): Editor
    interface Editor {
        fun putInt(key: String, v: Int): Editor
        fun putLong(key: String, v: Long): Editor
        fun putBoolean(key: String, v: Boolean): Editor
        fun putFloat(key: String, v: Float): Editor
        fun putString(key: String, v: String?): Editor
        fun remove(key: String): Editor
        fun clear(): Editor
        fun apply()
        fun commit(): Boolean
    }
}

class FilePreferences(private val file: File) : SharedPreferences {
    private val p = Properties()
    init { try { if (file.exists()) file.reader(Charsets.UTF_8).use { p.load(it) } } catch (_: Exception) {} }

    private fun raw(key: String): String? = synchronized(p) { p.getProperty(key) }
    override fun getInt(key: String, def: Int) = raw(key)?.toIntOrNull() ?: def
    override fun getLong(key: String, def: Long) = raw(key)?.toLongOrNull() ?: def
    override fun getBoolean(key: String, def: Boolean) = raw(key)?.let { it == "true" } ?: def
    override fun getFloat(key: String, def: Float) = raw(key)?.toFloatOrNull() ?: def
    override fun getString(key: String, def: String?) = raw(key) ?: def
    override fun contains(key: String) = raw(key) != null

    private fun save() {
        try {
            file.parentFile?.mkdirs()
            val tmp = File(file.path + ".tmp")
            synchronized(p) { tmp.writer(Charsets.UTF_8).use { p.store(it, "方方詞卡") } }
            if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
        } catch (_: Exception) {}
    }

    override fun edit(): SharedPreferences.Editor = Edit()

    private inner class Edit : SharedPreferences.Editor {
        private val put = HashMap<String, String?>()
        private var wipe = false
        private fun set(key: String, v: String?): SharedPreferences.Editor { put[key] = v; return this }
        override fun putInt(key: String, v: Int) = set(key, v.toString())
        override fun putLong(key: String, v: Long) = set(key, v.toString())
        override fun putBoolean(key: String, v: Boolean) = set(key, v.toString())
        override fun putFloat(key: String, v: Float) = set(key, v.toString())
        override fun putString(key: String, v: String?) = set(key, v)
        override fun remove(key: String) = set(key, null)
        override fun clear(): SharedPreferences.Editor { wipe = true; return this }
        override fun apply() { commit() }
        override fun commit(): Boolean {
            synchronized(p) {
                if (wipe) p.clear()
                for ((k, v) in put) if (v == null) p.remove(k) else p.setProperty(k, v)
            }
            save()
            return true
        }
    }
}
