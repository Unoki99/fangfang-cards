package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import com.unoki99.fangfang.UILang
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import kotlin.math.*

// MARK: - 華語: 詞典 and 轉換

private val ZH_PLACE_FILL = Color(0xFF4C3A5B)
private val ZH_PLACE_EDGE = Color(0xFF7B3C9B)

@Composable
private fun zhKey(): List<Any> = listOf(Prefs.zhRom.value, Prefs.zhPlace.value, Prefs.toneSys.value, Prefs.toneGlow.value, Prefs.theme.value)

/** 詞典 in 華語 mode: 查詞 / 收藏 */
@Composable
fun ZhDictionaryTab() {
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("詞典"))
        ZhGate { z ->
            var tab by Prefs.zhDictTab
            Column(Modifier.fillMaxSize()) {
                Segmented(listOf(0 to tr("查詞"), 1 to tr("收藏")), tab, { tab = it }, Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                Box(Modifier.weight(1f)) { if (tab == 1) ZhSavedPane(z) else ZhLookupPane(z) }
            }
        }
    }
}

// MARK: 查詞

@Composable
private fun ZhLookupPane(z: ZhDict) {
    var query by Prefs.zhLookupQuery
    val place = Prefs.zhPlace.value
    var found by remember { mutableStateOf(ZhDict.Found()) }
    LaunchedEffect(query, place) {
        delay(200)
        val q = query
        found = withContext(Dispatchers.Default) { z.search(q, place) }
    }
    val f = found
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
        item {
            val nav = LocalNav.current
            SearchField(query, { query = it }, tr("漢字、拼音、注音、英文或聲調，例如：吃飯、人*、chifan、eat、1-4"))
            Spacer(Modifier.height(8.dp))
            TileGrid(3) { i, m ->
                when (i) {
                    0 -> TileButton(Icons.AutoMirrored.Filled.List, tr("依詞類列出"), m) { nav.push(Route.ZhClasses) }
                    1 -> TileButton(Icons.Filled.VerticalSplit, tr("單詞比較"), m) { nav.push(Route.ZhCompare) }
                    else -> TileButton(Icons.Filled.GridView, tr("部首查字"), m) { nav.push(Route.Radicals(true)) }
                }
            }
        }
        if (query.isEmpty()) item {
            Txt(tr("可以查漢字（正體或簡體）、拼音（聲調可以不打，或用數字：chi1fan4）、注音或英文（eat、computer）。\n* 代表一個以上的字，? 代表剛好一個字：\n人* → 人開頭的詞　*子 → 子結尾　*水* → 水在中間　?子 → 兩個字、子結尾\n打聲調數字找聲調組合：1-4、3 3、2 0（0 或 5 = 輕聲）。\n讀音照上面選的「臺灣／大陸」和「拼音／注音」顯示。\n往右滑一個詞加到「不熟」，往左滑收藏。"),
                ff(FF.Footnote), T.muted, Modifier.padding(8.dp))
        } else if (f.empty) item { Txt(tr("找不到「{0}」。", query), ff(FF.Body), T.muted, Modifier.padding(8.dp)) }
        zhItems(z, tr("聲調「{0}」（{1}）", f.toneLabel, if (f.tones.size >= 500) "500+" else f.tones.size.toString()), f.tones)
        zhItems(z, "「$query」", f.words)
        for ((i, w) in f.parts.withIndex()) zhItems(z, "「$w」", f.partWords[i])
        zhItems(z, tr("開頭是「{0}」", query), f.starts)
        zhItems(z, tr("英文「{0}」", query), f.english, english = true)
        zhItems(z, tr("裡面有「{0}」", query), f.contains)
        zhItems(z, tr("解釋裡有「{0}」", query), f.defs)
        item { Spacer(Modifier.height(40.dp)) }
    }
}

/** 華語 words in a list (swipe right = 加到不熟, left = 收藏) */
private fun LazyListScope.zhItems(z: ZhDict, title: String, list: List<Int>, english: Boolean = false) {
    if (list.isEmpty()) return
    item { SectionTitle(title) }
    items(list.take(if (english) 250 else 500), key = { "z|$title|$it" }) { i ->
        val nav = LocalNav.current
        val e = z.entries[i]
        Store.rev
        Box(Modifier.clip(RoundedCornerShape(10.dp)).padding(vertical = 1.dp)) {
            SwipeRow(
                start = if (Store.cardStatus(e.k) != 1) Pair(if (Store.cardStatus(e.k) == 2) tr("移回新詞") else tr("加到不熟"), T.rustEdge) else null,
                end = Pair(if (Store.isSaved(e.k)) tr("取消收藏") else tr("收藏"), T.oliveEdge),
                onStart = { Store.toggleUnknown(e.k) }, onEnd = { Store.toggleSaved(e.k) },
                onClick = { nav.push(Route.ZhEntry(e.k)) },
            ) { ZhWordRow(z, e, english) }
        }
    }
}

