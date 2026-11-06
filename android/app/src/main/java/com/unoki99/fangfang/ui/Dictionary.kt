package com.unoki99.fangfang.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** what the texts depend on: redraw (and work out again) when one of these changes */
@Composable
fun textKey(): List<Any> = listOf(Prefs.rom.value, Prefs.place.value, Prefs.toneSys.value, Prefs.toneMarks.value, Prefs.toneGlow.value, Prefs.theme.value,
    Prefs.zhRom.value, Prefs.zhPlace.value)

// MARK: - entry

@Composable
fun EntryPage(d: Dict, key: String, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        TopBar(Dict.hanOf(key), onBack, settings = false)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
            DictEntryBody(d, key)
            Spacer(Modifier.height(40.dp))
        }
    }
}

/** a dictionary entry in the sheet from the bottom */
@Composable
fun EntrySheetRoot(d: Dict, key: String) {
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { UI.closeSheet() }) { Text("完成", color = T.greenInk) }
            Spacer(Modifier.weight(1f))
            BarButtons(settings = false)
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            DictEntryBody(d, key)
            Spacer(Modifier.height(60.dp))
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DictEntryBody(d: Dict, key: String) {
    val nav = LocalNav.current
    val rom = Prefs.rom.value; val place = Prefs.place.value
    val tk = textKey()
    val han = Dict.hanOf(key)
    Store.rev
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // header
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                val h = remember(key, tk) { d.hanText(key, place, (if (d.isUser(key)) T.ownInk else T.glyph).argbInt()).annotated() }
                // tap a character to see it on its own (the entry with the same reading)
                val targets = remember(key) { charKeys(d, key) }
                TappableHeadword(h, targets) { k -> nav.push(Route.Entry(k)) }
                d.raw.au[key]?.let { PlayButton(Audio.wordPath(it)) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val on = Store.isSaved(key)
                CapsuleButton(if (on) "已收藏" else "收藏", if (on) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder, on,
                    T.olive, T.oliveEdge, T.oliveInk) { Store.toggleSaved(key) }
                val st = Store.cardStatus(key)
                if (st == 1) Chip("卡片：熟悉", T.green, T.greenEdge, T.greenInk)
                else if (st != null) CapsuleButton(if (st == 2) "在「不熟」" else "加到「不熟」", if (st == 2) Icons.Filled.Star else Icons.Filled.StarBorder,
                    st == 2, T.rust, T.rustEdge, T.rustInk) { Store.toggleUnknown(key) }
            }
            val r = remember(key, tk) { d.wordText(key, rom, place).annotated() }
            Txt(r, lat(22f), T.greenInk)
            val z = remember(key, tk) { d.wordText(key, 3, place).annotated() }
            Txt(z, sz(19f), T.purpleInk)
            InputCodesRow(han)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                d.raw.reg[key]?.let { RegChip(it) }
                if (d.subst.contains(key)) Chip("替", T.rust, T.rustEdge, T.rustInk)
                val t = d.raw.typ[key]; val types = d.raw.types
                if (t != null && t > 0 && types != null && t < types.size && t != 1) Chip(types[t], T.fn, T.fnEdge, T.muted)
                if (d.own.contains(key)) Chip("方方補", T.fn, T.fnEdge, T.muted)
                if (d.isUser(key)) OwnChip()
                if (place >= 0 && d.differsFromCommon(key, place) && place < d.raw.places.size) {
                    PlaceChip(d.raw.places[place])
                    if (!d.isStated(key, place)) Chip("推測", T.fn, T.fnEdge, T.muted)
                }
            }
        }
        val oth = remember(key, tk) { d.others(key, place) }
        if (oth.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (o in oth) OtherRow(o.label, d.codes(o.codes, rom, -1, o.tokens), d.codes(o.codes, 3, if (o.label == "通行") -1 else place, o.tokens))
        }
        // names
        if (han.cpCount == 1) {
            fun part(lab: String, list: List<List<String>>?): String? =
                if (list.isNullOrEmpty()) null else lab + "：" + list.take(4).joinToString("、") { d.codes(it[0], rom, -1) }
            val s = listOfNotNull(part("人名", d.raw.names[han]), part("姓", d.raw.sur[han])).joinToString("　")
            if (s.isNotEmpty()) Txt(s, lat(14f), T.muted)
        }
        // 異用字
        val vs = remember(key) { d.raw.variants.filter { it.value.contains(key) }.keys.sorted() }
        if (vs.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Chip("異用字", T.fn, T.fnEdge, T.muted)
            Txt(vs.joinToString("、"), ff(FF.Subheadline), T.glyph.copy(alpha = 0.9f))
        }
        // 分類
        val cs = d.raw.cat?.get(key) ?: emptyList()
        val names = d.raw.cats
        if (cs.isNotEmpty() && names != null) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chip("分類", T.pink, T.pinkEdge, T.pinkInk)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (i in cs.filter { it < names.size }) {
                    Txt(names[i], ff(FF.Subheadline), T.pinkInk, Modifier.clip(CircleShape).background(T.pink.copy(alpha = 0.6f))
                        .clickable { nav.push(Route.Category(i)) }.padding(horizontal = 8.dp, vertical = 3.dp))
                }
            }
        }
        // 各地講法: other words the chosen place uses for the same meaning
        if (place >= 0 && place < d.raw.places.size) {
            val words = remember(key, place) {
                val out = ArrayList<Pair<String, String>>()
                for (e in d.raw.cmp) if (e.rows.any { it.han == han }) for (r in e.rows) {
                    if (r.place == place && r.han != han && out.none { it.first == r.han }) out.add(Pair(r.han, r.codes))
                }
                out
            }
            if (words.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PlaceChip(d.raw.places[place].take(2) + "也講")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    for ((h, c) in words) {
                        val k = d.keyOf(Opt(h, c.split(' ')))
                        Row(Modifier.clip(CircleShape).background(T.placeFill.copy(alpha = 0.6f))
                            .then(if (k != null && d.raw.defs.m[k] != null) Modifier.clickable { nav.push(Route.Entry(k)) } else Modifier)
                            .padding(horizontal = 8.dp, vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Txt(h, ff(FF.Subheadline), T.glyph)
                            Txt(d.codes(c, rom, place), lat(13f), T.purpleInk)
                        }
                    }
                }
            }
        }
        d.gl[key]?.takeIf { it.isNotEmpty() }?.let { g ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Chip("華語", T.fn, T.fnEdge, T.muted)
                Txt(g.joinToString("、") { it.t }, ff(FF.Subheadline), T.glyph.copy(alpha = 0.9f))
            }
        }
        val senses = remember(key) { d.senses(key) }
        for (s in senses) SenseBlock(d, key, s)
        if (place >= 0 && senses.any { s -> s.ex.any { it.size > 1 && d.hasGuess(it[1], it[0], place) } }) GuessNote()
        val wl = remember(key) { d.wordLinks(key) }
        if (wl.first.isNotEmpty() || wl.second.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            LinkChips(d, "近", wl.first, T.blue, T.blueEdge, T.blueInk)
            LinkChips(d, "反", wl.second, T.rust, T.rustEdge, T.rustInk)
        }
        if (d.raw.typ[key] == 1) Txt("臺華共同詞：台語和華語寫法、意思一樣的詞。", ff(FF.Caption), T.muted)
    }
}

