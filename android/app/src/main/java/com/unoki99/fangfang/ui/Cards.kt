package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.compose.animation.core.Animatable
import kotlin.math.max
import androidx.compose.foundation.Canvas
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.VectorConverter
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.unoki99.fangfang.Player
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.*
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

// MARK: - 新詞

@Composable
fun NewDeckTab() {
    Store.rev
    val zh = Store.isZh
    val topicPref = if (zh) Prefs.zhTopic else Prefs.topic
    var topic by topicPref
    var menu by remember { mutableStateOf(false) }
    val queue = Store.newQueue(4, topic)
    LaunchedEffect(queue.firstOrNull()?.k) {
        if (Prefs.autoPlay.value) queue.firstOrNull()?.audio?.let { Player.play(it) }
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("新詞"), extra = {
            Box {
                TextButton(onClick = { menu = true }) {
                    Icon(Icons.Filled.Layers, null, tint = T.btnInk, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(4.dp))
                    Text((Store.topics + Store.freqTopics).firstOrNull { it.id == topic }?.name?.take(if (zh) 12 else 10)
                        ?: (if (zh) Lang.listNames[Prefs.zhList.value.coerceIn(0, 1)] + "・" + tr("全部") else tr("全部")),
                        color = T.btnInk, style = ff(FF.Subheadline, FontWeight.SemiBold))
                }
                DropdownMenu(menu, { menu = false }, containerColor = T.fn) {
                    if (zh) {
                        Txt(tr("詞表"), ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
                        Lang.listNames.forEachIndexed { i, n ->
                            DropdownMenuItem(text = { Text(n, color = if (Prefs.zhList.value == i) T.greenInk else T.glyph) },
                                onClick = { Store.setZhList(i); menu = false })
                        }
                        HorizontalDivider(color = T.fnEdge)
                        Txt(tr("等級"), ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
                    }
                    DropdownMenuItem(text = { Text(if (zh) tr("全部（從第一級開始）") else tr("全部（最常用的先）"), color = if (topic < 0) T.greenInk else T.glyph) }, onClick = { topic = -1; menu = false })
                    for (t in Store.topics) {
                        if (zh && t.id == Store.topics.firstOrNull { it.id > Lang.charTopicBase }?.id) {
                            HorizontalDivider(color = T.fnEdge)
                            Txt(tr("漢字"), ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
                        }
                        DropdownMenuItem(text = { Text(tr("{0}（{1}）", t.name, t.count), color = if (topic == t.id) T.greenInk else T.glyph) },
                            onClick = { topic = t.id; menu = false })
                    }
                    // 台語: the most common words / characters, 500 at a time
                    if (!zh) for (t in Store.freqTopics) {
                        if (t.id == Lang.freqWordBase || t.id == Lang.freqCharBase) {
                            HorizontalDivider(color = T.fnEdge)
                            Txt(if (t.id == Lang.freqWordBase) tr("常用詞（每組 {0} 個）", Lang.freqSize) else tr("常用字（每組 {0} 個）", Lang.freqSize),
                                ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
                        }
                        DropdownMenuItem(text = { Text(t.name, color = if (topic == t.id) T.greenInk else T.glyph) }, onClick = { topic = t.id; menu = false })
                    }
                }
            }
        })
        BoxWithConstraints(Modifier.fillMaxSize()) {
            // a tablet, or a phone on its side (華語): the word's characters as small cards beside the big one
            val landscape = maxWidth > maxHeight
            val sides = queue.isNotEmpty() && (maxWidth >= 1100.dp || (landscape && maxWidth >= 560.dp))
            val sideW = if (maxWidth >= 1100.dp) 290.dp else ((maxWidth - 32.dp - 32.dp) * 0.27f)
            val small = maxHeight < 520.dp
            // a phone on its side: no counts, no buttons, no tab bar; just the cards
            val sideways = landscape && maxHeight < 520.dp
            var sideButtons by Prefs.sidewaysButtons
            SideEffect { UI.hideTabs = sideways }
            Row(Modifier.fillMaxSize().widthIn(max = if (sides) 1260.dp else 560.dp).align(Alignment.TopCenter).padding(if (small) 10.dp else 16.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                if (sides) CharSideColumn(queue.first(), 0, small, Modifier.width(sideW).fillMaxHeight())
                // (zIndex: the big card goes over the side cards when it's swiped)
                Column(Modifier.weight(1f).fillMaxHeight().zIndex(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    if (!sideways) {
                        Txt(tr("已看 {0} / {1}　熟悉 {2}　不熟 {3}", Store.seenCount, Store.cards.size, Store.knownCount, Store.unknownCount), ff(FF.Footnote), T.muted)
                        Spacer(Modifier.height(if (small) 6.dp else 12.dp))
                    }
                    if (queue.isEmpty()) {
                        Spacer(Modifier.weight(1f))
                        Txt(if (topic < 0) tr("全部的詞都看過了！") else if (zh) tr("這個等級的詞都看過了！") else tr("這個主題的詞都看過了！"), ff(FF.Title3), T.muted)
                        Spacer(Modifier.weight(1f))
                    } else Box(Modifier.weight(1f).fillMaxWidth()) {
                        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
                            DeckArea(queue, onSwipe = { c, right -> Store.mark(c, right) }, undo = { Store.undo() }, buttons = !sideways || sideButtons)
                        }
                        // a phone on its side: a small button to bring the ✕ ↺ ✓ buttons out, or put them away
                        if (sideways) Box(Modifier.align(Alignment.BottomEnd).offset(x = 14.dp).size(32.dp).clip(CircleShape)
                            .background(T.bg.copy(alpha = 0.35f)).border(1.dp, T.fnEdge.copy(alpha = 0.6f), CircleShape)
                            .clickable { sideButtons = !sideButtons }, contentAlignment = Alignment.Center) {
                            Icon(if (sideButtons) Icons.Filled.KeyboardArrowDown else Icons.Filled.KeyboardArrowUp,
                                if (sideButtons) tr("收起按鈕") else tr("顯示按鈕"), tint = T.muted, modifier = Modifier.size(20.dp))
                        }
                    }
                }
                if (sides) CharSideColumn(queue.first(), 1, small, Modifier.width(sideW).fillMaxHeight())
            }
        }
    }
}

/** a stack plus its buttons */
@Composable
fun ColumnScope.DeckArea(cards: List<Card>, leftLabel: String = tr("不熟"), rightLabel: String = tr("認識"),
                         onSwipe: (Card, Boolean) -> Unit, undo: (() -> Unit)? = null, buttons: Boolean = true) {
    val scope = rememberCoroutineScope()
    val offset = remember { Animatable(Offset.Zero, Offset.VectorConverter) }
    val dens = LocalDensity.current.density
    var flying by remember { mutableStateOf(false) }
    // the top card drawn into a picture when it's swiped: it falls apart into little squares
    val picture = rememberGraphicsLayer()
    val bursts = remember { mutableStateListOf<CardBurst>() }
    var boxSize by remember { mutableStateOf(IntSize.Zero) }
    fun fly(c: Card, right: Boolean) {
        if (flying) return
        flying = true
        scope.launch {
            val at = offset.value
            val img = try { picture.toImageBitmap() } catch (_: Exception) { null }
            val b = CardBurst.make(c, img, boxSize, right, at, at.x / 18f / dens, dens)
            if (b != null) bursts.add(b)
            onSwipe(c, right)
            offset.snapTo(Offset.Zero)
            flying = false
            if (b == null) return@launch
            kotlinx.coroutines.delay((CardBurst.LIFE * 1000).toLong() + 100)
            bursts.remove(b)
        }
    }
    Box(Modifier.weight(1f).fillMaxWidth().heightIn(max = 680.dp).onSizeChanged { boxSize = it }) {
        val shown = cards.take(3)
        for (i in shown.indices.reversed()) {
            val card = shown[i]
            key(card.k) {
                val top = i == 0
                // (the next card moves up into place)
                val place by animateFloatAsState(i.toFloat(), spring(dampingRatio = 0.8f, stiffness = 500f), label = "stack")
                Box(Modifier.fillMaxSize().zIndex((10 - i).toFloat())
                    .graphicsLayer {
                        val s = 1f - place * 0.04f
                        scaleX = s; scaleY = s
                        translationY = place * 14 * density + if (top) offset.value.y else 0f
                        translationX = if (top) offset.value.x else 0f
                        rotationZ = if (top) offset.value.x / 18f / density else 0f
                    }
                    .then(if (top) Modifier.pointerInput(card.k) {
                        detectDragGestures(
                            onDragEnd = {
                                val w = offset.value.x / density
                                if (abs(w) > 120) fly(card, w > 0) else scope.launch { offset.animateTo(Offset.Zero, androidx.compose.animation.core.spring(0.7f, 400f)) }
                            },
                            onDragCancel = { scope.launch { offset.animateTo(Offset.Zero) } },
                        ) { change, drag ->
                            change.consume()
                            scope.launch { offset.snapTo(offset.value + drag) }
                        }
                    } else Modifier)
                ) {
                    Box(if (top) Modifier.drawWithContent {
                        picture.record { this@drawWithContent.drawContent() }
                        drawLayer(picture)
                    } else Modifier) { WordCard(card, top) }
                    if (top) {
                        val sw = (offset.value.x / dens / 140f).coerceIn(-1f, 1f)
                        CardLight(sw)
                        Stamp(offset.value.x / dens, leftLabel, rightLabel)
                    }
                }
            }
        }
        if (bursts.isNotEmpty()) CardDust(bursts, Modifier.matchParentSize().zIndex(20f))
    }
    if (buttons) Spacer(Modifier.height(18.dp))
    if (buttons) cards.firstOrNull()?.let { top ->
        SwipeButtons(leftLabel, rightLabel, Store.canUndo, { fly(top, false) }, { fly(top, true) }, undo)
    }
}

@Composable
private fun BoxScope.Stamp(dx: Float, leftLabel: String, rightLabel: String) {
    val right = dx > 0
    val amount = (abs(dx) / 110f).coerceIn(0f, 1f)
    if (amount < 0.02f) return
    Text(if (right) rightLabel else leftLabel, style = ff(FF.Title, FontWeight.ExtraBold), color = if (right) T.blueInk else T.rustInk,
        modifier = Modifier.align(Alignment.TopCenter).padding(top = 24.dp).graphicsLayer { alpha = amount; rotationZ = if (right) -10f else 10f }
            .background((if (right) T.blue else T.rust).copy(alpha = 0.9f), RoundedCornerShape(12.dp))
            .border(3.dp, if (right) T.blueEdge else T.rustEdge, RoundedCornerShape(12.dp)).padding(horizontal = 16.dp, vertical = 6.dp))
}

/** blue / rust glow from the side you swipe toward */
@Composable
private fun BoxScope.CardLight(swipe: Float) {
    val a = abs(swipe)
    if (a < 0.02f) return
    val color = if (swipe > 0) T.blueEdge else T.rustEdge
    Box(Modifier.matchParentSize().clip(RoundedCornerShape(28.dp)).drawWithContent {
        drawRect(Brush.horizontalGradient(
            if (swipe > 0) listOf(Color.Transparent, color.copy(alpha = 0.55f * a)) else listOf(color.copy(alpha = 0.55f * a), Color.Transparent)))
    }.border(3.dp, color.copy(alpha = 0.9f * a), RoundedCornerShape(28.dp)))
}

@Composable
fun SwipeButtons(leftLabel: String, rightLabel: String, canUndo: Boolean, onLeft: () -> Unit, onRight: () -> Unit, onUndo: (() -> Unit)?) {
    Row(horizontalArrangement = Arrangement.spacedBy(22.dp), verticalAlignment = Alignment.CenterVertically) {
        RoundAction(Icons.Filled.Close, leftLabel, T.rust, T.rustEdge, T.rustInk, onLeft)
        if (onUndo != null) {
            Box(Modifier.size(46.dp).clip(CircleShape).background(T.fn).border(2.dp, T.fnEdge, CircleShape).clickable(enabled = canUndo, onClick = onUndo),
                contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Filled.Undo, tr("復原"), tint = if (canUndo) T.oliveInk else T.fnEdge)
            }
        }
        RoundAction(Icons.Filled.Check, rightLabel, T.blue, T.blueEdge, T.blueInk, onRight)
    }
}

@Composable
private fun RoundAction(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, fill: Color, edge: Color, ink: Color, onClick: () -> Unit) {
    Column(Modifier.size(68.dp).clip(CircleShape).background(fill).border(2.dp, edge, CircleShape).clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Icon(icon, label, tint = ink, modifier = Modifier.size(26.dp))
        Txt(label, ff(FF.Caption2, FontWeight.Bold), ink)
    }
}

/** The big swipeable card: 漢字, romanization, 方音, audio, meanings and two examples. */
@Composable
fun WordCard(card: Card, isTop: Boolean) {
    val rom = Prefs.rom.value; val place = Prefs.place.value
    val hide = Prefs.hideMeaning.value
    var revealed by remember { mutableStateOf(false) }
    val tk = textKey()
    val dict = Store.dict
    Column(Modifier.fillMaxSize().clip(RoundedCornerShape(28.dp)).background(T.fn).border(2.dp, T.keyEdge, RoundedCornerShape(28.dp))
        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { revealed = !revealed }.padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            val h = remember(card.k, tk, dict) { Store.cardHan(card, place, T.blueInk.argbInt()).annotated() }
            Txt(h, sz(if (card.h.cpCount > 3) 44f else 60f, FontWeight.Medium), T.blueInk, Modifier.weight(1f), maxLines = 1)
            CardChips(card, place)
        }
        val hideReading = Prefs.hideReading.value && !revealed
        Row(verticalAlignment = Alignment.CenterVertically) {
            // 設定 → 卡片先隱藏讀音: tap the card to see it
            if (hideReading) Txt(tr("點一下看讀音"), ff(FF.Subheadline), T.muted, Modifier.weight(1f))
            else Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Txt(remember(card.k, tk, dict) { Store.cardRom(card, rom, place).annotated() }, lat(26f), T.greenInk)
                Txt(remember(card.k, tk, dict) { Store.cardZy(card, place).annotated() }, sz(18f), T.purpleInk)
                val also = Store.alsoSaid(card, rom, place).firstOrNull()
                if (also != null) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    PlaceChip(tr("也講")); Txt(also.first, lat(15f), T.greenInk.copy(alpha = 0.85f))
                } else card.o?.firstOrNull()?.let { o ->
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Chip(o.l); Txt(o.r[rom.coerceIn(0, 2)], lat(15f), T.greenInk.copy(alpha = 0.85f))
                    }
                }
            }
            card.audio?.let { PlayButton(it, 44.dp) }
        }
        Box(Modifier.fillMaxWidth().height(2.dp).background(T.fnEdge))
        if (hide && !revealed) {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) { Txt(tr("點一下看意思"), ff(FF.Headline), T.muted) }
        } else {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                // 華語: the 詞類 (from the word lists), and the English meanings if they're the main ones
                val ze = if (card.isZh && Lang.charOf(card.k) == null) Store.zh?.entry(card.k) else null
                if (ze != null && ze.pos.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { for (p in ze.pos) Chip(p) }
                val ens = if (ze != null && Prefs.zhEnglish.value && ze.enList.isNotEmpty()) ze.enList else null
                val exs = card.cardExamples.take(if (ens == null) 2 else 1)
                if (ens != null) EnglishList(ens, max = 5, maxLines = 1, style = ff(FF.Body))
                else {
                    for ((i, d) in card.d.take(3).withIndex()) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NumBadge(i + 1)
                        if (d.p.isNotEmpty()) Chip(d.p)
                        Txt(d.t, ff(FF.Body), T.glyph, maxLines = if (exs.size > 1) 2 else 3)
                    }
                    if (card.d.size > 3) Txt(tr("還有 {0} 個意思", card.d.size - 3), ff(FF.Caption), T.muted)
                }
                for ((n, x) in exs) Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        PlayButton(Audio.examplePath(x.n), 28.dp)
                        if (card.d.size > 1) NumBadge(n)
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Txt(remember(card.k, x.n, tk, dict) { Store.exampleHan(card, x, place, T.blueInk.argbInt()).annotated() }, ff(FF.Body), T.blueInk, maxLines = 2)
                        if (!hideReading) Txt(remember(card.k, x.n, tk, dict) { Store.exampleRom(card, x, rom, place).annotated() }, lat(15f), T.greenInk, maxLines = 2)
                        Txt(x.z, ff(FF.Footnote), T.muted, maxLines = 2)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            Row(Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.08f)).border(1.dp, Color.White.copy(alpha = 0.25f), CircleShape)
                .clickable { UI.open(Sheet.CardSheet(card)) }.padding(horizontal = 12.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.MenuBook, null, tint = T.greenInk, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(5.dp))
                Txt(tr("詳細"), ff(FF.Footnote, FontWeight.SemiBold), T.greenInk)
            }
        }
    }
}

