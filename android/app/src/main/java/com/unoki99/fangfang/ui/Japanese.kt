package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

// MARK: - 日語's own pages, in the app's look: 活用 and 漢字 in a word's entry, 助詞, 助詞練習, 實驗室, 顏色
// (the same as the iPhone app's JaLab.swift). Everything else of 日語 is the same pages as the other languages.

/** (read so the pages are drawn again when a colour is picked) */
@Composable
private fun jaColorKey(): List<Int> = Prefs.jaColors.map { it.value } + Prefs.toneSys.value + (if (Prefs.toneGlow.value) 1 else 0)

/** a panel like the iPhone app's (a rounded box, a little lighter than the page) */
private fun Modifier.jaPanel(alpha: Float = 0.55f) = this.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = alpha))

// MARK: a word's entry: its kanji and its 活用

@Composable
fun JaWordExtras(z: ZhDict, e: ZhEntry) {
    val nav = LocalNav.current
    val kanji = remember(e.k) { e.h.cps().filter { JaKana.isKanji(it.firstCp()) }.distinct() }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // each kanji of a longer word: its card (a one-kanji word shows it at the top already)
        if (e.h.cpCount > 1) for (ch in kanji) if (z.charIndex[ch] != null) JaKanjiRow(z, ch)
        val cls = remember(e.k) { JaGrammar.classOf(e) }
        if (cls != null) {
            JaConjugationBlock(e, cls.first, cls.second)
            TileButton(Icons.Filled.Tune, tr("在實驗室組合這個詞"), Modifier.fillMaxWidth()) { nav.push(Route.JaLab(e.k)) }
        }
    }
}

/** one kanji of a word: its readings and meanings (KANJIDIC2); tap it for its card */
@Composable
fun JaKanjiRow(z: ZhDict, ch: String) {
    val i = z.charIndex[ch] ?: return
    val c = z.chars[i]
    jaColorKey()
    Store.rev
    Row(Modifier.jaPanel().clickable {
        val card = Store.cardFor(Lang.charKey(ch))
        if (card != null) UI.open(Sheet.CardSheet(card))
    }.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        Txt(z.hanText(ch, emptyList(), T.glyph.argbInt()).annotated(), sz(40f, FontWeight.SemiBold))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            c.readings.firstOrNull()?.let { r ->
                Txt(z.reading(listOf(r.zy), Prefs.zhRom.value).annotated(), lat(15f), T.greenInk, maxLines = 2)
                Txt(r.defs.filter { !it.second.startsWith("例：") }.take(4).joinToString(", ") { it.second }, ff(FF.Subheadline), T.glyph, maxLines = 2)
            }
            c.strokes?.let { Txt(tr("{0} 畫", it), ff(FF.Caption), T.muted) }
        }
        when (Store.cardStatus(Lang.charKey(ch))) {
            1 -> Icon(Icons.Filled.CheckCircle, null, tint = T.greenInk, modifier = Modifier.size(18.dp))
            2 -> Icon(Icons.Filled.Star, null, tint = T.rustInk, modifier = Modifier.size(18.dp))
            else -> {}
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted, modifier = Modifier.size(18.dp))
    }
}

/** 活用: every form of a verb or adjective in groups (plain and polite side by side, the voices together, the
 *  conditionals together), the word in its colours (the ending in the ending colour) */
