package com.unoki99.fangfang

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.*
import java.io.File

/** Everything the app knows: the cards, your progress, and (loaded in the background) the full dictionary. */
object Store {
    lateinit var app: Context
        private set
    private val scope = MainScope()

    var cards: List<Card> by mutableStateOf(emptyList()); private set
    var loaded by mutableStateOf(false); private set
    var loadError by mutableStateOf<String?>(null); private set
    /** how far loading the cards has got (0–1), for the loading screen */
    var loadProgress by mutableStateOf(0f); private set
    var loadStep by mutableStateOf("讀取詞卡…"); private set
    var dict by mutableStateOf<Dict?>(null); private set
    var dictError by mutableStateOf<String?>(null); private set
    private var dictLoading = false

    var progress = Progress(); private set
    /** bumped on every change of progress: reading it makes a screen redraw on changes */
    private val revState = mutableIntStateOf(0)
    val rev: Int get() = revState.intValue

    var canUndo by mutableStateOf(false); private set
    var byKey: Map<String, Card> = emptyMap(); private set
    private var byKeyMutable = HashMap<String, Card>()
    var syl: Map<String, List<String>> = emptyMap(); private set
    var places: List<String> = emptyList(); private set
    var topics: List<Topic> = emptyList(); private set
    private var rank: Map<String, Int> = emptyMap()
    private var pools: Map<Int, List<Card>> = emptyMap()
    private class Undo(val key: String, val status: Int?, val added: Double?, val streak: Int?)
    private val undoStack = ArrayList<Undo>()
    private var saveJob: Job? = null

    var seenCount = 0; private set
    var unknownCount = 0; private set
    var knownCount = 0; private set
    private var newStart = 0
    private var queueTopic = -1

    private val progressFile get() = File(app.filesDir, "progress.json")

    // MARK: 華語 mode
    /** the cards shown are 華語 ones (the 台語 deck waits in `other` meanwhile) */
    var isZh by mutableStateOf(false); private set
    /** the language shown: 0 台語, 1 華語, 2 粵語, 3 客語 (粵語 and 客語 use the 華語 pages, with their own dictionaries) */
    var lang by mutableIntStateOf(0); private set
    val isYue: Boolean get() = lang == 2
    val isHak: Boolean get() = lang == 3
    val isJa: Boolean get() = lang == 4
    /** which of 華語 / 粵語 / 客語 the dictionary in `zh` is (1, 2 or 3) */
    private val zhKind: Int get() = zh?.lang ?: 1
    /** a hint to show (粵語 without a Cantonese voice on the device) */
    var speechHint by mutableStateOf<String?>(null)
    /** switching language: the other deck is being loaded */
    var switching by mutableStateOf(false); private set
    /** the 華語 dictionary (zh.json), once loaded */
    var zh by mutableStateOf<ZhDict?>(null); private set
    var zhError by mutableStateOf<String?>(null)
    /** changes when the deck is made again (pages showing it start over) */
    var listVersion by mutableIntStateOf(0); private set
    private class Deck(val cards: List<Card> = emptyList(), val byKey: HashMap<String, Card> = HashMap(), val rank: Map<String, Int> = emptyMap(),
                       val pools: Map<Int, List<Card>> = emptyMap(), val topics: List<Topic> = emptyList(), var kind: Int = 0)
    /** which language the deck waiting in `other` is (0 台語, 1 華語, 2 粵語) */
    private val otherKind: Int get() = other?.kind ?: -1
    private var other: Deck? = null
    const val zhDeckSize = 20000

    /** 倉頡 / 五筆 / 無蝦米 (read the first time they're shown; again after 華語 is installed) */
    private var inputCodesMade: InputCodes? = null
    val inputCodes: InputCodes get() = inputCodesMade ?: InputCodes(DataFiles.readText("inputcodes")).also { inputCodesMade = it }

    /** no 台語 data yet: the app still opens, and offers to install it (設定 → 詞典資料) */
    var taigiMissing by mutableStateOf(false); private set

    fun init(ctx: Context) {
        app = ctx.applicationContext
        // 台語 words' English (Wiktionary), read the first time it's needed
        TwEnglish.source = { DataFiles.readText("tw_en") }
    }

    private fun changed() {
        recount()
        // (the 不熟 / 熟悉 / review lists only change when a word's status, date or review does)
        val sig = progress.status.hashCode() * 31L * 31L + progress.added.hashCode() * 31L + progress.srs.hashCode()
        if (sig != listSig) { listSig = sig; listCache.clear() }
        revState.intValue++
    }

    /** the 不熟 / 熟悉 / review lists, made once and kept until a word changes (each page showing one used to sort
     *  every list again on every redraw) */
    private val listCache = HashMap<String, List<Card>>()
    private var listSig = 0L
    private var dueMadeAt = 0.0
    /** (and a list of another language or deck isn't this one's) */
    private fun listKey(k: String) = "$k|$lang|${System.identityHashCode(cards)}|${System.identityHashCode(zh)}"

    // MARK: loading

    fun load() {
        if (loaded || loadError != null) return
        scope.launch {
            try {
                val t0 = System.currentTimeMillis()
                loadStep = "讀取詞卡檔案…"
                val text = withContext(Dispatchers.IO) { DataFiles.readText("cards") }
                // (no 台語 data yet: the app still opens; 設定 → 詞典資料, or the first language chosen, installs it)
                taigiMissing = text == null
                loadStep = "整理詞卡…"
                val deck = if (text == null) DeckFile.parse("{\"cards\":[]}") { } else withContext(Dispatchers.Default) {
                    DeckFile.parse(text) { p -> launch(Dispatchers.Main) { loadProgress = p } }
                }
                loadProgress = 1f
                android.util.Log.i("Fangfang", "cards ready in ${System.currentTimeMillis() - t0} ms")
                val prog = withContext(Dispatchers.IO) {
                    try { if (progressFile.exists()) Progress.parse(progressFile.readText()) else Progress() } catch (_: Exception) { Progress() }
                }
                cards = deck.cards
                syl = deck.syl; places = deck.places; topics = deck.topics
                val bk = HashMap<String, Card>(); val rk = HashMap<String, Int>()
                for ((i, c) in deck.cards.withIndex()) { bk[c.k] = c; rk[c.k] = i }
                byKey = bk; rank = rk
                byKeyMutable = bk
                val pl = HashMap<Int, MutableList<Card>>()
                for (c in deck.cards.take(4000)) pl.getOrPut(c.syllables) { ArrayList() }.add(c)
                pools = pl
                progress = prog
                changed()
                loaded = true
                migrateSenses()
                makeFreqTopics()
                // both dictionaries are read when the app starts (in the background), so neither has to be waited for later
                loadDict()
                if (Prefs.lang.value in 1 until Lang.count) setLanguage(Prefs.lang.value) else preloadZh()
                Backup.syncNow()
                WidgetBridge.appOpened()
            } catch (e: java.io.FileNotFoundException) {
                loadError = "找不到 cards.json"
            } catch (e: Throwable) {
                android.util.Log.e("Fangfang", "loading failed", e)
                loadError = "字典讀取失敗：${e.javaClass.simpleName} ${e.message ?: ""}"
            }
        }
    }

    fun loadDict() {
        if (dict != null || dictLoading) return
        dictLoading = true
        scope.launch {
            try {
                val d = withContext(Dispatchers.Default) {
                    val text = DataFiles.readText("dict") ?: throw java.io.FileNotFoundException("dict.json")
                    Dict(DictRaw.parse(text), Prefs)
                }
                d.setUserWords(ownKeys.toSet())
                dict = d
                WidgetBridge.rebuildIfNeeded()
                // build the sentence index ahead of the first search
                launch(Dispatchers.Default) { d.sentences(listOf("\t")) }
            } catch (e: Throwable) {
                dictError = "字典讀取失敗：${e.message}"
            }
            dictLoading = false
        }
    }

