package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

// MARK: - the rainbow (red, orange, yellow, green, teal, blue, purple, pink), from the colours in 選聲調顏色

object Rainbow {
    private val columns = listOf(1, 2, 3, 4, 5, 6, 7, 0)
    private fun shades(i: Int): List<Int> = ToneColors.palette[columns[((i % columns.size) + columns.size) % columns.size]].second
    fun fill(i: Int) = Color(shades(i)[4])
    fun edge(i: Int) = Color(shades(i)[2])
    fun ink(i: Int) = Color(shades(i)[0])
}

/** one capsule per word of the search, like the 皓羅 and 台・通行 buttons: grey until you tap one, then in its own colour */
@Composable
fun WordPickRow(words: List<String>, picked: Int?, onPick: (Int?) -> Unit) {
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 4.dp, vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for ((i, w) in words.withIndex()) {
            val on = picked == i
            Txt(w, ff(FF.Subheadline, FontWeight.Bold), if (on) Rainbow.ink(i) else T.glyph,
                Modifier.clip(CircleShape).background(if (on) Rainbow.fill(i) else T.fn.copy(alpha = 0.8f))
                    .border(2.dp, if (on) Rainbow.edge(i) else T.fnEdge, CircleShape)
                    .clickable { onPick(if (on) null else i) }.padding(horizontal = 12.dp, vertical = 5.dp))
        }
    }
}

// MARK: - English meanings as a numbered list

/** a blue square with a number, the shape of the 詞類 chips */
@Composable
fun EnNum(n: Int) = Chip("$n", T.blue, T.blueEdge, T.blueInk)

/** the English meanings (CC-CEDICT separates them with ;), numbered; max = 0: all of them */
@Composable
fun EnglishList(items: List<String>, max: Int = 0, maxLines: Int = Int.MAX_VALUE, style: TextStyle = ff(FF.Subheadline)) {
    val shown = if (max > 0) items.take(max) else items
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        for ((i, t) in shown.withIndex()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (items.size > 1) EnNum(i + 1)
            Txt(t, style, T.glyph.copy(alpha = 0.9f), maxLines = maxLines)
        }
        if (max > 0 && items.size > max) Txt(tr("還有 {0} 個意思", items.size - max), ff(FF.Caption), T.muted)
    }
}

// MARK: - 部首查字

/** the forms radicals take at the side of a character */
private val radicalForms = mapOf(
    "人" to "亻", "刀" to "刂", "水" to "氵", "手" to "扌", "心" to "忄", "犬" to "犭", "示" to "礻", "衣" to "衤", "糸" to "糹",
    "言" to "訁", "金" to "釒", "食" to "飠", "艸" to "艹", "辵" to "⻌", "火" to "灬", "爪" to "爫", "网" to "罒", "玉" to "王",
    "肉" to "⺼", "攴" to "攵", "阜" to "阝左", "邑" to "阝右", "老" to "耂", "足" to "⻊", "竹" to "⺮", "牛" to "牜", "歹" to "歺",
    "襾" to "覀", "毋" to "母",
)

/** 部首查字: 一個部首 (a radical, then the character) or 組合部首 (several radicals: the characters with all of them);
 *  the character tapped goes into the search */
