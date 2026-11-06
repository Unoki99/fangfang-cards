package com.unoki99.fangfang.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.TaigiSpeech
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.delay

/** 轉換: the text and its conversion (kept while you move between tabs) */
object ConvModel {
    var engine: ConvertEngine? = null; private set
    var result by mutableStateOf(ConvResult()); private set
    /** bumped when a reading is chosen (the items change inside the result) */
    var version by mutableIntStateOf(0); private set

    fun attach(d: Dict) {
        if (engine?.d === d) return
        engine = ConvertEngine(d, Prefs)
        run()
    }

    fun run() {
        val e = engine ?: return
        e.latinMode = LatinMode.of(Prefs.latin.value)
        result = e.convert(Prefs.convText.value)
        version++
    }

    fun choose(item: Int, opt: Int) {
        val r = result
        if (item !in r.items.indices) return
        r.items[item].sel = opt
        r.items[item].likely = null
        engine?.remember(r.items, item)
        version++
    }
}

private fun copyText(ctx: Context, s: String) {
    (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("方方", s))
}

@Composable
fun ConverterTab() {
    Column(Modifier.fillMaxSize()) {
        TopBar("轉換")
        if (Store.isZh) ZhGate { z -> ZhConvertPane(z) }
        else DictGate { d -> ConvertPane(d) }
    }
}