@Composable
fun JaConjugationBlock(e: ZhEntry, cls: JaClass, text: String) {
    val rom = Prefs.zhRom.value
    val ck = jaColorKey()
    val reading = remember(e.k) { JaGrammar.readingOf(e, cls) }
    val hasKanji = remember(e.k) { e.h.cps().any { JaKana.isKanji(it.firstCp()) } }
    val groups = remember(e.k) { JaGrammar.groups(cls) }
    Column(Modifier.jaPanel().padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Txt(tr("活用"), ff(FF.Caption, FontWeight.Bold), T.muted)
            Chip(tr(cls.name), T.olive, T.oliveEdge, T.oliveInk)
        }
        BoxWithConstraints {
            val wide = maxWidth >= 600.dp
            // two-form groups two to a row on a tablet; bigger ones a row of their own; the one-form groups together
            val pairs = groups.filter { it.rows.size == 2 }
            val bigs = groups.filter { it.rows.size > 2 }
            val singles = groups.filter { it.rows.size == 1 }
            @Composable fun form(row: Triple<String, String, List<String>>, m: Modifier) {
                val ch = remember(e.k, ck, rom, row) { JaGrammar.Chain(text, cls).adding(row.third) } ?: return
                val r = remember(e.k, row) { JaGrammar.Chain(reading, cls).adding(row.third) }
                Column(m.clip(RoundedCornerShape(10.dp)).background(T.fn.copy(alpha = 0.7f)).padding(10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Txt(tr(row.first), ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.weight(1f))
                        Txt(row.second, ff(FF.Caption2), T.muted, maxLines = 1)
                    }
                    Txt(JaInk.styled(ch.pieces).annotated(), sz(21f, FontWeight.SemiBold), maxLines = 1)
                    val sub: AnnotatedString? = when {
                        hasKanji && r != null -> if (rom == 0) AnnotatedString(JaKana.romaji(r.text)) else JaInk.styled(r.pieces).annotated()
                        rom == 0 -> AnnotatedString(JaKana.romaji(ch.text))
                        else -> null
                    }
                    if (sub != null) Txt(sub, lat(13f), T.greenInk, maxLines = 1)
                }
            }
            @Composable fun group(g: JaGrammar.ConjGroup, cols: Int, m: Modifier) {
                val tint = Color(g.color)
                Column(m.clip(RoundedCornerShape(12.dp)).background(tint.copy(alpha = 0.08f))
                    .border(1.5.dp, tint.copy(alpha = 0.45f), RoundedCornerShape(12.dp)).padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(8.dp).clip(CircleShape).background(tint))
                        Txt(tr(g.name), ff(FF.Caption, FontWeight.Bold), tint)
                        Txt(g.en, ff(FF.Caption2), T.muted, maxLines = 1)
                    }
                    for (line in g.rows.chunked(maxOf(1, cols))) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (row in line) form(row, Modifier.weight(1f))
                        repeat(cols - line.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for (line in pairs.chunked(if (wide) 2 else 1)) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (g in line) group(g, 2, Modifier.weight(1f))
                    if (wide && line.size == 1) Spacer(Modifier.weight(1f))
                }
                for (g in bigs) group(g, if (wide) g.rows.size else 2, Modifier.fillMaxWidth())
                if (singles.isNotEmpty()) for (line in singles.chunked(if (wide) singles.size else 2)) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (g in line) group(g, 1, Modifier.weight(1f))
                    repeat((if (wide) singles.size else 2) - line.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

// MARK: - 助詞: the map, the groups, each with examples

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun JaParticlesPage(onBack: () -> Unit) {
    var open by remember { mutableStateOf<JaParticle?>(null) }
    jaColorKey()
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("助詞"), onBack, settings = false)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            TileButton(Icons.Filled.Extension, tr("助詞練習"), Modifier.fillMaxWidth()) { UI.practice = Practice.JA_PARTICLES }
            // 用法地圖: one sentence, each particle under it with what it does; then the order of a sentence
            Column(Modifier.jaPanel().padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Txt(tr("用法地圖"), ff(FF.Caption, FontWeight.Bold), T.muted)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (piece in JaInk.marked(JaParticles.mapSentence)) {
                        val p = if (piece.kind == JaPiece.Kind.PARTICLE) JaParticles.all.firstOrNull { it.p == piece.text } else null
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            if (p != null) {
                                Txt(piece.text, sz(24f, FontWeight.SemiBold), Color(JaColors.particle),
                                    Modifier.clip(RoundedCornerShape(6.dp)).background(T.fn)
                                        .border(1.5.dp, Color(JaColors.particle).copy(alpha = 0.7f), RoundedCornerShape(6.dp))
                                        .clickable { open = p }.padding(horizontal = 5.dp))
                                Txt(tr(JaParticles.role(p.p)), ff(FF.Caption2), T.muted)
                            } else {
                                Txt(JaInk.styled(listOf(piece)).annotated(), sz(24f))
                                Txt(" ", ff(FF.Caption2), T.muted)
                            }
                        }
                    }
                }
                Txt(JaParticles.mapEnglish, ff(FF.Footnote), T.muted)
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    for ((name, ps) in JaParticles.order) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Txt(tr(name), ff(FF.Caption, FontWeight.Bold), T.glyph, Modifier.width(92.dp))
                        for (p in ps) Txt(p, sz(17f, FontWeight.SemiBold), Color(JaColors.particle),
                            Modifier.clip(CircleShape).background(T.fn).border(1.dp, T.fnEdge, CircleShape)
                                .clickable { open = JaParticles.all.firstOrNull { it.p == p } }.padding(horizontal = 8.dp, vertical = 2.dp))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Txt(tr("動詞"), ff(FF.Caption, FontWeight.Bold), T.glyph, Modifier.width(92.dp))
                        Txt(tr("最後：動詞或形容詞，再加語尾"), ff(FF.Caption), Color(JaColors.suffix))
                    }
                }
            }
            for ((g, en) in JaParticles.groups) {
                val ps = JaParticles.all.filter { it.group == g }
                if (ps.isEmpty()) continue
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Chip(tr(g), T.btn, T.btnEdge, T.btnInk)
                        Txt(en, ff(FF.Caption), T.muted)
                    }
                    for (p in ps) Row(Modifier.jaPanel().clickable { open = p }.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Txt(p.p, sz(26f, FontWeight.SemiBold), Color(JaColors.particle), Modifier.widthIn(min = 48.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Txt(tr(p.zh), ff(FF.Subheadline), T.glyph)
                            p.ex.firstOrNull()?.let { Txt(JaInk.styled(JaInk.marked(it.first)).annotated(), sz(17f)) }
                        }
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted, modifier = Modifier.size(18.dp))
                    }
                }
            }
            Txt(tr("說明和例句是方方詞卡自己寫的。"), ff(FF.Caption2), T.muted)
            Spacer(Modifier.height(30.dp))
        }
    }
    open?.let { p -> JaParticleDialog(p) { open = null } }
}