@Composable
fun RadicalPage(zhSearch: Boolean, onBack: () -> Unit) {
    LaunchedEffect(Unit) { Store.preloadZh() }
    var mode by Prefs.radicalMode
    var radical by remember { mutableStateOf<ZhRadical?>(null) }
    val picked = remember { mutableStateListOf<String>() }
    val d = Store.dict
    fun has(ch: String): Boolean = if (zhSearch) Store.zh?.byHan?.containsKey(ch) == true else d?.hanMap?.containsKey(ch) == true
    fun pick(ch: String) {
        if (zhSearch) Prefs.zhLookupQuery.value += ch else Prefs.lookupQuery.value += ch
        onBack()
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(if (mode == 1) tr("組合部首") else radical?.let { tr("部首「{0}」", it.radical) } ?: tr("部首查字"), onBack, settings = false) {
            if (mode == 0 && radical != null) TextButton(onClick = { radical = null }) { Text(tr("換部首"), color = T.btnInk) }
            if (mode == 1 && picked.isNotEmpty()) TextButton(onClick = { picked.clear() }) { Text(tr("清除"), color = T.btnInk) }
        }
        val z = Store.zh
        if (z == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = T.greenInk); Spacer(Modifier.height(12.dp)); Txt(tr("載入部首資料…"), ff(FF.Footnote), T.muted)
                }
            }
            return@Column
        }
        Segmented(listOf(0 to tr("一個部首"), 1 to tr("組合部首")), mode, { mode = it }, Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
        if (mode == 1) RadicalCombine(z, picked, ::has, ::pick)
        else {
            val r = radical
            if (r != null) RadicalChars(r, ::has, ::pick)
            else LazyVerticalGrid(GridCells.Adaptive(48.dp), Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                item(span = { GridItemSpan(maxLineSpan) }) { Txt(tr("點一個部首，再點你要的字。字會放進搜尋框。"), ff(FF.Footnote), T.muted) }
                radicalItems(z.radicals, emptyList(), null) { radical = it }
            }
        }
    }
}

private fun androidx.compose.foundation.lazy.grid.LazyGridScope.radicalItems(
    radicals: List<ZhRadical>, picked: List<String>, enabled: Set<String>?, onTap: (ZhRadical) -> Unit,
) {
    val groups = radicals.filter { it.radical != "｜" }.groupBy { it.strokes }.toSortedMap()
    for ((n, rs) in groups) {
        item(span = { GridItemSpan(maxLineSpan) }) { Txt(tr("{0} 畫", n), ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.padding(top = 8.dp)) }
        items(rs, key = { "r|" + it.radical }) { r ->
            val i = picked.indexOf(r.radical).takeIf { it >= 0 }
            val off = i == null && enabled != null && !enabled.contains(r.radical)
            Column(Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(10.dp))
                .background(i?.let { Rainbow.fill(it) } ?: T.fn.copy(alpha = if (off) 0.35f else 0.8f))
                .border(if (i == null) 1.dp else 2.dp, i?.let { Rainbow.edge(it) } ?: T.fnEdge, RoundedCornerShape(10.dp))
                .clickable(enabled = !off) { onTap(r) }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                val ink = i?.let { Rainbow.ink(it) } ?: if (off) T.muted.copy(alpha = 0.4f) else T.glyph
                Txt(r.radical, sz(22f, FontWeight.Medium), ink)
                radicalForms[r.radical]?.let { Txt(it, ff(FF.Caption2), ink) }
            }
        }
    }
}

/** the characters with one radical, by the strokes besides the radical */
@Composable
private fun RadicalChars(r: ZhRadical, has: (String) -> Boolean, onPick: (String) -> Unit) {
    val groups = remember(r) { r.chars.filter { has(it.first) }.groupBy { it.second }.toSortedMap() }
    LazyVerticalGrid(GridCells.Adaptive(48.dp), Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (groups.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) { Txt(tr("這個詞典沒有這個部首的字。"), ff(FF.Footnote), T.muted) }
        for ((n, cs) in groups) {
            item(span = { GridItemSpan(maxLineSpan) }) { Txt(if (n == 0) tr("部首本身") else tr("再 {0} 畫", n), ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.padding(top = 8.dp)) }
            items(cs, key = { "c|" + it.first }) { c -> CharButton(c.first) { onPick(c.first) } }
        }
    }
}

@Composable
private fun CharButton(ch: String, onClick: () -> Unit) {
    Box(Modifier.heightIn(min = 50.dp).fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(T.fn.copy(alpha = 0.8f))
        .border(1.dp, T.fnEdge, RoundedCornerShape(10.dp)).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Txt(ch, sz(26f, FontWeight.Medium), T.blueInk)
    }
}

