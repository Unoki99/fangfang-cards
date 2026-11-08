package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Player
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.Card
import com.unoki99.fangfang.engine.plain
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.random.Random

private class MemTile(val id: Int, val pair: Int, val isHan: Boolean, val text: AnnotatedString)

/** 翻牌配對: memory with 不熟 words. Half the cards are 漢字, half their readings; turn two over, and keep them if they belong together. */
@Composable
fun MemoryScreen(stars: StarField) {
    val rom = Prefs.rom.value; val place = Prefs.place.value
    var pairCount by Prefs.memoryPairs
    var cards by remember { mutableStateOf<List<Card>>(emptyList()) }
    var tiles by remember { mutableStateOf<List<MemTile>>(emptyList()) }
    val up = remember { mutableStateListOf<Int>() }
    val matched = remember { mutableStateListOf<Int>() }
    val wrong = remember { mutableStateListOf<Int>() }
    var moves by remember { mutableIntStateOf(0) }
    var busy by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current.density
    val screenW = LocalConfiguration.current.screenWidthDp

    var resumed by remember { mutableStateOf(false) }
    fun makeTiles(i: Int, c: Card) = listOf(MemTile(i * 2, i, true, AnnotatedString(c.h)),
        MemTile(i * 2 + 1, i, false, Store.cardRom(c, rom, place).annotated(T.greenInk)))
    /** a board left half way: the words, where each card lies, the pairs found, how many turns */
    fun saveNow() {
        if (tiles.isEmpty() || matched.size == cards.size) { PracticeSave.clear("memory", Store.isZh); return }
        PracticeSave.save("memory", Store.isZh, Store.practiceTopic, mapOf("keys" to cards.map { it.k }, "order" to tiles.map { it.id },
            "matched" to matched.toList(), "moves" to moves))
    }
    @Suppress("UNCHECKED_CAST")
    fun restore(): Boolean {
        val s = PracticeSave.load("memory", Store.isZh, Store.practiceTopic) ?: return false
        val keys = PracticeSave.strings(s["keys"])
        val cs = keys.mapNotNull { Store.cardFor(it) }
        val order = ((s["order"] as? List<Any?>) ?: emptyList()).map { PracticeSave.int(it) }
        if (cs.size != keys.size || cs.size < 2 || order.size != cs.size * 2) return false
        val byId = HashMap<Int, MemTile>()
        for ((i, c) in cs.withIndex()) for (t in makeTiles(i, c)) byId[t.id] = t
        val t = order.mapNotNull { byId[it] }
        if (t.size != order.size) return false
        cards = cs; tiles = t
        up.clear(); wrong.clear(); matched.clear(); matched.addAll(((s["matched"] as? List<Any?>) ?: emptyList()).map { PracticeSave.int(it) })
        moves = PracticeSave.int(s["moves"]); busy = false
        resumed = true
        return true
    }
    fun build() {
        val picked = ArrayList<Card>()
        val hans = HashSet<String>(); val roms = HashSet<String>()
        for (c in Store.practiceCards.shuffled()) {
            val r = Store.cardRom(c, rom, place).plain()
            if (hans.contains(c.h) || roms.contains(r)) continue
            hans.add(c.h); roms.add(r); picked.add(c)
            if (picked.size >= pairCount) break
        }
        up.clear(); matched.clear(); wrong.clear(); moves = 0; busy = false
        if (picked.size < 2) { cards = emptyList(); tiles = emptyList(); return }
        cards = picked
        val t = ArrayList<MemTile>()
        for ((i, c) in picked.withIndex()) t.addAll(makeTiles(i, c))
        tiles = t.shuffled()
        saveNow()
    }
    var first by remember { mutableStateOf(true) }
    LaunchedEffect(pairCount, rom) {
        if (first) { first = false; if (restore()) return@LaunchedEffect }
        build()
    }
    LaunchedEffect(moves, matched.size) { if (!first) saveNow() }

    fun tap(t: MemTile) {
        if (busy || matched.contains(t.pair) || up.contains(t.id)) return
        up.add(t.id)
        if (up.size < 2) return
        moves++
        val a = tiles.first { it.id == up[0] }; val b = tiles.first { it.id == up[1] }
        if (a.pair == b.pair) {
            cards[a.pair].audio?.let { Player.play(it) }
            matched.add(a.pair); up.clear()
            stars.burst(Offset(Random.nextInt(80, maxOf(81, screenW - 40)) * density, Random.nextInt(200, 380) * density), density)
        } else {
            busy = true
            wrong.clear(); wrong.addAll(up)
            scope.launch { delay(900); up.clear(); wrong.clear(); busy = false }
        }
    }

    val done = tiles.isNotEmpty() && matched.size == cards.size
    Column(Modifier.fillMaxSize()) {
        TopBar(if (tiles.isNotEmpty() && !done) tr("翻牌配對　{0}／{1}　翻了 {2} 次", matched.size, cards.size, moves) else tr("翻牌配對"),
            { UI.practice = null; Player.stop() }, close = true, settings = false) {
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.GridView, tr("幾對"), tint = T.glyph) }
                DropdownMenu(menu, { menu = false }, containerColor = T.fn) {
                    for (n in listOf(4, 6, 8, 10)) DropdownMenuItem(text = { Text(tr("{0} 對", n), color = T.glyph) },
                        leadingIcon = { if (n == pairCount) Icon(Icons.Filled.Check, null, tint = T.greenInk) else Spacer(Modifier.size(24.dp)) },
                        onClick = { pairCount = n; menu = false })
                }
            }
        }
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) { ResumedNote(resumed) { resumed = false } }
        Box(Modifier.fillMaxSize()) {
            when {
                tiles.isEmpty() -> Txt(tr("「不熟」裡至少要有兩個詞才能玩。"), ff(FF.Body), T.muted, Modifier.align(Alignment.Center))
                done -> Column(Modifier.align(Alignment.Center).widthIn(max = 520.dp).verticalScroll(rememberScrollState()).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Icon(Icons.Filled.AutoAwesome, null, tint = T.greenInk, modifier = Modifier.size(44.dp))
                    Txt(tr("全部配對了！"), ff(FF.Title2, FontWeight.Bold), T.glyph)
                    Txt(tr("{0} 對，翻了 {1} 次", cards.size, moves), ff(FF.Body), T.muted)
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.7f)).padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        for (c in cards) Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Txt(c.h, sz(18f, FontWeight.SemiBold), T.glyph)
                            Txt(Store.cardRom(c, rom, place).annotated(), lat(15f), T.greenInk)
                            Txt(Store.practiceMeaning(c).second, ff(FF.Footnote), T.muted, maxLines = 1)
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        SoftButton(onClick = { build() }, Modifier.weight(1f)) { IconLabel(Icons.Filled.Refresh, tr("再玩一次"), ff(FF.Subheadline)) }
                        SoftButton(onClick = { UI.practice = null; Player.stop() }, Modifier.weight(1f)) { IconLabel(Icons.Filled.Check, tr("結束"), ff(FF.Subheadline)) }
                    }
                }
                else -> BoxWithConstraints(Modifier.fillMaxSize()) {
                    val cols = if (maxWidth > 600.dp) 4 else 3
                    val rows = (tiles.size + cols - 1) / cols
                    val h = ((maxHeight - 32.dp - 10.dp * (rows - 1)) / rows).coerceIn(64.dp, 130.dp)
                    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        for (r in 0 until rows) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            for (cI in 0 until cols) {
                                val t = tiles.getOrNull(r * cols + cI)
                                if (t == null) Spacer(Modifier.weight(1f))
                                else MemTileView(t, up.contains(t.id) || matched.contains(t.pair), matched.contains(t.pair), wrong.contains(t.id),
                                    Modifier.weight(1f).height(h)) { tap(t) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MemTileView(t: MemTile, open: Boolean, isMatched: Boolean, isWrong: Boolean, modifier: Modifier, onTap: () -> Unit) {
    val angle by animateFloatAsState(if (open) 0f else 180f, spring(dampingRatio = 0.8f, stiffness = 300f), label = "flip")
    val showFront = angle < 90f
    val fill = if (isMatched) T.green else if (isWrong) T.rust else if (showFront) T.fn else T.blue.copy(alpha = 0.55f)
    val edge = if (isMatched) T.greenEdge else if (isWrong) T.rustEdge else if (showFront) T.fnEdge else T.blueEdge
    val dens = LocalDensity.current.density
    Box(modifier.graphicsLayer { rotationY = angle; cameraDistance = 12f * dens }.clip(RoundedCornerShape(14.dp)).background(fill)
        .border(1.5.dp, edge, RoundedCornerShape(14.dp))
        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onTap),
        contentAlignment = Alignment.Center) {
        if (showFront) {
            if (t.isHan) Txt(t.text, sz(26f, FontWeight.SemiBold), T.glyph, Modifier.padding(6.dp).graphicsLayer { alpha = if (isMatched) 0.75f else 1f })
            else Text(t.text, style = lat(17f), color = T.greenInk, textAlign = TextAlign.Center,
                modifier = Modifier.padding(6.dp).graphicsLayer { alpha = if (isMatched) 0.75f else 1f })
        } else Icon(if (t.isHan) Icons.Filled.Translate else Icons.Filled.TextFields, null, tint = T.blueInk.copy(alpha = 0.7f),
            modifier = Modifier.size(24.dp).graphicsLayer { rotationY = 180f })
    }
}