@Composable
private fun JaParticleDialog(p: JaParticle, close: () -> Unit) {
    AlertDialog(onDismissRequest = close, containerColor = T.bg,
        confirmButton = { TextButton(onClick = close) { Text(tr("完成"), color = T.btnInk) } },
        title = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Txt(p.p, sz(48f, FontWeight.SemiBold), Color(JaColors.particle))
                PlayButton("tts:" + p.p)
            }
        },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Txt(tr(p.zh), ff(FF.Body), T.glyph)
                Txt(p.en, ff(FF.Subheadline), T.muted)
                for ((jp, en) in p.ex) Column(Modifier.jaPanel().padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Txt(JaInk.styled(JaInk.marked(jp)).annotated(), sz(22f), modifier = Modifier.weight(1f))
                        PlayButton("tts:" + JaInk.plainText(jp))
                    }
                    Txt(en, ff(FF.Subheadline), T.muted)
                }
            }
        })
}

// MARK: 助詞練習: a sentence missing a particle, pick it

private class JaQuizQ(val p: JaParticle, val before: String, val after: String, val english: String, val choices: List<String>)

private fun jaQuizNext(): JaQuizQ? {
    repeat(20) {
        val p = JaParticles.all.random()
        val ex = p.ex.random()
        val mark = "[" + p.p + "]"
        val at = ex.first.indexOf(mark)
        if (at < 0) return@repeat
        val cs = mutableListOf(p.p)
        for (o in JaParticles.all.map { it.p }.shuffled()) if (o !in cs && cs.size < 4) cs.add(o)
        return JaQuizQ(p, ex.first.substring(0, at), ex.first.substring(at + mark.length), ex.second, cs.shuffled())
    }
    return null
}

