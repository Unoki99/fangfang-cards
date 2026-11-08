package com.unoki99.fangfang

import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.unoki99.fangfang.engine.JReader
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Automatic backup to a folder picked once (Google Drive, a folder on the phone…). Each device writes its own
 * file there; the other devices' files are merged in, so devices that use the same folder stay in step
 * (the same file names as the iPhone / iPad app, so a shared folder works with those too).
 */
object Backup {
    private const val prefix = "方方詞卡-"
    private val ownFileName get() = prefix + "Android-" + Prefs.deviceId.value + ".json"

    val folderName: String?
        get() {
            val u = Prefs.backupFolder.value
            if (u.isEmpty()) return null
            return DocumentFile.fromTreeUri(Store.app, Uri.parse(u))?.name ?: "資料夾"
        }

    fun setFolder(uri: Uri): String {
        try {
            Store.app.contentResolver.takePersistableUriPermission(uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        } catch (_: Exception) {}
        Prefs.backupFolder.value = uri.toString()
        return syncNow()
    }

    fun clearFolder() { Prefs.backupFolder.value = "" }

    private fun read(f: DocumentFile): String? = try {
        Store.app.contentResolver.openInputStream(f.uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
    } catch (_: Exception) { null }

    private fun write(dir: DocumentFile, name: String, text: String): Boolean = try {
        val f = dir.findFile(name) ?: dir.createFile("application/json", name.removeSuffix(".json"))
        if (f == null) false else {
            Store.app.contentResolver.openOutputStream(f.uri, "wt")?.use { it.write(text.toByteArray()) }
            true
        }
    } catch (_: Exception) { false }

    /** merge the other devices' files, then write ours (+ one dated copy per day, the newest 14 kept) */
    @Suppress("UNCHECKED_CAST")
    fun syncNow(): String {
        if (!Store.loaded) return ""
        val u = Prefs.backupFolder.value
        if (u.isEmpty()) return "還沒選擇備份資料夾。"
        val folder = DocumentFile.fromTreeUri(Store.app, Uri.parse(u)) ?: return "沒辦法使用這個資料夾。"
        var changed = 0
        try {
            if (Prefs.syncDevices.value) {
                for (f in folder.listFiles()) {
                    val name = f.name ?: continue
                    if (!name.startsWith(prefix) || !name.endsWith(".json") || name == ownFileName) continue
                    val text = read(f) ?: continue
                    val obj = try { JReader(text).any() as? Map<String, Any?> } catch (_: Exception) { null } ?: continue
                    if (obj["app"] == "fangfang-cards") changed += Store.mergeProgress(obj)
                }
                if (changed > 0) Store.save()
            }
            val data = Store.backupData()
            if (!write(folder, ownFileName, data)) return "備份失敗：沒辦法寫入「${folder.name}」。請重新選擇資料夾。"
            val old = folder.findFile("方方詞卡舊備份") ?: folder.createDirectory("方方詞卡舊備份")
            if (old != null) {
                val base = ownFileName.removeSuffix(".json")
                write(old, base + "-" + SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date()) + ".json", data)
                val mine = old.listFiles().filter { (it.name ?: "").startsWith("$base-") }.sortedBy { it.name }
                for (f in mine.dropLast(14)) f.delete()
            }
        } catch (e: Exception) {
            return "備份失敗：${e.message}"
        }
        Prefs.lastBackup.value = System.currentTimeMillis().toString()
        return if (changed > 0) "已同步，從其他裝置更新了 $changed 個詞。" else "已備份到「${folder.name}」。"
    }
}
