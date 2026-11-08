package com.unoki99.fangfang.engine

// Port of the 方方 website converter: reads 漢字 / 皓羅 / 方音 / 台羅 / 白話字 (mixed),
// splits it into dictionary words and writes it in the three scripts.

data class ConvItem(
    val opts: List<Opt> = emptyList(),
    var sel: Int = 0,
    val src: String = "",              // han / zy / lat / tl / poj
    val raw: String? = null,           // punctuation or text that isn't a word
    val space: Boolean = false,
    val newline: Boolean = false,
    val unknownWord: Boolean = false,  // Latin text we couldn't read
    /** how likely the chosen reading is right (0–1); null = not guessed */
    var likely: Double? = null,
) {
    val unsure: Boolean get() = (likely ?: 1.0) < 0.82
    val isWord: Boolean get() = raw == null && !space && !newline
    val current: Opt get() = opts[minOf(sel, opts.size - 1)]
}

enum class LatinMode(val raw: String) { AUTO("auto"), LAT("lat"), TL("tl"), POJ("poj");
    companion object { fun of(s: String?) = entries.firstOrNull { it.raw == s } ?: AUTO }
}

class ConvResult(
    val items: MutableList<ConvItem> = ArrayList(),
    val seen: MutableMap<String, Int> = HashMap(),
    var anyLatin: Boolean = false,
    var autoLatin: String = "lat",
)

private sealed class Atom {
    class Han(val c: String) : Atom()
    class Syl(val codes: List<String>, val from: String) : Atom()
    class Latin(val w: String) : Atom()
    object Newline : Atom()
    object Space : Atom()
    class Raw(val t: String) : Atom()
}

/** one piece of the converter output: its text, and which item it is (null = punctuation, -1 = unreadable) */
class OutPiece(val text: String, val item: Int?)

class ConvertEngine(val d: Dict, private val prefs: KeyValue) {
    var latinMode: LatinMode = LatinMode.of(prefs.getString("ff-latin"))
    private val mem: HashMap<String, String> = HashMap(
        try { prefs.getString("ff-picks")?.let { JReader(it).strMap() } ?: emptyMap() } catch (_: Exception) { emptyMap() })