/** a word in a list: 漢字, reading, first meaning */
@Composable
fun ZhWordRow(z: ZhDict, e: ZhEntry, english: Boolean = false, meanings: Int = 1) {
    val zk = zhKey()
    val place = Prefs.zhPlace.value; val rom = Prefs.zhRom.value; val list = Prefs.zhList.value
    Store.rev
    Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Txt(remember(e.k, zk) { z.hanText(e.h, e.syl(place), T.glyph.argbInt()).annotated() }, sz(20f, FontWeight.SemiBold))
            Txt(remember(e.k, zk) { z.reading(e.syl(place), rom).annotated() }, lat(16f), T.greenInk, Modifier.weight(1f, fill = false), maxLines = 1)
            if (e.spec != 0) ZhSpecChip(e.spec)
            if (e.level(list) > 0) Txt(UILang.label(Lang.levelName(list, e.level(list))), ff(FF.Caption2, FontWeight.Bold), T.greenInk)
            Spacer(Modifier.weight(0.01f))
            if (Store.isSaved(e.k)) Icon(Icons.Filled.Bookmark, null, tint = T.oliveInk, modifier = Modifier.size(14.dp))
            if (Store.cardStatus(e.k) == 2) Icon(Icons.Filled.Star, null, tint = T.rustInk, modifier = Modifier.size(14.dp))
        }
        // found by its English meaning, or 設定 → 主要解釋: English
        val en = if (e.en != null) e.enList.take(3).joinToString("; ") else null
        if (meanings > 1) {
            // 1–2 meanings, one a line (手寫練習's words)
            val useEn = ((english || Prefs.zhEnglish.value) && en != null) || e.senses.isEmpty()
            val ms = if (useEn) e.enList.take(meanings) else e.senses.take(meanings).map { it.text }
            for ((i, m) in ms.withIndex()) Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (ms.size > 1) Txt("${i + 1}.", ff(FF.Caption, FontWeight.Bold), T.muted)
                Txt(m, ff(FF.Footnote), T.muted, maxLines = 2)
            }
        } else {
            val m = if ((english || Prefs.zhEnglish.value) && en != null) en else e.senses.firstOrNull()?.text ?: en
            if (m != null) Txt(m, ff(FF.Footnote), T.muted, maxLines = 2)
        }
    }
}

@Composable
fun ZhSpecChip(spec: Int) = Chip(if (spec == 1) tr("臺灣用語") else tr("大陸用語"), ZH_PLACE_FILL, ZH_PLACE_EDGE, T.purpleInk)

// MARK: one entry

@Composable
fun ZhEntryPage(z: ZhDict, key: String, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        TopBar(z.entry(key)?.h ?: "", onBack, settings = false)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
            val e = z.entry(key)
            if (e != null) ZhEntryBody(z, e) else Txt(tr("找不到這個詞。"), ff(FF.Body), T.muted)
            Spacer(Modifier.height(40.dp))
        }
    }
}

/** a 華語 entry in the sheet from the bottom */
@Composable
fun ZhEntrySheetRoot(z: ZhDict, key: String) {
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { UI.closeSheet() }) { Text(tr("完成"), color = T.btnInk) }
            Spacer(Modifier.weight(1f))
            BarButtons(settings = false)
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            val e = z.entry(key)
            if (e != null) ZhEntryBody(z, e) else Txt(tr("找不到這個詞。"), ff(FF.Body), T.muted)
            Spacer(Modifier.height(60.dp))
        }
    }
}

