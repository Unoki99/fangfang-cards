package com.unoki99.fangfang.widget

import android.content.Context
import com.unoki99.fangfang.engine.JReader
import com.unoki99.fangfang.engine.JWriter
import java.io.File

/** The files the app writes for the widget, and what the widget writes back (its inbox). */
object WidgetFiles {
    class Word(
        val k: String, val h: String, val a: Int?, val r: List<String>, val z: String, val p: String, val m: String,
        val xh: String?, val xr: List<String>?, val xz: String?, val xn: String?,
        val hc: List<Pair<String, String?>>?, val rc: List<List<Pair<String, String?>>>?, val zc: List<Pair<String, String?>>?,
        val xhc: List<Pair<String, String?>>?, val xrc: List<List<Pair<String, String?>>>?,
    )
    class Category(val i: Int, val n: String, val c: Int)
    class State(val rom: Int = 0, val place: Int = -1, val bg: Double = 0.45, val saved: List<String> = emptyList(), val known: List<String> = emptyList(),
                /** the 不熟 words (both languages), for 只顯示不熟的詞 */
                val unknown: List<String> = emptyList())
    /** the 分類 ids besides the 台語 分類: 常用詞, the 不熟 words, the 華語 levels (10000 + level; characters 10100 + level) */
    const val COMMON = -1
    const val TW_UNKNOWN = -2
    const val ZH_UNKNOWN = -3
    const val ZH_BASE = 10000
    class InboxOp(val k: String, val save: Boolean, val t: Double, val known: Boolean? = null)

