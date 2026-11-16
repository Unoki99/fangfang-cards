package com.unoki99.fangfang.ui

import androidx.activity.compose.BackHandler
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
import com.unoki99.fangfang.*
import com.unoki99.fangfang.engine.Lang
import com.unoki99.fangfang.engine.ConvertEngine
import com.unoki99.fangfang.engine.Seg
import com.unoki99.fangfang.engine.Styled
import kotlinx.coroutines.launch

// 電台 and 歌詞, over everything (from the radio button at the top of the main pages)

/** the radio button in the top bars: lit while a station plays */
@Composable
fun RadioBarButton() {
    val on = Radio.state == Radio.State.PLAYING || Radio.state == Radio.State.CONNECTING
    IconButton(onClick = { UI.radioOpen = true }) { Icon(Icons.Filled.Radio, tr("電台"), tint = if (on) T.greenInk else T.glyph) }
}

@Composable
fun RadioScreen() {
    BackHandler { if (UI.lyricsOpen) UI.lyricsOpen = false else UI.radioOpen = false }
    if (UI.lyricsOpen) { AppBackground { LyricsScreen() }; return }
    var lang by remember { mutableIntStateOf(Store.lang.coerceIn(0, RadioLang.languages.size - 1)) }
    var searching by remember { mutableStateOf(false) }
    var adding by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf<RadioStation?>(null) }
    AppBackground {
        Column(Modifier.fillMaxSize()) {
            TopBar(tr("電台"), { UI.radioOpen = false }, close = true, settings = false) {
                IconButton(onClick = { searching = true }) { Icon(Icons.Filled.Search, tr("找電台"), tint = T.glyph) }
                IconButton(onClick = { adding = true }) { Icon(Icons.Filled.Add, tr("自己加網址"), tint = T.glyph) }
            }
            if (searching) { RadioSearch(lang) { searching = false }; return@Column }
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item { NowPlayingPanel() }
                item {
                    Segmented((0 until RadioLang.languages.size).map { it to tr(Lang.names[it]) }, lang, { lang = it })
                }
                val list = Radio.stations.filter { it.lang == lang }
                if (list.isEmpty()) item { Txt(tr("這個語言還沒有電台。按上面的放大鏡找。"), ff(FF.Body), T.muted, Modifier.padding(8.dp)) }
                // (by the kind of stream each sends: MP3, AAC, AAC+, HLS, the rest; not known yet until it has played)
                val groups = list.groupBy { it.format }.toList().sortedBy { RadioFormat.rank(it.first) }
                for ((format, inGroup) in groups) {
                item(key = "format-" + (format ?: "?")) {
                    Txt(RadioFormat.title(format), ff(FF.Footnote, FontWeight.SemiBold), T.muted, Modifier.padding(start = 4.dp, top = 6.dp))
                }
                items(inGroup, key = { it.id }) { s ->
                    val playing = Radio.current?.id == s.id && Radio.state != Radio.State.IDLE
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(if (playing) T.green.copy(alpha = 0.35f) else T.fn.copy(alpha = 0.7f))
                        .clickable { Radio.toggle(s) }.padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(if (playing && Radio.state == Radio.State.PLAYING) Icons.Filled.StopCircle else Icons.Filled.PlayCircle, null,
                            tint = if (playing) T.greenInk else T.btnInk, modifier = Modifier.size(30.dp))
                        Column(Modifier.weight(1f)) {
                            Txt(s.name, ff(FF.Body, FontWeight.SemiBold), T.glyph, maxLines = 1)
                            if (playing) Txt(when (Radio.state) {
                                Radio.State.CONNECTING -> tr("連線中…"); Radio.State.FAILED -> tr("連不上這個電台"); else -> Radio.nowPlaying ?: tr("播放中")
                            }, ff(FF.Caption), if (Radio.state == Radio.State.FAILED) T.rustInk else T.muted, maxLines = 1)
                        }
                        IconButton(onClick = { removing = s }) { Icon(Icons.Filled.Delete, tr("移除"), tint = T.muted) }
                    }
                }
                }
                item {
                    TextButton(onClick = { Radio.restoreStarters() }) { Text(tr("加回原本的電台"), color = T.btnInk) }
                    Txt(tr("電台來自 Radio Browser（radio-browser.info）。離開 App 也會繼續播，通知裡可以停。電台有送歌名的話，按「歌詞」可以看歌詞（LRCLIB）。"),
                        ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
                    Spacer(Modifier.height(40.dp))
                }
            }
        }
    }
    if (adding) {
        var name by remember { mutableStateOf("") }
        var url by remember { mutableStateOf("") }
        AlertDialog(onDismissRequest = { adding = false }, containerColor = T.fn,
            title = { Txt(tr("自己加網址"), ff(FF.Headline)) },
            text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it }, singleLine = true, label = { Text(tr("名字")) })
                OutlinedTextField(url, { url = it }, singleLine = true, label = { Text(tr("串流網址（http…）")) })
            } },
            confirmButton = { TextButton(onClick = {
                if (name.isNotBlank() && url.trim().startsWith("http")) Radio.add(name.trim(), url.trim(), lang)
                adding = false
            }) { Text(tr("加入"), color = T.btnInk) } },
            dismissButton = { TextButton(onClick = { adding = false }) { Text(tr("取消"), color = T.muted) } })
    }
    removing?.let { s ->
        AlertDialog(onDismissRequest = { removing = null }, containerColor = T.fn,
            title = { Txt(tr("移除「{0}」？", s.name), ff(FF.Headline)) },
            confirmButton = { TextButton(onClick = { Radio.remove(s); removing = null }) { Text(tr("移除"), color = T.rustInk) } },
            dismissButton = { TextButton(onClick = { removing = null }) { Text(tr("取消"), color = T.muted) } })
    }
}

