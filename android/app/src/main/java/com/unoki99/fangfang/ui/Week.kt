package com.unoki99.fangfang.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Store

// MARK: - 本週學習: pick words from 不熟 for the week, practise them, and take a test at the end

/** the panel at the top of 不熟 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WeekPanel() {
    Store.rev
    var picking by remember { mutableStateOf(false) }
    val words = Store.weekCards
    val left = Store.weekDaysLeft
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(T.fn.copy(alpha = 0.55f))
        .border(1.5.dp, if (words.isEmpty() || left > 0) T.fnEdge else T.rustEdge, RoundedCornerShape(16.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.CalendarMonth, null, tint = T.glyph, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(8.dp))
            Txt("本週學習", ff(FF.Headline), T.glyph, Modifier.weight(1f))
            if (words.isNotEmpty()) Txt(if (left == 0) "該考試了！" else "還有 $left 天", ff(FF.Subheadline, FontWeight.SemiBold), if (left == 0) T.rustInk else T.muted)
        }
        if (words.isEmpty()) {
            Txt("從「不熟」選這個星期要學的詞（例如 10–20 個），每天練習，一週後做期末測驗。", ff(FF.Footnote), T.muted)
        } else {
            val known = words.count { Store.status(it) == 1 }
            Txt("${words.size} 個詞・已經學會 $known 個", ff(FF.Footnote), T.muted)
            // the week: how many of its 7 days have gone
            PotionBar((7 - left) / 7.0, 16.dp, showMarks = false, label = "這一週", palette = PotionPalette.BLUE)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (c in words.take(24)) {
                    val k = Store.status(c) == 1
                    Txt(c.h, ff(FF.Subheadline), if (k) T.greenInk else T.glyph,
                        Modifier.clip(CircleShape).background(if (k) T.green.copy(alpha = 0.7f) else T.fn.copy(alpha = 0.8f)).padding(horizontal = 8.dp, vertical = 3.dp))
                }
                if (words.size > 24) Txt("…", ff(FF.Subheadline), T.muted)
            }
        }
        Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PracticeTile(if (words.isEmpty()) "選詞" else "改詞", Icons.Filled.Checklist, true, Modifier.weight(1f).fillMaxHeight()) { picking = true }
            PracticeTile("練習", Icons.Filled.School, words.isNotEmpty(), Modifier.weight(1f).fillMaxHeight()) { UI.practice = Practice.WEEK }
            PracticeTile("期末測驗", Icons.Filled.WorkspacePremium, words.isNotEmpty(), Modifier.weight(1f).fillMaxHeight()) { UI.practice = Practice.WEEK_TEST }
        }
    }
    if (picking) WeekPicker { picking = false }
}

/** choosing this week's words from 不熟 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WeekPicker(onDone: () -> Unit) {
    Store.rev
    var query by remember { mutableStateOf("") }
    val unknown = Store.unknownCards
    // words already in the week that aren't in 不熟 any more (learned) are shown too
    val extra = Store.weekCards.filter { Store.status(it) != 2 }
    val list = (extra + unknown).filter { query.isEmpty() || it.h.contains(query) || it.firstMeaning.contains(query) }
    val n = Store.weekCards.size
    ModalBottomSheet(onDismissRequest = onDone, containerColor = T.bg, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Txt("本週要學的詞", ff(FF.Headline), T.glyph, Modifier.weight(1f))
                TextButton(onClick = onDone) { Text("完成", color = T.btnInk) }
            }
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
                item {
                    SearchField(query, { query = it }, "漢字或意思")
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        for (k in listOf(10, 20)) SoftButton(onClick = {
                            val pick = unknown.filter { !Store.isInWeek(it.k) }.shuffled().take(maxOf(0, k - n)).map { it.k }
                            Store.setWeek(pick, true)
                        }) { Text("隨機選 $k 個") }
                        Spacer(Modifier.weight(1f))
                        if (n > 0) SoftButton(onClick = { Store.setWeek(Store.weekCards.map { it.k }, false) }) { Text("全部取消", color = T.rustInk) }
                    }
                    Txt("已選 $n 個。建議一週 10–20 個詞。", ff(FF.Footnote), T.muted, Modifier.padding(6.dp))
                    SectionTitle("不熟的詞（${unknown.size}）")
                }
                items(list, key = { "w|" + it.k }) { c ->
                    val on = Store.isInWeek(c.k)
                    Row(Modifier.fillMaxWidth().background(T.fn.copy(alpha = 0.7f)).clickable { Store.toggleWeek(c.k) }.padding(start = 12.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (on) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (on) T.greenInk else T.muted)
                        Box(Modifier.weight(1f)) { WordRow(c) }
                    }
                    RowDivider()
                }
            }
        }
    }
}