@Composable
fun JaParticleQuiz(onClose: () -> Unit) {
    var q by remember { mutableStateOf(jaQuizNext()) }
    var picked by remember { mutableStateOf<String?>(null) }
    var right by remember { mutableIntStateOf(0) }
    var done by remember { mutableIntStateOf(0) }
    jaColorKey()
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("助詞練習"), onClose, close = true, settings = false) {
            Txt("$right / $done", ff(FF.Subheadline), T.muted)
        }
        val cur = q ?: return@Column
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Spacer(Modifier.height(12.dp))
            val sentence = JaInk.styled(JaInk.marked(cur.before)) +
                (if (picked == null) styled("（　）") else JaInk.styled(listOf(JaPiece(cur.p.p, JaPiece.Kind.PARTICLE)))) +
                JaInk.styled(JaInk.marked(cur.after))
            Txt(sentence.annotated(), sz(30f).copy(textAlign = TextAlign.Center))
            Txt(cur.english, ff(FF.Subheadline).copy(textAlign = TextAlign.Center), T.muted)
            Column(Modifier.widthIn(max = 480.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for (line in cur.choices.chunked(2)) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (c in line) {
                        val p = picked
                        val isRight = c == cur.p.p
                        val fill = if (p == null) T.fn.copy(alpha = 0.85f) else if (isRight) T.green else if (c == p) T.rust else T.fn.copy(alpha = 0.6f)
                        val edge = if (p == null) T.fnEdge else if (isRight) T.greenEdge else if (c == p) T.rustEdge else T.fnEdge.copy(alpha = 0.5f)
                        val ink = if (p == null) Color(JaColors.particle) else if (isRight) T.greenInk else if (c == p) T.rustInk else T.muted
                        Box(Modifier.weight(1f).heightIn(min = 64.dp).clip(RoundedCornerShape(16.dp)).background(fill)
                            .border(1.5.dp, edge, RoundedCornerShape(16.dp))
                            .clickable(enabled = p == null) { picked = c; done++; if (isRight) right++ },
                            contentAlignment = Alignment.Center) {
                            Txt(c, sz(26f, FontWeight.SemiBold), ink)
                        }
                    }
                }
            }
            if (picked != null) {
                Txt(tr(cur.p.zh), ff(FF.Subheadline).copy(textAlign = TextAlign.Center), T.glyph)
                ProminentButton(onClick = { picked = null; q = jaQuizNext() }, Modifier.widthIn(min = 220.dp)) { Text(tr("下一題")) }
            }
        }
    }
}

// MARK: - 實驗室: put a word together on wheels, see what each part does
//
// Search a verb or adjective (日語 or English). The wheels: up to five endings, one after another. Each part has its
// own colour; a kana the next part changes goes with that part (書・かな・い, 食べ・られ・な・かった).

private class JaLabWord(val text: String, val reading: String, val cls: JaClass, val en: String, val key: String?) {
    companion object {
        fun of(e: ZhEntry): JaLabWord? {
            val (c, t) = JaGrammar.classOf(e) ?: return null
            return JaLabWord(t, JaGrammar.readingOf(e, c), c, JaEnglish.base(e, c), e.k)
        }
    }
    override fun equals(other: Any?) = other is JaLabWord && other.text == text && other.reading == reading
    override fun hashCode() = text.hashCode() * 31 + reading.hashCode()
}

private val labSamples = listOf("食べる", "書く", "行く", "飲む", "話す", "待つ", "遊ぶ", "泳ぐ", "買う", "見る", "する", "来る", "勉強", "高い", "いい", "静か")
/** each part added gets the next of the app's rainbow shades (not yellow and green: kanji and hiragana are those) */
private val labPalette = listOf(0xffa94d, 0x4fd8c4, 0x6eaaff, 0xc39bff, 0xff8cc6, 0xff6b6b).map { (0xFF000000.toInt()) or it }
private fun partColor(i: Int): Int? = if (i == 0) null else labPalette[(i - 1) % labPalette.size]

private class LabSplit(var base: String, var tail: String, var ending: String)

private fun common(a: String, b: String): String {
    val x = a.cps(); val y = b.cps()
    var n = 0
    while (n < x.size && n < y.size && x[n] == y[n]) n++
    return x.take(n).joinToString("")
}
private fun dropCps(s: String, n: Int): String = s.cps().drop(n).joinToString("")

/** each part of the word: what stays, what its end changed to because of the part after it, and (the last part) its
 *  own ending (食べ・る, な・い, ま・す) */
private fun labSplits(c: JaGrammar.Chain): List<LabSplit> {
    val out = ArrayList<LabSplit>()
    for ((i, p) in c.pieces.withIndex()) {
        val pre = common(p.text, p.dict)
        val sp = LabSplit(pre, dropCps(p.text, pre.cpCount), "")
        if (i == c.pieces.size - 1 && sp.tail.isEmpty() && (c.cls.isVerb || c.cls.isAdj || c.cls === JaClass.Masu)) {
            JaGrammar.stem(p.text, c.cls, JaForm.I)?.let { st ->
                val b = common(p.text, st)
                sp.base = b
                sp.ending = dropCps(p.text, b.cpCount)
            }
        }
        out.add(sp)
    }
    return out
}