@Composable
private fun ConvertPane(d: Dict) {
    val ctx = LocalContext.current
    val focus = LocalFocusManager.current
    var text by Prefs.convText
    val latin = Prefs.latin.value
    LaunchedEffect(d) { ConvModel.attach(d) }
    LaunchedEffect(text, latin) { delay(120); ConvModel.run() }
    val res = ConvModel.result
    ConvModel.version
    val hasOutput = res.items.any { it.isWord }
    var copied by remember { mutableIntStateOf(-1) }
    var copySheet by remember { mutableStateOf(false) }
    LaunchedEffect(copied) { if (copied >= 0) { delay(1200); copied = -1 } }
    Store.rev
    if (copySheet) CopyOptionsSheet(listOf(plain(0), plain(1), plain(2)), listOf("漢字", ROM_NAMES[Prefs.rom.value.coerceIn(0, 2)], "方音")) { copySheet = false }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth >= 820.dp
        val leftWidth = minOf(440.dp, maxWidth * 0.42f)
        @Composable fun input() {
            Box(Modifier.fillMaxWidth().surface()) {
                TextField(text, { text = it }, Modifier.fillMaxWidth().heightIn(min = 110.dp, max = 220.dp),
                    placeholder = { Text("輸入或貼上漢字、皓羅、方音、台羅、白話字…", color = T.muted) },
                    textStyle = TextStyle(fontSize = 18.sp, color = T.glyph),
                    colors = TextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
                        focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent, cursorColor = T.greenInk))
                Row(Modifier.align(Alignment.BottomEnd).padding(4.dp)) {
                    IconButton(onClick = {
                        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        cm.primaryClip?.getItemAt(0)?.coerceToText(ctx)?.toString()?.let { text = it }
                    }) { Icon(Icons.Filled.ContentPaste, "貼上", tint = T.muted) }
                    if (text.isNotEmpty()) IconButton(onClick = { text = "" }) { Icon(Icons.Filled.Cancel, "清除", tint = T.muted) }
                }
            }
            if (res.anyLatin) {
                val autoName = mapOf("lat" to "皓羅", "tl" to "台羅", "poj" to "白話字")[res.autoLatin] ?: "皓羅"
                Txt("羅馬字當作", ff(FF.Caption), T.muted)
                Segmented(listOf("auto" to "自動（$autoName）", "lat" to "皓羅", "tl" to "台羅", "poj" to "白話字"), latin, { Prefs.latin.value = it })
            }
        }
        @Composable fun help() {
            Txt("例：", ff(FF.Footnote, FontWeight.Bold), T.muted)
            for (s in listOf("我欲去學校讀冊。", "Guá beh khì ha̍k-hāu tha̍k-tsheh.", "ㆣㄨㄚˋ ㄅㆤㆷ ㄎㄧˋ")) {
                SoftButton(onClick = { text = s }, modifier = Modifier.fillMaxWidth()) {
                    Text(s, style = if (s.first().code < 128) lat(16f) else ff(FF.Body), color = T.glyph, modifier = Modifier.weight(1f))
                }
            }
        }
        @Composable fun panels() {
            for ((mode, title) in listOf(0 to "漢字", 1 to ROM_NAMES[Prefs.rom.value.coerceIn(0, 2)], 2 to "方音")) {
                OutPanel(d, mode, title, copied == mode, onCopy = { copyText(ctx, plain(mode)); copied = mode }) { i -> focus.clearFocus(); UI.open(Sheet.ConvWord(i)) }
            }
        }
        @Composable fun actions() {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SoftButton(onClick = { copyText(ctx, listOf(plain(0), plain(1), plain(2)).joinToString("\n")); copied = 9 }, modifier = Modifier.weight(1f)) {
                    IconLabel(if (copied == 9) Icons.Filled.Check else Icons.Filled.ContentCopy, if (copied == 9) "已複製" else "全部複製", ff(FF.Subheadline))
                }
                SoftButton(onClick = { copySheet = true }, modifier = Modifier.weight(1f)) {
                    IconLabel(Icons.Filled.Tune, "選擇複製…", ff(FF.Subheadline))
                }
            }
            val keys = textKeys(d)
            if (keys.isNotEmpty()) {
                val newOnes = keys.filter { Store.cardStatus(it) == 0 }
                SoftButton(onClick = { Store.addUnknown(keys) }, enabled = newOnes.isNotEmpty(), modifier = Modifier.fillMaxWidth()) {
                    IconLabel(if (newOnes.isEmpty()) Icons.Filled.Star else Icons.Filled.StarBorder,
                        if (newOnes.isEmpty()) "這段的新詞都在卡片裡了" else "這段的新詞加到「不熟」（${newOnes.size}）", ff(FF.Subheadline))
                }
                val all = keys.all { Store.isSaved(it) }
                SoftButton(onClick = { Store.saveAll(keys) }, enabled = !all, modifier = Modifier.fillMaxWidth()) {
                    IconLabel(if (all) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                        if (all) "這段的詞都收藏了" else "收藏這段所有的詞（${keys.count { !Store.isSaved(it) }}）", ff(FF.Subheadline))
                }
            }
            Txt("點詞可以看意思、換讀音、收藏、加到「不熟」。按住再滑過去，放開就打開那個詞。下面有彩色星星 = 已收藏或在「不熟」，藍色星星 = 收藏了這個詞的某個意思。橘色 = 字典裡找不到，或讀音不太確定（猜對的機會約 80% 以下），點一下可以確認。",
                ff(FF.Caption), T.muted)
        }
        if (wide) Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Column(Modifier.width(leftWidth).fillMaxHeight().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                input(); if (hasOutput) actions() else help()
            }
            Column(Modifier.weight(1f).fillMaxHeight().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (hasOutput) panels() else Txt("轉換的結果會出現在這裡。", ff(FF.Body), T.muted, Modifier.padding(top = 40.dp))
            }
        } else Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            input()
            if (hasOutput) { panels(); actions() } else help()
            Spacer(Modifier.height(40.dp))
        }
    }
}

private fun plain(mode: Int): String =
    ConvModel.engine?.pieces(ConvModel.result.items, mode, Prefs.rom.value, Prefs.place.value)?.joinToString("") { it.text } ?: ""