/** for each character of the headword: the single-character entry read the way this word reads it */
private fun zhCharKeys(z: ZhDict, e: ZhEntry, syl: List<String>): List<String?> {
    val out = ArrayList<String?>()
    var n = 0
    for (ch in e.h.cps()) {
        if (!Zhuyin.isHan(ch.firstCp())) { out.add(null); continue }
        val i = n; n++
        if (i >= syl.size || syl[i] == "-") { out.add(null); continue }
        val s = syl[i]
        val hit = (z.byHan[ch] ?: emptyList<Int>()).map { z.entries[it] }
            .firstOrNull { it.h == ch && it.k != e.k && (it.tw.firstOrNull() == s || it.lu?.firstOrNull() == s || (i < e.tw.size && it.tw.firstOrNull() == e.tw[i])) }
        out.add(hit?.k)
    }
    return out
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ZhEntryBody(z: ZhDict, e: ZhEntry) {
    val nav = LocalNav.current
    val zk = zhKey()
    val place = Prefs.zhPlace.value; val rom = Prefs.zhRom.value
    val syl = e.syl(place)
    Store.rev
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                // tap a character to see it on its own (the entry with the same reading)
                val h = remember(e.k, zk) { z.hanText(e.h, syl, T.glyph.argbInt()).annotated() }
                TappableHeadword(h, remember(e.k, place) { zhCharKeys(z, e, syl) }) { k -> nav.push(Route.ZhEntry(k)) }
                PlayButton("tts:" + e.h)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val on = Store.isSaved(e.k)
                CapsuleButton(if (on) tr("已收藏") else tr("收藏"), if (on) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder, on,
                    T.olive, T.oliveEdge, T.oliveInk) { Store.toggleSaved(e.k) }
                val st = Store.cardStatus(e.k) ?: 0
                if (st == 1) Chip(tr("卡片：熟悉"), T.green, T.greenEdge, T.greenInk)
                else CapsuleButton(if (st == 2) tr("在「不熟」") else tr("加到「不熟」"), if (st == 2) Icons.Filled.Star else Icons.Filled.StarBorder,
                    st == 2, T.rust, T.rustEdge, T.rustInk) { Store.toggleUnknown(e.k) }
            }
            Txt(remember(e.k, zk) { z.reading(syl, rom).annotated() }, lat(22f), T.greenInk)
            // the other reading system, small
            Txt(remember(e.k, zk) { z.reading(syl, if (rom == 0) 1 else 0).annotated() }, ff(FF.Subheadline), T.purpleInk)
            // 臺灣 and 大陸 say it differently
            e.lu?.let { lu ->
                val other = if (place == 1) e.tw else lu
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Chip(if (place == 1) tr("臺灣") else tr("大陸"), ZH_PLACE_FILL, ZH_PLACE_EDGE, T.purpleInk)
                    Txt(z.reading(other, rom).annotated(), lat(17f), T.greenInk)
                    Txt(z.reading(other, if (rom == 0) 1 else 0).annotated(), ff(FF.Footnote), T.purpleInk)
                }
            }
            InputCodesRow(e.h)
            // the English meanings, one per line
            if (e.enList.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Chip(tr("英"), T.fn, T.fnEdge, T.muted)
                EnglishList(e.enList)
            }
            // 詞類: tap one for the words of that class
            if (e.pos.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (p in e.pos) Box(Modifier.clip(RoundedCornerShape(6.dp)).clickable { nav.push(Route.ZhClass(p)) }) { Chip(p, T.fn, T.fnEdge, T.muted) }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (e.hsk > 0) Chip(Lang.hskName(e.hsk), T.green, T.greenEdge, T.greenInk)
                if (e.tocfl > 0) Chip(UILang.label(Lang.levelName(1, e.tocfl)), T.blue, T.blueEdge, T.blueInk)
                if (e.spec != 0) ZhSpecChip(e.spec)
                val a = e.alt
                if (a != null && a != e.h) { Chip(tr("簡"), T.fn, T.fnEdge, T.muted); Txt(a, ff(FF.Subheadline), T.glyph.copy(alpha = 0.85f)) }
            }
        }
        // the same 漢字 read another way
        val others = remember(e.k) { z.others(e) }
        if (others.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chip(tr("又讀"), T.fn, T.fnEdge, T.muted)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (o in others) Txt(z.reading(o.syl(place), rom).annotated(), lat(15f), T.greenInk,
                    Modifier.clip(CircleShape).background(T.fn.copy(alpha = 0.8f)).clickable { nav.push(Route.ZhEntry(o.k)) }.padding(horizontal = 8.dp, vertical = 3.dp))
            }
        }
        for (s in e.senses) {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.55f)).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Txt("${s.n}.", ff(FF.Subheadline, FontWeight.Bold), T.muted)
                    Txt(s.text, ff(FF.Body), T.glyph, Modifier.weight(1f))
                    CopyIconButton {
                        SenseCopy.zhText(z, e.k, s.n - 1, Prefs.zhRom.value, Prefs.zhPlace.value, Prefs.zhCopyTpl.value, Prefs.zhCopyEx.value, Prefs.zhCopySep.value)
                    }
                    SenseSaveButton(SavedSense(e.k, s.n - 1))
                }
                for (x in s.ex) Box(Modifier.padding(start = 18.dp)) { ZhExampleBlock(z, x) }
            }
        }
        // 近義詞 / 反義詞 (《重編國語辭典修訂本》), the ones this dictionary has
        val syn = remember(e.k) { e.syn.mapNotNull { z.usualEntry(it) } }
        val ant = remember(e.k) { e.ant.mapNotNull { z.usualEntry(it) } }
        if (syn.isNotEmpty() || ant.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            ZhLinks(z, tr("近"), syn, T.blue, T.blueEdge, T.blueInk)
            ZhLinks(z, tr("反"), ant, T.rust, T.rustEdge, T.rustInk)
        }
        if (e.extra) Txt(tr("這個詞表裡的詞《兩岸常用詞典》裡沒有：讀音用 CC-CEDICT 的（有臺灣讀音的話用臺灣的），沒有的話照組成它的詞推算；意思用 CC-CEDICT 的英文解釋。"),
            ff(FF.Caption), T.muted)
        Txt(tr("資料：中華文化總會《兩岸常用詞典》（CC BY-NC-ND）。拼音依注音照規則轉寫；例句的讀音依詞典的詞推算，可能有誤。"), ff(FF.Caption2), T.muted)
        // 《重編國語辭典修訂本》 always at the very bottom. A single character: its meanings in 教育部《重編國語辭典修訂本》 too (the reading this entry has)
        val ci = if (e.h.cpCount == 1) z.charIndex[e.h] else null
        val reading = ci?.let { z.chars[it].readings.firstOrNull { r -> r.zy == e.tw.firstOrNull() } }
        if (reading != null) {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.4f)).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Txt(tr("《重編國語辭典修訂本》"), ff(FF.Caption, FontWeight.Bold), T.muted)
                for ((n, d) in reading.defs.withIndex()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Txt("${n + 1}.", ff(FF.Subheadline, FontWeight.Bold), T.muted)
                    if (d.first.isNotEmpty()) Chip(d.first, T.fn, T.fnEdge, T.muted)
                    Txt(d.second, ff(FF.Body), T.glyph, Modifier.weight(1f))
                }
            }
        }
        if (reading != null) Txt(tr("資料：教育部《重編國語辭典修訂本》（CC BY-ND 3.0 TW），g0v 萌典整理。只收字的解釋和用例，引用的古書省略。"), ff(FF.Caption2), T.muted)
    }
}

