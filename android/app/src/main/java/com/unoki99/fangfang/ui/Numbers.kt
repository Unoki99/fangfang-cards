package com.unoki99.fangfang.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.tr
import java.text.Normalizer
import kotlin.random.Random

// MARK: - 台語 數字練習 (the same as the iPhone app's NumbersView.swift)
//
// Taiwanese numbers have two sets of readings: 白 (counting, amounts; 一 and 二 before a 量詞 are 一 tsi̍t and 兩 nn̄g)
// and 文 (phone numbers, ages, fixed expressions like 四季). Two games, everything in the spelling chosen (皓羅, 台羅,
// 白話字, 方音):
//  - 算數: a sum written out in spelling; type the answer in spelling (tone marks or not, spaces or not)
//  - 白還是文: a number in a setting (a 量詞, a phone number, an age, a fixed expression); pick how it's said
// Rules: 10–19 are always 十…, never 一十… (also after 百: 一百十一); a 3-digit number with no units may drop its 十
// (110 一百一, 120 一百二; 一百十, 一百二十 also right); a zero inside is 空 once (2002 兩千空二, 101 一百空一);
// 一, 二 before 百 / 千 / 萬 are 一 tsi̍t, 兩 nn̄g; above ten a 量詞 still takes 二.

/** the syllables, as 台羅 (the key to the dictionary's spellings) */
object TwNumbers {
    val bai = listOf("khòng", "it", "jī", "sann", "sì", "gōo", "la̍k", "tshit", "peh", "káu")
    val bun = listOf("khòng", "it", "jī", "sam", "sù", "ngóo", "lio̍k", "tshit", "pat", "kiú")
    const val ten = "tsa̍p"; const val tenBun = "si̍p"
    const val hundred = "pah"; const val thousand = "tshing"; const val tenThousand = "bān"
    /** 一 / 二 before a 量詞 or 百 千 萬 */
    const val tsit = "tsi̍t"; const val nng = "nn̄g"

    private fun lead(d: Int) = if (d == 1) tsit else if (d == 2) nng else bai[d]

    /** 1–99 in 白 (10–19: 十…; 20 and up: 二十…) */
    private fun underHundred(n: Int): List<String> {
        if (n < 10) return listOf(bai[n])
        val t = n / 10; val u = n % 10
        val out = if (t == 1) mutableListOf(ten) else mutableListOf(bai[t], ten)
        if (u > 0) out.add(bai[u])
        return out
    }

    /** a number 0–99 999 in 白 (counting); short: a 3-digit number with no units drops its 十 (110 一百一) */
    fun say(n: Int, short: Boolean = true): List<String> {
        if (n == 0) return listOf(bai[0])
        val out = ArrayList<String>()
        var zero = false
        val w = n / 10000; val th = (n / 1000) % 10; val h = (n / 100) % 10; val rest = n % 100
        if (w > 0) { out.addAll(if (w >= 10) underHundred(w) else listOf(lead(w))); out.add(tenThousand) }
        fun digitPlace(d: Int, unit: String, higher: Boolean) {
            if (d > 0) { if (zero) { out.add(bai[0]); zero = false }; out.add(lead(d)); out.add(unit) }
            else if (higher) zero = true
        }
        digitPlace(th, thousand, w > 0)
        digitPlace(h, hundred, out.isNotEmpty())
        if (rest > 0) {
            // (空 for the place left empty: 101 一百空一, 2202 兩千兩百空二, 2020 兩千空二十, 10 001 一萬空一)
            if (out.isNotEmpty() && (rest < 10 || h == 0)) out.add(bai[0])
            if (short && rest % 10 == 0 && rest >= 10 && out.isNotEmpty() && h > 0 && n < 1000) out.add(bai[rest / 10])
            else out.addAll(underHundred(rest))
        }
        return out
    }

    /** every way that's right for n */
    fun accepted(n: Int): List<List<String>> { val a = say(n, true); val b = say(n, false); return if (a == b) listOf(a) else listOf(a, b) }
    /** the same syllables read 文 (三 sam, 十 si̍p…) */
    fun toBun(w: List<String>): List<String> = w.map { t -> if (t == ten) tenBun else bai.indexOf(t).let { i -> if (i >= 0) bun[i] else t } }
    /** a phone number's digits in 文 */
    fun digitsBun(s: String): List<String> = s.filter { it.isDigit() }.map { bun[it - '0'] }
    /** an age (文): 1–99 */
    fun ageBun(n: Int): List<String> {
        if (n < 10) return listOf(bun[n])
        val t = n / 10; val u = n % 10
        val out = if (t == 1) mutableListOf(tenBun) else mutableListOf(bun[t], tenBun)
        if (u > 0) out.add(bun[u])
        return out
    }
}

