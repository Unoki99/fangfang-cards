package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import com.unoki99.fangfang.UILang
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.engine.*

// MARK: - 瑞典語 (the computer version only): the parts of a word, a part's page, the sentences, a word the dictionary
// doesn't have. The same as the iPhone app's (SvMorphology.swift).

private fun svColorKey(): List<Any> = Prefs.svColors.map { it.value } + Prefs.toneSys.value + Prefs.svGuessZh.value + Prefs.svMeanings.value

/** 瑞典語 in an entry: its Chinese meanings, the word in its parts (tap one to see what it means and does) and its
 *  forms (the ending of each in colour) */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SvWordExtras(z: ZhDict, e: ZhEntry) {
    val nav = LocalNav.current
    svColorKey()
    val ms = remember(e.k) { SvMorpheme.parse(z.svSyl(e)) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        val zh = e.svZh
        if (zh.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Chip(tr("中"), T.rust, T.rustEdge, T.rustInk)
            Txt(zh.joinToString("、"), ff(FF.Body), T.glyph, Modifier.weight(1f, fill = false))
            if (e.svZhGuessed) Txt(tr("（由英文推測）"), ff(FF.Caption), T.muted)
        }
        SvVia.found[e.k]?.let { v ->
            Txt(tr("由華語「{0}」的英文（{1}）找到的，不一定是同一個意思。", v.zh, v.en), ff(FF.Caption), T.muted)
        }
        if (ms.size > 1) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.55f)).padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Txt(tr("詞的組成（點一個看它的意思）"), ff(FF.Caption, FontWeight.SemiBold), T.muted)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for ((i, m) in ms.withIndex()) {
                    if (m.kind == SvMorpheme.Kind.SPACE) { Spacer(Modifier.width(14.dp)); continue }
                    if (i > 0 && ms[i - 1].kind != SvMorpheme.Kind.SPACE) Txt("+", ff(FF.Subheadline), T.muted, Modifier.align(Alignment.CenterVertically))
                    SvPartBox(z, m, ms) { nav.push(Route.SvPart(e.k, i)) }
                }
            }
        }
        if (e.eq.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chip(tr("變化"), T.blue, T.blueEdge, T.blueInk)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (f in e.eq) Txt(remember(f, svColorKey()) { SvColors.styledOf(SvMorpheme.forForm(f, e.h, ms), T.glyph.argbInt(), true).annotated() }, lat(16f),
                    modifier = Modifier.clip(CircleShape).background(T.fn.copy(alpha = 0.8f)).padding(horizontal = 8.dp, vertical = 3.dp))
            }
        }
    }
}