/** 組合部首: two areas, the radicals to pick from and what's picked with what it finds
 *  (wide screens: the found characters on the right; phones: on the bottom half) */
@Composable
private fun RadicalCombine(z: ZhDict, picked: MutableList<String>, has: (String) -> Boolean, onPick: (String) -> Unit) {
    var found by remember { mutableStateOf<List<String>>(emptyList()) }
    var enabled by remember { mutableStateOf<Set<String>?>(null) }
    val key = picked.joinToString("")
    LaunchedEffect(key) {
        if (picked.isEmpty()) { found = emptyList(); enabled = null; return@LaunchedEffect }
        val ps = picked.toList()
        val (f, e) = withContext(Dispatchers.Default) {
            val f = z.charsWith(ps).filter(has)
            // with not too many characters: dim the radicals that none of them has
            val e: Set<String>? = if (f.size <= 4000) z.radicalSets.filter { (r, set) -> r !in ps && f.any { set.contains(it) } }.keys else null
            f to e
        }
        found = f; enabled = e
    }
    val radicals: @Composable (Modifier) -> Unit = { m ->
        LazyVerticalGrid(GridCells.Adaptive(48.dp), m, contentPadding = PaddingValues(12.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (z.radicalInside.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
                Txt(tr("這份華語資料沒有字的組成。用新的 zh.json 就有了。"), ff(FF.Footnote), T.muted)
            }
            radicalItems(z.radicals, picked, enabled) { r -> if (picked.contains(r.radical)) picked.remove(r.radical) else picked.add(r.radical) }
        }
    }
    val results: @Composable (Modifier) -> Unit = { m ->
        Column(m.background(T.fn.copy(alpha = 0.25f))) {
            Row(Modifier.fillMaxWidth().background(T.fn.copy(alpha = 0.5f)).padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (picked.isEmpty()) Txt(tr("還沒選部首"), ff(FF.Subheadline), T.muted)
                Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for ((i, r) in picked.withIndex()) Row(Modifier.clip(CircleShape).background(Rainbow.fill(i)).border(2.dp, Rainbow.edge(i), CircleShape)
                        .clickable { picked.remove(r) }.padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Txt(r, ff(FF.Headline), Rainbow.ink(i))
                        Icon(Icons.Filled.Close, tr("拿掉 {0}", r), tint = Rainbow.ink(i), modifier = Modifier.size(12.dp))
                    }
                }
                if (picked.isNotEmpty()) Txt(tr("{0} 個字", found.size), ff(FF.Footnote), T.muted)
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(T.fnEdge))
            if (picked.isEmpty()) Txt(tr("點好幾個部首（例如 氵 和 毋），這裡會出現裡面都有這些部首的字。偏旁也算：氵 = 水、亻 = 人、扌 = 手、艹 = 艸、⻌ = 辵、阝 = 阜／邑…不可能再組合的部首會變淡。"),
                ff(FF.Footnote), T.muted, Modifier.padding(14.dp))
            else if (found.isEmpty()) Txt(tr("沒有字同時有這些部首。"), ff(FF.Footnote), T.muted, Modifier.padding(14.dp))
            else {
                val shown = found.take(300)
                val groups = shown.groupBy { z.strokesOf[it] ?: 0 }.toSortedMap()
                LazyVerticalGrid(GridCells.Adaptive(48.dp), Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    for ((n, cs) in groups) {
                        item(span = { GridItemSpan(maxLineSpan) }) { Txt(if (n == 0) tr("其他") else tr("{0} 畫", n), ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.padding(top = 6.dp)) }
                        items(cs, key = { "f|$it" }) { ch -> CharButton(ch) { onPick(ch) } }
                    }
                    if (found.size > 300) item(span = { GridItemSpan(maxLineSpan) }) {
                        Txt(tr("只列出筆畫最少的 300 個字。再點一個部首可以縮小範圍。"), ff(FF.Caption), T.muted)
                    }
                }
            }
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        // (read here: inside the Row / Column they belong to another scope)
        val w = maxWidth
        val h = maxHeight
        if (w > 640.dp) Row(Modifier.fillMaxSize()) {
            radicals(Modifier.weight(1f).fillMaxHeight())
            Box(Modifier.width(1.dp).fillMaxHeight().background(T.fnEdge))
            results(Modifier.width(maxOf(300.dp, w * 0.42f)).fillMaxHeight())
        } else Column(Modifier.fillMaxSize()) {
            radicals(Modifier.weight(1f).fillMaxWidth())
            Box(Modifier.fillMaxWidth().height(1.dp).background(T.fnEdge))
            results(Modifier.height(h * 0.5f).fillMaxWidth())
        }
    }
}

// MARK: - 日語借詞

@Composable
fun JapanesePage(d: Dict, onBack: () -> Unit) {
    val nav = LocalNav.current
    var list by remember { mutableStateOf<List<Pair<String, String>>?>(null) }
    LaunchedEffect(Unit) { list = withContext(Dispatchers.Default) { d.japaneseWords() } }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("日語借詞"), onBack, settings = false)
        val l = list
        if (l == null) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = T.greenInk) }
        else LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
            item { SectionTitle(tr("{0} 個詞", l.size)) }
            items(l, key = { "j|" + it.first }) { (k, from) ->
                Store.rev
                Box(Modifier.clip(RoundedCornerShape(10.dp)).padding(vertical = 1.dp)) {
                    SwipeRow(
                        start = if (Store.cardStatus(k) == 0) Pair(tr("加到不熟"), T.rustEdge) else null,
                        end = Pair(if (Store.isSaved(k)) tr("取消收藏") else tr("收藏"), T.oliveEdge),
                        onStart = { Store.toggleUnknown(k) }, onEnd = { Store.toggleSaved(k) },
                        onClick = { nav.push(Route.Entry(k)) },
                    ) {
                        Column {
                            DictRow(d, k)
                            if (from.isNotEmpty()) Row(Modifier.padding(start = 14.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalAlignment = Alignment.CenterVertically) {
                                Chip(tr("日"), T.rust, T.rustEdge, T.rustInk)
                                Txt(from, ff(FF.Footnote), T.rustInk)
                            }
                        }
                    }
                }
            }
            item { Spacer(Modifier.height(40.dp)) }
        }
    }
}