/** an example sentence: 漢字 (tap a word to see it in the dictionary; the whole word is the button), reading, where it's from; ▶ reads it aloud */
@Composable
fun ZhExampleBlock(z: ZhDict, ex: ZhEx) {
    val zk = zhKey()
    val place = Prefs.zhPlace.value; val rom = Prefs.zhRom.value
    val gap = Prefs.wordGap.value
    val ps = remember(ex) { ZhDict.pieces(ex) }
    val texts = remember(ex, zk) { ps.map { z.sentenceHan(listOf(it), place, T.blueInk.argbInt()).annotated() } }
    val targets = remember(ex, place) { ps.map { p -> if (p.tw != null) z.entryFor(p)?.k else null } }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        PlayButton("tts:" + ex.h, 28.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            // the same as the 台語 sentences: each word its own taller box (a bigger place to tap), a little apart
            TapWords(
                count = ps.size, lineSpacing = (-4).dp,
                isTappable = { i -> targets.getOrNull(i) != null },
                onTap = { i -> targets.getOrNull(i)?.let { UI.open(Sheet.ZhWord(it)) } },
            ) { i, hot ->
                Text(texts[i], style = ff(FF.Body), modifier = Modifier.swell(hot).padding(horizontal = if (gap) 2.5.dp else 0.dp, vertical = 7.dp))
            }
            Txt(remember(ex, zk) { z.sentence(ps, rom, place).annotated() }, lat(15f), T.greenInk)
            if (ex.src.isNotEmpty()) Txt(ex.src, ff(FF.Caption), T.muted)
        }
    }
}

// MARK: 收藏

@Composable
private fun ZhSavedPane(z: ZhDict) {
    val nav = LocalNav.current
    val ctx = LocalContext.current
    val zk = zhKey()
    val keys = Store.savedKeys
    val senses = Store.savedSenses
    var pending by remember { mutableStateOf("") }
    val saveCsv = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri -> writeTo(ctx, uri, pending) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
        if (keys.isEmpty() && senses.isEmpty()) item {
            Txt(tr("在詞典裡按「收藏」或意思旁邊的書籤，詞和意思會出現在這裡。"), ff(FF.Footnote), T.muted, Modifier.padding(8.dp))
        } else item {
            SoftButton(onClick = { pending = Store.zhSavedCSV(z); saveCsv.launch("方方-華語收藏.csv") }) {
                IconLabel(Icons.Filled.IosShare, tr("匯出 CSV"), ff(FF.Subheadline), T.oliveInk)
            }
            Txt(tr("詞、拼音（聲調用數字，音節中間空一格）、意思（有英文的話用英文）、例句（例句中間空一行）。"), ff(FF.Caption), T.muted, Modifier.padding(6.dp))
        }
        if (keys.isNotEmpty()) item { SectionTitle(tr("{0} 個詞（往左滑刪除）", keys.size)) }
        items(keys, key = { "zs|$it" }) { k ->
            val e = z.entry(k)
            if (e != null) {
                SwipeRow(start = null, end = Pair(tr("刪除"), Color(0xFFB3261E)), onEnd = { Store.toggleSaved(k) }, onClick = { nav.push(Route.ZhEntry(k)) }) {
                    ZhWordRow(z, e)
                }
                RowDivider()
            }
        }
        if (senses.isNotEmpty()) item { SectionTitle(tr("{0} 個意思（往左滑刪除）", senses.size)) }
        items(senses, key = { "zm|" + it.id }) { s ->
            val e = z.entry(s.key)
            if (e != null && s.sense < e.senses.size) {
                val m = e.senses[s.sense]
                SwipeRow(start = null, end = Pair(tr("刪除"), Color(0xFFB3261E)), onEnd = { Store.unsave(s) }, onClick = { nav.push(Route.ZhEntry(s.key)) }) {
                    Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Txt(remember(e.k, zk) { z.hanText(e.h, e.syl(Prefs.zhPlace.value), T.glyph.argbInt()).annotated() }, sz(20f, FontWeight.SemiBold))
                            Txt(remember(e.k, zk) { z.reading(e.syl(Prefs.zhPlace.value), Prefs.zhRom.value).annotated() }, lat(16f), T.greenInk, Modifier.weight(1f), maxLines = 1)
                            CopyIconButton {
                                SenseCopy.zhText(z, s.key, s.sense, Prefs.zhRom.value, Prefs.zhPlace.value, Prefs.zhCopyTpl.value, Prefs.zhCopyEx.value, Prefs.zhCopySep.value)
                            }
                            Icon(Icons.Filled.Bookmark, null, tint = T.blueInk, modifier = Modifier.size(14.dp))
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Txt("${m.n}.", ff(FF.Footnote, FontWeight.Bold), T.muted)
                            Txt(m.text, ff(FF.Footnote), T.glyph, maxLines = 3)
                        }
                    }
                }
                RowDivider()
            }
        }
        item { Spacer(Modifier.height(40.dp)) }
    }
}