@Composable
private fun SvPartBox(z: ZhDict, m: SvMorpheme, ms: List<SvMorpheme>, onClick: () -> Unit) {
    val c = Color(SvColors.colorOf(m, ms))
    Column(Modifier.clip(RoundedCornerShape(10.dp)).background(c.copy(alpha = 0.45f)).border(1.5.dp, c, RoundedCornerShape(10.dp))
        .clickable(onClick = onClick).hand().padding(horizontal = 10.dp, vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Txt(m.text, lat(20f).copy(fontWeight = FontWeight.SemiBold), T.glyph)
        Txt(tr(m.kindName), ff(FF.Caption2), T.muted)
        remember(m, SvGuess.show) { z.svPartGloss(m) }?.let { Txt(it, ff(FF.Caption2), T.glyph.copy(alpha = 0.85f), maxLines = 1) }
    }
}

/** one part of a word: what it is, what it means and does, and the other words with it */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SvPartPage(z: ZhDict, key: String, index: Int, onBack: () -> Unit) {
    val nav = LocalNav.current
    val e = z.entry(key)
    val all = remember(key) { e?.let { SvMorpheme.parse(z.svSyl(it)) } ?: emptyList() }
    val m = all.getOrNull(index)
    Column(Modifier.fillMaxSize()) {
        TopBar(m?.text ?: "", onBack, settings = false)
        if (e == null || m == null) return@Column
        val c = Color(SvColors.colorOf(m, all))
        Column(Modifier.fillMaxSize().dragScrollY(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            // the word with this part lit up
            Row {
                for (o in all) Txt(o.text, lat(30f).copy(fontWeight = if (o.id == m.id) FontWeight.Bold else FontWeight.Normal),
                    if (o.id == m.id) T.glyph else T.muted.copy(alpha = 0.6f),
                    Modifier.clip(RoundedCornerShape(6.dp)).background(if (o.id == m.id) c.copy(alpha = 0.5f) else Color.Transparent).padding(horizontal = 2.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Txt(when (m.kind) { SvMorpheme.Kind.ROOT -> m.text; SvMorpheme.Kind.PREFIX -> m.text + "-"; SvMorpheme.Kind.LINK -> "-" + m.text + "-"; else -> "-" + m.text },
                    lat(24f).copy(fontWeight = FontWeight.SemiBold), T.glyph)
                Chip(tr(m.kindName), c.copy(alpha = 0.5f), c, T.glyph)
            }
            if (m.kind == SvMorpheme.Kind.ROOT) {
                Txt(tr("詞根是詞的核心，帶著主要的意思；前綴、後綴和詞尾加在它前後，改變詞的意思或詞類。"), ff(FF.Subheadline), T.muted)
                val es = remember(m) { z.svEntries(m.word).filter { it.k != e.k }.take(3).ifEmpty { z.svEntries(m.word).take(1) } }
                for (o in es) SvMeaningCard(z, o) { nav.push(Route.ZhEntry(o.k)) }
            } else {
                val a = SvAffixes.of(m)
                if (a != null) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.55f)).padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for ((name, text) in (if (SvGuess.show == 2) listOf(tr("英文") to a.en, tr("例子") to a.ex) else listOf(tr("意思") to a.zh, tr("作用") to a.does, tr("英文") to a.en, tr("例子") to a.ex))) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Txt(name, ff(FF.Caption, FontWeight.SemiBold), T.muted, Modifier.width(40.dp))
                        Txt(text, ff(FF.Body), T.glyph, Modifier.weight(1f))
                    }
                } else Txt(tr("這個部分沒有說明。"), ff(FF.Subheadline), T.muted)
            }
            // other words with this part (not for linking letters and endings: almost every word has them)
            if (m.kind != SvMorpheme.Kind.LINK && m.kind != SvMorpheme.Kind.ENDING) {
                var ws by remember(m) { mutableStateOf<List<ZhEntry>>(emptyList()) }
                LaunchedEffect(m) { ws = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { z.svWords(m, e.k) } }
                if (ws.isNotEmpty()) {
                    Txt(if (m.kind == SvMorpheme.Kind.ROOT) tr("有這個詞根的詞") else if (m.kind == SvMorpheme.Kind.PREFIX) tr("有這個前綴的詞") else tr("有這個後綴的詞"),
                        ff(FF.Subheadline, FontWeight.SemiBold), T.glyph)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        for (o in ws) Column(Modifier.clip(RoundedCornerShape(9.dp)).background(T.fn.copy(alpha = 0.8f)).clickable { nav.push(Route.ZhEntry(o.k)) }.hand()
                            .padding(horizontal = 9.dp, vertical = 4.dp)) {
                            Txt(z.hanText(o.h, o.tw, T.glyph.argbInt()).annotated(), lat(16f).copy(fontWeight = FontWeight.Medium))
                            z.svGloss(o).takeIf { it.isNotEmpty() }?.let { Txt(it, ff(FF.Caption2), T.muted, maxLines = 1) }
                        }
                    }
                }
            }
        }
    }
}

/** a word with its class and meanings (tap to open it) */
@Composable
private fun SvMeaningCard(z: ZhDict, e: ZhEntry, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.55f)).clickable(onClick = onClick).hand().padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Txt(z.hanText(e.h, e.tw, T.glyph.argbInt()).annotated(), lat(20f).copy(fontWeight = FontWeight.SemiBold))
            e.pos.firstOrNull()?.let { Chip(it, T.fn, T.fnEdge, T.muted) }
            Spacer(Modifier.weight(1f))
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted, modifier = Modifier.size(16.dp))
        }
        if (e.svZh.isNotEmpty()) Txt(e.svZh.joinToString("、"), ff(FF.Body), T.glyph)
        e.en?.takeIf { it.isNotEmpty() }?.let { Txt(it, ff(FF.Subheadline), T.muted, maxLines = 3) }
    }
}

private class SvW(val lead: String, val core: String, val tail: String, val key: String?, val ms: List<SvMorpheme>)

/** 瑞典語: an example sentence and its English: each word in its morphemes' colours; tap a word to open it (a word
 *  the dictionary doesn't have: worked out) */
