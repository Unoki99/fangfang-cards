package com.unoki99.fangfang.engine

/** One example sentence. `bh`/`br` are the fill-in-the-blank versions (word replaced by ＿＿). */
data class Example(
    val h: String,              // 漢字
    val r: List<String>,        // 皓羅, 台羅, 白話字
    val z: String,              // 華語
    val n: String,              // audio name, e.g. "3139-1-1"
    val bh: String? = null,
    val br: List<String>? = null,
    /** 華語: the sentence's reading, word by word (see Zh.kt) */
    val w: String? = null,
)

data class Def(
    val p: String,              // word class
    val t: String,              // meaning
    val x: List<Example>,
    val sy: List<List<String>>? = null,   // synonyms: [漢字, 皓羅]
    val an: List<List<String>>? = null,   // antonyms
)

/** the word as said in one place (腔口) */
data class Variant(val r: List<String>, val z: String)

/** another reading: 又 / 俗 / 合 */
data class Other(val l: String, val r: List<String>, val z: String)

data class Topic(val id: Int, val rawName: String, val count: Int) {
    /** the name in the app's language */
    val name: String get() = com.unoki99.fangfang.UILang.label(rawName)
}

class Card(
    val k: String,              // "漢字\tcodes"
    val h: String,
    val r: List<String>,
    val z: String,
    val a: Int?,                // MOE audio id
    val g: String,              // 白 / 文 / 俗
    val d: List<Def>,
    val c: List<String>?,       // syllable codes
    val zo: String?,
    val v: Map<String, Variant>?,
    val o: List<Other>?,
    val s: Int?,                // 1 = 替代字
    val t: String?,             // 臺華共同 / 附錄
    val sy: List<List<String>>?,
    val an: List<List<String>>?,
    val cats: List<Int>?,
    /** 華語: the 注音 syllables (臺灣, and 大陸 where it differs) */
    val zs: List<String>? = null,
    val zl: List<String>? = null,
    /** 粵語: a recording of the word (a web address, Wikimedia Commons) */
    val web: String? = null,
) {
    override fun equals(other: Any?) = other is Card && other.k == k
    override fun hashCode() = k.hashCode()
    val isZh: Boolean get() = zs != null
    /** the word's recording (台語), or the device's voice (華語; 粵語 when the word has no recording) */
    /** (客語: only a recording; no device has a 客語 voice) */
    val audio: String? get() = if (isZh) (if (Lang.isHakKey(k)) web else (web ?: "tts:$h")) else a?.let { Audio.wordPath(it) }

    fun rom(i: Int, place: Int = -1): String {
        val j = i.coerceIn(0, r.size - 1)
        if (place >= 0) v?.get(place.toString())?.let { return it.r[minOf(j, it.r.size - 1)] }
        return r[j]
    }
    fun zy(place: Int = -1): String {
        if (place < 0) return z
        v?.get(place.toString())?.let { return it.z }
        return zo ?: z
    }
    fun differs(place: Int) = place >= 0 && v?.get(place.toString()) != null
    val syllables: Int get() = r[0].split("-").filter { it.isNotEmpty() }.size
    val firstMeaning: String get() = d.firstOrNull()?.t ?: ""
    fun meaning(x: Example): Def? = d.firstOrNull { def -> def.x.any { it.n == x.n && it.h == x.h } }
    val blankExamples: List<Example> get() = d.flatMap { it.x }.filter { it.bh != null && it.br != null }
    val firstExample: Example? get() = d.firstNotNullOfOrNull { it.x.firstOrNull() }

    /** examples for the swipe card: one from each of two different meanings (meaning number, example) */
    val cardExamples: List<Pair<Int, Example>>
        get() {
            val out = ArrayList<Pair<Int, Example>>()
            for ((i, def) in d.withIndex()) {
                def.x.firstOrNull()?.let { out.add(Pair(i + 1, it)) }
                if (out.size == 2) return out
            }
            if (out.size == 1) {
                val i = d.indexOfFirst { it.x.isNotEmpty() }
                if (i >= 0 && d[i].x.size > 1) out.add(Pair(i + 1, d[i].x[1]))
            }
            return out
        }
}