/** a run of text in part i's colour (the word itself: kanji and kana in their colours) */
private fun labRun(s: String, i: Int): Styled { val c = partColor(i) ?: return JaInk.word(s); return styled(s, c) }

/** the word as its steps: each one the kana the step before changed and this part, in its own colour */
private fun labSegments(c: JaGrammar.Chain): List<Styled> {
    val sp = labSplits(c)
    val out = ArrayList<Styled>()
    for (i in sp.indices) {
        val seg = ArrayList<Seg>()
        if (i > 0 && sp[i - 1].tail.isNotEmpty()) seg.addAll(labRun(sp[i - 1].tail, i - 1))
        if (sp[i].base.isNotEmpty()) seg.addAll(labRun(sp[i].base, i))
        if (seg.isNotEmpty()) out.add(seg)
    }
    sp.lastOrNull()?.let { l ->
        val n = sp.size - 1
        if (l.ending.isNotEmpty()) out.add(labRun(l.ending, n)) else if (l.tail.isNotEmpty()) out.add(labRun(l.tail, n))
    }
    return out
}

/** the steps one after another (each in its own colour, nothing between them) */
private fun labJoined(segs: List<Styled>): Styled = segs.flatten()

/** a tablet: bigger wheels and text */
@Composable
private fun labBig(): Boolean = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp >= 700

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun JaLabPage(z: ZhDict, startKey: String?, onBack: () -> Unit) {
    var word by remember { mutableStateOf<JaLabWord?>(null) }
    var query by remember { mutableStateOf("") }
    var found by remember { mutableStateOf<List<ZhEntry>>(emptyList()) }
    val steps = remember { mutableStateListOf(0, 0, 0, 0, 0) }
    jaColorKey()
    val rom = Prefs.zhRom.value
    LaunchedEffect(Unit) {
        if (word == null) word = startKey?.let { z.entry(it) }?.let { JaLabWord.of(it) } ?: labSamples.firstNotNullOfOrNull { s ->
            (z.byHan[s] ?: emptyList<Int>()).firstNotNullOfOrNull { JaLabWord.of(z.entries[it]) }
        }
    }
    LaunchedEffect(query) {
        val q = query
        if (q.isBlank()) { found = emptyList(); return@LaunchedEffect }
        delay(200)
        found = withContext(Dispatchers.Default) {
            val f = z.search(q)
            val order = if (f.englishFirst) f.english + f.words + f.starts else f.words + f.starts + f.english
            val seen = HashSet<Int>(); val out = ArrayList<ZhEntry>()
            for (i in order) {
                if (i >= z.entries.size || !seen.add(i)) continue
                if (JaGrammar.classOf(z.entries[i]) != null) out.add(z.entries[i])
                if (out.size >= 12) break
            }
            out
        }
    }
    fun pick(w: JaLabWord?) { word = w; for (j in steps.indices) steps[j] = 0 }

    Column(Modifier.fillMaxSize()) {
        TopBar(tr("實驗室"), onBack)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            // choosing the word
            SearchField(query, { query = it }, tr("查動詞或形容詞（日語、羅馬字或英文），例如：taberu、書く、eat"))
            if (query.isEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (s in labSamples) {
                        val e = (z.byHan[s] ?: emptyList<Int>()).map { z.entries[it] }.firstOrNull { JaGrammar.classOf(it) != null } ?: continue
                        val w = JaLabWord.of(e) ?: continue
                        val on = word == w
                        Txt(z.hanText(e.h, e.tw, T.glyph.argbInt()).annotated(), ff(FF.Subheadline, FontWeight.SemiBold), T.glyph,
                            Modifier.clip(CircleShape).background(if (on) T.btn else T.fn.copy(alpha = 0.8f))
                                .border(1.5.dp, if (on) T.btnEdge else T.fnEdge, CircleShape).clickable { pick(w) }
                                .padding(horizontal = 10.dp, vertical = 5.dp))
                    }
                }
            } else if (found.isEmpty()) Txt(tr("沒有找到會變化的詞（動詞、形容詞）。"), ff(FF.Footnote), T.muted)
            else Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (e in found) Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.7f))
                    .clickable { pick(JaLabWord.of(e)); query = "" }) { ZhWordRow(z, e) }
            }
            val w = word ?: return@Column
            LabWheels(w, steps)
            LabPane(z, w, labChosen(w, steps), rom)
            Spacer(Modifier.height(30.dp))
        }
    }
}

