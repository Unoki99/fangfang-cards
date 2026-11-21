package com.unoki99.fangfang.ui

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.boundsInParent
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

const val FLOW_BREAK = "flow-break"

/** a mouse is what points (the Windows version sets it): the words that open swell under the pointer, the pointer
 *  becomes a hand over them, and the songs' lyrics open word by word */
object PointerUI { var mouse = false }

/** this piece starts a new line in a Flow */
fun Modifier.flowBreak(on: Boolean = true): Modifier = if (on) this.layoutId(FLOW_BREAK) else this

/** lays its children out in rows, wrapping like text. baseline: the pieces of a row stand on one line (their text's
 *  baseline), not at the row's top: a character drawn from another font (a rare 台語 character, 𪜶) has other
 *  heights above and below its letters, and stood higher or lower than the rest */
@Composable
fun Flow(modifier: Modifier = Modifier, spacing: Dp = 6.dp, lineSpacing: Dp = spacing, baseline: Boolean = false, content: @Composable () -> Unit) {
    Layout(content, modifier) { measurables, constraints ->
        val maxW = if (constraints.hasBoundedWidth) constraints.maxWidth else Int.MAX_VALUE
        val sp = spacing.roundToPx(); val ls = lineSpacing.roundToPx()
        val loose = Constraints(maxWidth = maxW)
        val placeables = measurables.map { it.measure(loose) }
        val n = placeables.size
        val xs = IntArray(n); val ys = IntArray(n); val rowOf = IntArray(n)
        // (each piece's baseline from its top; none: its top)
        val bs = IntArray(n) { i -> if (!baseline) 0 else placeables[i][FirstBaseline].let { b -> if (b == AlignmentLine.Unspecified) 0 else b } }
        val rowAbove = ArrayList<Int>(); val rowBelow = ArrayList<Int>()
        var x = 0; var row = 0; var widest = 0
        rowAbove.add(0); rowBelow.add(0)
        for (i in 0 until n) {
            val p = placeables[i]
            val br = measurables[i].layoutId == FLOW_BREAK
            if ((x > 0 && x + p.width > maxW) || (br && (x > 0 || row > 0 || i > 0))) {
                x = 0; row++; rowAbove.add(0); rowBelow.add(0)
            }
            xs[i] = x; rowOf[i] = row
            rowAbove[row] = maxOf(rowAbove[row], bs[i])
            rowBelow[row] = maxOf(rowBelow[row], p.height - bs[i])
            x += p.width + sp
            widest = maxOf(widest, x - sp)
        }
        // (each row as tall as what's above its baseline and below it; its pieces put down on it)
        val rowY = IntArray(row + 1)
        var y = 0
        for (r in 0..row) { rowY[r] = y; y += rowAbove[r] + rowBelow[r] + ls }
        val total = if (n == 0) 0 else y - ls
        for (i in 0 until n) ys[i] = rowY[rowOf[i]] + rowAbove[rowOf[i]] - bs[i]
        val w = if (constraints.hasBoundedWidth) maxOf(constraints.minWidth, minOf(widest, maxW)) else widest
        val h = maxOf(constraints.minHeight, total)
        layout(w, h) { for ((i, p) in placeables.withIndex()) p.place(xs[i], ys[i]) }
    }
}

/**
 * Words in a row that wrap like text. A tap on a tappable word opens it (it swells while pressed); holding a finger
 * on the text and sliding swells the word under it, and letting go opens that word.
 */
@Composable
fun TapWords(
    count: Int,
    modifier: Modifier = Modifier,
    lineSpacing: Dp = 0.dp,
    isTappable: (Int) -> Boolean,
    newLine: (Int) -> Boolean = { false },
    onTap: (Int) -> Unit,
    item: @Composable (index: Int, hot: Boolean) -> Unit,
) {
    val hot = remember { mutableStateOf<Int?>(null) }
    val rects = remember { HashMap<Int, Rect>() }
    rects.keys.removeAll { it >= count }
    val haptic = LocalHapticFeedback.current
    val tappable by rememberUpdatedState(isTappable)
    val tap by rememberUpdatedState(onTap)
    fun hitAt(p: Offset, grow: Float = 0f): Int? =
        rects.entries.firstOrNull { (i, r) -> tappable(i) && r.inflate(grow).contains(p) }?.key

    Flow(
        modifier.pointerInput(count) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                val start = down.position
                hot.value = hitAt(start)
                var outcome = 0          // 0 = held (slide over the words), 1 = a tap, 2 = something else (scrolling)
                var last = start
                withTimeoutOrNull(300L) {
                    while (true) {
                        val ev = awaitPointerEvent()
                        val ch = ev.changes.firstOrNull { it.id == down.id }
                        if (ch == null || ch.isConsumed || (ch.position - start).getDistance() > viewConfiguration.touchSlop) { outcome = 2; break }
                        last = ch.position
                        if (!ch.pressed) { outcome = 1; ch.consume(); break }
                    }
                }
                when (outcome) {
                    1 -> { val i = hot.value; hot.value = null; if (i != null) tap(i) }
                    2 -> hot.value = null
                    else -> {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        hot.value = hitAt(last, 4f)
                        while (true) {
                            val ev = awaitPointerEvent()
                            val ch = ev.changes.firstOrNull { it.id == down.id } ?: break
                            ch.consume()
                            if (!ch.pressed) break
                            val h = hitAt(ch.position, 4f)
                            if (h != hot.value) {
                                hot.value = h
                                if (h != null) haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            }
                        }
                        val open = hot.value
                        hot.value = null
                        if (open != null) tap(open)
                    }
                }
            }
        }.then(if (!PointerUI.mouse) Modifier else Modifier.pointerInput(count) {
            // (a mouse: the word under the pointer swells, as it does on the iPad and the Mac)
            awaitPointerEventScope {
                while (true) {
                    val ev = awaitPointerEvent()
                    val ch = ev.changes.firstOrNull() ?: continue
                    if (ch.pressed) continue
                    when (ev.type) {
                        PointerEventType.Move, PointerEventType.Enter -> { val h = hitAt(ch.position); if (h != hot.value) hot.value = h }
                        PointerEventType.Exit -> hot.value = null
                        else -> {}
                    }
                }
            }
        }),
        spacing = 0.dp, lineSpacing = lineSpacing, baseline = true,
    ) {
        for (i in 0 until count) {
            val isHot by remember(i) { derivedStateOf { hot.value == i } }
            Box(Modifier.flowBreak(newLine(i)).onGloballyPositioned { rects[i] = it.boundsInParent() }
                .then(if (PointerUI.mouse && tappable(i)) Modifier.pointerHoverIcon(PointerIcon.Hand) else Modifier)) {
                item(i, isHot)
            }
        }
    }
}