    companion object {
        fun isHan(v: Int): Boolean =
            v in 0x3400..0x4DBF || v in 0x4E00..0x9FFF || v in 0xF900..0xFAFF || v in 0x20000..0x3134F || v == 0x3007

        private val zyExtra = setOf(0x02C9, 0x02CA, 0x02CB, 0x02EA, 0x02EB, 0x02D9, 0xFF0E, 0xFF4E, 0x0307, 0xA715, 0xA718)
        fun isZy(v: Int) = v in 0x3100..0x312F || v in 0x31A0..0x31BF || zyExtra.contains(v)
        fun isLatinLetter(v: Int) = v in 0x41..0x5A || v in 0x61..0x7A || (v in 0xC0..0x24F && v != 0xD7 && v != 0xF7) || v in 0x1E00..0x1EFF
        fun isMark(v: Int) = v in 0x300..0x36F || v == 0x207F

        private val oLike = "òóôōŏőǒȯöÒÓÔŌǑ".map { it.code }.toSet()
        /** is position j right after an o (with only tone marks between)? */
        fun afterO(u: IntArray, j: Int): Boolean {
            var k = j - 1
            while (k >= 0 && u[k] in 0x300..0x36F && u[k] != 0x0358) k--
            if (k < 0) return false
            return u[k] == 'o'.code || u[k] == 'O'.code || oLike.contains(u[k])
        }

        private val nas = mapOf("ㄧ" to "ㆪ", "ㄨ" to "ㆫ", "ㄚ" to "ㆩ", "ㆦ" to "ㆧ", "ㆤ" to "ㆥ", "ㄞ" to "ㆮ", "ㄠ" to "ㆯ")
        private val stops = setOf("ㆴ", "ㆵ", "ㆻ", "ㆷ")
        private fun normZy(s: String): List<String> {
            val a = s.cps()
            val out = ArrayList<String>()
            var i = 0
            while (i < a.size) {
                val c = a[i]; val nxt = if (i + 1 < a.size) a[i + 1] else ""
                if (stops.contains(c) && (nxt == "˙" || nxt == "·")) { out.add(c); out.add("̇"); i += 2; continue }
                if (stops.contains(c) && nxt == "．") { out.add(c); i += 2; continue }
                if (c == "ㆡ" && (nxt == "ㄧ" || nxt == "ㆪ")) { out.add("ㆢ"); i += 1; continue }
                val n = nas[c]
                if (n != null && (nxt == c || nxt == "ｎ")) { out.add(n); i += 2; continue }
                out.add(c); i++
            }
            var t = out.joinToString("")
            for ((x, y) in listOf("ㄚㆬ" to "ㆰ", "ㆦㆬ" to "ㆱ", "ㄚㄣ" to "ㄢ", "ㄚㆭ" to "ㄤ", "ㆦㆭ" to "ㆲ", "ㄜㆭ" to "ㄥ")) t = t.replace(x, y)
            return t.cps()
        }

        private val toneMark = mapOf(0x301 to "2", 0x300 to "3", 0x302 to "5", 0x30C to "6", 0x304 to "7", 0x30D to "8", 0x30B to "9")
        /** 白話字 o͘ (also typed o·): → "oo" */
        val pojDots = setOf(0x0358, 0x00B7, 0x0387, 0x2022, 0x22C5, 0x30FB, 0xFF65, 0x2027)

        fun pojOO(s: String): String {
            val out = StringBuilder()
            val marks = StringBuilder()
            var lastO = false
            var i = 0
            while (i < s.length) {
                val u = s.codePointAt(i); i += Character.charCount(u)
                if (pojDots.contains(u)) {
                    if (lastO) { out.append('o'); lastO = false }
                    continue
                }
                if (u in 0x300..0x36F) { marks.appendCodePoint(u); continue }
                out.append(marks); marks.setLength(0)
                out.appendCodePoint(u)
                lastO = u == 'o'.code || u == 'O'.code
            }
            out.append(marks)
            return out.toString()
        }

        fun romKey(word: String): String? {
            val s0 = pojOO(Dict.nfd(word).lowercase()).replace("ⁿ", "nn")
            var tone = ""
            val letters = StringBuilder()
            var i = 0
            while (i < s0.length) {
                val u = s0.codePointAt(i); i += Character.charCount(u)
                if (u in 0x300..0x36F) { toneMark[u]?.let { tone = it } } else letters.appendCodePoint(u)
            }
            var s = letters.toString()
            if (s.isNotEmpty()) {
                val last = s.last()
                if (last in '1'..'9') { tone = last.toString(); s = s.dropLast(1) }
            }
            if (s.isEmpty() || !s.all { it in 'a'..'z' }) return null
            if (tone.isEmpty()) tone = if ("ptkh".contains(s.last())) "4" else "1"
            return s + tone
        }

        val toASCII = mapOf("，" to ",", "。" to ".", "！" to "!", "？" to "?", "；" to ";", "：" to ":", "、" to ",", "「" to "“", "」" to "”", "『" to "‘", "』" to "’", "（" to "(", "）" to ")")
        val toFull = mapOf("," to "，", "." to "。", "!" to "！", "?" to "？", ";" to "；", ":" to "：", "(" to "（", ")" to "）")
        val openers = setOf("“", "‘", "(", "（", "「", "『", "[")

        fun isPunct(t: String): Boolean {
            if (t.isEmpty() || t.cpCount != 1) return false
            return when (Character.getType(t.codePointAt(0)).toByte()) {
                Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION, Character.END_PUNCTUATION,
                Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION, Character.OTHER_PUNCTUATION,
                Character.MATH_SYMBOL, Character.CURRENCY_SYMBOL, Character.MODIFIER_SYMBOL, Character.OTHER_SYMBOL -> true
                else -> false
            }
        }

        /** share of the evidence → how often such a guess was right in the example sentences */
        fun likely(share: Double): Double = when {
            share < 0.5 -> 0.37
            share < 0.55 -> 0.65
            share < 0.6 -> 0.76
            share < 0.7 -> 0.81
            share < 0.75 -> 0.88
            share < 0.8 -> 0.93
            share < 0.9 -> 0.96
            share < 0.95 -> 0.98
            else -> 0.99
        }
    }

