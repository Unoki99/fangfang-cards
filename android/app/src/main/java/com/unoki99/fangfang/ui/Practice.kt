package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Player
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID
import kotlin.random.Random

/** the practice screens, over everything */
@Composable
fun PracticeHost(p: Practice) {
    BackHandler { UI.practice = null; UI.handwritingOnly = null }
    val stars = remember { StarField() }
    AppBackground {
        StarBox(stars, Modifier.fillMaxSize().navigationBarsPadding()) {
            when (p) {
                Practice.STUDY -> StudyScreen(false, stars)
                Practice.BLANKS -> StudyScreen(true, stars)
                Practice.WEEK -> StudyScreen(false, stars, words = Store.weekCards)
                Practice.WEEK_TEST -> StudyScreen(false, stars, words = Store.weekCards, test = true)
                Practice.MEMORY -> MemoryScreen(stars)
                Practice.SCRAMBLE -> ScrambleScreen(false, stars)
                Practice.READING -> ScrambleScreen(true, stars)
                Practice.TONES -> ToneScreen(stars)
                Practice.HANDWRITING -> HandwritingScreen(only = UI.handwritingOnly) { UI.handwritingOnly = null; handwritingGiven = emptyMap(); close() }
            }
        }
    }
}

private fun close() { UI.practice = null; Player.stop() }

// MARK: - 練習 (multiple choice)

enum class QuizKind { MEANING_TO_WORD, WORD_TO_MEANING, LISTEN, FILL_BLANK, ROMANIZATION }

class Question(val card: Card, val kind: QuizKind, val options: List<Card>, val example: Example?) { val id: String = UUID.randomUUID().toString() }

private fun kinds(c: Card): List<QuizKind> = QuizKind.entries.filter {
    when (it) {
        QuizKind.LISTEN -> c.audio != null
        QuizKind.FILL_BLANK -> c.blankExamples.isNotEmpty()
        else -> c.d.isNotEmpty()
    }
}

private fun make(c: Card, k: QuizKind) = Question(c, k, (Store.distractors(c) + c).shuffled(),
    if (k == QuizKind.FILL_BLANK) c.blankExamples.randomOrNull() else null)

