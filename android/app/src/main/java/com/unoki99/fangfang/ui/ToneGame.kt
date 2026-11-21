package com.unoki99.fangfang.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.unoki99.fangfang.Player
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.*
import com.unoki99.fangfang.tr
import java.util.UUID

// 聲調色球: hear a word, and colour each of its syllables with its tone, one ball per syllable, in the tone colours
// (the ones picked in 設定, even when the colours on the words are off). Every syllable counts, not only the last
// one as in 聲調練習. 台語 (its tones as written, before sandhi), 華語, 粵語 and 客語 (only words with a recording).
// The same game as the iPhone app's.

private class ToneQ(val card: Card, val tones: List<Int>, val audio: String) { val id = UUID.randomUUID().toString() }

private val TG_TW = mapOf(1 to "陰平", 2 to "陰上", 3 to "陰去", 4 to "陰入", 5 to "陽平", 7 to "陽去", 8 to "陽入")
private val TG_ZH = mapOf(0 to "輕聲", 1 to "陰平", 2 to "陽平", 3 to "上聲", 4 to "去聲")
private val TG_YUE = mapOf(1 to "陰平", 2 to "陰上", 3 to "陰去", 4 to "陽平", 5 to "陽上", 6 to "陽去")

@Composable
fun ToneGameScreen(stars: StarField, onClose: () -> Unit) {
    val lang = Store.lang
    val rom = Prefs.rom.value; val place = Prefs.place.value
    val density = LocalDensity.current.density
    val toneSet = when (lang) {
        1 -> listOf(1, 2, 3, 4, 0)
        2 -> listOf(1, 2, 3, 4, 5, 6)
        3 -> ToneColors.hakTones
        else -> listOf(1, 2, 3, 4, 5, 7, 8)
    }
    fun color(t: Int): Color = Color(when (lang) { 1 -> ToneColors.zhColor(t); 2 -> ToneColors.yueColor(t); 3 -> ToneColors.hakColor(t); else -> ToneColors.twColor(t) })
    fun name(t: Int): String = tr(when (lang) { 1 -> TG_ZH[t]; 2 -> TG_YUE[t]; else -> TG_TW[t] } ?: "")
    /** a word's tones, one per syllable (null: it can't be asked) */
    fun tonesOf(c: Card): List<Int>? {
        val out = ArrayList<Int>()
        if (c.isZh) {
            val s = c.zs ?: return null
            for (x in s) if (x != "-" && x != "_" && x.isNotEmpty()) out.add(Zhuyin.tone(x))
        } else {
            val cs = c.c ?: return null
            for (code in cs) code.lastOrNull()?.digitToIntOrNull()?.let { out.add(it) }
        }
        if (out.isEmpty() || out.size > 4 || !out.all { it in toneSet }) return null
        return out
    }
    val queue = remember { mutableStateListOf<ToneQ>() }
    var idx by remember { mutableIntStateOf(0) }
    val picked = remember { mutableStateListOf<Int>() }
    var done by remember { mutableStateOf(false) }
    var score by remember { mutableIntStateOf(0) }
    var combo by remember { mutableIntStateOf(0) }
    var best by remember { mutableIntStateOf(0) }
    var allRight by remember { mutableIntStateOf(0) }
    var ballsAt by remember { mutableStateOf(Offset.Zero) }
    var started by remember { mutableStateOf(false) }
    // the 練習範圍's words first, then common words
    fun start() {
        val words = Store.practiceCards.shuffled().toMutableList()
        val seen = words.map { it.k }.toSet()
        words.addAll(Store.cards.take(2000).filter { it.k !in seen }.shuffled())
        val qs = ArrayList<ToneQ>()
        for (c in words) {
            if (Lang.charOf(c.k) != null) continue
            val a = c.audio ?: continue
            val t = tonesOf(c) ?: continue
            qs.add(ToneQ(c, t, a))
            if (qs.size == 12) break
        }
        queue.clear(); queue.addAll(qs)
        idx = 0; picked.clear(); done = false; score = 0; combo = 0; best = 0; allRight = 0; started = true
    }
    LaunchedEffect(Unit) { if (!started) start() }
    fun check(q: ToneQ) {
        done = true
        val n = picked.zip(q.tones).count { it.first == it.second }
        score += n * 10
        if (n == q.tones.size) {
            combo++; allRight++; best = maxOf(best, combo)
            if (combo >= 2) score += combo * 5
            stars.burst(ballsAt - stars.origin, density)
        } else {
            combo = 0
            Player.play(q.audio)            // (hear it again with the answer)
        }
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("聲調色球"), onClose, close = true, settings = false)
        Box(Modifier.fillMaxSize()) {
            when {
                !started -> {}
                queue.isEmpty() -> Txt(tr("找不到可以聽的詞。"), ff(FF.Body), T.muted, Modifier.align(Alignment.Center).padding(16.dp))
                idx >= queue.size -> Column(Modifier.align(Alignment.Center).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Txt(tr("{0} 分", score), sz(44f, FontWeight.Bold), T.greenInk)
                    Txt(tr("全對 {0} / {1}・最多連對 {2}", allRight, queue.size, best), ff(FF.Subheadline), T.muted)
                    SoftButton(onClick = { start() }, Modifier.heightIn(min = 44.dp)) { Txt(tr("再玩一次"), ff(FF.Headline), T.glyph) }
                }
                else -> {
                    val q = queue[idx]
                    LaunchedEffect(q.id) { Player.play(q.audio) }
                    Column(Modifier.fillMaxSize().widthIn(max = 640.dp).align(Alignment.TopCenter).verticalScroll(rememberScrollState()).padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(18.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Txt("${idx + 1} / ${queue.size}", ff(FF.Footnote), T.muted, Modifier.weight(1f))
                            if (combo >= 2) Txt(tr("連對 {0}", combo), ff(FF.Footnote, FontWeight.Bold), T.oliveInk)
                            Txt(tr("{0} 分", score), ff(FF.Footnote, FontWeight.Bold), T.greenInk)
                        }
                        Panel {
                            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                Txt(if (done) tr("答案") else tr("聽聽看，每個字是第幾聲？"), ff(FF.Subheadline, FontWeight.Bold), T.oliveInk)
                                PlayButton(q.audio, 72.dp)
                                // one ball per syllable: empty until picked
                                Row(Modifier.onGloballyPositioned { ballsAt = it.boundsInWindow().center }, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                                    for (i in q.tones.indices) {
                                        val has = i < picked.size
                                        val right = has && picked[i] == q.tones[i]
                                        val s by animateFloatAsState(if (has) 1f else 0.9f, spring(dampingRatio = 0.6f), label = "ball")
                                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Box(Modifier.size(46.dp).scale(s).clip(CircleShape)
                                                .background(if (has) color(picked[i]) else Color.Transparent)
                                                .border(2.dp, if (has) Color.Transparent else T.muted.copy(alpha = 0.6f), CircleShape),
                                                contentAlignment = Alignment.Center) {
                                                if (done) Icon(if (right) Icons.Filled.Check else Icons.Filled.Close, null, tint = Color.Black.copy(alpha = 0.75f), modifier = Modifier.size(20.dp))
                                            }
                                            // (wrong: the right colour under it)
                                            if (done) Box(Modifier.size(16.dp).clip(CircleShape).background(if (right) Color.Transparent else color(q.tones[i])))
                                        }
                                    }
                                }
                                if (done) {
                                    Txt(remember(q.id) { Store.cardHan(q.card, place, T.blueInk.argbInt()).annotated() }, sz(40f, FontWeight.Medium), T.blueInk)
                                    Txt(remember(q.id) { Store.cardRom(q.card, rom, place).annotated() }, lat(18f), T.greenInk)
                                    q.card.d.firstOrNull()?.t?.let { Txt(shownDef(q.card.k, 0, it), ff(FF.Subheadline), T.muted, maxLines = 2) }
                                }
                            }
                        }
                        if (done) {
                            SoftButton(onClick = { idx++; picked.clear(); done = false }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                                Txt(if (idx + 1 < queue.size) tr("下一個") else tr("看結果"), ff(FF.Headline), T.glyph)
                            }
                        } else {
                            // the tones to pick from, in their colours
                            val perRow = 4
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                for (row in toneSet.chunked(perRow)) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                                    for (t in row) Column(Modifier.clip(CircleShape).clickable {
                                        if (!done && picked.size < q.tones.size) {
                                            picked.add(t)
                                            if (picked.size == q.tones.size) check(q)
                                        }
                                    }.padding(4.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Box(Modifier.size(44.dp).clip(CircleShape).background(color(t)), contentAlignment = Alignment.Center) {
                                            Text(if (t == 0) "˙" else "$t", color = Color.Black.copy(alpha = 0.7f), fontSize = 18.sp, fontWeight = FontWeight.Bold)
                                        }
                                        Txt(name(t), ff(FF.Caption2), T.muted)
                                    }
                                }
                            }
                            if (picked.isNotEmpty()) TextButton(onClick = { picked.removeAt(picked.lastIndex) }) {
                                Icon(Icons.AutoMirrored.Filled.Backspace, null, tint = T.muted, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(6.dp))
                                Text(tr("退一格"), color = T.muted, style = ff(FF.Footnote))
                            }
                        }
                    }
                }
            }
        }
    }
}
