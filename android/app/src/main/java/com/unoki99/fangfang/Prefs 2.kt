package com.unoki99.fangfang

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import com.unoki99.fangfang.engine.EngineSettings
import com.unoki99.fangfang.engine.KeyValue
import kotlin.reflect.KProperty

/** one setting: a Compose state (screens redraw when it changes), saved in the app's preferences */
class Pref<T>(private val key: String, private val default: T) {
    private var state: MutableState<T>? = null
    var onChange: ((T) -> Unit)? = null

    @Suppress("UNCHECKED_CAST")
    fun bind(sp: SharedPreferences) {
        val v: T = when (default) {
            is Int -> sp.getInt(key, default) as T
            is Boolean -> sp.getBoolean(key, default) as T
            is Float -> sp.getFloat(key, default) as T
            is String -> (sp.getString(key, default) ?: default) as T
            else -> default
        }
        state = mutableStateOf(v)
    }

    var value: T
        get() = state?.value ?: default
        set(v) {
            if (state?.value == v) return
            state?.value = v
            val e = Prefs.sp.edit()
            when (v) {
                is Int -> e.putInt(key, v)
                is Boolean -> e.putBoolean(key, v)
                is Float -> e.putFloat(key, v)
                is String -> e.putString(key, v)
            }
            e.apply()
            onChange?.invoke(v)
        }

    operator fun getValue(thisRef: Any?, property: KProperty<*>): T = value
    operator fun setValue(thisRef: Any?, property: KProperty<*>, v: T) { value = v }
}

object Prefs : KeyValue {
    lateinit var sp: SharedPreferences
        private set