    private fun dir(ctx: Context) = File(ctx.filesDir, "widget").apply { mkdirs() }
    private fun file(ctx: Context, name: String) = File(dir(ctx), name)
    private fun readText(ctx: Context, name: String): String? = try { file(ctx, name).takeIf { it.exists() }?.readText() } catch (_: Exception) { null }
    private fun writeText(ctx: Context, name: String, text: String) {
        val f = file(ctx, name); val tmp = File(f.parentFile, "$name.tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(f)) { f.writeText(text); tmp.delete() }
    }

    private fun segsJson(s: List<Pair<String, String?>>?): Any? = s?.map { mapOf("t" to it.first, "c" to it.second) }

    @Suppress("UNCHECKED_CAST")
    private fun segsOf(v: Any?): List<Pair<String, String?>>? =
        (v as? List<Any?>)?.mapNotNull { (it as? Map<String, Any?>)?.let { m -> Pair(m["t"] as? String ?: "", m["c"] as? String) } }

    fun writeWords(ctx: Context, cat: Int, words: List<Word>) {
        val list = words.map { w ->
            mapOf("k" to w.k, "h" to w.h, "a" to w.a, "r" to w.r, "z" to w.z, "p" to w.p, "m" to w.m,
                "xh" to w.xh, "xr" to w.xr, "xz" to w.xz, "xn" to w.xn,
                "hc" to segsJson(w.hc), "rc" to w.rc?.map { segsJson(it) }, "zc" to segsJson(w.zc),
                "xhc" to segsJson(w.xhc), "xrc" to w.xrc?.map { segsJson(it) })
        }
        writeText(ctx, "words-$cat.json", JWriter.any(list))
    }

    @Suppress("UNCHECKED_CAST")
    fun words(ctx: Context, cat: Int): List<Word> {
        val text = readText(ctx, "words-$cat.json") ?: return emptyList()
        val l = try { JReader(text).any() as? List<Any?> } catch (_: Exception) { null } ?: return emptyList()
        return l.mapNotNull { v ->
            val m = v as? Map<String, Any?> ?: return@mapNotNull null
            fun s(k: String) = m[k] as? String
            fun sl(k: String) = (m[k] as? List<Any?>)?.map { it as? String ?: "" }
            Word(s("k") ?: return@mapNotNull null, s("h") ?: "", (m["a"] as? Number)?.toInt(), sl("r") ?: listOf("", "", ""),
                s("z") ?: "", s("p") ?: "", s("m") ?: "", s("xh"), sl("xr"), s("xz"), s("xn"),
                segsOf(m["hc"]), (m["rc"] as? List<Any?>)?.map { segsOf(it) ?: emptyList() }, segsOf(m["zc"]),
                segsOf(m["xhc"]), (m["xrc"] as? List<Any?>)?.map { segsOf(it) ?: emptyList() })
        }
    }

    fun writeCategories(ctx: Context, list: List<Category>) =
        writeText(ctx, "categories.json", JWriter.any(list.map { mapOf("i" to it.i, "n" to it.n, "c" to it.c) }))

    @Suppress("UNCHECKED_CAST")
    fun categories(ctx: Context): List<Category> {
        val text = readText(ctx, "categories.json") ?: return emptyList()
        val l = try { JReader(text).any() as? List<Any?> } catch (_: Exception) { null } ?: return emptyList()
        return l.mapNotNull { v -> (v as? Map<String, Any?>)?.let { Category((it["i"] as? Number)?.toInt() ?: -1, it["n"] as? String ?: "", (it["c"] as? Number)?.toInt() ?: 0) } }
    }
    fun hasCategories(ctx: Context) = file(ctx, "categories.json").exists()

    fun writeState(ctx: Context, s: State) = writeText(ctx, "state.json",
        JWriter.any(mapOf("rom" to s.rom, "place" to s.place, "bg" to s.bg, "saved" to s.saved, "known" to s.known, "unknown" to s.unknown)))

    @Suppress("UNCHECKED_CAST")
    fun state(ctx: Context): State {
        val text = readText(ctx, "state.json") ?: return State()
        val m = try { JReader(text).any() as? Map<String, Any?> } catch (_: Exception) { null } ?: return State()
        return State((m["rom"] as? Number)?.toInt() ?: 0, (m["place"] as? Number)?.toInt() ?: -1, (m["bg"] as? Number)?.toDouble() ?: 0.45,
            (m["saved"] as? List<Any?>)?.filterIsInstance<String>() ?: emptyList(), (m["known"] as? List<Any?>)?.filterIsInstance<String>() ?: emptyList(),
            (m["unknown"] as? List<Any?>)?.filterIsInstance<String>() ?: emptyList())
    }

    @Suppress("UNCHECKED_CAST")
    fun inbox(ctx: Context): List<InboxOp> {
        val text = readText(ctx, "inbox.json") ?: return emptyList()
        val l = try { JReader(text).any() as? List<Any?> } catch (_: Exception) { null } ?: return emptyList()
        return l.mapNotNull { v -> (v as? Map<String, Any?>)?.let {
            InboxOp(it["k"] as? String ?: return@let null, it["save"] as? Boolean ?: false, (it["t"] as? Number)?.toDouble() ?: 0.0, it["known"] as? Boolean)
        } }
    }

    fun writeInbox(ctx: Context, ops: List<InboxOp>) =
        writeText(ctx, "inbox.json", JWriter.any(ops.map { mapOf("k" to it.k, "save" to it.save, "t" to it.t, "known" to it.known) }))

    fun savedNow(ctx: Context): Set<String> {
        val s = state(ctx).saved.toHashSet()
        for (op in inbox(ctx)) if (op.known == null) { if (op.save) s.add(op.k) else s.remove(op.k) }
        return s
    }

    /** 不熟 words as the widget should see them (✓ on the widget takes a word out) */
    fun unknownNow(ctx: Context): Set<String> {
        val s = state(ctx).unknown.toHashSet()
        for (op in inbox(ctx)) if (op.known == true) s.remove(op.k)
        return s
    }

    fun knownNow(ctx: Context): Set<String> {
        val s = state(ctx).known.toHashSet()
        for (op in inbox(ctx)) { if (op.known == true) s.add(op.k) else if (op.known == false) s.remove(op.k) }
        return s
    }

    @Synchronized fun toggleSaved(ctx: Context, key: String) {
        val save = !savedNow(ctx).contains(key)
        writeInbox(ctx, inbox(ctx) + InboxOp(key, save, System.currentTimeMillis() / 1000.0))
    }

    @Synchronized fun toggleKnown(ctx: Context, key: String) {
        val known = !knownNow(ctx).contains(key)
        writeInbox(ctx, inbox(ctx) + InboxOp(key, false, System.currentTimeMillis() / 1000.0, known))
    }

    // per widget: which 分類, how many times → was pressed, the word on show
    private fun sp(ctx: Context) = ctx.getSharedPreferences("widget", Context.MODE_PRIVATE)
    fun stamp(ctx: Context) = sp(ctx).getString("words-stamp", null)
    fun setStamp(ctx: Context, s: String) = sp(ctx).edit().putString("words-stamp", s).apply()
    fun category(ctx: Context, widgetId: Int): Int? = sp(ctx).getInt("cat-$widgetId", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE }
    fun setCategory(ctx: Context, widgetId: Int, cat: Int) = sp(ctx).edit().putInt("cat-$widgetId", cat).apply()
    /** 只顯示不熟的詞 (per widget) */
    fun unknownOnly(ctx: Context, widgetId: Int) = sp(ctx).getBoolean("unknown-$widgetId", false)
    fun setUnknownOnly(ctx: Context, widgetId: Int, on: Boolean) = sp(ctx).edit().putBoolean("unknown-$widgetId", on).apply()
    fun nextCount(ctx: Context, widgetId: Int) = sp(ctx).getInt("next-$widgetId", 0)
    fun bumpNext(ctx: Context, widgetId: Int) = sp(ctx).edit().putInt("next-$widgetId", nextCount(ctx, widgetId) + 1).apply()
    fun pinned(ctx: Context, widgetId: Int, slot: String): String? =
        sp(ctx).getString("pin-$widgetId", null)?.takeIf { it.startsWith("$slot|") }?.substring(slot.length + 1)
    fun pin(ctx: Context, widgetId: Int, slot: String, key: String) = sp(ctx).edit().putString("pin-$widgetId", "$slot|$key").apply()
}