@Composable
fun GuessNote() = Txt("紅色 = 推測的讀音（辭典沒有寫這個地方怎麼唸這個詞，照規則推出來的）", ff(FF.Caption2), T.muted)

@Composable
fun OtherRow(label: String, rom: String, zy: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Chip(label)
        Txt(rom, lat(17f), T.greenInk)
        Txt(zy, ff(FF.Footnote), T.purpleInk)
    }
}

@Composable
private fun SenseBlock(d: Dict, key: String, s: DictSense) {
    val rom = Prefs.rom.value; val place = Prefs.place.value
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.55f)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Txt("${s.n}.", ff(FF.Subheadline, FontWeight.Bold), T.muted)
            if (s.pos.isNotEmpty()) Chip(s.pos, T.fn, T.fnEdge, T.muted)
            Txt(s.text, ff(FF.Body), T.glyph, Modifier.weight(1f))
            CopyIconButton {
                SenseCopy.text(d, key, s.n - 1, rom, place, Prefs.copyTpl.value, Prefs.copyEx.value, Prefs.copySep.value)
            }
            SenseSaveButton(SavedSense(key, s.n - 1))
        }
        // places that read this meaning differently from the word (足「非常、很」: 臺南、高雄、金門 tsok), yellow like 又
        val m = d.raw.sdia?.get(key)?.get((s.n - 1).toString())
        if (!m.isNullOrEmpty()) {
            val shown = if (place >= 0) m.filterKeys { it == place.toString() } else m
            val groups = shown.keys.mapNotNull { it.toIntOrNull() }.sorted().groupBy { shown[it.toString()] ?: "" }
            for (codes in groups.keys.sorted()) {
                val ps = groups[codes] ?: emptyList()
                Row(Modifier.padding(start = 18.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Chip(ps.joinToString("、") { d.raw.places.getOrNull(it)?.take(2) ?: "" })
                    Txt(d.codes(codes, rom, ps.firstOrNull() ?: -1), lat(15f), T.greenInk)
                    Txt(d.codes(codes, 3, ps.firstOrNull() ?: -1), ff(FF.Footnote), T.purpleInk)
                    Txt("這個意思", ff(FF.Caption2), T.muted)
                }
            }
        }
        for (e in s.ex) Box(Modifier.padding(start = 18.dp)) { ExampleBlock(d, e, own = key) }
        if (s.syn.isNotEmpty() || s.ant.isNotEmpty()) Column(Modifier.padding(start = 18.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            LinkChips(d, "近", s.syn, T.blue, T.blueEdge, T.blueInk)
            LinkChips(d, "反", s.ant, T.rust, T.rustEdge, T.rustInk)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LinkChips(d: Dict, name: String, keys: List<String>, fill: Color, edge: Color, ink: Color) {
    if (keys.isEmpty()) return
    val nav = LocalNav.current
    val rom = Prefs.rom.value; val place = Prefs.place.value
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Chip(name, fill, edge, ink)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (k in keys) {
                Row(Modifier.clip(CircleShape).background(fill.copy(alpha = 0.5f)).clickable { nav.push(Route.Entry(k)) }
                    .padding(horizontal = 8.dp, vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Txt(Dict.hanOf(k), ff(FF.Subheadline), T.glyph)
                    Txt(d.wordText(k, rom, place).annotated(ink), lat(13f), ink)
                }
            }
        }
    }
}

// MARK: - example sentence

private class ExPiece(val text: String, val key: String?, val swapOf: String?, val swapped: Boolean)

/**
 * one example sentence: 漢字 word by word (tap a word to open it; with a 腔口, the place's own words in pink),
 * 羅馬字 in the place's readings, 華語, and on the right the 在地詞 switch / 選詞 and ▶
 */
@Composable
fun ExampleBlock(d: Dict, ex: List<String>, own: String? = null, boxedOwn: Boolean = false, onWord: (String) -> Unit = { UI.openWord(it) }) {
    val rom = Prefs.rom.value; val place = Prefs.place.value; val toneSys = Prefs.toneSys.value
    val swaps = Prefs.swaps.value; val swapOff = Prefs.swapOff.value
    val tk = textKey()
    var swapWord by remember { mutableStateOf<String?>(null) }
    val zh = if (ex.size > 2) ex[2] else null
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (ex.size > 1) {
                val pieces = remember(ex, tk, swaps, swapOff) { examplePieces(d, ex[0], ex[1], zh, place) }
                val tones = remember(ex, tk, swaps, swapOff) { if (toneSys != 0) d.exampleTones(ex[0], ex[1], place, zh).tones else null }
                val starts = remember(pieces) {
                    var n = 0
                    pieces.map { p -> val s = n; n += p.text.cps().count { ConvertEngine.isHan(it.firstCp()) }; s }
                }
                val texts = remember(pieces, tones, tk) {
                    pieces.mapIndexed { i, p ->
                        val ink = when {
                            p.swapOf != null -> if (p.swapped) T.swapInk else T.glyph
                            p.key != null && p.key != own -> T.blueInk
                            p.key != null && p.key == own -> T.oliveInk
                            else -> T.glyph
                        }
                        val st = if (tones == null) styled(p.text, ink.argbInt()) else hanToneText(p.text, tones.drop(starts[i]), toneSys, ink.argbInt())
                        st.annotated()
                    }
                }
                TapWords(
                    count = pieces.size, lineSpacing = (-4).dp,
                    isTappable = { i -> i < pieces.size && (pieces[i].swapOf != null || (pieces[i].key != null && pieces[i].key != own)) },
                    onTap = { i ->
                        val p = pieces[i]
                        if (p.swapOf != null) swapWord = p.swapOf else p.key?.let { if (it != own) onWord(it) }
                    },
                ) { i, hot ->
                    val p = pieces[i]
                    val boxed = boxedOwn && p.key != null && p.key == own
                    Text(texts[i], style = ff(FF.Body),
                        modifier = Modifier.swell(hot).then(if (boxed) Modifier.background(T.olive.copy(alpha = 0.6f), RoundedCornerShape(4.dp)) else Modifier)
                            .padding(horizontal = if (Prefs.wordGap.value) 2.5.dp else 0.dp, vertical = 7.dp))
                }
                val r = remember(ex, tk, swaps, swapOff) { d.sentenceText(ex[1], rom, place, ex[0], zh).annotated() }
                Txt(r, lat(15f), T.greenInk)
            } else Txt(ex[0], ff(FF.Body), T.glyph)
            if (zh != null && zh.isNotEmpty()) Txt(zh, ff(FF.Footnote), T.muted)
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (ex.size > 1) SwapControl(d, ex[0], ex[1], zh, place, swaps, swapOff, rom)
            if (ex.size > 3 && ex[3].isNotEmpty()) PlayButton(Audio.examplePath(ex[3]), 28.dp)
        }
    }
    swapWord?.let { w ->
        AlertDialog(
            onDismissRequest = { swapWord = null }, containerColor = T.fn,
            title = { Txt(if (place in d.raw.places.indices) d.raw.places[place] + "怎麼講？" else "怎麼講？", ff(FF.Headline)) },
            text = {
                Column {
                    for ((h, c) in d.vocabOptions(w, place, zh)) {
                        TextButton(onClick = { chooseSwap(place, w, h); swapWord = null }) {
                            Text(h + "　" + d.codes(c.joinToString(" "), rom.coerceIn(0, 2), place), color = T.greenInk)
                        }
                    }
                    TextButton(onClick = { chooseSwap(place, w, w); swapWord = null }) {
                        val k = d.hanMap[w]?.firstOrNull()?.let { "$w\t$it" } ?: w
                        Text("原本的詞：" + w + "　" + d.word(k, rom.coerceIn(0, 2), -1), color = T.glyph)
                    }
                }
            },
            confirmButton = { TextButton(onClick = { swapWord = null }) { Text("取消", color = T.muted) } },
        )
    }
}

