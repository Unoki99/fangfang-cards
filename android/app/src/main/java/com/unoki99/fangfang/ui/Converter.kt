package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.draw.drawBehind
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
        val r = e.convert(Prefs.convText.value)
        // (the 腔口 readings chosen stay with their words while you write)
        if (pins.isNotEmpty()) for (it in r.items) if (it.opts.isNotEmpty()) e.d.keyOf(it.current)?.let { k -> pins[k]?.let { o -> it.pinned = o } }
        result = r
        version++
    }

    /** 轉換: words said the way of one 腔口 (the word's key → that reading), and which 腔口 */
    private val pins = HashMap<String, Opt>()
    val pinPlace = HashMap<String, Int>()
    /** a word whose 字 were given 腔口 one by one: each 字's place (-1: 通行, -2: the place in 設定) */
    val sylPlace = HashMap<String, List<Int>>()

    /** item's word said the way place says it (-1: 通行) */
    fun pin(item: Int, place: Int) {
        val r = result
        if (item !in r.items.indices) return
        val it = r.items[item]
        val d = engine?.d ?: return
        val k = d.keyOf(it.current) ?: return
        val han = it.current.han ?: return
        // (a word put together from its 字: each 字 as the place says it)
        val codes = d.composedCodes(k, place) ?: d.codesFor(k, place)
        val o = Opt(han, codes.split(' ').filter { c -> c.isNotEmpty() }, parent = k,
            label = if (place < 0) null else d.raw.places.getOrNull(place)?.take(2), tokens = d.tokensFor(k, place, codes).joinToString(" "))
        sylPlace.remove(k)
        apply(d, k, o, place)
    }

    /** 轉換, one 字 of a word: syllable j of item's word said the way place says it (-1: 通行, -2: the place in
     *  設定, setting); the other 字 keep theirs. Every 字 the same place: the whole word's reading of that place */
    fun pinSyl(item: Int, j: Int, place: Int, setting: Int) {
        val r = result
        if (item !in r.items.indices) return
        val it = r.items[item]
        val d = engine?.d ?: return
        val k = d.keyOf(it.current) ?: return
        val han = it.current.han ?: return
        val n = d.sylCount(k)
        var ps = sylPlace[k]?.toMutableList() ?: MutableList(n) { pinPlace[k] ?: -2 }
        if (ps.size != n) ps = MutableList(n) { -2 }
        if (j !in ps.indices) return
        ps[j] = place
        if (ps.all { p -> p == -2 }) { unpin(item); return }
        val f = ps[0]
        if (f != -2 && ps.all { p -> p == f }) { pin(item, f); return }
        val codes = ps.indices.map { i -> d.sylAt(k, i, if (ps[i] == -2) setting else ps[i]).code }
        val o = Opt(han, codes, parent = k, label = null, tokens = d.tokensFor(k, -1, codes.joinToString(" ")).joinToString(" "))
        sylPlace[k] = ps
        apply(d, k, o, null)
    }

    /** (the reading put on every time the word comes in the text, those 腔口-picked before too) */
    private fun apply(d: Dict, k: String, o: Opt, place: Int?) {
        pins[k] = o
        if (place == null) pinPlace.remove(k) else pinPlace[k] = place
        for (x in result.items) if (x.opts.isNotEmpty() && (x.pinned?.parent == k || (x.pinned == null && d.keyOf(x.current) == k))) x.pinned = o
        version++
    }

    /** the 腔口 reading of item's word taken off (the place in 設定 again) */
    fun unpin(item: Int) {
        val r = result
        if (item !in r.items.indices) return
        val o = r.items[item].pinned ?: return
        val k = o.parent ?: return
        pins.remove(k); pinPlace.remove(k); sylPlace.remove(k)
        for (x in r.items) if (x.pinned?.parent == k) x.pinned = null
        version++
    }

    /** the word of item k in the text replaced by another (各地講法: 柑仔蜜 → 柑仔得); false: not a word typed in
     *  漢字, so not found in the text */
    fun replaceWord(k: Int, han: String): Boolean {
        val r = result
        if (k !in r.items.indices) return false
        val text = Prefs.convText.value
        var pos = 0
        for ((j, it) in r.items.withIndex()) {
            val h = if (it.src == "han" && it.opts.isNotEmpty()) it.current.han else null
            if (h.isNullOrEmpty()) { if (j == k) return false; continue }
            val at = text.indexOf(h, pos)
            if (at < 0) return false
            if (j == k) {
                Prefs.convText.value = text.substring(0, at) + han + text.substring(at + h.length)
                run()
                return true
            }
            pos = at + h.length
        }
        return false
    }

    fun choose(item: Int, opt: Int) {
        val r = result
        if (item !in r.items.indices) return
        if (r.items[item].pinned != null) unpin(item)
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
        TopBar(tr("轉換"))
        // 轉換, or 讀音 (a word in 台語, 華語 and 粵語 side by side)
        var tab by Prefs.convertTab
        Segmented(listOf(0 to tr("轉換"), 1 to tr("讀音")), tab, { tab = it }, Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
        Box(Modifier.weight(1f)) {
            if (tab == 1) ReadingsPane()
            else if (Store.isZh) ZhGate { z -> ZhConvertPane(z) }
            else DictGate { d -> ConvertPane(d) }
        }
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
    if (copySheet) CopyOptionsSheet(listOf(plain(0), plain(1), plain(2)), listOf(tr("漢字"), tr(ROM_NAMES[TwRom.lat(Prefs.rom.value)]), tr("方音"))) { copySheet = false }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth >= 820.dp
        val leftWidth = minOf(440.dp, maxWidth * 0.42f)
        @Composable fun input() {
            Box(Modifier.fillMaxWidth().surface()) {
                TextField(text, { text = it }, Modifier.fillMaxWidth().heightIn(min = 110.dp, max = 220.dp),
                    placeholder = { Text(tr("輸入或貼上漢字、皓羅、方音、台羅、白話字…"), color = T.muted) },
                    textStyle = TextStyle(fontSize = 18.sp, color = T.glyph),
                    colors = TextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
                        focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent, cursorColor = T.greenInk))
                Row(Modifier.align(Alignment.BottomEnd).padding(4.dp)) {
                    IconButton(onClick = {
                        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        cm.primaryClip?.getItemAt(0)?.coerceToText(ctx)?.toString()?.let { text = it }
                    }) { Icon(Icons.Filled.ContentPaste, tr("貼上"), tint = T.muted) }
                    if (text.isNotEmpty()) IconButton(onClick = { text = "" }) { Icon(Icons.Filled.Cancel, tr("清除"), tint = T.muted) }
                }
            }
            if (res.anyLatin) {
                val autoName = mapOf("lat" to tr("皓羅"), "tl" to tr("台羅"), "poj" to tr("白話字"))[res.autoLatin] ?: tr("皓羅")
                Txt(tr("羅馬字當作"), ff(FF.Caption), T.muted)
                Segmented(listOf("auto" to tr("自動（{0}）", autoName), "lat" to tr("皓羅"), "tl" to tr("台羅"), "poj" to tr("白話字")), latin, { Prefs.latin.value = it })
            }
        }
        @Composable fun help() {
            Txt(tr("例："), ff(FF.Footnote, FontWeight.Bold), T.muted)
            for (s in listOf("我欲去學校讀冊。", "Guá beh khì ha̍k-hāu tha̍k-tsheh.", "ㆣㄨㄚˋ ㄅㆤㆷ ㄎㄧˋ")) {
                SoftButton(onClick = { text = s }, modifier = Modifier.fillMaxWidth()) {
                    Text(s, style = if (s.first().code < 128) lat(16f) else ff(FF.Body), color = T.glyph, modifier = Modifier.weight(1f))
                }
            }
        }
        @Composable fun panels() {
            // (方音 only: no 羅馬字 panel, the 方音 one is it)
            for ((mode, title) in listOf(0 to tr("漢字"), 1 to tr(ROM_NAMES[TwRom.lat(Prefs.rom.value)]), 2 to tr("方音")).filter { !(it.first == 1 && TwRom.hongimOnly) }) {
                OutPanel(d, mode, title, copied == mode, onCopy = { copyText(ctx, plain(mode)); copied = mode }) { i -> focus.clearFocus(); UI.open(Sheet.ConvWord(i)) }
            }
        }
        @Composable fun actions() {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SoftButton(onClick = { copyText(ctx, listOf(plain(0), plain(1), plain(2)).joinToString("\n")); copied = 9 }, modifier = Modifier.weight(1f)) {
                    IconLabel(if (copied == 9) Icons.Filled.Check else Icons.Filled.ContentCopy, if (copied == 9) tr("已複製") else tr("全部複製"), ff(FF.Subheadline))
                }
                SoftButton(onClick = { copySheet = true }, modifier = Modifier.weight(1f)) {
                    IconLabel(Icons.Filled.Tune, tr("選擇複製…"), ff(FF.Subheadline))
                }
            }
            val keys = textKeys(d)
            if (keys.isNotEmpty()) {
                val newOnes = keys.filter { Store.cardStatus(it) == 0 }
                SoftButton(onClick = { Store.addUnknown(keys) }, enabled = newOnes.isNotEmpty(), modifier = Modifier.fillMaxWidth()) {
                    IconLabel(if (newOnes.isEmpty()) Icons.Filled.Star else Icons.Filled.StarBorder,
                        if (newOnes.isEmpty()) tr("這段的新詞都在卡片裡了") else tr("這段的新詞加到「不熟」（{0}）", newOnes.size), ff(FF.Subheadline))
                }
                val all = keys.all { Store.isSaved(it) }
                SoftButton(onClick = { Store.saveAll(keys) }, enabled = !all, modifier = Modifier.fillMaxWidth()) {
                    IconLabel(if (all) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                        if (all) tr("這段的詞都收藏了") else tr("收藏這段所有的詞（{0}）", keys.count { !Store.isSaved(it) }), ff(FF.Subheadline))
                }
            }
            // 選讀音的時候也選腔口: some say a word another place's way, whatever the place they speak
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.55f)).clickable { Prefs.convAnyPlace.value = !Prefs.convAnyPlace.value }
                .padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Column(Modifier.weight(1f)) {
                    Txt(tr("選讀音時也選腔口"), ff(FF.Subheadline), T.glyph)
                    Txt(tr("選了讀音以後，再選要用哪個地方的講法（不限設定的腔口）。"), ff(FF.Caption), T.muted)
                }
                Switch(Prefs.convAnyPlace.value, { Prefs.convAnyPlace.value = it })
            }
            Txt(tr("點詞可以看意思、換讀音、收藏、加到「不熟」。按住再滑過去，放開就打開那個詞。下面有彩色星星 = 已收藏或在「不熟」，藍色星星 = 收藏了這個詞的某個意思。橘色 = 字典裡找不到，或讀音不太確定（猜對的機會約 80% 以下），點一下可以確認。"),
                ff(FF.Caption), T.muted)
        }
        if (wide) Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Column(Modifier.width(leftWidth).fillMaxHeight().dragScrollY(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                input(); if (hasOutput) actions() else help()
            }
            Column(Modifier.weight(1f).fillMaxHeight().dragScrollY(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (hasOutput) panels() else Txt(tr("轉換的結果會出現在這裡。"), ff(FF.Body), T.muted, Modifier.padding(top = 40.dp))
            }
        } else Column(Modifier.fillMaxSize().dragScrollY(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
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
internal fun itemTones(d: Dict, items: List<ConvItem>, place: Int): Map<Int, Pair<List<String>, List<Int>>> {
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

private class OutWord(val text: AnnotatedString, val item: Int?, val newLine: Boolean, val mark: Int = 0, val say: Boolean = false)

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
            IconButton(onClick = onCopy) { Icon(if (copied) Icons.Filled.Check else Icons.Filled.ContentCopy, tr("複製"), tint = T.muted, modifier = Modifier.size(18.dp)) }
        }
        val style = if (mode == 1) lat(19f) else sz(if (mode == 0) 22f else 20f)
        TapWords(
            count = words.size,
            isTappable = { i -> i < words.size && (words[i].item ?: -1) >= 0 },
            newLine = { i -> i < words.size && words[i].newLine },
            onTap = { i -> words.getOrNull(i)?.item?.let { if (it >= 0) onOpen(it) } },
        ) { i, hot ->
            Box(Modifier.swell(hot), contentAlignment = Alignment.BottomCenter) {
                Text(words[i].text, style = style, color = ink, overflow = TextOverflow.Visible, modifier = Modifier.padding(vertical = 4.dp))
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
            // (no star under saved words any more: taken away on request)
            // (a choice of readings, or other places say it differently (各地講法): the same line)
            val deco = if (it.opts.size > 1 || it.current.han?.let { h -> d.sayingHans.contains(h) } == true) TextDecoration.Underline else null
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
        // (other places say it differently: 各地講法, a line of its own colour; not when it has readings to choose)
        val say = i != null && i >= 0 && res.items[i].opts.size <= 1 && res.items[i].current.han?.let { d.sayingHans.contains(it) } == true
        out.add(OutWord(text, i, newLine, mark, say))
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
        Txt(if (failed) tr("連不上鬥拍字") else if (ph == TaigiSpeech.Phase.IDLE) tr("唸出來") else tr("停"), ff(FF.Footnote, FontWeight.SemiBold), if (failed) T.rustInk else T.purpleInk)
    }
}

/** which 腔口's reading the word has: the one in 設定, one place, or each 字 its own (家 鹿港・內 通行) */
private fun placeName(d: Dict, p: Int): String =
    if (p == -2) tr("設定") else if (p < 0 || p >= d.raw.places.size) tr("通行") else tr(d.raw.places[p].take(2))

private fun pinText(d: Dict, it: ConvItem, pk: String): String {
    if (it.pinned == null) return tr("讀音：設定的腔口")
    val ps = ConvModel.sylPlace[pk] ?: return tr("讀音：{0}", placeName(d, ConvModel.pinPlace[pk] ?: -1))
    val hs = hanChars(Dict.hanOf(pk))
    val parts = ps.indices.map { i -> (hs.getOrNull(i) ?: "") + " " + placeName(d, ps[i]) }
    return tr("讀音：{0}", parts.joinToString("・"))
}

private fun hanChars(h: String): List<String> {
    val out = ArrayList<String>()
    var i = 0
    while (i < h.length) { val n = Character.charCount(h.codePointAt(i)); out.add(h.substring(i, i + n)); i += n }
    return out
}

/** the place lit in the window (a word whose 字 have places of their own: none, for the whole word) */
private fun pickedPlace(pk: String, j: Int, place: Int): Int {
    val ps = ConvModel.sylPlace[pk] ?: return ConvModel.pinPlace[pk] ?: place
    if (j < 0) return -99
    val p = ps.getOrNull(j) ?: return place
    return if (p == -2) place else p
}

/** 轉換's 選腔口的讀音: the 腔口 to pick, for the whole word or (a word of more than one 字) for one 字 of it */
@Composable
private fun PlacePickDialog(d: Dict, index: Int, k: String, han: String, onClose: () -> Unit) {
    ConvModel.version
    var sylPick by remember(k) { mutableStateOf(-1) }
    val split = d.canSplit(k)
    val hs = hanChars(Dict.hanOf(k))
    val j = if (split && sylPick < hs.size) sylPick else -1
    val place = Prefs.place.value
    val picked = pickedPlace(k, j, place)
    AlertDialog(onDismissRequest = onClose, containerColor = T.bg,
        title = { Txt(tr("「{0}」各地的讀音", han), ff(FF.Headline), T.glyph) },
        text = {
            Column(Modifier.dragScrollY(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (split) SylChips(hs, j) { i -> sylPick = i }
                Txt(if (j < 0) tr("點一個腔口，這段文字裡的這個詞就用那裡的講法。") else tr("點一個腔口，這個字就用那裡的讀音（別的字不變）。"), ff(FF.Footnote), T.muted)
                if (j < 0) TwPlaceRows(d, k, onPick = { p -> ConvModel.pin(index, p); onClose() }, picked = picked)
                else TwPlaceRows(d, k, onPick = { p -> ConvModel.pinSyl(index, j, p, place) }, picked = picked, syl = j)
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text(tr("完成"), color = T.btnInk) } })
}

/** 整個詞 and each 字 of the word, one of them picked */
@Composable
private fun SylChips(hs: List<String>, j: Int, onPick: (Int) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        SylChip(tr("整個詞"), j < 0, -1, onPick)
        for (i in hs.indices) SylChip(hs[i], j == i, i, onPick)
    }
}

@Composable
private fun SylChip(t: String, on: Boolean, i: Int, onPick: (Int) -> Unit) {
    Box(Modifier.clip(RoundedCornerShape(50)).background(if (on) T.twFill else T.fn.copy(alpha = 0.6f))
        .border(1.5.dp, if (on) T.twEdge else Color.Transparent, RoundedCornerShape(50))
        .clickable { onPick(i) }.hand().padding(horizontal = 12.dp, vertical = 5.dp)) {
        Txt(t, ff(FF.Subheadline, FontWeight.SemiBold), if (on) T.twInk else T.muted)
    }
}

/** a word in the converted text: pick the reading, see its dictionary entry */
@Composable
fun ConvWordSheet(d: Dict, index: Int) {
    val res = ConvModel.result
    ConvModel.version
    val rom = Prefs.rom.value; val place = Prefs.place.value
    var addingOwn by remember { mutableStateOf(false) }
    // (轉換's setting: after choosing a reading, which 腔口's way of saying it)
    var placePick by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { UI.closeSheet() }) { Text(tr("完成"), color = T.btnInk) }
            Spacer(Modifier.weight(1f))
            BarButtons(settings = false)
        }
        if (index !in res.items.indices) return@Column
        val it = res.items[index]
        val e = ConvModel.engine ?: return@Column
        Column(Modifier.fillMaxSize().dragScrollY(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            if (it.opts.size > 1) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Txt(tr("選讀音／漢字"), ff(FF.Caption, FontWeight.Bold), T.muted)
                    it.likely?.let { p -> Txt(tr("目前的讀音：猜對的機會約 {0}%", Math.round(p * 100)), ff(FF.Caption), if (it.unsure) Color(0xFFFF9F0A) else T.muted) }
                }
                for ((i, o) in it.opts.withIndex()) {
                    val on = i == it.sel
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(if (on) T.btn.copy(alpha = 0.6f) else T.fn.copy(alpha = 0.6f))
                        .clickable { ConvModel.choose(index, i); if (Prefs.convAnyPlace.value) placePick = true }.padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        RadioButton(on, { ConvModel.choose(index, i); if (Prefs.convAnyPlace.value) placePick = true }, colors = RadioButtonDefaults.colors(selectedColor = T.greenInk, unselectedColor = T.muted))
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
            // the 腔口 whose reading it has (轉換's setting on: choose another, for the whole word or one 字 of it;
            // a word with one reading too)
            val pk = d.keyOf(it.current)
            if (Prefs.convAnyPlace.value && pk != null && it.current.codes != null && d.raw.places.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Txt(pinText(d, it, pk), ff(FF.Footnote), T.muted)
                CapsuleButton(tr("選腔口的讀音"), Icons.Filled.Place, false, T.twFill, T.twEdge, T.twInk) { placePick = true }
                if (it.pinned != null) TextButton(onClick = { ConvModel.unpin(index) }) { Text(tr("用設定的腔口"), color = T.btnInk) }
            }
            it.current.han?.let { h -> Sayings(d, h, if (it.src == "han") index else -1) }
            val k = d.keyOf(it.current)
            if (k != null && (d.baseKeys.contains(k) || d.raw.defs.m[k] != null)) DictEntryBody(d, k)
            else Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Txt(e.wordText(it.current, 0, rom, place), sz(30f, FontWeight.SemiBold), T.glyph)
                if (it.current.codes != null) {
                    Txt(guessColored(e.wordPieces(it.current, 1, rom, place)).annotated(), lat(20f), T.greenInk)
                    Txt(guessColored(e.wordPieces(it.current, 2, rom, place)).annotated(), ff(FF.Body), T.purpleInk)
                }
                if (k != null && d.isUser(k)) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OwnChip(); Txt(tr("你自己加的詞（不是教育部辭典的內容）。"), ff(FF.Footnote), T.muted)
                } else {
                    Txt(tr("字典裡沒有這個詞。"), ff(FF.Footnote), T.muted)
                    val h = it.current.han
                    if (!h.isNullOrEmpty()) CapsuleButton(tr("加到「自訂」"), Icons.Filled.AddCircleOutline, true, T.own, T.ownEdge, T.ownInk) { addingOwn = true }
                }
            }
            Spacer(Modifier.height(60.dp))
        }
        if (placePick) {
            val k = d.keyOf(it.current)
            if (k == null || it.current.codes == null) placePick = false
            else PlacePickDialog(d, index, k, it.current.han ?: "") { placePick = false }
        }
        // (轉換's setting on: a word with one reading has nothing to choose first, so the 腔口 straight away)
        LaunchedEffect(index) {
            if (Prefs.convAnyPlace.value && it.opts.size <= 1 && it.current.codes != null && it.current.han != null && d.raw.places.isNotEmpty()) placePick = true
        }
        if (addingOwn) AddOwnWordDialog(d, it.current.han ?: "", it.current.codes?.let { c -> d.codes(c.joinToString(" "), 1, -1) } ?: "") {
            addingOwn = false; ConvModel.run()
        }
    }
}