    private fun parseZy(raw: String): List<Atom> {
        val s = normZy(raw); val n = s.size
        class Step(val cost: Double, val from: Int, val atom: Atom?)
        val best = arrayOfNulls<Step>(n + 1)
        best[0] = Step(0.0, 0, null)
        fun relax(j: Int, cost: Double, from: Int, atom: Atom) {
            val b = best[j]
            if (b == null || cost < b.cost) best[j] = Step(cost, from, atom)
        }
        for (i in 0 until n) {
            val b = best[i] ?: continue
            for (L in 1..minOf(d.maxZy, n - i)) {
                val k = s.subList(i, i + L).joinToString("")
                val c = d.zyRev[k]
                if (c != null) relax(i + L, b.cost + 1, i, Atom.Syl(c, "zy"))
                else d.zyRev0[k]?.let { relax(i + L, b.cost + 1.4, i, Atom.Syl(it, "zy")) }
            }
            relax(i + 1, b.cost + 10, i, Atom.Raw(s[i]))
        }
        val out = ArrayList<Atom>()
        var j = n
        while (j > 0) { val b = best[j] ?: break; b.atom?.let { out.add(it) }; j = b.from }
        out.reverse()
        val merged = ArrayList<Atom>()
        for (a in out) {
            val last = merged.lastOrNull()
            if (a is Atom.Raw && last is Atom.Raw) merged[merged.size - 1] = Atom.Raw(last.t + a.t) else merged.add(a)
        }
        return merged
    }

    private fun look(sys: String, w: String, rk: String?): List<String>? = when (sys) {
        "lat" -> d.latRev[w.lowercase()]
        "tl" -> if (rk != null && !w.contains("ⁿ") && !w.codePoints().anyMatch { pojDots.contains(it) }) d.tlRev[rk] else null
        else -> rk?.let { d.pojRev[it] }
    }

    private fun atomize(text: String, res: ConvResult): List<Atom> {
        val u = Dict.nfc(text).codePoints().toArray()
        val atoms = ArrayList<Atom>()
        var i = 0
        fun str(a: Int, b: Int): String { val sb = StringBuilder(); for (k in a until b) sb.appendCodePoint(u[k]); return sb.toString() }
        while (i < u.size) {
            val v = u[i]
            if (isHan(v)) { atoms.add(Atom.Han(str(i, i + 1))); i++; continue }
            if (isZy(v) && v != 0x0307) {
                var j = i; while (j < u.size && isZy(u[j])) j++
                atoms.addAll(parseZy(str(i, j))); i = j; continue
            }
            if (isLatinLetter(v) || isMark(v)) {
                var j = i
                while (j < u.size && (isLatinLetter(u[j]) || isMark(u[j]) || (pojDots.contains(u[j]) && afterO(u, j)))) j++
                if (j < u.size && u[j] in 0x31..0x39) j++
                atoms.add(Atom.Latin(str(i, j))); i = j; continue
            }
            if (v == 0x0A) { atoms.add(Atom.Newline); i++; continue }
            if (v == 0x20 || v == 0x09 || v == 0x3000) {
                var j = i; while (j < u.size && (u[j] == 0x20 || u[j] == 0x09 || u[j] == 0x3000)) j++
                atoms.add(Atom.Space); i = j; continue
            }
            if (v == 0x2D || v == 0x2011) { atoms.add(Atom.Space); i++; continue }
            atoms.add(Atom.Raw(str(i, i + 1))); i++
        }
        val votes = hashMapOf("lat" to 0.0, "tl" to 0.0, "poj" to 0.0)
        for (a in atoms) {
            if (a is Atom.Latin) {
                res.anyLatin = true
                val rk = romKey(a.w)
                val hits = listOf("lat", "tl", "poj").filter { look(it, a.w, rk) != null }
                for (k in hits) votes[k] = votes[k]!! + 1.0 / hits.size
            }
        }
        var auto = "lat"
        for (k in listOf("tl", "poj")) if (votes[k]!! > votes[auto]!! + 1e-6) auto = k
        res.autoLatin = auto
        val used = if (latinMode == LatinMode.AUTO) auto else latinMode.raw
        val order = listOf(used) + listOf("lat", "tl", "poj").filter { it != used }
        return atoms.map { a ->
            if (a !is Atom.Latin) a else {
                val rk = romKey(a.w)
                var r: Atom = Atom.Raw("\u0001" + a.w)
                for (k in order) { val c = look(k, a.w, rk); if (c != null) { r = Atom.Syl(c, k); break } }
                r
            }
        }
    }

