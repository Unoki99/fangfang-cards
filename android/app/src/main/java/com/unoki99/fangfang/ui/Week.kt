package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
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
import com.unoki99.fangfang.Prefs

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
            Txt(tr("本週學習"), ff(FF.Headline), T.glyph, Modifier.weight(1f))
            if (words.isNotEmpty()) Txt(if (left == 0) tr("該考試了！") else tr("還有 {0} 天", left), ff(FF.Subheadline, FontWeight.SemiBold), if (left == 0) T.rustInk else T.muted)
        }
        if (words.isEmpty()) {
            Txt(tr("從「不熟」選這個星期要學的詞（例如 10–20 個），每天練習，一週後做期末測驗。"), ff(FF.Footnote), T.muted)
        } else {
            val known = words.count { Store.status(it) == 1 }
            Txt(tr("{0} 個詞・已經學會 {1} 個", words.size, known), ff(FF.Footnote), T.muted)
            // the week: how many of its 7 days have gone
            PotionBar((7 - left) / 7.0, 16.dp, showMarks = false, label = tr("這一週"), palette = PotionPalette.BLUE)
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
            PracticeTile(if (words.isEmpty()) tr("選詞") else tr("改詞"), Icons.Filled.Checklist, true, Modifier.weight(1f).fillMaxHeight()) { picking = true }
            PracticeTile(tr("練習"), Icons.Filled.School, words.isNotEmpty(), Modifier.weight(1f).fillMaxHeight()) { UI.practice = Practice.WEEK }
            PracticeTile(tr("寫字"), Icons.Filled.Draw, words.any { Store.canWrite(it.h) }, Modifier.weight(1f).fillMaxHeight()) { UI.practice = Practice.WEEK_WRITE }
            PracticeTile(tr("期末測驗"), Icons.Filled.WorkspacePremium, words.isNotEmpty(), Modifier.weight(1f).fillMaxHeight()) { UI.practice = Practice.WEEK_TEST }
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
    /** the level / group to pick from (-1 = all of 不熟), so the week can follow the levels in order */
    var topic by Prefs.weekPickTopic
    val topics = Store.practiceTopics.filter { t -> Store.unknownCards.any { Store.inTopic(it, t.id) } }
    val unknown = if (topic < 0 || topics.none { it.id == topic }) Store.unknownCards else Store.unknownCards.filter { Store.inTopic(it, topic) }
    // words already in the week that aren't in 不熟 any more (learned) are shown too
    val extra = Store.weekCards.filter { Store.status(it) != 2 }
    val list = (extra + unknown).filter { query.isEmpty() || it.h.contains(query) || it.firstMeaning.contains(query) }
    val n = Store.weekCards.size
    ModalBottomSheet(onDismissRequest = onDone, containerColor = T.bg, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Txt(tr("本週要學的詞"), ff(FF.Headline), T.glyph, Modifier.weight(1f))
                TextButton(onClick = onDone) { Text(tr("完成"), color = T.btnInk) }
            }
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
                item {
                    if (topics.isNotEmpty()) {
                        ListCard {
                            MenuRow(tr("從哪裡選"), if (topics.any { it.id == topic }) topics.first { it.id == topic }.name else tr("全部不熟的詞"),
                                listOf(-1 to tr("全部不熟的詞")) + topics.map { it.id to it.name }) { topic = it }
                        }
                        Txt(tr("選一個等級或一組詞，照順序一級一級學。"), ff(FF.Footnote), T.muted, Modifier.padding(6.dp))
                    }
                    SearchField(query, { query = it }, tr("漢字或意思"))
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        for (k in listOf(10, 20)) SoftButton(onClick = {
                            val pick = unknown.filter { !Store.isInWeek(it.k) }.shuffled().take(maxOf(0, k - n)).map { it.k }
                            Store.setWeek(pick, true)
                        }) { Text(tr("隨機選 {0} 個", k)) }
                        Spacer(Modifier.weight(1f))
                        if (n > 0) SoftButton(onClick = { Store.setWeek(Store.weekCards.map { it.k }, false) }) { Text(tr("全部取消"), color = T.rustInk) }
                    }
                    Txt(tr("已選 {0} 個。建議一週 10–20 個詞。", n), ff(FF.Footnote), T.muted, Modifier.padding(6.dp))
                    SectionTitle(tr("不熟的詞（{0}）", unknown.size))
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