/** words = only these (本週學習); test = 本週學習's final test: one question per word, nothing asked again, a score at the end */
@Composable
private fun StudyScreen(blanksOnly: Boolean, stars: StarField, words: List<Card>? = null, test: Boolean = false) {
    val rom = Prefs.rom.value; val place = Prefs.place.value
    val goal = Prefs.goal.value; val size = Prefs.sessionSize.value
    val queue = remember { mutableStateListOf<Question>() }
    var idx by remember { mutableIntStateOf(0) }
    var chosen by remember { mutableStateOf<Card?>(null) }
    var right by remember { mutableIntStateOf(0) }
    var wrong by remember { mutableIntStateOf(0) }
    val learned = remember { mutableStateListOf<Card>() }
    val retried = remember { HashSet<String>() }
    var started by remember { mutableStateOf(false) }
    val missed = remember { mutableStateListOf<Card>() }
    val pool0 = remember { words }
    var resumed by remember { mutableStateOf(false) }

    // a round left half way
    val saveName = if (test) "test" else if (blanksOnly) "blanks" else if (pool0 != null) "week" else "study"
    val saveScope = if (pool0 != null) -1 else Store.practiceTopic
    /** next: the question on show has been answered (it isn't asked again when the round is picked up) */
    fun saveNow(next: Boolean = false) {
        val at = idx + if (next) 1 else 0
        if (at >= queue.size) { PracticeSave.clear(saveName, Store.isZh); return }
        PracticeSave.save(saveName, Store.isZh, saveScope, mapOf(
            "qs" to queue.map { q -> mapOf("k" to q.card.k, "kind" to q.kind.ordinal, "opts" to q.options.map { it.k }, "ex" to q.example?.h) },
            "idx" to at, "right" to right, "wrong" to wrong, "learned" to learned.map { it.k }, "retried" to retried.toList(),
            "missed" to missed.map { it.k }))
    }
    @Suppress("UNCHECKED_CAST")
    fun restore(): Boolean {
        val s = PracticeSave.load(saveName, Store.isZh, saveScope) ?: return false
        val saved = (s["qs"] as? List<Any?>)?.filterIsInstance<Map<String, Any?>>() ?: return false
        val at0 = PracticeSave.int(s["idx"])
        val qs = ArrayList<Question>(); var at = 0
        for ((i, sq) in saved.withIndex()) {
            val c = Store.cardFor(sq["k"] as? String ?: continue) ?: continue
            val kind = QuizKind.entries.getOrNull(PracticeSave.int(sq["kind"])) ?: continue
            val opts = PracticeSave.strings(sq["opts"]).mapNotNull { Store.cardFor(it) }
            if (!opts.contains(c)) continue
            val exH = sq["ex"] as? String
            val ex = exH?.let { h -> (if (kind == QuizKind.FILL_BLANK) c.blankExamples else c.d.flatMap { it.x }).firstOrNull { it.h == h } }
            if (kind == QuizKind.FILL_BLANK && ex == null) continue
            if (i < at0) at++
            qs.add(Question(c, kind, opts, ex))
        }
        if (at >= qs.size) return false
        queue.clear(); queue.addAll(qs); idx = at; chosen = null
        right = PracticeSave.int(s["right"]); wrong = PracticeSave.int(s["wrong"])
        learned.clear(); learned.addAll(PracticeSave.strings(s["learned"]).mapNotNull { Store.cardFor(it) })
        retried.clear(); retried.addAll(PracticeSave.strings(s["retried"]))
        missed.clear(); missed.addAll(PracticeSave.strings(s["missed"]).mapNotNull { Store.cardFor(it) })
        started = true; resumed = true
        return true
    }

    fun start() {
        missed.clear()
        if (test) {
            // every word of the week once, in a random way
            queue.clear()
            queue.addAll((pool0 ?: emptyList()).shuffled().mapNotNull { c -> kinds(c).randomOrNull()?.let { make(c, it) } })
            idx = 0; chosen = null; right = 0; wrong = 0; learned.clear(); retried.clear()
            started = true
            saveNow()
            return
        }
        val pool = pool0 ?: Store.practiceCards
        val words = pool.filter { !blanksOnly || it.blankExamples.isNotEmpty() }.shuffled().sortedBy { Store.streak(it) }
            .take(maxOf(1, if (pool0 != null) pool.size else size))
        val first = ArrayList<Question>(); val second = ArrayList<Question>()
        for (c in words) {
            if (blanksOnly) {
                val xs = c.blankExamples.shuffled()
                first.add(Question(c, QuizKind.FILL_BLANK, (Store.distractors(c) + c).shuffled(), xs[0]))
                if (xs.size > 1) second.add(Question(c, QuizKind.FILL_BLANK, (Store.distractors(c) + c).shuffled(), xs[1]))
            } else {
                val ks = kinds(c).shuffled()
                ks.firstOrNull()?.let { first.add(make(c, it)) }
                if (ks.size > 1) second.add(make(c, ks[1]))
            }
        }
        queue.clear(); queue.addAll(first.shuffled() + second.shuffled())
        idx = 0; chosen = null; right = 0; wrong = 0; learned.clear(); retried.clear()
        started = true
        saveNow()
    }
    LaunchedEffect(Unit) { if (!started && !restore()) start() }
    LaunchedEffect(idx) { if (started) saveNow() }

    fun pick(o: Card, q: Question) {
        if (chosen != null) return
        chosen = o
        val ok = o == q.card
        if (ok) right++ else { wrong++; if (test) missed.add(q.card) }
        if (q.kind != QuizKind.LISTEN) q.card.audio?.let { Player.play(it) }
        if (test) { Store.answer(q.card, ok, goal); saveNow(true); return }
        if (Store.answer(q.card, ok, goal)) {
            learned.add(q.card)
            val rest = queue.subList(idx + 1, queue.size).filter { it.card != q.card }
            val head = queue.subList(0, idx + 1).toList()
            queue.clear(); queue.addAll(head + rest)
        } else if (!ok && !retried.contains(q.card.k)) {
            retried.add(q.card.k)
            val other = kinds(q.card).filter { it != q.kind }.randomOrNull() ?: q.kind
            queue.add(make(q.card, other))
        }
        saveNow(true)
    }

    Column(Modifier.fillMaxSize()) {
        TopBar(if (test) tr("期末測驗") else if (pool0 != null) tr("本週學習") else "", { close() }, close = true, settings = false) {
            if (idx > 0 && idx < queue.size) IconButton(onClick = { start() }) { Icon(Icons.Filled.Refresh, tr("重新開始"), tint = T.glyph) }
        }
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) { ResumedNote(resumed) { resumed = false } }
        if (queue.isNotEmpty() && idx < queue.size) Row(Modifier.fillMaxWidth().widthIn(max = 700.dp).padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PotionBar(idx.toDouble() / maxOf(queue.size, 1), 22.dp, showMarks = false, label = tr("練習進度"), modifier = Modifier.weight(1f))
            Txt(tr("{0}／{1}", idx + 1, queue.size), lat(14f), T.muted)
        }
        Box(Modifier.fillMaxSize()) {
            when {
                !started -> {}
                queue.isEmpty() -> Txt(if (blanksOnly) tr("不熟的詞裡沒有可以填空的例句。") else if (pool0 != null) tr("本週還沒有選詞。") else tr("沒有不熟的詞可以練習。"),
                    ff(FF.Body), T.muted, Modifier.align(Alignment.Center))
                idx >= queue.size && test -> TestSummary(right, wrong, missed)
                idx >= queue.size -> Summary(tr("答對 {0} 題，答錯 {1} 題", right, wrong), learned, onAgain = { start() },
                    againEnabled = if (pool0 == null) Store.practiceCards.isNotEmpty() else pool0.isNotEmpty())
                else -> {
                    val q = queue[idx]
                    LaunchedEffect(q.id) { if (q.kind == QuizKind.LISTEN) q.card.audio?.let { Player.play(it) } }
                    Column(Modifier.fillMaxSize().widthIn(max = 640.dp).align(Alignment.TopCenter).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Prompt(q, rom, place)
                        Options(q, chosen, rom, place) { pick(it, q) }
                        chosen?.let { c ->
                            Feedback(q, c, learned.contains(q.card), rom, place, last = idx + 1 >= queue.size) { chosen = null; idx++ }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun QLabel(s: String) = Txt(s, ff(FF.Subheadline, FontWeight.Bold), T.oliveInk)

@Composable
private fun Prompt(q: Question, rom: Int, place: Int) {
    val c = q.card
    Panel {
        when (q.kind) {
            QuizKind.MEANING_TO_WORD -> {
                QLabel(if (Store.isZh) tr("這個意思是哪個詞？") else tr("這個意思的台語是？")); Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    c.d.firstOrNull()?.p?.takeIf { it.isNotEmpty() }?.let { Chip(it) }
                    Txt(c.firstMeaning, ff(FF.Title3), T.glyph)
                }
            }
            QuizKind.WORD_TO_MEANING -> {
                QLabel(tr("這個詞是什麼意思？"))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Txt(c.h, sz(52f, FontWeight.Medium), T.blueInk, Modifier.weight(1f))
                    c.audio?.let { PlayButton(it, 44.dp) }
                }
                Txt(Store.cardRom(c, rom, place).annotated(), lat(24f), T.greenInk)
            }
            QuizKind.LISTEN -> {
                QLabel(tr("聽發音，選出正確的詞"))
                Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) { c.audio?.let { PlayButton(it, 84.dp) } }
            }
            QuizKind.FILL_BLANK -> {
                QLabel(tr("例句填空")); Spacer(Modifier.height(10.dp))
                q.example?.let { x ->
                    Txt(x.bh ?: x.h, ff(FF.Title3), T.blueInk)
                    Store.blankRom(c, x, rom, place)?.let { Txt(it.annotated(), lat(17f), T.greenInk) }
                    Txt(x.z, ff(FF.Subheadline), T.muted)
                    Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        PlayButton(Audio.examplePath(x.n), 28.dp); Txt(tr("聽例句（提示）"), ff(FF.Caption), T.muted)
                    }
                }
            }
            QuizKind.ROMANIZATION -> {
                QLabel(tr("這個詞怎麼唸？"))
                Txt(c.h, sz(60f, FontWeight.Medium), T.blueInk)
                Txt(c.firstMeaning, ff(FF.Footnote), T.muted, maxLines = 2)
            }
        }
    }
}

@Composable
private fun Options(q: Question, chosen: Card?, rom: Int, place: Int, onPick: (Card) -> Unit) {
    val wide = q.kind == QuizKind.WORD_TO_MEANING || q.kind == QuizKind.ROMANIZATION
    val rows = if (wide) q.options.map { listOf(it) } else q.options.chunked(2)
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        for (row in rows) Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            for (o in row) {
                val answered = chosen != null
                val isRight = o == q.card; val isPicked = chosen == o
                val fill = if (answered && isRight) T.green else if (answered && isPicked) T.rust else T.key
                val edge = if (answered && isRight) T.greenEdge else if (answered && isPicked) T.rustEdge else T.keyEdge
                Column(Modifier.weight(1f).heightIn(min = 64.dp).clip(RoundedCornerShape(18.dp)).background(fill).border(2.dp, edge, RoundedCornerShape(18.dp))
                    .clickable(enabled = !answered) { onPick(o) }.padding(14.dp),
                    horizontalAlignment = if (q.kind == QuizKind.WORD_TO_MEANING) Alignment.Start else Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center) {
                    when (q.kind) {
                        QuizKind.WORD_TO_MEANING -> Txt(o.firstMeaning, ff(FF.Body), T.glyph, maxLines = 3)
                        QuizKind.ROMANIZATION -> Txt(Store.cardRom(o, rom, place).annotated(), lat(22f), T.greenInk)
                        else -> {
                            Txt(o.h, sz(30f, FontWeight.Medium), T.blueInk, maxLines = 1)
                            if (answered) Txt(Store.cardRom(o, rom, place).annotated(), lat(14f), T.greenInk)
                        }
                    }
                }
            }
            if (row.size == 1 && !wide) Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun Feedback(q: Question, picked: Card, learnedNow: Boolean, rom: Int, place: Int, last: Boolean, onNext: () -> Unit) {
    val ok = picked == q.card
    val c = q.card
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Panel {
            Txt(if (ok) (if (learnedNow) tr("答對了！學會了") else tr("答對了！")) else tr("答錯了"), ff(FF.Headline), if (ok) T.greenInk else T.rustInk)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Txt(c.h, ff(FF.Title, FontWeight.Medium), T.blueInk)
                Txt(Store.cardRom(c, rom, place).annotated(), lat(20f), T.greenInk)
                Txt(Store.cardZy(c, place).annotated(), ff(FF.Body), T.purpleInk, Modifier.weight(1f))
                c.audio?.let { PlayButton(it, 34.dp) }
            }
            val sense = if (q.kind == QuizKind.FILL_BLANK) q.example?.let { c.meaning(it) } else null
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                sense?.p?.takeIf { it.isNotEmpty() }?.let { Chip(it) }
                Txt(sense?.t ?: c.firstMeaning, ff(FF.Body), T.glyph)
            }
            if (q.kind == QuizKind.FILL_BLANK) q.example?.let { x ->
                Spacer(Modifier.height(4.dp))
                Txt(Store.exampleHan(c, x, place, T.glyph.argbInt()).annotated(), ff(FF.Body))
                Txt(Store.exampleRom(c, x, rom, place).annotated(), lat(15f), T.greenInk)
            }
        }
        ProminentButton(onClick = onNext, Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text(if (last) tr("看結果") else tr("下一題"), style = ff(FF.Headline)) }
    }
}