private fun examplePieces(d: Dict, han0: String, tpl0: String, zh: String?, place: Int): List<ExPiece> {
    val loc = if (place >= 0) d.localizedExample(han0, tpl0, place, zh) else Localized(han0, tpl0, emptySet(), emptyMap())
    val out = ArrayList<ExPiece>()
    var at = 0
    for ((text, key) in d.exampleWords(loc.han, loc.tpl)) {
        val chars = text.cps()
        if (chars.indices.any { loc.words[at + it] != null }) {
            val cur = StringBuilder(); var curOrig: String? = null; var curSw = false
            fun flush() { if (cur.isNotEmpty()) out.add(ExPiece(cur.toString(), null, curOrig, curSw)); cur.setLength(0) }
            for ((j, ch) in chars.withIndex()) {
                val o = loc.words[at + j]; val sw = loc.swapped.contains(at + j)
                if (o != curOrig || sw != curSw) { flush(); curOrig = o; curSw = sw }
                cur.append(ch)
            }
            flush()
        } else if (key == null && chars.size > 1) {
            for (ch in chars) out.add(ExPiece(ch, null, null, false))
        } else out.add(ExPiece(text, key, null, false))
        at += chars.size
    }
    return out
}

private fun chooseSwap(place: Int, word: String, pick: String) {
    val m = HashMap(try { if (Prefs.swaps.value.isEmpty()) emptyMap() else JReader(Prefs.swaps.value).strMap() } catch (_: Exception) { emptyMap() })
    m["$place|$word"] = pick
    Prefs.swaps.value = JWriter.any(m)
}

@Composable
private fun SwapControl(d: Dict, han0: String, tpl0: String, zh: String?, place: Int, swaps: String, swapOff: String, rom: Int) {
    if (place < 0) return
    val words = remember(han0, tpl0, place, swaps, swapOff) {
        val loc = d.localizedExample(han0, tpl0, place, zh)
        val out = ArrayList<String>()
        for (k in loc.words.keys.sorted()) { val w = loc.words[k]; if (!w.isNullOrEmpty() && !out.contains(w)) out.add(w) }
        out
    }
    if (words.isEmpty()) return
    val k = Dict.swapOffKey(han0, place)
    val on = !d.swapsOff().contains(k)
    var menu by remember { mutableStateOf(false) }
    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Txt("在地詞", ff(FF.Caption, FontWeight.Bold), if (on) T.pinkInk else T.muted)
            Switch(on, { v ->
                val s = d.swapsOff().toMutableSet()
                if (v) s.remove(k) else s.add(k)
                Prefs.swapOff.value = JWriter.any(s.sorted())
            }, modifier = Modifier.height(24.dp), colors = SwitchDefaults.colors(checkedTrackColor = T.swapInk))
        }
        if (on) Box {
            Row(Modifier.clip(CircleShape).background(T.pink).border(1.5.dp, T.pinkEdge, CircleShape).clickable { menu = true }
                .padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Txt("選詞", ff(FF.Caption, FontWeight.SemiBold), T.pinkInk)
                Icon(Icons.Filled.KeyboardArrowDown, null, tint = T.pinkInk, modifier = Modifier.size(14.dp))
            }
            DropdownMenu(menu, { menu = false }, containerColor = T.fn) {
                for (w in words) {
                    val cur = d.vocabSwap(w, place, zh)?.first ?: w
                    Txt("$w →", ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                    for ((h, c) in d.vocabOptions(w, place, zh)) {
                        DropdownMenuItem(text = { Text(h + "　" + d.codes(c.joinToString(" "), rom.coerceIn(0, 2), place), color = T.glyph) },
                            leadingIcon = { if (cur == h) Icon(Icons.Filled.Check, null, tint = T.greenInk) },
                            onClick = { chooseSwap(place, w, h); menu = false })
                    }
                    DropdownMenuItem(text = { Text("$w（原本的詞）", color = T.glyph) },
                        leadingIcon = { if (cur == w) Icon(Icons.Filled.Check, null, tint = T.greenInk) },
                        onClick = { chooseSwap(place, w, w); menu = false })
                }
            }
        }
    }
}

// MARK: - 各地讀音

