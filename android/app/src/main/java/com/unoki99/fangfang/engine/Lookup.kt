package com.unoki99.fangfang.engine

class PlaceRow(val han: String, val codes: String, val places: List<Int>)
class PlaceGroup(val zh: String, val rows: List<PlaceRow>)

class LookupResult {
    var exact: List<String> = emptyList()
    var taigi: List<String> = emptyList()       // words for a 台語 spelling
    var contains: List<String> = emptyList()    // 台語 words that contain the 漢字
    var pattern: List<String> = emptyList()     // 台語 words matching a * / ? pattern
    var patternZh: List<String> = emptyList()   // 台語 words for 華語 words matching it
    var isPattern = false
    var gloss: List<String> = emptyList()
    var defs: List<String> = emptyList()
    var places: List<PlaceGroup> = emptyList()
    var tones: List<String> = emptyList()
    var toneNote: String? = null
    var sentences: List<SentenceHit> = emptyList()
    var sentenceWords: List<String> = emptyList()
    /** several words searched at once (陰謀論 → 陰謀, 論; or 陰謀 論): each word and what it finds */
    var parts: List<String> = emptyList()
    var partResults: List<LookupResult> = emptyList()
    /** words whose English (Wiktionary) has the word: added after the rest, which stay as they are */
    var english: List<String> = emptyList()
    val empty: Boolean
        get() = english.isEmpty() && parts.isEmpty() && tones.isEmpty() && taigi.isEmpty() && contains.isEmpty() && pattern.isEmpty() && patternZh.isEmpty() &&
            exact.isEmpty() && gloss.isEmpty() && defs.isEmpty() && places.isEmpty()
}

object Lookup {
    private val rankCmp = { d: Dict -> compareBy<String>({ Dict.hanOf(it).cpCount }, { -d.score(Dict.hanOf(it), Dict.codesOf(it)) }) }

    /** * = one or more characters, ? = exactly one */
    fun wildcard(d: Dict, q: String): LookupResult {
        val r = LookupResult()
        r.isPattern = true
        val pat = StringBuilder("^")
        for (ch in q.cps()) {
            when (ch) {
                "*", "＊" -> pat.append(".+")
                "?", "？" -> pat.append(".")
                else -> pat.append(Regex.escape(ch))
            }
        }
        pat.append("$")
        val re = try { Regex(pat.toString()) } catch (_: Exception) { return r }
        val keys = ArrayList<String>()
        for ((h, cs) in d.hanMap.entries.toList()) {
            if (!re.matches(h)) continue
            for (c in cs.toList()) { val k = h + "\t" + c; if (d.baseKeys.contains(k) || d.isUser(k)) keys.add(k) }
        }
        r.pattern = keys.sortedWith(rankCmp(d)).take(300)
        val seen = r.pattern.toSet()
        val zh = HashSet<String>()
        for ((t, ks) in d.termIndex) if (re.matches(t)) zh.addAll(ks.filter { !seen.contains(it) })
        r.patternZh = zh.sortedWith(rankCmp(d)).take(100)
        return r
    }

    private val sepRe = Regex("[ \\-‑　]+")

