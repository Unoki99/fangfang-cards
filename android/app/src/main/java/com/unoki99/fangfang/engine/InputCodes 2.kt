package com.unoki99.fangfang.engine

/** 倉頡 / 五筆 / 無蝦米 codes of characters (inputcodes.json, made by tools/build_inputcodes.py). */
class InputCodes(text: String?) {
    private val tables: List<Map<String, String>>

    init {
        val c = HashMap<String, String>(); val w = HashMap<String, String>(); val l = HashMap<String, String>()
        if (text != null) {
            val j = JReader(text)
            j.obj { k ->
                when (k) {
                    "c" -> j.obj { ch -> c[ch] = j.nextString() }
                    "w" -> j.obj { ch -> w[ch] = j.nextString() }
                    "l" -> j.obj { ch -> l[ch] = j.nextString() }
                    else -> j.skip()
                }
            }
        }
        tables = listOf(c, w, l)
    }

    /** is there a table for this system (無蝦米 only when you added your own) */
    fun has(system: Int): Boolean = tables[system].isNotEmpty()

    /** the codes of a character in a system: what to show ("口卜人 ryo", "KHU") */
    fun code(ch: String, system: Int): String? {
        val c = tables[system][ch] ?: return null
        if (c.isEmpty()) return null
        val first = c.split(' ').first()
        return when (system) {
            0 -> first.mapNotNull { radicals[it] }.joinToString("") + " " + first
            else -> first.uppercase()
        }
    }

    companion object {
        val names = listOf("倉頡", "五筆", "無蝦米")
        val short = listOf("倉", "五", "蝦")
        private val radicals = mapOf(
            'a' to "日", 'b' to "月", 'c' to "金", 'd' to "木", 'e' to "水", 'f' to "火", 'g' to "土", 'h' to "竹", 'i' to "戈", 'j' to "十",
            'k' to "大", 'l' to "中", 'm' to "一", 'n' to "弓", 'o' to "人", 'p' to "心", 'q' to "手", 'r' to "口", 's' to "尸", 't' to "廿",
            'u' to "山", 'v' to "女", 'w' to "田", 'x' to "難", 'y' to "卜", 'z' to "重")
    }
}