@Composable
fun PlacesTable(d: Dict, key: String, always: Boolean = false) {
    val rom = Prefs.rom.value; val place = Prefs.place.value
    val main = Dict.codesOf(key)
    val colours = Prefs.toneSys.value != 0
    class G(val codes: String, val guessed: Boolean, val tones: List<Int>, val places: MutableList<Int>)
    val groups = remember(key, colours) {
        val out = ArrayList<G>()
        for (p in d.raw.places.indices) {
            // a place that says it like 通行 shares the 通行 box
            val c = if (d.differsFromCommon(key, p)) d.codesFor(key, p) else main
            val g = d.guessedSyllables(key, p).isNotEmpty()
            // with tone colours on, places whose tones change differently (泉 / 漳) get boxes of their own
            val t = if (colours) d.wordTones(key, p) else emptyList()
            val i = out.indexOfFirst { it.codes == c && it.guessed == g && it.tones == t }
            if (i >= 0) out[i].places.add(p) else out.add(G(c, g, t, mutableListOf(p)))
        }
        out
    }
    if (!(always || groups.any { it.codes != main } || d.raw.dia2?.get(key) != null)) return
    val commonBoxes = groups.count { it.codes == main }
    val tk = textKey()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Txt("各地讀音", ff(FF.Caption, FontWeight.Bold), T.muted)
        for (g in groups) {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.55f))
                .border(1.5.dp, if (g.places.contains(place)) T.placeEdge else Color.Transparent, RoundedCornerShape(12.dp)).padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp)) {
                val note = if (g.codes != main) "" else if (commonBoxes > 1) (if (g.places.any { d.quanSandhi(it) }) "（同通行，泉腔變調）" else "（同通行，漳腔變調）") else "（同通行）"
                Txt(g.places.joinToString("、") { d.raw.places[it].take(2) } + note,
                    ff(FF.Caption), if (g.places.contains(place)) T.oliveInk else T.muted)
                // the 通行 box is spelled the 通行 way, but with the tones as these places change them
                val shownIn = if (g.codes == main) -1 else g.places[0]
                val tonesIn = g.places[0]
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Txt(remember(key, shownIn, tonesIn, tk) { d.wordText(key, rom, shownIn, tonesIn).annotated() }, lat(17f), T.greenInk)
                    Txt(remember(key, shownIn, tonesIn, tk) { d.wordText(key, 3, shownIn, tonesIn).annotated() }, ff(FF.Subheadline), T.purpleInk)
                    if (g.guessed) Chip("推測", T.fn, T.fnEdge, T.muted)
                }
                val also = g.places.flatMap { d.alsoSaid(key, it) }.toSet().sorted()
                for (x in also) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    PlaceChip("也講")
                    Txt(d.codes(x, rom, g.places[0]), lat(15f), T.greenInk)
                    Txt(d.codes(x, 3, g.places[0]), ff(FF.Footnote), T.purpleInk)
                    val who = g.places.filter { d.alsoSaid(key, it).contains(x) }
                    if (who.size < g.places.size) Txt(who.joinToString("、") { d.raw.places[it].take(2) }, ff(FF.Caption2), T.muted)
                }
            }
        }
        Txt(if (colours) "推測 = 辭典沒有寫這個地方的讀音，是照規則推出來的。顏色是在詞尾以外的字照各地的變調（泉腔：2→5、5→3、8→3；漳腔：2→1、5→7、8→4）。"
            else "紅色／推測 = 辭典沒有寫這個地方的讀音，是照規則推出來的。", ff(FF.Caption2), T.muted)
    }
}

// MARK: - lists of words

/** one word in a list: 漢字, readings, a short meaning, and whether it's in 不熟 / 熟悉 / 收藏 */
@Composable
fun DictRow(d: Dict, key: String, modifier: Modifier = Modifier) {
    val rom = Prefs.rom.value; val place = Prefs.place.value
    val tk = textKey()
    Store.rev
    Column(modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Txt(remember(key, tk) { d.hanText(key, place, (if (d.isUser(key)) T.ownInk else T.glyph).argbInt()).annotated() }, sz(20f, FontWeight.SemiBold))
            Txt(remember(key, tk) { d.wordText(key, rom, place).annotated() }, lat(16f), T.greenInk, Modifier.weight(1f, fill = false), maxLines = 1)
            Txt(remember(key, tk) { d.wordText(key, 3, place).annotated() }, ff(FF.Footnote), T.purpleInk, Modifier.weight(1f, fill = false), maxLines = 1)
            Spacer(Modifier.weight(0.01f))
            if (d.isUser(key)) OwnChip()
            if (Store.isSaved(key)) Icon(Icons.Filled.Bookmark, null, tint = T.oliveInk, modifier = Modifier.size(14.dp))
            when (Store.cardStatus(key)) {
                2 -> Icon(Icons.Filled.Star, null, tint = T.rustInk, modifier = Modifier.size(14.dp))
                1 -> Icon(Icons.Filled.CheckCircle, null, tint = T.greenInk, modifier = Modifier.size(14.dp))
                else -> {}
            }
        }
        val g = d.gl[key]
        if (!g.isNullOrEmpty()) Txt(g.joinToString("、") { it.t }, ff(FF.Footnote), T.muted, maxLines = 1)
        else d.defText(key)?.let { Txt(it.replace("\n", " "), ff(FF.Footnote), T.muted, maxLines = 2) }
    }
}

/** a row that can be swiped: right = the start action, left = the end action (they snap back) */
@Composable
fun SwipeRow(
    start: Pair<String, Color>?, end: Pair<String, Color>?, onStart: () -> Unit = {}, onEnd: () -> Unit = {},
    onClick: () -> Unit, content: @Composable () -> Unit,
) {
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { v ->
        when (v) {
            SwipeToDismissBoxValue.StartToEnd -> if (start != null) onStart()
            SwipeToDismissBoxValue.EndToStart -> if (end != null) onEnd()
            else -> {}
        }
        false
    })
    SwipeToDismissBox(
        state, enableDismissFromStartToEnd = start != null, enableDismissFromEndToStart = end != null,
        backgroundContent = {
            val dir = state.dismissDirection
            val (label, color) = (if (dir == SwipeToDismissBoxValue.StartToEnd) start else end) ?: Pair("", Color.Transparent)
            Box(Modifier.fillMaxSize().background(color).padding(horizontal = 20.dp),
                contentAlignment = if (dir == SwipeToDismissBoxValue.StartToEnd) Alignment.CenterStart else Alignment.CenterEnd) {
                Txt(label, ff(FF.Subheadline, FontWeight.Bold), Color.White)
            }
        },
    ) {
        Box(Modifier.fillMaxWidth().background(T.fn).clickable(onClick = onClick)) { content() }
    }
}