    private fun segHan(chars: List<String>): List<ConvItem> {
        val n = chars.size
        class Step(val cost: Double, val from: Int, val w: String, val known: Boolean)
        val best = arrayOfNulls<Step>(n + 1)
        best[0] = Step(0.0, 0, "", false)
        for (i in 0 until n) {
            val b = best[i] ?: continue
            for (L in minOf(d.maxHan, n - i) downTo 1) {
                val w = chars.subList(i, i + L).joinToString("")
                val known = d.hanMap[w] != null
                if (!known && L > 1) continue
                val cost = b.cost + if (known) 1.0 else 1.5
                val cur = best[i + L]
                if (cur == null || cost < cur.cost) best[i + L] = Step(cost, i, w, known)
            }
        }
        val items = ArrayList<ConvItem>()
        var j = n
        while (j > 0) {
            val b = best[j] ?: break
            val opts = ArrayList<Opt>()
            if (b.known) {
                for (c in d.hanMap[b.w]!!) opts.add(Opt(b.w, c.split(' ')))
                d.hanAlt[b.w]?.let { opts.addAll(it) }
            } else opts.add(Opt(b.w, null))
            items.add(ConvItem(opts = opts, src = "han"))
            j = b.from
        }
        items.reverse()
        return items
    }

    private fun combos(lists: List<List<String>>, cap: Int = 32): List<List<String>> {
        var acc: List<List<String>> = listOf(emptyList())
        for (l in lists) {
            val next = ArrayList<List<String>>()
            outer@ for (a in acc) for (x in l) { next.add(a + x); if (next.size >= cap) break@outer }
            acc = next
        }
        return acc
    }

    private fun segSyl(syls: List<Pair<List<String>, String>>): List<ConvItem> {
        val n = syls.size
        class Step(val cost: Double, val from: Int, val opts: List<Opt>)
        val best = arrayOfNulls<Step>(n + 1)
        best[0] = Step(0.0, 0, emptyList())
        for (i in 0 until n) {
            val b = best[i] ?: continue
            for (L in 1..minOf(d.maxSyl, n - i)) {
                var opts = ArrayList<Opt>()
                for (combo in combos(syls.subList(i, i + L).map { it.first })) {
                    for (h in d.codeMap[combo.joinToString(" ")] ?: emptyList<String>()) opts.add(Opt(h, combo))
                }
                val cost: Double
                if (opts.isNotEmpty()) cost = b.cost + 1
                else if (L == 1) { opts = ArrayList(syls[i].first.map { Opt(null, listOf(it)) }); cost = b.cost + 1.5 }
                else continue
                val cur = best[i + L]
                if (cur == null || cost < cur.cost) best[i + L] = Step(cost, i, opts)
            }
        }
        val items = ArrayList<ConvItem>()
        var j = n
        while (j > 0) { val b = best[j] ?: break; items.add(ConvItem(opts = b.opts, src = syls.firstOrNull()?.second ?: "lat")); j = b.from }
        items.reverse()
        return items
    }