// MARK: - 華語: 單詞比較, 依詞類列出

@Composable
fun ZhComparePage(z: ZhDict, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("單詞比較"), onBack, settings = false)
        BoxWithConstraints(Modifier.fillMaxSize()) {
            if (maxWidth > 700.dp) Row(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) { ZhComparePane(z, Prefs.zhCompareA, tr("第一個詞")) }
                Box(Modifier.width(1.dp).fillMaxHeight().background(T.fnEdge))
                Box(Modifier.weight(1f)) { ZhComparePane(z, Prefs.zhCompareB, tr("第二個詞")) }
            } else Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) { ZhComparePane(z, Prefs.zhCompareA, tr("第一個詞")) }
                Box(Modifier.height(1.dp).fillMaxWidth().background(T.fnEdge))
                Box(Modifier.weight(1f)) { ZhComparePane(z, Prefs.zhCompareB, tr("第二個詞")) }
            }
        }
    }
}

@Composable
private fun ZhComparePane(z: ZhDict, slot: com.unoki99.fangfang.Pref<String>, hint: String) {
    var query by remember { mutableStateOf("") }
    var found by remember { mutableStateOf<List<Int>>(emptyList()) }
    LaunchedEffect(query) {
        if (query.isEmpty()) { found = emptyList(); return@LaunchedEffect }
        delay(200)
        val q = query
        val f = withContext(Dispatchers.Default) { z.search(q, Prefs.zhPlace.value) }
        found = (f.words + f.partWords.flatten() + f.starts + f.english + f.contains).distinct().take(40)
    }
    Column(Modifier.fillMaxSize()) {
        SearchField(query, { query = it }, hint, Modifier.padding(10.dp))
        val e = z.entry(slot.value)
        if (query.isNotEmpty()) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 10.dp)) {
                items(found) { i -> Box(Modifier.background(T.fn).clickable { slot.value = z.entries[i].k; query = "" }) { ZhWordRow(z, z.entries[i]) } }
            }
        } else if (e != null) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) { ZhEntryBody(z, e); Spacer(Modifier.height(30.dp)) }
        } else Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Txt(tr("查一個詞，選它。"), ff(FF.Body), T.muted) }
    }
}