@Composable
private fun BoxScope.TestSummary(right: Int, wrong: Int, missed: List<Card>) {
    val score = right.toDouble() / maxOf(right + wrong, 1)
    Column(Modifier.align(Alignment.TopCenter).widthIn(max = 560.dp).verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Txt(tr("期末測驗"), ff(FF.LargeTitle, FontWeight.Bold), T.glyph)
        Txt(tr("{0} 分", Math.round(score * 100)), ff(FF.Title, FontWeight.Bold), if (score >= 0.8) T.greenInk else T.rustInk)
        PotionBar(score, 24.dp, showMarks = false, label = tr("分數"))
        Txt(tr("答對 {0} 個，答錯 {1} 個", right, wrong), ff(FF.Body), T.muted)
        if (missed.isNotEmpty()) Panel {
            Txt(tr("答錯的詞："), ff(FF.Headline), T.rustInk)
            for (c in missed) WordRow(c)
        }
        if (missed.isNotEmpty()) ProminentButton(onClick = { Store.finishWeek(missed.map { it.k }); close() }, Modifier.fillMaxWidth()) {
            Text(tr("開始新的一週（答錯的 {0} 個詞留下來）", missed.size))
        }
        SoftButton(onClick = { Store.finishWeek(); close() }, Modifier.fillMaxWidth()) { Text(tr("結束這一週（清空本週的詞）")) }
        SoftButton(onClick = { close() }, Modifier.fillMaxWidth()) { Text(tr("先不要，繼續這一週")) }
        Txt(tr("詞還是會留在「不熟」或「熟悉」，只是不在本週的清單裡。"), ff(FF.Caption), T.muted)
    }
}

