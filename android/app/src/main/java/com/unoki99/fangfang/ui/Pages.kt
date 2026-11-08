package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.engine.Dict

/** shows its content once the dictionary is loaded */
@Composable
fun DictGate(content: @Composable (Dict) -> Unit) {
    LaunchedEffect(Unit) { Store.loadDict() }
    val d = Store.dict
    if (d != null) content(d)
    else Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val e = Store.dictError
        if (e != null) Txt(e, ff(FF.Body), T.muted, Modifier.padding(16.dp))
        else Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator(color = T.greenInk)
            Spacer(Modifier.height(12.dp))
            Txt(tr("載入字典…"), ff(FF.Footnote), T.muted)
        }
    }
}

/** shows its content once the 華語 dictionary is loaded */
@Composable
fun ZhGate(content: @Composable (com.unoki99.fangfang.engine.ZhDict) -> Unit) {
    val z = Store.zh
    // (a new dictionary (華語 ↔ 粵語): everything made again, nothing kept from the other one)
    if (z != null) key(z) { content(z) }
    else Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val e = Store.zhError
        if (e != null) Txt(e, ff(FF.Body), T.muted, Modifier.padding(16.dp))
        else Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator(color = T.greenInk)
            Spacer(Modifier.height(12.dp))
            Txt(tr("載入{0}詞典…", tr(com.unoki99.fangfang.engine.Lang.names[if (com.unoki99.fangfang.Prefs.lang.value == 2) 2 else 1])), ff(FF.Footnote), T.muted)
        }
    }
}

/** a tab (or the sheet): its own page, with the pages opened from it drawn on top; back goes back */
@Composable
fun StackHost(nav: NavStack, root: @Composable () -> Unit) {
    CompositionLocalProvider(LocalNav provides nav) {
        Box(Modifier.fillMaxSize()) {
            root()
            val top = nav.top
            if (top != null) {
                key(nav.stack.size, top) {
                    AppBackground(Modifier.pointerInput(Unit) { detectTapGestures { } }) {
                        RoutePage(top) { nav.pop() }
                    }
                }
            }
        }
        BackHandler(enabled = nav.stack.isNotEmpty()) { nav.pop() }
    }
}

@Composable
fun RoutePage(r: Route, onBack: () -> Unit) {
    when (r) {
        is Route.ZhEntry -> { ZhGate { z -> ZhEntryPage(z, r.key, onBack) }; return }
        is Route.ZhLevel -> { LevelWordsPage(r.level, onBack); return }
        is Route.ZhProgress -> { ZhProgressPage(onBack); return }
        is Route.SenseCopySettings -> { SenseCopySettingsPage(onBack); return }
        is Route.Radicals -> { RadicalPage(r.zh, onBack); return }
        is Route.ZhCompare -> { ZhGate { z -> ZhComparePage(z, onBack) }; return }
        is Route.ZhClasses -> { ZhGate { z -> ZhWordClassListPage(z, onBack) }; return }
        is Route.ZhClass -> { ZhGate { z -> ZhWordClassPage(z, r.cls, onBack) }; return }
        is Route.ZhChars -> { ZhCharListPage(onBack); return }
        is Route.ToneColorPicker -> { ToneColorPickerPage(onBack); return }
        else -> {}
    }
    DictGate { d ->
        when (r) {
            is Route.Entry -> EntryPage(d, r.key, onBack)
            is Route.Keys -> KeysPage(d, r.title, r.keys, onBack)
            is Route.Sentences -> SentencesPage(d, r.title, r.hits, onBack)
            is Route.Places -> PlacesPage(d, r.groups, onBack)
            is Route.WordClass -> WordClassPage(d, r.cls, onBack)
            is Route.Compare -> ComparePage(d, onBack)
            is Route.Category -> CategoryWordsPage(d, r.i, onBack)
            is Route.WordClasses -> WordClassesPage(d, onBack)
            is Route.Japanese -> JapanesePage(d, onBack)
            else -> {}
        }
    }
}

/** the sheets from the bottom (a word from an example sentence, a word in 轉換, a card) */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Sheets() {
    for ((i, s) in UI.sheets.withIndex()) {
        key(i, s) {
            val state = rememberModalBottomSheetState(skipPartiallyExpanded = false)
            val nav = remember { NavStack() }
            ModalBottomSheet(
                onDismissRequest = { UI.closeSheet() }, sheetState = state, containerColor = T.bg,
                dragHandle = { BottomSheetDefaults.DragHandle(color = T.muted) },
            ) {
                Box(Modifier.fillMaxWidth().fillMaxHeight(0.94f)) {
                    StackHost(nav) {
                        when (s) {
                            is Sheet.Word -> DictGate { d -> EntrySheetRoot(d, s.key) }
                            is Sheet.ConvWord -> DictGate { d -> ConvWordSheet(d, s.index) }
                            is Sheet.CardSheet -> CardSheetRoot(s.card)
                            is Sheet.ZhWord -> ZhGate { z -> ZhEntrySheetRoot(z, s.key) }
                            is Sheet.CharWords -> CharWordsSheetRoot(s.ch)
                        }
                    }
                }
            }
        }
    }
}