/** 依詞類列出 (華語): every word class with how many words it has (from the HSK / TOCFL lists) */
@Composable
fun ZhWordClassListPage(z: ZhDict, onBack: () -> Unit) {
    val nav = LocalNav.current
    var counts by remember { mutableStateOf<List<Pair<String, Int>>>(emptyList()) }
    LaunchedEffect(Unit) {
        counts = withContext(Dispatchers.Default) {
            val n = HashMap<String, Int>()
            for (e in z.entries) for (p in e.pos) n[p] = (n[p] ?: 0) + 1
            val order = listOf("名詞", "動詞", "離合詞", "形容詞", "副詞", "量詞", "時間詞", "代詞", "數詞", "方位詞",
                "介詞", "連詞", "助詞", "疑問詞", "嘆詞", "擬聲詞", "擬態詞", "熟語")
            n.keys.sortedWith(compareBy({ order.indexOf(it).let { i -> if (i < 0) 99 else i } }, { it })).map { it to n[it]!! }
        }
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("依詞類列出"), onBack, settings = false)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
            item {
                ListCard {
                    for ((i, c) in counts.withIndex()) {
                        if (i > 0) RowDivider()
                        Row(Modifier.fillMaxWidth().clickable { nav.push(Route.ZhClass(c.first)) }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Txt(c.first, ff(FF.Body), modifier = Modifier.weight(1f))
                            Txt("${c.second}", ff(FF.Footnote), T.muted)
                            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted)
                        }
                    }
                }
                Txt(tr("詞類來自 HSK 3.0 和 TOCFL 的詞表，所以只有詞表裡的詞有。"), ff(FF.Footnote), T.muted, Modifier.padding(8.dp))
            }
        }
    }
}

@Composable
fun ZhWordClassPage(z: ZhDict, cls: String, onBack: () -> Unit) {
    val nav = LocalNav.current
    var list by remember { mutableStateOf<List<Int>?>(null) }
    LaunchedEffect(cls) { list = withContext(Dispatchers.Default) { z.wordsOfClass(cls) } }
    Column(Modifier.fillMaxSize()) {
        TopBar(cls, onBack, settings = false)
        val l = list
        if (l == null) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = T.greenInk) }
        else LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
            item { SectionTitle(tr("{0} 個詞", l.size)) }
            items(l, key = { "wc|$it" }) { i ->
                val e = z.entries[i]
                Store.rev
                Box(Modifier.clip(RoundedCornerShape(10.dp)).padding(vertical = 1.dp)) {
                    SwipeRow(
                        start = if (Store.cardStatus(e.k) != 1) Pair(if (Store.cardStatus(e.k) == 2) tr("移回新詞") else tr("加到不熟"), T.rustEdge) else null,
                        end = Pair(if (Store.isSaved(e.k)) tr("取消收藏") else tr("收藏"), T.oliveEdge),
                        onStart = { Store.toggleUnknown(e.k) }, onEnd = { Store.toggleSaved(e.k) },
                        onClick = { nav.push(Route.ZhEntry(e.k)) },
                    ) { ZhWordRow(z, e) }
                }
            }
        }
    }
}

// MARK: - 認識的漢字

