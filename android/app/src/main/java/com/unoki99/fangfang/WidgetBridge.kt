package com.unoki99.fangfang

import com.unoki99.fangfang.engine.*
import com.unoki99.fangfang.widget.WidgetFiles
import com.unoki99.fangfang.widget.WordWidget
import kotlinx.coroutines.*

/**
 * Keeps the 分類詞卡 widget up to date: writes each 分類's words (in the chosen spelling and 腔口, with their tone
 * colours) and your progress into the app's widget folder, and takes over what was pressed on a widget.
 */
object WidgetBridge {
    const val commonCount = 1000
    private val scope = MainScope()
    private var building = false
    private var stateJob: Job? = null

    fun appOpened() {
        if (!Store.loaded) return
        mergeInbox()
        writeState()
        rebuildIfNeeded()
    }

    /** what was pressed on a widget → the app */
    fun mergeInbox() {
        if (!Store.loaded) return
        val ops = WidgetFiles.inbox(Store.app)
        if (ops.isEmpty()) return
        for (op in ops) {
            // (台語 and 華語 words: either language's cards)
            val c = Store.cardFor(op.k)
            when (op.known) {
                true -> if (c != null && Store.status(c) != 1) Store.mark(c, true, undoable = false)
                false -> if (c != null && Store.status(c) == 1) Store.forget(c)
                null -> if (Store.isSaved(op.k) != op.save) Store.toggleSaved(op.k)
            }
        }
        WidgetFiles.writeInbox(Store.app, emptyList())
        Store.saveNow()
    }

    /** progress changed (a swipe…): written when the app goes to the background, or after half a minute without
     *  changes. Every swipe used to write all your words out and update the widgets a second later */
    fun progressChanged() {
        dirty = true
        stateJob?.cancel()
        stateJob = scope.launch { delay(30_000); writeState() }
    }

    /** the app goes to the background: what changed, written now */
    fun flush() {
        if (!dirty) return
        stateJob?.cancel()
        writeState()
    }
    private var dirty = false

    fun writeState() {
        if (!Store.loaded) return
        dirty = false
        if (WidgetFiles.inbox(Store.app).isNotEmpty()) mergeInbox()
        val st = WidgetFiles.State(
            rom = Prefs.rom.value.coerceIn(0, 2),
            place = Prefs.place.value,
            bg = Prefs.widgetBG.value.toDouble(),
            saved = Store.progress.saved.filter { it.value > 0 }.keys.sorted(),
            known = Store.progress.status.filter { it.value == 1 }.keys.sorted(),
            unknown = Store.progress.status.filter { it.value == 2 }.keys.sorted(),
        )
        WidgetFiles.writeState(Store.app, st)
        writeUnknown(st.unknown)
        refresh()
    }

    // the 不熟 分類 (台語 and 華語): written again when the 不熟 words change
    private var unknownStamp = ""
    private val wordCache = HashMap<String, WidgetFiles.Word>()
    private var cacheStamp = ""

    private fun writeUnknown(keys: List<String>) {
        val place = Prefs.place.value
        val settings = "$place|${Store.zh != null}|${Store.dict != null}|${Prefs.toneSys.value}|${Prefs.toneMarks.value}|${ToneColors.signature}|" +
            "${Prefs.zhEnglish.value}|${Prefs.zhRom.value}|${Prefs.zhPlace.value}"
        val stamp = "${keys.hashCode()}|$settings"
        if (stamp == unknownStamp) return
        unknownStamp = stamp
        // the words already written out stay good while the settings stay the same
        if (cacheStamp != settings) { wordCache.clear(); cacheStamp = settings }
        // the newest 400 of each language
        val newest = keys.sortedByDescending { Store.progress.added[it] ?: 0.0 }
        val tw = ArrayList<WidgetFiles.Word>(); val zh = ArrayList<WidgetFiles.Word>()
        for (k in newest) {
            val isZh = Lang.isZhKey(k)
            if (if (isZh) zh.size >= 400 else tw.size >= 400) continue
            if (isZh && Store.zh == null) continue
            val c = Store.cardFor(k) ?: continue
            val w = wordCache.getOrPut(k) { word(c, place) }
            if (isZh) zh.add(w) else tw.add(w)
            if (tw.size >= 400 && zh.size >= 400) break
        }
        WidgetFiles.writeWords(Store.app, WidgetFiles.TW_UNKNOWN, tw)
        WidgetFiles.writeWords(Store.app, WidgetFiles.ZH_UNKNOWN, zh)
        val list = WidgetFiles.categories(Store.app)
        if (list.isNotEmpty()) WidgetFiles.writeCategories(Store.app, list.map { c ->
            when (c.i) {
                WidgetFiles.TW_UNKNOWN -> WidgetFiles.Category(c.i, c.n, tw.size)
                WidgetFiles.ZH_UNKNOWN -> WidgetFiles.Category(c.i, c.n, zh.size)
                else -> c
            }
        })
    }

    fun refresh() {
        scope.launch { try { WordWidget.refreshAll(Store.app) } catch (_: Exception) {} }
    }