@Composable
private fun BoxScope.Summary(line: String, learned: List<Card>, onAgain: () -> Unit, againEnabled: Boolean = true) {
    Column(Modifier.align(Alignment.Center).widthIn(max = 560.dp).padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Txt(tr("練習完了"), ff(FF.LargeTitle, FontWeight.Bold), T.glyph)
        Txt(line, ff(FF.Body), T.muted)
        if (learned.isNotEmpty()) Panel {
            Txt(tr("學會了，移到「熟悉」："), ff(FF.Headline), T.greenInk)
            for (c in learned) WordRow(c)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SoftButton(onClick = onAgain, Modifier.weight(1f), enabled = againEnabled) { Text(tr("再練一次")) }
            ProminentButton(onClick = { close() }, Modifier.weight(1f)) { Text(tr("完成")) }
        }
    }
}

// MARK: - 聲調練習

class ToneOption(val id: String, val tone: Int, val rom: List<String>)
class ToneQuestion(val card: Card, val options: List<ToneOption>, val answer: ToneOption) { val id: String = UUID.randomUUID().toString() }

private val TONE_NAMES = mapOf(1 to "陰平", 2 to "陰上", 3 to "陰去", 4 to "陰入", 5 to "陽平", 7 to "陽去", 8 to "陽入")

private val ZH_TONE_NAMES = mapOf(0 to "輕聲", 1 to "陰平", 2 to "陽平", 3 to "上聲", 4 to "去聲")

/** 華語: the word with each tone on its last syllable (in 拼音 or 注音, as shown) */
private fun zhToneQuestion(c: Card): ToneQuestion? {
    val d = Store.zh ?: return null
    val tw = c.zs ?: return null
    val syl = if (Prefs.zhPlace.value == 1) (c.zl ?: tw) else tw
    val li = syl.indexOfLast { it != "-" && it != "_" }
    if (li < 0) return null
    val tone = Zhuyin.tone(syl[li])
    val all = ArrayList<ToneOption>(); var answer: ToneOption? = null
    for (t in listOf(1, 2, 3, 4, 0)) {
        if (t == 0 && tone != 0) continue
        val s = syl.toMutableList(); s[li] = Zhuyin.withTone(syl[li], t)
        val r = d.readingPlain(s, Prefs.zhRom.value)
        val o = ToneOption("zh$t", t, listOf(r, r, r))
        all.add(o)
        if (t == tone) answer = o
    }
    return answer?.let { ToneQuestion(c, all, it) }
}

private fun toneQuestion(c: Card, rom: Int): ToneQuestion? {
    if (c.isZh) return zhToneQuestion(c)
    if (c.a == null) return null
    val codes = c.c ?: return null
    val last = codes.lastOrNull() ?: return null
    val tone = last.lastOrNull()?.digitToIntOrNull() ?: return null
    val base = last.dropLast(1)
    val prefix = codes.dropLast(1).map { Store.syl[it] ?: listOf("", "", "") }
    val all = ArrayList<ToneOption>(); var answer: ToneOption? = null
    for (t in listOf(1, 2, 3, 4, 5, 7, 8)) {
        val code = base + t
        val s = Store.syl[code] ?: continue
        if (s.size != 3) continue
        val r = (0 until 3).map { i -> (prefix.map { it[i] } + s[i]).joinToString("-") }
        val o = ToneOption(code, t, r)
        all.add(o)
        if (t == tone) answer = o
    }
    if (answer == null || all.size < 2) return null
    val pairs = if (rom == 0) mapOf(1 to 8, 8 to 1, 3 to 4, 4 to 3) else mapOf(1 to 4, 4 to 1)
    val pick = arrayListOf(answer)
    pairs[answer.tone]?.let { p -> all.firstOrNull { it.tone == p }?.let { pick.add(it) } }
    for (o in all.shuffled()) if (pick.size < 4 && !pick.contains(o)) pick.add(o)
    return ToneQuestion(c, pick.shuffled(), answer)
}

