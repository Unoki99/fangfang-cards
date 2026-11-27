package com.unoki99.fangfang

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.unoki99.fangfang.engine.*

// 瀏覽器查詞 (the same add-on as the iPhone's Safari 查詞, in Firefox): the words chosen there (加到不熟 / 收藏 / 認識)
// come here when its 傳到 App button opens
//   fangfangcards://safari?ops=<base64url of [[key, "u" | "s" | "k" | "g", the sentence (optional), its 影片詞組 (optional)], …]>
//     &gr=<base64url of {"yt:abc123": [the video's name, its address], …}> (optional)
// (on Android as intent://safari?…#Intent;scheme=fangfangcards;end, which Firefox hands to the app)
// A word of a language the app can't open right now waits until it can. The same as the iPhone app's SafariImport.

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
        String(android.util.Base64.decode(s, android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP), Charsets.UTF_8)
    } catch (_: Exception) { null }

    /** a fangfangcards://safari link's words: taken over (how many) */
    @Suppress("UNCHECKED_CAST")
    fun handle(uri: Uri): Int {
        if (uri.scheme != "fangfangcards") return 0
        // (我的進度: the minutes watched with the subtitle panel, by day; and each video's 懂 %,
        // {"yt:abc123": [its name, address, %, when in seconds]}), as on the iPhone / iPad
        if (Store.loaded) {
            uri.getQueryParameter("w")?.let { unpack(it) }?.let { try { JReader(it).any() as? Map<String, Any?> } catch (_: Exception) { null } }
                ?.forEach { (day, m) -> (m as? Number)?.toDouble()?.let { Store.addListening(it, 1, day) } }
            uri.getQueryParameter("vk")?.let { unpack(it) }?.let { try { JReader(it).any() as? Map<String, Any?> } catch (_: Exception) { null } }
                ?.forEach { (id, v) ->
                    val l = v as? List<Any?> ?: return@forEach
                    if (l.size >= 4) Store.noteSeen(id, l[0] as? String ?: "", l[1] as? String ?: "",
                        (l[2] as? Number)?.toDouble() ?: 0.0, (l[3] as? Number)?.toDouble() ?: 0.0)
                }
        }
        val ops = uri.getQueryParameter("ops")?.let { unpack(it) }?.let { try { JReader(it).any() as? List<Any?> } catch (_: Exception) { null } }
            ?.mapNotNull { (it as? List<Any?>)?.map { x -> x as? String ?: "" } } ?: return 0
        // 影片詞組: the words chosen from one video go into its group (not the ones marked 認識)
        val groups = uri.getQueryParameter("gr")?.let { unpack(it) }?.let { try { JReader(it).any() as? Map<String, Any?> } catch (_: Exception) { null } }
            ?.mapValues { (it.value as? List<Any?>)?.map { x -> x as? String ?: "" } ?: emptyList() } ?: emptyMap()
        val p = pending(); p.addAll(ops.filter { it.size >= 2 })
        if (!Store.loaded) {
            // (not ready yet: the words wait; their groups are made now)
            keep(p)
            for (op in ops) if (op.size >= 4 && op[1] != "k" && op[3].isNotEmpty()) {
                val g = groups[op[3]] ?: emptyList()
                Store.addToGroup(op[3], g.firstOrNull() ?: op[3], g.getOrNull(1) ?: "", op[0])
            }
            return ops.size
        }
        // (everything in one go: see Store.applyBrowser)
        keep(Store.applyBrowser(ops, groups, p))
        Store.saveNow()
        return ops.size
    }

    /** the words waiting: put in where the app can (the rest keep waiting) */
    fun apply() {
        if (!Store.loaded) return
        val p = pending()
        if (p.isEmpty()) return
        keep(Store.applyBrowser(emptyList(), emptyMap(), p))
        Store.saveNow()
    }
}

/** the words you know (熟悉) and don't (不熟), by language, to the browser add-on: it opens example.com with them after
 *  a "#" (which never leaves the phone); the add-on, on that page, keeps them. The same as the iPhone app's. */
object BrowserKnown {
    class Payload(val url: String, val known: Int, val unknown: Int, val text: String)

    fun payload(): Payload? {
        val names = listOf("tw", "zh", "yue", "hak", "ja", "sv", "eng")
        val known = HashMap<String, MutableSet<String>>(); val unknown = HashMap<String, MutableSet<String>>()
        for ((k, st) in Store.progressStatus()) {
            if (st != 1 && st != 2) continue
            val head = Lang.charOf(k) ?: k.substringBefore("\t")
            if (head.isEmpty()) continue
            val l = names[Lang.kind(k).coerceIn(0, names.size - 1)]
            (if (st == 1) known else unknown).getOrPut(l) { HashSet() }.add(head)
        }
        val json = JWriter.any(mapOf("v" to 1, "k" to known.mapValues { it.value.toList() }, "u" to unknown.mapValues { it.value.toList() }, "f" to emptyList<Any>()))
        // raw deflate, base64url (what the add-on reads)
        val d = java.util.zip.Deflater(java.util.zip.Deflater.BEST_COMPRESSION, true)
        d.setInput(json.toByteArray(Charsets.UTF_8)); d.finish()
        val out = java.io.ByteArrayOutputStream(); val buf = ByteArray(1 shl 16)
        while (!d.finished()) { val n = d.deflate(buf); out.write(buf, 0, n) }
        d.end()
        val b = android.util.Base64.encodeToString(out.toByteArray(), android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP)
        return Payload("https://example.com/#fangfang-known=$b", known.values.sumOf { it.size }, unknown.values.sumOf { it.size }, "fangfang-known:$b")
    }

    /** opens the page in Firefox (where the add-on is), or the browser chosen when Firefox isn't there */
    fun open(ctx: Context, url: String) {
        val firefox = listOf("org.mozilla.firefox", "org.mozilla.firefox_beta", "org.mozilla.fenix")
        for (p in firefox) {
            try { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage(p).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); return }
            catch (_: ActivityNotFoundException) {}
        }
        try { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) {}
    }
}