/** 白/文/俗, 替, 臺華共同, and the place when its reading is shown */
@Composable
fun CardChips(card: Card, place: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        RegChip(card.g)
        if (card.s == 1) Chip(tr("替"), T.rust, T.rustEdge, T.rustInk)
        card.t?.let { Chip(it, T.fn, T.fnEdge, T.muted) }
        if (Store.cardDiffers(card, place) && place < Store.places.size && place >= 0) {
            PlaceChip(Store.places[place].take(2))
            if (Store.isGuessed(card, place)) Chip(tr("推測"), T.fn, T.fnEdge, T.muted)
        }
    }
}

/** 詳細 / a word from the lists: the dictionary entry (the card's own details until the dictionary has loaded) */
@Composable
fun CardSheetRoot(card: Card) {
    if (card.isZh) {
        // a character card: the dictionary entry of the character read that way (with its 《重編國語辭典修訂本》 meanings)
        val ch = Lang.charOf(card.k)
        ZhGate { z ->
            val k = if (ch != null) z.entryForChar(ch, card.z)?.k else card.k
            if (k != null) ZhEntrySheetRoot(z, k) else CardDetail(card)
        }
        return
    }
    LaunchedEffect(Unit) { Store.loadDict() }
    val d = Store.dict
    if (d != null && (d.raw.defs.m[card.k] != null || d.baseKeys.contains(card.k))) EntrySheetRoot(d, card.k)
    else CardDetail(card)
}