/** the spellings of the 台語 syllables the games use, from the dictionary (台羅 → its code) */
object TwSpell {
    private var byTL: Map<String, String> = emptyMap()
    private fun norm(s: String) = Normalizer.normalize(s, Normalizer.Form.NFC).lowercase()

    /** the syllable in the spelling chosen (0 皓羅, 1 台羅, 2 白話字, 3 方音); 台羅 when the dictionary hasn't it */
    fun spell(tl: String, rom: Int): String {
        if (byTL.isEmpty()) {
            val m = HashMap<String, String>()
            for ((c, s) in Store.syl) if (s.size >= 2) m.putIfAbsent(norm(s[1]), c)
            byTL = m
        }
        val c = byTL[norm(tl)] ?: return tl
        val d = Store.dict
        if (d != null) return d.syl(c, if (rom == 3) 3 else rom.coerceIn(0, 2), -1)
        return Store.syl[c]?.getOrNull(rom.coerceIn(0, 2)) ?: tl
    }
    fun spell(tls: List<String>, rom: Int): String = tls.joinToString(" ") { spell(it, rom) }

    /** a typed answer, ready to compare: no tone marks or numbers, no spaces or dashes, ⁿ / nn as n */
    fun plain(s: String): String {
        val d = Normalizer.normalize(s, Normalizer.Form.NFKD).lowercase()
        val b = StringBuilder()
        for (ch in d) {
            val c = ch.code
            if (c in 0x0300..0x036F) continue
            if (ch in "ˉˊˇˋ˪˫˙·'ʼ- " || ch.isWhitespace() || ch.isDigit()) continue
            if (c in 0xA700..0xA71F) continue
            b.append(ch)
        }
        return b.toString().replace("nn", "n")
    }
}

/** 不熟 → 數字練習 (台語) */
@Composable
fun NumbersScreen(onClose: () -> Unit) {
    var mode by Prefs.numbersMode
    var level by Prefs.numbersLevel
    val rom = Prefs.rom.value
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("數字練習"), onClose, close = true, settings = false) { RomButton() }
        Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Segmented(listOf(0 to tr("算數"), 1 to tr("白還是文")), mode, { mode = it })
            if (mode == 0) Segmented(listOf(0 to "≤ 20", 1 to "≤ 100", 2 to "≤ 1000", 3 to "≤ 10 000"), level, { level = it })
        }
        if (mode == 0) key(level, rom) { MathGame(level, rom) } else key(rom) { BaiBunGame(rom) }
    }
}

/** a text field in the games' look */
@Composable
fun GameField(value: String, onChange: (String) -> Unit, hint: String, modifier: Modifier = Modifier, enabled: Boolean = true,
              style: TextStyle = TextStyle(fontSize = 20.sp), focus: FocusRequester? = null, onDone: () -> Unit = {}) {
    TextField(value, onChange, modifier.fillMaxWidth().then(if (focus != null) Modifier.focusRequester(focus) else Modifier), enabled = enabled,
        singleLine = true, textStyle = style.copy(color = T.glyph),
        placeholder = { Text(hint, color = T.muted, style = TextStyle(fontSize = 15.sp)) },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { onDone() }),
        shape = RoundedCornerShape(12.dp),
        colors = TextFieldDefaults.colors(focusedContainerColor = T.fn.copy(alpha = 0.85f), unfocusedContainerColor = T.fn.copy(alpha = 0.7f),
            disabledContainerColor = T.fn.copy(alpha = 0.5f), focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent, cursorColor = T.greenInk, disabledTextColor = T.glyph))
}

@Composable
private fun Score(right: Int, wrong: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Txt("✓ $right", ff(FF.Subheadline, FontWeight.SemiBold), T.blueInk)
        Txt("✗ $wrong", ff(FF.Subheadline, FontWeight.SemiBold), T.rustInk)
    }
}

private val OPS = listOf("ka" to "+", "kiám" to "−", "sîng" to "×", "tû" to "÷")