@Composable
private fun ToneScreen(stars: StarField) {
    val rom = Prefs.rom.value
    val queue = remember { mutableStateListOf<ToneQuestion>() }
    var idx by remember { mutableIntStateOf(0) }
    var chosen by remember { mutableStateOf<ToneOption?>(null) }
    var right by remember { mutableIntStateOf(0) }
    var wrong by remember { mutableIntStateOf(0) }
    var resumed by remember { mutableStateOf(false) }
    /** next: the question on show has been answered */
    fun saveNow(next: Boolean = false) {
        val at = idx + if (next) 1 else 0
        if (at >= queue.size) { PracticeSave.clear("tone", Store.isZh); return }
        PracticeSave.save("tone", Store.isZh, Store.practiceTopic, mapOf("keys" to queue.map { it.card.k }, "idx" to at, "right" to right, "wrong" to wrong))
    }
    fun restore(): Boolean {
        val s = PracticeSave.load("tone", Store.isZh, Store.practiceTopic) ?: return false
        val at0 = PracticeSave.int(s["idx"])
        val qs = ArrayList<ToneQuestion>(); var at = 0
        for ((i, k) in PracticeSave.strings(s["keys"]).withIndex()) {
            val q = Store.cardFor(k)?.let { toneQuestion(it, rom) } ?: continue
            if (i < at0) at++
            qs.add(q)
        }
        if (at >= qs.size) return false
        queue.clear(); queue.addAll(qs); idx = at; chosen = null; right = PracticeSave.int(s["right"]); wrong = PracticeSave.int(s["wrong"])
        resumed = true
        return true
    }
    fun start() {
        val words = Store.practiceCards.shuffled().toMutableList()
        val seen = words.map { it.k }.toSet()
        words.addAll(Store.cards.take(1500).filter { !seen.contains(it.k) }.shuffled())
        val qs = ArrayList<ToneQuestion>()
        for (c in words) { toneQuestion(c, rom)?.let { qs.add(it) }; if (qs.size == 15) break }
        queue.clear(); queue.addAll(qs); idx = 0; chosen = null; right = 0; wrong = 0
        saveNow()
    }
    LaunchedEffect(Unit) { if (queue.isEmpty() && !restore()) start() }
    LaunchedEffect(idx) { if (queue.isNotEmpty()) saveNow() }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("聲調練習"), { close() }, close = true, settings = false) {
            if (idx > 0 && idx < queue.size) IconButton(onClick = { start() }) { Icon(Icons.Filled.Refresh, tr("重新開始"), tint = T.glyph) }
        }
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) { ResumedNote(resumed) { resumed = false } }
        Box(Modifier.fillMaxSize()) {
            if (queue.isEmpty()) CircularProgressIndicator(Modifier.align(Alignment.Center), color = T.greenInk)
            else if (idx >= queue.size) Summary(tr("答對 {0} 題，答錯 {1} 題", right, wrong), emptyList(), onAgain = { start() })
            else {
                val q = queue[idx]
                LaunchedEffect(q.id) { q.card.audio?.let { Player.play(it) } }
                Column(Modifier.fillMaxSize().widthIn(max = 640.dp).align(Alignment.TopCenter).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Row { Txt("${idx + 1} / ${queue.size}", ff(FF.Footnote), T.muted, Modifier.weight(1f)); Txt(tr("答對 {0}", right), ff(FF.Footnote), T.greenInk) }
                    Panel {
                        QLabel(tr("聽發音，選出正確的拼法"))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Txt(q.card.h, sz(56f, FontWeight.Medium), T.blueInk, Modifier.weight(1f), maxLines = 1)
                            q.card.audio?.let { PlayButton(it, 60.dp) }
                        }
                        if (if (q.card.isZh) (q.card.zs?.size ?: 1) > 1 else q.card.syllables > 1)
                            Txt(if (q.card.isZh) tr("只有最後一個字的聲調不一樣") else tr("只有最後一個字的聲調不一樣（前面的字唸起來會變調）"), ff(FF.Caption), T.muted)
                    }
                    for (o in q.options) {
                        val answered = chosen != null; val isRight = o === q.answer; val isPicked = chosen === o
                        Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).clip(RoundedCornerShape(18.dp))
                            .background(if (answered && isRight) T.green else if (answered && isPicked) T.rust else T.key)
                            .border(2.dp, if (answered && isRight) T.greenEdge else if (answered && isPicked) T.rustEdge else T.keyEdge, RoundedCornerShape(18.dp))
                            .clickable(enabled = !answered) {
                                chosen = o
                                if (o === q.answer) right++ else { wrong++; toneQuestion(q.card, rom)?.let { queue.add(it) } }
                                saveNow(true)
                            }.padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Txt(o.rom[rom.coerceIn(0, 2)], lat(28f), T.greenInk, Modifier.weight(1f))
                            if (answered) Txt(if (Store.isZh) (if (o.tone == 0) tr("輕聲") else tr("第 {0} 聲　{1}", o.tone, ZH_TONE_NAMES[o.tone] ?: "")) else "${o.tone}　${TONE_NAMES[o.tone] ?: ""}", ff(FF.Subheadline, FontWeight.Bold),
                                if (isRight) T.greenInk else if (isPicked) T.rustInk else T.muted)
                        }
                    }
                    chosen?.let { ch ->
                        val ok = ch === q.answer; val t = q.answer.tone
                        Panel {
                            Txt(if (ok) tr("答對了！") else tr("答錯了"), ff(FF.Headline), if (ok) T.greenInk else T.rustInk)
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                Txt(q.card.h, ff(FF.Title2, FontWeight.Medium), T.blueInk)
                                Txt(q.answer.rom[rom.coerceIn(0, 2)], lat(22f), T.greenInk)
                                Txt(q.card.z, ff(FF.Body), T.purpleInk)
                            }
                            Txt(if (Store.isZh) (if (t == 0) tr("輕聲") else tr("第 {0} 聲（{1}）", t, ZH_TONE_NAMES[t] ?: "")) else tr("第 {0} 聲（{1}）{2}", t, TONE_NAMES[t] ?: "", hint(t, rom)), ff(FF.Subheadline), T.glyph)
                            Txt(q.card.firstMeaning, ff(FF.Footnote), T.muted)
                        }
                        ProminentButton(onClick = { chosen = null; idx++ }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                            Text(if (idx + 1 >= queue.size) tr("看結果") else tr("下一題"), style = ff(FF.Headline))
                        }
                    }
                    Txt(if (Store.isZh) tr("華語：第 1 聲 ā／ㄚ（注音不標）、第 2 聲 á／ˊ、第 3 聲 ǎ／ˇ、第 4 聲 à／ˋ、輕聲 a／˙。") else if (rom == 0) tr("皓羅：第 1 聲和第 8 聲記號一樣，第 3 聲和第 4 聲記號一樣；第 4、8 聲結尾有 p／t／k／h。")
                        else tr("台羅／白話字：第 1 聲和第 4 聲都沒有記號；第 4、8 聲結尾有 p／t／k／h。"), ff(FF.Caption), T.muted)
                }
            }
        }
    }
}

