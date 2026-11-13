package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.*
import kotlin.random.Random

// MARK: - 遊戲: words falling down the screen (the same as the iPhone app's Games.swift)
//
// 看讀音找字: the reading of one of the falling words is at the bottom; tap that word before it reaches the bottom.
// 看字找讀音: the word is at the bottom and readings fall; tap its reading.
// The further you get, the faster they fall. Three hearts: the right one reaching the bottom costs a heart, a wrong
// tap half a heart.

private class Drop(val id: Long, val card: Card, val x: Float, val y: Float)

/** the game's state; sizes in dp */
private class FallingGame {
    var drops by mutableStateOf<List<Drop>>(emptyList())
    var target by mutableStateOf<Card?>(null)
    /** half hearts left (3 hearts = 6) */
    var halves by mutableIntStateOf(6)
    var score by mutableIntStateOf(0)
    var over by mutableStateOf(false)
    /** a wrong tap: the hearts flash for a moment */
    var hurtAt by mutableLongStateOf(0L)
    var w = 0f; var h = 0f
    private var pool: List<Card> = emptyList()
    private var speed = 55f
    private var sinceSpawn = 10.0
    private var nextId = 0L
    val bottomBand = 96f

    fun start(cards: List<Card>) {
        pool = cards
        drops = emptyList(); target = null; halves = 6; score = 0; over = false; speed = 55f; sinceSpawn = 10.0
    }

    private fun spawn(c: Card) {
        if (w <= 0f) return
        fun rx() = 70f + Random.nextFloat() * maxOf(1f, w - 140f)
        // (not on top of a word near the top already)
        var x = rx()
        repeat(6) { if (drops.any { kotlin.math.abs(it.x - x) < 110f && it.y < 120f }) x = rx() }
        drops = drops + Drop(nextId++, c, x, -30f)
    }

    private fun newTarget() {
        // one that's falling and still high enough to be reached, else a new one
        val open = drops.filter { it.y < h * 0.45f }
        if (open.isNotEmpty()) { target = open.random().card; return }
        val c = pool.randomOrNull() ?: return
        target = c
        spawn(c)
    }

    fun tick(dt: Double) {
        if (over || h <= 0f || pool.isEmpty()) return
        val floor = h - bottomBand
        drops = drops.map { Drop(it.id, it.card, it.x, it.y + speed * dt.toFloat()) }
        // the right one reached the bottom: a heart lost
        val t = target
        if (t != null && drops.any { it.card.k == t.k && it.y > floor }) {
            drops = drops.filter { it.card.k != t.k }
            lose(2)
            target = null
        }
        drops = drops.filter { it.y <= floor + 40f }
        sinceSpawn += dt
        val every = maxOf(0.7, 1.9 - score * 0.04)
        if (sinceSpawn >= every && drops.size < 7) {
            sinceSpawn = 0.0
            // (another word than the ones already falling)
            val falling = drops.map { it.card.k }.toSet()
            (pool.filter { it.k !in falling }.randomOrNull() ?: pool.randomOrNull())?.let { spawn(it) }
        }
        if (target == null || drops.none { it.card.k == target?.k }) newTarget()
        speed += dt.toFloat() * 1.4f
    }

    /** a tap on a falling word: true when it's the right one */
    fun tap(d: Drop): Boolean {
        if (over) return false
        if (d.card.k == target?.k) {
            drops = drops.filter { it.id != d.id }
            score++
            speed += 4f
            target = null
            newTarget()
            return true
        }
        lose(1)
        hurtAt = System.nanoTime()
        return false
    }

    private fun lose(n: Int) {
        halves = maxOf(0, halves - n)
        if (halves == 0) over = true
    }
}

/** a box placed with its centre at (x, y) dp of its parent */
private fun Modifier.centerAt(x: Float, y: Float) = layout { m, c ->
    val p = m.measure(c.copy(minWidth = 0, minHeight = 0))
    layout(p.width, p.height) { p.place(x.dp.roundToPx() - p.width / 2, y.dp.roundToPx() - p.height / 2) }
}