// MARK: - 轉換 (華語)

/** 華語 text → 拼音 / 注音, in tone colours; the readings are the dictionary's (most common reading of each word) */
@Composable
fun ZhConvertPane(z: ZhDict) {
    val ctx = LocalContext.current
    val focus = LocalFocusManager.current
    var text by Prefs.zhConvText
    val zk = zhKey()
    val place = Prefs.zhPlace.value
    var pieces by remember { mutableStateOf<List<ZhPiece>>(emptyList()) }
    var copied by remember { mutableIntStateOf(-1) }
    var copySheet by remember { mutableStateOf(false) }
    LaunchedEffect(copied) { if (copied >= 0) { delay(1200); copied = -1 } }
    LaunchedEffect(text) {
        delay(150)
        val t = text
        // line by line, so line breaks stay
        pieces = withContext(Dispatchers.Default) {
            val out = ArrayList<ZhPiece>()
            for ((i, line) in t.split("\n").withIndex()) {
                if (i > 0) out.add(ZhPiece(listOf("\n"), null, null))
                out.addAll(z.convertPieces(line))
            }
            out
        }
    }
    fun plain(i: Int): String = when (i) {
        0 -> text
        1 -> z.sentence(pieces, 0, place, colours = 0).plain()
        else -> z.sentence(pieces, 1, place, colours = 0).plain()
    }
    if (copySheet) CopyOptionsSheet(listOf(plain(0), plain(1), plain(2)), listOf(tr("漢字"), tr("拼音"), tr("注音"))) { copySheet = false }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.fillMaxWidth().surface()) {
            TextField(text, { text = it }, Modifier.fillMaxWidth().heightIn(min = 110.dp, max = 220.dp),
                placeholder = { Text(tr("輸入或貼上華語（正體或簡體都可以）…"), color = T.muted) },
                textStyle = TextStyle(fontSize = 18.sp, color = T.glyph),
                colors = TextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
                    focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent, cursorColor = T.greenInk))
            if (text.isNotEmpty()) IconButton(onClick = { text = "" }, Modifier.align(Alignment.BottomEnd)) { Icon(Icons.Filled.Cancel, tr("清除"), tint = T.muted) }
        }
        if (pieces.isNotEmpty()) {
            for ((i, title) in listOf(0 to tr("漢字"), 1 to tr("拼音"), 2 to tr("注音"))) {
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.55f)).padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Txt(title, ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.weight(1f))
                        if (i == 0) PlayButton("tts:$text", 28.dp)
                        IconButton(onClick = { copyToClipboard(ctx, plain(i)); copied = i }) {
                            Icon(if (copied == i) Icons.Filled.Check else Icons.Filled.ContentCopy, tr("複製"), tint = T.muted, modifier = Modifier.size(18.dp))
                        }
                    }
                    if (i == 0) {
                        // the 漢字: each word can be tapped to see it (it swells while pressed; hold and slide to open the word under the finger)
                        class W(val text: androidx.compose.ui.text.AnnotatedString, val key: String?, val newLine: Boolean)
                        val words = remember(pieces, zk) {
                            val out = ArrayList<W>(); var nl = false
                            for (p in pieces) {
                                if (p.text == listOf("\n")) { nl = true; continue }
                                out.add(W(z.sentenceHan(listOf(p), place, T.glyph.argbInt()).annotated(), if (p.tw != null) z.entryFor(p)?.k else null, nl))
                                nl = false
                            }
                            out
                        }
                        TapWords(count = words.size, isTappable = { j -> words.getOrNull(j)?.key != null },
                            newLine = { j -> words.getOrNull(j)?.newLine == true },
                            onTap = { j -> words.getOrNull(j)?.key?.let { focus.clearFocus(); UI.open(Sheet.ZhWord(it)) } }) { j, hot ->
                            Text(words[j].text, style = ff(FF.Title3), modifier = Modifier.swell(hot).padding(vertical = 3.dp))
                        }
                    } else {
                        val a = remember(pieces, zk, i) { (if (i == 1) z.sentence(pieces, 0, place) else z.sentence(pieces, 1, place)).annotated() }
                        Txt(a, if (i == 1) lat(17f) else ff(FF.Body), if (i == 1) T.greenInk else T.purpleInk)
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SoftButton(onClick = { focus.clearFocus(); copyToClipboard(ctx, listOf(plain(0), plain(1), plain(2)).joinToString("\n")); copied = 9 }, Modifier.weight(1f)) {
                    IconLabel(if (copied == 9) Icons.Filled.Check else Icons.Filled.ContentCopy, if (copied == 9) tr("已複製") else tr("全部複製"), ff(FF.Subheadline))
                }
                SoftButton(onClick = { focus.clearFocus(); copySheet = true }, Modifier.weight(1f)) { IconLabel(Icons.Filled.Tune, tr("選擇複製…"), ff(FF.Subheadline)) }
            }
            Txt(tr("讀音照詞典裡最常見的唸法，一字多音的地方可能會錯。上面可以切換臺灣／大陸讀音。"), ff(FF.Caption), T.muted)
        }
        Spacer(Modifier.height(40.dp))
    }
}