@Composable
private fun CardDetail(card: Card) {
    val rom = Prefs.rom.value; val place = Prefs.place.value
    Store.rev
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { UI.closeSheet() }) { Text(tr("完成"), color = T.btnInk) }
            Spacer(Modifier.weight(1f)); BarButtons(settings = false)
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Panel {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Txt(card.h, sz(44f, FontWeight.Medium), T.blueInk, Modifier.weight(1f))
                    CardChips(card, place)
                    card.audio?.let { PlayButton(it, 40.dp) }
                }
                Txt(Store.cardRom(card, rom, place).annotated(), lat(24f), T.greenInk)
                Txt(Store.cardZy(card, place).annotated(), sz(17f), T.purpleInk)
                for (o in card.o ?: emptyList()) OtherRow(o.l, o.r[rom.coerceIn(0, 2)], o.z)
                Txt(when (Store.status(card)) { 1 -> tr("熟悉"); 2 -> tr("不熟（連續答對 {0} 次）", Store.streak(card)); else -> tr("還沒看過") }, ff(FF.Caption), T.muted)
            }
            for ((i, d) in card.d.withIndex()) Panel {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { NumBadge(i + 1); if (d.p.isNotEmpty()) Chip(d.p); Txt(d.t, ff(FF.Body), T.glyph) }
                for (x in d.x) Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    PlayButton(Audio.examplePath(x.n), 28.dp)
                    Column {
                        Txt(Store.exampleHan(card, x, place, T.glyph.argbInt()).annotated(), ff(FF.Body))
                        Txt(Store.exampleRom(card, x, rom, place).annotated(), lat(15f), T.greenInk)
                        Txt(x.z, ff(FF.Footnote), T.muted)
                    }
                }
            }
            if (card.t == "臺華共同") Txt(tr("臺華共同詞：意思跟華語一樣。"), ff(FF.Footnote), T.muted)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ProminentButton(onClick = { Store.mark(card, false, false); UI.closeSheet() }, Modifier.weight(1f), T.rustEdge) { IconLabel(Icons.Filled.Close, tr("不熟")) }
                ProminentButton(onClick = { Store.mark(card, true, false); UI.closeSheet() }, Modifier.weight(1f)) { IconLabel(Icons.Filled.Check, tr("熟悉")) }
            }
            Spacer(Modifier.height(40.dp))
        }
    }
}

