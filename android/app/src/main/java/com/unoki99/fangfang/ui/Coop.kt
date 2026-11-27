package com.unoki99.fangfang.ui

import com.unoki99.fangfang.engine.svZhAll
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.RoomLink
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.Card
import com.unoki99.fangfang.engine.Lang
import com.unoki99.fangfang.engine.TwEnglish
import com.unoki99.fangfang.tr
import com.unoki99.fangfang.engine.plain
import com.unoki99.fangfang.engine.cps
import org.json.JSONArray
import org.json.JSONObject

// MARK: - 一起玩 (two or more players taking turns, over the internet: a room on the relay; the same game and the same
// messages as the iPhone app's CoopGame.swift, so every version plays with every other)
//
// Each player picks how they answer (手寫, 八選一 or 打字) and how many words, and presses 準備好了; the game starts
// once everyone has. On your turn a word from your own 練習範圍 (your own language) goes to the others only, never to
// your screen: they read you its clues one at a time (its reading; if you ask, its meaning, then its radicals) and
// see the answer. You answer on your screen and press 完成; your answer shows on theirs, and one of them presses 對
// or 錯. 10 points, 3 fewer for each extra clue; the most points wins. A word shows in the list only once answered.

/** what's sent (JSON; the same keys as the iPhone app's CoopMsg) */
class CoopMsg(val kind: String, val name: String) {
    var mode = 0; var rounds = 0; var word = ""; var reading = ""
    var clues: List<String> = emptyList(); var clueKinds: List<String> = emptyList(); var english = ""
    var lang = 0; var hints = 1; var text = ""; var squares: List<List<InkLine>> = emptyList(); var right = false
    fun json(): String = JSONObject().put("kind", kind).put("name", name).put("mode", mode).put("rounds", rounds).put("word", word)
        .put("reading", reading).put("clues", JSONArray(clues)).put("clueKinds", JSONArray(clueKinds)).put("english", english)
        .put("lang", lang).put("hints", hints).put("text", text).put("squares", InkLine.squaresJson(squares)).put("right", right).toString()
    companion object {
        fun of(s: String): CoopMsg? = try {
            val o = JSONObject(s)
            fun strs(k: String): List<String> { val a = o.optJSONArray(k) ?: return emptyList(); return (0 until a.length()).map { a.optString(it) } }
            CoopMsg(o.getString("kind"), o.getString("name")).apply {
                mode = o.optInt("mode"); rounds = o.optInt("rounds"); word = o.optString("word"); reading = o.optString("reading")
                clues = strs("clues"); clueKinds = strs("clueKinds"); english = o.optString("english"); lang = o.optInt("lang")
                hints = o.optInt("hints", 1); text = o.optString("text"); squares = InkLine.squaresOf(o.optJSONArray("squares")); right = o.optBoolean("right")
            }
        } catch (_: Exception) { null }
    }
}

class CoopQuestion(val from: String, val word: String, val reading: String, val clues: List<String>, val clueKinds: List<String>,
                   val english: String, val lang: Int) {
    var shown by mutableIntStateOf(1)
    var text by mutableStateOf("")
    var squares by mutableStateOf<List<List<InkLine>>>(emptyList())
    var submitted by mutableStateOf(false)
}

class CoopResult(val who: String, val word: String, val reading: String, val right: Boolean, val points: Int)

class CoopLink(name: String) : RoomLink(name) {
    /** who's pressed 準備好了: their way of answering, how many words */
    val ready = mutableStateMapOf<String, Pair<Int, Int>>()
    private var mine: Pair<Int, Int>? = null
    var playing by mutableStateOf(false)
    var order by mutableStateOf<List<String>>(emptyList())
    var modes by mutableStateOf<Map<String, Int>>(emptyMap())
    var schedule by mutableStateOf<List<String>>(emptyList())
    var turn by mutableIntStateOf(0)
    var question by mutableStateOf<CoopQuestion?>(null)
    val scores = mutableStateMapOf<String, Int>()
    val results = mutableStateListOf<CoopResult>()
    var game by mutableIntStateOf(0)