// MARK: - HSK / TOCFL progress

/** the colour of a word list level: red, orange, yellow, green, green-blue, blue, purple, pink */
fun levelColor(level0: Int): Color {
    // character cards (100 + level): the colour of the same level; 台語 常用 groups: the colours in turn
    val level = if (Lang.isFreqTopic(level0)) (level0 % Lang.freqWordBase) % 8 + 1
        else if (level0 > Lang.charTopicBase) level0 - Lang.charTopicBase else level0
    val colors = listOf(0xFF5C5C, 0xFF9A3C, 0xFFD84A, 0x6FDC7F, 0x3FD6C6, 0x4F8DFF, 0xA66BFF, 0xFF7AC6)
    return hex(colors[(level - 1).coerceIn(0, colors.size - 1)].toLong())
}

/** One glass tube with two potions: 熟悉 from the left in the level's colour, 不熟 from the right in a pale one; the glass between is what hasn't been seen yet */
@Composable
fun SplitPotionBar(known: Double, unknown: Double, tint: Color, height: Dp = 24.dp, label: String = tr("進度"), modifier: Modifier = Modifier) {
    val k = remember { Animatable(0f) }
    val u = remember { Animatable(0f) }
    LaunchedEffect(known) { k.animateTo(known.toFloat(), spring(dampingRatio = 0.62f, stiffness = 60f)) }
    LaunchedEffect(unknown) { u.animateTo(unknown.toFloat(), spring(dampingRatio = 0.62f, stiffness = 60f)) }
    var time by remember { mutableFloatStateOf(0f) }
    val moving = Prefs.themeMotion.value
    LaunchedEffect(moving) {
        if (!moving) return@LaunchedEffect
        val start = withFrameNanos { it }
        while (isActive) withFrameNanos { time = (it - start) / 1e9f }
    }
    Canvas(modifier.fillMaxWidth().padding(vertical = 5.dp).height(height)
        .semantics { contentDescription = tr("{0} 熟悉 {1}%，不熟 {2}%", label, (known * 100).roundToInt(), (unknown * 100).roundToInt()) }) {
        val w = size.width; val h = size.height
        val tube = Path().apply { addRoundRect(RoundRect(0f, 0f, w, h, CornerRadius(h / 2, h / 2))) }
        val kv = k.value.coerceIn(0f, 1.05f); val uv = u.value.coerceIn(0f, 1.05f)
        val kEdge = if (kv > 0.001f) max(w * min(kv, 1f), 8f) else 0f
        val uEdge = if (uv > 0.001f) max(w * min(uv, 1f), 8f) else 0f
        clipPath(tube) {
            drawRect(Color.Black.copy(alpha = 0.35f))
            side(kEdge, true, Brush.horizontalGradient(listOf(tint.copy(alpha = 0.7f), tint), 0f, w), 0f, time)
            side(uEdge, false, Brush.horizontalGradient(listOf(tint.copy(alpha = 0.22f), tint.copy(alpha = 0.35f)), 0f, w), 1.7f, time)
        }
        drawPath(tube, Color.White.copy(alpha = 0.28f), style = Stroke(1.5f * density))
        drawRoundRect(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.35f), Color.Transparent), startY = 3f, endY = 3f + 6 * density),
            Offset(10 * density, 3 * density), Size(w - 20 * density, 6 * density), CornerRadius(3 * density))
    }
}

private fun DrawScope.side(edge: Float, fromLeft: Boolean, brush: Brush, seed: Float, t: Float) {
    if (edge <= 0f) return
    val w = size.width; val h = size.height
    val p = Path()
    val amp = if (edge >= w - 1) 0f else 2.5f * density
    val x0 = if (fromLeft) 0f else w
    p.moveTo(x0, 0f)
    var y = 0f
    while (y <= h) {
        val wob = sin(y / h * PI * 2 + t * 3.2 + seed).toFloat() * amp + sin(y / h * PI * 5 - t * 4.7 + seed).toFloat() * amp * 0.35f
        p.lineTo(if (fromLeft) edge + wob else w - edge - wob, y)
        y += 2f
    }
    p.lineTo(x0, h); p.close()
    drawPath(p, brush)
    clipPath(p) {
        drawRect(Color.White.copy(alpha = 0.16f), Offset.Zero, Size(w, h * 0.32f))
        drawRect(Color.Black.copy(alpha = 0.14f), Offset(0f, h * 0.72f), Size(w, h * 0.28f))
        for (i in 0 until 12) {
            val s = i + seed * 10.0
            fun frac(v: Double) = v - floor(v)
            val fx = frac(sin(s * 12.9898) * 43758.5453)
            val fs = frac(sin(s * 78.233) * 12345.678)
            val phase = frac(t * (0.18 + fs * 0.35) + fx * 3.1)
            val off = 5 + fx * max(edge - 10.0, 1.0)
            val bx = ((if (fromLeft) off else w - off) + sin(t * 2 + s) * 1.5).toFloat()
            val by = (h * (1.05 - phase * 1.1)).toFloat()
            val r = ((0.9 + fs * 1.6) * density / 2).toFloat()
            drawCircle(Color.White.copy(alpha = (0.6 * sin(phase * PI)).toFloat().coerceIn(0f, 1f)), r, Offset(bx, by), style = Stroke(0.8f * density))
        }
    }
}