private fun textKeys(d: Dict): List<String> {
    val seen = HashSet<String>(); val out = ArrayList<String>()
    for (it in ConvModel.result.items) {
        if (!it.isWord || it.current.codes == null) continue
        val k = d.keyOf(it.current) ?: continue
        if ((d.raw.defs.m[k] != null || d.baseKeys.contains(k)) && seen.add(k)) out.add(k)
    }
    return out
}

/** the text in 台羅 (通行 readings), for reading aloud — never any 漢字 */
private fun speechText(): String {
    val t = ConvModel.engine?.pieces(ConvModel.result.items, 1, 1, -1)?.joinToString("") { it.text } ?: ""
    val sb = StringBuilder()
    for (c in t.cps()) if (!ConvertEngine.isHan(c.firstCp())) sb.append(c)
    return sb.toString().replace(Regex("[ \\t]{2,}"), " ").trim()
}

/** 聲調顏色 in 轉換: the tone of every syllable, working through the whole text. item index -> (tokens, tones) */
private fun itemTones(d: Dict, items: List<ConvItem>, place: Int): Map<Int, Pair<List<String>, List<Int>>> {
    val units = ArrayList<ToneUnit>()
    val ranges = HashMap<Int, Triple<List<String>, Int, Int>>()
    var prevKey: String? = null
    fun endPhrase() { units.lastOrNull()?.phraseEnd = true }
    val nextKeyOf = HashMap<Int, String>()
    var upcoming: String? = null
    for (i in items.indices.reversed()) {
        val it = items[i]
        if (it.space) continue
        if (it.newline || it.raw != null || it.current.codes == null) { upcoming = null; continue }
        upcoming?.let { up -> nextKeyOf[i] = up }
        upcoming = d.keyOf(it.current)
    }
    for ((i, it) in items.withIndex()) {
        if (it.newline) { endPhrase(); prevKey = null; continue }
        if (it.space) continue
        val raw = it.raw
        if (raw != null) {
            if (ConvertEngine.isPunct(raw) && !ConvertEngine.openers.contains(raw)) endPhrase()
            prevKey = null
            continue
        }
        val codes = it.current.codes
        if (codes == null) { endPhrase(); prevKey = null; continue }
        val key = d.keyOf(it.current)
        val tokens = if (key != null && d.baseKeys.contains(key) && it.current.parent == null) d.tokensFor(key, place)
            else (it.current.tokens ?: codes.joinToString(" ")).split(' ').filter { s -> s.isNotEmpty() }
        val u = d.toneUnits(tokens, key, prevKey, nextKeyOf[i])
        prevKey = key
        if (tokens.firstOrNull() == "--" && units.isNotEmpty()) units.last().beforeLight = true
        if (it.current.han?.startsWith("仔") == true && units.isNotEmpty()) units.last().beforeA = true
        ranges[i] = Triple(tokens, units.size, units.size + u.size)
        units.addAll(u)
    }
    endPhrase()
    val tones = d.realizedTones(units, place)
    return ranges.mapValues { (_, v) -> Pair(v.first, tones.subList(v.second, v.third)) }
}

private class OutWord(val text: AnnotatedString, val item: Int?, val newLine: Boolean, val mark: Int = 0)