    val over: Boolean get() = playing && turn >= schedule.size
    val answerer: String? get() = schedule.getOrNull(turn)
    val myTurn: Boolean get() = answerer == myName
    val myTurnsBefore: Int get() = schedule.take(turn).count { it == myName }

    fun send(m: CoopMsg) { handle(m); sendPayload(m.json()) }
    override fun received(d: String) { CoopMsg.of(d)?.let { handle(it) } }
    override fun joined(name: String) {
        mine?.let { send(CoopMsg("ready", myName).apply { mode = it.first; rounds = it.second; right = true }) }
        startIfReady()
    }
    override fun left(name: String) { ready.remove(name); skipGone(); startIfReady() }

    fun setReady(on: Boolean, mode: Int, rounds: Int) {
        mine = if (on) mode to rounds else null
        send(CoopMsg("ready", myName).apply { this.mode = mode; this.rounds = rounds; right = on })
    }

    private fun skipGone() {
        val here = everyone
        while (playing) { val a = answerer ?: break; if (a in here) break; if (question?.from == a) question = null; turn++ }
    }

    private fun startIfReady() {
        if (playing && !over) return
        val all = everyone
        if (all.size < 2 || !ready.keys.containsAll(all)) return
        order = all.sorted()
        modes = order.associateWith { ready[it]?.first ?: 0 }
        val left = order.associateWith { maxOf(1, ready[it]?.second ?: 5) }.toMutableMap()
        val s = ArrayList<String>()
        while (left.values.any { it > 0 }) for (n in order) if ((left[n] ?: 0) > 0) { s.add(n); left[n] = left[n]!! - 1 }
        schedule = s
        turn = 0; question = null; results.clear()
        scores.clear(); for (n in order) scores[n] = 0
        ready.clear(); mine = null
        playing = true
        game++
    }

    private fun handle(m: CoopMsg) {
        when (m.kind) {
            "ready" -> { if (m.right) ready[m.name] = m.mode to m.rounds else ready.remove(m.name); startIfReady() }
            "question" -> question = CoopQuestion(m.name, m.word, m.reading, m.clues, m.clueKinds, m.english, m.lang)
            "hint" -> question?.let { if (it.from == m.name) it.shown = maxOf(it.shown, m.hints) }
            "submit" -> question?.let { q -> if (q.from == m.name) { q.text = m.text; q.squares = m.squares; q.submitted = true } }
            "judge" -> {
                val q = question ?: return
                if (!q.submitted) return
                val pts = if (m.right) points(q.shown) else 0
                scores[q.from] = (scores[q.from] ?: 0) + pts
                results.add(CoopResult(q.from, q.word, q.reading, m.right, pts))
                question = null
                turn++
                skipGone()
            }
        }
    }

    companion object { fun points(shown: Int) = maxOf(1, 10 - 3 * (shown - 1)) }
}

private val COOP_MODES = listOf("手寫", "八選一", "打字")