private val numDot = Regex("\\d+\\.\\s*")

/** 各地講法: the words the places say for the same meaning, the usual ones first and each place's own after, each
 *  with where it's said and what it means (tap one for its entry) */
@Composable
private fun Sayings(d: Dict, han: String, swapItem: Int) {
    val groups = remember(han) { d.sayings(han) }
    if (groups.isEmpty()) return
    val rom = Prefs.rom.value; val place = Prefs.place.value
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Txt(tr("各地講法"), ff(FF.Caption, FontWeight.Bold), T.muted)
        for (g in groups) {
            if (groups.size > 1) Txt(tr("華語「{0}」", g.zh), ff(FF.Caption), T.muted)
            for ((k, ps) in g.words) {
                // (another word: tapped, it goes in the text in place of this one; its entry: the arrow)
                val swap = swapItem >= 0 && Dict.hanOf(k) != han
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.6f))
                    .clickable { if (swap) ConvModel.replaceWord(swapItem, Dict.hanOf(k)) else UI.openWord(k) }
                    .padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Txt(Dict.hanOf(k), sz(19f, FontWeight.SemiBold), if (Dict.hanOf(k) == han) T.greenInk else T.glyph)
                        Txt(d.wordText(k, TwRom.lat(rom), place).annotated(), lat(16f), T.greenInk, Modifier.weight(1f, fill = false), maxLines = 1)
                        Spacer(Modifier.weight(1f))
                        PlaceChip(if (ps.size >= 6) tr("多數地方") else d.placeNames(ps, 4))
                    }
                    glossKey(d, k, plain = d.raw.loc?.get(k) != null)?.let { t -> Txt(t, ff(FF.Footnote), T.glyph.copy(alpha = 0.75f), maxLines = 2) }
                    if (swap) Txt(tr("點一下換成這個講法"), ff(FF.Caption), T.muted)
                }
                if (swap) IconButton(onClick = { UI.openWord(k) }) { Icon(Icons.Filled.ChevronRight, tr("詞典"), tint = T.muted) }
                }
            }
        }
    }
}