/** one output box: its pieces, words tappable (and slidable over) */
@Composable
private fun OutPanel(d: Dict, mode: Int, title: String, copied: Boolean, onCopy: () -> Unit, onOpen: (Int) -> Unit) {
    val rom = Prefs.rom.value; val place = Prefs.place.value; val toneSys = Prefs.toneSys.value
    val ink = listOf(T.glyph, T.greenInk, T.purpleInk)[mode]
    val res = ConvModel.result
    val version = ConvModel.version
    val tk = textKey()
    val rev = Store.rev
    val words = remember(res, version, tk, rev, mode) { outWords(d, res, mode, rom, place, toneSys, ink) }
    Column(Modifier.fillMaxWidth().surface().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Txt(title, ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.weight(1f))
            SpeakButton(speechText())
            IconButton(onClick = onCopy) { Icon(if (copied) Icons.Filled.Check else Icons.Filled.ContentCopy, "複製", tint = T.muted, modifier = Modifier.size(18.dp)) }
        }
        val style = if (mode == 1) lat(19f) else sz(if (mode == 0) 22f else 20f)
        TapWords(
            count = words.size,
            isTappable = { i -> i < words.size && (words[i].item ?: -1) >= 0 },
            newLine = { i -> i < words.size && words[i].newLine },
            onTap = { i -> words.getOrNull(i)?.item?.let { if (it >= 0) onOpen(it) } },
        ) { i, hot ->
            Box(Modifier.swell(hot), contentAlignment = Alignment.BottomCenter) {
                Text(words[i].text, style = style, color = ink, modifier = Modifier.padding(vertical = 4.dp))
                when (words[i].mark) {
                    1 -> Box(Modifier.offset(y = 3.dp)) { ToneStar() }
                    2 -> Box(Modifier.offset(y = 3.dp)) { ToneStar(blue = true) }
                }
            }
        }
    }
}

private fun outWords(d: Dict, res: ConvResult, mode: Int, rom: Int, place: Int, toneSys: Int, ink: Color): List<OutWord> {
    val e = ConvModel.engine ?: return emptyList()
    val pieces = e.pieces(res.items, mode, rom, place)
    val tones = if (toneSys != 0) itemTones(d, res.items, place) else emptyMap()
    val glow = Prefs.toneGlow.value
    val orange = Color(0xFFFF9F0A)
    val out = ArrayList<OutWord>()
    val senseKeys = Store.savedSenseKeys
    var newLine = false
    for (p in pieces) {
        if (p.text == "\n") {
            if (newLine) out.add(OutWord(AnnotatedString(" "), null, true))
            newLine = true; continue
        }
        var t = p.text
        if (t.startsWith(" ")) {
            t = t.drop(1)
            if (!newLine && out.isNotEmpty()) { val l = out.last(); out[out.size - 1] = OutWord(l.text + AnnotatedString(" "), l.item, l.newLine, l.mark) }
        }
        val i = p.item
        var mark = 0
        val text: AnnotatedString = if (i == null) AnnotatedString(t)
        else if (i < 0) buildAnnotatedString { withStyle(SpanStyle(color = orange)) { append(t) } }
        else {
            val it = res.items[i]
            val k = d.keyOf(it.current)
            // saved or in 不熟: a star in the tone colours under it; only meanings saved: a blue one
            if (k != null) mark = if (Store.isSaved(k) || Store.cardStatus(k) == 2) 1 else if (senseKeys.contains(k)) 2 else 0
            val deco = if (it.opts.size > 1) TextDecoration.Underline else null
            val bg = Color.Unspecified
            val tt = tones[i]
            if (it.current.codes == null) buildAnnotatedString { withStyle(SpanStyle(color = orange)) { append(t) } }
            else if (tt != null) {
                val st = if (mode == 0) hanToneText(t, tt.second, toneSys, ink.argbInt())
                    else d.toneText(tt.first, if (mode == 2) 3 else rom, place, tt.second, toneSys)
                val a = st.annotated(ink, glow)
                buildAnnotatedString { withStyle(SpanStyle(background = bg, textDecoration = deco)) { append(a) } }
            } else {
                val col = when {
                    it.unsure -> orange
                    k != null && d.isUser(k) -> T.ownInk
                    else -> null
                }
                val base: Styled = if (col == null && mode != 0) guessColored(e.wordPieces(it.current, mode, rom, place), ink.argbInt())
                    else styled(t, (col ?: ink).argbInt())
                val a = base.annotated(ink, false)
                buildAnnotatedString { withStyle(SpanStyle(background = bg, textDecoration = deco)) { append(a) } }
            }
        }
        out.add(OutWord(text, i, newLine, mark))
        newLine = false
    }
    return out
}

