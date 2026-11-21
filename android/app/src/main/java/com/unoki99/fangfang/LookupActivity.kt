package com.unoki99.fangfang

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.engine.*
import com.unoki99.fangfang.ui.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// 方方查詞 (the menu of text selected in any app): a small card over that app with the words of the text, in the
// language shown in the app; tap a word, or 在 App 打開, to see it all in the app. (The iPhone's Shortcuts card.)
class LookupActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Prefs.init(applicationContext)
        Store.init(applicationContext)
        val text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()?.trim().orEmpty().take(60)
        if (text.isEmpty()) { finish(); return }
        setContent { LookupCard(text, { finish() }) { openApp(text) } }
    }

    /** the whole app, on 詞典 with the text searched */
    private fun openApp(text: String) {
        startActivity(Intent(Intent.ACTION_PROCESS_TEXT).setClass(this, MainActivity::class.java)
            .putExtra(Intent.EXTRA_PROCESS_TEXT, text).setType("text/plain").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }
}

@Composable
private fun LookupCard(text: String, close: () -> Unit, open: () -> Unit) {
    T.syncEngine()
    val scheme = darkColorScheme(primary = T.btnInk, onPrimary = T.bg, background = T.bg, surface = T.fn, onSurface = T.glyph,
        onBackground = T.glyph, surfaceVariant = T.fn, onSurfaceVariant = T.muted, secondary = T.oliveInk, outline = T.fnEdge)
    LaunchedEffect(Unit) { Store.load() }
    MaterialTheme(colorScheme = scheme) {
        ProvideTextStyle(TextStyle(color = T.glyph)) {
            // (a tap outside the card closes it)
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f))
                .clickable(MutableInteractionSource(), null) { close() }, contentAlignment = Alignment.BottomCenter) {
                Column(Modifier.fillMaxWidth().widthIn(max = 600.dp).heightIn(max = 520.dp).navigationBarsPadding().padding(10.dp)
                    .clip(RoundedCornerShape(20.dp)).background(T.bg).clickable(MutableInteractionSource(), null) {}.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Txt(text, ff(FF.Headline), T.glyph, Modifier.weight(1f), maxLines = 1)
                        TextButton(onClick = open) { Text(tr("在 App 打開"), color = T.btnInk) }
                        TextButton(onClick = close) { Text(tr("完成"), color = T.muted) }
                    }
                    Box(Modifier.fillMaxWidth().weight(1f, fill = false)) {
                        if (!Store.loaded) CircularProgressIndicator(Modifier.align(Alignment.Center).padding(20.dp), color = T.greenInk)
                        else if (Prefs.lang.value != 0) ZhGate { z -> ZhResults(z, text, open) }
                        else DictGate { d -> TwResults(d, text, open) }
                    }
                }
            }
        }
    }
}

@Composable
private fun ZhResults(z: ZhDict, text: String, open: () -> Unit) {
    var list by remember { mutableStateOf<List<Int>?>(null) }
    LaunchedEffect(z, text) {
        list = withContext(Dispatchers.Default) {
            val f = z.search(text, Prefs.zhPlace.value)
            (f.words + f.partWords.flatten() + f.mandarin + f.starts + f.english).distinct().take(8)
        }
    }
    val l = list ?: return
    Column(Modifier.dragScrollY(rememberScrollState())) {
        if (l.isEmpty()) Txt(tr("找不到「{0}」。", text), ff(FF.Body), T.muted, Modifier.padding(8.dp))
        for (i in l) if (i < z.entries.size) Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { open() }) { ZhWordRow(z, z.entries[i], meanings = 2) }
    }
}

@Composable
private fun TwResults(d: Dict, text: String, open: () -> Unit) {
    var list by remember { mutableStateOf<List<String>?>(null) }
    LaunchedEffect(d, text) {
        list = withContext(Dispatchers.Default) {
            val r = Lookup.run(d, text, Prefs.place.value, Prefs)
            (r.exact + r.taigi + r.parts.indices.flatMap { r.partResults[it].exact + r.partResults[it].taigi } + r.contains).distinct().take(8)
        }
    }
    val l = list ?: return
    Column(Modifier.dragScrollY(rememberScrollState())) {
        if (l.isEmpty()) Txt(tr("找不到「{0}」。", text), ff(FF.Body), T.muted, Modifier.padding(8.dp))
        for (k in l) Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { open() }) { DictRow(d, k) }
    }
}