/** how many single 漢字 you know (from the words you've swiped): a character in any 熟悉 word is known */
@Composable
fun CharMeter(onClick: () -> Unit) {
    val p = Store.zhCharSets()
    val total = p.all.size
    val k = if (total > 0) p.known.size.toDouble() / total else 0.0
    val u = if (total > 0) p.unknown.size.toDouble() / total else 0.0
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(T.fn.copy(alpha = 0.55f)).clickable(onClick = onClick).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted, modifier = Modifier.size(16.dp))
            Txt(tr("認識的漢字"), ff(FF.Headline), T.glyph)
            Txt(tr("{0} 字", total), ff(FF.Caption), T.muted, Modifier.weight(1f))
            Txt(tr("熟悉 {0}", p.known.size), ff(FF.Subheadline, FontWeight.SemiBold), Color(0xFF6EAAFF))
            Txt(tr("不熟 {0}", p.unknown.size), ff(FF.Subheadline, FontWeight.SemiBold), Color(0xFFFFA94D))
        }
        SplitPotionBar(k, u, Color(0xFF6EAAFF), label = tr("認識的漢字"))
        Txt(tr("熟悉的詞裡的字都算認識（就算它也在不熟的詞裡）；只在不熟的詞裡出現的字算不熟。還沒看 {0} 字（所有詞卡和漢字卡裡的字，每個字只算一次）。", total - p.known.size - p.unknown.size),
            ff(FF.Caption), T.muted)
    }
}

/** every character: blue = 熟悉, orange = 不熟; hold one to switch it, tap it to see it */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ZhCharListPage(onBack: () -> Unit) {
    val haptic = LocalHapticFeedback.current
    var filter by remember { mutableIntStateOf(0) }
    var query by remember { mutableStateOf("") }
    val sets = Store.zhCharSets()
    val shown = sets.all.filter { ch ->
        when (filter) {
            1 -> sets.known.contains(ch)
            2 -> sets.unknown.contains(ch)
            3 -> !sets.known.contains(ch) && !sets.unknown.contains(ch)
            else -> true
        } && (query.isEmpty() || query.contains(ch))
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("認識的漢字"), onBack, settings = false)
        LazyVerticalGrid(GridCells.Adaptive(48.dp), Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    val total = sets.all.size
                    SplitPotionBar(if (total > 0) sets.known.size.toDouble() / total else 0.0, if (total > 0) sets.unknown.size.toDouble() / total else 0.0,
                        Color(0xFF6EAAFF), label = tr("認識的漢字"))
                    Segmented(listOf(0 to tr("全部 {0}", total), 1 to tr("熟悉 {0}", sets.known.size), 2 to tr("不熟 {0}", sets.unknown.size), 3 to tr("沒看過")), filter, { filter = it })
                    SearchField(query, { query = it }, tr("找字，例如：愛"), fontSize = 18.sp)
                    if (query.isNotEmpty() && shown.isEmpty()) Txt(tr("這裡沒有「{0}」。", query), ff(FF.Footnote), T.muted)
                }
            }
            items(shown, key = { "ch|$it" }) { ch ->
                val k = sets.known.contains(ch); val u = sets.unknown.contains(ch)
                Box(Modifier.size(48.dp).clip(RoundedCornerShape(10.dp))
                    .background(if (k) Color(0xFF4F7DFF).copy(alpha = 0.35f) else if (u) Color(0xFFFFA94D).copy(alpha = 0.3f) else T.fn.copy(alpha = 0.7f))
                    .border(1.dp, if (k) Color(0xFF6EAAFF) else if (u) Color(0xFFFFA94D) else T.fnEdge, RoundedCornerShape(10.dp))
                    // hold: 熟悉 ⇄ 不熟 (its character card); tap: open it
                    .combinedClickable(onLongClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        Store.setCharKnown(ch, !k)
                    }, onClick = {
                        val c = Store.cardFor(Lang.charKey(ch))
                        if (c != null) UI.open(Sheet.CardSheet(c))
                        else Store.zh?.entryForChar(ch, "")?.let { UI.open(Sheet.ZhWord(it.k)) }
                    }), contentAlignment = Alignment.Center) {
                    Txt(ch, sz(24f), if (k) Color(0xFFCFE2FF) else if (u) Color(0xFFFFE1C2) else T.glyph)
                }
            }
            item(span = { GridItemSpan(maxLineSpan) }) {
                Txt(tr("按住一個字可以在熟悉和不熟之間換。藍色 = 熟悉（在熟悉的詞裡，或漢字卡往右滑；熟悉的詞裡的字，漢字卡也會自動標成熟悉）；橘色 = 不熟（只在不熟的詞或漢字卡裡）；沒有顏色 = 還沒看過。這裡是所有可以滑的卡片裡的字（詞卡和漢字卡，每個字只算一次），照卡片的順序排。點一個字看它的意思。"),
                    ff(FF.Caption), T.muted, Modifier.padding(top = 8.dp))
            }
        }
    }
}