/** the chain after the first k wheels (null: a wheel before it stopped) */
private fun labChain(w: JaLabWord, steps: List<Int>, upTo: Int): JaGrammar.Chain? {
    var c = JaGrammar.Chain(w.text, w.cls, "「${w.text}」" + tr(w.cls.name))
    for (j in 0 until upTo) {
        val opts = labOptions(c)
        val s = opts[minOf(steps[j], opts.size - 1)] ?: return null
        c = c.adding(s.id) ?: return null
    }
    return c
}
/** what can come after a chain: stopping here (null), then each ending */
private fun labOptions(c: JaGrammar.Chain): List<JaGrammar.Suffix?> = if (c.cls === JaClass.Done) listOf(null) else listOf(null) + c.next
private fun labChosen(w: JaLabWord, steps: List<Int>): JaGrammar.Chain {
    var last = JaGrammar.Chain(w.text, w.cls, "「${w.text}」" + tr(w.cls.name))
    for (k in 0..steps.size) { last = labChain(w, steps, k) ?: break }
    return last
}

/** a wheel's row: the step this ending makes (the changed kana before it in the colour of the part it belongs to) */
private fun labRow(before: JaGrammar.Chain, s: JaGrammar.Suffix?): Styled {
    val k = before.pieces.size
    if (s == null) {
        val l = labSplits(before).lastOrNull()
        if (l != null && l.ending.isNotEmpty()) return labRun(l.ending, k - 1)
        return styled("—", T.muted.argbInt())
    }
    val n = before.adding(s.id) ?: return styled("—")
    val sp = labSplits(n)
    val out = ArrayList<Seg>()
    if (k - 1 < sp.size && sp[k - 1].tail.isNotEmpty()) out.addAll(labRun(sp[k - 1].tail, k - 1))
    if (k < sp.size) out.addAll(labRun(if (sp[k].base.isEmpty() && sp[k].ending.isEmpty()) n.pieces[k].text.ifEmpty { "∅" } else sp[k].base, k))
    return out.ifEmpty { styled("∅") }
}