/** words in a list (swipe right = 加到不熟, left = 收藏) */
fun LazyListScope.keyItems(d: Dict, title: String, keys: List<String>) {
    if (keys.isEmpty()) return
    if (title.isNotEmpty()) item { SectionTitle(title) }
    items(keys, key = { "k|$title|$it" }) { k ->
        val nav = LocalNav.current
        Store.rev
        Box(Modifier.clip(RoundedCornerShape(10.dp)).padding(vertical = 1.dp)) {
            SwipeRow(
                start = if (Store.cardStatus(k) == 0) Pair("加到不熟", T.rustEdge) else null,
                end = Pair(if (Store.isSaved(k)) "取消收藏" else "收藏", T.oliveEdge),
                onStart = { Store.toggleUnknown(k) }, onEnd = { Store.toggleSaved(k) },
                onClick = { nav.push(Route.Entry(k)) },
            ) { DictRow(d, k) }
        }
    }
}

@Composable
fun KeysPage(d: Dict, title: String, keys: List<String>, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        TopBar(title, onBack, settings = false)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) { keyItems(d, "", keys) }
    }
}

@Composable
fun SentencesPage(d: Dict, title: String, hits: List<SentenceHit>, onBack: () -> Unit) {
    val nav = LocalNav.current
    Column(Modifier.fillMaxSize()) {
        TopBar(title, onBack, settings = false)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { Txt("${hits.size} 句，短的在前面", ff(FF.Caption), T.muted) }
            items(hits) { h ->
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.55f))
                    .clickable { nav.push(Route.Entry(h.entry)) }.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    ExampleBlock(d, h.ex, own = h.word, boxedOwn = true)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Txt("出自", ff(FF.Caption), T.muted)
                        Txt(Dict.hanOf(h.entry), ff(FF.Caption), T.blueInk)
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted, modifier = Modifier.size(14.dp))
                    }
                }
            }
        }
    }
}

@Composable
fun PlacesBlock(d: Dict, e: PlaceGroup) {
    val nav = LocalNav.current
    val rom = Prefs.rom.value; val place = Prefs.place.value
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.7f)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Txt(e.zh, ff(FF.Headline), T.pinkInk, Modifier.background(T.pink, RoundedCornerShape(8.dp)).border(1.5.dp, T.pinkEdge, RoundedCornerShape(8.dp))
            .padding(horizontal = 10.dp, vertical = 3.dp))
        for (row in e.rows) {
            val key = d.keyOf(Opt(row.han, row.codes.split(' ')))
            Column(Modifier.fillMaxWidth().then(if (key != null && d.raw.defs.m[key] != null) Modifier.clickable { nav.push(Route.Entry(key)) } else Modifier),
                verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Txt(row.han, sz(18f, FontWeight.SemiBold), T.glyph)
                    Txt(d.codes(row.codes, rom, -1), lat(15f), T.greenInk)
                    Txt(d.codes(row.codes, 3, row.places.firstOrNull() ?: -1), ff(FF.Footnote), T.purpleInk)
                }
                Txt(row.places.mapNotNull { d.raw.places.getOrNull(it) }.joinToString("、"), ff(FF.Caption), if (row.places.contains(place)) T.oliveInk else T.muted)
            }
        }
    }
}

@Composable
fun PlacesPage(d: Dict, groups: List<PlaceGroup>, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        TopBar("各地講法", onBack, settings = false)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(groups) { PlacesBlock(d, it) }
        }
    }
}

/** 依詞類列出: every word class, with how many words it has */
@Composable
fun WordClassesPage(d: Dict, onBack: () -> Unit) {
    val nav = LocalNav.current
    Column(Modifier.fillMaxSize()) {
        TopBar("依詞類列出", onBack, settings = false)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
            item {
                ListCard {
                    for ((i, c) in Dict.wordClasses.withIndex()) {
                        if (i > 0) RowDivider()
                        Row(Modifier.fillMaxWidth().clickable { nav.push(Route.WordClass(c)) }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Txt(c, ff(FF.Body), if (c == "離合詞") T.pinkInk else T.glyph, Modifier.weight(1f))
                            Txt("${d.wordsOfClass(c).size}", ff(FF.Footnote), T.muted)
                            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun WordClassPage(d: Dict, cls: String, onBack: () -> Unit) {
    var all by remember { mutableStateOf(false) }
    val keys = remember(cls) { d.wordsOfClass(cls).sortedBy { Store.rankOf(it) } }
    Column(Modifier.fillMaxSize()) {
        TopBar(cls, onBack, settings = false)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
            keyItems(d, if (cls == "離合詞") "動詞裡面有名詞（${keys.size}）" else "${keys.size} 個詞", if (all) keys else keys.take(300))
            if (!all && keys.size > 300) item {
                TextButton(onClick = { all = true }) { Text("顯示全部（${keys.size}）", color = T.oliveInk) }
            }
        }
    }
}

@Composable
fun CategoryWordsPage(d: Dict, cat: Int, onBack: () -> Unit) {
    Store.rev
    val keys = remember(cat) { (d.catWords[cat] ?: emptyList()).sortedBy { Store.rankOf(it) } }
    val newOnes = keys.filter { Store.cardStatus(it) == 0 }
    Column(Modifier.fillMaxSize()) {
        TopBar(d.raw.cats?.getOrNull(cat) ?: "", onBack, settings = false)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
            item {
                SoftButton(onClick = { Store.addUnknown(keys) }, enabled = newOnes.isNotEmpty(), modifier = Modifier.fillMaxWidth()) {
                    IconLabel(if (newOnes.isEmpty()) Icons.Filled.Star else Icons.Filled.StarBorder,
                        if (newOnes.isEmpty()) "這個分類的新詞都在卡片裡了" else "新詞全部加到「不熟」（${newOnes.size}）", ff(FF.Subheadline))
                }
                Txt("最常用的在前面。往右滑一個詞加到「不熟」，往左滑收藏。", ff(FF.Footnote), T.muted, Modifier.padding(4.dp))
            }
            keyItems(d, "${keys.size} 個詞", keys)
        }
    }
}

/** 比較兩個詞: two words one above the other (side by side when the screen is wide) */
@Composable
fun ComparePage(d: Dict, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        TopBar("單詞比較", onBack, settings = false)
        BoxWithConstraints(Modifier.fillMaxSize()) {
            if (maxWidth > 700.dp) Row(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) { ComparePane(d, Prefs.compareA, "第一個詞") }
                Box(Modifier.width(1.dp).fillMaxHeight().background(T.fnEdge))
                Box(Modifier.weight(1f)) { ComparePane(d, Prefs.compareB, "第二個詞") }
            } else Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) { ComparePane(d, Prefs.compareA, "第一個詞") }
                Box(Modifier.height(1.dp).fillMaxWidth().background(T.fnEdge))
                Box(Modifier.weight(1f)) { ComparePane(d, Prefs.compareB, "第二個詞") }
            }
        }
    }
}

