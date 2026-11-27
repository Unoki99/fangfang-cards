package com.unoki99.fangfang.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.UILang
import com.unoki99.fangfang.tr
import kotlin.random.Random

// MARK: - 認識的漢字 → 猜字義 (the same as the iPhone app's CharMeaningGame): a character, four meanings, pick its own.
// Just for fun: it never changes whether a character is 熟悉 or 不熟; the common characters come more often.

@Composable
fun CharMeaningScreen(onClose: () -> Unit) {
    val z = Store.zh
    var ch by remember { mutableStateOf("") }
    var options by remember { mutableStateOf<List<String>>(emptyList()) }
    var answer by remember { mutableIntStateOf(0) }
    var picked by remember { mutableStateOf<Int?>(null) }
    var right by remember { mutableIntStateOf(0) }
    var wrong by remember { mutableIntStateOf(0) }
    /** a character's meaning, short: English when the app is in English and there is one, else Chinese */
    fun meaning(c: String): String? {
        val d = z ?: return null
        if (UILang.english) d.entryForChar(c, "")?.enList?.firstOrNull()?.let { return it }
        val i = d.charIndex[c] ?: return null
        val t0 = d.chars[i].readings.firstOrNull()?.defs?.firstOrNull()?.second ?: return null
        var t = t0.substringBefore("。")
        if (t.length > 40) t = t.take(39) + "…"
        return t.ifEmpty { null }
    }
    // (the characters, the most common first: the order of the list)
    val pool = remember { Store.zhCharSets().all.filter { z?.charIndex?.get(it) != null && meaning(it) != null } }
    fun pickChar(): String? {
        if (pool.isEmpty()) return null
        val ws = pool.indices.map { 1.0 / (it + 40) }
        var r = Random.nextDouble(ws.sum())
        for ((i, w) in ws.withIndex()) { r -= w; if (r <= 0) return pool[i] }
        return pool.last()
    }
    fun next() {
        picked = null
        val c = pickChar() ?: return
        val m = meaning(c) ?: return
        ch = c
        val opts = mutableListOf(m)
        var tries = 0
        while (opts.size < 4 && tries < 60) { tries++; val o = pool.random(); if (o != c) meaning(o)?.let { if (it !in opts) opts.add(it) } }
        opts.shuffle()
        options = opts
        answer = opts.indexOf(m).coerceAtLeast(0)
    }
    LaunchedEffect(Unit) { if (ch.isEmpty()) next() }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("猜字義"), onClose, close = true, settings = false)
        Column(Modifier.fillMaxSize().dragScrollY(rememberScrollState()).padding(16.dp).widthIn(max = 620.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Txt("✓ $right", ff(FF.Subheadline, FontWeight.SemiBold), T.blueInk)
                Txt("✗ $wrong", ff(FF.Subheadline, FontWeight.SemiBold), T.rustInk)
            }
            Box(Modifier.fillMaxWidth().heightIn(min = 140.dp).clip(RoundedCornerShape(18.dp)).background(T.fn.copy(alpha = 0.7f)), contentAlignment = Alignment.Center) {
                Txt(ch, sz(96f, FontWeight.SemiBold), T.glyph)
            }
            for ((i, o) in options.withIndex()) {
                val p = picked
                val ink = if (p == null) T.glyph else if (i == answer) T.blueInk else if (i == p) T.rustInk else T.muted
                val edge = if (p == null) T.fnEdge else if (i == answer) T.blueEdge else if (i == p) T.rustEdge else T.fnEdge
                Box(Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.75f))
                    .border(2.dp, edge, RoundedCornerShape(12.dp)).clickable(enabled = p == null) { picked = i; if (i == answer) right++ else wrong++ }
                    .padding(horizontal = 14.dp, vertical = 10.dp), contentAlignment = Alignment.CenterStart) {
                    Txt(o, ff(FF.Body), ink)
                }
            }
            if (picked != null) {
                val d = z
                val r = d?.charIndex?.get(ch)?.let { d.chars[it].readings.firstOrNull() }
                if (d != null && r != null) Txt(d.reading(listOf(r.zy), Prefs.zhRom.value).plain(), lat(20f), T.greenInk)
                ProminentButton({ next() }, Modifier.fillMaxWidth().heightIn(min = 46.dp)) { Text(tr("下一題"), style = ff(FF.Headline)) }
            }
            Txt(tr("好玩的：答對答錯都不會改字是熟悉還是不熟。常用的字出現得比較多。"), ff(FF.Caption), T.muted)
        }
    }
}