private fun hint(t: Int, rom: Int): String = if (rom == 0) when (t) {
    8 -> tr("：記號跟第 1 聲一樣，但是結尾有 p／t／k／h")
    1 -> tr("：記號跟第 8 聲一樣，但是結尾沒有 p／t／k／h")
    4 -> tr("：記號跟第 3 聲一樣，但是結尾有 p／t／k／h")
    3 -> tr("：記號跟第 4 聲一樣，但是結尾沒有 p／t／k／h")
    else -> ""
} else when (t) {
    4 -> tr("：跟第 1 聲一樣沒有記號，但是結尾有 p／t／k／h")
    1 -> tr("：跟第 4 聲一樣沒有記號，但是結尾沒有 p／t／k／h")
    8 -> tr("：結尾有 p／t／k／h")
    else -> ""
}

// MARK: - 排句子 / 看字排讀音

private class Tile(val id: Int, val han: Styled, val rom: Styled, val reading: Boolean, val start: Int, val count: Int) {
    val text: String get() = if (reading) rom.plain() else han.plain() + "|" + rom.plain()
}
private class Puzzle(val card: Card, val example: Example, val tiles: List<Tile>, val end: String)

private val punctSet = ",.!?;:\"“”‘’()（），。！？；：、…".toSet()

/** the sentence cut into its words (the romanization's words, joined by "-"), with the matching 漢字 */
private fun makePuzzle(c: Card, x: Example, rom: Int, place: Int, reading: Boolean): Puzzle? {
    // 華語: the sentence's own words (from the dictionary), each a card
    val z = Store.zh
    if (x.w != null && z != null) {
        if (x.z.isNotEmpty()) return null        // sentences quoted from old books aren't used
        val ps = ZhDict.pieces(x.h, x.w)
        val tiles = ArrayList<Tile>(); var n = 0
        for (p in ps) {
            if (p.tw == null) continue
            tiles.add(Tile(tiles.size, z.sentenceHan(listOf(p), Prefs.zhPlace.value, T.blueInk.argbInt()),
                z.sentence(listOf(p), Prefs.zhRom.value, Prefs.zhPlace.value), reading, n, p.text.size))
            n += p.text.size
        }
        if (tiles.size < 3 || tiles.size > 12) return null
        // no capital letter on the first card (it would give it away)
        val f = tiles[0].rom
        if (Prefs.zhRom.value == 0 && f.isNotEmpty() && f[0].t.isNotEmpty() && f[0].t[0].isUpperCase()) {
            tiles[0] = Tile(0, tiles[0].han, listOf(Seg(f[0].t.substring(0, 1).lowercase() + f[0].t.substring(1), f[0].c)) + f.drop(1), reading, 0, tiles[0].count)
        }
        val last = ps.lastOrNull()
        val end = if (last != null && last.tw == null) last.text.joinToString("") else ""
        return Puzzle(c, x, tiles, end)
    }
    val romA = Store.exampleRom(c, x, rom, place)
    val hanA = Store.exampleHan(c, x, place, T.glyph.argbInt())
    // romanization words, split at spaces, punctuation around them dropped
    val words = ArrayList<StyledBuilder>()
    var cur = StyledBuilder()
    for (s in romA) for (ch in s.t) {
        if (ch == ' ') { if (cur.out.isNotEmpty()) { words.add(cur); cur = StyledBuilder() } }
        else cur.add(ch.toString(), s.c)
    }
    if (cur.out.isNotEmpty()) words.add(cur)
    fun trimmed(b: StyledBuilder): Styled? {
        val segs = ArrayList(b.out)
        while (segs.isNotEmpty()) {
            val l = segs.last()
            if (l.t.isNotEmpty() && punctSet.contains(l.t.last())) { val t = l.t.dropLast(1); if (t.isEmpty()) segs.removeAt(segs.size - 1) else segs[segs.size - 1] = Seg(t, l.c) } else break
        }
        while (segs.isNotEmpty()) {
            val f = segs.first()
            if (f.t.isNotEmpty() && punctSet.contains(f.t.first())) { val t = f.t.drop(1); if (t.isEmpty()) segs.removeAt(0) else segs[0] = Seg(t, f.c) } else break
        }
        return if (segs.isEmpty()) null else segs
    }
    val ws = words.mapNotNull { trimmed(it) }.toMutableList()
    if (ws.size < 3 || ws.size > 12) return null
    val all = romA.plain()
    val end = all.lastOrNull()?.let { if (punctSet.contains(it)) it.toString() else "" } ?: ""
    // don't give away the first word by its capital letter
    val f = ws[0]
    if (f.isNotEmpty() && f[0].t.isNotEmpty() && f[0].t[0].isUpperCase()) {
        ws[0] = listOf(Seg(f[0].t.substring(0, 1).lowercase() + f[0].t.substring(1), f[0].c)) + f.drop(1)
    }
    val counts = ws.map { w -> w.plain().split("-").count { it.isNotEmpty() } }
    val hanChars = ArrayList<Seg>()
    for (s in hanA) for (ch in s.t.cps()) if (ConvertEngine.isHan(ch.firstCp())) hanChars.add(Seg(ch, s.c))
    if (counts.sum() != hanChars.size) return null
    val tiles = ArrayList<Tile>(); var n = 0
    for ((i, w) in ws.withIndex()) {
        val hb = StyledBuilder()
        for (k in n until n + counts[i]) hb.add(hanChars[k].t, hanChars[k].c)
        if (hb.out.isEmpty()) return null
        tiles.add(Tile(i, hb.build(), w, reading, n, counts[i]))
        n += counts[i]
    }
    return Puzzle(c, x, tiles, end)
}

