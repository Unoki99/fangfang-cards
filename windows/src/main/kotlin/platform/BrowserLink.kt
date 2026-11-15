package com.unoki99.fangfang

import android.content.Context
import android.net.Uri
import com.unoki99.fangfang.engine.*
import java.io.File

// (Windows) the browser add-on (Firefox on this computer): its 傳到 App opens fangfangcards://safari?… , which
// Windows hands to this program (install-windows.bat tells Windows to); the words come in here. The same as the
// Android app's BrowserLink.kt.

object BrowserImport {
    private const val KEY = "browserPending"
    private fun prefs() = Store.app.getSharedPreferences("fangfang", Context.MODE_PRIVATE)

    @Suppress("UNCHECKED_CAST")
    private fun pending(): MutableList<List<String>> {
        val s = prefs().getString(KEY, "") ?: ""
        if (s.isEmpty()) return ArrayList()
        return try { ((JReader(s).any() as? List<Any?>) ?: emptyList()).mapNotNull { (it as? List<Any?>)?.map { x -> x as? String ?: "" } }.toMutableList() }
        catch (_: Exception) { ArrayList() }
    }
    private fun keep(l: List<List<String>>) { prefs().edit().putString(KEY, if (l.isEmpty()) "" else JWriter.any(l)).apply() }
    val waitingCount: Int get() = pending().size

    private fun unpack(s: String): String? = try {
        String(java.util.Base64.getUrlDecoder().decode(s.trim().trimEnd('=')), Charsets.UTF_8)
    } catch (_: Exception) { null }

    /** a fangfangcards://safari link's words: taken over (how many) */
    @Suppress("UNCHECKED_CAST")
    fun handle(uri: Uri): Int {
        if (uri.scheme != "fangfangcards") return 0
        val ops = uri.getQueryParameter("ops")?.let { unpack(it) }?.let { try { JReader(it).any() as? List<Any?> } catch (_: Exception) { null } }
            ?.mapNotNull { (it as? List<Any?>)?.map { x -> x as? String ?: "" } } ?: return 0
        val groups = uri.getQueryParameter("gr")?.let { unpack(it) }?.let { try { JReader(it).any() as? Map<String, Any?> } catch (_: Exception) { null } }
            ?.mapValues { (it.value as? List<Any?>)?.map { x -> x as? String ?: "" } ?: emptyList() } ?: emptyMap()
        for (op in ops) if (op.size >= 4 && op[1] != "k" && op[3].isNotEmpty()) {
            val g = groups[op[3]] ?: emptyList()
            Store.addToGroup(op[3], g.firstOrNull() ?: op[3], g.getOrNull(1) ?: "", op[0])
        }
        val p = pending(); p.addAll(ops.filter { it.size >= 2 }); keep(p)
        apply()
        Store.saveNow()
        return ops.size
    }

    /** the words waiting: put in where the app can (the rest keep waiting) */
    fun apply() {
        if (!Store.loaded) return
        val p = pending()
        if (p.isEmpty()) return
        val waiting = ArrayList<List<String>>()
        for (op in p) {
            if (op.size < 2) continue
            val k = op[0]
            if (op[1] == "g") continue
            if (op[1] == "s") { if (!Store.isSaved(k)) Store.toggleSaved(k); continue }
            val want = if (op[1] == "k") 1 else 2
            if (Store.cardFor(k) != null || Lang.kind(k) == Store.lang) {
                if (Store.wordStatus(k) != want) Store.setWord(k, want)
            } else waiting.add(op)
        }
        keep(waiting)
        Store.saveNow()
    }
}

/** the words you know (熟悉) and don't (不熟), by language, to the browser add-on: it opens example.com with them after
 *  a "#" (which never leaves the computer); the add-on, on that page, keeps them. The same as the Android app's. */
object BrowserKnown {
    class Payload(val url: String, val known: Int, val unknown: Int, val text: String)

    fun payload(): Payload? {
        val names = listOf("tw", "zh", "yue", "hak", "ja", "sv")
        val known = HashMap<String, MutableSet<String>>(); val unknown = HashMap<String, MutableSet<String>>()
        for ((k, st) in Store.progressStatus()) {
            if (st != 1 && st != 2) continue
            val head = Lang.charOf(k) ?: k.substringBefore("\t")
            if (head.isEmpty()) continue
            val l = names[Lang.kind(k).coerceIn(0, names.size - 1)]
            (if (st == 1) known else unknown).getOrPut(l) { HashSet() }.add(head)
        }
        val json = JWriter.any(mapOf("v" to 1, "k" to known.mapValues { it.value.toList() }, "u" to unknown.mapValues { it.value.toList() }, "f" to emptyList<Any>()))
        val d = java.util.zip.Deflater(java.util.zip.Deflater.BEST_COMPRESSION, true)
        d.setInput(json.toByteArray(Charsets.UTF_8)); d.finish()
        val out = java.io.ByteArrayOutputStream(); val buf = ByteArray(1 shl 16)
        while (!d.finished()) { val n = d.deflate(buf); out.write(buf, 0, n) }
        d.end()
        val b = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(out.toByteArray())
        return Payload("https://example.com/#fangfang-known=$b", known.values.sumOf { it.size }, unknown.values.sumOf { it.size }, "fangfang-known:$b")
    }

    /** opens the page in Firefox (where the add-on is), or the usual browser when Firefox isn't there */
    fun open(ctx: Context, url: String) {
        val firefox = listOfNotNull(System.getenv("ProgramFiles"), System.getenv("ProgramFiles(x86)"), System.getenv("LOCALAPPDATA")?.let { "$it\\Programs" })
            .map { File(it, "Mozilla Firefox\\firefox.exe") }.firstOrNull { it.isFile }
        try {
            if (firefox != null) { ProcessBuilder(firefox.path, url).start(); return }
        } catch (_: Exception) {}
        try { java.awt.Desktop.getDesktop().browse(java.net.URI(url)) } catch (_: Exception) {}
    }
}
