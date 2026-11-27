package com.unoki99.fangfang.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.RoomLink
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.Lang
import com.unoki99.fangfang.engine.Zhuyin
import com.unoki99.fangfang.engine.cps
import com.unoki99.fangfang.engine.firstCp
import com.unoki99.fangfang.tr
import com.unoki99.fangfang.engine.plain
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject

// MARK: - 詞龍 (詞語接龍; the same as the iPhone app's WordDragon.swift)
//
// A word is given; the next word must start with its last character (瑞典語: its last letter), and so on. Every word
// must be in the dictionary of the language shown, and no word twice.
// 一個人: you and the app take turns, and it never ends by itself: the app always answers (with a common word if it
// has one, else any word of the dictionary; if no word at all starts with that character, it starts again with a new
// word). You can only lose: when the time for a turn runs out (時間, if set) or you give up (認輸).
// 和別人一起: two or more players in a room (over the internet, with every version) take turns; the app doesn't
// play. Whoever runs out of time or gives up is out; the last one left wins.

/** what's sent (JSON; the same keys as the iPhone app's DragonMsg) */
class DragonMsg(val kind: String, val name: String) {
    var on = false; var order: List<String> = emptyList(); var word = ""; var seconds = 0
    fun json(): String = JSONObject().put("kind", kind).put("name", name).put("on", on).put("order", JSONArray(order))
        .put("word", word).put("seconds", seconds).toString()
    companion object {
        fun of(s: String): DragonMsg? = try {
            val o = JSONObject(s)
            DragonMsg(o.getString("kind"), o.getString("name")).apply {
                on = o.optBoolean("on"); word = o.optString("word"); seconds = o.optInt("seconds")
                val a = o.optJSONArray("order"); order = if (a == null) emptyList() else (0 until a.length()).map { a.optString(it) }
            }
        } catch (_: Exception) { null }
    }
}

class DragonLink(name: String) : RoomLink(name) {
    val ready = mutableStateListOf<String>()
    private var meReady = false
    var playing by mutableStateOf(false)
    var order by mutableStateOf<List<String>>(emptyList())
    val alive = mutableStateListOf<String>()
    var turn by mutableIntStateOf(0)
    val chain = mutableStateListOf<Pair<String, String>>()
    var seconds by mutableIntStateOf(0)
    var game by mutableIntStateOf(0)
    val outs = mutableStateListOf<String>()

    val current: String? get() = if (alive.isEmpty()) null else alive[turn % alive.size]
    val myTurn: Boolean get() = playing && current == myName
    val winner: String? get() = if (order.size > 1 && alive.size == 1 && !playing) alive.first() else null
    val allReady: Boolean get() = everyone.size >= 2 && ready.containsAll(everyone) && !playing
    val iStart: Boolean get() = allReady && everyone.sorted().first() == myName

    fun send(m: DragonMsg) { handle(m); sendPayload(m.json()) }
    override fun received(d: String) { DragonMsg.of(d)?.let { handle(it) } }
    override fun joined(name: String) { if (meReady) send(DragonMsg("ready", myName).apply { on = true }) }
    override fun left(name: String) { ready.remove(name); if (playing && alive.contains(name)) out(name) }
    fun setReady(on: Boolean) { meReady = on; send(DragonMsg("ready", myName).apply { this.on = on }) }

    private fun out(name: String) {
        val i = alive.indexOf(name)
        if (i < 0) return
        val cur = turn % maxOf(alive.size, 1)
        alive.removeAt(i)
        outs.add(name)
        // (the turn stays with the same player; theirs, when it's the one who's out, goes to the next)
        turn = if (alive.isEmpty()) 0 else if (i < cur) cur - 1 else cur % alive.size
        if (alive.size <= 1) { playing = false; ready.clear(); meReady = false }
    }

    private fun handle(m: DragonMsg) {
        when (m.kind) {
            "ready" -> if (m.on) { if (m.name !in ready) ready.add(m.name) } else ready.remove(m.name)
            "start" -> {
                order = m.order; alive.clear(); alive.addAll(m.order); turn = 0; outs.clear()
                chain.clear(); chain.add(m.word to "")
                seconds = m.seconds
                playing = true
                game++
            }
            "word" -> {
                if (!playing || current != m.name) return
                chain.add(m.word to m.name)
                turn = (turn + 1) % maxOf(alive.size, 1)
            }
            "out" -> out(m.name)
        }
    }
}

