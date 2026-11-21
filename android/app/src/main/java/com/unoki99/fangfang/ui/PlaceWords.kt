package com.unoki99.fangfang.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.engine.*
import com.unoki99.fangfang.tr
import com.unoki99.fangfang.UILang

// A 腔口's own words (鹿港偏好用詞…): in 教育部's 詞彙比較 (各地講法), the words recorded only in this place, or in
// this place and one other, with what most places say instead. The same as the iPhone app's.

class PlaceWord(val han: String, val codes: String, val zh: List<String>, val others: List<Int>, val usual: List<String>)

object PlaceWords {
    private val cache = HashMap<Int, List<PlaceWord>>()
    fun title(d: Dict, place: Int): String {
        val n = d.raw.places.getOrNull(place) ?: ""
        return UILang.label(n.take(2)) + tr("偏好用詞")
    }
    fun words(d: Dict, place: Int): List<PlaceWord> {
        cache[place]?.let { return it }
        // where each word is used, for any meaning (a word that's everywhere for another meaning isn't this place's)
        val placesOf = HashMap<String, MutableSet<Int>>()
        for (e in d.raw.cmp) for (r in e.rows) placesOf.getOrPut(r.han) { HashSet() }.add(r.place)
        class W(val codes: String, val zh: MutableList<String> = ArrayList(), val usual: MutableList<String> = ArrayList())
        val byWord = LinkedHashMap<String, W>()
        for (e in d.raw.cmp) {
            // the words most places use for this meaning (the most places; at least 3)
            val count = HashMap<String, MutableSet<Int>>()
            for (r in e.rows) count.getOrPut(r.han) { HashSet() }.add(r.place)
            for (r in e.rows) {
                if (r.place != place) continue
                val ps = placesOf[r.han] ?: continue
                if (ps.size > 2) continue
                val w = byWord.getOrPut(r.han) { W(r.codes) }
                if (e.zh !in w.zh) w.zh.add(e.zh)
                val others = count.filter { it.key != r.han && it.value.size >= 3 }
                val most = others.values.maxOfOrNull { it.size } ?: continue
                for (h in others.filter { it.value.size == most }.keys.sorted()) if (h !in w.usual) w.usual.add(h)
            }
        }
        val out = byWord.map { (h, w) -> PlaceWord(h, w.codes, w.zh, ((placesOf[h] ?: emptySet<Int>()) - place).sorted(), w.usual) }
        // only here first, then here and one other place; each in the order of 詞彙比較
        val sorted = out.filter { it.others.isEmpty() } + out.filter { it.others.isNotEmpty() }
        cache[place] = sorted
        return sorted
    }
}

@Composable
fun PlaceWordsPage(d: Dict, place: Int, onBack: () -> Unit) {
    val nav = LocalNav.current
    val rom = Prefs.rom.value
    var query by remember { mutableStateOf("") }
    val all = remember(place) { PlaceWords.words(d, place) }
    // (a spelling too, as in the dictionary: 皓羅, 台羅, 白話字 or 方音, with or without the tones: the words it finds)
    var spelled by remember { mutableStateOf<Set<String>?>(null) }
    LaunchedEffect(query, place) {
        val q = query.trim()
        if (q.isEmpty() || !q.codePoints().anyMatch { ConvertEngine.isZy(it) || ConvertEngine.isLatinLetter(it) }) { spelled = null; return@LaunchedEffect }
        kotlinx.coroutines.delay(200)
        spelled = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            val r = Lookup.run(d, q, place, Prefs)
            (r.taigi + Lookup.run(d, q, -1, Prefs).taigi).toHashSet()
        }
    }
    val sp = spelled
    val list = if (query.isEmpty()) all else if (sp != null) all.filter { w ->
        val k = d.keyOf(Opt(w.han, w.codes.split(" ").filter { it.isNotEmpty() }))
        (k != null && k in sp) || sp.any { Dict.hanOf(it) == w.han || Dict.hanOf(it) in w.usual }
    } else all.filter { w -> w.han.contains(query) || w.zh.any { it.contains(query) } || w.usual.any { it.contains(query) } }
    val only = list.filter { it.others.isEmpty() }; val shared = list.filter { it.others.isNotEmpty() }
    val name = UILang.label((d.raw.places.getOrNull(place) ?: "").take(2))
    @Composable fun PwRow(w: PlaceWord) {
        val key = remember(w) { d.keyOf(Opt(w.han, w.codes.split(" ").filter { it.isNotEmpty() })) }
        val has = key != null && d.raw.defs.m[key] != null
        Column(Modifier.fillMaxWidth().clickable(enabled = has) { key?.let { nav.push(Route.Entry(it)) } }.padding(horizontal = 14.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp)) {
            androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Txt(w.han, sz(18f, FontWeight.SemiBold), T.glyph)
                if (w.codes.isNotEmpty()) Txt(d.codes(w.codes, rom, place), lat(15f), T.greenInk)
            }
            androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Chip(tr("華"), T.blue, T.blueEdge, T.blueInk)
                Txt(w.zh.joinToString("、"), ff(FF.Footnote), T.glyph, maxLines = 2)
            }
            // what most places say instead, each in a box
            if (w.usual.isNotEmpty()) androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Txt(tr("一般講："), ff(FF.Caption), T.muted)
                for (h in w.usual.take(4)) Txt(h, ff(FF.Subheadline), T.oliveInk, Modifier.clip(RoundedCornerShape(7.dp)).background(T.olive)
                    .border(1.2.dp, T.oliveEdge, RoundedCornerShape(7.dp)).padding(horizontal = 8.dp, vertical = 2.dp))
            }
            if (w.others.isNotEmpty()) Txt(tr("也在：") + w.others.mapNotNull { d.raw.places.getOrNull(it)?.take(2)?.let { n -> UILang.label(n) } }.joinToString("、"),
                ff(FF.Caption), T.muted)
        }
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(PlaceWords.title(d, place), onBack, settings = false)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
            item {
                SearchField(query, { query = it }, tr("台語漢字或拼音（這裡的或一般的講法）或華語"))
                Txt(tr("教育部辭典的「詞彙比較」（各地講法）裡，只記在這個地方，或這裡和另外一個地方的詞。只比較這 10 個地方，而且只有調查過的意思。"),
                    ff(FF.Footnote), T.muted, Modifier.padding(8.dp))
            }
            if (only.isNotEmpty()) {
                item { SectionTitle(tr("只有{0}（{1}）", name, only.size)) }
                items(only, key = { "o|" + it.han }) { w -> Box(Modifier.clip(RoundedCornerShape(10.dp)).background(T.fn.copy(alpha = 0.7f)).padding(vertical = 1.dp)) { PwRow(w) }; Spacer(Modifier.height(4.dp)) }
            }
            if (shared.isNotEmpty()) {
                item { SectionTitle(tr("{0}和另外一個地方（{1}）", name, shared.size)) }
                items(shared, key = { "s|" + it.han }) { w -> Box(Modifier.clip(RoundedCornerShape(10.dp)).background(T.fn.copy(alpha = 0.7f)).padding(vertical = 1.dp)) { PwRow(w) }; Spacer(Modifier.height(4.dp)) }
            }
            item { Spacer(Modifier.height(40.dp)) }
        }
    }
}