@Composable
fun FallingGameScreen(onClose: () -> Unit) {
    var mode by remember { mutableStateOf<Int?>(null) }
    var best by Prefs.fallingBest
    val game = remember { FallingGame() }
    val rom = Prefs.rom.value; val place = Prefs.place.value
    val cards = remember {
        // (words of 1–4 characters, so they fit as they fall)
        (Store.practiceCards + Store.knownCards.take(200)).filter { it.h.cpCount in 1..4 }.distinctBy { it.k }.take(400)
    }
    fun reading(c: Card) = Store.cardRom(c, rom, place).plain()
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("遊戲"), { if (mode != null && !game.over) mode = null else onClose() }, close = true, settings = false)
        val m = mode
        if (m == null) {
            Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically)) {
                Txt(tr("字從上面掉下來，在它掉到底以前點對的那一個。越玩越快。"), ff(FF.Subheadline).copy(textAlign = TextAlign.Center), T.muted)
                for (k in 0..1) ProminentButton(onClick = { game.start(cards.shuffled()); mode = k }, Modifier.widthIn(max = 360.dp).fillMaxWidth().heightIn(min = 70.dp),
                    enabled = cards.size >= 4) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(if (k == 0) tr("看讀音找字") else tr("看字找讀音"), style = ff(FF.Title3, FontWeight.Bold))
                        Text(if (k == 0) tr("下面是讀音，點掉下來的字") else tr("下面是字，點掉下來的讀音"), style = ff(FF.Caption))
                    }
                }
                if (cards.size < 4) Txt(tr("先在「新詞」往左滑幾個詞（不熟），才有字可以玩。"), ff(FF.Footnote), T.muted)
                if (best > 0) Txt(tr("最高分：{0}", best), ff(FF.Footnote), T.muted)
            }
            return@Column
        }
        // 30 times a second
        LaunchedEffect(m) {
            var last = withFrameNanos { it }
            while (true) {
                withFrameNanos { now ->
                    game.tick(minOf(0.1, (now - last) / 1e9)); last = now
                }
            }
        }
        LaunchedEffect(game.over) { if (game.over && game.score > best) best = game.score }
        val density = LocalDensity.current
        Box(Modifier.fillMaxSize().clip(RoundedCornerShape(0.dp)).onSizeChanged {
            with(density) { game.w = it.width.toDp().value; game.h = it.height.toDp().value }
        }) {
            // the falling words
            for (d in game.drops) key(d.id) {
                Box(Modifier.centerAt(d.x, d.y).clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.85f))
                    .border(1.5.dp, T.fnEdge, RoundedCornerShape(12.dp)).clickable { game.tap(d) }
                    .padding(horizontal = 12.dp, vertical = 6.dp)) {
                    if (m == 0) Text(d.card.h, style = sz(34f).copy(fontFamily = Kai.family), color = T.glyph)
                    else Txt(reading(d.card), lat(20f), T.greenInk, maxLines = 1)
                }
            }
            // score and hearts
            val hurt = System.nanoTime() - game.hurtAt < 400_000_000L
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Txt(tr("分數 {0}", game.score), lat(16f), T.glyph, Modifier.weight(1f))
                for (i in 0 until 3) {
                    val left = game.halves - i * 2
                    val red = if (hurt) Color(0xFFFF2020) else Color(ToneColors.red)
                    Box(Modifier.size(24.dp)) {
                        Icon(Icons.Filled.FavoriteBorder, null, tint = red, modifier = Modifier.fillMaxSize())
                        if (left >= 2) Icon(Icons.Filled.Favorite, null, tint = red, modifier = Modifier.fillMaxSize())
                        else if (left == 1) Box(Modifier.fillMaxHeight().width(12.dp).clip(RoundedCornerShape(0.dp))) {
                            Icon(Icons.Filled.Favorite, null, tint = red, modifier = Modifier.requiredSize(24.dp).offset(x = 6.dp))
                        }
                    }
                }
            }
            // what to find, at the bottom
            Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height((game.bottomBand - 16f).dp)
                .background(T.btn.copy(alpha = 0.5f)), contentAlignment = Alignment.Center) {
                Box(Modifier.align(Alignment.TopCenter).fillMaxWidth().height(2.dp).background(T.btnEdge))
                val t = game.target
                if (t != null) {
                    if (m == 0) Txt(reading(t), lat(26f), T.greenInk, maxLines = 1)
                    else Text(t.h, style = sz(40f).copy(fontFamily = Kai.family), color = T.glyph)
                }
            }
            if (game.over) Column(Modifier.align(Alignment.Center).clip(RoundedCornerShape(22.dp)).background(T.fn.copy(alpha = 0.97f))
                .border(1.5.dp, T.fnEdge, RoundedCornerShape(22.dp)).padding(28.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Txt(tr("遊戲結束"), ff(FF.Title, FontWeight.Bold), T.glyph)
                Txt(tr("分數 {0}", game.score), ff(FF.Title2), T.btnInk)
                if (game.score >= best && game.score > 0) Txt(tr("新的最高分！"), ff(FF.Body), T.oliveInk)
                ProminentButton(onClick = { game.start(cards.shuffled()) }, Modifier.widthIn(min = 180.dp)) { Text(tr("再玩一次")) }
                TextButton(onClick = { mode = null }) { Text(tr("換一種玩法"), color = T.muted) }
            }
        }
    }
}