/** one row in the 不熟 / 熟悉 lists */
@Composable
fun WordRow(card: Card, streak: Int? = null, goal: Int = 3) {
    val rom = Prefs.rom.value; val place = Prefs.place.value
    val tk = textKey()
    val dict = Store.dict
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Txt(card.h, ff(FF.Title3, FontWeight.Medium), T.blueInk)
                Txt(remember(card.k, tk, dict) { Store.cardRom(card, rom, place).annotated() }, lat(16f), T.greenInk, maxLines = 1)
                Txt(remember(card.k, tk, dict) { Store.cardZy(card, place).annotated() }, ff(FF.Footnote), T.purpleInk, maxLines = 1)
            }
            Txt(card.firstMeaning, ff(FF.Footnote), T.muted, maxLines = 1)
        }
        if (streak != null) Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            for (i in 0 until goal) Box(Modifier.size(7.dp).background(if (i < streak) T.greenInk else T.fnEdge, CircleShape))
        }
    }
}

private fun matches(c: Card, q: String): Boolean {
    if (q.isEmpty()) return true
    val l = q.lowercase()
    return c.h.contains(q) || c.r.any { it.lowercase().contains(l) } || c.d.any { it.t.contains(q) }
}

// MARK: - 不熟

@Composable
fun UnknownTab() {
    Store.rev
    val goal = Prefs.goal.value
    var query by remember { mutableStateOf("") }
    // the words of the 練習範圍 (all of 不熟 when none is chosen)
    val all = Store.practiceCards
    val list = all.filter { matches(it, query) }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("不熟"))
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(0.dp)) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    WeekPanel()
                    class PT(val title: String, val icon: androidx.compose.ui.graphics.vector.ImageVector, val enabled: Boolean, val p: Practice)
                    PracticeScopeMenu()
                    val tiles = listOfNotNull(
                        PT(tr("開始練習"), Icons.Filled.School, all.isNotEmpty(), Practice.STUDY),
                        PT(tr("例句填空"), Icons.Filled.Rule, all.any { it.blankExamples.isNotEmpty() }, Practice.BLANKS),
                        PT(tr("排句子"), Icons.Filled.ViewModule, all.isNotEmpty(), Practice.SCRAMBLE),
                        PT(tr("看字排讀音"), Icons.Filled.MenuBook, all.isNotEmpty(), Practice.READING),
                        PT(tr("聲調練習"), Icons.Filled.GraphicEq, true, Practice.TONES),
                        PT(tr("翻牌配對"), Icons.Filled.GridView, all.size > 1, Practice.MEMORY),
                        PT(tr("手寫練習"), Icons.Filled.Edit, true, Practice.HANDWRITING),
                    )
                    // the last tile: 怎麼練習, what each way of practising does
                    var help by remember { mutableStateOf(false) }
                    TileGrid(tiles.size + 1) { i, m ->
                        if (i == tiles.size) PracticeTile(tr("怎麼練習"), Icons.Filled.HelpOutline, true, m) { help = true }
                        else { val t = tiles[i]; PracticeTile(t.title, t.icon, t.enabled, m) { UI.practice = t.p } }
                    }
                    if (help) PracticeHelp(goal) { help = false }
                    SearchField(query, { query = it }, tr("漢字、羅馬字或意思"), fontSize = androidx.compose.ui.unit.TextUnit(16f, androidx.compose.ui.unit.TextUnitType.Sp))
                    SectionTitle(if (Store.practiceName == tr("全部不熟的詞")) tr("不熟的詞（{0}）", Store.unknownCount)
                        else tr("{0}・不熟的詞（{1}／{2}）", Store.practiceName, all.size, Store.unknownCount))
                }
            }
            if (list.isEmpty()) item { Txt(if (query.isEmpty()) tr("在「新詞」往左滑的詞會出現在這裡。") else tr("找不到。"), ff(FF.Body), T.muted, Modifier.padding(8.dp)) }
            items(list, key = { "u|" + it.k }) { c ->
                SwipeRow(start = Pair(tr("熟悉"), T.greenEdge), end = Pair(tr("移回新詞"), T.oliveEdge),
                    onStart = { Store.mark(c, true, false) }, onEnd = { Store.forget(c) }, onClick = { UI.open(Sheet.CardSheet(c)) }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.weight(1f)) { WordRow(c, Store.streak(c), goal) }
                        val inWeek = Store.isInWeek(c.k)
                        IconButton(onClick = { Store.toggleWeek(c.k) }) {
                            Icon(if (inWeek) Icons.Filled.CalendarMonth else Icons.Filled.CalendarToday, if (inWeek) tr("移出本週") else tr("本週學習"),
                                tint = if (inWeek) T.blueInk else T.fnEdge, modifier = Modifier.size(20.dp))
                        }
                    }
                }
                RowDivider()
            }
        }
    }
}