    val rom = Pref("rom", 0)
    val place = Pref("place", -1)
    val toneSys = Pref("toneColors", 0)
    val toneMarks = Pref("toneMarksSandhi", false)
    val toneGlow = Pref("toneGlow", true)
    val hideMeaning = Pref("hideMeaning", false)
    val autoPlay = Pref("autoPlay", false)
    val volume = Pref("volume", 0.8f)
    val goal = Pref("goal", 3)
    val sessionSize = Pref("sessionSize", 10)
    val audioBase = Pref("audioBase", "https://unoki99.github.io/fangfang/")
    val theme = Pref("appTheme", "night")
    /** 設定 → 畫成圖再放大: tappable words swell when pressed (off = they don't) */
    val swellAnim = Pref("swellOn", true)
    val widgetBG = Pref("widgetBG", 0.45f)
    val textSize = Pref("textSize", 0)
    val syncDevices = Pref("syncDevices", true)
    val topic = Pref("topic", -1)
    val dictTab = Pref("dictTab", 0)
    val lookupQuery = Pref("lookupQuery", "")
    val pronQuery = Pref("pronQuery", "")
    val convText = Pref("ff-text", "")
    val latin = Pref("ff-latin", "auto")
    val swaps = Pref("ff-swaps", "")
    val swapOff = Pref("ff-swap-off", "")
    val compareA = Pref("compareA", "")
    val compareB = Pref("compareB", "")
    val backupFolder = Pref("backupFolder", "")
    val lastBackup = Pref("lastBackupMs", "")
    val deviceId = Pref("deviceId", "")
    // 華語 mode
    /** 0 = 台語, 1 = 華語 */
    val lang = Pref("lang", 0)
    /** the first time: the language to learn was chosen */
    val pickedLanguage = Pref("pickedLanguage", false)
    /** 華語 reading: 0 拼音, 1 注音 */
    val zhRom = Pref("zhRom", 0)
    /** 華語 reading of: 0 臺灣, 1 大陸 */
    val zhPlace = Pref("zhPlace", 0)
    /** the word list the 華語 cards follow: 0 HSK 3.0, 1 TOCFL */
    val zhList = Pref("zhList", 0)
    val zhTopic = Pref("zhTopic", -1)
    val zhDictTab = Pref("zhDictTab", 0)
    val zhLookupQuery = Pref("zhLookupQuery", "")
    val zhConvText = Pref("zhConvText", "")
    // 詞典
    val wordGap = Pref("wordGap", true)
    val imeOn = Pref("imeOn", false)
    val imeCJ = Pref("imeCJ", true)
    val imeWB = Pref("imeWB", false)
    val imeLiu = Pref("imeLiu", false)
    // 複製意思 (the layout) and 選擇複製 (轉換)
    val copyTpl = Pref("senseCopyTpl", com.unoki99.fangfang.engine.SenseCopy.presets[0].tpl)
    val copyEx = Pref("senseCopyExTpl", com.unoki99.fangfang.engine.SenseCopy.presets[0].ex)
    val copySep = Pref("senseCopySep", 0)
    /** 選擇複製: which of 漢字 / 羅馬字 / 方音 are copied, the Discord style of each, and what goes in front */
    val copyOn = listOf(Pref("copyHan", true), Pref("copyRom", true), Pref("copyZy", true))
    val copyStyle = listOf(Pref("copyStyleHan", 0), Pref("copyStyleRom", 0), Pref("copyStyleZy", 0))
    val copyPreText = listOf(Pref("copyPreHan", ""), Pref("copyPreRom", ""), Pref("copyPreZy", ""))
    val copyGap = Pref("copyGap", true)
    val memoryPairs = Pref("memoryPairs", 6)
    // 練習範圍 (-1 = all of 不熟), for 台語 and 華語
    val practiceTw = Pref("practiceTopic.tw", -1)
    val practiceZh = Pref("practiceTopic.zh", -1)
    // 華語: the main explanation on cards and lists (false 華語, true English)
    val zhEnglish = Pref("zhMainEnglish", false)
    /** the cards don't show the reading until you tap them */
    val hideReading = Pref("hideReading", false)
    /** 寫字題 in 開始練習 and 本週學習: write the whole word */
    val practiceWrite = Pref("practiceWrite", true)
    /** the themes' backgrounds and the potions move (off: less power) */
    val themeMotion = Pref("themeMotion", true)
    /** 華語's own copy layout */
    val zhCopyTpl = Pref("zh.senseCopyTpl", com.unoki99.fangfang.engine.SenseCopy.zhPresets[0].tpl)
    val zhCopyEx = Pref("zh.senseCopyExTpl", com.unoki99.fangfang.engine.SenseCopy.zhPresets[0].ex)
    val zhCopySep = Pref("zh.senseCopySep", com.unoki99.fangfang.engine.SenseCopy.zhPresets[0].sep)
    // 手寫練習
    val handTrace = Pref("handwritingTrace", false)
    val handList = Pref("handwritingList", "unknown")
    val handShuffle = Pref("handwritingShuffle", false)
    val handOwn = Pref("handwritingOwn", "")
    /** how big the writing square is (dp); 格子大小 changes it, the shadow follows */
    val handPad = Pref("handwritingPadSize", 380f)
    /** how much a stylus's pressure changes the thickness (0 = not at all, 1.5 = a lot) */
    val handPressure = Pref("handwritingPressure", 0.6f)
    /** the writing in the rainbow instead of the dark ink */
    val handRainbow = Pref("handwritingRainbow", false)
    /** 筆的顏色: a colour of the tone colours' grid (0xRRGGBB); 0 = the dark ink */
    val handInk = Pref("handwritingInkColor", 0)
    /** 手寫練習's font: 0 文楷, 1 芫荽 */
    val handFont = Pref("handwritingFont", 0)
    /** how thick the pen is (dp) */
    val handWidth = Pref("handwritingPenWidth", 9f)
    /** a phone on its side, 新詞: the ✕ ↺ ✓ buttons shown */
    val sidewaysButtons = Pref("sidewaysButtons", false)
    /** 介面語言: 0 中文, 1 English */
    val uiLanguage = Pref("uiLanguage", 0)
    /** 筆跡延遲: how many seconds after the pen the writing shows up (0 = right away) */
    val handDelay = Pref("handwritingInkDelay", 0f)
    val radicalMode = Pref("radicalMode", 0)
    val zhCompareA = Pref("zhCompareA", "")
    val zhCompareB = Pref("zhCompareB", "")
    /** the colours picked for each tone ("" = the standard ones): "1:ff6b6b,2:…" */
    val toneColorsTw = Pref("toneColorsTw", "")
    val toneColorsZh = Pref("toneColorsZh", "")
    val toneColorsYue = Pref("toneColorsYue", "")
    /** the other spellings kept while one language is shown (zhRom is the one shown: 華語 拼音/注音, 粵語 粵拼/耶魯) */
    val mandRom = Pref("mandRom", 0)
    val yueRom = Pref("yueRom", 0)
    /** the one of 華語 / 粵語 used last (read in the background in 台語 mode) */
    val lastZh = Pref("lastZh", 1)
    /** 轉換: 0 轉換, 1 讀音 */
    val convertTab = Pref("convertTab", 0)
    val readingsQuery = Pref("readingsQuery", "學生")
    /** 設定 → 字形: 簡體字 (華語 and 粵語) */
    val simplified = Pref("simplified", false)