@Composable
private fun ComparePane(d: Dict, slot: com.unoki99.fangfang.Pref<String>, hint: String) {
    var query by remember { mutableStateOf("") }
    var found by remember { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(query) {
        if (query.isEmpty()) { found = emptyList(); return@LaunchedEffect }
        delay(200)
        val q = query
        val r = withContext(Dispatchers.Default) { Lookup.run(d, q, -1, Prefs) }
        val out = ArrayList<String>()
        for (k in r.tones + r.taigi + r.exact + r.contains + r.gloss) if (!out.contains(k)) out.add(k)
        found = out.take(40)
    }
    Column(Modifier.fillMaxSize()) {
        SearchField(query, { query = it }, hint, Modifier.padding(10.dp), family = null)
        val key = slot.value
        if (query.isNotEmpty()) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 10.dp)) {
                items(found) { k -> Box(Modifier.background(T.fn).clickable { slot.value = k; query = "" }) { DictRow(d, k) } }
            }
        } else if (key.isNotEmpty() && (d.raw.defs.m[key] != null || d.baseKeys.contains(key) || d.isUser(key))) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) { DictEntryBody(d, key); Spacer(Modifier.height(30.dp)) }
        } else Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Txt("查一個詞，選它。", ff(FF.Body), T.muted) }
    }
}

// MARK: - 詞典 tab

@Composable
fun DictionaryTab() {
    if (Store.isZh) { ZhDictionaryTab(); return }
    Column(Modifier.fillMaxSize()) {
        TopBar("詞典")
        DictGate { d ->
            var tab by Prefs.dictTab
            Column(Modifier.fillMaxSize()) {
                Segmented(listOf(0 to "查詞", 3 to "各地讀音", 1 to "分類", 2 to "收藏", 4 to "自訂"), tab, { tab = it },
                    Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                Box(Modifier.weight(1f)) {
                    when (tab) {
                        1 -> CategoryPane(d)
                        2 -> SavedPane(d)
                        3 -> PronunciationPane(d)
                        4 -> OwnPane(d)
                        else -> LookupPane(d)
                    }
                }
            }
        }
    }
}

/** a row of choices, one picked (like a segmented control) */
@Composable
fun <V> Segmented(options: List<Pair<V, String>>, selected: V, onSelect: (V) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(T.fn).border(1.dp, T.fnEdge, RoundedCornerShape(10.dp)).padding(2.dp)) {
        for ((v, name) in options) {
            val on = v == selected
            Box(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).background(if (on) T.key else Color.Transparent).clickable { onSelect(v) }
                .padding(vertical = 7.dp), contentAlignment = Alignment.Center) {
                Txt(name, ff(FF.Footnote, if (on) FontWeight.Bold else FontWeight.Normal), if (on) T.glyph else T.muted, maxLines = 1)
            }
        }
    }
}

@Composable
private fun LookupPane(d: Dict) {
    val nav = LocalNav.current
    var query by Prefs.lookupQuery
    val place = Prefs.place.value
    var result by remember { mutableStateOf(LookupResult()) }
    /** several words searched: the one whose 更多 is shown (null = the whole search) */
    var picked by remember { mutableStateOf<Int?>(null) }
    LaunchedEffect(query) { picked = null }
    LaunchedEffect(query, place) {
        delay(200)
        val q = query
        result = withContext(Dispatchers.Default) { Lookup.run(d, q, place, Prefs) }
    }
    val r = result
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
        item {
            SearchField(query, { query = it }, "華語、台語漢字、羅馬字或方音")
            Spacer(Modifier.height(8.dp))
            TileGrid(4) { i, m ->
                when (i) {
                    0 -> TileButton(Icons.AutoMirrored.Filled.List, "依詞類列出", m) { nav.push(Route.WordClasses) }
                    1 -> TileButton(Icons.Filled.VerticalSplit, "單詞比較", m) { nav.push(Route.Compare) }
                    2 -> TileButton(Icons.Filled.GridView, "部首查字", m) { nav.push(Route.Radicals(false)) }
                    else -> TileButton(Icons.Filled.Translate, "日語借詞", m) { nav.push(Route.Japanese) }
                }
            }
        }
        if (query.isNotEmpty() && r.empty) item { Txt("找不到「$query」。", ff(FF.Body), T.muted, Modifier.padding(8.dp)) }
        if (r.isPattern) {
            keyItems(d, "台語詞「$query」（${if (r.pattern.size == 300) "300+" else r.pattern.size.toString()}）", r.pattern)
            keyItems(d, "華語「$query」的台語講法", r.patternZh)
        } else if (query.isEmpty()) item {
            Txt("可以查華語、台語漢字、皓羅／台羅／白話字（聲調可以不打，例如 tsiah png）或方音。\n往右滑一個詞加到「不熟」，往左滑收藏。\n* 代表一個以上的字，? 代表剛好一個字：\n人* → 人開頭的詞　*仔 → 仔結尾　*水* → 水在中間　?仔 → 兩個字、仔結尾\n打聲調數字找聲調組合：4-5、2 2、817…",
                ff(FF.Footnote), T.muted, Modifier.padding(8.dp))
        }
        if (r.tones.isNotEmpty()) keyItems(d, "聲調「${query.filter { it.isDigit() }.toList().joinToString("-")}」（${if (r.tones.size >= 1000) "1000+" else r.tones.size.toString()}）", r.tones)
        r.toneNote?.let { item { Txt(it, ff(FF.Footnote), T.muted, Modifier.padding(8.dp)) } }
        keyItems(d, "台語「$query」", r.taigi)
        keyItems(d, "台語講法", r.exact)
        // several words searched at once: each word's words, then a capsule for each to see its 更多
        for ((i, w) in r.parts.withIndex()) {
            val pr = r.partResults[i]
            keyItems(d, "「$w」", pr.exact + pr.taigi.filter { it !in pr.exact })
        }
        if (r.parts.isNotEmpty()) item {
            Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Txt("點一個詞，看那個詞的更多", ff(FF.Footnote), T.muted, Modifier.padding(start = 4.dp))
                WordPickRow(r.parts, picked) { picked = it }
            }
        }
        val pi = picked
        if (pi != null && pi < r.partResults.size) moreItems(r.partResults[pi], r.parts[pi], nav) else moreItems(r, query, nav)
        item { Spacer(Modifier.height(40.dp)) }
    }
}