@Composable
fun WordDragonScreen(onClose: () -> Unit) {
    val sv = Store.isSv
    val link = remember { DragonLink(Prefs.coopName.value.ifBlank { tr("玩家") + (100..999).random() }) }
    DisposableEffect(Unit) { onDispose { link.close() } }
    var together by remember { mutableStateOf(false) }
    var best by Prefs.dragonBest
    var secondsPref by Prefs.dragonSeconds
    val rom = Prefs.rom.value; val place = Prefs.place.value
    val solo = remember { mutableStateListOf<Pair<String, String>>() }
    var lost by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf<String?>(null) }
    var typed by remember { mutableStateOf("") }
    var said by remember { mutableStateOf<String?>(null) }
    var left by remember { mutableIntStateOf(0) }

    fun norm(w: String) = if (sv) w.lowercase() else w
    fun first(w: String): String? = (if (sv) w.lowercase() else w).cps().firstOrNull()
    fun last(w: String): String? {
        if (sv) return w.lowercase().lastOrNull { it.isLetter() }?.toString()
        return w.cps().lastOrNull { Zhuyin.isHan(it.firstCp()) } ?: w.cps().lastOrNull()
    }
    fun isWord(w: String): Boolean {
        if (!Store.isZh) return Store.dict?.hanMap?.get(w) != null
        val z = Store.zh ?: return false
        if (z.isSv) return z.svIndices(w).isNotEmpty()
        return z.byHan[w] != null
    }
    // the app's words: the cards (most common first), then the whole dictionary's
    val byFirst = remember {
        val m = HashMap<String, MutableList<String>>()
        for (c in Store.cards) {
            if (Lang.charOf(c.k) != null) continue
            val w = c.h
            if ((if (sv) w.length >= 3 else w.cps().size >= 2) && !w.contains(' ')) first(w)?.let { m.getOrPut(it) { ArrayList() }.add(w) }
        }
        m
    }
    val anyFirst = remember {
        val m = HashMap<String, MutableList<String>>()
        val all: Collection<String> = if (!Store.isZh) (Store.dict?.hanMap?.keys ?: emptySet())
            else Store.zh?.let { z -> if (z.isSv) z.entries.map { it.h } else z.byHan.keys } ?: emptySet()
        for (w in all) if ((if (sv) w.length >= 3 else w.cps().size >= 2) && !w.contains(' ')) first(w)?.let { m.getOrPut(it) { ArrayList() }.add(w) }
        m
    }
    fun opening(): String? {
        val pool = byFirst.values.flatMap { it.take(30) }.filter { w -> last(w)?.let { byFirst.containsKey(it) } ?: false }
        return pool.randomOrNull() ?: byFirst.values.firstOrNull()?.firstOrNull()
    }
    val words: List<Pair<String, String>> = if (together) link.chain else solo
    val used = words.map { norm(it.first) }.toSet()
    val mineCount = words.count { it.second == link.myName }
    val myTurn = if (together) link.myTurn else !lost
    val need = words.lastOrNull()?.let { last(it.first) }

    fun startSolo() { typed = ""; said = null; lost = false; note = null; solo.clear(); opening()?.let { solo.add(it to "app") } }
    LaunchedEffect(Unit) { if (solo.isEmpty()) startSolo() }
    LaunchedEffect(link.allReady) {
        if (link.iStart) opening()?.let { w -> link.send(DragonMsg("start", link.myName).apply { order = link.everyone.sorted(); word = w; seconds = secondsPref }) }
    }
    LaunchedEffect(together) { if (!together) link.close() }

    fun reply(w: String) {
        note = null
        val u = solo.map { norm(it.first) }.toSet()
        val l = last(w) ?: return
        val r = byFirst[l]?.firstOrNull { norm(it) !in u } ?: anyFirst[l]?.firstOrNull { norm(it) !in u }
        if (r != null) solo.add(r to "app")
        else opening()?.let { n -> if (norm(n) !in u) { note = tr("詞典裡沒有「{0}」開頭的詞了，換一個詞開始：", l); solo.add(n to "app") } }
    }
    fun submit() {
        val w = typed.trim()
        if (w.isEmpty() || !myTurn) return
        if (need != null && first(w) != need) { said = tr("要用「{0}」開頭。", need); return }
        if (norm(w) in used) { said = tr("這個詞用過了。"); return }
        if (!isWord(w)) { said = tr("詞典裡沒有「{0}」。", w); return }
        said = null; typed = ""
        if (together) { link.send(DragonMsg("word", link.myName).apply { word = w }); return }
        solo.add(w to link.myName)
        val n = solo.count { it.second == link.myName }
        if (n > best) best = n
        reply(w)
    }
    fun timeUp() { if (together) { if (link.myTurn) link.send(DragonMsg("out", link.myName)) } else { lost = true; said = tr("時間到了。") } }
    fun giveUp() { if (together) link.send(DragonMsg("out", link.myName)) else lost = true }

    // (the time left of this turn)
    val limit = if (together) link.seconds else secondsPref
    LaunchedEffect(together, link.game, link.turn, words.size, lost, myTurn, limit) {
        if (limit <= 0 || !myTurn || (together && !link.playing)) { left = 0; return@LaunchedEffect }
        left = limit
        while (left > 0) { delay(1000); left-- }
        timeUp()
    }

    Column(Modifier.fillMaxSize()) {
        TopBar(tr("詞龍"), { link.close(); onClose() }, close = true, settings = false) {
            // 每一輪的時間
            var open by remember { mutableStateOf(false) }
            TextButton(onClick = { open = true }) { Text(if (secondsPref == 0) tr("不限時間") else tr("{0} 秒", secondsPref), color = T.btnInk) }
            DropdownMenu(open, { open = false }, containerColor = T.fn) {
                for (t in listOf(0, 15, 30, 60)) DropdownMenuItem(text = { Text(if (t == 0) tr("不限時間") else tr("{0} 秒", t), color = if (t == secondsPref) T.greenInk else T.glyph) },
                    onClick = { secondsPref = t; open = false })
            }
            if (!sv) RomButton()
        }
        Segmented(listOf(false to tr("一個人"), true to tr("和別人一起")), together, { if (!link.playing) together = it }, Modifier.padding(horizontal = 12.dp))
        val list = rememberLazyListState()
        LaunchedEffect(words.size) { if (words.isNotEmpty()) list.animateScrollToItem(words.size - 1 + (if (together) 1 else 0)) }
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (together) item { DragonRoom(link) }
            itemsIndexed(words) { _, w ->
                val mine = w.second == link.myName
                Row(Modifier.fillMaxWidth(), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start, verticalAlignment = Alignment.CenterVertically) {
                    Txt(if (w.second.isEmpty() || w.second == "app") "✦" else if (mine) tr("你") else w.second, ff(FF.Caption, FontWeight.SemiBold),
                        if (mine) T.blueInk else if (w.second == "app" || w.second.isEmpty()) T.oliveInk else T.greenInk)
                    Spacer(Modifier.width(10.dp))
                    Txt(w.first, ff(FF.Title2, FontWeight.SemiBold), T.glyph)
                    if (!sv) Store.cards.firstOrNull { it.h == w.first }?.let { c -> Spacer(Modifier.width(10.dp)); Txt(Store.cardRom(c, rom, place).plain(), lat(16f), T.greenInk) }
                }
            }
            note?.let { n -> item { Txt(n, ff(FF.Footnote), T.muted) } }
            if (!together && lost) item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Txt(tr("接了 {0} 個詞。", mineCount), ff(FF.Headline), T.glyph)
                    ProminentButton({ startSolo() }, Modifier.fillMaxWidth()) { Text(tr("再玩一次")) }
                }
            }
        }
        if (myTurn && (!together || link.playing)) Column(Modifier.fillMaxWidth().background(T.fn.copy(alpha = 0.35f)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            said?.let { Txt(it, ff(FF.Footnote), T.rustInk) }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (need != null) Txt(need, ff(FF.Title2, FontWeight.Bold), T.btnInk)
                GameField(typed, { typed = it }, if (sv) tr("打一個瑞典文的詞") else tr("打一個詞"), Modifier.weight(1f)) { submit() }
                ProminentButton({ submit() }, enabled = typed.isNotBlank()) { Text("↑") }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (left > 0) Txt(tr("{0} 秒", left), ff(FF.Caption, FontWeight.SemiBold), if (left <= 5) T.rustInk else T.muted)
                Spacer(Modifier.width(10.dp))
                Txt(if (together) tr("接了 {0} 個", mineCount) else tr("接了 {0} 個・最多 {1} 個", mineCount, best), ff(FF.Caption), T.muted, Modifier.weight(1f))
                TextButton(onClick = { giveUp() }) { Text(tr("認輸"), color = T.rustInk) }
            }
        }
    }
}