// MARK: - 練習範圍

/** 不熟 → 練習範圍: all of 不熟, or one level / group (華語: HSK / TOCFL words or characters; 台語: 常用詞 / 常用字) */
@Composable
fun PracticeScopeMenu() {
    val ts = Store.practiceTopics
    if (ts.isEmpty()) return
    var open by remember { mutableStateOf(false) }
    val all = Store.allTopicProgress()
    val zh = Store.isZh
    Box {
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.7f))
            .border(1.dp, T.fnEdge, RoundedCornerShape(12.dp)).clickable { open = true }.padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.Tune, null, tint = T.greenInk, modifier = Modifier.size(20.dp))
            Txt(tr("練習範圍"), ff(FF.Subheadline), T.muted)
            Txt(Store.practiceName, ff(FF.Subheadline), T.glyph, Modifier.weight(1f), maxLines = 1)
            Txt("${Store.practiceCards.size}", ff(FF.Footnote), T.muted)
            Icon(Icons.Filled.UnfoldMore, null, tint = T.muted, modifier = Modifier.size(18.dp))
        }
        DropdownMenu(open, { open = false }, containerColor = T.fn) {
            DropdownMenuItem(text = { Text(tr("全部不熟的詞（{0}）", Store.unknownCount), color = if (Store.practiceTopic < 0) T.greenInk else T.glyph) },
                onClick = { Store.practiceTopic = -1; open = false })
            var lastHeader = ""
            for (t in ts) {
                val isChar = if (zh) t.id > Lang.charTopicBase else t.id >= Lang.freqCharBase
                val header = if (zh) (if (isChar) tr("漢字（等級）") else tr("詞（等級）")) else (if (isChar) tr("常用字") else tr("常用詞"))
                if (header != lastHeader) {
                    lastHeader = header
                    HorizontalDivider(color = T.fnEdge)
                    Txt(header, ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
                }
                DropdownMenuItem(text = { Text(tr("{0}（不熟 {1}）", t.name, all[t.id]?.unknown ?: 0), color = if (Store.practiceTopic == t.id) T.greenInk else T.glyph) },
                    onClick = { Store.practiceTopic = t.id; open = false })
            }
        }
    }
}

// MARK: - 選聲調顏色

@Composable
fun ToneColorPickerPage(onBack: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("選聲調顏色"), onBack, settings = false)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).widthIn(max = 700.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            ToneColorPickerBody()
            Spacer(Modifier.height(40.dp))
        }
    }
}