/** a short meaning for a reading choice: its 華語 words, or the start of its definition */
private fun gloss(d: Dict, o: Opt): String? = d.keyOf(o)?.let { glossKey(d, it) }
/** plain: the definition, not the 華語 words (a 方言詞: 看「臭柿仔」…) */
private fun glossKey(d: Dict, k: String, plain: Boolean = false): String? {
    val pos = (d.raw.pos[k] ?: "").split("|").firstOrNull { it.isNotEmpty() } ?: ""
    val g = if (plain) null else d.gl[k]
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
        Column(Modifier.fillMaxWidth().dragScrollY(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Txt(tr("選擇複製"), ff(FF.Headline))
            for (i in 0 until 3) {
                var on by Prefs.copyOn[i]
                var style by Prefs.copyStyle[i]
                var pre by Prefs.copyPreText[i]
                var menu by remember { mutableStateOf(false) }
                Column(Modifier.fillMaxWidth().surface(RoundedCornerShape(14.dp), width = 1.dp).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Txt(tr("複製") + names[i], ff(FF.Body), T.glyph, Modifier.weight(1f))
                        Switch(on, { on = it }, colors = SwitchDefaults.colors(checkedTrackColor = T.btnEdge))
                    }
                    if (on) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Txt(tr("格式"), ff(FF.Body), T.muted, Modifier.weight(1f))
                            Box {
                                TextButton(onClick = { menu = true }) { Text(tr(COPY_STYLES[style.coerceIn(0, COPY_STYLES.size - 1)].name), color = T.oliveInk) }
                                DropdownMenu(menu, { menu = false }, containerColor = T.fn) {
                                    COPY_STYLES.forEachIndexed { j, st ->
                                        DropdownMenuItem(text = { Text(tr(st.name), color = T.glyph) },
                                            leadingIcon = { if (j == style) Icon(Icons.Filled.Check, null, tint = T.greenInk) else Spacer(Modifier.size(24.dp)) },
                                            onClick = { style = j; menu = false })
                                    }
                                }
                            }
                        }
                        val fPre = remember { androidx.compose.ui.focus.FocusRequester() }
                        OutlinedTextField(pre, { pre = it }, label = { Text(tr("前面加")) }, placeholder = { Text(tr("（不加）")) }, singleLine = true,
                            modifier = Modifier.fillMaxWidth().focusRequester(fPre), trailingIcon = { ClearIcon(pre, { pre = it }, fPre) })
                    }
                }
            }
            var gap by Prefs.copyGap
            Row(verticalAlignment = Alignment.CenterVertically) {
                Txt(tr("段跟段中間空一行"), ff(FF.Body), T.glyph, Modifier.weight(1f))
                Switch(gap, { gap = it }, colors = SwitchDefaults.colors(checkedTrackColor = T.btnEdge))
            }
            Txt(tr("這些是 Discord 的格式：文字本身會被包起來，例如 **粗體**、||暗藏||、> 引用。"), ff(FF.Caption), T.muted)
            val out = copyOutput(texts)
            Txt(tr("預覽"), ff(FF.Caption, FontWeight.Bold), T.muted)
            Txt(if (out.isEmpty()) tr("（沒有選任何一段）") else out, ff(FF.Footnote).copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace),
                if (out.isEmpty()) T.muted else T.glyph, Modifier.fillMaxWidth().surface(RoundedCornerShape(12.dp), width = 1.dp).padding(10.dp))
            ProminentButton(onClick = { copyText(ctx, out); done = true }, enabled = out.isNotEmpty(), modifier = Modifier.fillMaxWidth()) {
                IconLabel(if (done) Icons.Filled.Check else Icons.Filled.ContentCopy, if (done) tr("已複製") else tr("複製"), ff(FF.Headline))
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}