class DeckFile(
    val cards: List<Card>,
    val syl: Map<String, List<String>>,
    val places: List<String>,
    val topics: List<Topic>,
) {
    companion object {
        fun parse(text: String, onProgress: ((Float) -> Unit)? = null): DeckFile {
            val j = JReader(text)
            var cards: List<Card> = emptyList()
            var syl: Map<String, List<String>> = emptyMap()
            var places: List<String> = emptyList()
            var topics: List<Topic> = emptyList()
            j.obj { k ->
                when (k) {
                    "cards" -> {
                        var n = 0
                        cards = j.list { val c = readCard(j); if (++n % 500 == 0) onProgress?.invoke(j.progress); c }
                    }
                    "syl" -> syl = j.strListMap()
                    "places" -> places = j.strList()
                    "topics" -> topics = j.list {
                        j.beginArray()
                        j.hasNext(); val id = j.nextInt()
                        j.hasNext(); val name = j.nextString()
                        j.hasNext(); val count = j.nextInt()
                        while (j.hasNext()) j.skip()
                        j.endArray()
                        Topic(id, name, count)
                    }
                    else -> j.skip()
                }
            }
            return DeckFile(cards, syl, places, topics)
        }

        private fun optStrList2(j: JReader): List<List<String>>? = if (j.isNull()) null else j.strList2()

        private fun readExample(j: JReader): Example {
            var h = ""; var r: List<String> = emptyList(); var z = ""; var n = ""
            var bh: String? = null; var br: List<String>? = null
            j.obj { k ->
                when (k) {
                    "h" -> h = j.nextString()
                    "r" -> r = j.strList()
                    "z" -> z = j.nextString()
                    "n" -> n = j.nextString()
                    "bh" -> bh = if (j.isNull()) null else j.nextString()
                    "br" -> br = if (j.isNull()) null else j.strList()
                    else -> j.skip()
                }
            }
            return Example(h, r, z, n, bh, br)
        }

        private fun readDef(j: JReader): Def {
            var p = ""; var t = ""; var x: List<Example> = emptyList()
            var sy: List<List<String>>? = null; var an: List<List<String>>? = null
            j.obj { k ->
                when (k) {
                    "p" -> p = j.nextString()
                    "t" -> t = j.nextString()
                    "x" -> x = j.list { readExample(j) }
                    "sy" -> sy = optStrList2(j)
                    "an" -> an = optStrList2(j)
                    else -> j.skip()
                }
            }
            return Def(p, t, x, sy, an)
        }

        private fun readCard(j: JReader): Card {
            var k = ""; var h = ""; var r: List<String> = emptyList(); var z = ""; var a: Int? = null; var g = ""
            var d: List<Def> = emptyList(); var c: List<String>? = null; var zo: String? = null
            var v: Map<String, Variant>? = null; var o: List<Other>? = null; var s: Int? = null; var t: String? = null
            var sy: List<List<String>>? = null; var an: List<List<String>>? = null; var cats: List<Int>? = null
            j.obj { key ->
                when (key) {
                    "k" -> k = j.nextString()
                    "h" -> h = j.nextString()
                    "r" -> r = j.strList()
                    "z" -> z = j.nextString()
                    "a" -> a = if (j.isNull()) null else j.nextInt()
                    "g" -> g = j.nextString()
                    "d" -> d = j.list { readDef(j) }
                    "c" -> c = if (j.isNull()) null else j.strList()
                    "zo" -> zo = if (j.isNull()) null else j.nextString()
                    "v" -> v = if (j.isNull()) null else j.map {
                        var vr: List<String> = emptyList(); var vz = ""
                        j.obj { kk -> when (kk) { "r" -> vr = j.strList(); "z" -> vz = j.nextString(); else -> j.skip() } }
                        Variant(vr, vz)
                    }
                    "o" -> o = if (j.isNull()) null else j.list {
                        var l = ""; var orr: List<String> = emptyList(); var oz = ""
                        j.obj { kk -> when (kk) { "l" -> l = j.nextString(); "r" -> orr = j.strList(); "z" -> oz = j.nextString(); else -> j.skip() } }
                        Other(l, orr, oz)
                    }
                    "s" -> s = if (j.isNull()) null else j.nextInt()
                    "t" -> t = if (j.isNull()) null else j.nextString()
                    "sy" -> sy = optStrList2(j)
                    "an" -> an = optStrList2(j)
                    "cats" -> cats = if (j.isNull()) null else j.intList()
                    else -> j.skip()
                }
            }
            return Card(k, h, r, z, a, g, d, c, zo, v, o, s, t, sy, an, cats)
        }
    }
}