/** everything else, as a short list of pages right under 台語講法 */
private fun LazyListScope.moreItems(r: LookupResult, query: String, nav: NavStack) {
    val words = r.sentenceWords.take(3).joinToString("、")
    if (r.sentences.isEmpty() && r.contains.isEmpty() && r.places.isEmpty() && r.gloss.isEmpty() && r.defs.isEmpty()) return
    item {
        SectionTitle("更多")
        class MoreRow(val icon: androidx.compose.ui.graphics.vector.ImageVector, val title: String, val n: Int, val cap: Int, val route: Route)
        val rows = ArrayList<MoreRow>()
        if (r.sentences.isNotEmpty()) rows.add(MoreRow(Icons.Filled.FormatQuote, "句子裡有「$words」", r.sentences.size, 300, Route.Sentences("台語句子裡有「$words」", r.sentences)))
        if (r.contains.isNotEmpty()) rows.add(MoreRow(Icons.Filled.TextFields, "詞裡有「$query」", r.contains.size, 80, Route.Keys("台語詞裡有「$query」", r.contains)))
        if (r.places.isNotEmpty()) rows.add(MoreRow(Icons.Filled.Map, "各地講法", r.places.size, 6, Route.Places(r.places)))
        if (r.gloss.isNotEmpty()) rows.add(MoreRow(Icons.Filled.Search, "華語意思有「$query」", r.gloss.size, 60, Route.Keys("華語意思有「$query」", r.gloss)))
        if (r.defs.isNotEmpty()) rows.add(MoreRow(Icons.Filled.Book, "解釋裡有「$query」", r.defs.size, 60, Route.Keys("解釋裡有「$query」", r.defs)))
        TileGrid(rows.size) { i, m -> val row = rows[i]; TileButton(row.icon, row.title, m, row.n, row.cap) { nav.push(row.route) } }
    }
}

@Composable
private fun PronunciationPane(d: Dict) {
    val nav = LocalNav.current
    var query by Prefs.pronQuery
    val rom = Prefs.rom.value
    var keys by remember { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(query) {
        delay(250)
        val q = query
        keys = withContext(Dispatchers.Default) { Lookup.exact(d, q, Prefs) }
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item { SearchField(query, { query = it }, "台語漢字、羅馬字或方音，例如：做伙、四界、tsiah") }
        if (query.isEmpty()) item {
            Txt("查一個詞，看它在鹿港、三峽、臺北、宜蘭、臺南、高雄、金門、馬公、新竹、臺中各地的讀音。紅色／推測 = 辭典沒有寫，照規則推出來的。", ff(FF.Footnote), T.muted)
        } else if (keys.isEmpty()) item { Txt("找不到「$query」。", ff(FF.Body), T.muted) }
        items(keys) { k ->
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(T.fn.copy(alpha = 0.35f)).clickable { nav.push(Route.Entry(k)) }.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Txt(Dict.hanOf(k), sz(24f, FontWeight.SemiBold), T.glyph)
                    Txt("通行", ff(FF.Caption), T.muted)
                    Txt(d.word(k, rom.coerceIn(0, 2), -1), lat(16f), T.greenInk)
                    Txt(d.word(k, 3, -1), ff(FF.Footnote), T.purpleInk, Modifier.weight(1f))
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted)
                }
                PlacesTable(d, k, always = true)
            }
        }
    }
}

@Composable
private fun CategoryPane(d: Dict) {
    val nav = LocalNav.current
    var filter by remember { mutableStateOf("") }
    val names = d.raw.cats ?: emptyList()
    val counts = remember { d.catCounts }
    val shown = names.indices.filter { filter.isEmpty() || names[it].contains(filter) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
        item { SearchField(filter, { filter = it }, "找分類，例如：食物、稱謂、時間"); SectionTitle("${shown.size} 個分類（教育部辭典）") }
        items(shown) { i ->
            Row(Modifier.fillMaxWidth().background(T.fn.copy(alpha = 0.7f)).clickable { nav.push(Route.Category(i)) }.padding(14.dp)) {
                Txt(names[i], ff(FF.Body), T.glyph, Modifier.weight(1f))
                Txt("${counts[i] ?: 0}", ff(FF.Footnote), T.muted)
            }
            RowDivider()
        }
    }
}

@Composable
private fun SavedPane(d: Dict) {
    val nav = LocalNav.current
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val rom = Prefs.rom.value
    val keys = Store.savedKeys
    val senses = Store.savedSenses
    var menu by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf("") }
    val saveCsv = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri ->
        if (uri != null) ctx.contentResolver.openOutputStream(uri)?.use { it.write(pending.toByteArray()) }
    }
    val saveTxt = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri ->
        if (uri != null) ctx.contentResolver.openOutputStream(uri)?.use { it.write(pending.toByteArray()) }
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
        if (keys.isEmpty() && senses.isEmpty()) item {
            Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Txt("還沒有收藏", ff(FF.Headline), T.glyph)
                Txt("在「轉換」點一個詞，或在「查詞」打開一個詞，按「收藏」就會存在這裡。意思旁邊的書籤可以只收藏那個意思。", ff(FF.Footnote), T.muted)
            }
        } else {
            item {
                Box {
                    SoftButton(onClick = { menu = true }) { IconLabel(Icons.Filled.IosShare, "匯出收藏", ff(FF.Subheadline), T.oliveInk) }
                    DropdownMenu(menu, { menu = false }, containerColor = T.fn) {
                        DropdownMenuItem(text = { Text("匯出 CSV（Anki）", color = T.glyph) }, onClick = {
                            menu = false; pending = Store.savedCSV(d); saveCsv.launch("方方-收藏.csv")
                        })
                        DropdownMenuItem(text = { Text("匯出文字", color = T.glyph) }, onClick = {
                            menu = false; pending = keys.joinToString("\n") { Dict.hanOf(it) + "\t" + d.word(it, rom, -1) }; saveTxt.launch("方方-收藏.txt")
                        })
                    }
                }
                if (keys.isNotEmpty()) SectionTitle("${keys.size} 個詞（往左滑刪除，往右滑加到「不熟」）")
            }
            items(keys, key = { "s|$it" }) { k ->
                val st = Store.cardStatus(k)
                SwipeRow(
                    start = if (st != null && st != 2) Pair("加到不熟", T.rustEdge) else null, end = Pair("刪除", Color(0xFFB3261E)),
                    onStart = { Store.toggleUnknown(k) }, onEnd = { Store.unsave(listOf(k)) },
                    onClick = { nav.push(Route.Entry(k)) },
                ) { DictRow(d, k) }
                RowDivider()
            }
            if (senses.isNotEmpty()) item { SectionTitle("${senses.size} 個意思（往左滑刪除）") }
            items(senses, key = { "m|" + it.id }) { s ->
                val all = d.senses(s.key)
                if (s.sense < all.size) {
                    val m = all[s.sense]
                    SwipeRow(start = null, end = Pair("刪除", Color(0xFFB3261E)), onEnd = { Store.unsave(s) },
                        onClick = { nav.push(Route.Entry(s.key)) }) {
                        Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Txt(Dict.hanOf(s.key), sz(20f, FontWeight.SemiBold), T.glyph)
                                Txt(d.word(s.key, rom.coerceIn(0, 2), -1), lat(16f), T.greenInk, Modifier.weight(1f), maxLines = 1)
                                CopyIconButton {
                                    SenseCopy.text(d, s.key, s.sense, rom, Prefs.place.value, Prefs.copyTpl.value, Prefs.copyEx.value, Prefs.copySep.value)
                                }
                                Icon(Icons.Filled.Bookmark, null, tint = T.blueInk, modifier = Modifier.size(14.dp))
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Txt("${m.n}.", ff(FF.Footnote, FontWeight.Bold), T.muted)
                                if (m.pos.isNotEmpty()) Chip(m.pos, T.fn, T.fnEdge, T.muted)
                                Txt(m.text, ff(FF.Footnote), T.glyph, maxLines = 3)
                            }
                        }
                    }
                    RowDivider()
                }
            }
        }
    }
}