/** the station playing, what it says is playing, 停 and 歌詞 */
@Composable
private fun NowPlayingPanel() {
    val s = Radio.current ?: return
    if (Radio.state == Radio.State.IDLE) return
    Panel {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Filled.GraphicEq, null, tint = T.greenInk, modifier = Modifier.size(28.dp))
            Column(Modifier.weight(1f)) {
                Txt(s.name, ff(FF.Headline), T.glyph, maxLines = 1)
                Txt(Radio.nowPlaying ?: if (Radio.state == Radio.State.CONNECTING) tr("連線中…") else tr("電台沒有送歌名"), ff(FF.Footnote), T.muted, maxLines = 2)
            }
        }
        // 睡眠計時: stops by itself after a while
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.Bedtime, null, tint = T.muted, modifier = Modifier.size(18.dp))
            Txt(Radio.sleepAt?.let { tr("{0} 分鐘後停", maxOf(1, ((it - System.currentTimeMillis()) / 60000).toInt())) } ?: tr("睡眠計時"), ff(FF.Footnote), T.muted, Modifier.weight(1f))
            for (m in listOf(15, 30, 60)) TextButton(onClick = { Radio.sleep(m) }) { Text("$m", color = T.btnInk) }
            if (Radio.sleepAt != null) TextButton(onClick = { Radio.sleep(null) }) { Text(tr("關"), color = T.muted) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            SoftButton(onClick = { Radio.stop() }, Modifier.weight(1f).heightIn(min = 44.dp)) { IconLabel(Icons.Filled.Stop, tr("停"), ff(FF.Subheadline)) }
            SoftButton(onClick = { UI.lyricsOpen = true }, Modifier.weight(1f).heightIn(min = 44.dp)) { IconLabel(Icons.Filled.MusicNote, tr("歌詞"), ff(FF.Subheadline)) }
        }
    }
}

