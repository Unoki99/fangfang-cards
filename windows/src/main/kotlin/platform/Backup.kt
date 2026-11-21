package com.unoki99.fangfang

import android.net.Uri
import com.unoki99.fangfang.engine.JReader
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** (Windows) the backup folder, the same as the Android app's: a folder chosen once (a OneDrive or Google Drive folder
 *  on this computer works too). Each device writes its own file (方方詞卡-Windows-<id>.json) and reads the others'. */
object Backup {
    private const val prefix = "方方詞卡-"
    private val ownFileName get() = prefix + com.unoki99.fangfang.desktop.Os.name + "-" + Prefs.deviceId.value + ".json"

    private fun folder(): File? {
        val u = Prefs.backupFolder.value
        if (u.isEmpty()) return null
        return Uri.parse(u).toFile()
    }

    val folderName: String?
        get() {
            if (Prefs.backupFolder.value.isEmpty()) return null
            return folder()?.name?.ifEmpty { folder()?.path } ?: "資料夾"
        }

    fun setFolder(uri: Uri): String {
        Prefs.backupFolder.value = uri.toString()
        return syncNow()
    }

    fun clearFolder() { Prefs.backupFolder.value = "" }

    @Suppress("UNCHECKED_CAST")
    /** run on the window's thread (from it: right away; from elsewhere: waiting for it) */
    private fun onUi(f: () -> Unit) {
        if (javax.swing.SwingUtilities.isEventDispatchThread()) f() else javax.swing.SwingUtilities.invokeAndWait(f)
    }

    /** on quitting: only this computer's own file written (the other devices' files aren't read: in a folder iCloud
     *  keeps that took long, and quitting waited for it) */
    fun writeOwn() {
        if (!Store.loaded || Prefs.backupFolder.value.isEmpty()) return
        val dir = folder() ?: return
        if (!dir.isDirectory) return
        try { File(dir, ownFileName).writeText(Store.backupData()); Prefs.lastBackup.value = System.currentTimeMillis().toString() } catch (_: Exception) {}
    }

    fun syncNow(): String {
        if (!Store.loaded) return ""
        if (Prefs.backupFolder.value.isEmpty()) return "還沒選擇備份資料夾。"
        val dir = folder() ?: return "沒辦法使用這個資料夾。"
        if (!dir.isDirectory) return "找不到資料夾「${dir.path}」。請重新選擇資料夾。"
        var changed = 0
        try {
            if (Prefs.syncDevices.value) {
                for (f in dir.listFiles() ?: emptyArray()) {
                    val name = f.name
                    if (!name.startsWith(prefix) || !name.endsWith(".json") || name == ownFileName) continue
                    val text = try { f.readText() } catch (_: Exception) { null } ?: continue
                    val obj = try { JReader(text).any() as? Map<String, Any?> } catch (_: Exception) { null } ?: continue
                    // (the files are read away from the window; what they bring is put in on the window's own thread)
                    if (obj["app"] == "fangfang-cards") onUi { changed += Store.mergeProgress(obj) }
                }
                if (changed > 0) onUi { Store.save() }
            }
            // (歌詞: the lyrics of your own, one .lrc file a song, the same folder as the iPhone / iPad app's)
            try { OwnLyrics.sync(File(dir, "歌詞")) } catch (_: Exception) {}
            val data = Store.backupData()
            try { File(dir, ownFileName).writeText(data) } catch (e: Exception) { return "備份失敗：沒辦法寫入「${dir.name}」。請重新選擇資料夾。" }
            val old = File(dir, "方方詞卡舊備份").apply { mkdirs() }
            val base = ownFileName.removeSuffix(".json")
            try { File(old, base + "-" + SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date()) + ".json").writeText(data) } catch (_: Exception) {}
            val mine = (old.listFiles() ?: emptyArray()).filter { it.name.startsWith("$base-") }.sortedBy { it.name }
            for (f in mine.dropLast(14)) f.delete()
        } catch (e: Exception) {
            return "備份失敗：${e.message}"
        }
        Prefs.lastBackup.value = System.currentTimeMillis().toString()
        return if (changed > 0) "已同步，從其他裝置更新了 $changed 個詞。" else "已備份到「${dir.name}」。"
    }
}