@Composable
private fun DragonRoom(link: DragonLink) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        RoomBar(link, link.playing)
        if (link.status == 2) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(T.fn.copy(alpha = 0.55f)).padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            val names = if (link.playing) link.order else link.everyone.sorted()
            for (n in names) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (link.playing && link.current == n) Txt("▶", ff(FF.Caption), T.blueInk)
                Txt(n + if (n == link.myName) tr("（你）") else "", ff(FF.Subheadline, FontWeight.SemiBold), if (n in link.outs) T.muted else T.glyph)
                Spacer(Modifier.weight(1f))
                if (!link.playing) Txt(if (n in link.ready) tr("準備好了") else tr("還沒準備好"), ff(FF.Caption), if (n in link.ready) T.greenInk else T.muted)
            }
            link.winner?.let { w -> Txt(if (w == link.myName) tr("你贏了！") else tr("{0} 贏了！", w), ff(FF.Title3, FontWeight.Bold), T.blueInk) }
            if (!link.playing) {
                Txt(tr("輪流接；時間到或認輸就出局，最後留下來的人贏。每一輪的時間照第一個人（名字排最前面）的設定。"), ff(FF.Caption), T.muted)
                val on = link.myName in link.ready
                ProminentButton({ link.setReady(!on) }, Modifier.fillMaxWidth(), tint = if (on) T.rustEdge else T.btnEdge, enabled = link.players.isNotEmpty()) {
                    Text(if (on) tr("不要了，先等一下") else tr("準備好了"))
                }
            } else if (!link.myTurn) link.current?.let { Txt(tr("輪到 {0}…", it), ff(FF.Body), T.muted) }
        }
    }
}