/** 熟悉 → HSK / TOCFL 進度: for each level of the word list, how much of it you know and don't know yet */
@Composable
fun HSKProgressList() {
    val nav = LocalNav.current
    Store.rev
    fun pct(v: Double) = "${(v * 100).roundToInt()}%"
    val zh = Store.isZh
    // 台語: 常用詞 and 常用字, 500 a group
    // (台語: the characters first, then the words)
    val list = if (zh) Store.topics else Store.freqTopics.filter { it.id >= Lang.freqCharBase } + Store.freqTopics.filter { it.id < Lang.freqCharBase }
    val all = Store.allTopicProgress()
    val firstChar = Store.topics.firstOrNull { it.id > Lang.charTopicBase }?.id
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (zh) item { CharMeter { nav.push(Route.ZhChars) } }
        items(list, key = { "h|" + it.id }) { t ->
            if (zh && t.id == firstChar) Txt(tr("漢字卡"), ff(FF.Headline), T.muted, Modifier.padding(top = 6.dp, bottom = 8.dp))
            if (!zh && (t.id == Lang.freqWordBase || t.id == Lang.freqCharBase))
                Txt(if (t.id == Lang.freqWordBase) tr("常用詞") else tr("常用字"), ff(FF.Headline), T.muted, Modifier.padding(top = 6.dp, bottom = 8.dp))
            val p = all[t.id] ?: Store.LevelProgress(0, 0, 0)
            val isChar = (t.id > Lang.charTopicBase && t.id < Lang.freqWordBase) || t.id >= Lang.freqCharBase
            val k = if (p.total > 0) p.known.toDouble() / p.total else 0.0
            val u = if (p.total > 0) p.unknown.toDouble() / p.total else 0.0
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(T.fn.copy(alpha = 0.55f)).clickable { nav.push(Route.ZhLevel(t.id)) }
                .padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted, modifier = Modifier.size(16.dp))
                    Txt(t.name, ff(FF.Headline), T.glyph)
                    Txt("${p.total} ${if (isChar) "字" else "詞"}", ff(FF.Caption), T.muted, Modifier.weight(1f))
                    Txt(tr("熟悉 {0}", pct(k)), ff(FF.Subheadline, FontWeight.SemiBold), levelColor(t.id))
                    Txt(tr("不熟 {0}", pct(u)), ff(FF.Subheadline, FontWeight.SemiBold), levelColor(t.id).copy(alpha = 0.6f))
                }
                SplitPotionBar(k, u, levelColor(t.id), label = t.name)
                Txt(tr("熟悉 {0}　不熟 {1}　還沒看 {2}", p.known, p.unknown, p.total - p.known - p.unknown), ff(FF.Caption), T.muted)
            }
        }
        item {
            if (zh) Txt(tr("每個等級一個顏色：從左邊來的濃色 = 熟悉（往右滑或練習學會的詞），從右邊來的淡色 = 不熟，中間空的 = 還沒看過。點一個等級可以看全部的詞，或一次把整個等級標成熟悉；點「認識的漢字」可以看每個字。漢字卡在「新詞」右上角的選單選。在「新詞」右上角可以換詞表（HSK／TOCFL）和選等級。詞表：{0}。", if (Prefs.zhList.value == 1) "TOCFL 華語八千詞（2023）" else "HSK 3.0（2021）"),
                ff(FF.Caption), T.muted)
            else Txt(tr("台語的詞照常用的程度分組，每組 {0} 個：最常用的在「常用詞 1–{1}」。單一個字的另外分在「常用字」。在「新詞」右上角可以選一組來滑。點一組可以看全部的詞，或一次把整組標成熟悉。", Lang.freqSize, Lang.freqSize),
                ff(FF.Caption), T.muted)
        }
    }
}

@Composable
fun ZhProgressPage(onBack: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("學習進度"), onBack, settings = false)
        HSKProgressList()
    }
}