/** 算數: "sann ka gōo ＝ ?", the answer typed in spelling */
@Composable
private fun MathGame(level: Int, rom: Int) {
    var a by remember { mutableIntStateOf(0) }
    var b by remember { mutableIntStateOf(0) }
    var op by remember { mutableIntStateOf(0) }
    var typed by remember { mutableStateOf("") }
    var result by remember { mutableStateOf<Boolean?>(null) }
    var right by remember { mutableIntStateOf(0) }
    var wrong by remember { mutableIntStateOf(0) }
    val focus = remember { FocusRequester() }
    val answer = when (op) { 0 -> a + b; 1 -> a - b; 2 -> a * b; else -> if (b == 0) 0 else a / b }
    fun next() {
        typed = ""; result = null
        val top = listOf(20, 100, 1000, 10000)[level.coerceIn(0, 3)]
        op = Random.nextInt(0, if (level == 0) 2 else 4)
        when (op) {
            0 -> { a = Random.nextInt(0, top / 2 + 1); b = Random.nextInt(0, top - a + 1) }
            1 -> { a = Random.nextInt(0, top + 1); b = Random.nextInt(0, a + 1) }
            2 -> { val lim = maxOf(2, Math.sqrt(top.toDouble()).toInt()); a = Random.nextInt(1, lim + 1); b = minOf(Random.nextInt(1, maxOf(1, top / maxOf(a, 1)) + 1), lim * 2) }
            else -> { b = Random.nextInt(1, maxOf(1, minOf(12, top / 10)) + 1); a = b * Random.nextInt(0, maxOf(1, top / b) + 1) }
        }
    }
    fun check() {
        if (result != null || typed.isBlank()) return
        val mine = TwSpell.plain(typed)
        // (the chosen spelling, or 台羅; any of the right ways)
        val ok = TwNumbers.accepted(answer).any { w -> TwSpell.plain(TwSpell.spell(w, rom)) == mine || TwSpell.plain(w.joinToString("")) == mine }
        result = ok
        if (ok) right++ else wrong++
    }
    LaunchedEffect(Unit) { if (a == 0 && b == 0) next() }
    Column(Modifier.fillMaxSize().dragScrollY(rememberScrollState()).padding(16.dp).widthIn(max = 640.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Score(right, wrong)
        // the sum, all in spelling (the digits only after answering)
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.7f)).padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Txt(TwSpell.spell(TwNumbers.say(a), rom), lat(24f), T.greenInk)
            Txt(TwSpell.spell(OPS[op].first, rom), lat(20f), T.muted)
            Txt(TwSpell.spell(TwNumbers.say(b), rom), lat(24f), T.greenInk)
            Txt("＝ ?", ff(FF.Title2, FontWeight.Bold), T.glyph)
        }
        GameField(typed, { typed = it }, tr("用拼音寫答案（聲調符號可有可無）"), enabled = result == null, style = lat(20f), focus = focus) { check() }
        val r = result
        if (r != null) {
            Txt(if (r) tr("答對了！") else tr("不對。"), ff(FF.Headline), if (r) T.blueInk else T.rustInk)
            Txt("$a ${OPS[op].second} $b ＝ $answer", ff(FF.Subheadline), T.muted)
            Txt(TwSpell.spell(TwNumbers.say(answer), rom), lat(22f), T.greenInk)
            ProminentButton({ next() }, Modifier.fillMaxWidth().heightIn(min = 46.dp)) { Text(tr("下一題"), style = ff(FF.Headline)) }
        } else {
            ProminentButton({ check() }, Modifier.fillMaxWidth().heightIn(min = 46.dp), enabled = typed.isNotBlank()) { Text(tr("確認答案"), style = ff(FF.Headline)) }
        }
        Txt(tr("算數：加 ka、減 kiám、乘 sîng、除 tû。答案用上面選的拼音打，可以不打聲調、不分開音節。"), ff(FF.Caption), T.muted)
    }
}

private class BaiBunQ(val prompt: String, val why: String, val right: List<String>, val other: List<String>)