@Composable
private fun ScrambleScreen(reading: Boolean, stars: StarField) {
    val rom = Prefs.rom.value; val place = Prefs.place.value; val toneSys = Prefs.toneSys.value
    val size = Prefs.sessionSize.value
    var puzzles by remember { mutableStateOf<List<Puzzle>?>(null) }
    var idx by remember { mutableIntStateOf(0) }
    val pool = remember { mutableStateListOf<Tile>() }
    val placed = remember { mutableStateListOf<Tile>() }
    var solved by remember { mutableIntStateOf(0) }
    var revealed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current.density
    val screenW = LocalConfiguration.current.screenWidthDp
    var resumed by remember { mutableStateOf(false) }
    val saveName = if (reading) "reading" else "scramble"
    fun saveNow() {
        val ps = puzzles ?: return
        if (idx >= ps.size) { PracticeSave.clear(saveName, Store.isZh); return }
        PracticeSave.save(saveName, Store.isZh, Store.practiceTopic, mapOf("items" to ps.map { listOf(it.card.k, it.example.h) }, "idx" to idx, "solved" to solved))
    }

    fun setUp(p: Puzzle) {
        var s = p.tiles.shuffled(); var tries = 0
        while (s.map { it.text } == p.tiles.map { it.text } && tries < 10) { s = s.shuffled(); tries++ }
        pool.clear(); pool.addAll(s); placed.clear(); revealed = false
    }
    /** the round left last time, if there is one */
    @Suppress("UNCHECKED_CAST")
    fun restore(): Boolean {
        val s = PracticeSave.load(saveName, Store.isZh, Store.practiceTopic) ?: return false
        val out = ArrayList<Puzzle>()
        for (it in (s["items"] as? List<Any?>) ?: emptyList()) {
            val pair = PracticeSave.strings(it)
            if (pair.size != 2) continue
            val c = Store.cardFor(pair[0]) ?: continue
            val x = c.d.flatMap { d -> d.x }.firstOrNull { e -> e.h == pair[1] } ?: continue
            makePuzzle(c, x, rom, place, reading)?.let { p -> out.add(p) }
        }
        val i = PracticeSave.int(s["idx"])
        if (out.isEmpty() || i >= out.size) return false
        puzzles = out; idx = i; solved = PracticeSave.int(s["solved"])
        setUp(out[i])
        resumed = true
        return true
    }
    fun build() {
        // a round left half way: carry on with it
        if (puzzles == null && restore()) return
        val out = ArrayList<Puzzle>()
        for (c in Store.practiceCards.shuffled()) {
            for (x in c.d.flatMap { it.x }.shuffled()) { val p = makePuzzle(c, x, rom, place, reading); if (p != null) { out.add(p); break } }
            if (out.size >= maxOf(1, size)) break
        }
        puzzles = out; idx = 0; solved = 0
        out.firstOrNull()?.let { setUp(it) }
        saveNow()
    }
    LaunchedEffect(idx) { saveNow() }
    val dict = Store.dict
    LaunchedEffect(dict) {
        if (dict == null) Store.loadDict()
        // local readings and tone colours need the dictionary: wait for it
        if (puzzles == null && (Store.isZh || !((place >= 0 || toneSys != 0) && dict == null))) build()
    }
    val ps = puzzles
    Column(Modifier.fillMaxSize()) {
        TopBar(if (ps != null && idx < ps.size) tr("{0}　{1}／{2}", if (reading) tr("看字排讀音") else tr("排句子"), idx + 1, ps.size) else if (reading) tr("看字排讀音") else tr("排句子"),
            { close() }, close = true, settings = false) {
            if (ps != null && idx > 0 && idx < ps.size) IconButton(onClick = { puzzles = emptyList(); build() }) { Icon(Icons.Filled.Refresh, tr("重新開始"), tint = T.glyph) }
        }
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) { ResumedNote(resumed) { resumed = false } }
        Box(Modifier.fillMaxSize()) {
            if (ps == null) CircularProgressIndicator(Modifier.align(Alignment.Center), color = T.greenInk)
            else if (ps.isEmpty()) Txt(tr("不熟的詞裡沒有可以排的例句。"), ff(FF.Body), T.muted, Modifier.align(Alignment.Center))
            else if (idx >= ps.size) Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Icon(Icons.Filled.AutoAwesome, null, tint = Color(ToneColors.yellow), modifier = Modifier.size(44.dp))
                Txt(tr("排好了 {0}／{1} 句", solved, ps.size), ff(FF.Title2, FontWeight.Bold), T.glyph)
                ProminentButton(onClick = { puzzles = null; build() }, Modifier.widthIn(min = 220.dp)) { IconLabel(Icons.Filled.Refresh, tr("再來一輪")) }
                TextButton(onClick = { close() }) { Text(tr("結束"), color = T.muted) }
            } else {
                val p = ps[idx]
                val done = pool.isEmpty() && placed.map { it.text } == p.tiles.map { it.text }
                val closeness = run {
                    val a = placed.map { it.text }; val b = p.tiles.map { it.text }
                    if (a.isEmpty()) 0.0 else {
                        val dp = IntArray(b.size + 1)
                        for (x in a) { var prev = 0; for (j in 1..b.size) { val tmp = dp[j]; dp[j] = if (x == b[j - 1]) prev + 1 else maxOf(dp[j], dp[j - 1]); prev = tmp } }
                        dp[b.size].toDouble() / b.size
                    }
                }
                fun wrongAt(i: Int) = pool.isEmpty() && !done && placed[i].text != p.tiles[i].text
                fun put(t: Tile) {
                    pool.remove(t); placed.add(t)
                    if (pool.isEmpty() && placed.map { it.text } == p.tiles.map { it.text } && !revealed) {
                        solved++
                        scope.launch {
                            for (i in 0 until 4) {
                                stars.burst(Offset(Random.nextInt(80, maxOf(81, screenW - 40)) * density, Random.nextInt(200, 380) * density), density)
                                delay(120)
                            }
                        }
                        Player.play(Audio.examplePath(p.example.n))
                    }
                }
                Column(Modifier.fillMaxSize().widthIn(max = 760.dp).align(Alignment.TopCenter).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    if (reading) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (done) PlayButton(Audio.examplePath(p.example.n), 34.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Txt(Store.exampleHan(p.card, p.example, place, 0).plain(), sz(26f, FontWeight.SemiBold), T.blueInk)
                            if (done) Txt(p.example.z, ff(FF.Subheadline), T.muted)
                        }
                    } else Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        PlayButton(Audio.examplePath(p.example.n), 34.dp)
                        Txt(p.example.z, ff(FF.Title3), T.glyph, Modifier.weight(1f))
                    }
                    PotionBar(closeness, 22.dp, showMarks = false, label = tr("排得多接近"), palette = PotionPalette.BLUE)
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Txt(if (done) (if (revealed) tr("答案（點詞看意思）") else tr("排對了！點詞看意思")) else if (reading) tr("照上面的字，把讀音照順序排") else tr("點下面的詞，照順序排"),
                            ff(FF.Caption, FontWeight.Bold), if (done) T.greenInk else T.muted)
                        Flow(Modifier.fillMaxWidth().heightIn(min = 70.dp).clip(RoundedCornerShape(18.dp)).background(T.fn.copy(alpha = 0.6f))
                            .border(2.dp, if (done) T.greenEdge else T.fnEdge, RoundedCornerShape(18.dp)).padding(12.dp).animateContentSize(),
                            spacing = 8.dp, lineSpacing = 10.dp) {
                            for ((i, t) in placed.withIndex()) key(t.id) {
                                TileView(t, reading, wrong = wrongAt(i), right = done) {
                                    if (done) keyOf(t, p, place)?.let { if (Store.isZh) UI.open(Sheet.ZhWord(it)) else UI.openWord(it) } else { placed.remove(t); pool.add(t) }
                                }
                            }
                            if (done && p.end.isNotEmpty()) Txt(p.end, ff(FF.Title2), T.muted, Modifier.padding(top = 14.dp))
                        }
                    }
                    if (pool.isNotEmpty()) Flow(Modifier.fillMaxWidth().animateContentSize(), spacing = 8.dp, lineSpacing = 10.dp) {
                        for (t in pool.toList()) key(t.id) { TileView(t, reading, wrong = false, right = false) { put(t) } }
                    }
                    if (pool.isEmpty() && !done) Txt(tr("紅框的詞位置不對，點一下拿回來再排。"), ff(FF.Footnote), T.rustInk)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (!done) {
                            SoftButton(onClick = { val all = (pool + placed).shuffled(); pool.clear(); pool.addAll(all); placed.clear() }, Modifier.weight(1f), enabled = placed.isNotEmpty()) {
                                IconLabel(Icons.Filled.Refresh, tr("重來"), ff(FF.Subheadline))
                            }
                            SoftButton(onClick = { revealed = true; placed.clear(); placed.addAll(p.tiles); pool.clear() }, Modifier.weight(1f)) {
                                IconLabel(Icons.Filled.Visibility, tr("看答案"), ff(FF.Subheadline))
                            }
                        } else ProminentButton(onClick = { idx++; ps.getOrNull(idx)?.let { setUp(it) } }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                            IconLabel(Icons.AutoMirrored.Filled.ArrowForward, if (idx + 1 < ps.size) tr("下一句") else tr("完成"))
                        }
                    }
                    if (done) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Txt(tr("出自"), ff(FF.Footnote), T.muted); Txt(p.card.h, ff(FF.Footnote), T.blueInk)
                    }
                }
            }
        }
    }
}