    /** saves a moment later, off the main thread */
    fun save() {
        syncCharCards()
        WidgetBridge.progressChanged()
        saveJob?.cancel()
        saveJob = scope.launch {
            delay(700)
            if (!loaded) return@launch
            val text = progress.toJson()
            withContext(Dispatchers.IO) { writeAtomic(progressFile, text) }
        }
    }

    fun saveNow() {
        saveJob?.cancel()
        if (!loaded) return
        writeAtomic(progressFile, progress.toJson())
    }

    fun writeAtomic(f: File, text: String) {
        val tmp = File(f.parentFile, f.name + ".tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(f)) { f.writeText(text); tmp.delete() }
    }

    private fun recount() {
        var s = 0; var u = 0; var k = 0
        // only the language shown (台語 and 華語 words are counted apart)
        for ((key, v) in progress.status) {
            if (Lang.kind(key) != lang) continue
            if (v != 0) s++
            if (v == 1) k++ else if (v == 2) u++
        }
        seenCount = s; unknownCount = u; knownCount = k
        newStart = 0
    }

    private val now: Double get() = System.currentTimeMillis() / 1000.0

    // MARK: switching language

    fun setLanguage(wantZh: Boolean) = setLanguage(if (wantZh) 1 else 0)

    /** the spelling shown for 華語 / 粵語 (Prefs.zhRom) is kept apart for each */
    private fun shownRom(l: Int) {
        val was = lang
        when (was) { 1 -> Prefs.mandRom.value = Prefs.zhRom.value; 2 -> Prefs.yueRom.value = Prefs.zhRom.value; 3 -> Prefs.hakRom.value = Prefs.zhRom.value; 4 -> Prefs.jaRom.value = Prefs.zhRom.value }
        when (l) { 1 -> Prefs.zhRom.value = Prefs.mandRom.value; 2 -> Prefs.zhRom.value = Prefs.yueRom.value; 3 -> Prefs.zhRom.value = Prefs.hakRom.value; 4 -> Prefs.zhRom.value = Prefs.jaRom.value }
    }

    private fun shown(l: Int) {
        shownRom(l)
        lang = l; isZh = l != 0
        EngineSettings.yue = l == 2; EngineSettings.hak = l == 3; EngineSettings.ja = l == 4; EngineSettings.zhShown = l != 0
        undoStack.clear(); canUndo = false
        changed()
    }

    /** 0 台語, 1 華語, 2 粵語, 3 客語 */
    fun setLanguage(want0: Int) {
        val want = want0.coerceIn(0, Lang.count - 1)
        Prefs.lang.value = want
        if (want == lang || switching) return
        if (want != 0) Prefs.lastZh.value = want
        if (want == 0) { if (otherKind == 0) swapDecks(); shown(0); return }
        // the deck waiting is the one wanted (台語 → 華語 / 粵語)
        if (lang == 0 && otherKind == want) { swapDecks(); shown(want); return }
        switching = true
        scope.launch {
            try {
                val (d, deck) = zhLoad(want).await()
                useZh(d, deck)
            } catch (e: Throwable) {
                android.util.Log.e("Fangfang", "zh failed", e)
                zhError = if (e is java.io.FileNotFoundException) tr("還沒有{0}詞典：到「設定 → 詞典資料」安裝。", tr(Lang.names[want]))
                    else "${Lang.names[want]}詞典讀取失敗：${e.javaClass.simpleName} ${e.message ?: ""}"
                Prefs.lang.value = lang
                zhJob = null
            }
            switching = false
        }
    }

    /** the 華語 / 粵語 dictionary and deck being read (shared: reading it at start-up and switching meanwhile read it once) */
    private var zhJob: kotlinx.coroutines.Deferred<Pair<ZhDict, Deck>>? = null
    private var zhJobKind = 0

    /** kind: 1 華語 (zh.json), 2 粵語 (yue.json), 3 客語 (hak.json); fresh: read again (客語: another accent) */
    private fun zhLoad(kind: Int, fresh: Boolean = false): kotlinx.coroutines.Deferred<Pair<ZhDict, Deck>> {
        if (!fresh) zhJob?.let { if (zhJobKind == kind) return it }
        val keys = progress.status.keys.filter { Lang.kind(it) == kind } + progress.saved.keys.filter { Lang.kind(it) == kind }
        val have = if (fresh) null else zh?.takeIf { it.lang == kind }
        val list = Prefs.zhList.value
        val accent = Prefs.hakAccent.value.coerceIn(0, 5)
        val j = scope.async(Dispatchers.Default) {
            val name = listOf("zh", "zh", "yue", "hak", "ja")[kind.coerceIn(0, 4)]
            val d = have ?: ZhDict(DataFiles.readText(name) ?: throw java.io.FileNotFoundException("$name.json"), accent).also { d ->
                // 粵語, 客語: the radicals (部首查字) from the 華語 data, when it's there
                if (d.lang != 1 && d.lang != 4) DataFiles.readText("zh")?.let { z -> try { d.borrowRadicals(z) } catch (_: Exception) {} }
            }
            d to makeZhDeck(d, list, keys).also { it.kind = kind }
        }
        zhJob = j; zhJobKind = kind
        return j
    }

    /** reads the 華語 (or 粵語, if that was used last) dictionary in the background (at start-up, in 台語 mode) */
    fun preloadZh() {
        if (zh != null) return
        val kind = Prefs.lastZh.value.let { if (it in 1 until Lang.count) it else 1 }
        scope.launch {
            try { val (d, deck) = zhLoad(kind).await(); useZh(d, deck) } catch (e: Throwable) { zhJob = null }
        }
    }

    /** a 華語 / 粵語 dictionary is read: keep it, and use its deck now (if that language is wanted) or keep it for switching */
    private fun useZh(d: ZhDict, deck: Deck) {
        val kind = d.lang
        deck.kind = kind
        // (the other one of 華語 / 粵語, read in the background, finishing after this one was chosen: not kept)
        if (lang != 0 && kind != Prefs.lang.value) return
        val first = zh == null
        zh = d
        zhJob = null
        if (first) { syncCharCards(); save() }
        if (Prefs.lang.value == kind) {
            if (lang == kind) return
            if (lang == 0) other = Deck(cards, byKeyMutable, rank, pools, topics, 0)
            use(deck)
            shown(kind)
        } else if (lang == 0) {
            other = deck
        }
        WidgetBridge.rebuildIfNeeded()
    }

    /** 客語: another accent was chosen. The dictionary is read again with that accent's readings (the words stay the
     *  same, so 不熟 / 熟悉 don't change) */
    fun hakAccentChanged() {
        EngineSettings.hakAccent = Prefs.hakAccent.value.coerceIn(0, 5)
        if (lang != 3 || switching) return
        switching = true
        scope.launch {
            try {
                val (d, deck) = zhLoad(3, fresh = true).await()
                zhJob = null
                if (lang == 3) { deck.kind = 3; zh = d; use(deck); undoStack.clear(); canUndo = false; listVersion++; changed() }
            } catch (e: Throwable) { zhJob = null }
            switching = false
        }
    }

    /** a dictionary was installed or removed (設定 → 詞典資料): read again if it's the one in use */
    fun dictionaryChanged(kind: Int) {
        if (kind == 1) inputCodesMade = null
        if (kind == 0) { if (DataFiles.has("cards")) reloadTaigi(); return }
        if (kind < 0) return
        if (zh?.lang == kind && lang != kind) zh = null
        if (lang == kind && !switching) {
            switching = true
            scope.launch {
                try {
                    val (d, deck) = zhLoad(kind, fresh = true).await()
                    zhJob = null
                    if (lang == kind) { deck.kind = kind; zh = d; use(deck); undoStack.clear(); canUndo = false; listVersion++; changed() }
                } catch (e: Throwable) { zhJob = null }
                switching = false
            }
        }
    }

    /** 台語's words (cards.json) and dictionary, read again after installing them */
    fun reloadTaigi() {
        scope.launch {
            val text = withContext(Dispatchers.IO) { DataFiles.readText("cards") } ?: return@launch
            val deck = withContext(Dispatchers.Default) { DeckFile.parse(text) { } }
            val bk = HashMap<String, Card>(); val rk = HashMap<String, Int>()
            for ((i, c) in deck.cards.withIndex()) { bk[c.k] = c; rk[c.k] = i }
            val pl = HashMap<Int, MutableList<Card>>()
            for (c in deck.cards.take(4000)) pl.getOrPut(c.syllables) { ArrayList() }.add(c)
            syl = deck.syl; places = deck.places
            taigiMissing = false
            val d = Deck(deck.cards, bk, rk, pl, deck.topics, 0)
            if (lang == 0) { use(d); makeFreqTopics(); listVersion++; changed() } else other = d
            dict = null; dictLoading = false
            loadDict()
        }
    }

    private fun use(d: Deck) {
        cards = d.cards; byKeyMutable = d.byKey; byKey = d.byKey; rank = d.rank; pools = d.pools; topics = d.topics
        newStart = 0; queueTopic = -1
    }

    /** the 華語 cards: the words of a word list (HSK 3.0 or TOCFL), level by level, the more common ones first in each level */
    private fun makeZhDeck(d: ZhDict, list: Int, keys: List<String>): Deck {
        var order = d.entries.indices.filter { d.entries[it].level(list) > 0 }
            .sortedWith(compareBy({ d.entries[it].level(list) }, { it }))
        if (order.isEmpty()) order = (0 until minOf(d.cardCount, zhDeckSize)).toList()
        val cs = ArrayList<Card>(order.size); val bk = HashMap<String, Card>(); val rk = HashMap<String, Int>()
        val pl = HashMap<Int, MutableList<Card>>(); val counts = java.util.TreeMap<Int, Int>()
        for ((n, i) in order.withIndex()) {
            val c = d.card(i, list)
            cs.add(c); bk[c.k] = c; rk[c.k] = n
            if (n < 4000) pl.getOrPut(c.syllables) { ArrayList() }.add(c)
            val l = d.entries[i].level(list)
            if (l > 0) counts[l] = (counts[l] ?: 0) + 1
        }
        val tops = ArrayList(counts.map { (l, n) -> Topic(l, if (d.lang != 1) Lang.yueLevelName(l) else Lang.levelName(list, l), n) })
        // the character cards, after the words: level by level of the word list's character list, the more
        // common first; then the more common characters the list doesn't have
        val corder = d.chars.indices.sortedWith(compareBy({ d.chars[it].level(list).let { l -> if (l == 0) 99 else l } }, { it }))
        val ccounts = java.util.TreeMap<Int, Int>()
        for (i in corder) {
            val c = d.charCard(i, list)
            rk[c.k] = cs.size; cs.add(c); bk[c.k] = c
            c.cats?.firstOrNull()?.let { t -> ccounts[t] = (ccounts[t] ?: 0) + 1 }
        }
        for ((t, n) in ccounts) tops.add(Topic(t, if (t == Lang.moreChars) "漢字・更多常用字"
            else "漢字・" + (if (d.lang != 1) Lang.yueCharLevelName(t - Lang.charTopicBase) else Lang.levelName(list, t - Lang.charTopicBase)), n))
        // rarer words you already have in 不熟 / 熟悉 / 收藏
        for (k in keys) if (bk[k] == null) d.index[k]?.let { bk[k] = d.card(it, list) }
        return Deck(cs, bk, rk, pl, tops)
    }

    /** another word list for the 華語 cards (HSK ⇄ TOCFL): the deck is made again */
    fun setZhList(list: Int) {
        if (list == Prefs.zhList.value) return
        Prefs.zhList.value = list
        Prefs.zhTopic.value = -1
        val d = zh ?: return
        if (switching) return
        switching = true
        val kind = zhKind
        val keys = progress.status.keys.filter { Lang.kind(it) == kind } + progress.saved.keys.filter { Lang.kind(it) == kind }
        scope.launch {
            val deck = withContext(Dispatchers.Default) { makeZhDeck(d, list, keys) }.also { it.kind = kind }
            if (lang == kind) { use(deck); undoStack.clear(); canUndo = false } else if (otherKind == kind) other = deck
            switching = false
            listVersion++
            changed()
        }
    }

    /** 設定 → 字形 changed: the 華語 / 粵語 cards are made again (their 漢字 shown the new way) */
    fun simplifiedChanged() {
        val d = zh ?: return
        if (switching) return
        switching = true
        val kind = zhKind; val list = Prefs.zhList.value
        val keys = progress.status.keys.filter { Lang.kind(it) == kind } + progress.saved.keys.filter { Lang.kind(it) == kind }
        scope.launch {
            val deck = withContext(Dispatchers.Default) { makeZhDeck(d, list, keys) }.also { it.kind = kind }
            if (lang == kind) use(deck) else if (otherKind == kind) other = deck
            switching = false
            listVersion++
            changed()
        }
    }

    private fun swapDecks() {
        val o = other ?: return
        other = Deck(cards, byKeyMutable, rank, pools, topics, lang)
        use(o)
    }

    /** a word of the language shown as a card (華語: rarer dictionary words become cards when they're needed) */
    fun cardFor(k: String): Card? {
        byKey[k]?.let { return it }
        other?.byKey?.get(k)?.let { return it }
        if (!isZh || Lang.kind(k) != lang || lang != zhKind) return null
        val d = zh ?: return null
        Lang.charOf(k)?.let { ch ->
            val ci = d.charIndex[ch] ?: return null
            val c = d.charCard(ci, Prefs.zhList.value)
            byKeyMutable[k] = c
            return c
        }
        val i = d.index[k] ?: return null
        val c = d.card(i, Prefs.zhList.value)
        byKeyMutable[k] = c
        return c
    }

    /** a word of either language (for syncing: the other language's words are kept too) */
    private fun isWord(k: String): Boolean =
        byKey[k] != null || other?.byKey?.get(k) != null ||
            (Lang.isZhKey(k) && (zh == null || Lang.kind(k) != zhKind || zh?.index?.get(k) != null || Lang.charOf(k)?.let { zh?.charIndex?.get(it) != null } == true))

    /** each language's cards and topics, whichever is shown now (for the widgets; 華語 once it has loaded) */
    val twDeck: Pair<List<Card>, List<Topic>> get() {
        if (!isZh) return cards to topics
        val o = other
        return if (o != null && o.kind == 0) o.cards to o.topics else emptyList<Card>() to emptyList()
    }
    val zhDeck: Pair<List<Card>, List<Topic>> get() {
        if (isZh) return cards to topics
        val o = other
        return if (o != null && o.kind != 0) o.cards to o.topics else emptyList<Card>() to emptyList()
    }

    // MARK: 漢字 (華語)

    /** the characters for 認識的漢字: all of them in the order they come in the cards, and which are 熟悉 / 不熟 */
    class CharSets(val all: List<String>, val known: Set<String>, val unknown: Set<String>)

    fun zhCharSets(): CharSets {
        rev
        fun hans(s: String) = s.cps().filter { Zhuyin.isHan(it.firstCp()) }
        val known = HashSet<String>(); val unknown = HashSet<String>(); val seen = HashSet<String>(); val all = ArrayList<String>()
        fun add(cs: List<String>) { for (ch in cs) if (seen.add(ch)) all.add(ch) }
        for (c in zhDeck.first) add(hans(c.h))
        for ((k, v) in progress.status) {
            if (v == 0 || Lang.kind(k) != lang) continue
            val cs = hans(k.substringBefore('\t'))
            add(cs)
            if (v == 1) known.addAll(cs) else if (v == 2) unknown.addAll(cs)
        }
        unknown.removeAll(known)
        // a character card marked 不熟 after its words were learned (held in 認識的漢字): 不熟 wins
        for ((k, v) in progress.status) if (v == 2) Lang.charOf(k)?.let { known.remove(it); unknown.add(it) }
        return CharSets(all, known, unknown)
    }

    /** every character of a 熟悉 word is known, so its character card is marked 熟悉 too */
    fun syncCharCards() {
        val d = zh ?: return
        if (d.chars.isEmpty()) return
        val kind = d.lang
        val want = ArrayList<String>(); val seen = HashSet<String>()
        for ((k, v) in progress.status) {
            if (v != 1 || Lang.charOf(k) != null || Lang.kind(k) != kind) continue
            for (ch in k.substringBefore('\t').cps()) {
                if (!Zhuyin.isHan(ch.firstCp()) || !seen.add(ch) || d.charIndex[ch] == null) continue
                val ck = Lang.charKey(ch, d.isYue, d.isHak, d.isJa)
                when (progress.status[ck]) {
                    1 -> {}
                    // marked 不熟 by hand after the word was learned: left as it is
                    2 -> if ((progress.added[ck] ?: 0.0) < (progress.added[k] ?: 0.0)) want.add(ck)
                    else -> want.add(ck)
                }
            }
        }
        if (want.isEmpty()) return
        val t = now
        for (ck in want) { progress.status[ck] = 1; progress.added[ck] = t; progress.streak.remove(ck) }
        changed()
    }

    /** 認識的漢字: hold a character to make it 熟悉 or 不熟 (its character card) */
    fun setCharKnown(ch: String, known: Boolean): Boolean {
        val c = cardFor(Lang.charKey(ch)) ?: return false
        mark(c, known, undoable = false)
        return true
    }

    /** the words of the language shown */
    fun isShownLanguage(k: String): Boolean = Lang.kind(k) == lang

    // MARK: 本週學習 (this week's words)

    private val weekLang: String get() = listOf("tw", "zh", "yue", "hak", "ja")[lang.coerceIn(0, 4)]

    /** this week's words (in the language shown), in the order they were picked */
    val weekCards: List<Card> get() {
        rev
        return progress.week.filter { it.value > 0 && isShownLanguage(it.key) }.entries.sortedBy { it.value }.mapNotNull { cardFor(it.key) }
    }
    fun isInWeek(k: String): Boolean { rev; return (progress.week[k] ?: -1.0) > 0 }

    /** days left of the week (0 = it's time for the test) */
    val weekDaysLeft: Int get() {
        rev
        val t = progress.weekStart[weekLang] ?: return 7
        if (t <= 0) return 7
        val z = java.time.ZoneId.systemDefault()
        val start = java.time.Instant.ofEpochMilli((t * 1000).toLong()).atZone(z).toLocalDate()
        val days = java.time.temporal.ChronoUnit.DAYS.between(start, java.time.LocalDate.now(z)).toInt()
        return maxOf(0, 7 - days)
    }

    fun toggleWeek(k: String) = setWeek(listOf(k), !isInWeek(k))

    fun setWeek(keys: List<String>, on: Boolean) {
        var t = now
        for (k in keys) { t += 0.001; progress.week[k] = if (on) t else -t }
        // the first word picked starts the week
        if (on && (progress.weekStart[weekLang] ?: -1.0) <= 0) progress.weekStart[weekLang] = now
        val any = progress.week.any { it.value > 0 && isShownLanguage(it.key) }
        if (!any && (progress.weekStart[weekLang] ?: -1.0) > 0) progress.weekStart[weekLang] = -now
        changed(); save()
    }

    /** the week is over: its words are taken out (`keep` = words that go on to next week, which starts now) */
    fun finishWeek(keep: List<String> = emptyList()) {
        val t = now
        for (c in weekCards) if (c.k !in keep) progress.week[c.k] = -t
        if (keep.isEmpty()) progress.weekStart[weekLang] = -t
        else { progress.weekStart[weekLang] = t + 0.001; for (k in keep) progress.week[k] = t + 0.002 }
        changed(); save()
    }

    // MARK: word lists

    /** the words of a level of the word list (HSK / TOCFL), in order */
    fun levelCards(level: Int): List<Card> = cards.filter { inTopic(it, level) }

    // MARK: 台語 常用詞 / 常用字 groups (500 each; the cards are the most common first)

    var freqTopics: List<Topic> by mutableStateOf(emptyList()); private set
    private var freqTopic: Map<String, Int> = emptyMap()

    private fun makeFreqTopics() {
        val tw = twDeck.first
        var nw = 0; var nc = 0
        val m = HashMap<String, Int>(); val counts = java.util.TreeMap<Int, Int>()
        for (c in tw) {
            val t = if (c.h.codePointCount(0, c.h.length) == 1) Lang.freqCharBase + nc++ / Lang.freqSize else Lang.freqWordBase + nw++ / Lang.freqSize
            m[c.k] = t
            counts[t] = (counts[t] ?: 0) + 1
        }
        freqTopic = m
        freqTopics = counts.map { (t, n) -> Topic(t, Lang.freqName(t, n), n) }
    }

    /** a card is in a topic: a 分類 or level (its cats), or a 台語 常用 group */
    fun inTopic(c: Card, t: Int): Boolean {
        if (Lang.isFreqTopic(t)) return !c.isZh && freqTopic[c.k] == t
        return c.cats?.firstOrNull() == t || (!c.isZh && c.cats?.contains(t) == true)
    }

    /** the progress of every topic at once (one pass over the cards) */
    fun allTopicProgress(): Map<Int, LevelProgress> {
        rev
        val t = HashMap<Int, IntArray>()
        for (c in cards) {
            val id = (if (!c.isZh) freqTopic[c.k] else null) ?: c.cats?.firstOrNull() ?: continue
            val a = t.getOrPut(id) { IntArray(3) }
            a[0]++
            when (progress.status[c.k]) { 1 -> a[1]++; 2 -> a[2]++ }
        }
        return t.mapValues { LevelProgress(it.value[0], it.value[1], it.value[2]) }
    }

    // MARK: 練習範圍

    /** -1 = all of 不熟; 華語: a level (words) or 100 + level (characters); 台語: a 常用詞 / 常用字 group */
    var practiceTopic: Int
        get() = if (isZh) Prefs.practiceZh.value else Prefs.practiceTw.value
        set(v) { if (isZh) Prefs.practiceZh.value = v else Prefs.practiceTw.value = v }
    val practiceTopics: List<Topic> get() = if (isZh) topics else freqTopics
    /** the 不熟 words to practise (練習範圍) */
    val practiceCards: List<Card> get() {
        val u = unknownCards
        val t = practiceTopic
        if (t < 0 || practiceTopics.none { it.id == t }) return u
        val key = listKey("p$t")
        listCache[key]?.let { return it }
        val out = u.filter { inTopic(it, t) }
        listCache[key] = out
        return out
    }
    val practiceName: String get() = practiceTopics.firstOrNull { it.id == practiceTopic }?.name ?: tr("全部不熟的詞")

    /** many words at once to 熟悉 (or back to 新詞) */
    fun markAll(list: List<Card>, known: Boolean) {
        val t = now
        for (c in list) {
            if (known) {
                if (progress.status[c.k] == 1) continue
                progress.status[c.k] = 1; progress.streak.remove(c.k)
            } else {
                if ((progress.status[c.k] ?: 0) == 0) continue
                progress.status[c.k] = 0; progress.streak.remove(c.k)
            }
            progress.added[c.k] = t
        }
        undoStack.clear(); canUndo = false
        changed(); save()
    }

    class LevelProgress(val total: Int, val known: Int, val unknown: Int)

    /** progress on a level of the word list (HSK / TOCFL) */
    fun hskProgress(level: Int): LevelProgress {
        rev
        var t = 0; var k = 0; var u = 0
        for (c in cards) if (inTopic(c, level)) {
            t++
            when (progress.status[c.k]) { 1 -> k++; 2 -> u++ }
        }
        return LevelProgress(t, k, u)
    }

    // MARK: lists

    fun status(c: Card): Int? { rev; return progress.status[c.k] }
    fun streak(c: Card): Int { rev; return progress.streak[c.k] ?: 0 }

    fun newQueue(n: Int, topic: Int = -1): List<Card> {
        rev
        if (topic != queueTopic) { queueTopic = topic; newStart = 0 }
        val out = ArrayList<Card>()
        var i = newStart
        var first: Int? = null
        while (i < cards.size && out.size < n) {
            val c = cards[i]
            if ((progress.status[c.k] ?: 0) == 0 && (topic < 0 || (if (Lang.isFreqTopic(topic)) inTopic(c, topic) else c.cats?.contains(topic) == true))) {
                if (first == null) first = i
                out.add(c)
            }
            i++
        }
        newStart = first ?: cards.size
        return out
    }

    private fun list(s: Int): List<Card> {
        rev
        val key = listKey("s$s")
        listCache[key]?.let { return it }
        val added = progress.added
        val out = progress.status.mapNotNull { (k, v) -> if (v == s && isShownLanguage(k)) cardFor(k) else null }
            .sortedByDescending { added[it.k] ?: 0.0 }
        listCache[key] = out
        return out
    }
    val unknownCards: List<Card> get() = list(2)
    val knownCards: List<Card> get() = list(1)

    // MARK: changes

    fun mark(c: Card, known: Boolean, undoable: Boolean = true) {
        if (undoable) {
            undoStack.add(Undo(c.k, progress.status[c.k], progress.added[c.k], progress.streak[c.k]))
            if (undoStack.size > 50) undoStack.removeAt(0)
            canUndo = true
        }
        progress.status[c.k] = if (known) 1 else 2
        progress.added[c.k] = now
        if (known) progress.streak.remove(c.k) else if (progress.streak[c.k] == null) progress.streak[c.k] = 0
        changed(); save()
    }

    fun undo() {
        val u = undoStack.removeLastOrNull() ?: return
        if (u.status != null) progress.status[u.key] = u.status else progress.status.remove(u.key)
        if (u.added != null) progress.added[u.key] = u.added else progress.added.remove(u.key)
        if (u.streak != null) progress.streak[u.key] = u.streak else progress.streak.remove(u.key)
        canUndo = undoStack.isNotEmpty()
        changed(); save()
    }

    fun forget(c: Card) {
        progress.status[c.k] = 0
        progress.added[c.k] = now
        progress.streak.remove(c.k)
        progress.srs.remove(c.k)
        changed(); save()
    }

    /** study answer; returns true when the word has been learned (moved to 熟悉) or a review was answered right.
     *  A word learned in practice comes back after 1 day, then 3, then each time about 2.5× longer (SM-2:
     *  Algorithm SM-2, (C) Copyright SuperMemo World, 1991. www.supermemo.com); answered wrong it goes back to 不熟. */
    fun answer(c: Card, correct: Boolean, goal: Int): Boolean {
        val st = progress.status[c.k]
        val review = st == 1 && isDue(c.k)
        if (st != 2 && !review) return false
        val t = now
        val s = progress.srs[c.k]?.toMutableList() ?: mutableListOf(0.0, 0.0, SRS.EASE, 0.0, 0.0, 0.0)
        while (s.size < 6) s.add(0.0)
        var done = false
        if (review) {
            if (correct) {
                val iv = if (s[1] < 1) 1.0 else if (s[1] < 2) 3.0 else Math.round(s[1] * s[2]).toDouble()
                s[1] = minOf(iv, SRS.LONGEST); s[3] += 1
                s[0] = t + SRS.days(s[1])
                done = true
            } else {
                // forgotten: back to 不熟 (learned again from the start)
                s[2] = maxOf(SRS.MIN_EASE, s[2] - 0.2); s[4] += 1; s[1] = 0.0; s[0] = 0.0
                progress.status[c.k] = 2; progress.added[c.k] = t; progress.streak[c.k] = 0
            }
        } else if (correct) {
            val n = (progress.streak[c.k] ?: 0) + 1
            if (n >= goal) {
                // learned: to 熟悉, back for review tomorrow
                progress.status[c.k] = 1; progress.added[c.k] = t; progress.streak.remove(c.k)
                s[1] = 1.0; s[3] += 1; s[0] = t + SRS.days(1.0)
                done = true
            } else progress.streak[c.k] = n
        } else progress.streak[c.k] = 0
        s[5] = t
        progress.srs[c.k] = s
        // 練習統計
        val day = SRS.dayKey(Lang.names[lang], java.util.Date())
        val l = progress.log[day]?.toMutableList() ?: mutableListOf(0, 0, 0)
        while (l.size < 3) l.add(0)
        if (correct) l[0] += 1 else l[1] += 1
        if (done && !review) l[2] += 1
        progress.log[day] = l
        changed(); save()
        return done
    }

    /** a word learned in practice whose review time has come */
    fun isDue(k: String, at: Double = now): Boolean {
        val s = progress.srs[k] ?: return false
        return s.size >= 2 && s[1] >= 1 && s[0] <= at
    }
    /** the days until a word comes back (null: not scheduled) */
    fun reviewDays(c: Card): Int? {
        if (progress.status[c.k] != 1) return null
        val s = progress.srs[c.k] ?: return null
        return if (s.size >= 2 && s[1] >= 1) s[1].toInt() else null
    }
    /** the words of the shown language that are due for review now (in 練習範圍) */
    val dueCards: List<Card> get() {
        rev
        val t0 = now
        val t = practiceTopic
        // (kept for a minute: words come due by the hour or day, not by the second)
        if (t0 - dueMadeAt > 60) listCache.keys.removeAll { it.startsWith("d") }
        val key = listKey("d$t")
        listCache[key]?.let { return it }
        val scoped = t >= 0 && practiceTopics.any { it.id == t }
        val out = progress.srs.mapNotNull { (k, s) ->
            if (s.size < 2 || s[1] < 1 || s[0] > t0 || progress.status[k] != 1 || Lang.kind(k) != lang) return@mapNotNull null
            val c = cardFor(k) ?: return@mapNotNull null
            if (scoped && !inTopic(c, t)) null else c
        }
        listCache[key] = out
        dueMadeAt = t0
        return out
    }
    /** 開始練習 / 例句填空: the words due for review first, then the 不熟 words */
    val studyCards: List<Card> get() = dueCards.shuffled() + practiceCards

    // MARK: what practice shows

    /** 主要解釋 = 英文 (設定, each of 台語, 華語, 客語): a card's English meanings (null: the dictionary's own;
     *  粵語's and 日語's are English already). 台語's are Wiktionary's (tw_en.json). */
    fun englishMeanings(c: Card): List<String>? {
        val kind = Lang.kind(c.k)
        if (kind == 0) {
            if (!Prefs.twEnglish.value) return null
            return TwEnglish.meanings(c.k).takeIf { it.isNotEmpty() }
        }
        val on = when (kind) { 1 -> Prefs.zhEnglish.value; 3 -> Prefs.hakEnglish.value; else -> false }
        if (!on) return null
        val d = zh ?: return null
        if (d.lang != kind) return null
        val e = Lang.charOf(c.k)?.let { d.entryForChar(it, "") } ?: d.entry(c.k)
        return e?.enList?.takeIf { it.isNotEmpty() }
    }
    /** the meaning practice shows for a card: the English (the first two) when that's chosen, or the first meaning */
    fun practiceMeaning(c: Card): Pair<String, String> {
        englishMeanings(c)?.let { return "" to it.take(2).joinToString("; ") }
        return (c.d.firstOrNull()?.p ?: "") to c.firstMeaning
    }
    /** 寫字題: a word of 1–4 characters, all of them 漢字 */
    fun canWrite(h: String): Boolean {
        val cps = h.codePoints().toArray()
        return cps.size in 1..4 && cps.all { Character.isIdeographic(it) }
    }

    /** the place's other way(s) of saying a card's word: (羅馬字, 方音) */
    fun alsoSaid(card: Card, rom: Int, place: Int): List<Pair<String, String>> {
        if (card.isZh) return emptyList()
        val d = dict ?: return emptyList()
        if (place < 0) return emptyList()
        val r = rom.coerceIn(0, 2)
        return d.alsoSaid(card.k, place).map { Pair(d.codes(it, r, place), d.codes(it, 3, place)) }
    }

    private fun zhSyl(card: Card): List<String> = if (Prefs.zhPlace.value == 1) (card.zl ?: card.zs!!) else card.zs!!

    fun cardHan(card: Card, place: Int, base: Int): Styled {
        val z = zh
        if (card.zs != null && z != null) return z.hanText(card.h, zhSyl(card), base)
        val d = dict
        if (EngineSettings.toneSystem != 0 && d != null) return d.hanText(card.k, place, base)
        return styled(card.h, base)
    }

    fun cardRom(card: Card, rom: Int, place: Int): Styled {
        val z = zh
        if (card.zs != null && z != null) return z.reading(zhSyl(card), Prefs.zhRom.value)
        val r = rom.coerceIn(0, 2)
        val d = dict
        if (EngineSettings.toneSystem != 0 && d != null) return d.wordText(card.k, r, place)
        if (place >= 0 && d != null && d.guessedSyllables(card.k, place).isNotEmpty()) return d.wordText(card.k, r, place)
        return styled(card.rom(r, place))
    }

    fun cardZy(card: Card, place: Int): Styled {
        if (card.isZh) return emptyList()       // 華語: one reading line (拼音 or 注音)
        val d = dict
        if ((place >= 0 || EngineSettings.toneSystem != 0) && d != null) return d.wordText(card.k, 3, place)
        return styled(card.zy(place))
    }

    /** 客語: an example sentence in the dictionary's words (as in 轉換), the card's word kept whole and read as the
     *  card reads it */
    private fun examplePieces(d: ZhDict, card: Card, text: String): List<ZhPiece> {
        val syl = card.zs
        if (syl == null || card.h.isEmpty() || !text.contains(card.h)) return d.convertPieces(text)
        val parts = text.split(card.h)
        val word = card.h.cps()
        val out = ArrayList<ZhPiece>()
        for ((i, part) in parts.withIndex()) {
            out.addAll(d.convertPieces(part))
            if (i < parts.size - 1) out.add(ZhPiece(word, syl.take(word.size), null))
        }
        return out
    }

    private fun dictExample(d: Dict, card: Card, x: Example): List<String>? =
        d.raw.ex[card.k]?.flatten()?.firstOrNull { it.size > 3 && it[0] == x.h && it[3] == x.n }

    fun exampleRom(card: Card, x: Example, rom: Int, place: Int): Styled {
        val z = zh
        if (x.w != null && z != null) return z.sentence(ZhDict.pieces(x.h, x.w), Prefs.zhRom.value, Prefs.zhPlace.value)
        // (客語: the sentences have no reading of their own: the dictionary's words, as in 轉換)
        if (card.isZh) return if (z != null) z.sentence(examplePieces(z, card, x.h), Prefs.zhRom.value, Prefs.zhPlace.value) else styled("")
        val r = rom.coerceIn(0, 2)
        val d = dict
        if ((place >= 0 || EngineSettings.toneSystem != 0) && d != null) {
            val e = dictExample(d, card, x)
            if (e != null) return d.sentenceText(e[1], r, place, e[0], if (e.size > 2) e[2] else null)
        }
        return styled(x.r[r])
    }

    fun exampleHan(card: Card, x: Example, place: Int, base: Int): Styled {
        val z = zh
        if (x.w != null && z != null) return z.sentenceHan(ZhDict.pieces(x.h, x.w), Prefs.zhPlace.value, base)
        if (card.isZh) return if (z != null) z.sentenceHan(examplePieces(z, card, x.h), Prefs.zhPlace.value, base) else styled(x.h, base)
        val d = dict
        if ((place >= 0 || EngineSettings.toneSystem != 0) && d != null) {
            val e = dictExample(d, card, x)
            if (e != null) return d.exampleHanText(e[0], e[1], place, if (e.size > 2) e[2] else null, base)
        }
        return styled(x.h, base)
    }

    fun blankRom(card: Card, x: Example, rom: Int, place: Int): Styled? {
        val z = zh
        if (x.w != null && z != null) return z.sentence(ZhDict.pieces(x.h, x.w), Prefs.zhRom.value, Prefs.zhPlace.value, blank = card.h)
        if (card.isZh) return z?.sentence(examplePieces(z, card, x.h), Prefs.zhRom.value, Prefs.zhPlace.value, blank = card.h)
        val r = rom.coerceIn(0, 2)
        val d = dict
        if (place >= 0 && d != null) {
            val e = dictExample(d, card, x)
            if (e != null) {
                val ps = d.blankSentencePieces(e[1], e[0], Dict.codesOf(card.k).split(' '), r, place)
                if (ps != null) return guessColored(ps)
            }
        }
        return x.br?.let { styled(it[r]) }
    }

    fun cardHasGuess(card: Card, place: Int): Boolean {
        if (card.isZh) return false
        val d = dict ?: return false
        if (place < 0) return false
        return card.d.any { def -> def.x.any { x -> dictExample(d, card, x)?.let { d.hasGuess(it[1], it[0], place) } ?: false } }
    }

    fun isGuessed(card: Card, place: Int): Boolean {
        if (card.isZh) return false
        val d = dict ?: return false
        if (place < 0 || !cardDiffers(card, place)) return false
        return !d.isStated(card.k, place)
    }

    fun cardDiffers(card: Card, place: Int): Boolean = if (card.isZh) false else dict?.differsFromCommon(card.k, place) ?: card.differs(place)

    /** status of a dictionary word in the cards: null = not a card */
    fun cardStatus(key: String): Int? { rev; if (cardFor(key) == null) return null; return progress.status[key] ?: 0 }

    fun toggleUnknown(key: String) {
        val c = cardFor(key) ?: return
        if (progress.status[key] == 2) forget(c) else mark(c, false, undoable = false)
    }

    // MARK: 收藏

    fun isSaved(key: String): Boolean { rev; return (progress.saved[key] ?: -1.0) > 0 }

    fun toggleSaved(key: String) {
        progress.saved[key] = if (isSaved(key)) -now else now
        changed(); save()
    }

    // MARK: 自訂

    val ownKeys: List<String> get() { rev; return progress.own.filter { it.value > 0 }.entries.sortedByDescending { it.value }.map { it.key } }
    fun isOwn(key: String): Boolean { rev; return (progress.own[key] ?: -1.0) > 0 }
    fun addOwn(key: String) { progress.own[key] = now; changed(); save(); applyOwn() }
    fun removeOwn(key: String) { progress.own[key] = -now; changed(); save(); applyOwn() }
    fun applyOwn() { dict?.setUserWords(ownKeys.toSet()) }

    fun rankOf(key: String): Int = rank[key] ?: Int.MAX_VALUE

    fun addUnknown(keys: List<String>) {
        var n = 0
        val t = now
        for (k in keys) if (cardFor(k) != null && (progress.status[k] ?: 0) == 0) {
            progress.status[k] = 2; progress.added[k] = t; progress.streak[k] = 0; n++
        }
        if (n > 0) { changed(); save() }
    }

    fun saveAll(keys: List<String>) {
        val t = now
        for ((i, k) in keys.withIndex()) if (!isSaved(k)) progress.saved[k] = t + (keys.size - i) * 0.001
        changed(); save()
    }

    fun unsave(keys: List<String>) {
        val t = now
        for (k in keys) progress.saved[k] = -t
        changed(); save()
    }

    val savedKeys: List<String> get() { rev; return progress.saved.filter { it.value > 0 && isShownLanguage(it.key) }.entries.sortedByDescending { it.value }.map { it.key } }

    // MARK: 收藏 of one meaning

    fun isSaved(s: SavedSense): Boolean { rev; return (progress.senses[s.id] ?: -1.0) > 0 }
    fun toggleSaved(s: SavedSense) { progress.senses[s.id] = if (isSaved(s)) -now else now; changed(); save() }
    fun unsave(s: SavedSense) { progress.senses[s.id] = -now; changed(); save() }

    /** saved meanings, newest first */
    val savedSenses: List<SavedSense> get() {
        rev
        return progress.senses.filter { it.value > 0 }.entries.sortedByDescending { it.value }.mapNotNull { SavedSense.fromId(it.key) }
            .filter { it.ex.isEmpty() && isShownLanguage(it.key) }
    }
    /** words with at least one meaning saved (the blue star in 轉換) */
    val savedSenseKeys: Set<String> get() = savedSenses.map { it.key }.toSet()

    /** an earlier version could save single sentences: each becomes its whole meaning */
    private fun migrateSenses() {
        var ch = false
        val t0 = now
        for ((id, t) in progress.senses.entries.toList()) {
            if (t <= 0) continue
            val s = SavedSense.fromId(id) ?: continue
            if (s.ex.isEmpty()) continue
            val m = SavedSense(s.key, s.sense).id
            if ((progress.senses[m] ?: -1.0) < t) progress.senses[m] = t
            progress.senses[id] = -t0
            ch = true
        }
        if (ch) save()
    }

    private fun q(s: String) = if (s.any { it == ';' || it == '"' || it == '\n' }) "\"" + s.replace("\"", "\"\"") + "\"" else s

    fun savedCSV(d: Dict): String {
        val rows = arrayListOf("詞;皓羅;詞性;釋義;例句;例句皓羅;例句華語;音檔;例句音檔")
        for (k in savedKeys) {
            val h = Dict.hanOf(k); val r = d.word(k, 0, -1)
            val audio = d.raw.au[k]?.let { "$it(1)" } ?: ""
            val senses = d.senses(k)
            if (senses.isEmpty()) rows.add(listOf(h, r, "", "", "", "", "", audio, "").joinToString(";") { q(it) })
            for (s in senses) {
                val x = s.ex.firstOrNull()
                rows.add(listOf(h, r, s.pos, s.text, x?.getOrNull(0) ?: "", if (x != null && x.size > 1) d.sentence(x[1], 0) else "",
                    x?.getOrNull(2) ?: "", audio, x?.getOrNull(3) ?: "").joinToString(";") { q(it) })
            }
        }
        // saved meanings: one row each; its sentences one after another, separated by <br> (a line break in Anki)
        for (s in savedSenses) {
            val senses = d.senses(s.key)
            if (s.sense >= senses.size) continue
            val m = senses[s.sense]
            val h = Dict.hanOf(s.key); val r = d.word(s.key, 0, -1)
            val audio = d.raw.au[s.key]?.let { "$it(1)" } ?: ""
            val xs = m.ex
            rows.add(listOf(h, r, m.pos, m.text,
                xs.joinToString("<br>") { it.getOrNull(0) ?: "" },
                xs.joinToString("<br>") { if (it.size > 1) d.sentence(it[1], 0) else "" },
                xs.joinToString("<br>") { it.getOrNull(2) ?: "" },
                audio,
                xs.joinToString("<br>") { it.getOrNull(3) ?: "" }).joinToString(";") { q(it) })
        }
        return "﻿" + rows.joinToString("\n") + "\n"
    }

    /** 華語 收藏 as CSV: word, 拼音 with tone numbers (a space between syllables), meaning (English first),
     *  sentences (a blank line between them); saved words first, then saved meanings */
    fun zhSavedCSV(d: ZhDict): String {
        fun qc(s: String) = if (s.any { it == ',' || it == '"' || it == '\n' }) "\"" + s.replace("\"", "\"\"") + "\"" else s
        fun numbered(e: ZhEntry) = e.syl(Prefs.zhPlace.value).filter { it != "-" && it != "_" }.joinToString(" ") { s ->
            val t = Zhuyin.tone(s); Zhuyin.plainSyllable(s).replace("v", "ü") + (if (t == 0) 5 else t)
        }
        val rows = arrayListOf("word,pronunciation,meaning,sentences")
        for (k in savedKeys) {
            val e = d.entry(k) ?: continue
            val meaning = e.en ?: e.senses.joinToString("；") { it.text }
            rows.add(listOf(e.h, numbered(e), meaning, e.senses.flatMap { it.ex }.joinToString("\n\n") { it.h }).joinToString(",") { qc(it) })
        }
        for (s in savedSenses) {
            val e = d.entry(s.key) ?: continue
            if (s.sense >= e.senses.size) continue
            val m = e.senses[s.sense]
            val meaning = e.en?.let { it + "（${m.text}）" } ?: m.text
            rows.add(listOf(e.h, numbered(e), meaning, m.ex.joinToString("\n\n") { it.h }).joinToString(",") { qc(it) })
        }
        return "\uFEFF" + rows.joinToString("\n") + "\n"
    }

    fun resetAll() {
        val t = now
        val p = Progress()
        for (k in progress.status.keys) { p.status[k] = 0; p.added[k] = t }
        p.saved.putAll(progress.saved); p.own.putAll(progress.own); p.senses.putAll(progress.senses)
        progress = p
        undoStack.clear(); canUndo = false
        changed(); save()
    }

    // MARK: study helpers

    fun distractors(c: Card, count: Int = 3): List<Card> {
        var pool = pools[c.syllables] ?: emptyList()
        if (pool.size < 20) pool = cards.take(4000)
        val out = ArrayList<Card>()
        val usedH = hashSetOf(c.h); val usedM = hashSetOf(c.firstMeaning); val usedR = hashSetOf(c.r[0])
        var tries = 0
        while (out.size < count && tries < 200) {
            tries++
            val x = pool.randomOrNull() ?: break
            if (usedH.contains(x.h) || usedM.contains(x.firstMeaning) || usedR.contains(x.r[0])) continue
            usedH.add(x.h); usedM.add(x.firstMeaning); usedR.add(x.r[0])
            out.add(x)
        }
        return out
    }

    // MARK: export / import

    fun csv(list: List<Card>): String {
        val rows = arrayListOf("詞;皓羅;詞性;釋義;例句;例句皓羅;例句華語;音檔;例句音檔")
        for (c in list) for (d in c.d) {
            val x = d.x.firstOrNull()
            val audio = if (c.isZh) "" else c.a?.let { "$it(1)" } ?: ""
            val xr = x?.let { if (c.isZh) exampleRom(c, it, 0, -1).plain() else it.r[0] } ?: ""
            val r = if (c.isZh) cardRom(c, 0, -1).plain() else c.r[0]
            rows.add(listOf(c.h, r, d.p, d.t, x?.h ?: "", xr, x?.z ?: "", audio, if (c.isZh) "" else x?.n ?: "").joinToString(";") { q(it) })
        }
        return "﻿" + rows.joinToString("\n") + "\n"
    }

    @Suppress("UNCHECKED_CAST")
    fun mergeProgress(obj: Map<String, Any?>): Int {
        val n = mergeSlice(obj, 0, Int.MAX_VALUE)
        changed()
        if (ownChangedInMerge) applyOwn()
        return n
    }

    private var ownChangedInMerge = false

    /** the merge, the words (status) from..<to of them in key order (the rest with the first slice) */
    @Suppress("UNCHECKED_CAST")
    private fun mergeSlice(obj: Map<String, Any?>, from: Int, to: Int): Int {
        fun dmap(k: String): Map<String, Double> = (obj[k] as? Map<String, Any?>)?.mapNotNull { (a, b) -> (b as? Number)?.let { a to it.toDouble() } }?.toMap() ?: emptyMap()
        val statusAll = dmap("status")
        val keys = statusAll.keys.sorted()
        val status = keys.subList(minOf(from, keys.size), minOf(to, keys.size)).associateWith { statusAll[it]!!.toInt() }
        val added = dmap("added")
        val streak = dmap("streak").mapValues { it.value.toInt() }
        var n = 0
        if (from == 0) ownChangedInMerge = false
        if (from == 0) for ((k, t) in dmap("saved")) if (Math.abs(t) > Math.abs(progress.saved[k] ?: 0.0)) {
            if ((t > 0) != isSaved(k)) n++
            progress.saved[k] = t
        }
        if (from == 0) for ((k, t) in dmap("week")) if (Math.abs(t) > Math.abs(progress.week[k] ?: 0.0)) {
            if ((t > 0) != ((progress.week[k] ?: -1.0) > 0)) n++
            progress.week[k] = t
        }
        // the week that was started (or ended) last wins
        if (from == 0) for ((k, t) in dmap("weekStart")) if (Math.abs(t) > Math.abs(progress.weekStart[k] ?: 0.0)) progress.weekStart[k] = t
        if (from == 0) for ((k, t) in dmap("senses")) if (Math.abs(t) > Math.abs(progress.senses[k] ?: 0.0)) {
            if ((t > 0) != ((progress.senses[k] ?: -1.0) > 0)) n++
            progress.senses[k] = t
        }
        if (from == 0) for ((k, t) in dmap("own")) if (Math.abs(t) > Math.abs(progress.own[k] ?: 0.0)) {
            if ((t > 0) != isOwn(k)) { n++; ownChangedInMerge = true }
            progress.own[k] = t
        }
        // 複習: the one answered last wins; 練習統計: the bigger count of each day (the same answers can be in both)
        if (from == 0) (obj["srs"] as? Map<String, Any?>)?.forEach { (k, v) ->
            val l = (v as? List<Any?>)?.mapNotNull { (it as? Number)?.toDouble() } ?: return@forEach
            val m = progress.srs[k]
            if (l.size >= 6 && l[5] > (if (m != null && m.size >= 6) m[5] else -1.0)) progress.srs[k] = l.toMutableList()
        }
        if (from == 0) (obj["log"] as? Map<String, Any?>)?.forEach { (d, v) ->
            val l = (v as? List<Any?>)?.mapNotNull { (it as? Number)?.toInt() } ?: return@forEach
            val m = progress.log[d] ?: emptyList<Int>()
            progress.log[d] = MutableList(maxOf(l.size, m.size)) { maxOf(l.getOrElse(it) { 0 }, m.getOrElse(it) { 0 }) }
        }
        for ((k, s) in status) {
            if (!isWord(k)) continue
            val theirs = added[k] ?: 0.0; val mine = progress.added[k] ?: -1.0
            if (theirs > mine || (progress.status[k] == null && theirs >= mine)) {
                if (progress.status[k] != s) n++
                progress.status[k] = s
                progress.added[k] = theirs
                if (s == 2) progress.streak[k] = maxOf(streak[k] ?: 0, progress.streak[k] ?: 0) else progress.streak.remove(k)
            } else if (s == 2 && progress.status[k] == 2 && theirs == mine) {
                val t = streak[k]
                if (t != null && t > (progress.streak[k] ?: 0)) progress.streak[k] = t
            }
        }
        return n
    }

    /** importing a backup a slice at a time, so a progress bar can show how far it is (0–1) */
    @Suppress("UNCHECKED_CAST")
    suspend fun importBackupWithProgress(text: String, report: (Float) -> Unit): String {
        report(0.02f)
        val obj = withContext(Dispatchers.Default) {
            try { JReader(text).any() as? Map<String, Any?> } catch (_: Exception) { null }
        } ?: return "讀不到這個檔案。"
        report(0.12f)
        if (obj["app"] != "fangfang-cards") return importBackup(text)
        val total = (obj["status"] as? Map<*, *>)?.size ?: 0
        var n = 0
        var from = 0
        val step = 1500
        do {
            n += mergeSlice(obj, from, from + step)
            from += step
            report(0.12f + 0.78f * (if (total == 0) 1f else minOf(1f, from.toFloat() / total)))
            kotlinx.coroutines.yield()
        } while (from < total)
        changed()
        if (ownChangedInMerge) applyOwn()
        report(0.95f)
        syncCharCards()
        save()
        report(1f)
        return "已匯入，更新了 $n 個詞。"
    }

    fun backupData(): String {
        val exported = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US)
            .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.format(java.util.Date())
        return JWriter.any(mapOf("app" to "fangfang-cards", "version" to 1, "exported" to exported,
            "status" to progress.status, "added" to progress.added, "streak" to progress.streak,
            "saved" to progress.saved, "own" to progress.own, "senses" to progress.senses,
            "week" to progress.week, "weekStart" to progress.weekStart, "srs" to progress.srs, "log" to progress.log), pretty = true)
    }

    @Suppress("UNCHECKED_CAST")
    fun importBackup(text: String): String {
        val obj = try { JReader(text).any() as? Map<String, Any?> } catch (_: Exception) { null } ?: return "讀不到這個檔案。"
        val app = obj["app"] as? String
        if (app == "fangfang-cards") {
            val n = mergeProgress(obj)
            save()
            return "已匯入，更新了 $n 個詞。"
        }
        val saved = obj["saved"] as? List<Any?>
        if (app == "fangfang" && saved != null) {
            var n = 0; var m = 0
            val t = now
            for (s in saved.filterIsInstance<String>()) {
                val k = s.split("\t").take(2).joinToString("\t")
                if (!isSaved(k)) { progress.saved[k] = t; m++ }
                if (byKey[k] == null || progress.status[k] == 2) continue
                progress.status[k] = 2; progress.added[k] = t; progress.streak[k] = 0
                n++
            }
            changed(); save()
            return "已把方方收藏的 $m 個詞加到「轉換 → 收藏」，$n 個詞加到「不熟」。"
        }
        return "這不是方方的備份檔。"
    }
}