/** 🔊: reads the text aloud with 鬥拍字 (tap again to stop) */
@Composable
fun SpeakButton(text: String) {
    val ph = TaigiSpeech.phaseFor(text)
    LaunchedEffect(Unit) { kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { try { TaigiSpeech.dropOldDays() } catch (_: Exception) {} } }
    val failed = ph == TaigiSpeech.Phase.FAILED
    Row(Modifier.clip(CircleShape).background(if (failed) T.rust else T.placeFill).border(1.5.dp, if (failed) T.rustEdge else T.placeEdge, CircleShape)
        .clickable(enabled = text.isNotEmpty()) { TaigiSpeech.toggle(text) }.padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        when (ph) {
            TaigiSpeech.Phase.LOADING -> CircularProgressIndicator(Modifier.size(12.dp), color = T.purpleInk, strokeWidth = 2.dp)
            TaigiSpeech.Phase.PLAYING -> Icon(Icons.Filled.Stop, null, tint = T.purpleInk, modifier = Modifier.size(14.dp))
            TaigiSpeech.Phase.FAILED -> Icon(Icons.Filled.Warning, null, tint = T.rustInk, modifier = Modifier.size(14.dp))
            TaigiSpeech.Phase.IDLE -> Icon(Icons.Filled.VolumeUp, null, tint = T.purpleInk, modifier = Modifier.size(14.dp))
        }
        Txt(if (failed) "連不上鬥拍字" else if (ph == TaigiSpeech.Phase.IDLE) "唸出來" else "停", ff(FF.Footnote, FontWeight.SemiBold), if (failed) T.rustInk else T.purpleInk)
    }
}

/** a word in the converted text: pick the reading, see its dictionary entry */
@Composable
fun ConvWordSheet(d: Dict, index: Int) {
    val res = ConvModel.result
    ConvModel.version
    val rom = Prefs.rom.value; val place = Prefs.place.value
    var addingOwn by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { UI.closeSheet() }) { Text("完成", color = T.greenInk) }
            Spacer(Modifier.weight(1f))
            BarButtons(settings = false)
        }
        if (index !in res.items.indices) return@Column
        val it = res.items[index]
        val e = ConvModel.engine ?: return@Column
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            if (it.opts.size > 1) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Txt("選讀音／漢字", ff(FF.Caption, FontWeight.Bold), T.muted)
                    it.likely?.let { p -> Txt("目前的讀音：猜對的機會約 ${Math.round(p * 100)}%", ff(FF.Caption), if (it.unsure) Color(0xFFFF9F0A) else T.muted) }
                }
                for ((i, o) in it.opts.withIndex()) {
                    val on = i == it.sel
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(if (on) T.green.copy(alpha = 0.6f) else T.fn.copy(alpha = 0.6f))
                        .clickable { ConvModel.choose(index, i) }.padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        RadioButton(on, { ConvModel.choose(index, i) }, colors = RadioButtonDefaults.colors(selectedColor = T.greenInk, unselectedColor = T.muted))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                                Txt(o.han ?: "—", sz(20f, FontWeight.SemiBold), T.glyph)
                                if (o.codes != null) {
                                    Txt(guessColored(e.wordPieces(o, 1, rom, place)).annotated(), lat(17f), T.greenInk)
                                    Txt(guessColored(e.wordPieces(o, 2, rom, place)).annotated(), ff(FF.Footnote), T.purpleInk)
                                }
                                o.label?.let { l -> Chip(l) }
                                d.keyOf(o)?.let { k -> d.raw.reg[k]?.let { r -> RegChip(r) } }
                            }
                            gloss(d, o)?.let { g -> Txt(g, ff(FF.Footnote), T.glyph.copy(alpha = 0.75f), maxLines = 2) }
                        }
                    }
                }
            }
            val k = d.keyOf(it.current)
            if (k != null && (d.baseKeys.contains(k) || d.raw.defs.m[k] != null)) DictEntryBody(d, k)
            else Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Txt(e.wordText(it.current, 0, rom, place), sz(30f, FontWeight.SemiBold), T.glyph)
                if (it.current.codes != null) {
                    Txt(guessColored(e.wordPieces(it.current, 1, rom, place)).annotated(), lat(20f), T.greenInk)
                    Txt(guessColored(e.wordPieces(it.current, 2, rom, place)).annotated(), ff(FF.Body), T.purpleInk)
                }
                if (k != null && d.isUser(k)) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OwnChip(); Txt("你自己加的詞（不是教育部辭典的內容）。", ff(FF.Footnote), T.muted)
                } else {
                    Txt("字典裡沒有這個詞。", ff(FF.Footnote), T.muted)
                    val h = it.current.han
                    if (!h.isNullOrEmpty()) CapsuleButton("加到「自訂」", Icons.Filled.AddCircleOutline, true, T.own, T.ownEdge, T.ownInk) { addingOwn = true }
                }
            }
            Spacer(Modifier.height(60.dp))
        }
        if (addingOwn) AddOwnWordDialog(d, it.current.han ?: "", it.current.codes?.let { c -> d.codes(c.joinToString(" "), 1, -1) } ?: "") {
            addingOwn = false; ConvModel.run()
        }
    }
}