    /** the word files: written again when the 腔口, the spelling settings or the word list changed */
    fun rebuildIfNeeded() {
        if (!Store.loaded || building) return
        val place = Prefs.place.value
        val tones = Prefs.toneSys.value
        if ((place >= 0 || tones != 0) && Store.dict == null) Store.loadDict()   // called again once it's there
        val needsDict = place >= 0 || tones != 0
        val (twCards, twTopics) = Store.twDeck
        val (zhCards, zhTopics) = Store.zhDeck
        val stamp = "v3|${twCards.size}|${twCards.firstOrNull()?.k}|$place|${needsDict && Store.dict != null}|$tones|${Prefs.toneMarks.value}|${ToneColors.signature}" +
            "|zh${zhCards.size}|${Prefs.zhList.value}|${Prefs.zhRom.value}|${Prefs.zhPlace.value}|${Prefs.zhEnglish.value}"
        if (WidgetFiles.stamp(Store.app) == stamp && WidgetFiles.hasCategories(Store.app)) return
        building = true
        scope.launch {
            val cards = twCards
            val topics = twTopics
            withContext(Dispatchers.Default) {
                val byCat = HashMap<Int, MutableList<WidgetFiles.Word>>()
                val common = ArrayList<WidgetFiles.Word>()
                for ((i, c) in cards.withIndex()) {
                    val cats = c.cats ?: emptyList()
                    if (cats.isEmpty() && i >= commonCount) continue
                    val w = word(c, place)
                    for (cat in cats) byCat.getOrPut(cat) { ArrayList() }.add(w)
                    if (i < commonCount) common.add(w)
                }
                // 華語: each level of the word list, and each character level (not 更多常用字)
                for (c in zhCards) {
                    val l = c.cats?.firstOrNull() ?: continue
                    if (l == Lang.moreChars) continue
                    byCat.getOrPut(WidgetFiles.ZH_BASE + l) { ArrayList() }.add(word(c, place))
                }
                val list = arrayListOf(WidgetFiles.Category(-1, "常用詞", common.size))
                WidgetFiles.writeWords(Store.app, -1, common)
                list.add(WidgetFiles.Category(WidgetFiles.TW_UNKNOWN, "不熟的詞（台語）", 0))
                for (t in topics) {
                    val ws = byCat[t.id] ?: continue
                    if (ws.isEmpty()) continue
                    WidgetFiles.writeWords(Store.app, t.id, ws)
                    list.add(WidgetFiles.Category(t.id, t.name, ws.size))
                }
                if (zhCards.isNotEmpty()) {
                    list.add(WidgetFiles.Category(WidgetFiles.ZH_UNKNOWN, "不熟的詞（華語）", 0))
                    for (t in zhTopics) {
                        val ws = byCat[WidgetFiles.ZH_BASE + t.id] ?: continue
                        if (ws.isEmpty()) continue
                        WidgetFiles.writeWords(Store.app, WidgetFiles.ZH_BASE + t.id, ws)
                        list.add(WidgetFiles.Category(WidgetFiles.ZH_BASE + t.id, "華語・" + t.name, ws.size))
                    }
                }
                WidgetFiles.writeCategories(Store.app, list)
                WidgetFiles.setStamp(Store.app, stamp)
            }
            building = false
            unknownStamp = ""
            writeUnknown(Store.progress.status.filter { it.value == 2 }.keys.sorted())
            refresh()
            rebuildIfNeeded()     // something changed meanwhile: once more
        }
    }

    private fun hex(s: Styled): List<Pair<String, String?>> = s.map { Pair(it.t, it.c?.let { c -> "%06x".format(c and 0xFFFFFF) }) }

    private fun word(c: Card, place: Int): WidgetFiles.Word {
        val def = c.d.firstOrNull { it.x.isNotEmpty() } ?: c.d.firstOrNull()
        val x = def?.x?.firstOrNull()
        val han = Store.cardHan(c, place, 0xFFC8CFFF.toInt())
        val rom = (0..2).map { Store.cardRom(c, it, place) }
        val zy = Store.cardZy(c, place)
        val xh = x?.let { Store.exampleHan(c, it, place, 0xFFF2F2F2.toInt()) }
        val xr = x?.let { ex -> (0..2).map { Store.exampleRom(c, ex, it, place) } }
        // 華語: the other reading (注音 under 拼音, or 拼音 under 注音), its 詞類, and English as the meaning if chosen
        var z = zy.plain(); var p = def?.p ?: ""; var m = def?.t ?: ""
        val zd = Store.zh
        if (c.isZh && zd != null) {
            val syl = if (Prefs.zhPlace.value == 1) (c.zl ?: c.zs ?: emptyList()) else (c.zs ?: emptyList())
            z = zd.readingPlain(syl, if (Prefs.zhRom.value == 0) 1 else 0)
            zd.entry(c.k)?.let { e ->
                p = e.pos.joinToString("、")
                if (Prefs.zhEnglish.value && e.enList.isNotEmpty()) m = e.enList.take(3).joinToString("; ")
            }
        }
        return WidgetFiles.Word(
            k = c.k, h = c.h, a = c.a,
            r = rom.map { it.plain() }, z = z,
            p = p, m = m,
            xh = xh?.plain(), xr = xr?.map { it.plain() }, xz = x?.z, xn = x?.n,
            hc = hex(han), rc = rom.map { hex(it) }, zc = hex(zy),
            xhc = xh?.let { hex(it) }, xrc = xr?.map { hex(it) },
        )
    }
}