@Composable
fun SvExampleBlock(z: ZhDict, ex: ZhEx) {
    val nav = LocalNav.current
    val ck = svColorKey()
    val words = remember(ex, ck) {
        ex.h.split(" ").filter { it.isNotEmpty() }.map { t ->
            val (lead, core, tail) = svSplitWord(t)
            SvW(lead, core, tail, if (core.isEmpty()) null else z.svKey(core), if (core.isEmpty()) emptyList() else z.svMorphemes(core))
        }
    }
    val colours = Prefs.toneSys.value != 0
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        PlayButton("tts:" + ex.h, 28.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            TapWords(count = words.size, isTappable = { i -> words[i].key != null || words[i].ms.size > 1 },
                onTap = { i -> val w = words[i]; if (w.key != null) nav.push(Route.ZhEntry(w.key)) else nav.push(Route.SvWord(w.core)) }) { i, hot ->
                val w = words[i]
                val s = remember(w, ck) {
                    styled(w.lead, T.muted.argbInt()) + (if (w.ms.isEmpty()) styled(w.core, T.glyph.argbInt()) else SvColors.styledOf(w.ms, T.glyph.argbInt(), colours)) +
                        styled(w.tail + " ", T.muted.argbInt())
                }
                Txt(s.annotated(), lat(17f), modifier = if (hot) Modifier.clip(RoundedCornerShape(6.dp)).background(T.fn) else Modifier)
            }
            if (ex.src.isNotEmpty()) Txt(ex.src, ff(FF.Subheadline), T.muted)
        }
    }
}

/** a word the dictionary doesn't have, worked out: the word in colour, split into morphemes, what it's made of (each
 *  word opens its entry) and each step (-ande: makes a noun of a verb…) */
@Composable
fun SvEstimateBlock(z: ZhDict, est: SvEstimate) {
    val nav = LocalNav.current
    svColorKey()
    val colours = Prefs.toneSys.value != 0
    val ms = est.ms
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Txt(SvColors.styledOf(ms, T.glyph.argbInt(), colours).annotated(), lat(26f).copy(fontWeight = FontWeight.SemiBold))
            if (est.cls != SvCls.ANY) Chip(tr(est.cls.label), T.fn, T.fnEdge, T.muted)
        }
        Txt(SvColors.hyphened(ms, T.greenInk.argbInt(), colours, T.muted.copy(alpha = 0.7f).argbInt()).annotated(), lat(17f))
        Txt(est.parts.mapNotNull { p -> if (p.link || p.entry == null) null else z.entries[p.entry].let { e -> val g = z.svGloss(e); e.h + (if (g.isEmpty()) "" else "（$g）") } }
            .joinToString(" ＋ "), ff(FF.Subheadline), T.glyph.copy(alpha = 0.9f))
        for (p in est.parts) {
            if (p.link) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Txt("-" + p.text + "-", lat(16f), Color(SvColors.color(4)))
                Txt(tr("連接音：把兩個詞接起來，沒有意思"), ff(FF.Caption), T.muted)
            } else p.entry?.let { i ->
                val e = z.entries[i]
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(T.fn.copy(alpha = 0.8f)).clickable { nav.push(Route.ZhEntry(e.k)) }.hand()
                    .padding(horizontal = 10.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Txt(z.hanText(e.h, e.tw, T.glyph.argbInt()).annotated(), lat(18f).copy(fontWeight = FontWeight.SemiBold))
                    if (p.text.lowercase() != e.h.lowercase()) Txt(p.text, lat(13f), T.muted)
                    e.pos.firstOrNull()?.let { Chip(it, T.fn, T.fnEdge, T.muted) }
                    Txt(z.svGloss(e), ff(FF.Subheadline), T.glyph.copy(alpha = 0.85f), Modifier.weight(1f), maxLines = 1)
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = T.muted, modifier = Modifier.size(16.dp))
                }
            }
        }
        if (est.steps.isNotEmpty()) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(T.fn.copy(alpha = 0.5f)).padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (st in est.steps) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Txt(if (st.kind == SvMorpheme.Kind.PREFIX) st.text + "-" else "-" + st.text, lat(16f).copy(fontWeight = FontWeight.SemiBold),
                    Color(SvColors.color(if (st.kind == SvMorpheme.Kind.PREFIX) 2 else if (st.kind == SvMorpheme.Kind.SUFFIX) 3 else 5)), Modifier.widthIn(min = 52.dp))
                Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Txt(if (UILang.english || SvGuess.show == 2) st.en else st.zh, ff(FF.Subheadline), T.glyph)
                    if (st.cls != SvCls.ANY && st.kind != SvMorpheme.Kind.PREFIX) Txt(tr("→ ") + tr(st.cls.label), ff(FF.Caption), T.muted)
                }
            }
        }
        Txt(tr("這個詞詞典裡沒有：照詞典裡的詞和構詞規則推算，可能有誤。"), ff(FF.Caption), T.muted)
    }
}

/** a worked-out word on its own page (tapped in a sentence) */
@Composable
fun SvWordPage(z: ZhDict, word: String, onBack: () -> Unit) {
    val est = remember(word) { z.svEstimate(word) }
    Column(Modifier.fillMaxSize()) {
        TopBar(word, onBack, settings = false)
        Column(Modifier.fillMaxSize().dragScrollY(rememberScrollState()).padding(16.dp)) {
            if (est != null) SvEstimateBlock(z, est) else Txt(tr("找不到「{0}」。", word), ff(FF.Body), T.muted)
        }
    }
}
