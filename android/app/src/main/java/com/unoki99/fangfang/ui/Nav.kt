package com.unoki99.fangfang.ui

import androidx.compose.runtime.*
import androidx.compose.runtime.snapshots.SnapshotStateList
import com.unoki99.fangfang.engine.Card
import com.unoki99.fangfang.engine.PlaceGroup
import com.unoki99.fangfang.engine.SentenceHit

/** a page that opens on top of a tab (or inside the sheet from the bottom) */
sealed class Route {
    data class Entry(val key: String) : Route()
    data class Keys(val title: String, val keys: List<String>) : Route()
    data class Sentences(val title: String, val hits: List<SentenceHit>) : Route()
    data class Places(val groups: List<PlaceGroup>) : Route()
    data class WordClass(val cls: String) : Route()
    object Compare : Route()
    /** 依常用度列出 (zh: the 華語-like dictionary shown; else 台語's), and one of its steps */
    data class FreqBands(val zh: Boolean) : Route()
    data class FreqBand(val zh: Boolean, val level: Int) : Route()
    /** 影片詞組, and 創作範圍 / 編輯 one (name: the scope being changed) */
    object VideoGroups : Route()
    /** 台語: a 腔口's own words */
    data class PlaceWords(val place: Int) : Route()
    data class ScopeEditor(val name: String?) : Route()
    object WordClasses : Route()
    /** 華語 */
    data class ZhEntry(val key: String) : Route()
    data class ZhLevel(val level: Int) : Route()
    object ZhProgress : Route()
    object SenseCopySettings : Route()
    data class Category(val i: Int) : Route()
    /** 部首查字 (for the 台語 or the 華語 search) */
    data class Radicals(val zh: Boolean) : Route()
    object Japanese : Route()
    object ZhCompare : Route()
    object ZhClasses : Route()
    data class ZhClass(val cls: String) : Route()
    object ZhChars : Route()
    object ToneColorPicker : Route()
    /** 日語 */
    object JaParticles : Route()
    data class JaLab(val key: String?) : Route()
    object JaColors : Route()
}

class NavStack {
    val stack: SnapshotStateList<Route> = mutableStateListOf()
    fun push(r: Route) { stack.add(r) }
    fun pop(): Boolean = if (stack.isEmpty()) false else { stack.removeAt(stack.size - 1); true }
    val top: Route? get() = stack.lastOrNull()
}

val LocalNav = staticCompositionLocalOf { NavStack() }

/** what the sheet from the bottom shows */
sealed class Sheet {
    data class Word(val key: String) : Sheet()
    data class ConvWord(val index: Int) : Sheet()
    data class CardSheet(val card: Card) : Sheet()
    data class ZhWord(val key: String) : Sheet()
    /** 手寫練習: the words with a character */
    data class CharWords(val ch: String) : Sheet()
}

enum class Practice { STUDY, BLANKS, SCRAMBLE, READING, TONES, MEMORY, WEEK, WEEK_TEST, HANDWRITING, STATS, WEEK_WRITE, WORD_WRITE, JA_PARTICLES, FALLING, SWIPE, TONE_GAME, FREE_WRITING }

/** the app's screens that open over everything */
object UI {
    /** the app opens on 詞典 */
    var tab by mutableIntStateOf(4)
    var settingsOpen by mutableStateOf(false)
    /** 電台, and its 歌詞 */
    var radioOpen by mutableStateOf(false)
    var lyricsOpen by mutableStateOf(false)
    /** 新詞 on a phone on its side: no tab bar (only the cards) */
    var hideTabs by mutableStateOf(false)
    var practice by mutableStateOf<Practice?>(null)
    /** 手寫練習 opened from a side card (新詞): just these characters, then back to the cards */
    var handwritingOnly by mutableStateOf<List<String>?>(null)
    /** 寫整個詞 (a tablet's 新詞): the card whose word is written */
    var writeCard by mutableStateOf<Card?>(null)
    /** sheets can open on top of each other (a word from a word): the last one is shown */
    val sheets = mutableStateListOf<Sheet>()
    fun open(s: Sheet) { sheets.add(s) }
    fun openWord(key: String) { sheets.add(Sheet.Word(key)) }
    fun closeSheet() { if (sheets.isNotEmpty()) sheets.removeAt(sheets.size - 1) }
    val tabs = List(5) { NavStack() }
}