@Composable
fun CoopScreen(onClose: () -> Unit) {
    val link = remember { CoopLink(Prefs.coopName.value.ifBlank { tr("玩家") + (100..999).random() }) }
    DisposableEffect(Unit) { onDispose { link.close() } }
    var mode by Prefs.coopMode
    var rounds by Prefs.coopRounds
    val rom = Prefs.rom.value; val place = Prefs.place.value; val goal = Prefs.goal.value
    // my turns: my words, and the one being asked now (never shown here until it's been judged)
    var queue by remember { mutableStateOf<List<Card>>(emptyList()) }
    var mineCard by remember { mutableStateOf<Card?>(null) }
    var options by remember { mutableStateOf<List<Card>>(emptyList()) }
    var picked by remember { mutableStateOf<String?>(null) }
    var typed by remember { mutableStateOf("") }
    val squares = remember { mutableStateListOf<SnapshotStateList<InkStroke>>(mutableStateListOf()) }
    var side by remember { mutableStateOf(0f) }
    var hints by remember { mutableIntStateOf(1) }
    var sent by remember { mutableStateOf(false) }
    // (瑞典語, 英語: no handwriting: 八選一 or spelling it)
    val myMode = (link.modes[link.myName] ?: mode).let { if (Store.isSv && it == 0) 2 else it }
    val modeChoices = if (Store.isSv) listOf(1, 2) else listOf(0, 1, 2)
    fun modeName(i: Int) = if (Store.isSv && i == 2) tr("拼字") else tr(COOP_MODES[i.coerceIn(0, 2)])
    LaunchedEffect(Unit) { if (Store.isSv && mode == 0) mode = 2 }
    val iAmReady = link.ready.containsKey(link.myName)

    fun meanings(c: Card): Pair<String, String> {
        val kind = Lang.kind(c.k)
        val first = c.d.take(2).joinToString("；") { it.t }
        var en: List<String> = emptyList()
        if (kind == 0) en = TwEnglish.meanings(c.k)
        else { val d = Store.zh; val e = if (d != null && d.lang == kind) d.entry(c.k) else null
            if (e != null) {
                en = e.enList
                if (kind == 5 || kind == 6) {
                    val e3 = en.take(3).joinToString("; ")
                    // (英語: the Chinese lines without their word class, "n. 跑、賽跑" → 跑、賽跑)
                    val zh = (if (kind == 6) e.jp else e.svZhAll).take(2).map { if (kind == 6) it.replace(Regex("""^\s*([a-z]+\.\s*)+"""), "") else it }
                    return zh.joinToString("；").ifEmpty { first } to e3.ifEmpty { first }
                }
            }
        }
        if (kind == 2 || kind == 4) return first to first
        return first to en.take(3).joinToString("; ")
    }
    /** 英語, 瑞典語: seven words spelt like it (the fewest letters different; the same first or last letter counts
     *  as a bit closer), the rest any of the practice words */
    fun spellingAlike(c: Card): List<Card> {
        val me = c.h.lowercase()
        fun dist(a: String, b: String): Int {
            if (a.isEmpty()) return b.length
            if (b.isEmpty()) return a.length
            var prev = IntArray(b.length + 1) { it }; var cur = IntArray(b.length + 1)
            for (i in 1..a.length) {
                cur[0] = i
                for (j in 1..b.length) cur[j] = minOf(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + if (a[i - 1] == b[j - 1]) 0 else 1)
                val t = prev; prev = cur; cur = t
            }
            return prev[b.length]
        }
        val scored = ArrayList<Pair<Int, Card>>()
        val most = maxOf(2, me.length / 2)
        for (x in Store.cards.take(30000)) {
            if (x.k == c.k) continue
            val b = x.h.lowercase()
            if (b == me || kotlin.math.abs(b.length - me.length) > 2 || (b.contains(' ') && !me.contains(' '))) continue
            var d = dist(me, b) * 2
            if (b.firstOrNull() == me.firstOrNull()) d -= 1
            if (b.lastOrNull() == me.lastOrNull()) d -= 1
            if (d <= most * 2) scored.add(d to x)
        }
        val out = ArrayList<Card>()
        val used = hashSetOf(me)
        for ((_, x) in scored.sortedBy { it.first }.take(14).shuffled()) {
            if (!used.add(x.h.lowercase())) continue
            out.add(x)
            if (out.size == 7) break
        }
        if (out.size < 7) out += Store.distractors(c, 7 - out.size).filter { used.add(it.h.lowercase()) }
        return out.take(7)
    }
    fun radicals(h: String): String {
        val z = Store.zh ?: return ""
        val rs = h.cps().map { ch -> z.charIndex[ch]?.let { z.chars[it].radical } ?: "？" }
        return if (rs.any { it != "？" }) rs.joinToString("、") else ""
    }
    fun ask() {
        val k = link.myTurnsBefore
        sent = false; picked = null; typed = ""; squares.clear(); squares.add(mutableStateListOf()); hints = 1
        val c = queue.getOrNull(k) ?: run { mineCard = null; return }
        mineCard = c
        options = ((if (Store.isSv) spellingAlike(c) else Store.distractors(c, 7)) + c).shuffled()
        val reading = if (Store.isSv && !Store.isEn) "" else Store.cardRom(c, rom, place).plain()
        val m = meanings(c)
        val r = radicals(c.h)
        link.send(CoopMsg("question", link.myName).apply {
            word = c.h; this.reading = reading; lang = Lang.kind(c.k); english = m.second
            // 英語: the meaning first, then the IPA, then how many letters and the first one
            if (Store.isEn) {
                clues = if (reading.isEmpty()) listOf(m.first, "") else listOf(m.first, reading, "")
                clueKinds = if (reading.isEmpty()) listOf("meaning", "letters") else listOf("meaning", "reading", "letters")
            }
            else if (Store.isSv) { clues = listOf(m.first, ""); clueKinds = listOf("meaning", "letters") }
            else { clues = listOf(reading, m.first, r); clueKinds = listOf("reading", "meaning", if (r.isEmpty()) "count" else "radicals") }
        })
    }
    fun begin() {
        val seen = HashSet<String>()
        val pool = (Store.dueCards.shuffled() + Store.practiceCards.shuffled())
            .filter { seen.add(it.k) && (myMode != 0 || Store.isSv || Store.canWrite(it.h)) }
        queue = pool.take(link.schedule.count { it == link.myName })
        mineCard = null
    }
    // (a new game: my words for it; then, on my turns, the next of them sent to the others)
    var lastGame by remember { mutableIntStateOf(0) }
    LaunchedEffect(link.game, link.turn) {
        if (link.game == 0) return@LaunchedEffect
        if (lastGame != link.game) { lastGame = link.game; begin() }
        if (link.playing && !link.over && link.myTurn) ask()
    }
    LaunchedEffect(link.results.size) {
        val r = link.results.lastOrNull() ?: return@LaunchedEffect
        if (r.who == link.myName) queue.firstOrNull { it.h == r.word }?.let { Store.answer(it, r.right, goal) }
    }

    fun clueText(q: CoopQuestion, i: Int): String {
        val v = q.clues[i]
        return when (q.clueKinds.getOrNull(i)) {
            "reading" -> tr("讀音：") + v
            "meaning" -> {
                // (the meaning in the language this app's 主要解釋 says for the word's language)
                val en = q.english.isNotEmpty() && (v.isEmpty() || when (q.lang) { 0 -> Prefs.twEnglish.value; 1 -> Prefs.zhEnglish.value; 3 -> Prefs.hakEnglish.value; 2 -> true; else -> false })
                tr("意思：") + (if (en) q.english else v)
            }
            "radicals" -> if (v.isEmpty()) "" else tr("部首：") + v
            "letters" -> tr("{0} 個字母，開頭是「{1}」", q.word.length, q.word.take(1))
            "count" -> tr("{0} 個字", q.word.cps().size)
            else -> v
        }
    }

    Column(Modifier.fillMaxSize()) {
        TopBar(tr("一起玩"), { link.close(); onClose() }, close = true, settings = false) {
            if (link.playing && link.myTurn && myMode == 0) PenButton()
            RomButton()
        }
        Column(Modifier.fillMaxSize().dragScrollY(rememberScrollState()).padding(16.dp).widthIn(max = 700.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            RoomBar(link, link.playing && !link.over)
            // the players, whose turn, the scores
            if (link.status == 2) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(T.fn.copy(alpha = 0.55f)).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val names = if (link.playing) link.order else link.everyone.sorted()
                for (n in names) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (link.playing && link.answerer == n) Txt("▶", ff(FF.Caption), T.blueInk)
                    Txt(n + if (n == link.myName) tr("（你）") else "", ff(FF.Subheadline, FontWeight.SemiBold), T.glyph)
                    if (link.playing) link.modes[n]?.let { Txt(modeName(it), ff(FF.Caption), T.muted) }
                    Spacer(Modifier.weight(1f))
                    if (!link.playing || link.over) {
                        val r = link.ready[n]
                        if (r != null) Txt(tr("準備好了") + "・" + modeName(r.first) + "・" + tr("{0} 題", r.second), ff(FF.Caption), T.greenInk)
                        else Txt(tr("還沒準備好"), ff(FF.Caption), T.muted)
                    }
                    if (link.playing) Txt("${link.scores[n] ?: 0}", ff(FF.Title3, FontWeight.Bold), T.blueInk)
                }
                if (link.players.isEmpty()) Txt(tr("等其他人進這個房間…"), ff(FF.Footnote), T.muted)
            }
            if (link.status == 2) {
                if (link.over) {
                    val best = link.scores.values.maxOrNull() ?: 0
                    val winners = link.order.filter { (link.scores[it] ?: 0) == best }
                    Txt(if (winners.size == 1) tr("{0} 贏了！", winners[0]) else tr("平手！"), ff(FF.Title2, FontWeight.Bold), T.blueInk)
                }
                if (!link.playing || link.over) {
                    // the lobby: my way of answering, how many words, 準備好了
                    Txt(tr("你的名字"), ff(FF.Subheadline, FontWeight.SemiBold), T.muted)
                    GameField(Prefs.coopName.value, { Prefs.coopName.value = it }, tr("名字"), enabled = !iAmReady && link.players.isEmpty())
                    Txt(tr("（改名字要重新進房間才會用上）"), ff(FF.Caption2), T.muted)
                    Txt(tr("你怎麼答"), ff(FF.Subheadline, FontWeight.SemiBold), T.muted)
                    Segmented(modeChoices.map { it to modeName(it) }, mode, { if (!iAmReady) mode = it })
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Txt(tr("你答 {0} 題", rounds), ff(FF.Body), T.glyph, Modifier.weight(1f))
                        SoftButton({ if (!iAmReady && rounds > 1) rounds-- }) { Text("−") }
                        Spacer(Modifier.width(8.dp))
                        SoftButton({ if (!iAmReady && rounds < 20) rounds++ }) { Text("+") }
                    }
                    Txt(tr("輪流答題，每個人用自己選的方式答。輪到你的時候，詞只會出現在別人的畫面上：他們一次給你一個提示（先是讀音，要的話再給意思、部首），你在自己的畫面上答，按「完成」，他們再按對或錯。每個人的詞都從自己的練習範圍（{0}）出，用自己的語言。答對 10 分，每多要一個提示少 3 分。", Store.practiceName),
                        ff(FF.Footnote), T.muted)
                    ProminentButton({ link.setReady(!iAmReady, mode, rounds) }, Modifier.fillMaxWidth().heightIn(min = 44.dp),
                        tint = if (iAmReady) T.rustEdge else T.btnEdge, enabled = link.players.isNotEmpty()) {
                        Text(if (iAmReady) tr("不要了，先等一下") else tr("準備好了"), style = ff(FF.Headline))
                    }
                } else if (link.myTurn) {
                    // my turn: the clues are on the others' screens; I answer here
                    Txt(tr("輪到你了"), ff(FF.Title3, FontWeight.Bold), T.blueInk)
                    val c = mineCard
                    if (c == null) {
                        Txt(tr("你的練習範圍沒有詞可以問了。"), ff(FF.Body), T.muted)
                        SoftButton({
                            link.send(CoopMsg("question", link.myName).apply { word = "—"; clues = listOf("—") })
                            link.send(CoopMsg("submit", link.myName).apply { text = "—" })
                            link.send(CoopMsg("judge", link.myName))
                        }) { Text(tr("跳過")) }
                    } else if (sent) {
                        Txt(tr("等對方看你的答案…"), ff(FF.Body), T.muted)
                    } else {
                        Txt(tr("請對方唸提示給你聽（第 {0} 個提示）。", hints), ff(FF.Footnote), T.muted)
                        when (myMode) {
                            0 -> GameWriteSquares(squares) { side = it }
                            1 -> for (row in options.chunked(2)) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                for (o in row) Box(Modifier.weight(1f).heightIn(min = 50.dp).clip(RoundedCornerShape(12.dp))
                                    .background(if (picked == o.h) T.blue else T.fn).border(2.dp, if (picked == o.h) T.blueEdge else T.fnEdge, RoundedCornerShape(12.dp))
                                    .clickable { picked = o.h }, contentAlignment = Alignment.Center) {
                                    Txt(o.h, ff(FF.Title3, FontWeight.SemiBold), T.glyph)
                                }
                                if (row.size == 1) Spacer(Modifier.weight(1f))
                            }
                            else -> GameField(typed, { typed = it }, if (Store.isSv) tr("打這個詞") else tr("打這個詞的字"))
                        }
                        val can = when (myMode) { 0 -> squares.any { it.isNotEmpty() }; 1 -> picked != null; else -> typed.isNotBlank() }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            TextButton(onClick = { hints++; link.send(CoopMsg("hint", link.myName).apply { this.hints = hints }) },
                                enabled = hints < (link.question?.clues?.size ?: 1)) { Text(tr("再給一個提示"), color = T.btnInk) }
                            Spacer(Modifier.weight(1f))
                            ProminentButton({
                                val m = CoopMsg("submit", link.myName)
                                when (myMode) {
                                    0 -> m.squares = squares.map { InkLine.from(it, side, Prefs.handRainbow.value, HandInk.solid) }
                                    1 -> m.text = picked ?: ""
                                    else -> m.text = typed.trim()
                                }
                                sent = true
                                link.send(m)
                            }, enabled = can) { Text(tr("完成"), style = ff(FF.Headline)) }
                        }
                    }
                } else {
                    // someone else's turn: their word, its clues so far, and, once they've answered, 對 / 錯
                    val q = link.question
                    if (q == null) Txt(tr("等 {0} 的題目…", link.answerer ?: ""), ff(FF.Body), T.muted)
                    else {
                        Txt(tr("輪到 {0}：唸提示給他聽", q.from), ff(FF.Title3, FontWeight.Bold), T.blueInk)
                        for (i in 0 until minOf(q.shown, q.clues.size)) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Txt("${i + 1}", ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.width(18.dp))
                            Txt(clueText(q, i), ff(FF.Title3), T.glyph)
                        }
                        if (q.shown < q.clues.size) Txt(tr("（還有 {0} 個提示，他要的時候才會出現）", q.clues.size - q.shown), ff(FF.Caption), T.muted)
                        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(T.fn).padding(10.dp)) {
                            Txt(tr("答案（不要給 {0} 看）", q.from), ff(FF.Caption), T.muted)
                            Txt(q.word, ff(FF.LargeTitle, FontWeight.Bold), T.glyph)
                            if (q.reading.isNotEmpty()) Txt(q.reading, lat(18f), T.greenInk)
                        }
                        if (q.submitted) {
                            Txt(tr("{0} 的答案", q.from), ff(FF.Subheadline, FontWeight.SemiBold), T.muted)
                            if (q.squares.isNotEmpty()) WrittenSquares(q.squares, 130.dp) else Txt(q.text, ff(FF.Title, FontWeight.SemiBold), T.glyph)
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                ProminentButton({ link.send(CoopMsg("judge", link.myName).apply { right = true }) }, Modifier.weight(1f), tint = T.greenEdge) { Text(tr("對")) }
                                ProminentButton({ link.send(CoopMsg("judge", link.myName).apply { right = false }) }, Modifier.weight(1f), tint = T.rustEdge) { Text(tr("錯")) }
                            }
                        } else Txt(tr("{0} 正在答…", q.from), ff(FF.Body), T.muted)
                    }
                }
            }
            // the words answered so far (only once answered: never the one being asked)
            if (link.results.isNotEmpty()) Txt(tr("答過的詞"), ff(FF.Subheadline, FontWeight.SemiBold), T.muted)
            for (r in link.results.reversed()) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Txt(if (r.right) "✓" else "✗", ff(FF.Body, FontWeight.Bold), if (r.right) T.greenInk else T.rustInk)
                Txt(r.word, ff(FF.Title3, FontWeight.SemiBold), T.glyph)
                if (r.reading.isNotEmpty()) Txt(r.reading, lat(14f), T.greenInk)
                Spacer(Modifier.weight(1f))
                Txt(r.who + if (r.right) "　+${r.points}" else "", ff(FF.Caption), T.muted)
            }
        }
    }
}