/** 設定 → 顏色與外觀 → 選聲調顏色: every tone of 台語 and 華語 can have a colour of its own */
@Composable
fun ToneColorPickerBody() {
    var zh by remember { mutableStateOf(Store.isZh) }
    var tone by remember { mutableStateOf<Int?>(null) }
    // (read so the page redraws when a colour changes)
    val sig = Prefs.toneColorsTw.value + Prefs.toneColorsZh.value
    fun set(t: Int, c: Int?) {
        val m = HashMap(ToneColors.picked(zh))
        if (c == null) m.remove(t) else m[t] = c
        if (zh) Prefs.toneColorsZh.value = ToneColors.encode(m) else Prefs.toneColorsTw.value = ToneColors.encode(m)
        ToneColors.load(Prefs.toneColorsTw.value, Prefs.toneColorsZh.value)
    }
    fun colorOf(t: Int) = Color(if (zh) ToneColors.zhColor(t) else ToneColors.twColor(t))
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        run {
            key(sig) {
                Segmented(listOf(false to tr("台語"), true to tr("華語")), zh, { zh = it; tone = null })
                SectionTitle(tr("看起來"))
                ListCard {
                    Row(Modifier.fillMaxWidth().padding(vertical = 12.dp, horizontal = 6.dp)) {
                        if (zh) {
                            for ((h, t) in listOf("媽" to 1, "麻" to 2, "馬" to 3, "罵" to 4, "嗎" to 0)) Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                                Txt(h, sz(26f, FontWeight.SemiBold), colorOf(t))
                                Txt(listOf("mā", "má", "mǎ", "mà", "ma")[if (t == 0) 4 else t - 1], lat(15f), colorOf(t))
                            }
                        } else {
                            // 番 返 販 法 凡 犯 泛 罰 蕃: tones 1–8 and the light tone, in 皓羅
                            val hs = listOf("番", "返", "販", "法", "凡", "犯", "泛", "罰", "蕃")
                            val rs = listOf("hua̍n", "huàn", "huạn", "huạt", "huán", "hua̱n", "huān", "hua̍t", "--huan")
                            for ((i, t) in ToneColors.twTones.withIndex()) Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                                Txt(if (t == 0) tr("輕") else "$t", ff(FF.Caption2, FontWeight.Bold), T.muted)
                                Txt(hs[i], sz(22f, FontWeight.SemiBold), colorOf(t))
                                Txt(rs[i], lat(10f), colorOf(t), maxLines = 1)
                            }
                        }
                    }
                }
                SectionTitle(tr("每個聲調（點一下選顏色）"))
                ListCard {
                    val tones = if (zh) ToneColors.zhTones else ToneColors.twTones
                    for ((i, t) in tones.withIndex()) {
                        if (i > 0) RowDivider()
                        Row(Modifier.fillMaxWidth().clickable { tone = if (tone == t) null else t }.padding(14.dp), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Box(Modifier.size(22.dp).clip(CircleShape).background(colorOf(t)))
                            Txt(if (t == 0) (if (zh) tr("輕聲") else tr("輕聲（--）")) else tr("第 {0} 聲", t), ff(FF.Body), modifier = Modifier.weight(1f))
                            if (ToneColors.picked(zh).containsKey(t)) TextButton(onClick = { set(t, null) }) { Text(tr("原本的"), color = T.muted) }
                        }
                        if (tone == t) {
                            // one column per colour, light at the top and dark at the bottom
                            Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                                for ((_, shades) in ToneColors.palette) Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    for (c in shades) {
                                        val on = colorOf(t) == Color(c)
                                        Box(Modifier.size(28.dp).clip(CircleShape).background(Color(c))
                                            .border(if (on) 3.dp else 0.dp, if (on) T.glyph else Color.Transparent, CircleShape)
                                            .clickable { set(t, c) })
                                    }
                                }
                            }
                        }
                    }
                }
                TextButton(onClick = {
                    if (zh) Prefs.toneColorsZh.value = "" else Prefs.toneColorsTw.value = ""
                    ToneColors.load(Prefs.toneColorsTw.value, Prefs.toneColorsZh.value)
                }) { Text(tr("全部換回原本的顏色"), color = T.rustInk) }
                Txt(tr("原本的顏色：台語一聲紅、二聲紫、三聲藍、四聲橘、五聲綠、六聲青、七聲黃、八聲粉紅、輕聲灰；華語一聲紅、二聲綠、三聲藍、四聲紫、輕聲灰。"),
                    ff(FF.Footnote), T.muted)
            }
        }
    }
}