/** Saved progress. status: 1 = 熟悉 (known), 2 = 不熟 (unknown) */
class Progress(
    val status: HashMap<String, Int> = HashMap(),
    val added: HashMap<String, Double> = HashMap(),
    val streak: HashMap<String, Int> = HashMap(),
    /** 收藏: key -> time saved (negative = removed, so synced devices remove it too) */
    val saved: HashMap<String, Double> = HashMap(),
    /** 自訂: your own words (key -> time added; negative = removed) */
    val own: HashMap<String, Double> = HashMap(),
    /** 收藏 of one meaning of a word: SavedSense.id -> time saved (negative = removed) */
    val senses: HashMap<String, Double> = HashMap(),
    /** 本週學習: words picked for this week (key -> time picked; negative = taken out) */
    val week: HashMap<String, Double> = HashMap(),
    /** when this week started, for 台語 ("tw") and 華語 ("zh") (negative = ended) */
    val weekStart: HashMap<String, Double> = HashMap(),
    /** 複習: key -> [next review time, interval (days), ease, reviews, lapses, last answered] */
    val srs: HashMap<String, MutableList<Double>> = HashMap(),
    /** 練習統計: "台語|2026-11-08" -> [right, wrong, learned] */
    val log: HashMap<String, MutableList<Int>> = HashMap(),
) {
    fun copy() = Progress(HashMap(status), HashMap(added), HashMap(streak), HashMap(saved), HashMap(own),
        HashMap(senses), HashMap(week), HashMap(weekStart),
        HashMap(srs.mapValues { it.value.toMutableList() }), HashMap(log.mapValues { it.value.toMutableList() }))

    fun toJson(): String = JWriter.any(mapOf("status" to status, "added" to added, "streak" to streak, "saved" to saved, "own" to own,
        "senses" to senses, "week" to week, "weekStart" to weekStart, "srs" to srs, "log" to log))

    companion object {
        fun parse(text: String): Progress {
            val p = Progress()
            val j = JReader(text)
            j.obj { k ->
                when (k) {
                    "status" -> j.obj { w -> p.status[w] = j.nextInt() }
                    "added" -> j.obj { w -> p.added[w] = j.nextDouble() }
                    "streak" -> j.obj { w -> p.streak[w] = j.nextInt() }
                    "saved" -> j.obj { w -> p.saved[w] = j.nextDouble() }
                    "own" -> j.obj { w -> p.own[w] = j.nextDouble() }
                    "senses" -> j.obj { w -> p.senses[w] = j.nextDouble() }
                    "week" -> j.obj { w -> p.week[w] = j.nextDouble() }
                    "weekStart" -> j.obj { w -> p.weekStart[w] = j.nextDouble() }
                    "srs" -> j.obj { w -> val l = ArrayList<Double>(); j.arr { l.add(j.nextDouble()) }; p.srs[w] = l }
                    "log" -> j.obj { w -> val l = ArrayList<Int>(); j.arr { l.add(j.nextInt()) }; p.log[w] = l }
                    else -> j.skip()
                }
            }
            return p
        }
    }
}

/** a saved meaning of a word (sense = its number, from 0) */
data class SavedSense(val key: String, val sense: Int, val ex: String = "") {
    val id: String get() = key + "\u0001" + sense + "\u0001" + ex
    companion object {
        fun fromId(id: String): SavedSense? {
            val p = id.split("\u0001")
            if (p.size != 3) return null
            val n = p[1].toIntOrNull() ?: return null
            return SavedSense(p[0], n, p[2])
        }
    }
}

object Audio {
    const val defaultBase = "https://unoki99.github.io/fangfang/"
    fun wordPath(id: Int) = "audio/${id / 1000}/$id(1).mp3"
    fun examplePath(name: String): String {
        if (name.startsWith("tts:") || name.isEmpty()) return name          // 華語: read by the device (客語: nothing)
        val id = name.split("-").firstOrNull()?.toIntOrNull() ?: 0
        return "leku/${id / 1000}/$name.mp3"
    }
}

/** a piece of text in one colour (ARGB; null = the colour of the text around it) */
data class Seg(val t: String, val c: Int? = null)

typealias Styled = List<Seg>

fun Styled.plain(): String = joinToString("") { it.t }

/** pieces of text with neighbours of the same colour merged */
class StyledBuilder {
    val out = ArrayList<Seg>()
    fun add(t: String, c: Int? = null) {
        if (t.isEmpty()) return
        val l = out.lastOrNull()
        if (l != null && l.c == c) out[out.size - 1] = Seg(l.t + t, c) else out.add(Seg(t, c))
    }
    fun addAll(s: Styled) { for (x in s) add(x.t, x.c) }
    fun build(): Styled = out
}

fun styled(t: String, c: Int? = null): Styled = if (t.isEmpty()) emptyList() else listOf(Seg(t, c))

// MARK: text helpers (Swift works on characters; Kotlin strings are UTF-16, so 𪜶 is two chars)

/** the code points of a string, one string each */
fun String.cps(): List<String> {
    val out = ArrayList<String>(length)
    var i = 0
    while (i < length) {
        val cp = codePointAt(i)
        val n = Character.charCount(cp)
        out.add(substring(i, i + n))
        i += n
    }
    return out
}

/** number of code points (Swift's count for 漢字) */
val String.cpCount: Int get() = codePointCount(0, length)

fun String.firstCp(): Int = if (isEmpty()) 0 else codePointAt(0)

/** the numbers of spaced review: a word learned in practice comes back after 1 day, then 3, then each time about
 *  2.5× longer ("ease"; a little less each time it's forgotten, never under 1.3). The way of SM-2:
 *  Algorithm SM-2, (C) Copyright SuperMemo World, 1991. www.supermemo.com */
object SRS {
    const val EASE = 2.5
    const val MIN_EASE = 1.3
    /** (at most about a year and a half between two reviews) */
    const val LONGEST = 540.0
    /** 記熟了: back in 3 weeks or more */
    const val MATURE_DAYS = 21.0
    fun days(d: Double) = d * 86_400
    /** "台語|2026-11-08" (the day where the device is) */
    fun dayKey(lang: String, date: java.util.Date): String {
        val c = java.util.Calendar.getInstance().apply { time = date }
        return String.format(java.util.Locale.US, "%s|%04d-%02d-%02d", lang, c.get(java.util.Calendar.YEAR),
            c.get(java.util.Calendar.MONTH) + 1, c.get(java.util.Calendar.DAY_OF_MONTH))
    }
}