    /** words for a 台語 spelling: 皓羅, 台羅, 白話字 (with or without tones) or 方音 */
    fun taigi(d: Dict, q: String, prefs: KeyValue): List<String> {
        val keys = ArrayList<String>(); val seen = HashSet<String>()
        fun add(h: String, codes: List<String>) {
            val k = d.keyOf(Opt(h, codes)) ?: return
            if (d.raw.defs.m[k] == null && !d.baseKeys.contains(k) && !d.isUser(k)) return
            if (seen.add(k)) keys.add(k)
        }
        if (q.codePoints().anyMatch { ConvertEngine.isZy(it) }) {
            val res = ConvertEngine(d, prefs).convert(q)
            for (it in res.items) if (it.isWord) for (o in it.opts) { if (o.han != null && o.codes != null) add(o.han, o.codes) }
        } else {
            val toks = Dict.nfc(q).split(sepRe).filter { it.isNotEmpty() }
            val lists = ArrayList<List<String>>()
            for (t in toks) {
                val c = LinkedHashSet<String>()
                d.latRev[t.lowercase()]?.let { c.addAll(it) }
                ConvertEngine.romKey(t)?.let { rk -> d.tlRev[rk]?.let { c.addAll(it) }; d.pojRev[rk]?.let { c.addAll(it) } }
                val toned = Dict.nfd(t).codePoints().anyMatch { (it in 0x300..0x36F && it != 0x358) || it in '1'.code..'9'.code }
                if (!toned) d.plainRev[Dict.plainKey(t)]?.let { c.addAll(it) }
                if (c.isEmpty()) return emptyList()
                lists.add(c.toList())
            }
            fun combos(ls: List<List<String>>): List<List<String>> {
                var acc: List<List<String>> = listOf(emptyList())
                for (l in ls) {
                    val next = ArrayList<List<String>>()
                    outer@ for (a in acc) for (x in l) { next.add(a + x); if (next.size >= 400) break@outer }
                    acc = next
                }
                return acc
            }
            for (cs in combos(lists)) for (h in d.codeMap[cs.joinToString(" ")]?.toList() ?: emptyList()) add(h, cs)
            if (keys.isEmpty() && lists.size > 1) {
                var i = 0
                while (i < lists.size) {
                    var step = 1
                    for (L in (lists.size - i) downTo 1) {
                        var hit = false
                        for (cs in combos(lists.subList(i, i + L))) {
                            for (h in d.codeMap[cs.joinToString(" ")]?.toList() ?: emptyList()) { add(h, cs); hit = true }
                        }
                        if (hit) { step = L; break }
                    }
                    i += step
                }
                return keys
            }
        }
        return keys.sortedByDescending { d.score(Dict.hanOf(it), Dict.codesOf(it)) }.take(120)
    }

    private val toneRe = Regex("^[1-9](?:[-\\s]?[1-9]){0,7}$")

    fun run(d: Dict, q0: String, place: Int, prefs: KeyValue, split: Boolean = true): LookupResult {
        val q = q0.trim()
        val r = LookupResult()
        if (q.isEmpty()) return r
        if (q.any { "*＊?？".contains(it) }) return wildcard(d, q)
        if (toneRe.matches(q)) {
            val ts = q.filter { it.isDigit() }.map { it - '0' }
            r.tones = toneSearch(d, ts, place)
            if (r.tones.isEmpty() && ts.contains(6)) {
                r.toneNote = if (place < 0) "通行讀音沒有第 6 聲。先在上方選一個有第 6 聲的腔口（例如鹿港），再查一次。"
                else "這個腔口找不到這個聲調組合的詞。第 6 聲只有部分腔口有（例如鹿港）。"
            }
            return r
        }
        if (q.codePoints().anyMatch { ConvertEngine.isZy(it) || ConvertEngine.isLatinLetter(it) }) {
            r.taigi = taigi(d, q, prefs)
            addSentences(d, r, r.taigi)
            // (letters: maybe English too; a section of its own, after the 台語 results)
            if (q.codePoints().noneMatch { ConvertEngine.isZy(it) }) {
                val seen = r.taigi.toHashSet()
                r.english = TwEnglish.search(q).filter { it !in seen }
            }
            return r
        }
        val seen = HashSet<String>()
        val exact = ArrayList<String>()
        for (k in d.termIndex[q] ?: emptyList<String>()) if (seen.add(k)) exact.add(k)
        for (c in d.hanMap[q]?.toList() ?: emptyList()) {
            val k = q + "\t" + c
            val kk = if (d.baseKeys.contains(k)) k else (d.keyOf(Opt(q, c.split(' '))) ?: k)
            if (seen.add(kk)) exact.add(kk)
        }
        r.exact = exact
        if (q.codePoints().allMatch { ConvertEngine.isHan(it) }) {
            val c = ArrayList<String>()
            for ((h, cs) in d.hanMap.entries.toList()) {
                if (h == q || !h.contains(q)) continue
                for (code in cs.toList()) { val k = h + "\t" + code; if ((d.baseKeys.contains(k) || d.isUser(k)) && !seen.contains(k)) c.add(k) }
            }
            r.contains = c.sortedWith(rankCmp(d)).take(80)
            seen.addAll(r.contains)
        }
        fun rank(k: String) = d.score(Dict.hanOf(k), Dict.codesOf(k)) - 0.15 * Dict.hanOf(k).cpCount
        val g = ArrayList<String>()
        for ((k, arr) in d.gl) if (!seen.contains(k) && arr.any { it.t != q && it.t.contains(q) }) g.add(k)
        r.gloss = g.sortedByDescending { rank(it) }.take(60)
        seen.addAll(r.gloss)
        val m = ArrayList<String>()
        for ((k, i) in d.raw.defs.m) if (!seen.contains(k) && d.raw.defs.t[i].contains(q)) m.add(k)
        r.defs = m.sortedByDescending { rank(it) }.take(60)
        var hits = d.raw.cmp.filter { it.zh == q }
        if (hits.size < 6) hits = hits + d.raw.cmp.filter { it.zh != q && it.zh.contains(q) }.take(6 - hits.size)
        val places = ArrayList<PlaceGroup>()
        for (e in hits.take(6)) {
            val order = ArrayList<String>(); val by = HashMap<String, MutableList<Int>>()
            for (row in e.rows) {
                val k = row.han + "\t" + row.codes
                if (by[k] == null) order.add(k)
                by.getOrPut(k) { ArrayList() }.add(row.place)
            }
            places.add(PlaceGroup(e.zh, order.map { PlaceRow(Dict.hanOf(it), Dict.codesOf(it), by[it]!!) }))
        }
        r.places = places
        addSentences(d, r, r.exact)
        // not one word: the words it's made of, each searched on its own
        if (split && r.exact.isEmpty()) Segmenter.parts(q) { d.termIndex.containsKey(it) || d.hanMap.containsKey(it) }?.let { ps ->
            r.parts = ps
            r.partResults = ps.map { run(d, it, place, prefs, false) }
        }
        return r
    }