// MARK: - 熟悉

@Composable
fun KnownTab() {
    Store.rev
    var mode by remember { mutableIntStateOf(0) }
    var reviewKeys by remember { mutableStateOf<List<String>>(emptyList()) }
    var pos by remember { mutableIntStateOf(0) }
    var query by remember { mutableStateOf("") }
    fun shuffle() { reviewKeys = Store.knownCards.map { it.k }.shuffled(); pos = 0 }
    LaunchedEffect(Unit) { if (reviewKeys.isEmpty()) shuffle() }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("熟悉"))
        val modes = if (if (Store.isZh) Store.topics.isNotEmpty() else Store.freqTopics.isNotEmpty()) listOf(0 to tr("卡片複習"), 1 to tr("列表"), 2 to tr("學習進度"))
            else listOf(0 to tr("卡片複習"), 1 to tr("列表"))
        Segmented(modes, mode, { mode = it }, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
        if (mode == 2) {
            HSKProgressList()
        } else if (mode == 0) {
            val cards = ArrayList<Card>()
            if (pos < reviewKeys.size) for (k in reviewKeys.subList(pos, reviewKeys.size)) {
                val c = Store.cardFor(k)
                if (c != null && Store.status(c) == 1) cards.add(c)
                if (cards.size == 4) break
            }
            Column(Modifier.fillMaxSize().widthIn(max = 560.dp).align(Alignment.CenterHorizontally).padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Txt(if (Store.knownCount == 0) "" else "${minOf(pos, reviewKeys.size)} / ${reviewKeys.size}", ff(FF.Footnote), T.muted)
                Spacer(Modifier.height(12.dp))
                if (cards.isEmpty()) {
                    Spacer(Modifier.weight(1f))
                    Txt(if (Store.knownCount == 0) tr("在「新詞」往右滑的詞會出現在這裡。") else tr("這一輪複習完了！"), ff(FF.Body), T.muted, modifier = Modifier.fillMaxWidth())
                    if (Store.knownCount > 0) { Spacer(Modifier.height(12.dp)); ProminentButton(onClick = { shuffle() }) { Text(tr("再複習一輪")) } }
                    Spacer(Modifier.weight(1f))
                } else DeckArea(cards, tr("不熟"), tr("記得"), onSwipe = { card, right ->
                    if (!right) Store.mark(card, false, false)
                    val i = reviewKeys.subList(pos, reviewKeys.size).indexOf(card.k)
                    pos = if (i >= 0) pos + i + 1 else pos + 1
                })
            }
        } else {
            val list = Store.knownCards.filter { matches(it, query) }
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp)) {
                item {
                    SearchField(query, { query = it }, tr("漢字、羅馬字或意思"))
                    SectionTitle(tr("熟悉的詞（{0}）", Store.knownCount))
                }
                items(list, key = { "k|" + it.k }) { c ->
                    SwipeRow(start = null, end = Pair(tr("不熟"), T.rustEdge), onEnd = { Store.mark(c, false, false) }, onClick = { UI.open(Sheet.CardSheet(c)) }) {
                        WordRow(c)
                    }
                    RowDivider()
                }
            }
        }
    }
}

