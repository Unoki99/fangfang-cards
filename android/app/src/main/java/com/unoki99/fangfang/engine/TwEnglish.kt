package com.unoki99.fangfang.engine

// 台語 words' English (Wiktionary). tw_en.json (tools/build_tw_english.py): English meanings for the 教育部 dictionary's
// words, from the Wiktionary pages with the same 漢字 and the same Hokkien reading. A file of its own: the
// dictionary's data and its search results stay as they are; the English is only added (a line on a word's page,
// a section in the search).

object TwEnglish {
    /** reads the file (set by the app; null when it isn't there) */
    @Volatile var source: (() -> String?)? = null
    @Volatile private var table: Map<String, String>? = null
    /** words with meanings Wiktionary marks as Hokkien's own (they come first among equals) */
    @Volatile private var hokkien: Set<String> = emptySet()

    private val all: Map<String, String>
        get() {
            table?.let { return it }
            synchronized(this) {
                table?.let { return it }
                val t = HashMap<String, String>(); val h = HashSet<String>()
                try {
                    val text = source?.invoke()
                    if (text != null) {
                        val j = JReader(text)
                        j.obj { k ->
                            if (k == "e") j.obj { key ->
                                val v = j.nextString()
                                if (v.startsWith("*")) { t[key] = v.substring(1); h.add(key) } else t[key] = v
                            } else j.skip()
                        }
                    }
                } catch (_: Exception) {}
                hokkien = h; table = t
                return t
            }
        }

    val available: Boolean get() = all.isNotEmpty()

    /** a word's English meanings, one each */
    fun meanings(key: String): List<String> = all[key]?.split("; ")?.filter { it.isNotEmpty() } ?: emptyList()

    /** the words whose English has the word(s): a meaning that is just the word first ("eat", "to eat"), then meanings
     *  that start with it, then the rest; "to park" (a verb) before "park" (a noun) and the other way round; the closer
     *  the meaning is to the word, the higher ("quality" before "good quality" before a long description that has
     *  "quality" somewhere in it); among equals, Hokkien's own meanings first, then the shorter words */
    fun search(q0: String, limit: Int = 200): List<String> {
        val q = q0.lowercase().trim()
        if (!(q.length >= 2 || q == "i" || q == "a") || q.any { it.code > 127 }) return emptyList()
        val t = all
        val wantVerb = q.startsWith("to ")
        val bare = if (wantVerb) q.drop(3) else q
        val inWord = Regex("[^a-z]" + Regex.escape(bare) + "[^a-z]")
        val notes = Regex("\\([^()]*\\)")
        val qWords = bare.split(" ").count { it.isNotEmpty() }
        class Hit(val tier: Int, val later: Int, val hok: Int, val len: Int, val k: String)
        val hits = ArrayList<Hit>()
        for ((k, en0) in t) {
            val en = en0.lowercase()
            if (!en.contains(bare)) continue
            var best = 99; var bestPos = 1
            for ((pos, g0) in en.split("; ").withIndex()) {
                var g = g0
                var noted = false
                while (true) { val m = notes.find(g) ?: break; g = g.removeRange(m.range); noted = true }
                // (several meanings in one: "to eat, to have a meal")
                for (part in g.split(",")) {
                    val p = part.trim()
                    val isVerb = p.startsWith("to ")
                    val v = if (isVerb) p.drop(3) else p
                    var tier = 9
                    if (v == bare) tier = 0
                    else if (v.startsWith("$bare ")) tier = 2
                    else if (inWord.containsMatchIn(" $v ")) tier = 4
                    if (tier < 9 && isVerb != wantVerb && (wantVerb || tier == 0)) tier += if (wantVerb) 2 else 1
                    if (tier < 9 && noted) tier += 1
                    if (tier >= 9) continue
                    // how much more the meaning says than the word (each word more: a little lower; a long
                    // description that only mentions it: at the end)
                    val extra = maxOf(0, v.split(" ").count { it.isNotEmpty() } - qWords)
                    tier = tier * 10 + minOf(extra, 9) + (if (extra > 4) 20 else 0)
                    val p0 = if (pos == 0) 0 else 1
                    if (tier < best || (tier == best && p0 < bestPos)) { best = tier; bestPos = p0 }
                }
            }
            if (best < 90) hits.add(Hit(best, bestPos, if (k in hokkien) 0 else 1, k.substringBefore('\t').codePointCount(0, k.substringBefore('\t').length), k))
        }
        hits.sortWith(compareBy({ it.tier }, { it.later }, { it.hok }, { it.len }, { it.k }))
        return hits.take(limit).map { it.k }
    }
}

/** English meanings found by a search: the ones with the searched word(s) first ("to park": "to park (a car)" before
 *  "to anchor (a vessel)"); the rest keep their order */
object EnglishMatch {
    fun first(list: List<String>, q0: String): List<String> {
        var q = q0.lowercase().trim()
        if (q.startsWith("to ")) q = q.drop(3)
        if (q.isEmpty()) return list
        val pat = Regex("(^|[^a-z])" + Regex.escape(q) + "($|[^a-z])")
        val hit = list.filter { pat.containsMatchIn(it.lowercase()) }
        return hit + list.filter { it !in hit }
    }

    fun unique(list: List<String>): List<String> {
        val seen = HashSet<String>()
        return list.filter { it.isNotEmpty() && seen.add(it.lowercase()) }
    }
}