    private val all = listOf<Pref<*>>(rom, place, toneSys, toneMarks, toneGlow, hideMeaning, autoPlay, volume, goal, sessionSize,
        audioBase, theme, swellAnim, widgetBG, textSize, syncDevices, topic, dictTab, lookupQuery, pronQuery, convText, latin,
        swaps, swapOff, compareA, compareB, backupFolder, lastBackup, deviceId,
        lang, zhRom, zhPlace, zhList, zhTopic, zhDictTab, zhLookupQuery, zhConvText, wordGap, imeOn, imeCJ, imeWB, imeLiu,
        copyTpl, copyEx, copySep, copyGap, memoryPairs, practiceTw, practiceZh, zhEnglish, hideReading, practiceWrite, themeMotion,
        zhCopyTpl, zhCopyEx, zhCopySep, handTrace, handList, handShuffle, handOwn, handPad, handPressure, handRainbow, handInk, handFont, handWidth, handDelay, radicalMode, zhCompareA, zhCompareB, toneColorsTw, toneColorsZh, toneColorsYue, mandRom, yueRom, lastZh, convertTab, readingsQuery, simplified, pickedLanguage, sidewaysButtons, uiLanguage) + copyOn + copyStyle + copyPreText

    fun init(ctx: Context) {
        if (::sp.isInitialized) return
        sp = ctx.getSharedPreferences("fangfang", Context.MODE_PRIVATE)
        UILang.init(ctx)
        for (p in all) p.bind(sp)
        if (deviceId.value.isEmpty()) deviceId.value = java.util.UUID.randomUUID().toString().take(4).uppercase()
        syncEngine()
        toneSys.onChange = { syncEngine() }
        toneMarks.onChange = { syncEngine() }
        com.unoki99.fangfang.engine.ToneColors.load(toneColorsTw.value, toneColorsZh.value, toneColorsYue.value)
        simplified.onChange = { syncEngine() }
    }

    fun syncEngine() {
        EngineSettings.toneSystem = toneSys.value
        EngineSettings.toneMarks = toneMarks.value
        EngineSettings.simplified = simplified.value
    }

    // the engine's own settings (remembered converter picks and the like)
    override fun getString(key: String): String? = when (key) {
        "ff-swaps" -> swaps.value
        "ff-swap-off" -> swapOff.value
        "ff-latin" -> latin.value
        else -> sp.getString(key, null)
    }

    override fun putString(key: String, value: String) {
        when (key) {
            "ff-swaps" -> swaps.value = value
            "ff-swap-off" -> swapOff.value = value
            "ff-latin" -> latin.value = value
            else -> sp.edit().putString(key, value).apply()
        }
    }
}