/** one practice button in 不熟 (half the width, the soft green) */
@Composable
fun PracticeTile(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, enabled: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Row(modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(12.dp)).background(if (enabled) T.btn else T.fn.copy(alpha = 0.6f))
        .border(1.5.dp, if (enabled) T.btnEdge else T.fnEdge, RoundedCornerShape(12.dp)).clickable(enabled = enabled, onClick = onClick)
        .padding(horizontal = 8.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = if (enabled) T.btnInk else T.muted, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(6.dp))
        Txt(title, ff(FF.Subheadline, FontWeight.SemiBold), if (enabled) T.btnInk else T.muted, maxLines = 1)
    }
}

/** 不熟 → 怎麼練習: what each way of practising does, one box each */
@Composable
private fun PracticeHelp(goal: Int, close: () -> Unit) {
    val items = buildList {
        add(tr("本週學習") to tr("從不熟的詞選這個星期要學的（或點詞旁邊的月曆），一週後做期末測驗；答錯的詞可以留到下一週。"))
        add(tr("開始練習") to tr("各種題目混在一起練。連續答對 {0} 次，詞就會移到「熟悉」；在列表往右滑可以直接移過去。", goal))
        add(tr("例句填空") to tr("只做例句填空題。"))
        add(tr("排句子") to tr("例句被打亂了，照華語的意思把詞排回去。"))
        add(tr("看字排讀音") to tr("只看漢字，把讀音照順序排。"))
        add(tr("聲調練習") to tr("聽發音，選出聲調正確的拼法（先用不熟的詞，再用常用詞）。"))
        add(tr("翻牌配對") to tr("不熟的詞做成牌，一半是漢字，一半是讀音；一次翻兩張，把漢字和它的讀音配起來。"))
        add(tr("手寫練習") to (if (Store.isZh) tr("選要寫的字（不熟的漢字、HSK／TOCFL 的漢字等級、認識的漢字或自己打的字），") else tr("選要寫的字（不熟的詞的字、熟悉的詞的字或自己打的字），")) + tr("看字、讀音和意思，用手指或觸控筆在格子裡寫。「描字」會在格子裡放一個淡淡的字，藥水條顯示描得多像；點上面的字看有這個字的詞，打勾表示這個字會了。"))
        add(tr("練習範圍") to tr("只練一個等級（或一組）的不熟的詞或字。"))
    }
    AlertDialog(onDismissRequest = close, containerColor = T.bg,
        confirmButton = { TextButton(onClick = close) { Text(tr("完成"), color = T.btnInk) } },
        title = { Txt(tr("怎麼練習"), ff(FF.Headline, FontWeight.SemiBold), T.glyph) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for ((t, x) in items) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.7f))
                    .border(1.dp, T.fnEdge, RoundedCornerShape(14.dp)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Txt(t, ff(FF.Headline, FontWeight.SemiBold), T.glyph)
                    Txt(x, ff(FF.Subheadline), T.muted)
                }
            }
        })
}

// MARK: - the characters of the word beside the card (tablet, or a phone on its side)

/** the side cards of a word's characters: the 1st, 3rd, 5th… on the left (side 0), the 2nd, 4th, 6th… on the right */
@Composable
private fun CharSideColumn(word: Card, side: Int, small: Boolean, modifier: Modifier) {
    val cards = remember(word.k, Store.rev) { sideCards(word) }
    Column(modifier.padding(top = if (small) 22.dp else 32.dp), verticalArrangement = Arrangement.spacedBy(if (small) 10.dp else 16.dp)) {
        for ((i, c) in cards.withIndex()) if (i % 2 == side) key(word.k + "|" + c.k) {
            CharSideSwipe(c, small, Modifier.fillMaxWidth().height(if (small) 140.dp else 210.dp))
        }
    }
}

/** a side card you can swipe: right = 認識, left = 不熟 (the character card); it flies off and comes back, as it's
 *  part of the word on the big card (which stays until that one is swiped) */