    fun convert(text: String): ConvResult {
        val res = ConvResult()
        val atoms = atomize(text, res)
        var i = 0
        while (i < atoms.size) {
            when (val a = atoms[i]) {
                is Atom.Han -> {
                    val chars = ArrayList<String>()
                    while (i < atoms.size) { val x = atoms[i]; if (x is Atom.Han) { chars.add(x.c); i++ } else break }
                    res.seen["han"] = (res.seen["han"] ?: 0) + chars.size
                    res.items.addAll(segHan(chars))
                }
                is Atom.Syl -> {
                    val syls = ArrayList<Pair<List<String>, String>>()
                    while (i < atoms.size) {
                        val x = atoms[i]
                        if (x is Atom.Syl) { syls.add(Pair(x.codes, x.from)); res.seen[x.from] = (res.seen[x.from] ?: 0) + 1; i++ }
                        else if (x is Atom.Space && i + 1 < atoms.size && atoms[i + 1] is Atom.Syl) i++
                        else break
                    }
                    res.items.addAll(segSyl(syls))
                }
                is Atom.Space -> { res.items.add(ConvItem(space = true)); i++ }
                is Atom.Newline -> { res.items.add(ConvItem(newline = true)); i++ }
                is Atom.Raw -> {
                    if (a.t.startsWith("\u0001")) res.items.add(ConvItem(raw = a.t.drop(1), unknownWord = true))
                    else res.items.add(ConvItem(raw = a.t))
                    i++
                }
                is Atom.Latin -> { res.items.add(ConvItem(raw = a.w, unknownWord = true)); i++ }
            }
        }
        for (k in res.items.indices) {
            val it = res.items[k]
            if (it.opts.size <= 1) continue
            // what you picked before for this word between the same neighbours always wins
            val wantCtx = mem[ctxMemKey(res.items, k)]
            if (wantCtx != null) {
                val at = it.opts.indexOfFirst { o -> optID(o) == wantCtx }
                if (at >= 0) { it.sel = at; continue }
            }
            val guess = contextPick(res.items, k)
            if (guess != null && guess.strong && guess.index != null) {
                it.sel = guess.index
            } else {
                val want = mem[memKey(it)]
                val at = if (want != null) it.opts.indexOfFirst { o -> optID(o) == want } else -1
                if (at >= 0) it.sel = at
                else if (guess?.index != null) it.sel = guess.index
            }
            if (guess != null) it.likely = likely(guess.share[it.sel] ?: 0.0)
        }
        return res
    }

    private fun neighbour(items: List<ConvItem>, k: Int, step: Int): String? {
        var j = k + step
        while (j >= 0 && j < items.size) {
            val it = items[j]
            if (it.newline) return null
            if (it.isWord) {
                val h = it.current.han
                if (h != null && it.current.codes != null) {
                    val cs = h.cps()
                    return if (step < 0) cs.lastOrNull() else cs.firstOrNull()
                }
            }
            j += step
        }
        return null
    }

    private class Guess(val index: Int?, val strong: Boolean, val share: Map<Int, Double>)

    private fun contextPick(items: List<ConvItem>, k: Int): Guess? {
        val ctx = d.raw.ctx ?: return null
        if (items[k].src != "han") return null
        val h = items[k].opts.firstOrNull()?.han ?: return null
        if (h.cpCount != 1) return null
        val prev = neighbour(items, k, -1); val next = neighbour(items, k, 1)
        var bestIdx = -1; var bestScore = 0.0; var bestNear = 0
        val near = LinkedHashMap<Int, Int>(); val uses = HashMap<Int, Int>()
        for ((j, o) in items[k].opts.withIndex()) {
            val cs = o.codes ?: continue
            if (cs.size != 1 || o.han != h) continue
            val c = cs[0]
            val l = prev?.let { ctx.l[it + "\t" + h + "\t" + c] } ?: 0
            val r = next?.let { ctx.r[h + "\t" + c + "\t" + it] } ?: 0
            val u = ctx.u[h + "\t" + c] ?: 0
            near[j] = l + r; uses[j] = u
            val score = 2.0 * (l + r) + 0.05 * u
            if (score > 0 && (bestIdx < 0 || score > bestScore)) { bestIdx = j; bestScore = score; bestNear = l + r }
        }
        if (near.size <= 1) return null
        val n = near.size.toDouble()
        val nearSum = near.values.sum().toDouble(); val useSum = uses.values.sum().toDouble()
        val share = HashMap<Int, Double>()
        for (j in near.keys) {
            share[j] = if (nearSum > 0) (near[j]!! + 0.5) / (nearSum + 0.5 * n) else (uses[j]!! + 1.0) / (useSum + n)
        }
        return Guess(if (bestIdx >= 0) bestIdx else null, bestIdx >= 0 && bestNear > 0, share)
    }