@Composable
private fun OwnPane(d: Dict) {
    val nav = LocalNav.current
    val rom = Prefs.rom.value
    var adding by remember { mutableStateOf(false) }
    val keys = Store.ownKeys
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
        item {
            SoftButton(onClick = { adding = true }, modifier = Modifier.fillMaxWidth()) { IconLabel(Icons.Filled.AddCircle, "加一個詞", ff(FF.Headline), T.ownInk) }
            Txt("自己加的詞不是教育部辭典的內容，在「轉換」和「詞典」都會用紫色和「自訂」標示。", ff(FF.Footnote), T.muted, Modifier.padding(6.dp))
            if (keys.isNotEmpty()) SectionTitle("${keys.size} 個詞（往左滑刪除）")
        }
        items(keys, key = { "o|$it" }) { k ->
            SwipeRow(start = null, end = Pair("刪除", Color(0xFFB3261E)), onEnd = { Store.removeOwn(k) }, onClick = { nav.push(Route.Entry(k)) }) {
                Row(Modifier.fillMaxWidth().padding(14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Txt(Dict.hanOf(k), sz(20f, FontWeight.SemiBold), T.ownInk)
                    Txt(d.codes(Dict.codesOf(k), rom.coerceIn(0, 2), -1), lat(16f), T.greenInk)
                    Txt(d.codes(Dict.codesOf(k), 3, -1), ff(FF.Footnote), T.purpleInk, Modifier.weight(1f))
                    OwnChip()
                }
            }
            RowDivider()
        }
    }
    if (adding) AddOwnWordDialog(d) { adding = false }
}

/** add a word: 漢字 and its reading (typed in 皓羅, 台羅, 白話字 or 方音) */
@Composable
fun AddOwnWordDialog(d: Dict, han0: String = "", reading0: String = "", onDone: () -> Unit) {
    var han by remember { mutableStateOf(han0) }
    var reading by remember { mutableStateOf(reading0) }
    val engine = remember { ConvertEngine(d, Prefs) }
    val fHan = remember { androidx.compose.ui.focus.FocusRequester() }
    val fReading = remember { androidx.compose.ui.focus.FocusRequester() }
    val check: Pair<List<String>?, String> = run {
        val h = han.trim()
        val chars = h.cps()
        when {
            h.isEmpty() -> Pair(null, "先寫漢字。")
            chars.any { !ConvertEngine.isHan(it.firstCp()) } -> Pair(null, "漢字欄只能寫漢字。")
            reading.trim().isEmpty() -> Pair(null, "再寫讀音。")
            else -> {
                var problem: String? = null
                val codes = ArrayList<String>()
                for (it in engine.convert(reading).items) {
                    if (it.space || it.newline) continue
                    val raw = it.raw
                    if (raw != null) {
                        if (raw.trim(' ', '-', '‑', '–').isEmpty()) continue
                        problem = "看不懂「$raw」這個讀音。"; break
                    }
                    val c = it.current.codes
                    if (c == null) { problem = "看不懂這個讀音。"; break }
                    codes.addAll(c)
                }
                val key = h + "\t" + codes.joinToString(" ")
                when {
                    problem != null -> Pair(null, problem)
                    codes.isEmpty() -> Pair(null, "看不懂這個讀音。")
                    codes.size != chars.size -> Pair(null, "讀音有 ${codes.size} 個音節，漢字有 ${chars.size} 個字，要一樣多。")
                    d.baseKeys.contains(key) || d.altParent[key] != null -> Pair(null, "辭典裡已經有這個詞了。")
                    Store.isOwn(key) -> Pair(null, "這個詞已經在「自訂」裡了。")
                    else -> Pair(codes, "")
                }
            }
        }
    }
    AlertDialog(
        onDismissRequest = onDone, containerColor = T.fn,
        title = { Txt("加一個詞", ff(FF.Headline)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(han, { han = it }, Modifier.focusRequester(fHan), label = { Text("漢字") }, placeholder = { Text("例：揣頭路") }, singleLine = true,
                    trailingIcon = { ClearIcon(han, { han = it }, fHan) })
                OutlinedTextField(reading, { reading = it }, Modifier.focusRequester(fReading), label = { Text("讀音") }, placeholder = { Text("例：tshuē-thâu-lōo") }, singleLine = true,
                    textStyle = lat(17f).copy(color = T.glyph), trailingIcon = { ClearIcon(reading, { reading = it }, fReading) })
                Txt("用皓羅、台羅、白話字或方音都可以。寫聲調比較準；沒寫聲調的話，請看下面的結果對不對。", ff(FF.Caption), T.muted)
                val codes = check.first
                if (codes != null) {
                    val cs = codes.joinToString(" ")
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Txt(han.trim(), sz(24f, FontWeight.SemiBold), T.ownInk); OwnChip()
                    }
                    Txt(d.codes(cs, 0, -1), lat(17f), T.greenInk)
                    Txt(d.codes(cs, 1, -1) + "　" + d.codes(cs, 2, -1), lat(14f), T.greenInk.copy(alpha = 0.8f))
                    Txt(d.codes(cs, 3, -1), ff(FF.Body), T.purpleInk)
                } else Txt(check.second, ff(FF.Footnote), T.muted)
            }
        },
        confirmButton = {
            TextButton(onClick = {
                check.first?.let { Store.addOwn(han.trim() + "\t" + it.joinToString(" ")); onDone() }
            }, enabled = check.first != null) { Text("加入", color = if (check.first != null) T.greenInk else T.muted) }
        },
        dismissButton = { TextButton(onClick = onDone) { Text("取消", color = T.muted) } },
    )
}