@Composable
private fun CharSideSwipe(card: Card, small: Boolean, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    val offset = remember { Animatable(Offset.Zero, Offset.VectorConverter) }
    val shown = remember { Animatable(1f) }
    val dens = LocalDensity.current.density
    var flying by remember { mutableStateOf(false) }
    val ch = Lang.charOf(card.k) ?: card.h
    fun fly(right: Boolean) {
        if (flying) return
        flying = true
        scope.launch {
            offset.animateTo(Offset(if (right) 1600f else -1600f, offset.value.y + 60f), tween(220))
            // 華語: the character card; 台語: the character's own dictionary word (read as in the big card's word)
            if (Lang.charOf(card.k) != null) Store.setCharKnown(ch, right) else Store.mark(card, right, undoable = false)
            offset.snapTo(Offset.Zero); shown.snapTo(0f)
            shown.animateTo(1f, androidx.compose.animation.core.spring(0.7f, 300f))
            flying = false
        }
    }
    Box(modifier.graphicsLayer {
        translationX = offset.value.x; translationY = offset.value.y
        rotationZ = offset.value.x / 22f / density
        val k = 0.85f + 0.15f * shown.value
        scaleX = k; scaleY = k; alpha = shown.value
    }.pointerInput(card.k) {
        detectDragGestures(
            onDragEnd = {
                val w = offset.value.x / density
                if (abs(w) > 90) fly(w > 0) else scope.launch { offset.animateTo(Offset.Zero, androidx.compose.animation.core.spring(0.7f, 400f)) }
            },
            onDragCancel = { scope.launch { offset.animateTo(Offset.Zero) } },
        ) { change, drag -> change.consume(); scope.launch { offset.snapTo(offset.value + drag) } }
    }) {
        CharSideCard(card, small)
        CardLight((offset.value.x / dens / 110f).coerceIn(-1f, 1f))
        // write this character (手寫練習), then back to the cards
        Box(Modifier.align(Alignment.BottomEnd).padding(if (small) 8.dp else 12.dp).size(if (small) 32.dp else 38.dp).clip(CircleShape)
            // (quiet: see-through, in the theme's own colours)
            .background(T.bg.copy(alpha = 0.35f)).border(1.dp, T.fnEdge.copy(alpha = 0.6f), CircleShape)
            .clickable {
                handwritingGiven = if (card.isZh) emptyMap() else mapOf(card.h to card)
                UI.handwritingOnly = listOf(ch); UI.practice = Practice.HANDWRITING
            }, contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Draw, tr("寫這個字"), tint = T.muted, modifier = Modifier.size(if (small) 16.dp else 20.dp))
        }
    }
}