    // MARK: remembered picks

    private fun optID(o: Opt) = (o.han ?: "") + "|" + (o.codes ?: emptyList()).joinToString(" ")
    private fun memKey(it: ConvItem) =
        if (it.src == "han") "h:" + (it.opts[0].han ?: "") else "c:" + (it.opts[0].codes ?: emptyList()).joinToString(" ") + ":" + it.opts.size

    fun remember(items: List<ConvItem>, k: Int) {
        val it = items[k]
        mem[memKey(it)] = optID(it.current)
        mem[ctxMemKey(items, k)] = optID(it.current)
        prefs.putString("ff-picks", JWriter.any(mem))
    }

    private fun ctxMemKey(items: List<ConvItem>, k: Int) =
        "x:" + (neighbour(items, k, -1) ?: "") + "|" + memKey(items[k]) + "|" + (neighbour(items, k, 1) ?: "")

    // MARK: writing the result

    /** text of one word in a mode: 0 漢字, 1 romanization (rom = 0/1/2), 2 方音 */
    fun wordText(o: Opt, mode: Int, rom: Int, place: Int): String {
        if (mode == 0) return o.han ?: d.codes((o.codes ?: emptyList()).joinToString(" "), rom, place)
        val codes = o.codes ?: return o.han ?: ""
        val sys = if (mode == 2) 3 else rom
        if (o.han != null && o.parent == null) {
            val k = o.han + "\t" + codes.joinToString(" ")
            if (d.baseKeys.contains(k)) return d.word(k, sys, place)
        }
        return d.codes(codes.joinToString(" "), sys, place, o.tokens)
    }

    fun wordPieces(o: Opt, mode: Int, rom: Int, place: Int): List<Pair<String, Boolean>> {
        if (mode != 0 && place >= 0 && o.han != null && o.codes != null && o.parent == null) {
            val k = o.han + "\t" + o.codes.joinToString(" ")
            if (d.baseKeys.contains(k)) return d.wordPieces(k, if (mode == 2) 3 else rom, place)
        }
        return listOf(Pair(wordText(o, mode, rom, place), false))
    }

    fun pieces(items: List<ConvItem>, mode: Int, rom: Int, place: Int): List<OutPiece> {
        val out = ArrayList<OutPiece>()
        var prev: Char? = null          // w word, x foreign text, o opening punct, p other punct
        var lastText = ""
        for ((idx, it) in items.withIndex()) {
            if (it.newline) { out.add(OutPiece("\n", null)); prev = null; lastText = "\n"; continue }
            if (it.space) continue
            val raw = it.raw
            if (raw != null) {
                var t = raw; val kind: Char
                if (isPunct(t) && !it.unknownWord) {
                    t = if (mode == 1) toASCII[t] ?: t else toFull[t] ?: t
                    kind = if (openers.contains(t)) 'o' else 'p'
                } else kind = 'x'
                var space = false
                if (prev != null && prev != 'o') {
                    space = if (kind == 'x') (prev != 'p' || mode == 1) else (if (kind == 'o') mode == 1 else false)
                }
                if (!space && kind == 'x' && prev == 'p' && mode != 1 && lastText.isNotEmpty() && ",.!?;:".contains(lastText.last())) space = true
                out.add(OutPiece((if (space) " " else "") + t, if (it.unknownWord) -1 else null))
                prev = kind; lastText = t
                continue
            }
            var space = false
            if (prev == 'w' || prev == 'x') space = mode != 0 || prev == 'x'
            else if (prev == 'p') space = mode == 1
            val t = wordText(it.current, mode, rom, place)
            if (space && prev == 'w' && mode != 0 && wordText(it.current, 1, rom, place).startsWith("--")) space = false
            out.add(OutPiece((if (space) " " else "") + t, idx))
            prev = 'w'; lastText = t
        }
        return out
    }
}