private val numDot = Regex("\\d+\\.\\s*")

/** a short meaning for a reading choice: its 華語 words, or the start of its definition */
private fun gloss(d: Dict, o: Opt): String? {
    val k = d.keyOf(o) ?: return null
    val pos = (d.raw.pos[k] ?: "").split("|").firstOrNull { it.isNotEmpty() } ?: ""
    val g = d.gl[k]
    val text = if (!g.isNullOrEmpty()) g.take(5).joinToString("、") { it.t }
        else d.defText(k)?.replace(numDot, "")?.replace("\n", "／") ?: return null
    return if (pos.isEmpty()) text else "〔$pos〕$text"
}

// MARK: - 選擇複製

/** a Discord style: how a line is wrapped (block = the whole text at once, lineStart = only in front) */
class CopyStyle(val name: String, val before: String, val after: String, val block: Boolean = false, val lineStart: Boolean = false)

val COPY_STYLES = listOf(
    CopyStyle("不加", "", ""),
    CopyStyle("**粗體**", "**", "**"),
    CopyStyle("*斜體*", "*", "*"),
    CopyStyle("***粗斜體***", "***", "***"),
    CopyStyle("__底線__", "__", "__"),
    CopyStyle("~~刪除線~~", "~~", "~~"),
    CopyStyle("||暗藏||", "||", "||"),
    CopyStyle("`程式碼`", "`", "`"),
    CopyStyle("```程式區塊```", "```\n", "\n```", block = true),
    CopyStyle("> 引用", "> ", "", lineStart = true),
    CopyStyle("# 大標題", "# ", "", lineStart = true),
    CopyStyle("## 標題", "## ", "", lineStart = true),
    CopyStyle("### 小標題", "### ", "", lineStart = true),
    CopyStyle("-# 小字", "-# ", "", lineStart = true),
)

fun copyWrap(text: String, i: Int): String {
    val st = COPY_STYLES[i.coerceIn(0, COPY_STYLES.size - 1)]
    if (st.block) return st.before + text + st.after
    // every line on its own, so the marks never run across a line break
    return text.split("\n").joinToString("\n") { line -> val t = line.trim(); if (t.isEmpty()) line else st.before + t + st.after }
}