/** a character as a small card: the character, its reading and up to 4 meanings */
@Composable
private fun CharSideCard(card: Card, small: Boolean) {
    val rom = Prefs.rom.value; val place = Prefs.place.value
    val tk = textKey()
    val ch = Lang.charOf(card.k) ?: card.h
    val en = if (card.isZh && Prefs.zhEnglish.value) Store.zh?.entryForChar(ch, "")?.enList?.takeIf { it.isNotEmpty() } else null
    Row(Modifier.fillMaxSize().clip(RoundedCornerShape(24.dp)).background(T.fn).border(2.dp, T.keyEdge, RoundedCornerShape(24.dp))
        .padding(if (small) 10.dp else 16.dp), horizontalArrangement = Arrangement.spacedBy(if (small) 8.dp else 14.dp)) {
        Column(Modifier.widthIn(min = if (small) 48.dp else 70.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Txt(remember(card.k, tk) { Store.cardHan(card, place, T.blueInk.argbInt()).annotated() }, sz(if (small) 38f else 56f, FontWeight.Medium), T.blueInk, maxLines = 1)
            Txt(remember(card.k, tk) { Store.cardRom(card, rom, place).annotated() }, lat(if (small) 15f else 20f), T.greenInk, maxLines = 1)
            when (Store.status(card)) {
                1 -> Chip(tr("熟悉"), T.blue, T.blueEdge, T.blueInk)
                2 -> Chip(tr("不熟"), T.rust, T.rustEdge, T.rustInk)
                else -> {}
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(if (small) 3.dp else 6.dp)) {
            val n = if (small) 3 else 4
            if (en != null) for ((i, t) in en.take(n).withIndex()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                EnNum(i + 1); Txt(t, ff(if (small) FF.Footnote else FF.Subheadline), T.glyph, maxLines = 2)
            } else for ((i, d) in card.d.take(n).withIndex()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                NumBadge(i + 1); Txt(d.t, ff(if (small) FF.Footnote else FF.Subheadline), T.glyph, maxLines = 2)
            }
        }
    }
}

/** the side cards of a word (2 characters or more): 華語, each character's card; 台語, each character's own word in
 *  the dictionary with the reading it has in this word (a character is often read several ways) */
private fun sideCards(word: Card): List<Card> {
    if (word.isZh) {
        val chars = word.h.codePoints().toArray().filter { Zhuyin.isHan(it) }.map { String(Character.toChars(it)) }
        return if (chars.size > 1) chars.mapNotNull { Store.cardFor(Lang.charKey(it)) } else emptyList()
    }
    val tab = word.k.indexOf('\t')
    if (tab < 0) return emptyList()
    val han = word.k.substring(0, tab).codePoints().toArray().map { String(Character.toChars(it)) }
    val codes = word.k.substring(tab + 1).split(" ")
    if (han.size < 2 || han.size != codes.size) return emptyList()
    return han.zip(codes).mapNotNull { (h, c) ->
        val k = h + "\t" + c
        Store.cardFor(k) ?: Store.dict?.altParent?.get(k)?.takeIf { p -> p.indexOf('\t').let { it > 0 && p.codePointCount(0, it) == 1 } }?.let { Store.cardFor(it) }
    }
}

// MARK: - a swiped card falling apart

/** a card falling apart: its picture cut into little squares, each with its own way to go. 認識: they turn blue
 *  and float up and away to the right; 不熟: red, out to the left and falling. With 聲調顏色, the word's tone
 *  colours, mixed. */
class CardBurst(val start: Long, val right: Boolean, val w: Int, val h: Int, val offset: Offset, val angle: Float,
                val cell: Float, val cols: Int, val rows: Int, val colors: IntArray, val rnd: FloatArray, val tones: IntArray) {
    companion object {
        const val LIFE = 1.1f
        fun make(card: Card, img: ImageBitmap?, size: IntSize, right: Boolean, offset: Offset, angleDeg: Float, density: Float): CardBurst? {
            if (size.width <= 0 || size.height <= 0) return null
            val cell = (size.width / 42f).coerceIn(16f, 34f)
            val cols = max(1, (size.width / cell).toInt()); val rows = max(1, (size.height / cell).toInt())
            val px = IntArray(cols * rows)
            if (img != null) try {
                var bmp = img.asAndroidBitmap()
                if (bmp.config == android.graphics.Bitmap.Config.HARDWARE) bmp = bmp.copy(android.graphics.Bitmap.Config.ARGB_8888, false)
                android.graphics.Bitmap.createScaledBitmap(bmp, cols, rows, true).getPixels(px, 0, cols, 0, 0, cols, rows)
            } catch (_: Exception) {}
            val base = T.fn.toArgb()
            val r = 28f * density / cell
            for (y in 0 until rows) for (x in 0 until cols) {
                val i = y * cols + x
                // outside the rounded corners: nothing
                val fx = x + 0.5f; val fy = y + 0.5f
                val rx = minOf(fx, cols - fx); val ry = minOf(fy, rows - fy)
                val inside = !(rx < r && ry < r) || (r - rx) * (r - rx) + (r - ry) * (r - ry) <= r * r
                val p = px[i]
                val a = (p ushr 24) / 255f
                // (the card's own colour where the picture has nothing)
                val c = if (a < 0.99f) blend(p, base, a) else p
                px[i] = if (inside) (c or (0xFF shl 24)) else 0
            }
            val rnd = FloatArray(cols * rows * 4) { Math.random().toFloat() }
            // the word's characters in their tone colours (only when 聲調顏色 is on)
            val tones = if (Prefs.toneSys.value != 0) {
                Store.cardHan(card, Prefs.place.value, T.blueInk.toArgb()).flatMap { seg ->
                    val c = seg.c ?: return@flatMap emptyList<Int>()
                    List(seg.t.codePointCount(0, seg.t.length)) { c }
                }.toIntArray()
            } else IntArray(0)
            return CardBurst(android.os.SystemClock.uptimeMillis(), right, size.width, size.height, offset,
                Math.toRadians(angleDeg.toDouble()).toFloat(), cell, cols, rows, px, rnd, tones)
        }
        private fun blend(p: Int, base: Int, a: Float): Int {
            fun ch(v: Int, s: Int) = ((v shr s) and 0xFF)
            fun mix(s: Int) = (ch(p, s) + ch(base, s) * (1 - a)).toInt().coerceIn(0, 255)
            return (mix(16) shl 16) or (mix(8) shl 8) or mix(0)
        }
    }
}

/** draws the falling-apart cards (over the whole screen: nothing cuts it off) */
@Composable
private fun CardDust(bursts: List<CardBurst>, modifier: Modifier) {
    var now by remember { mutableLongStateOf(android.os.SystemClock.uptimeMillis()) }
    LaunchedEffect(Unit) { while (true) { withFrameMillis { }; now = android.os.SystemClock.uptimeMillis() } }
    val blue = Color(0xFF6EA8FF); val red = Color(0xFFFF6B66)
    Canvas(modifier) {
        for (b in bursts) {
            val t = (now - b.start) / 1000f
            if (t < 0 || t >= CardBurst.LIFE) continue
            val cx = size.width / 2 + b.offset.x; val cy = size.height / 2 + b.offset.y
            val ca = kotlin.math.cos(b.angle); val sa = kotlin.math.sin(b.angle)
            val tint = if (b.right) blue else red
            val c = b.cell
            for (y in 0 until b.rows) for (x in 0 until b.cols) {
                val i = y * b.cols + x
                val col = b.colors[i]
                if (col == 0) continue
                val r0 = b.rnd[i * 4]; val r1 = b.rnd[i * 4 + 1]; val r2 = b.rnd[i * 4 + 2]; val r3 = b.rnd[i * 4 + 3]
                val u = (x + 0.5f) / b.cols
                // the side it's going to goes first, like a wind blowing it away
                val delay = (if (b.right) 1 - u else u) * 0.28f + r0 * 0.12f
                val s = t - delay
                val lx = (x + 0.5f) * c - b.w / 2f; val ly = (y + 0.5f) * c - b.h / 2f
                var px = cx + lx * ca - ly * sa; var py = cy + lx * sa + ly * ca
                var alpha = 1f; var k = 0f; var sc = 1f
                if (s > 0) {
                    k = (s / 0.22f).coerceAtMost(1f)
                    val left = (CardBurst.LIFE - delay).coerceAtLeast(0.3f)
                    alpha = (1 - s / left).coerceAtLeast(0f)
                    sc = 1 - 0.45f * s / left
                    val d = density
                    if (b.right) {
                        px += ((40 + r1 * 110) * s + kotlin.math.sin(s * 7 + r2 * 6) * 6) * d
                        py -= ((60 + r3 * 120) * s + 260 * s * s) * d
                    } else {
                        px -= ((50 + r1 * 120) * s) * d
                        py += ((-40 + r3 * 60) * s + 620 * s * s) * d
                    }
                }
                val to = if (b.tones.isEmpty()) tint else Color(b.tones[minOf((r2 * b.tones.size).toInt(), b.tones.size - 1)])
                val from = Color(col)
                val rgb = Color(from.red + (to.red - from.red) * k, from.green + (to.green - from.green) * k,
                    from.blue + (to.blue - from.blue) * k, alpha)
                val wq = c * sc
                drawRect(rgb, Offset(px - wq / 2, py - wq / 2), Size(wq, wq))
            }
        }
    }
}
