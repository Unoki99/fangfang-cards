package com.unoki99.fangfang.engine

/**
 * A small, fast JSON reader for the big data files (cards.json, dict.json): it reads straight into
 * the app's own types, without building a tree of the whole file first.
 */
class JReader(private val s: String) {
    private var i = 0
    /** how far through the text it has read (0–1) */
    val progress: Float get() = if (s.isEmpty()) 1f else i.toFloat() / s.length

    private fun ws() {
        while (i < s.length) {
            val c = s[i]
            if (c == ' ' || c == '\n' || c == '\r' || c == '\t') i++ else break
        }
    }

    fun peek(): Char { ws(); return if (i < s.length) s[i] else '\u0000' }

    private fun expect(c: Char) {
        ws()
        if (i >= s.length || s[i] != c) throw IllegalStateException("JSON: expected '$c' at $i")
        i++
    }

    fun isNull(): Boolean {
        ws()
        if (s.startsWith("null", i)) { i += 4; return true }
        return false
    }

    /** reads an object: block gets each key, and must read its value */
    inline fun obj(block: (String) -> Unit) {
        beginObject()
        while (hasNext()) block(nextName())
        endObject()
    }

    /** reads an array: block reads each element */
    inline fun arr(block: () -> Unit) {
        beginArray()
        while (hasNext()) block()
        endArray()
    }

    fun beginObject() { expect('{'); first = true }
    fun endObject() { expect('}'); first = false }
    fun beginArray() { expect('['); first = true }
    fun endArray() { expect(']'); first = false }

    private var first = true

    fun hasNext(): Boolean {
        ws()
        val c = if (i < s.length) s[i] else '\u0000'
        if (c == '}' || c == ']') return false
        if (c == ',') { i++; ws() }
        return true
    }

    fun nextName(): String {
        val n = nextString()
        expect(':')
        return n
    }

    fun nextString(): String {
        expect('"')
        // fast path: no escapes
        var j = i
        while (j < s.length) {
            val c = s[j]
            if (c == '"') { val out = s.substring(i, j); i = j + 1; return out }
            if (c == '\\') break
            j++
        }
        val sb = StringBuilder().append(s, i, j)
        i = j
        while (i < s.length) {
            val c = s[i++]
            when (c) {
                '"' -> return sb.toString()
                '\\' -> {
                    val e = s[i++]
                    when (e) {
                        'n' -> sb.append('\n'); 't' -> sb.append('\t'); 'r' -> sb.append('\r')
                        'b' -> sb.append('\b'); 'f' -> sb.append('\u000c')
                        'u' -> { sb.append(s.substring(i, i + 4).toInt(16).toChar()); i += 4 }
                        else -> sb.append(e)
                    }
                }
                else -> sb.append(c)
            }
        }
        throw IllegalStateException("JSON: unterminated string")
    }

    private fun numberText(): String {
        ws()
        val st = i
        while (i < s.length && (s[i].isDigit() || s[i] == '-' || s[i] == '+' || s[i] == '.' || s[i] == 'e' || s[i] == 'E')) i++
        return s.substring(st, i)
    }

    fun nextInt(): Int = numberText().let { t -> t.toIntOrNull() ?: t.toDouble().toInt() }
    fun nextDouble(): Double = numberText().toDouble()
    fun nextBool(): Boolean {
        ws()
        if (s.startsWith("true", i)) { i += 4; return true }
        if (s.startsWith("false", i)) { i += 5; return false }
        throw IllegalStateException("JSON: expected a boolean at $i")
    }

    /** any value, as Map / List / String / Double / Boolean / null */
    fun any(): Any? {
        return when (peek()) {
            '{' -> { val m = LinkedHashMap<String, Any?>(); obj { k -> m[k] = any() }; m }
            '[' -> { val l = ArrayList<Any?>(); arr { l.add(any()) }; l }
            '"' -> nextString()
            't', 'f' -> nextBool()
            'n' -> { isNull(); null }
            else -> nextDouble()
        }
    }

    fun skip() { any() }

    // helpers for the shapes the data uses
    fun strList(): List<String> { val l = ArrayList<String>(); arr { l.add(nextString()) }; return l }
    fun strList2(): List<List<String>> { val l = ArrayList<List<String>>(); arr { l.add(strList()) }; return l }
    fun intList(): List<Int> { val l = ArrayList<Int>(); arr { l.add(nextInt()) }; return l }
    fun strMap(): Map<String, String> { val m = HashMap<String, String>(); obj { k -> m[k] = nextString() }; return m }
    fun intMap(): Map<String, Int> { val m = HashMap<String, Int>(); obj { k -> m[k] = nextInt() }; return m }
    fun doubleMap(): Map<String, Double> { val m = HashMap<String, Double>(); obj { k -> m[k] = nextDouble() }; return m }
    fun strListMap(): Map<String, List<String>> { val m = HashMap<String, List<String>>(); obj { k -> m[k] = strList() }; return m }
    fun <T> map(value: () -> T): Map<String, T> { val m = LinkedHashMap<String, T>(); obj { k -> m[k] = value() }; return m }
    fun <T> list(value: () -> T): List<T> { val l = ArrayList<T>(); arr { l.add(value()) }; return l }
}

/** writing JSON (progress, backups, widget files) */
object JWriter {
    fun str(s: String): String {
        val sb = StringBuilder(s.length + 2)
        sb.append('"')
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\""); '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n"); '\r' -> sb.append("\\r"); '\t' -> sb.append("\\t")
                else -> if (c < ' ') sb.append(String.format("\\u%04x", c.code)) else sb.append(c)
            }
        }
        sb.append('"')
        return sb.toString()
    }

    fun num(d: Double): String = if (d == Math.floor(d) && Math.abs(d) < 1e15) d.toLong().toString() else d.toString()

    /** Map / List / String / Number / Boolean / null as JSON */
    fun any(v: Any?, pretty: Boolean = false, indent: String = ""): String {
        val nl = if (pretty) "\n" else ""
        val ind2 = if (pretty) "$indent  " else ""
        return when (v) {
            null -> "null"
            is String -> str(v)
            is Boolean -> v.toString()
            is Int -> v.toString()
            is Long -> v.toString()
            is Double -> num(v)
            is Float -> num(v.toDouble())
            is Map<*, *> -> {
                if (v.isEmpty()) "{}" else {
                    val keys = v.keys.map { it.toString() }.let { if (pretty) it.sorted() else it }
                    keys.joinToString(",$nl", "{$nl", "$nl$indent}") { k ->
                        ind2 + str(k) + (if (pretty) ": " else ":") + any(v[k], pretty, ind2)
                    }
                }
            }
            is Iterable<*> -> {
                val l = v.toList()
                if (l.isEmpty()) "[]" else l.joinToString(",", "[", "]") { any(it, false) }
            }
            else -> str(v.toString())
        }
    }
}
