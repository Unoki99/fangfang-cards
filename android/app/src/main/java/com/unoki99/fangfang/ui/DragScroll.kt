package com.unoki99.fangfang.ui

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.gestures.FlingBehavior
import androidx.compose.foundation.gestures.ScrollableDefaults
import androidx.compose.foundation.gestures.ScrollableState
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import kotlin.math.abs

// Scrolling by dragging with the mouse, as with a finger on a touch screen (the computer: Compose's pages take only the
// wheel from a mouse). Every page that scrolls: its .verticalScroll / .horizontalScroll are dragScrollY / dragScrollX,
// and its lists and grids are these LazyColumn / LazyVerticalGrid (the same as Compose's, the mouse drag added).
// A press that doesn't move is still a click; a drag something inside takes first (a slider, a card swiped, text being
// selected, an inner list) is left to it; the innermost page that can still move is the one that does.

/** a mouse drag scrolls state (up and down, or sideways) */
fun Modifier.mouseDrag(state: ScrollableState, horizontal: Boolean = false): Modifier = pointerInput(state, horizontal) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        if (down.type == PointerType.Mouse) {
            val start = down.position
            var last = start
            var dragging = false
            while (true) {
                // (dragging: taken before anything inside sees it, so a button it started on isn't clicked)
                val ev = awaitPointerEvent(if (dragging) PointerEventPass.Initial else PointerEventPass.Main)
                val c = ev.changes.firstOrNull { it.id == down.id } ?: break
                if (!c.pressed) break
                if (!dragging) {
                    if (c.isConsumed) break
                    val moved = if (horizontal) abs(c.position.x - start.x) else abs(c.position.y - start.y)
                    if (moved <= viewConfiguration.touchSlop) continue
                    // (this page can't move that way: left to the one around it)
                    val dir = if (horizontal) start.x - c.position.x else start.y - c.position.y
                    if ((dir > 0 && !state.canScrollForward) || (dir < 0 && !state.canScrollBackward)) break
                    dragging = true
                    last = c.position
                    c.consume()
                    continue
                }
                val d = if (horizontal) c.position.x - last.x else c.position.y - last.y
                last = c.position
                state.dispatchRawDelta(-d)
                c.consume()
            }
        }
    }
}

/** .verticalScroll(state), and a mouse drag scrolls it too */
fun Modifier.dragScrollY(state: ScrollState): Modifier = mouseDrag(state).verticalScroll(state)

/** .horizontalScroll(state), and a mouse drag scrolls it too */
fun Modifier.dragScrollX(state: ScrollState): Modifier = mouseDrag(state, horizontal = true).horizontalScroll(state)

/** Compose's LazyColumn, a mouse drag scrolling it too */
@Composable
fun LazyColumn(
    modifier: Modifier = Modifier,
    state: LazyListState = rememberLazyListState(),
    contentPadding: PaddingValues = PaddingValues(0.dp),
    reverseLayout: Boolean = false,
    verticalArrangement: Arrangement.Vertical = if (!reverseLayout) Arrangement.Top else Arrangement.Bottom,
    horizontalAlignment: Alignment.Horizontal = Alignment.Start,
    flingBehavior: FlingBehavior = ScrollableDefaults.flingBehavior(),
    userScrollEnabled: Boolean = true,
    content: LazyListScope.() -> Unit,
) = androidx.compose.foundation.lazy.LazyColumn(modifier = modifier.mouseDrag(state), state = state,
    contentPadding = contentPadding, reverseLayout = reverseLayout, verticalArrangement = verticalArrangement,
    horizontalAlignment = horizontalAlignment, flingBehavior = flingBehavior, userScrollEnabled = userScrollEnabled,
    content = content)

/** Compose's LazyVerticalGrid, a mouse drag scrolling it too */
@Composable
fun LazyVerticalGrid(
    columns: GridCells,
    modifier: Modifier = Modifier,
    state: LazyGridState = rememberLazyGridState(),
    contentPadding: PaddingValues = PaddingValues(0.dp),
    reverseLayout: Boolean = false,
    verticalArrangement: Arrangement.Vertical = if (!reverseLayout) Arrangement.Top else Arrangement.Bottom,
    horizontalArrangement: Arrangement.Horizontal = Arrangement.Start,
    flingBehavior: FlingBehavior = ScrollableDefaults.flingBehavior(),
    userScrollEnabled: Boolean = true,
    content: LazyGridScope.() -> Unit,
) = androidx.compose.foundation.lazy.grid.LazyVerticalGrid(columns = columns,
    modifier = modifier.mouseDrag(state), state = state, contentPadding = contentPadding, reverseLayout = reverseLayout,
    verticalArrangement = verticalArrangement, horizontalArrangement = horizontalArrangement,
    flingBehavior = flingBehavior, userScrollEnabled = userScrollEnabled, content = content)
