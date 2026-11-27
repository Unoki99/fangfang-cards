package com.unoki99.fangfang.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
    BackHandler { if (UI.karaokeOpen) UI.karaokeOpen = false else if (UI.ytEditOpen) UI.ytEditOpen = false else if (UI.ytLyricsOpen) UI.ytLyricsOpen = false else if (UI.lyricsOpen) UI.lyricsOpen = false else UI.radioOpen = false }
    if (UI.ytLyricsOpen) { AppBackground { YtLyricsScreen() }; return }
    if (UI.lyricsOpen) { AppBackground { LyricsScreen() }; return }
    var lang by remember { mutableIntStateOf(Store.lang.coerceIn(0, RadioLang.languages.size - 1)) }
    var searching by remember { mutableStateOf(false) }
    var adding by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf<RadioStation?>(null) }
    // 我的歌, 電台送來的資料
    var songsOpen by remember { mutableStateOf(false) }
    var metaOpen by remember { mutableStateOf(false) }
    if (songsOpen) { AppBackground { SavedSongsScreen { songsOpen = false } }; return }
    AppBackground {
        Column(Modifier.fillMaxSize()) {
            TopBar(tr("電台"), { UI.radioOpen = false }, close = true, settings = false) {
                IconButton(onClick = { searching = true }) { Icon(Icons.Filled.Search, tr("找電台"), tint = T.glyph) }
                IconButton(onClick = { adding = true }) { Icon(Icons.Filled.Add, tr("自己加網址"), tint = T.glyph) }
            }
            if (searching) { RadioSearch(lang) { searching = false }; return@Column }
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item { NowPlayingPanel { metaOpen = true } }
                // (Windows: the song playing on YouTube in the browser, its lyrics following it)
                if (YtLink.available) item {
                    SoftButton(onClick = { UI.ytLyricsOpen = true }, Modifier.fillMaxWidth().heightIn(min = 44.dp)) {
                        IconLabel(Icons.Filled.MusicNote, tr("YouTube 歌詞") + if (YtLink.live()) "：" + (YtLink.song?.title ?: "") else "", ff(FF.Subheadline))
                    }
                }
                // (the radios by language, the language shown first; the 放大鏡 and + find and add them for the
                // language chosen here)
                item {
                    Segmented((0 until RadioLang.languages.size).map { it to tr(Lang.names[it]) }, lang, { lang = it })
                }
                if (Radio.stations.isEmpty()) item { Txt(tr("還沒有電台。按上面的放大鏡找。"), ff(FF.Body), T.muted, Modifier.padding(8.dp)) }
                val langs = listOf(Store.lang.coerceIn(0, RadioLang.languages.size - 1)) + (0 until RadioLang.languages.size).filter { it != Store.lang }
                for (l in langs) {
                val inGroup = Radio.stations.filter { it.lang == l }
                if (inGroup.isEmpty()) continue
                item(key = "lang-$l") {
                    Txt(tr(Lang.names[l]), ff(FF.Footnote, FontWeight.SemiBold), T.muted, Modifier.padding(start = 4.dp, top = 6.dp))
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
                // 我的歌 and 電台鬧鐘
                item {
                    SoftButton(onClick = { songsOpen = true }, Modifier.fillMaxWidth().heightIn(min = 44.dp)) {
                        SongList.version
                        IconLabel(Icons.Filled.Bookmark, tr("我的歌") + if (SongList.songs.isNotEmpty()) "（${SongList.songs.size}）" else "", ff(FF.Subheadline))
                    }
                }
                item { AlarmPanel() }
                item {
                    TextButton(onClick = { Radio.restoreStarters() }) { Text(tr("加回原本的電台"), color = T.btnInk) }
                    Txt(tr("電台來自 Radio Browser（radio-browser.info）。離開 App 也會繼續播，通知裡可以停。電台有送歌名的話，按「歌詞」可以看歌詞（LRCLIB）。"),
                        ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 4.dp))
                    Spacer(Modifier.height(40.dp))
                }
            }
            // 歌詞: at the bottom of the window (the song playing: the radio's, or YouTube's on the computer)
            Box(Modifier.fillMaxWidth().background(T.fn.copy(alpha = 0.35f)).padding(horizontal = 12.dp, vertical = 8.dp)) {
                ProminentButton({ if (YtLink.available && YtLink.live()) UI.ytLyricsOpen = true else UI.lyricsOpen = true }, Modifier.fillMaxWidth().heightIn(min = 44.dp)) {
                    IconLabel(Icons.Filled.MusicNote, tr("歌詞"), ff(FF.Headline))
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
    if (metaOpen) AlertDialog(onDismissRequest = { metaOpen = false }, containerColor = T.fn,
        title = { Txt(tr("電台送來的資料"), ff(FF.Headline)) },
        text = {
            Column(Modifier.heightIn(max = 420.dp).dragScrollY(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (RadioExtras.metaLog.isEmpty()) Txt(tr("這個電台到現在什麼都沒送：它沒有說在放什麼歌。"), ff(FF.Body), T.muted)
                for ((t, line) in RadioExtras.metaLog) Column {
                    Txt(java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US).format(java.util.Date(t)), lat(12f), T.muted)
                    androidx.compose.foundation.text.selection.SelectionContainer { Txt(line, ff(FF.Body), T.glyph) }
                }
                Txt(tr("電台和聲音一起送來的文字（例如歌名和歌手）。有些電台只在自己的網站上寫在放什麼歌，聲音裡什麼都沒有。"), ff(FF.Footnote), T.muted)
            }
        },
        confirmButton = { TextButton(onClick = { metaOpen = false }) { Text(tr("好"), color = T.btnInk) } })
    removing?.let { s ->
        AlertDialog(onDismissRequest = { removing = null }, containerColor = T.fn,
            title = { Txt(tr("移除「{0}」？", s.name), ff(FF.Headline)) },
            confirmButton = { TextButton(onClick = { Radio.remove(s); removing = null }) { Text(tr("移除"), color = T.rustInk) } },
            dismissButton = { TextButton(onClick = { removing = null }) { Text(tr("取消"), color = T.muted) } })
    }
}

/** the station playing, what it says is playing (存到我的歌, 電台送來的資料), 停 and 歌詞 */
@Composable
private fun NowPlayingPanel(onMeta: () -> Unit) {
    val s = Radio.current ?: return
    if (Radio.state == Radio.State.IDLE) return
    Panel {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Filled.GraphicEq, null, tint = T.greenInk, modifier = Modifier.size(28.dp))
            Column(Modifier.weight(1f)) {
                Txt(s.name, ff(FF.Headline), T.glyph, maxLines = 1)
                Txt(Radio.nowPlaying ?: if (Radio.state == Radio.State.CONNECTING) tr("連線中…") else tr("電台沒有送歌名"), ff(FF.Footnote), T.muted, maxLines = 2)
            }
            // (the song playing: into 我的歌, or out again)
            SongList.version
            val cur = SongList.current()
            val saved = cur != null && SongList.has(cur.first, cur.second)
            IconButton(onClick = { SongList.toggle() }, enabled = cur != null) {
                Icon(if (saved) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder, if (saved) tr("從我的歌拿掉") else tr("存到我的歌"),
                    tint = if (saved) T.btnInk else if (cur != null) T.glyph else T.muted)
            }
            IconButton(onClick = onMeta) { Icon(Icons.Filled.Info, tr("電台送來的資料"), tint = T.muted) }
        }
        // 音量: the radio's own, on top of the device's
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.VolumeDown, tr("電台音量"), tint = T.muted, modifier = Modifier.size(20.dp))
            Slider(Prefs.radioVolume.value, { Prefs.radioVolume.value = it }, Modifier.weight(1f),
                colors = SliderDefaults.colors(thumbColor = T.btnInk, activeTrackColor = T.btnEdge))
            Icon(Icons.Filled.VolumeUp, null, tint = T.muted, modifier = Modifier.size(20.dp))
            Txt("${Math.round(Prefs.radioVolume.value * 100)}%", ff(FF.Footnote), T.muted, Modifier.widthIn(min = 40.dp))
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
            Box(Modifier.weight(1f)) { SearchField(query, { query = it }, tr("電台的名字（空白：{0}的電台）", tr(Lang.names[lang])), onSubmit = { run() }) }
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
    LaunchedEffect(Radio.nowPlaying) { if (LyricsLookup.query == null) Radio.nowPlaying?.let { query = it; run(it) } }
    // (a song from 我的歌)
    LaunchedEffect(LyricsLookup.query) { LyricsLookup.query?.let { query = it; run(it); LyricsLookup.query = null } }
    // each line's reading (the language shown: 拼音／注音, 粵拼…; 台語 in the spelling chosen)
    var readings by remember { mutableStateOf<Map<String, androidx.compose.ui.text.AnnotatedString>>(emptyMap()) }
    val showReadings = Prefs.lyricsReadings.value
    val zk = listOf(Prefs.zhRom.value, Prefs.zhPlace.value, Prefs.rom.value, Prefs.place.value, Prefs.toneSys.value, Prefs.toneGlow.value, showReadings)
    LaunchedEffect(pick, zk, LyricsScript.keepSimplified) {
        // (readings off: none made, and the ones made before let go)
        if (!showReadings) { readings = emptyMap(); return@LaunchedEffect }
        val p = pick ?: return@LaunchedEffect
        // (in tone colours, 台語's too: LyricText.kt)
        readings = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            val out = HashMap<String, androidx.compose.ui.text.AnnotatedString>()
            for (line in LyricsScript.shown(p.text).lines().map { it.trim() }.filter { it.isNotEmpty() }.distinct()) lyricReading(line)?.let { out[line] = it }
            out
        }
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("歌詞"), { UI.lyricsOpen = false }, settings = false) {
            // 簡 / 繁: the lyrics as written, or in 正體 (only when they have 簡體 in them)
            if (pick?.let { LyricsScript.canSwitch(it.text) } == true) TextButton(onClick = { LyricsScript.keepSimplified = !LyricsScript.keepSimplified }) {
                Text(if (LyricsScript.keepSimplified) "簡" else "繁", color = T.btnInk, fontWeight = FontWeight.Bold)
            }
        }
        Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { SearchField(query, { query = it }, tr("歌名或歌手"), onSubmit = { run(query) }) }
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
                items(LyricsScript.shown(p.text).lines()) { line ->
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
internal fun LyricWords(line: String, size: Float = 20f, color: androidx.compose.ui.graphics.Color = T.glyph, center: Boolean = false) {
    val zk = listOf(Prefs.zhPlace.value, Prefs.rom.value, Prefs.place.value, Prefs.toneSys.value, Prefs.toneGlow.value)
    // (in their tone colours: 華語's and 台語's alike, LyricText.kt)
    val words = remember(line, zk, Store.isZh, Store.lang, LyricPicks.songKey, LyricPicks.lang, LyricPicks.version) { lyricWords(line) }
    if (words.isEmpty()) { Txt(line, sz(size), color); return }
    // (a 台語 word with several readings: its readings to pick from, YtLyricsPages.kt)
    var menu by remember { mutableStateOf(-1) }
    val openHere = LocalLyricOpen.current
    TapWords(
        count = words.size,
        center = center,
        isTappable = { i -> words.getOrNull(i)?.let { it.open != null || it.pick != null } == true },
        onTap = { i -> val w = words.getOrNull(i); if (w?.pick != null) menu = i else if (w?.open != null) { if (openHere != null) openHere(w) else w.open.invoke() } },
    ) { i, hot ->
        Box {
            Text(words[i].text, style = sz(size), color = color, modifier = Modifier.swell(hot).padding(vertical = 2.dp)
                .then(if (words[i].pick != null) Modifier.dottedUnder() else Modifier))
            if (menu == i) ReadingMenu(words[i]) { menu = -1 }
        }
    }
}
private val NOOP: () -> Unit = {}


/** 電台鬧鐘: a station at a set time each day, while the program is open */
@Composable
private fun AlarmPanel() {
    val on = Prefs.radioAlarmOn.value
    var stationMenu by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.7f)).padding(horizontal = 14.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Filled.Alarm, null, tint = if (on) T.btnInk else T.muted, modifier = Modifier.size(20.dp))
            Txt(tr("電台鬧鐘"), ff(FF.Body, FontWeight.SemiBold), T.glyph, Modifier.weight(1f))
            androidx.compose.material3.Switch(on, { Prefs.radioAlarmOn.value = it },
                colors = SwitchDefaults.colors(checkedTrackColor = T.btnEdge, checkedThumbColor = T.btnInk))
        }
        if (on) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                val m = Prefs.radioAlarmTime.value
                // (the hour and the minutes, each up or down)
                TextButton(onClick = { Prefs.radioAlarmTime.value = (m + 23 * 60) % (24 * 60) }) { Text("−", color = T.btnInk) }
                Txt("%02d".format(m / 60), lat(22f), T.glyph)
                TextButton(onClick = { Prefs.radioAlarmTime.value = (m + 60) % (24 * 60) }) { Text("+", color = T.btnInk) }
                Txt(":", lat(22f), T.muted)
                TextButton(onClick = { Prefs.radioAlarmTime.value = (m / 60) * 60 + ((m % 60) + 55) % 60 }) { Text("−", color = T.btnInk) }
                Txt("%02d".format(m % 60), lat(22f), T.glyph)
                TextButton(onClick = { Prefs.radioAlarmTime.value = (m / 60) * 60 + ((m % 60) + 5) % 60 }) { Text("+", color = T.btnInk) }
                Spacer(Modifier.weight(1f))
                Box {
                    TextButton(onClick = { stationMenu = true }) { Text(RadioExtras.alarmStation()?.name ?: tr("電台"), color = T.btnInk, maxLines = 1) }
                    DropdownMenu(stationMenu, { stationMenu = false }, containerColor = T.fn) {
                        for (st in Radio.stations) DropdownMenuItem(text = { Text(st.name, color = T.glyph) },
                            onClick = { Prefs.radioAlarmStation.value = st.id; stationMenu = false })
                    }
                }
            }
            Txt(tr("每天 {0} 電台自己開始播（程式要開著）。", RadioExtras.alarmText()), ff(FF.Footnote), T.muted)
        }
    }
}

