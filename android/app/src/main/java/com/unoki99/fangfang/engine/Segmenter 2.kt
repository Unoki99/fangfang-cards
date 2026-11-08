package com.unoki99.fangfang.engine

// Searching several words at once: 陰謀論 (not a word) → 陰謀 + 論, or typed with spaces: 陰謀 論.
object Segmenter {
    /** the words a search is made of, or null when it's one search:
     *  - 漢字 typed with spaces between them (羅馬字 with spaces is one word: tsiah png)
     *  - 漢字 that aren't a word, split into the longest words from the left (isWord says what's a word) */
    fun parts(q0: String, maxLen: Int = 8, isWord: (String) -> Boolean): List<String>? {
        val q = q0.trim()
        if (q.isEmpty() || q.any { it in "*＊?？" }) return null
        val cps = q.codePoints().toArray()
        val latin = cps.any { ConvertEngine.isLatinLetter(it) || ConvertEngine.isZy(it) || it in '0'.code..'9'.code }
        val spaced = q.split(' ', '　', ',', '，', '、').filter { it.isNotEmpty() }
        if (spaced.size > 1) {
            if (latin) return null
            val out = spaced.distinct()
            return if (out.size > 1) out.take(12) else null
        }
        if (latin || !cps.all { ConvertEngine.isHan(it) } || cps.size < 2 || isWord(q)) return null
        val cs = q.cps()
        val out = ArrayList<String>()
        var i = 0
        while (i < cs.size) {
            var step = 1
            var l = minOf(maxLen, cs.size - i)
            while (l >= 2) {
                if (isWord(cs.subList(i, i + l).joinToString(""))) { step = l; break }
                l--
            }
            val w = cs.subList(i, i + step).joinToString("")
            if (w !in out) out.add(w)
            i += step
        }
        return if (out.size > 1) out.take(12) else null
    }
}