@Composable
private fun LabWheels(w: JaLabWord, steps: MutableList<Int>) {
    val big = labBig()
    val wheelH = if (big) 300.dp else 170.dp
    val base = JaGrammar.Chain(w.text, w.cls)
    val first = labSplits(base).firstOrNull()
    Column(Modifier.jaPanel().padding(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        // (the wheels glide to their new places when one comes or goes)
        Row(Modifier.horizontalScroll(rememberScrollState()).animateContentSize(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Top) {
            // the word's part that stays (食べ, 書): not on a wheel
            Column(Modifier.widthIn(min = 44.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Txt(tr("詞"), ff(if (big) FF.Footnote else FF.Caption2, FontWeight.Bold), T.muted)
                Box(Modifier.height(wheelH), contentAlignment = Alignment.Center) {
                    Txt(JaInk.word(first?.base?.ifEmpty { null } ?: w.text).annotated(), sz(if (big) 34f else 22f, FontWeight.SemiBold), maxLines = 1)
                }
            }
            for (k in steps.indices) {
                val before = labChain(w, steps, k) ?: break
                if (k > 0 && steps[k - 1] == 0) break
                val opts = labOptions(before)
                if (opts.size <= 1) break
                val sel = minOf(steps[k], opts.size - 1)
                Column(Modifier.width(if (big) 150.dp else 104.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Txt(tr("接 {0}", k + 1), ff(if (big) FF.Footnote else FF.Caption2, FontWeight.Bold), T.muted)
                    Column(Modifier.height(wheelH).fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(T.bg.copy(alpha = 0.35f))
                        .verticalScroll(rememberScrollState()).padding(4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        for ((i, o) in opts.withIndex()) {
                            val on = i == sel
                            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                                .background(if (on) T.btn else Color.Transparent)
                                .border(if (on) 1.5.dp else 0.dp, if (on) T.btnEdge else Color.Transparent, RoundedCornerShape(10.dp))
                                .clickable { steps[k] = i; for (j in k + 1 until steps.size) steps[j] = 0 }
                                .padding(vertical = if (big) 8.dp else 4.dp, horizontal = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                Txt(labRow(before, o).annotated(), sz(if (big) 30f else 19f, FontWeight.SemiBold), maxLines = 1)
                                val name = o?.let { tr(it.name) } ?: if (labSplits(before).lastOrNull()?.ending?.isNotEmpty() == true) tr("辭書形") else tr("到這裡")
                                Txt(name, ff(if (big) FF.Footnote else FF.Caption2), if (on) T.btnInk else T.muted, maxLines = 1)
                            }
                        }
                    }
                }
            }
        }
        Txt(tr("一個滾輪接一個部分，每一部分一個顏色。最後一個音節會變的話，它跟著下一個部分出現（書 ＋ かな ＋ い）。"),
            ff(FF.Caption).copy(textAlign = TextAlign.Center), T.muted)
    }
}

/** what the word chosen means: the word in its steps, its reading, rōmaji with a hyphen between the parts, the
 *  English (put together by rule), and each part */
@Composable
private fun LabPane(z: ZhDict, w: JaLabWord, c: JaGrammar.Chain, rom: Int) {
    val nav = LocalNav.current
    val reading = if (w.reading == w.text) null else JaGrammar.Chain(w.reading, w.cls).adding(c.ops)
    val readSegs = labSegments(reading ?: c).map { it.plain() }
    val en = if (w.en.startsWith("be ") || !(w.cls.isAdj || w.cls === JaClass.AdjNa)) w.en else "be " + w.en
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.jaPanel().padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Txt(labJoined(labSegments(c)).annotated(), sz(if (labBig()) 48f else 34f, FontWeight.SemiBold), modifier = Modifier.weight(1f, fill = false))
                PlayButton("tts:" + (reading?.text ?: c.text))
            }
            if (reading != null) Txt(labJoined(labSegments(reading)).annotated(), sz(if (labBig()) 22f else 18f))
            // rōmaji, a hyphen between the parts: tabe-rare-ru
            Txt(readSegs.joinToString("-") { JaKana.romaji(it) }, lat(17f), T.greenInk)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Chip(tr("英"), T.fn, T.fnEdge, T.muted)
                Txt(JaEnglish.compose(en, c.ops), ff(FF.Body, FontWeight.SemiBold), T.glyph)
            }
            Txt(tr("（英文是依規則組合出來的大意）"), ff(FF.Caption2), T.muted)
        }
        Column(Modifier.jaPanel().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Txt(tr("每一部分"), ff(FF.Caption, FontWeight.Bold), T.muted)
            for ((n, p) in c.pieces.withIndex()) {
                val col = partColor(n)?.let { Color(it) }
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(T.fn.copy(alpha = 0.7f)).padding(10.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Txt((if (p.text.isEmpty()) styled("∅") else labRun(p.text, n)).annotated(), sz(24f, FontWeight.SemiBold), modifier = Modifier.widthIn(min = 64.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(8.dp).clip(CircleShape).background(col ?: Color(JaColors.kanji)))
                            Txt(tr(p.label), ff(FF.Subheadline, FontWeight.Bold), col ?: T.glyph)
                        }
                        if (p.note.isNotEmpty()) Txt(p.note, ff(FF.Footnote), T.muted)
                    }
                }
            }
        }
        val e = w.key?.let { z.entry(it) }
        if (e != null) TileButton(Icons.Filled.MenuBook, tr("在詞典看「{0}」", e.h), Modifier.fillMaxWidth()) { nav.push(Route.ZhEntry(e.k)) }
    }
}

// MARK: 設定 → 日語的顏色

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun JaColorSettingsPage(onBack: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("日語的顏色"), onBack, settings = false)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) { JaColorSettingsBody() }
    }
}

/** the colours of kanji, hiragana, katakana, particles and suffixes (設定 → 顏色與外觀 → 日語的顏色): the same picker
 *  and balls as the tones' colours */
@Composable
fun JaColorSettingsBody() = ToneColorPickerBody(4)