    /** words whose syllables have these tones, in the chosen place's readings */
    fun toneSearch(d: Dict, tones: List<Int>, place: Int = -1): List<String> {
        val out = ArrayList<Pair<String, Double>>()
        for (w in d.raw.words) {
            if (w.size != 2) continue
            val cs = (if (place >= 0) d.codesFor(w[0] + "\t" + w[1], place) else w[1]).split(' ').filter { it.isNotEmpty() }
            if (cs.size != tones.size || w[0].cpCount != tones.size) continue
            var ok = true
            for (i in cs.indices) { val l = cs[i].lastOrNull(); if (l == null || l - '0' != tones[i]) { ok = false; break } }
            if (ok) out.add(Pair(w[0] + "\t" + w[1], d.score(w[0], w[1])))
        }
        return out.sortedByDescending { it.second }.take(1000).map { it.first }
    }

    fun addSentences(d: Dict, r: LookupResult, keys: List<String>) {
        val ks = ArrayList<String>()
        for (k in keys) if (!ks.contains(k)) ks.add(k)
        val top = ks.take(6)
        r.sentences = d.sentences(top)
        val hs = ArrayList<String>()
        for (k in top) if (r.sentences.any { it.word == k }) { val h = Dict.hanOf(k); if (!hs.contains(h)) hs.add(h) }
        r.sentenceWords = hs
    }

    /** 各地讀音: only words that are exactly what was typed */
    fun exact(d: Dict, q0: String, prefs: KeyValue): List<String> {
        val q = q0.trim()
        if (q.isEmpty()) return emptyList()
        val out = ArrayList<String>()
        fun add(k: String?) { if (k != null && !out.contains(k) && (d.raw.defs.m[k] != null || d.baseKeys.contains(k))) out.add(k) }
        if (q.codePoints().allMatch { ConvertEngine.isHan(it) }) {
            for (c in d.hanMap[q]?.toList() ?: emptyList()) add(d.keyOf(Opt(q, c.split(' '))))
            return out
        }
        val typed = q.split(sepRe).filter { it.isNotEmpty() }.size
        val zy = q.codePoints().anyMatch { ConvertEngine.isZy(it) }
        for (k in taigi(d, q, prefs)) if (zy || Dict.codesOf(k).split(' ').size == typed) add(k)
        if (zy) {
            val res = ConvertEngine(d, prefs).convert(q)
            if (res.items.count { it.isWord } != 1) return emptyList()
        }
        return out
    }
}

/** words the dictionary says come from Japanese (源自日語「…」, 借自日語…), the more common first, with the Japanese word */
fun Dict.japaneseWords(): List<Pair<String, String>> {
    val re = Regex("(?:源自|借自|來自|譯自|出自)日語|日語原作|日語外來語")
    val src = Regex("日語(?:原作)?「([^」]+)」")
    val out = ArrayList<Triple<String, String, Double>>()
    for ((k, i) in raw.defs.m) {
        val t = raw.defs.t[i]
        if (!re.containsMatchIn(t)) continue
        out.add(Triple(k, src.find(t)?.groupValues?.get(1) ?: "", score(Dict.hanOf(k), Dict.codesOf(k))))
    }
    return out.sortedByDescending { it.third }.map { it.first to it.second }
}