/** 我的歌: the songs kept from the radio, newest first: their lyrics, YouTube, the name to copy, take out */
@Composable
private fun SavedSongsScreen(onClose: () -> Unit) {
    SongList.version
    val songs = SongList.songs
    var menu by remember { mutableStateOf<String?>(null) }
    val clip = androidx.compose.ui.platform.LocalClipboardManager.current
    val ctx = androidx.compose.ui.platform.LocalContext.current
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("我的歌"), onClose, settings = false)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (songs.isEmpty()) item { Txt(tr("還沒有存歌。聽電台的時候按書籤，歌名和歌手就會存在這裡。"), ff(FF.Body), T.muted, Modifier.padding(8.dp)) }
            items(songs, key = { it.id }) { s ->
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.7f)).clickable { menu = s.id }.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column(Modifier.weight(1f)) {
                        Txt(s.title, ff(FF.Body, FontWeight.SemiBold), T.glyph, maxLines = 1)
                        val d = listOfNotNull(s.artist.ifEmpty { null }, s.station,
                            java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(java.util.Date(s.date))).joinToString(" · ")
                        Txt(d, ff(FF.Caption), T.muted, maxLines = 1)
                    }
                    Box {
                        Icon(Icons.Filled.MoreVert, null, tint = T.muted)
                        DropdownMenu(menu == s.id, { menu = null }, containerColor = T.fn) {
                            DropdownMenuItem(text = { Text(tr("只看歌詞"), color = T.glyph) }, leadingIcon = { Icon(Icons.Filled.MusicNote, null, tint = T.btnInk) },
                                onClick = { menu = null; LyricsLookup.query = s.query; UI.lyricsOpen = true; onClose() })
                            DropdownMenuItem(text = { Text(tr("在 YouTube 找"), color = T.glyph) }, leadingIcon = { Icon(Icons.Filled.PlayCircle, null, tint = T.btnInk) },
                                onClick = {
                                    menu = null
                                    // (in the browser: Firefox when it's there, where the add-on is)
                                    try { BrowserKnown.open(ctx, "https://www.youtube.com/results?search_query=" + java.net.URLEncoder.encode(s.query, "UTF-8")) } catch (_: Throwable) {}
                                })
                            DropdownMenuItem(text = { Text(tr("複製歌名"), color = T.glyph) }, leadingIcon = { Icon(Icons.Filled.ContentCopy, null, tint = T.btnInk) },
                                onClick = { menu = null; clip.setText(androidx.compose.ui.text.AnnotatedString(if (s.artist.isEmpty()) s.title else s.artist + " - " + s.title)) })
                            DropdownMenuItem(text = { Text(tr("刪除"), color = T.rustInk) }, leadingIcon = { Icon(Icons.Filled.Delete, null, tint = T.rustInk) },
                                onClick = { menu = null; SongList.remove(s) })
                        }
                    }
                }
            }
            item { Spacer(Modifier.height(30.dp)) }
        }
    }
}

/** (a song from 我的歌: the 歌詞 page looks it up) */
object LyricsLookup { var query by mutableStateOf<String?>(null) }