/** 找電台: by name, or the language's stations (Radio Browser) */
@Composable
private fun RadioSearch(lang: Int, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<RBStation>?>(null) }
    var busy by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    fun run() {
        busy = true; failed = false
        scope.launch {
            results = try {
                if (query.isNotBlank()) RadioDirectory.search(name = query.trim())
                else {
                    // the language's stations: by each of its names, the most played first
                    val out = ArrayList<RBStation>(); val seen = HashSet<String>()
                    for (l in RadioLang.languages[lang]) for (s in RadioDirectory.search(language = l, limit = 30)) if (seen.add(s.uuid)) out.add(s)
                    out.sortedByDescending { it.clicks }
                }
            } catch (_: Exception) { failed = true; emptyList() }
            busy = false
        }
    }
    LaunchedEffect(Unit) { run() }
    Column(Modifier.fillMaxSize().padding(horizontal = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { SearchField(query, { query = it }, tr("電台的名字（空白：{0}的電台）", tr(Lang.names[lang]))) }
            TextButton(onClick = { run() }) { Text(tr("找"), color = T.btnInk) }
            TextButton(onClick = onDone) { Text(tr("完成"), color = T.btnInk) }
        }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth().padding(vertical = 6.dp), color = T.btnEdge, trackColor = T.fnEdge)
        if (failed) Txt(tr("連不上 Radio Browser，等一下再試。"), ff(FF.Footnote), T.rustInk, Modifier.padding(8.dp))
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(results ?: emptyList(), key = { it.uuid }) { r ->
                val have = Radio.has(r)
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.7f)).padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column(Modifier.weight(1f)) {
                        Txt(r.name, ff(FF.Body, FontWeight.SemiBold), T.glyph, maxLines = 1)
                        Txt(listOf(r.country, r.language, (if (r.hls) "HLS " else "") + r.codec + (if (r.bitrate > 0) " ${r.bitrate}k" else "")).filter { it.isNotBlank() }.joinToString("・"),
                            ff(FF.Caption), T.muted, maxLines = 1)
                    }
                    if (have) Icon(Icons.Filled.Check, null, tint = T.greenInk)
                    else TextButton(onClick = { Radio.add(r, lang) }) { Text(tr("加入"), color = T.btnInk) }
                }
            }
            item { Spacer(Modifier.height(40.dp)) }
        }
    }
}

/** 歌詞: the song the station says is playing, its lyrics (LRCLIB); tap a line to look its words up */
@Composable
private fun LyricsScreen() {
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf(Radio.nowPlaying ?: "") }
    var hits by remember { mutableStateOf<List<LyricHit>?>(null) }
    var pick by remember { mutableStateOf<LyricHit?>(null) }
    var busy by remember { mutableStateOf(false) }
    fun run(q: String) {
        if (q.isBlank()) return
        busy = true; pick = null
        scope.launch { hits = LyricsSource.find(q); pick = hits?.firstOrNull(); busy = false }
    }
    LaunchedEffect(Radio.nowPlaying) { Radio.nowPlaying?.let { query = it; run(it) } }
    // each line's reading (the language shown: 拼音／注音, 粵拼…; 台語 in the spelling chosen)
    var readings by remember { mutableStateOf<Map<String, androidx.compose.ui.text.AnnotatedString>>(emptyMap()) }
    val showReadings = Prefs.lyricsReadings.value
    val zk = listOf(Prefs.zhRom.value, Prefs.zhPlace.value, Prefs.rom.value, Prefs.place.value, Prefs.toneSys.value, showReadings)
    LaunchedEffect(pick, zk) {
        // (readings off: none made, and the ones made before let go)
        if (!showReadings) { readings = emptyMap(); return@LaunchedEffect }
        val p = pick ?: return@LaunchedEffect
        readings = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            val out = HashMap<String, Styled>()
            val z = Store.zh; val d = Store.dict
            val tw = if (!Store.isZh && d != null) ConvertEngine(d, Prefs) else null
            for (line in p.text.lines().map { it.trim() }.filter { it.isNotEmpty() }.distinct()) {
                try {
                    if (Store.isZh && z != null) out[line] = z.sentence(z.convertPieces(line), Prefs.zhRom.value, Prefs.zhPlace.value)
                    else if (tw != null) out[line] = listOf(Seg(tw.pieces(tw.convert(line).items, 1, Prefs.rom.value, Prefs.place.value).joinToString("") { it.text }))
                } catch (_: Exception) {}
            }
            out
        }.mapValues { it.value.annotated() }
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("歌詞"), { UI.lyricsOpen = false }, settings = false)
        Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { SearchField(query, { query = it }, tr("歌名或歌手")) }
            TextButton(onClick = { run(query) }) { Text(tr("找"), color = T.btnInk) }
        }
        // (the readings under the lines: off makes a long song lighter on memory)
        Row(Modifier.fillMaxWidth().clickable { Prefs.lyricsReadings.value = !showReadings }.padding(horizontal = 16.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Txt(tr("顯示讀音"), ff(FF.Subheadline), T.glyph, Modifier.weight(1f))
            androidx.compose.material3.Switch(showReadings, { Prefs.lyricsReadings.value = it },
                colors = androidx.compose.material3.SwitchDefaults.colors(checkedTrackColor = T.btnEdge, checkedThumbColor = T.btnInk))
        }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth().padding(12.dp), color = T.btnEdge, trackColor = T.fnEdge)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            val hs = hits
            if (hs != null && hs.isEmpty() && !busy) item { Txt(tr("找不到這首歌的歌詞。可以自己打歌名再找。"), ff(FF.Body), T.muted, Modifier.padding(8.dp)) }
            if (hs != null && hs.size > 1) item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (h in hs.take(4)) Txt(h.track + "・" + h.artist, ff(FF.Caption), if (pick?.id == h.id) T.btnInk else T.muted,
                        Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).border(1.dp, if (pick?.id == h.id) T.btnEdge else T.fnEdge, RoundedCornerShape(8.dp))
                            .clickable { pick = h }.padding(6.dp), maxLines = 2)
                }
            }
            pick?.let { p ->
                item { Txt(p.track + "　" + p.artist, ff(FF.Headline), T.glyph) }
                items(p.text.lines()) { line ->
                    if (line.isBlank()) Spacer(Modifier.height(10.dp))
                    // (tap a line: its words in 詞典, several at once)
                    else Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable {
                        Prefs.lookupQuery.value = line.trim(); UI.tab = 4; UI.lyricsOpen = false; UI.radioOpen = false
                    }.padding(horizontal = 6.dp, vertical = 4.dp)) {
                        if (PointerUI.mouse) LyricWords(line.trim()) else Txt(line, sz(20f), T.glyph)
                        if (showReadings) readings[line.trim()]?.let { Txt(it, lat(14f), T.greenInk) }
                    }
                }
                item { Txt(if (PointerUI.mouse) tr("點一個詞看它的意思；點一行旁邊空的地方，詞典會查那一行的詞。歌詞來自 LRCLIB（lrclib.net），不會存起來。") else tr("點一行，詞典會查那一行的詞。歌詞來自 LRCLIB（lrclib.net），不會存起來。"), ff(FF.Footnote), T.muted, Modifier.padding(top = 10.dp)) }
            }
            item { Spacer(Modifier.height(40.dp)) }
        }
    }
}

