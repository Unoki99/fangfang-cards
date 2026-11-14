package com.unoki99.fangfang.engine

// MARK: - 日語: kana and rōmaji (the dictionary itself is ZhDict, read from ja.json like 華語 / 粵語 / 客語)

object JaKana {
    fun isHiragana(cp: Int) = cp in 0x3041..0x309F
    fun isKatakana(cp: Int) = cp in 0x30A0..0x30FF || cp in 0x31F0..0x31FF
    fun isKanji(cp: Int) = cp in 0x4E00..0x9FFF || cp in 0x3400..0x4DBF || cp == 0x3005 || cp in 0x20000..0x2FA1F
    fun isHiragana(s: String) = s.isNotEmpty() && isHiragana(s.firstCp())
    fun isKatakana(s: String) = s.isNotEmpty() && isKatakana(s.firstCp())
    fun isKanji(s: String) = s.isNotEmpty() && s.cps().any { isKanji(it.firstCp()) }

    /** katakana → hiragana (ー stays) */
    fun hiragana(s: String): String {
        val b = StringBuilder(s.length)
        for (c in s) b.append(if (c.code in 0x30A1..0x30F6) (c.code - 0x60).toChar() else c)
        return b.toString()
    }
    fun katakana(s: String): String {
        val b = StringBuilder(s.length)
        for (c in s) b.append(if (c.code in 0x3041..0x3096) (c.code + 0x60).toChar() else c)
        return b.toString()
    }

    private val table: List<Pair<String, String>> = run {
        val t = mutableListOf(
            "kya" to "きゃ", "kyu" to "きゅ", "kyo" to "きょ", "sha" to "しゃ", "shu" to "しゅ", "sho" to "しょ", "she" to "しぇ",
            "cha" to "ちゃ", "chu" to "ちゅ", "cho" to "ちょ", "che" to "ちぇ", "nya" to "にゃ", "nyu" to "にゅ", "nyo" to "にょ",
            "hya" to "ひゃ", "hyu" to "ひゅ", "hyo" to "ひょ", "mya" to "みゃ", "myu" to "みゅ", "myo" to "みょ",
            "rya" to "りゃ", "ryu" to "りゅ", "ryo" to "りょ", "gya" to "ぎゃ", "gyu" to "ぎゅ", "gyo" to "ぎょ",
            "ja" to "じゃ", "ju" to "じゅ", "jo" to "じょ", "je" to "じぇ", "bya" to "びゃ", "byu" to "びゅ", "byo" to "びょ",
            "pya" to "ぴゃ", "pyu" to "ぴゅ", "pyo" to "ぴょ", "tsu" to "つ", "shi" to "し", "chi" to "ち",
            "sya" to "しゃ", "syu" to "しゅ", "syo" to "しょ", "tya" to "ちゃ", "tyu" to "ちゅ", "tyo" to "ちょ",
            "jya" to "じゃ", "jyu" to "じゅ", "jyo" to "じょ", "dzu" to "づ", "fa" to "ふぁ", "fi" to "ふぃ", "fe" to "ふぇ", "fo" to "ふぉ",
            "ti" to "てぃ", "di" to "でぃ", "tu" to "つ", "si" to "し", "zi" to "じ", "hu" to "ふ", "fu" to "ふ", "ji" to "じ",
            "wo" to "を", "wa" to "わ", "ya" to "や", "yu" to "ゆ", "yo" to "よ", "nn" to "ん", "n'" to "ん", "-" to "ー",
            "a" to "あ", "i" to "い", "u" to "う", "e" to "え", "o" to "お",
        )
        val rows = listOf("k" to "かきくけこ", "g" to "がぎぐげご", "s" to "さ_すせそ", "z" to "ざ_ずぜぞ",
            "t" to "た__てと", "d" to "だぢづでど", "n" to "なにぬねの", "h" to "はひ_へほ",
            "b" to "ばびぶべぼ", "p" to "ぱぴぷぺぽ", "m" to "まみむめも", "r" to "らりるれろ")
        for ((c, ks) in rows) for ((v, k) in listOf("a", "i", "u", "e", "o").zip(ks.toList())) if (k != '_') t.add(c + v to k.toString())
        t.sortedByDescending { it.first.length }
    }

    /** rōmaji (Hepburn, or the keyboard ways) → hiragana; null when it isn't rōmaji */
    fun fromRomaji(s: String): String? {
        val cs = s.lowercase()
        val out = StringBuilder()
        var i = 0
        while (i < cs.length) {
            val c = cs[i]
            if (c == ' ') { i++; continue }
            // a doubled consonant: っ
            if (i + 1 < cs.length && c == cs[i + 1] && c.isLetter() && c !in "aeioun") { out.append("っ"); i++; continue }
            if (c == 't' && i + 2 < cs.length && cs[i + 1] == 'c' && cs[i + 2] == 'h') { out.append("っ"); i++; continue }
            var hit = false
            for ((r, k) in table) if (cs.startsWith(r, i)) { out.append(k); i += r.length; hit = true; break }
            if (hit) continue
            // n before a consonant (or at the end)
            if (c == 'n') { out.append("ん"); i++; continue }
            return null
        }
        return if (out.isEmpty()) null else out.toString()
    }

    private val back: Map<String, String> = run {
        val m = HashMap<String, String>()
        val skip = setOf("si", "zi", "tu", "hu", "sya", "syu", "syo", "tya", "tyu", "tyo", "jya", "jyu", "jyo", "nn", "n'", "dzu")
        for ((r, k) in table) if (!m.containsKey(k) && r !in skip) m[k] = r
        m["ん"] = "n"; m["を"] = "o"; m["づ"] = "zu"; m["ぢ"] = "ji"
        m
    }

    /** hiragana or katakana → rōmaji (Hepburn) */
    fun romaji(s: String): String {
        val cs = hiragana(s)
        val out = StringBuilder()
        var i = 0
        var double = false
        var afterN = false
        while (i < cs.length) {
            if (cs[i] == 'っ') { double = true; i++; continue }
            val isN = cs[i] == 'ん'
            var p: String
            val two = if (i + 1 < cs.length) back[cs.substring(i, i + 2)] else null
            val one = back[cs[i].toString()]
            if (two != null) { p = two; i += 2 }
            else if (one != null) { p = one; i++ }
            else if (cs[i] == 'ー' && out.isNotEmpty()) { p = out.last().toString(); i++ }
            else { p = cs[i].toString(); i++ }
            if (double && p.isNotEmpty()) { p = (if (p.startsWith("ch")) "t" else p[0].toString()) + p; double = false }
            // (ん before a vowel or y: n')
            if (afterN && p.isNotEmpty() && p[0] in "aiueoy") out.append("'")
            out.append(p)
            afterN = isN
        }
        return out.toString()
    }
}