@Composable
private fun TileView(t: Tile, reading: Boolean, wrong: Boolean, right: Boolean, onClick: () -> Unit) {
    Column(Modifier.shadow(3.dp, RoundedCornerShape(12.dp)).clip(RoundedCornerShape(12.dp))
        .background(if (right) T.green.copy(alpha = 0.85f) else T.key.copy(alpha = 0.85f))
        .border(if (wrong) 2.5.dp else 1.5.dp, if (wrong) T.rustEdge else if (right) T.greenEdge else T.keyEdge, RoundedCornerShape(12.dp))
        .clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        if (reading) Txt(t.rom.annotated(T.greenInk), lat(19f), T.greenInk, Modifier.padding(vertical = 4.dp))
        else {
            Txt(t.han.annotated(T.glyph), ff(FF.Title3, FontWeight.SemiBold), T.glyph)
            Txt(t.rom.annotated(T.greenInk), lat(14f), T.greenInk)
        }
    }
}

/** the dictionary word a card stands for: the word of its first 漢字 that the dictionary knows */
private fun keyOf(t: Tile, p: Puzzle, place: Int): String? {
    val w = p.example.w
    val z = Store.zh
    if (w != null && z != null) {
        // the word of the tile
        var n = 0
        for (piece in ZhDict.pieces(p.example.h, w)) {
            if (piece.tw == null) continue
            if (n == t.start) return z.entryFor(piece)?.k
            n += piece.text.size
        }
        return null
    }
    val d = Store.dict ?: return null
    val e = d.raw.ex[p.card.k]?.flatten()?.firstOrNull { it.size > 3 && it[0] == p.example.h && it[3] == p.example.n } ?: return null
    var han = e[0]; var tpl = e[1]
    if (place >= 0) { val loc = d.localizedExample(e[0], e[1], place, e.getOrNull(2)); han = loc.han; tpl = loc.tpl }
    val keys = ArrayList<String?>()
    for ((text, key) in d.exampleWords(han, tpl)) for (ch in text.cps()) if (ConvertEngine.isHan(ch.firstCp())) keys.add(key)
    if (t.start + t.count > keys.size) return null
    return keys.subList(t.start, t.start + t.count).firstNotNullOfOrNull { it }
}