/** a level of HSK / TOCFL: every word, and checking them off */
@Composable
fun LevelWordsPage(level: Int, onBack: () -> Unit) {
    Store.rev
    val name = (Store.topics + Store.freqTopics).firstOrNull { it.id == level }?.name ?: UILang.label(Lang.levelName(Prefs.zhList.value, level))
    var filter by remember { mutableIntStateOf(0) }       // 0 all, 1 not seen, 2 熟悉, 3 不熟
    var confirm by remember { mutableStateOf<Int?>(null) } // 1 = all to 熟悉, 2 = the unseen ones to 熟悉, 3 = all back to 新詞
    var menu by remember { mutableStateOf(false) }
    val all = remember(level, Store.listVersion) { Store.levelCards(level) }
    val shown = all.filter { c ->
        when (filter) {
            1 -> (Store.status(c) ?: 0) == 0
            2 -> Store.status(c) == 1
            3 -> Store.status(c) == 2
            else -> true
        }
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(name, onBack, settings = false) {
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.Checklist, tr("整個等級"), tint = T.glyph) }
                DropdownMenu(menu, { menu = false }, containerColor = T.fn) {
                    DropdownMenuItem(text = { Text(tr("全部標成熟悉"), color = T.glyph) }, leadingIcon = { Icon(Icons.Filled.CheckCircle, null, tint = T.greenInk) },
                        onClick = { confirm = 1; menu = false })
                    DropdownMenuItem(text = { Text(tr("沒看過的標成熟悉"), color = T.glyph) }, leadingIcon = { Icon(Icons.Filled.CheckCircleOutline, null, tint = T.greenInk) },
                        onClick = { confirm = 2; menu = false })
                    DropdownMenuItem(text = { Text(tr("全部移回新詞"), color = T.rustInk) }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.Undo, null, tint = T.rustInk) },
                        onClick = { confirm = 3; menu = false })
                }
            }
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
            item {
                val p = Store.hskProgress(level)
                SplitPotionBar(if (p.total > 0) p.known.toDouble() / p.total else 0.0, if (p.total > 0) p.unknown.toDouble() / p.total else 0.0,
                    levelColor(level), label = name)
                Segmented(listOf(0 to tr("全部"), 1 to tr("沒看過"), 2 to tr("熟悉"), 3 to tr("不熟")), filter, { filter = it }, Modifier.padding(vertical = 6.dp))
                SectionTitle(tr("{0} 個詞（往右滑 = 熟悉，往左滑 = 不熟）", shown.size))
            }
            items(shown, key = { "l|" + it.k }) { c ->
                SwipeRow(start = Pair(tr("熟悉"), T.greenEdge), end = Pair(tr("不熟"), T.rustEdge),
                    onStart = { Store.mark(c, true, false) }, onEnd = { Store.mark(c, false, false) }, onClick = { UI.open(Sheet.CardSheet(c)) }) {
                    Row(Modifier.padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        when (Store.status(c)) {
                            1 -> Icon(Icons.Filled.CheckCircle, null, tint = Color(0xFF6EAAFF), modifier = Modifier.size(20.dp))
                            2 -> Icon(Icons.Filled.Help, null, tint = Color(0xFFFFA94D), modifier = Modifier.size(20.dp))
                            else -> Icon(Icons.Filled.RadioButtonUnchecked, null, tint = T.muted, modifier = Modifier.size(20.dp))
                        }
                        Box(Modifier.weight(1f)) { WordRow(c) }
                    }
                }
                RowDivider()
            }
            item { Spacer(Modifier.height(40.dp)) }
        }
    }
    confirm?.let { cf ->
        AlertDialog(onDismissRequest = { confirm = null }, containerColor = T.fn,
            title = { Txt(when (cf) { 1 -> tr("把 {0} 的詞全部標成熟悉？", name); 2 -> tr("把 {0} 還沒看過的詞標成熟悉？", name); else -> tr("把 {0} 的詞全部移回新詞？（熟悉和不熟的都會）", name) }, ff(FF.Headline)) },
            confirmButton = {
                TextButton(onClick = {
                    when (cf) {
                        1 -> Store.markAll(all, true)
                        2 -> Store.markAll(all.filter { (Store.status(it) ?: 0) == 0 }, true)
                        else -> Store.markAll(all, false)
                    }
                    confirm = null
                }) { Text(if (cf == 3) tr("移回新詞") else tr("標成熟悉"), color = if (cf == 3) T.rustInk else T.greenInk) }
            },
            dismissButton = { TextButton(onClick = { confirm = null }) { Text(tr("取消"), color = T.muted) } })
    }
}

/** 近 / 反: the words, each opens its entry */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ZhLinks(z: ZhDict, name: String, es: List<ZhEntry>, fill: Color, edge: Color, ink: Color) {
    if (es.isEmpty()) return
    val nav = LocalNav.current
    val place = Prefs.zhPlace.value; val rom = Prefs.zhRom.value
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Chip(name, fill, edge, ink)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (e in es) Row(Modifier.clip(CircleShape).background(fill.copy(alpha = 0.5f)).clickable { nav.push(Route.ZhEntry(e.k)) }
                .padding(horizontal = 8.dp, vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Txt(e.h, ff(FF.Subheadline), T.glyph)
                Txt(z.readingPlain(e.syl(place), rom), lat(13f), ink)
            }
        }
    }
}
