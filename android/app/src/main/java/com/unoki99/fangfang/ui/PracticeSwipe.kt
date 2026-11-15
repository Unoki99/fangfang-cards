package com.unoki99.fangfang.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.Card
import com.unoki99.fangfang.tr

// 滑卡練習: the 新詞 cards, but for practising the 練習範圍's words (and the ones due to be reviewed).
// A swipe doesn't put a word in 熟悉 straight away: right (會) counts as a right answer, left (不會) as a wrong one,
// the same as in the other ways of practising. So a word goes to 熟悉 after enough right answers in a row
// (設定 → 答對幾次算學會), and comes back to be reviewed a few days later.

@Composable
fun PracticeSwipeScreen(onClose: () -> Unit) {
    val goal = Prefs.goal.value
    val queue = remember { mutableStateListOf<Card>() }
    var total by remember { mutableIntStateOf(0) }
    var right by remember { mutableIntStateOf(0) }
    var wrong by remember { mutableIntStateOf(0) }
    var learned by remember { mutableIntStateOf(0) }
    val again = remember { HashSet<String>() }
    var started by remember { mutableStateOf(false) }
    fun build() {
        queue.clear(); queue.addAll(Store.studyCards.distinctBy { it.k })
        total = queue.size; right = 0; wrong = 0; learned = 0; again.clear(); started = true
    }
    LaunchedEffect(Unit) { if (!started) build() }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("滑卡練習"), onClose, close = true, settings = false, extra = {
            if (started && total > 0) Txt(tr("會 {0}・不會 {1}", right, wrong), ff(FF.Caption), T.muted)
        })
        when {
            !started -> {}
            total == 0 -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Txt(tr("練習範圍裡沒有要練習的詞。"), ff(FF.Body), T.muted, Modifier.padding(16.dp))
            }
            queue.isEmpty() -> Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)) {
                Icon(Icons.Filled.Verified, null, tint = T.greenInk, modifier = Modifier.size(54.dp))
                Txt(tr("這一輪練完了"), ff(FF.Title2, FontWeight.Bold), T.glyph)
                Txt(tr("會 {0}・不會 {1}", right, wrong), ff(FF.Body), T.muted)
                if (learned > 0) Txt(tr("{0} 個詞學會了，放到「熟悉」，過幾天會再出來複習。", learned), ff(FF.Subheadline), T.greenInk)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    SoftButton(onClick = { build() }, Modifier.widthIn(min = 130.dp).heightIn(min = 44.dp)) { IconLabel(Icons.Filled.Refresh, tr("再來一輪"), ff(FF.Subheadline)) }
                    SoftButton(onClick = onClose, Modifier.widthIn(min = 130.dp).heightIn(min = 44.dp)) { Txt(tr("結束"), ff(FF.Subheadline), T.glyph) }
                }
            }
            else -> Column(Modifier.fillMaxSize().widthIn(max = 560.dp).padding(16.dp).align(Alignment.CenterHorizontally),
                horizontalAlignment = Alignment.CenterHorizontally) {
                Txt(tr("{0}・還有 {1} 個", Store.practiceName, queue.size), ff(FF.Footnote), T.muted)
                Spacer(Modifier.height(12.dp))
                DeckArea(queue.take(4), leftLabel = tr("不會"), rightLabel = tr("會"), onSwipe = { c, ok ->
                    if (Store.answer(c, ok, goal) && ok) learned++
                    if (ok) right++ else wrong++
                    val i = queue.indexOfFirst { it.k == c.k }
                    if (i >= 0) queue.removeAt(i)
                    // (wrong: once more at the end of the round)
                    if (!ok && again.add(c.k)) queue.add(c)
                })
            }
        }
    }
}