fun copyOutput(texts: List<String>): String {
    val parts = ArrayList<String>()
    for (i in 0 until 3) {
        if (!Prefs.copyOn[i].value) continue
        val t = texts.getOrElse(i) { "" }.trim()
        if (t.isEmpty()) continue
        val si = Prefs.copyStyle[i].value
        val w = copyWrap(t, si)
        val p = Prefs.copyPreText[i].value.trim()
        val st = COPY_STYLES[si.coerceIn(0, COPY_STYLES.size - 1)]
        parts.add(if (p.isEmpty()) w else if (st.block || st.lineStart) p + "\n" + w else "$p $w")
    }
    return parts.joinToString(if (Prefs.copyGap.value) "\n\n" else "\n")
}

/** 選擇複製: pick which versions to copy, and a Discord style for each one (the text itself is wrapped in it) */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CopyOptionsSheet(texts: List<String>, names: List<String>, onDone: () -> Unit) {
    val ctx = LocalContext.current
    var done by remember { mutableStateOf(false) }
    LaunchedEffect(done) { if (done) { delay(700); onDone() } }
    ModalBottomSheet(onDismissRequest = onDone, containerColor = T.bg, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Txt("選擇複製", ff(FF.Headline))
            for (i in 0 until 3) {
                var on by Prefs.copyOn[i]
                var style by Prefs.copyStyle[i]
                var pre by Prefs.copyPreText[i]
                var menu by remember { mutableStateOf(false) }
                Column(Modifier.fillMaxWidth().surface(RoundedCornerShape(14.dp), width = 1.dp).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Txt("複製" + names[i], ff(FF.Body), T.glyph, Modifier.weight(1f))
                        Switch(on, { on = it }, colors = SwitchDefaults.colors(checkedTrackColor = T.greenEdge))
                    }
                    if (on) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Txt("格式", ff(FF.Body), T.muted, Modifier.weight(1f))
                            Box {
                                TextButton(onClick = { menu = true }) { Text(COPY_STYLES[style.coerceIn(0, COPY_STYLES.size - 1)].name, color = T.oliveInk) }
                                DropdownMenu(menu, { menu = false }, containerColor = T.fn) {
                                    COPY_STYLES.forEachIndexed { j, st ->
                                        DropdownMenuItem(text = { Text(st.name, color = T.glyph) },
                                            leadingIcon = { if (j == style) Icon(Icons.Filled.Check, null, tint = T.greenInk) else Spacer(Modifier.size(24.dp)) },
                                            onClick = { style = j; menu = false })
                                    }
                                }
                            }
                        }
                        val fPre = remember { androidx.compose.ui.focus.FocusRequester() }
                        OutlinedTextField(pre, { pre = it }, label = { Text("前面加") }, placeholder = { Text("（不加）") }, singleLine = true,
                            modifier = Modifier.fillMaxWidth().focusRequester(fPre), trailingIcon = { ClearIcon(pre, { pre = it }, fPre) })
                    }
                }
            }
            var gap by Prefs.copyGap
            Row(verticalAlignment = Alignment.CenterVertically) {
                Txt("段跟段中間空一行", ff(FF.Body), T.glyph, Modifier.weight(1f))
                Switch(gap, { gap = it }, colors = SwitchDefaults.colors(checkedTrackColor = T.greenEdge))
            }
            Txt("這些是 Discord 的格式：文字本身會被包起來，例如 **粗體**、||暗藏||、> 引用。", ff(FF.Caption), T.muted)
            val out = copyOutput(texts)
            Txt("預覽", ff(FF.Caption, FontWeight.Bold), T.muted)
            Txt(if (out.isEmpty()) "（沒有選任何一段）" else out, ff(FF.Footnote).copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace),
                if (out.isEmpty()) T.muted else T.glyph, Modifier.fillMaxWidth().surface(RoundedCornerShape(12.dp), width = 1.dp).padding(10.dp))
            ProminentButton(onClick = { copyText(ctx, out); done = true }, enabled = out.isNotEmpty(), modifier = Modifier.fillMaxWidth()) {
                IconLabel(if (done) Icons.Filled.Check else Icons.Filled.ContentCopy, if (done) "已複製" else "複製", ff(FF.Headline))
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}
