package com.unoki99.fangfang

import android.content.Context
import org.json.JSONObject

/** The app's own language, for buttons, menus and explanations: 中文 (as the code is written) or English (from
 *  assets/ui_en.json, keyed by the Chinese text). The dictionaries' content (meanings, examples) stays as it is. */
object UILang {
    private var ctx: Context? = null
    private var table: Map<String, String>? = null

    fun init(c: Context) { ctx = c.applicationContext }

    /** 設定 → 介面語言 (a Compose state: the screens redraw when it changes) */
    val english: Boolean get() = Prefs.uiLanguage.value == 1

    /** the English for a piece of text (with {0} {1}… where the values go), or null */
    fun english(key: String): String? {
        if (table == null) {
            table = try {
                val o = JSONObject(ctx!!.assets.open("ui_en.json").bufferedReader().use { it.readText() })
                buildMap { for (k in o.keys()) put(k, o.getString(k)) }
            } catch (_: Exception) { emptyMap() }
        }
        return table?.get(key)
    }

    /** a name the app puts together (the 新詞 groups, the HSK/TOCFL levels), in the app's language */
    fun label(s: String): String {
        if (!english) return s
        english(s)?.let { return it }
        var t = s
        for ((a, b) in parts) t = t.replace(a, b)
        return t
    }
    private val parts = listOf(
        "漢字・更多常用字" to "Characters · more common ones", "漢字・" to "Characters · ",
        "常用字 " to "Common characters ", "常用詞 " to "Common words ",
        "準備一級" to "Novice 1", "準備二級" to "Novice 2", "入門級" to "Level 1", "基礎級" to "Level 2",
        "進階級" to "Level 3", "高階級" to "Level 4", "流利級" to "Level 5",
    )
}

/** the app's text in the language chosen (設定 → 介面語言); {0} {1}… are the values put in; numbers get their
 *  thousands separators */
fun tr(key: String, vararg a: Any?): String {
    val en = UILang.english
    var s = (if (en) UILang.english(key) else null) ?: key
    a.forEachIndexed { i, v ->
        // (values aren't looked up: a word or character from the dictionary never turns into English by accident;
        // the app's own text is translated where it's made, tr("…"))
        val t = when (v) {
            is Int, is Long -> "%,d".format(v)
            null -> ""
            else -> v.toString()
        }
        s = s.replace("{$i}", t)
    }
    return s
}