private fun makeBaiBun(): BaiBunQ {
    when (Random.nextInt(0, 4)) {
        0 -> {
            // 量詞: 一個、兩隻 (白, 一 tsi̍t / 兩 nn̄g); 十二個 (白, still 二)
            val units = listOf("個" to "ê", "隻" to "tsiah", "本" to "pún", "張" to "tiunn", "杯" to "pue")
            val u = units.random()
            val n = listOf(1, 2, 1, 2, 3, 12, 21).random()
            val said = TwNumbers.say(n)
            val right = if (n == 1) listOf(TwNumbers.tsit, u.second) else if (n == 2) listOf(TwNumbers.nng, u.second) else said + u.second
            val other = if (n <= 2) listOf(TwNumbers.bai[n], u.second)
                else if (said.contains(TwNumbers.bai[2])) said.map { if (it == TwNumbers.bai[2]) TwNumbers.nng else it } + u.second
                else TwNumbers.toBun(said) + u.second
            return BaiBunQ("$n${u.first}", if (n <= 2) tr("量詞前面：一講 tsi̍t、二講 nn̄g（白）。") else tr("數量用白的讀音；十以上，量詞前面還是講二，不講兩。"), right, other)
        }
        1 -> {
            // a phone number (文)
            val num = "09" + (0 until 8).joinToString("") { Random.nextInt(0, 10).toString() }
            val shown = num.take(4) + " " + num.drop(4).take(3) + " " + num.takeLast(3)
            return BaiBunQ(tr("電話：{0}", shown), tr("電話號碼一個數字一個數字講，用文的讀音。"),
                TwNumbers.digitsBun(num), num.map { TwNumbers.bai[it - '0'] })
        }
        2 -> {
            // an age (文)
            val n = Random.nextInt(13, 90)
            return BaiBunQ(tr("{0} 歲", n), tr("年紀用文的讀音。"), TwNumbers.ageBun(n) + "huè", TwNumbers.say(n) + "huè")
        }
        else -> {
            // counting (白)
            val n = Random.nextInt(3, 100)
            val bunForm = TwNumbers.toBun(TwNumbers.say(n))
            return BaiBunQ(tr("算數：{0}", n), tr("算數、數量用白的讀音。"), TwNumbers.say(n), if (bunForm == TwNumbers.say(n)) TwNumbers.say(n + 1) else bunForm)
        }
    }
}

/** 白還是文: a number in a setting; pick how it's said there */
@Composable
private fun BaiBunGame(rom: Int) {
    var q by remember { mutableStateOf<BaiBunQ?>(null) }
    var choices by remember { mutableStateOf<List<List<String>>>(emptyList()) }
    var picked by remember { mutableStateOf<Int?>(null) }
    var right by remember { mutableIntStateOf(0) }
    var wrong by remember { mutableIntStateOf(0) }
    fun next() { picked = null; val m = makeBaiBun(); q = m; choices = listOf(m.right, m.other).shuffled() }
    LaunchedEffect(Unit) { if (q == null) next() }
    Column(Modifier.fillMaxSize().dragScrollY(rememberScrollState()).padding(16.dp).widthIn(max = 640.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Score(right, wrong)
        val qq = q
        if (qq != null) {
            Txt(qq.prompt, ff(FF.Title2, FontWeight.SemiBold), T.glyph,
                Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.7f)).padding(14.dp))
            Txt(tr("這裡要怎麼講？"), ff(FF.Subheadline), T.muted)
            for ((i, c) in choices.withIndex()) {
                val p = picked
                val isRight = c == qq.right
                val ink = if (p == null) T.greenInk else if (isRight) T.blueInk else if (i == p) T.rustInk else T.muted
                val edge = if (p == null) T.fnEdge else if (isRight) T.blueEdge else if (i == p) T.rustEdge else T.fnEdge
                Box(Modifier.fillMaxWidth().heightIn(min = 50.dp).clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.75f))
                    .border(2.dp, edge, RoundedCornerShape(12.dp))
                    .clickable(enabled = p == null) { picked = i; if (isRight) right++ else wrong++ }.padding(horizontal = 14.dp, vertical = 12.dp)) {
                    Txt(TwSpell.spell(c, rom), lat(20f), ink)
                }
            }
            if (picked != null) {
                Txt(qq.why, ff(FF.Subheadline), T.muted)
                ProminentButton({ next() }, Modifier.fillMaxWidth().heightIn(min = 46.dp)) { Text(tr("下一題"), style = ff(FF.Headline)) }
            }
        }
        Txt(tr("白：算數、數量；一、二在量詞和百、千、萬前面講「一 tsi̍t」「兩 nn̄g」（十以上還是講二）。文：電話號碼、年紀、固定的講法（四季）。"), ff(FF.Caption), T.muted)
    }
}