/** a line of the lyrics word by word (the Windows version, with a mouse): a word under the pointer swells, a click
 *  opens it (華語: its entry in 華語 詞典; 台語: the 台語 word the converter finds for it); a click beside the words
 *  still looks up the whole line */
@Composable
private fun LyricWords(line: String) {
    val zk = listOf(Prefs.zhPlace.value, Prefs.rom.value, Prefs.place.value)
    val words: List<Pair<androidx.compose.ui.text.AnnotatedString, () -> Unit>> = remember(line, zk, Store.isZh) {
        try {
            val z = Store.zh; val d = Store.dict
            if (Store.isZh && z != null) {
                z.convertPieces(line).map { p ->
                    val k = if (p.tw != null) z.entryFor(p)?.k else null
                    val t = z.sentenceHan(listOf(p), Prefs.zhPlace.value, T.glyph.argbInt()).annotated()
                    Pair(t, if (k != null) ({ UI.open(Sheet.ZhWord(k)) }) else NOOP)
                }
            } else if (!Store.isZh && d != null) {
                val e = ConvertEngine(d, Prefs)
                val items = e.convert(line).items
                e.pieces(items, 0, Prefs.rom.value, Prefs.place.value).filter { it.text != "\n" }.map { p ->
                    val i = p.item
                    val k = if (i != null && i >= 0) d.keyOf(items[i].current) else null
                    Pair(androidx.compose.ui.text.AnnotatedString(p.text), if (k != null) ({ UI.openWord(k) }) else NOOP)
                }
            } else emptyList()
        } catch (_: Exception) { emptyList() }
    }
    if (words.isEmpty()) { Txt(line, sz(20f), T.glyph); return }
    TapWords(
        count = words.size,
        isTappable = { i -> words.getOrNull(i)?.second.let { it != null && it !== NOOP } },
        onTap = { i -> words.getOrNull(i)?.second?.invoke() },
    ) { i, hot ->
        Text(words[i].first, style = sz(20f), color = T.glyph, modifier = Modifier.swell(hot).padding(vertical = 2.dp))
    }
}
private val NOOP: () -> Unit = {}
