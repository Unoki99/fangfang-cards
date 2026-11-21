package com.unoki99.fangfang.ui

import androidx.compose.animation.*
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.unoki99.fangfang.*
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// YouTube 歌詞 (the Windows program): the song playing on YouTube or YouTube Music in the browser (the add-on's
// 連到方方詞卡（Windows） tells it: YtLink), its lyrics following it: your own (歌詞對時, kept in the backup folder's
// 歌詞, like the iPhone / iPad's), else LRCLIB's. The line being sung lights up word by word and stays in the middle;
// each line's reading under it, in tone colours; a word clicked opens it, a line's time jumps the song there. Under
// it: 上一句, play / pause, 下一句, 重複, 慢速, 一句一停, the lyrics' timing, 編輯歌詞 and 浮動歌詞 (the line being
// sung in a small window of its own over everything).

/** the lyrics of the song playing, kept apart from the screens: the 歌詞 screen, the floating window and the editor
 *  all show the same */
object YtLyricsState {
    private val scope = MainScope()
    var hits by mutableStateOf<List<TimedLyrics>?>(null)
    var pick by mutableStateOf<TimedLyrics?>(null)
    var busy by mutableStateOf(false)
    var query by mutableStateOf("")
    /** the lyrics a little early or late against the video: seconds added to where the song is */
    var offset by mutableDoubleStateOf(0.0)
    var repeatAt by mutableStateOf<Int?>(null)
    var stopEach by mutableStateOf(false)
    var slow by mutableStateOf(false)
    /** where your lyrics just saved went (shown on the lyrics page) */
    var savedNote by mutableStateOf<String?>(null)
    /** lyrics without times imported on the lyrics page: the editor opens with them, to time them */
    var importText: String? = null
    private var forKey = ""
    private var asked = 0

    /** the song's own key for your lyrics */
    fun ownId(s: YtSong?) = s?.id?.takeIf { it.isNotEmpty() }?.let { "yt-$it" }
    // (the video and its name: a name corrected a moment after a new video starts is looked up again)
    private fun keyOf(s: YtSong) = s.id + "|" + s.title

    /** the song playing changed: its lyrics (yours first, then the iPad's of the same name, then LRCLIB's) */
    /** the readings picked in this song's lyrics are kept for it (the video; else its name) */
    fun picksKey(s: YtSong?): String? = s?.let { ownId(it) ?: LyricPicks.keyOf(it.title, it.artist).takeIf { k -> k != "|" } }

    fun follow() {
        val s = YtLink.song ?: return
        if (s.title.isEmpty() || keyOf(s) == forKey) return
        forKey = keyOf(s)
        query = s.title + if (s.artist.isNotEmpty()) " " + s.artist else ""
        repeatAt = null; offset = 0.0
        if (slow) { slow = false; YtLink.rate(1.0) }
        lookFor(s.title, s.artist, s.d, s.site == "music", ownId(s))
    }

    fun lookFor(title: String, artist: String, d: Double, music: Boolean, own: String? = null) {
        busy = true; pick = null; hits = null
        val n = ++asked
        scope.launch {
            val mine = (own?.let { OwnLyrics.get(it) } ?: OwnLyrics.byName(title, artist))?.let { YtLyrics.ofOwn(it) }
            val found = YtLyrics.find(title, artist, d, music)
            // (a newer song asked for meanwhile: this answer is for the song before)
            if (n != asked) return@launch
            hits = listOfNotNull(mine) + found
            pick = hits?.firstOrNull()
            busy = false
        }
    }

    /** your own lyrics saved (or deleted): shown at once */
    fun reloadOwn() {
        val s = YtLink.song
        val mine = ownId(s)?.let { OwnLyrics.get(it) }?.let { YtLyrics.ofOwn(it) }
        val rest = (hits ?: emptyList()).filter { it.own == null }
        hits = listOfNotNull(mine) + rest
        pick = mine ?: rest.firstOrNull()
        repeatAt = null
    }

    // (the lines as shown: 簡體 lyrics in 正體, unless 簡 is chosen; made again only when one of those changes)
    private var linesFor: Triple<TimedLyrics?, Boolean, Boolean>? = null
    private var linesCache: List<TimedLine> = emptyList()
    val lines: List<TimedLine> get() {
        val k = Triple(pick, LyricsScript.keepSimplified, LyricsScript.applies())
        if (k != linesFor) { linesFor = k; linesCache = pick?.lines?.map { it.copy(text = LyricsScript.shown(it.text)) } ?: emptyList() }
        return linesCache
    }
    /** the line being sung at p (only timed lines count) */
    fun lineAt(p: Double): Int = lines.indexOfLast { it.t != null && it.t <= p }
    fun endOf(i: Int): Double {
        for (j in i + 1 until lines.size) lines[j].t?.let { return it }
        return YtLink.song?.d?.takeIf { it > 0 } ?: Double.MAX_VALUE
    }
    fun seekLine(i: Int) { lines.getOrNull(i)?.t?.let { YtLink.seek(it - offset + 0.01) } }
}

/** while YouTube's lyrics show (the screen, the floating window): the readings picked are this song's; after, none
 *  (the radio's lyrics aren't this song) */
private var picksHolders = 0
@Composable
private fun PicksFor(song: YtSong?) {
    val k = YtLyricsState.picksKey(song)
    val tag = SongLangs.version.let { SongLangs.get(k) }
    DisposableEffect(Unit) { picksHolders++; onDispose { picksHolders--; if (picksHolders <= 0) { LyricPicks.songKey = null; LyricPicks.lang = null } } }
    LaunchedEffect(k, tag) {
        LyricPicks.songKey = k
        LyricPicks.lang = tag
        // (a song tagged 華語, 粵語, 客語 or 日語: on a phone the app goes to that language, its dictionary then reads the
        // lyrics; on the computer the song's language has a dictionary of its own and the app stays as it is. 台語's is
        // always there, so a 台語 song needs no switch)
        if (tag != null && tag in 1 until com.unoki99.fangfang.engine.Lang.count && Store.lang != tag) {
            if (com.unoki99.fangfang.engine.EngineSettings.desktop) LyricDicts.get(tag) else Store.setLanguage(tag)
        }
    }
}

/** where the song is now (with the lyrics' timing), ten times a second */
@Composable
private fun rememberSongPos(): Double {
    var pos by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(Unit) { while (true) { pos = YtLink.position() + YtLyricsState.offset; delay(100) } }
    return pos
}

@Composable
fun YtLyricsScreen() {
    if (UI.ytEditOpen) { YtLyricsEditor(); return }
    if (UI.karaokeOpen) { YtKaraoke(); return }
    val st = YtLyricsState
    val song = YtLink.song
    val live = YtLink.live()
    LaunchedEffect(song?.id, song?.title) { st.follow() }
    PicksFor(song)
    SpaceToPlay()
    val pos = rememberSongPos()
    val lines = st.lines
    val cur = st.lineAt(pos)

    // 重複 and 一句一停, done here as the song goes
    var lastLine by remember { mutableIntStateOf(-1) }
    LaunchedEffect(cur, pos) {
        val r = st.repeatAt
        if (r != null && lines.getOrNull(r)?.t != null && (pos >= st.endOf(r) - 0.08 || cur < r)) st.seekLine(r)
        else if (st.stopEach && song?.playing == true && lastLine >= 0 && cur == lastLine + 1) YtLink.pause()
        lastLine = cur
    }

    // the line sung kept in the middle, unless you've just scrolled yourself
    val list = rememberLazyListState()
    var autoScroll by remember { mutableStateOf(false) }
    var userAt by remember { mutableLongStateOf(0L) }
    LaunchedEffect(list.isScrollInProgress) { if (list.isScrollInProgress && !autoScroll) userAt = System.currentTimeMillis() }
    LaunchedEffect(cur, st.pick) {
        if (cur < 0 || System.currentTimeMillis() - userAt < 4000) return@LaunchedEffect
        val h = list.layoutInfo.viewportSize.height
        autoScroll = true
        try { list.animateScrollToItem(cur + 1, -h / 3) } catch (_: Exception) {}
        autoScroll = false
    }

    // each line's reading, in tone colours
    var readings by remember { mutableStateOf<Map<String, AnnotatedString>>(emptyMap()) }
    val showReadings = Prefs.lyricsReadings.value
    val zk = listOf(Prefs.zhRom.value, Prefs.zhPlace.value, Prefs.rom.value, Prefs.place.value, Prefs.toneSys.value, Prefs.toneGlow.value, showReadings)
    LaunchedEffect(st.pick, zk, Store.isZh, Store.lang, LyricPicks.songKey, LyricPicks.lang, LyricPicks.version) {
        if (!showReadings) { readings = emptyMap(); return@LaunchedEffect }
        val p = st.pick ?: return@LaunchedEffect
        readings = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            val out = HashMap<String, AnnotatedString>()
            for (line in p.lines.map { it.text.trim() }.filter { it.isNotEmpty() }.distinct()) lyricReading(line)?.let { out[line] = it }
            out
        }
    }

    Column(Modifier.fillMaxSize()) {
        TopBar(tr("YouTube 歌詞"), { UI.ytLyricsOpen = false }, settings = false) {
            // 簡 / 繁: the lyrics as written, or in 正體 (only when they have 簡體 in them)
            val raw = st.pick?.lines?.joinToString("\n") { it.text } ?: ""
            if (LyricsScript.canSwitch(raw)) TextButton(onClick = { LyricsScript.keepSimplified = !LyricsScript.keepSimplified }) {
                Text(if (LyricsScript.keepSimplified) "簡" else "繁", color = T.btnInk, fontWeight = FontWeight.Bold)
            }
            // 卡拉 OK: the whole window, big
            if (lines.any { it.t != null }) IconButton(onClick = { UI.karaokeOpen = true }) { Icon(Icons.Filled.Mic, tr("卡拉 OK"), tint = T.glyph) }
            // 浮動歌詞: the line being sung in a small window over everything
            IconButton(onClick = { UI.lyricsFloat = !UI.lyricsFloat }) {
                Icon(Icons.Filled.PictureInPicture, tr("浮動歌詞"), tint = if (UI.lyricsFloat) T.btnInk else T.glyph)
            }
            // 分享: 從檔案匯入 and 匯出成 .lrc 檔
            if (live && song?.id?.isNotEmpty() == true) LyricsShareMenu()
            if (live && song?.id?.isNotEmpty() == true) IconButton(onClick = { UI.ytEditOpen = true }) {
                Icon(Icons.Filled.Edit, tr("編輯歌詞"), tint = T.glyph)
            }
        }
        Column(Modifier.padding(horizontal = 16.dp, vertical = 2.dp)) {
            if (song == null || !live) {
                Txt(tr("在 YouTube 或 YouTube Music 放一首歌。Firefox 的方方詞卡 查詞要打開「連到方方詞卡（Windows）」。"), ff(FF.Body), T.muted)
            } else {
                Txt(song.title, ff(FF.Headline), T.glyph, maxLines = 2)
                if (song.artist.isNotEmpty()) Txt(song.artist, ff(FF.Footnote), T.muted, maxLines = 1)
            }
        }
        if (live && song != null) SongLangRow(st.picksKey(song))
        st.savedNote?.let { n ->
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp).clip(RoundedCornerShape(10.dp)).background(T.fn.copy(alpha = 0.6f))
                .padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                androidx.compose.foundation.text.selection.SelectionContainer(Modifier.weight(1f)) { Txt(n, ff(FF.Footnote), T.glyph) }
                IconButton(onClick = { st.savedNote = null }, Modifier.size(28.dp)) { Icon(Icons.Filled.Close, tr("關"), tint = T.muted) }
            }
        }
        Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            val find = { if (st.query.isNotBlank()) st.lookFor(st.query, "", YtLink.song?.d ?: 0.0, false, st.ownId(YtLink.song)) }
            Box(Modifier.weight(1f).onFocusChanged { SpaceKeys.typing = it.hasFocus }) { SearchField(st.query, { st.query = it }, tr("歌名或歌手"), onSubmit = find) }
            TextButton(onClick = find) { Text(tr("找"), color = T.btnInk) }
        }
        Row(Modifier.fillMaxWidth().clickable { Prefs.lyricsReadings.value = !showReadings }.padding(horizontal = 16.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Txt(tr("顯示讀音"), ff(FF.Subheadline), T.glyph, Modifier.weight(1f))
            Switch(showReadings, { Prefs.lyricsReadings.value = it },
                colors = SwitchDefaults.colors(checkedTrackColor = T.btnEdge, checkedThumbColor = T.btnInk))
        }
        BallSettings()
        // 浮動歌詞: the letters' size and the reading, set here (the window itself has only play / pause and close)
        if (UI.lyricsFloat) FloatSettings()
        if (st.busy) LinearProgressIndicator(Modifier.fillMaxWidth().padding(12.dp), color = T.btnEdge, trackColor = T.fnEdge)
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)) {
            // (row 0: which lyrics, when there are several; yours marked)
            item {
                val hs = st.hits
                if (hs != null && hs.isEmpty() && !st.busy) Txt(tr("找不到這首歌的歌詞。可以在上面自己打歌名再找，或按右上角的筆自己寫。"), ff(FF.Body), T.muted, Modifier.padding(8.dp))
                if (hs != null && hs.size > 1) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (h in hs.take(4)) Txt((if (h.own != null) tr("自己的：") else "") + h.track + "・" + h.artist, ff(FF.Caption),
                        if (st.pick === h) T.btnInk else T.muted,
                        Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).border(1.dp, if (st.pick === h) T.btnEdge else T.fnEdge, RoundedCornerShape(8.dp))
                            .clickable { st.pick = h; st.repeatAt = null; st.offset = 0.0 }.padding(6.dp), maxLines = 2)
                }
                if (st.pick != null && st.pick?.lines?.none { it.t != null } == true)
                    Txt(tr("這份歌詞還沒有時間：按右上角的筆，在「對時間」跟著歌點一下。"), ff(FF.Footnote), T.muted, Modifier.padding(8.dp))
            }
            itemsIndexed(lines) { i, line ->
                val on = i == cur
                val rep = st.repeatAt == i
                if (line.text.isBlank()) Spacer(Modifier.height(14.dp))
                else Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                    .then(if (on) Modifier.border(1.5.dp, if (rep) T.btnEdge else T.fnEdge, RoundedCornerShape(10.dp)) else Modifier)
                    .clickable { if (line.t != null) { st.seekLine(i); if (st.repeatAt != null) st.repeatAt = i } }
                    .padding(horizontal = 8.dp, vertical = if (on) 8.dp else 4.dp),
                    verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Txt(line.t?.let { clock(it) } ?: "", lat(12f), if (on) T.btnInk else T.muted, Modifier.padding(top = 6.dp).widthIn(min = 38.dp))
                    Column(Modifier.weight(1f)) {
                        if (on) SungLine(line, st.endOf(i), pos, 26f)
                        else Box(Modifier.graphicsLayer { alpha = 0.55f }) { LyricWords(line.text.trim(), 19f, T.glyph) }
                        if (showReadings) readings[line.text.trim()]?.let {
                            Box(Modifier.graphicsLayer { alpha = if (on) 1f else 0.55f }) { Txt(it, lat(if (on) 15f else 13f), T.greenInk) }
                        }
                    }
                }
            }
            if (st.pick != null) item {
                Txt(tr("點一行的時間（或一行旁邊空的地方），歌會跳到那裡；點一個詞看它的意思。") +
                    if (st.pick?.own != null) tr("這是你自己的歌詞（存在備份資料夾的「歌詞」）。") else tr("歌詞來自 LRCLIB（lrclib.net），不會存起來。"),
                    ff(FF.Footnote), T.muted, Modifier.padding(top = 10.dp))
            }
            item { Spacer(Modifier.height(30.dp)) }
        }
        if (live && lines.any { it.t != null }) SongControls(cur, pos, song?.playing == true)
    }
}

/** 歌的語言: the language the song is sung in (its lyrics read in it), or 跟著 App */
internal fun songLangOptions(): List<Pair<Int?, String>> =
    listOf<Pair<Int?, String>>(null to tr("跟著 App")) + com.unoki99.fangfang.engine.Lang.names.mapIndexed { i, n -> i to tr(n) }

@Composable
private fun SongLangRow(key: String?) {
    if (key == null) return
    SongLangs.version
    val tag = SongLangs.get(key)
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Txt(tr("歌的語言"), ff(FF.Footnote), T.muted)
        for ((v, name) in songLangOptions()) {
            val on = tag == v
            Txt(name, ff(FF.Footnote, if (on) FontWeight.SemiBold else null), if (on) T.btnInk else T.glyph,
                Modifier.clip(RoundedCornerShape(50)).border(1.dp, if (on) T.btnEdge else T.fnEdge, RoundedCornerShape(50))
                    .clickable { SongLangs.set(key, v) }.padding(horizontal = 10.dp, vertical = 3.dp))
        }
    }
}

/** 浮動歌詞's settings: 字的大小 (a slider) and 讀音 (on / off) */
@Composable
private fun FloatSettings() {
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp).clip(RoundedCornerShape(12.dp))
        .background(T.fn.copy(alpha = 0.6f)).padding(horizontal = 12.dp, vertical = 4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Filled.PictureInPicture, null, tint = T.muted, modifier = Modifier.size(18.dp))
            Txt(tr("浮動歌詞的字"), ff(FF.Subheadline), T.glyph)
            Slider(Prefs.lyricsFloatSize.value, { Prefs.lyricsFloatSize.value = Math.round(it).toFloat() }, Modifier.weight(1f), valueRange = 14f..48f,
                colors = SliderDefaults.colors(thumbColor = T.btnInk, activeTrackColor = T.btnEdge, inactiveTrackColor = T.fnEdge))
            Txt("${Prefs.lyricsFloatSize.value.toInt()}", lat(13f), T.muted, Modifier.widthIn(min = 24.dp))
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Spacer(Modifier.width(18.dp))
            Txt(tr("浮動歌詞的寬度"), ff(FF.Subheadline), T.glyph)
            Slider(Prefs.lyricsFloatWidth.value, { Prefs.lyricsFloatWidth.value = (Math.round(it / 10f) * 10).toFloat() }, Modifier.weight(1f), valueRange = 320f..1600f,
                colors = SliderDefaults.colors(thumbColor = T.btnInk, activeTrackColor = T.btnEdge, inactiveTrackColor = T.fnEdge))
            Txt("${Prefs.lyricsFloatWidth.value.toInt()}", lat(13f), T.muted, Modifier.widthIn(min = 36.dp))
        }
        Row(Modifier.fillMaxWidth().clickable { Prefs.lyricsFloatReadings.value = !Prefs.lyricsFloatReadings.value },
            verticalAlignment = Alignment.CenterVertically) {
            Txt(tr("浮動歌詞的讀音"), ff(FF.Subheadline), T.glyph, Modifier.weight(1f).padding(start = 28.dp))
            Switch(Prefs.lyricsFloatReadings.value, { Prefs.lyricsFloatReadings.value = it },
                colors = SwitchDefaults.colors(checkedTrackColor = T.btnEdge, checkedThumbColor = T.btnInk))
        }
    }
}

/** 上一句 · play / pause · 下一句 / 重複 · 慢速 · 一句一停 / the lyrics' timing */
@Composable
private fun SongControls(cur: Int, pos: Double, playing: Boolean) {
    val st = YtLyricsState
    val lines = st.lines
    fun timed(from: Int, step: Int): Int? { var j = from; while (j in lines.indices) { if (lines[j].t != null) return j; j += step }; return null }
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Ctl(Icons.Filled.SkipPrevious, tr("上一句"), Modifier.weight(1f)) {
                val here = lines.getOrNull(cur)?.t
                val to = if (cur > 0 && here != null && pos - here < 1.5) timed(cur - 1, -1) else if (cur >= 0) cur else timed(0, 1)
                if (to != null) { if (st.repeatAt != null) st.repeatAt = to; st.seekLine(to) }
            }
            Ctl(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (playing) tr("暫停") else tr("播放"), Modifier.weight(1f)) {
                if (playing) YtLink.pause() else YtLink.play()
            }
            Ctl(Icons.Filled.SkipNext, tr("下一句"), Modifier.weight(1f)) {
                timed(cur + 1, 1)?.let { to -> if (st.repeatAt != null) st.repeatAt = to; st.seekLine(to) }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Ctl(Icons.Filled.Repeat, tr("重複"), Modifier.weight(1f), on = st.repeatAt != null) {
                st.repeatAt = if (st.repeatAt != null) null else maxOf(cur, 0)
            }
            Ctl(Icons.Filled.SlowMotionVideo, tr("慢速"), Modifier.weight(1f), on = st.slow) {
                st.slow = !st.slow; YtLink.rate(if (st.slow) 0.75 else 1.0)
            }
            Ctl(Icons.Filled.PauseCircle, tr("一句一停"), Modifier.weight(1f), on = st.stopEach) { st.stopEach = !st.stopEach }
        }
        OffsetRow()
    }
}

/** 對時: the lyrics a second or a quarter of a second later / sooner, as on the iPhone / iPad; the time: back to 0
 *  (the lyrics page and 卡拉 OK) */
@Composable
private fun OffsetRow() {
    val st = YtLyricsState
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        TextButton(onClick = { st.offset -= 1.0 }) { Text("−1", color = T.btnInk) }
        TextButton(onClick = { st.offset -= 0.25 }) { Text("−¼", color = T.btnInk) }
        Txt(if (st.offset == 0.0) tr("歌詞時間") else String.format(java.util.Locale.US, "%+.2f s", st.offset), ff(FF.Footnote), T.muted,
            Modifier.clickable { st.offset = 0.0 }.padding(horizontal = 6.dp))
        TextButton(onClick = { st.offset += 0.25 }) { Text("+¼", color = T.btnInk) }
        TextButton(onClick = { st.offset += 1.0 }) { Text("+1", color = T.btnInk) }
    }
}

/** the line being sung, word by word: the words already sung lit, the one being sung swelling, the rest dim. A word's
 *  time: from the lyrics' own word times (歌詞對時 on the iPad, or here) when they have them, else the line's time spread
 *  over its words by their length */
@Composable
internal fun SungLine(line: TimedLine, end: Double, pos: Double, size: Float, center: Boolean = false, ball: Boolean = true) {
    val zk = listOf(Prefs.zhPlace.value, Prefs.rom.value, Prefs.place.value, Prefs.toneSys.value, Prefs.toneGlow.value)
    val words = remember(line.text, zk, Store.isZh, Store.lang, LyricPicks.songKey, LyricPicks.lang, LyricPicks.version) { lyricWords(line.text.trim()) }
    var menu by remember { mutableIntStateOf(-1) }
    val openHere = LocalLyricOpen.current
    val start = line.t ?: 0.0
    // when each word starts
    val starts = remember(words, line) {
        val total = words.sumOf { it.letters }.coerceAtLeast(1)
        val own = line.words
        val ps = if (own != null) LRC.pieceStarts(LRC.pieces(line.text)) else null
        var acc = 0
        words.map { w ->
            val at = acc; acc += w.letters
            if (own != null && ps != null) {
                val k = ps.indexOfLast { it <= at }.coerceAtLeast(0)
                own.getOrElse(k) { start }
            } else {
                val dur = minOf(end - start, maxOf(1.5, total * 0.45)).coerceAtLeast(0.5)
                start + dur * at / total
            }
        }
    }
    if (words.isEmpty()) { Txt(line.text, sz(size, FontWeight.SemiBold), T.glyph); return }
    // 跳跳球: each syllable's time and place (the words' places in the window, measured as they're laid out)
    val ballOn = ball && Prefs.lyricsBall.value
    val syls = remember(words, line, end) { ballSyllables(words, line, end) }
    val rects = remember(words) { androidx.compose.runtime.mutableStateMapOf<Int, androidx.compose.ui.geometry.Rect>() }
    var origin by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
    Box(Modifier.onGloballyPositioned { origin = it.positionInRoot() }) {
    TapWords(
        count = words.size,
        center = center,
        // (room above the line for the ball)
        modifier = if (ballOn) Modifier.padding(top = (size * 0.55f).dp) else Modifier,
        isTappable = { i -> words.getOrNull(i)?.let { it.open != null || it.pick != null } == true },
        onTap = { i -> val w = words.getOrNull(i); if (w?.pick != null) menu = i else if (w?.open != null) { if (openHere != null) openHere(w) else w.open.invoke() } },
    ) { i, hot ->
        val sung = pos >= starts[i]
        val now = sung && (i == words.size - 1 || pos < starts[i + 1])
        val scale by animateFloatAsState(if (now || hot) 1.14f else 1f, label = "sung")
        val alpha by animateFloatAsState(if (sung) 1f else 0.42f, label = "lit")
        // (where the word is, for the ball)
        Box(if (ballOn) Modifier.onGloballyPositioned { rects[i] = it.boundsInRoot() } else Modifier) {
            Text(words[i].text, style = sz(size, FontWeight.SemiBold), color = T.glyph,
                modifier = Modifier.graphicsLayer {
                    // (the first word swells to the right, not out past the left edge)
                    transformOrigin = if (i == 0) androidx.compose.ui.graphics.TransformOrigin(0f, 0.5f) else androidx.compose.ui.graphics.TransformOrigin.Center
                    scaleX = scale; scaleY = scale; this.alpha = alpha
                }.padding(vertical = 2.dp)
                    .then(if (words[i].pick != null) Modifier.dottedUnder() else Modifier))
            if (menu == i) ReadingMenu(words[i]) { menu = -1 }
        }
    }
    if (ballOn) LyricBall(syls, rects, origin, size, Modifier.matchParentSize())
    }
}

/** one syllable for the ball: its word, which of the word's syllables (of n), and when it's sung */
private class BallSyl(val word: Int, val j: Int, val n: Int, val t: Double)

/** the line's syllables: each 漢字 one (a word of 漢字 is as many syllables as it has); a word in letters (English,
 *  羅馬字) one. Their times as the line lights up: the lyrics' own, else spread by length */
private fun ballSyllables(words: List<LyricWord>, line: TimedLine, end: Double): List<BallSyl> {
    val start = line.t ?: return emptyList()
    val total = words.sumOf { it.letters }.coerceAtLeast(1)
    val own = line.words
    val ps = if (own != null) LRC.pieceStarts(LRC.pieces(line.text)) else null
    val dur = minOf(end - start, maxOf(1.5, total * 0.45)).coerceAtLeast(0.5)
    val out = ArrayList<BallSyl>()
    var acc = 0
    for (i in words.indices) {
        val w = words[i]
        if (w.letters <= 0) continue
        val text = w.text.text
        val han = text.codePoints().anyMatch { Character.UnicodeScript.of(it) == Character.UnicodeScript.HAN }
        val n = if (han) w.letters else 1
        for (j in 0 until n) {
            val at = acc + j
            val t = if (own != null && ps != null) own.getOrElse(ps.indexOfLast { it <= at }.coerceAtLeast(0)) { start }
                else start + dur * at / total
            out.add(BallSyl(i, j, n, t))
        }
        acc += w.letters
    }
    return out
}

/** where the ball is at time e: on syllable k at its time, flying in an arc to the next one until that one's time */
private fun ballAt(syls: List<BallSyl>, rects: Map<Int, androidx.compose.ui.geometry.Rect>, origin: androidx.compose.ui.geometry.Offset,
                   e: Double, hop: Float): Triple<Float, Float, Float>? {
    if (syls.isEmpty()) return null
    fun spot(s: BallSyl): androidx.compose.ui.geometry.Offset? {
        val r = rects[s.word] ?: return null
        return androidx.compose.ui.geometry.Offset(r.left - origin.x + r.width * (s.j + 0.5f) / s.n, r.top - origin.y)
    }
    val k = syls.indexOfLast { it.t <= e }
    if (k < 0) {
        // (before the line: waiting on its first syllable, a small hop just before it starts)
        val a = spot(syls[0]) ?: return null
        val left = syls[0].t - e
        val f = if (left > 0.5) 0f else (1 - left / 0.5).toFloat()
        return Triple(a.x, a.y - hop * 0.5f * 4f * f * (1 - f), f)
    }
    val a = spot(syls[k]) ?: return null
    if (k == syls.size - 1) return Triple(a.x, a.y, 0f)
    val b = spot(syls[k + 1]) ?: return Triple(a.x, a.y, 0f)
    val span = (syls[k + 1].t - syls[k].t).coerceAtLeast(0.05)
    val f = ((e - syls[k].t) / span).toFloat().coerceIn(0f, 1f)
    // (a longer gap: a higher hop)
    val h = hop * (0.45f + 0.55f * minOf(1f, (span / 0.6).toFloat()))
    return Triple(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f - h * 4f * f * (1 - f), f)
}

/** 跳跳球: a ball bouncing from syllable to syllable, landing on each the set seconds before it's sung; squashed a
 *  little as it lands and takes off */
@Composable
private fun LyricBall(syls: List<BallSyl>, rects: Map<Int, androidx.compose.ui.geometry.Rect>, origin: androidx.compose.ui.geometry.Offset,
                      size: Float, modifier: Modifier) {
    val lead = Prefs.lyricsBallLead.value.toDouble()
    var now by remember { mutableDoubleStateOf(0.0) }
    // (every frame: the ball moves smoothly)
    LaunchedEffect(Unit) { while (true) { androidx.compose.runtime.withFrameNanos { }; now = YtLink.position() + YtLyricsState.offset } }
    val ink = T.btnInk
    val glow = T.btnEdge
    androidx.compose.foundation.Canvas(modifier) {
        val r = (size * 0.16f).dp.toPx()
        val p = ballAt(syls, rects, origin, now + lead, (size * 0.5f).dp.toPx())
        if (p != null) {
            val f = p.third
            val air = 4f * f * (1 - f)
            val squash = (1f - minOf(1f, air * 3f)) * 0.28f
            val w = r * (1 + squash); val h = r * (1 - squash)
            val cy = p.second - h - 3f
            drawCircle(glow.copy(alpha = 0.35f), r * 1.7f, androidx.compose.ui.geometry.Offset(p.first, cy))
            drawOval(ink, androidx.compose.ui.geometry.Offset(p.first - w, cy - h), androidx.compose.ui.geometry.Size(w * 2, h * 2))
        }
    }
}

/** 跳跳球 on or off, and how many seconds ahead of the syllable it lands */
@Composable
private fun BallSettings() {
    val on = Prefs.lyricsBall.value
    val lead = Prefs.lyricsBallLead.value
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Txt(tr("跳跳球"), ff(FF.Subheadline), T.glyph)
        Switch(on, { Prefs.lyricsBall.value = it }, colors = SwitchDefaults.colors(checkedTrackColor = T.btnEdge, checkedThumbColor = T.btnInk))
        if (on) {
            Spacer(Modifier.width(8.dp))
            Txt(tr("提早"), ff(FF.Footnote), T.muted)
            TextButton(onClick = { Prefs.lyricsBallLead.value = (Math.round((lead - 0.05f) * 100) / 100f).coerceAtLeast(0f) }) { Text("−", color = T.btnInk) }
            Txt(tr("{0} 秒", "%.2f".format(lead)), lat(14f), T.glyph)
            TextButton(onClick = { Prefs.lyricsBallLead.value = (Math.round((lead + 0.05f) * 100) / 100f).coerceAtMost(3f) }) { Text("+", color = T.btnInk) }
        }
    }
}

/** a 台語 word of the lyrics with more than one reading (dotted underline): its readings to pick from, the one
 *  picked kept for this song (always used in its lyrics), and its dictionary entry */
@Composable
internal fun ReadingMenu(w: LyricWord, onClose: () -> Unit) {
    val openHere = LocalLyricOpen.current
    DropdownMenu(true, onClose, containerColor = T.fn) {
        Txt(tr("這首歌裡讀做"), ff(FF.Caption, FontWeight.Bold), T.muted, Modifier.padding(horizontal = 14.dp, vertical = 4.dp))
        w.choices.forEachIndexed { j, (han, reading) ->
            DropdownMenuItem(
                text = {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Txt(han, sz(18f, FontWeight.SemiBold), T.glyph)
                        Txt(reading, lat(15f), T.greenInk)
                    }
                },
                leadingIcon = { Icon(if (j == w.chosen) Icons.Filled.RadioButtonChecked else Icons.Filled.RadioButtonUnchecked, null,
                    tint = if (j == w.chosen) T.greenInk else T.muted) },
                onClick = { w.pick?.invoke(j); onClose() })
        }
        w.open?.let { o ->
            HorizontalDivider(color = T.fnEdge)
            DropdownMenuItem(text = { Text(tr("看詞典"), color = T.btnInk) }, leadingIcon = { Icon(Icons.Filled.MenuBook, null, tint = T.btnInk) },
                onClick = { onClose(); if (openHere != null) openHere(w) else o() })
        }
    }
}

/** a dotted line under a word that has other readings to pick */
internal fun Modifier.dottedUnder(): Modifier = drawBehind {
    val y = size.height - 1.dp.toPx()
    drawLine(T.muted.copy(alpha = 0.7f), androidx.compose.ui.geometry.Offset(0f, y), androidx.compose.ui.geometry.Offset(size.width, y),
        strokeWidth = 1.5.dp.toPx(), pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(3f, 4f)))
}

/** 浮動歌詞: the line being sung (its reading under it, when 浮動歌詞的讀音 is on) and the next one, in a small window of
 *  its own over everything (the Windows program opens it: desktop/Main.kt). The lines glide up as the song goes on
 *  (down when it jumps back). The letters' size: 浮動歌詞的字 in YouTube 歌詞. A word clicked opens it in the program */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun FloatingLyrics(onClose: () -> Unit) {
    val st = YtLyricsState
    val song = YtLink.song
    LaunchedEffect(song?.id, song?.title) { st.follow() }
    PicksFor(song)
    // (no SpaceToPlay here: that took the space bar from the whole program while this window was open; this window's
    // own keys: floatSpaceKey, desktop/Main.kt)
    val pos = rememberSongPos()
    val lines = st.lines
    val cur = st.lineAt(pos)
    val size = Prefs.lyricsFloatSize.value
    val showRd = Prefs.lyricsFloatReadings.value
    // (a word clicked: its dictionary entry slides out under the lines, in this window)
    CompositionLocalProvider(LocalLyricOpen provides { w: LyricWord -> if (w.key != null) { FloatWord.key = w.key; FloatWord.zh = w.zh } }) {
    Column(Modifier.fillMaxSize().clip(RoundedCornerShape(16.dp)).background(T.bg.copy(alpha = 0.9f))
        .border(1.dp, T.fnEdge, RoundedCornerShape(16.dp))) {
        // (the lines' own height: the window is made just as tall, however many lines they wrap onto)
        val density = androidx.compose.ui.platform.LocalDensity.current
        // (measured as tall as the lines want, not as the window is: else a window made smaller once could only get
        // smaller, line after line)
        var gear by remember { mutableStateOf(false) }
        Column(Modifier.fillMaxWidth().wrapContentHeight(Alignment.Top, unbounded = true)
            .onSizeChanged { with(density) { FloatWord.linesHeight = it.height.toDp().value } }) {
        Box(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(start = 4.dp, end = 8.dp, top = 2.dp, bottom = 2.dp)) {
            // (the lines slide inside this box; the room inside its edge is for a word swelling and its glow, which
            // were cut off at the left)
            Box(Modifier.fillMaxWidth().padding(end = 58.dp).clipToBounds().padding(start = 16.dp, end = 6.dp, top = 4.dp, bottom = 4.dp),
                contentAlignment = Alignment.CenterStart) {
                when {
                    !YtLink.live() -> Txt(tr("在 YouTube 放一首歌。"), ff(FF.Body), T.muted)
                    lines.isEmpty() -> Txt(if (st.busy) tr("找歌詞⋯") else song?.title ?: "", ff(FF.Body), T.muted, maxLines = 1)
                    else -> AnimatedContent(targetState = cur, label = "lines",
                        transitionSpec = {
                            val down = targetState >= initialState
                            (slideInVertically(tween(420)) { h -> if (down) h / 2 else -h / 2 } + fadeIn(tween(420))) togetherWith
                                (slideOutVertically(tween(320)) { h -> if (down) -h / 2 else h / 2 } + fadeOut(tween(260))) using SizeTransform(clip = false)
                        }) { at ->
                        FloatLines(at, pos, size, showRd)
                    }
                }
            }
            Row(Modifier.align(Alignment.TopEnd)) {
                val playing = song?.playing == true
                IconButton(onClick = { if (playing) YtLink.pause() else YtLink.play() }, Modifier.size(30.dp)) {
                    Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (playing) tr("暫停") else tr("播放"), tint = T.glyph)
                }
                IconButton(onClick = { gear = !gear }, Modifier.size(30.dp)) { Icon(Icons.Filled.Settings, tr("設定"), tint = if (gear) T.btnInk else T.muted) }
                IconButton(onClick = { FloatWord.key = null; onClose() }, Modifier.size(30.dp)) { Icon(Icons.Filled.Close, tr("關"), tint = T.muted) }
            }
        }
        // the song's language (the lyrics read in it, whatever language the app is on)
        val sk = st.picksKey(song)
        // 讀音: on / off (the line under each line)
        if (gear) Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 12.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Txt(tr("讀音"), ff(FF.Footnote), T.muted)
            for ((v, name) in listOf(true to tr("顯示"), false to tr("不顯示"))) {
                val on = showRd == v
                Txt(name, ff(FF.Footnote, if (on) FontWeight.SemiBold else null), if (on) T.btnInk else T.glyph,
                    Modifier.clip(RoundedCornerShape(50)).border(1.dp, if (on) T.btnEdge else T.fnEdge, RoundedCornerShape(50))
                        .clickable { Prefs.lyricsFloatReadings.value = v }.hand().padding(horizontal = 10.dp, vertical = 3.dp))
            }
        }
        // the lyrics' timing: earlier / later (the same as in the 歌詞 page and karaoke)
        if (gear && YtLyricsState.lines.isNotEmpty()) Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(bottom = 4.dp)) { OffsetRow() }
        if (gear && sk != null) {
            SongLangs.version
            val tag = SongLangs.get(sk)
            androidx.compose.foundation.layout.FlowRow(Modifier.fillMaxWidth().padding(start = 16.dp, end = 12.dp, bottom = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Txt(tr("歌的語言"), ff(FF.Footnote), T.muted, Modifier.align(Alignment.CenterVertically))
                for ((v, name) in songLangOptions()) {
                    val on = tag == v
                    Txt(name, ff(FF.Footnote, if (on) FontWeight.SemiBold else null), if (on) T.btnInk else T.glyph,
                        Modifier.clip(RoundedCornerShape(50)).border(1.dp, if (on) T.btnEdge else T.fnEdge, RoundedCornerShape(50))
                            .clickable { SongLangs.set(sk, v) }.hand().padding(horizontal = 10.dp, vertical = 3.dp))
                }
            }
        }
        }
        AnimatedVisibility(FloatWord.key != null, Modifier.weight(1f, fill = false), enter = expandVertically(tween(260)) + fadeIn(),
            exit = shrinkVertically(tween(220)) + fadeOut()) {
            FloatWord.key?.let { FloatDict(it, FloatWord.zh) }
        }
    }
    }
}

/** the word clicked in 浮動歌詞 (its dictionary key; zh: 華語 / 粵語 / 客語's dictionary) */
object FloatWord {
    /** the lines' height (dp) as last measured */
    var linesHeight by mutableFloatStateOf(0f)
    var key by mutableStateOf<String?>(null)
    var zh by mutableStateOf(false)
}
/** how much taller 浮動歌詞 gets when a word's entry shows under its lines */
const val FLOAT_DICT_HEIGHT = 380f

/** 浮動歌詞: a word's dictionary entry under the lines (a word clicked in it opens here too; 收起 slides it away) */
@Composable
private fun FloatDict(key: String, zh: Boolean) {
    val nav = remember { NavStack() }
    // (a word in the entry clicked: shown here instead)
    LaunchedEffect(nav.stack.size) {
        when (val r = nav.top) {
            is Route.Entry -> { FloatWord.key = r.key; FloatWord.zh = false }
            is Route.ZhEntry -> { FloatWord.key = r.key; FloatWord.zh = true }
            else -> {}
        }
        nav.stack.clear()
    }
    Column(Modifier.fillMaxWidth().height(FLOAT_DICT_HEIGHT.dp)) {
        HorizontalDivider(color = T.fnEdge)
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { FloatWord.key = null }) {
                Icon(Icons.Filled.KeyboardArrowUp, null, tint = T.btnInk); Text(tr("收起"), color = T.btnInk)
            }
            Spacer(Modifier.weight(1f))
            // (the same entry in the program's own window, with everything)
            TextButton(onClick = { if (zh) UI.open(Sheet.ZhWord(key)) else UI.openWord(key) }) { Text(tr("在程式裡打開"), color = T.btnInk) }
        }
        CompositionLocalProvider(LocalNav provides nav) {
            Column(Modifier.fillMaxSize().dragScrollY(androidx.compose.foundation.rememberScrollState()).padding(horizontal = 16.dp)) {
                val z = LyricDicts.forKey(key) ?: Store.zh; val d = Store.dict
                if (zh && z != null) { val e = z.entry(key); if (e != null) ZhEntryBody(z, e) else Txt(tr("找不到這個詞。"), ff(FF.Body), T.muted) }
                else if (!zh && d != null) DictEntryBody(d, key)
                else Txt(tr("找不到這個詞。"), ff(FF.Body), T.muted)
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

/** the floating window's line at, being sung (with its reading), and the next one, dim */
@Composable
private fun FloatLines(at: Int, pos: Double, size: Float, showRd: Boolean) {
    val st = YtLyricsState
    val lines = st.lines
    val l = lines.getOrNull(at)
    val next = (at + 1 until lines.size).firstOrNull { lines[it].text.isNotBlank() }
    val zk = listOf(Prefs.zhRom.value, Prefs.zhPlace.value, Prefs.rom.value, Prefs.place.value, Prefs.toneSys.value, Prefs.toneGlow.value)
    val text = l?.text?.trim() ?: ""
    val rd = remember(text, zk, showRd, Store.isZh, Store.lang, LyricPicks.songKey, LyricPicks.lang, LyricPicks.version) {
        if (showRd && text.isNotEmpty()) lyricReading(text) else null
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(1.dp)) {
        if (l == null || text.isEmpty()) Txt("♪", sz(size), T.muted)
        else SungLine(l, st.endOf(at), pos, size, ball = false)
        // (everything wraps onto the next line at the window's edge, never cut off)
        if (rd != null) Txt(rd, lat(size * 0.6f), T.greenInk)
        next?.let { Box(Modifier.graphicsLayer { alpha = 0.5f }) { LyricWords(lines[it].text.trim(), size * 0.68f, T.glyph) } }
    }
}

/** the floating window's height: the lines' own (as measured), or before they're there, a guess for the letters'
 *  size chosen (and the reading on or off) */
fun floatingLyricsHeight(): Float {
    if (FloatWord.linesHeight > 0f) return FloatWord.linesHeight + 2f
    val size = Prefs.lyricsFloatSize.value
    val rd = if (Prefs.lyricsFloatReadings.value) size * 0.6f * 1.35f + 2f else 0f
    return 12f + size * 1.14f * 1.45f + 6f + rd + size * 0.68f * 1.45f + 6f
}
/** …and its width: as set in YouTube 歌詞 (浮動歌詞的寬度) */
fun floatingLyricsWidth(): Float = Prefs.lyricsFloatWidth.value.coerceIn(320f, 2000f)

// MARK: - 歌詞對時: write or fix the lyrics, then time them along with the song

/** the editor: ① 歌詞 (type, paste, or the lyrics found to fix), ② 對時間 (one click as each line starts). Saved as
 *  your own lyrics (LRC) for this song, in the backup folder's 歌詞 like the iPhone / iPad's */
@Composable
private fun YtLyricsEditor() {
    val st = YtLyricsState
    val song = YtLink.song
    var page by remember { mutableIntStateOf(0) }
    // (lyrics without times just imported on the lyrics page: those, to time)
    val imported = remember { st.importText.also { st.importText = null } }
    val lines = remember { mutableStateListOf<TimedLine>().apply { addAll(if (imported != null) LRC.linesFromText(imported, emptyList()) else st.lines) } }
    var text by remember { mutableStateOf(imported ?: st.lines.joinToString("\n") { it.text }) }
    var next by remember { mutableIntStateOf(0) }
    var saved by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf<String?>(null) }
    val pos = rememberSongPos()
    // 從檔案匯入: lyrics from a file (.lrc with its times, or plain text to time here)
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val pickFile = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val raw = try { ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() } } catch (_: Exception) { null }
        if (raw == null) { note = tr("讀不到這個檔案。"); return@rememberLauncherForActivityResult }
        val t = String(raw, Charsets.UTF_8).removePrefix("\uFEFF")
        val timed = Regex("\\[\\d+:\\d").containsMatchIn(t)
        val got = if (timed) LRC.lines(t) else LRC.linesFromText(t, emptyList())
        if (got.isEmpty()) { note = tr("這個檔案是空的。"); return@rememberLauncherForActivityResult }
        lines.clear(); lines.addAll(got)
        text = got.joinToString("\n") { it.text }
        saved = false; page = 0
        note = if (got.any { it.t != null }) tr("匯入了有時間的歌詞：按「儲存」就好，或到「對時間」再調。") else tr("匯入了：到「對時間」替它對時間，再按「儲存」。")
    }
    fun toTiming() { val l = LRC.linesFromText(text, lines.toList()); lines.clear(); lines.addAll(l); next = lines.indexOfFirst { it.t == null }.let { if (it < 0) 0 else it }; page = 1 }
    fun toText() { text = lines.joinToString("\n") { it.text }; page = 0 }
    /** a line's time changed: its word times move with it */
    fun setTime(i: Int, t: Double?) {
        val l = lines[i]
        val w = if (t != null && l.t != null) l.words?.map { it + (t - l.t) } else null
        lines[i] = l.copy(t = t?.let { Math.round(maxOf(0.0, it) * 100) / 100.0 }, words = w)
    }
    // 復原: each change to the times kept (the button, Backspace, Ctrl+Z)
    val undo = remember { ArrayList<EditSnap>() }
    var canUndo by remember { mutableStateOf(false) }
    // 逐字: each character stamped as it's sung (ci: the next character of line `next`)
    var byChar by remember { mutableStateOf(false) }
    var ci by remember { mutableIntStateOf(0) }
    fun snap() { undo.add(EditSnap(lines.toList(), next, ci)); if (undo.size > 400) undo.removeAt(0); canUndo = true; saved = false }
    fun doUndo() {
        if (undo.isEmpty()) return
        val sn = undo.removeAt(undo.size - 1)
        lines.clear(); lines.addAll(sn.lines); next = sn.next; ci = sn.ci; canUndo = undo.isNotEmpty(); saved = false
    }
    // (a key comes a little after the singer: the time taken a bit before)
    fun now() = Math.round(maxOf(0.0, YtLink.position() - 0.1) * 100) / 100.0
    /** 空白鍵: this line starts now (逐字: this character, the line's first one its time too) */
    fun stamp() {
        if (next !in lines.indices) return
        val l = lines[next]
        val ps = LRC.pieces(l.text)
        snap()
        val t = now()
        if (!byChar || ps.size < 2) {
            setTime(next, t)
            if (byChar) lines[next] = lines[next].copy(words = null)
            next++; ci = 0; return
        }
        val c = ci.coerceIn(0, ps.size - 1)
        val got = ArrayList<Double>()
        if (c > 0) { val w = l.words; if (w != null && w.size == ps.size) got.addAll(w.take(c)) else got.add(l.t ?: t) }
        while (got.size < c) got.add(got.lastOrNull() ?: t)
        got.add(maxOf(t, (got.lastOrNull() ?: 0.0) + 0.01))
        val start = got.first()
        val end = editEnd(lines, next)?.takeIf { it > got.last() } ?: (got.last() + (ps.size - got.size) * 0.4 + 0.3)
        lines[next] = l.copy(t = start, words = fillWords(got, ps.size, end))
        ci = c + 1
        if (ci >= ps.size) { next++; ci = 0 }
    }
    /** Enter: an empty line (a break) right after the line being worked on */
    fun addBreak() { snap(); lines.add(minOf(next + 1, lines.size), TimedLine("", null)) }
    // the keys, while 對時間 is open: 空白鍵 stamps, Enter a break after, ↑ ↓ another line, Backspace / Ctrl+Z undo
    DisposableEffect(page) {
        // (a key held down stamps once, not again and again)
        var held = false
        val mine: (androidx.compose.ui.input.key.KeyEvent) -> Boolean = { e ->
            if (e.type == androidx.compose.ui.input.key.KeyEventType.KeyUp && e.key == androidx.compose.ui.input.key.Key.Spacebar) { held = false; true }
            else if (e.type != androidx.compose.ui.input.key.KeyEventType.KeyDown) false
            else when (e.key) {
                androidx.compose.ui.input.key.Key.Spacebar -> { if (!held) { held = true; stamp() }; true }
                androidx.compose.ui.input.key.Key.Enter, androidx.compose.ui.input.key.Key.NumPadEnter -> { addBreak(); true }
                androidx.compose.ui.input.key.Key.DirectionUp -> { if (next > 0) next--; ci = 0; true }
                androidx.compose.ui.input.key.Key.DirectionDown -> { if (next < lines.size) next++; ci = 0; true }
                // (← →: the song back or on 2 seconds; with Shift 5)
                androidx.compose.ui.input.key.Key.DirectionLeft -> { YtLink.seek(YtLink.position() - if (e.isShiftPressed) 5 else 2); true }
                androidx.compose.ui.input.key.Key.DirectionRight -> { YtLink.seek(YtLink.position() + if (e.isShiftPressed) 5 else 2); true }
                androidx.compose.ui.input.key.Key.Backspace -> { doUndo(); true }
                androidx.compose.ui.input.key.Key.Z -> if (e.isCtrlPressed || e.isMetaPressed) { doUndo(); true } else false
                else -> false
            }
        }
        if (page == 1) EditorKeys.handler = mine
        // (only its own: the lyrics screen's space bar, set meanwhile, stays)
        onDispose { if (EditorKeys.handler === mine) EditorKeys.handler = null }
    }
    fun save() {
        if (page == 0) toTiming()
        val s = YtLink.song ?: return
        val id = st.ownId(s) ?: return
        val lrc = LRC.make(lines.toList(), s.title, s.artist, s.d.takeIf { it > 0 })
        OwnLyrics.set(OwnLyric(id, s.title, s.artist, s.d.takeIf { it > 0 }, lrc, System.currentTimeMillis()))
        st.reloadOwn()
        saved = true
        // (into the backup folder's 歌詞, in the background: reading every device's backup there could take a while
        // (iCloud) and the window froze meanwhile; where it went said on the lyrics page once it's done)
        syncInBackground { msg ->
            val dir = OwnLyrics.lastDir
            st.savedNote = if (dir != null && Prefs.backupFolder.value.isNotEmpty()) tr("存好了：{0}", java.io.File(dir, OwnLyrics.fileName(OwnLyric(id, s.title, s.artist, null, "", 0))).path)
                else tr("存好了，在這台電腦的程式裡。要存到備份資料夾：先在設定 → 備份與同步選一個資料夾。") + if (msg.isNotEmpty()) "（$msg）" else ""
        }
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(tr("歌詞對時"), { UI.ytEditOpen = false }, settings = false) {
            TextButton(onClick = { save(); UI.ytEditOpen = false }) { Text(tr("儲存"), color = T.btnInk) }
        }
        // the song: its name, play / pause, back 5 seconds, where it is
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.weight(1f)) {
                Txt(song?.title ?: "", ff(FF.Headline), T.glyph, maxLines = 1)
                Txt(LRC.shown(YtLink.position()) + (song?.d?.takeIf { it > 0 }?.let { " / " + LRC.shown(it) } ?: ""), lat(13f), T.muted)
            }
            IconButton(onClick = { YtLink.seek(YtLink.position() - 5) }) { Icon(Icons.Filled.Replay5, tr("退 5 秒"), tint = T.glyph) }
            val playing = song?.playing == true
            IconButton(onClick = { if (playing) YtLink.pause() else YtLink.play() }) {
                Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (playing) tr("暫停") else tr("播放"), tint = T.glyph)
            }
            IconButton(onClick = { YtLink.seek(YtLink.position() + 5) }) { Icon(Icons.Filled.Forward5, tr("前進 5 秒"), tint = T.glyph) }
        }
        SongBar(song)
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Ctl(Icons.Filled.Notes, tr("① 歌詞"), Modifier.weight(1f), on = page == 0) { if (page != 0) toText() }
            Ctl(Icons.Filled.Timer, tr("② 對時間"), Modifier.weight(1f), on = page == 1) { if (page != 1) toTiming() }
        }
        if (page == 0) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Txt(tr("打或貼上歌詞，一行一句；空一行是間奏。找到的歌詞可以在這裡改。改好以後到「對時間」。"), ff(FF.Footnote), T.muted, Modifier.weight(1f))
            }
            note?.let { Txt(it, ff(FF.Footnote), T.btnInk, Modifier.padding(horizontal = 16.dp)) }
            Box(Modifier.weight(1f).fillMaxWidth().padding(12.dp).clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.7f))
                .border(1.dp, T.fnEdge, RoundedCornerShape(12.dp)).padding(12.dp)) {
                BasicTextField(text, { text = it; saved = false }, Modifier.fillMaxSize(),
                    textStyle = TextStyle(fontSize = 18.sp, color = T.glyph), cursorBrush = SolidColor(T.btnInk))
            }
        } else {
            Txt(if (byChar) tr("逐字：每個字開始唱的時候按空白鍵（或「這個字」）。一句的第一個字也是這一句的時間。")
                else tr("每一句開始唱的時候按空白鍵（或「這一句開始」）。Enter：在這一行後面加空行；↑ ↓：換行；← →：歌退後或往前 2 秒（Shift：5 秒）；Backspace 或 Ctrl+Z：復原。點一行，歌跳到那裡。"),
                ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            // (the line being sung, big, lighting up character by character: to see whether the times are right)
            val playingLine = lines.indexOfLast { it.t != null && it.t <= pos }
            Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp).clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.6f))
                .padding(horizontal = 14.dp, vertical = 10.dp).heightIn(min = 44.dp), contentAlignment = Alignment.CenterStart) {
                val l = lines.getOrNull(playingLine)
                if (l == null || l.text.isEmpty()) Txt(if (l == null) "" else tr("（間奏）"), sz(24f), T.muted)
                else Text(litPieces(l, editEnd(lines, playingLine), pos, if (byChar && playingLine == next) ci else -1), style = sz(26f, FontWeight.SemiBold))
            }
            val list = rememberLazyListState()
            LaunchedEffect(next) { if (next in lines.indices) try { list.animateScrollToItem(next, -200) } catch (_: Exception) {} }
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                itemsIndexed(lines) { i, l ->
                    val isNext = i == next
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp))
                        .background(if (isNext) T.btnEdge.copy(alpha = 0.18f) else if (i == playingLine) T.fn.copy(alpha = 0.6f) else androidx.compose.ui.graphics.Color.Transparent)
                        .then(if (isNext) Modifier.border(1.dp, T.btnEdge, RoundedCornerShape(8.dp)) else Modifier)
                        .clickable { next = i; ci = 0; l.t?.let { YtLink.seek(it) } }
                        .padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Txt(l.t?.let { LRC.shown(it) } ?: "—", lat(13f), if (l.t != null) T.btnInk else T.muted, Modifier.widthIn(min = 52.dp))
                        if (l.text.isEmpty()) Txt(tr("（間奏）"), sz(17f), T.muted, Modifier.weight(1f))
                        else Text(litPieces(l, editEnd(lines, i), if (i == playingLine) pos else -1.0, if (byChar && isNext) ci else -1),
                            style = sz(17f), modifier = Modifier.weight(1f))
                        if (l.words != null) Txt(tr("逐字"), ff(FF.Caption), T.muted)
                        if (l.t != null) {
                            TextButton(onClick = { snap(); setTime(i, l.t - 0.25) }, contentPadding = PaddingValues(4.dp)) { Text("−¼", color = T.btnInk) }
                            TextButton(onClick = { snap(); setTime(i, l.t + 0.25) }, contentPadding = PaddingValues(4.dp)) { Text("+¼", color = T.btnInk) }
                        }
                    }
                }
            }
            // the taps: undo, this line (or character) starts now, an empty line after this one, line by line or 逐字
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SoftButton(onClick = { doUndo() }, Modifier.weight(1f).heightIn(min = 42.dp), enabled = canUndo) {
                    IconLabel(Icons.Filled.Undo, tr("復原"), ff(FF.Subheadline), if (canUndo) T.glyph else T.muted)
                }
                Ctl(Icons.Filled.TouchApp, if (byChar) tr("這個字（空白鍵）") else tr("這一句開始（空白鍵）"), Modifier.weight(2f), on = true) { stamp() }
                Ctl(Icons.Filled.MoreHoriz, tr("後面加空行（Enter）"), Modifier.weight(1.4f)) { addBreak() }
                Ctl(Icons.Filled.TextFields, tr("逐字"), Modifier.weight(1f), on = byChar) { byChar = !byChar; ci = 0 }
            }
        }
        // (your own lyrics for this song: delete them, back to LRCLIB's)
        val own = st.ownId(song)?.let { OwnLyrics.get(it) }
        if (own != null) TextButton(onClick = { OwnLyrics.remove(own.id); st.reloadOwn(); syncInBackground { }; UI.ytEditOpen = false },
            Modifier.align(Alignment.CenterHorizontally)) { Text(tr("刪掉自己的歌詞"), color = T.muted) }
    }
}

/** a control under the lyrics: its icon and name; on: lit */
@Composable
private fun Ctl(icon: ImageVector, label: String, modifier: Modifier, on: Boolean = false, onClick: () -> Unit) {
    SoftButton(onClick = onClick, modifier.heightIn(min = 42.dp)) {
        IconLabel(icon, label, ff(FF.Subheadline), if (on) T.btnInk else T.glyph)
    }
}

private fun clock(t: Double): String {
    val s = t.toInt().coerceAtLeast(0)
    return "%d:%02d".format(s / 60, s % 60)
}

/** where the song is, as a bar to drag (the song jumps there when let go); ← → in 對時間 move it too */
@Composable
private fun SongBar(song: YtSong?) {
    val d = song?.d ?: 0.0
    if (d <= 0) return
    var drag by remember { mutableStateOf<Float?>(null) }
    val p = rememberSongPos() - YtLyricsState.offset
    Slider(drag ?: p.toFloat().coerceIn(0f, d.toFloat()), { drag = it }, Modifier.fillMaxWidth().padding(horizontal = 16.dp).height(28.dp),
        valueRange = 0f..d.toFloat(), onValueChangeFinished = { drag?.let { YtLink.seek(it.toDouble()) }; drag = null },
        colors = SliderDefaults.colors(thumbColor = T.btnInk, activeTrackColor = T.btnEdge, inactiveTrackColor = T.fnEdge))
}

/** a change in 歌詞對時, for 復原 */
private class EditSnap(val lines: List<TimedLine>, val next: Int, val ci: Int)

/** the lyrics page's share button: 從檔案匯入 (an .lrc file with its times is saved as your lyrics for the video at
 *  once; plain text opens 歌詞對時 to time it) and 匯出成 .lrc 檔 (the lyrics shown, with their times) */
@Composable
private fun LyricsShareMenu() {
    val st = YtLyricsState
    val ctx = androidx.compose.ui.platform.LocalContext.current
    var open by remember { mutableStateOf(false) }
    val pickFile = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) importLyrics(ctx, uri)
    }
    val saveFile = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.CreateDocument("text/plain")) { uri ->
        if (uri != null) exportLyrics(ctx, uri)
    }
    Box {
        IconButton(onClick = { open = true }) { Icon(Icons.Filled.Share, tr("分享"), tint = T.glyph) }
        DropdownMenu(open, { open = false }, containerColor = T.fn) {
            DropdownMenuItem(text = { Text(tr("從檔案匯入"), color = T.glyph) }, leadingIcon = { Icon(Icons.Filled.FileOpen, null, tint = T.btnInk) },
                onClick = { open = false; pickFile.launch(arrayOf("*/*")) })
            DropdownMenuItem(text = { Text(tr("匯出成 .lrc 檔"), color = if (st.lines.isNotEmpty()) T.glyph else T.muted) },
                leadingIcon = { Icon(Icons.Filled.Save, null, tint = T.btnInk) }, enabled = st.lines.isNotEmpty(),
                onClick = { open = false; saveFile.launch(lrcName()) })
        }
    }
}

/** the backup folder synced away from the window (the computer: reading every device's backup could take a while and
 *  froze it), then done(its message) on the window's thread */
private fun syncInBackground(done: (String) -> Unit) {
    // (Android: as before, right here; its backup merges on the main thread)
    if (!com.unoki99.fangfang.engine.EngineSettings.desktop) { done(try { Backup.syncNow() } catch (e: Exception) { e.message ?: "" }); return }
    MainScope().launch {
        val msg = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            try { Backup.syncNow() } catch (e: Exception) { e.message ?: "" }
        }
        done(msg)
    }
}

/** "繁華夢 - 黃齡.lrc" */
private fun lrcName(): String {
    val s = YtLink.song
    val clean = { x: String -> x.replace(Regex("[\\\\/:*?\"<>|\\r\\n]"), " ").trim() }
    val base = (s?.title ?: "lyrics").let(clean) + (s?.artist?.takeIf { it.isNotEmpty() }?.let { " - " + clean(it) } ?: "")
    return (base.ifEmpty { "lyrics" }) + ".lrc"
}

private fun importLyrics(ctx: android.content.Context, uri: android.net.Uri) {
    val st = YtLyricsState
    val s = YtLink.song ?: return
    val raw = try { ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() } } catch (_: Exception) { null }
    if (raw == null) { st.savedNote = tr("讀不到這個檔案。"); return }
    val t = String(raw, Charsets.UTF_8).removePrefix("\uFEFF")
    if (t.isBlank()) { st.savedNote = tr("這個檔案是空的。"); return }
    if (!Regex("\\[\\d+:\\d").containsMatchIn(t)) {
        // (no times: 歌詞對時, to time them)
        st.importText = t.trim()
        UI.ytEditOpen = true
        return
    }
    val id = st.ownId(s) ?: return
    val lrc = LRC.make(LRC.lines(t), s.title, s.artist, s.d.takeIf { it > 0 })
    OwnLyrics.set(OwnLyric(id, s.title, s.artist, s.d.takeIf { it > 0 }, lrc, System.currentTimeMillis()))
    st.reloadOwn()
    st.savedNote = tr("匯入了，存成這部影片的歌詞。")
    syncInBackground { }
}

private fun exportLyrics(ctx: android.content.Context, uri: android.net.Uri) {
    val st = YtLyricsState
    val s = YtLink.song
    val lrc = LRC.make(st.lines, s?.title ?: st.pick?.track ?: "", s?.artist ?: st.pick?.artist ?: "", s?.d?.takeIf { it > 0 })
    val ok = try { ctx.contentResolver.openOutputStream(uri)?.use { it.write(lrc.toByteArray(Charsets.UTF_8)) } != null } catch (_: Exception) { false }
    st.savedNote = if (ok) tr("匯出了：{0}", uri.path ?: "") else tr("沒辦法存這個檔案。")
}

/** YouTube 歌詞 (and 卡拉 OK): the space bar plays or pauses the song (the Windows / Mac program hands the keys here
 *  first), except while typing in the search field */
object SpaceKeys { var typing = false }

@Composable
private fun SpaceToPlay() {
    DisposableEffect(Unit) {
        SpaceKeys.typing = false
        // (a key held down: once)
        var held = false
        val h: (androidx.compose.ui.input.key.KeyEvent) -> Boolean = { e ->
            if (e.key != androidx.compose.ui.input.key.Key.Spacebar || SpaceKeys.typing) false
            else if (e.type == androidx.compose.ui.input.key.KeyEventType.KeyUp) { held = false; true }
            else if (e.type != androidx.compose.ui.input.key.KeyEventType.KeyDown) false
            else {
                if (!held) { held = true; if (YtLink.song?.playing == true) YtLink.pause() else YtLink.play() }
                true
            }
        }
        EditorKeys.handler = h
        onDispose { if (EditorKeys.handler === h) EditorKeys.handler = null }
    }
}

/** 浮動歌詞's own window: the space bar plays / pauses, only while that window is the one in front */
private var floatSpaceHeld = false
fun floatSpaceKey(e: androidx.compose.ui.input.key.KeyEvent): Boolean {
    if (e.key != androidx.compose.ui.input.key.Key.Spacebar) return false
    if (e.type == androidx.compose.ui.input.key.KeyEventType.KeyUp) { floatSpaceHeld = false; return true }
    if (e.type != androidx.compose.ui.input.key.KeyEventType.KeyDown) return false
    if (!floatSpaceHeld) { floatSpaceHeld = true; if (YtLink.song?.playing == true) YtLink.pause() else YtLink.play() }
    return true
}

/** the keys of 歌詞對時's 對時間 (the Windows program hands them here first: desktop/Main.kt) */
object EditorKeys {
    var handler: ((androidx.compose.ui.input.key.KeyEvent) -> Boolean)? = null
}

/** where line i ends in the editor: the next line's time */
private fun editEnd(lines: List<TimedLine>, i: Int): Double? {
    for (j in i + 1 until lines.size) lines[j].t?.let { return it }
    return null
}

/** the characters stamped so far, then the rest spread evenly up to the line's end */
private fun fillWords(got: List<Double>, n: Int, end: Double): List<Double> {
    val out = ArrayList(got.map { Math.round(it * 100) / 100.0 })
    val from = out.last(); val left = n - out.size
    for (k in 1..left) out.add(Math.round((from + (end - from) * k / (left + 1)) * 100) / 100.0)
    return out
}

/** a line in the editor, its characters lit as they're sung (pos < 0: not being sung, all plain); mark: the next
 *  character to stamp (逐字), underlined */
@Composable
private fun litPieces(l: TimedLine, end: Double?, pos: Double, mark: Int): AnnotatedString {
    val ps = LRC.pieces(l.text)
    val t0 = l.t
    val times: List<Double>? = when {
        t0 == null || ps.isEmpty() -> null
        l.words != null && l.words.size == ps.size -> l.words
        else -> {
            val starts = LRC.pieceStarts(ps); val total = maxOf(1, l.text.count { it.isLetterOrDigit() })
            val dur = minOf((end ?: (t0 + 99)) - t0, maxOf(1.5, total * 0.45)).coerceAtLeast(0.5)
            starts.map { t0 + dur * it / total }
        }
    }
    val ink = T.glyph; val lit = T.btnInk
    return androidx.compose.ui.text.buildAnnotatedString {
        if (ps.isEmpty()) { append(l.text); return@buildAnnotatedString }
        ps.forEachIndexed { k, p ->
            val sung = pos >= 0 && times != null && pos >= times[k]
            val now = sung && (k == ps.size - 1 || pos < times!![k + 1])
            val color = when { pos < 0 -> ink; now -> lit; sung -> ink; else -> ink.copy(alpha = 0.35f) }
            withStyle(androidx.compose.ui.text.SpanStyle(color = color,
                textDecoration = if (k == mark) androidx.compose.ui.text.style.TextDecoration.Underline else null,
                background = if (k == mark) T.btnEdge.copy(alpha = 0.25f) else androidx.compose.ui.graphics.Color.Unspecified)) { append(p) }
        }
    }
}


// MARK: - 卡拉 OK: the song's lines big, the whole window (the iPhone / iPad's 卡拉 OK)

@Composable
private fun YtKaraoke() {
    val st = YtLyricsState
    val song = YtLink.song
    LaunchedEffect(song?.id, song?.title) { st.follow() }
    PicksFor(song)
    val pos = rememberSongPos()
    val lines = st.lines
    val cur = st.lineAt(pos)
    val size = Prefs.karaokeSize.value
    val showRd = Prefs.karaokeReadings.value
    Column(Modifier.fillMaxSize().background(T.bg)) {
        TopBar(tr("卡拉 OK"), { UI.karaokeOpen = false }, close = true, settings = false) {
            TextButton(onClick = { Prefs.karaokeSize.value = (size - 4f).coerceAtLeast(24f) }) { Text("A−", color = T.btnInk) }
            TextButton(onClick = { Prefs.karaokeSize.value = (size + 4f).coerceAtMost(96f) }) { Text("A+", color = T.btnInk) }
            TextButton(onClick = { Prefs.karaokeReadings.value = !showRd }) { Text(tr("讀音"), color = if (showRd) T.btnInk else T.muted) }
        }
        // (歌的語言 here too, and 跳跳球)
        SongLangRow(st.picksKey(song))
        BallSettings()
        Box(Modifier.weight(1f).fillMaxWidth().clipToBounds().padding(horizontal = 40.dp), contentAlignment = Alignment.Center) {
            AnimatedContent(targetState = cur, label = "karaoke",
                transitionSpec = {
                    val down = targetState >= initialState
                    (slideInVertically(tween(450)) { h -> if (down) h / 3 else -h / 3 } + fadeIn(tween(450))) togetherWith
                        (slideOutVertically(tween(350)) { h -> if (down) -h / 3 else h / 3 } + fadeOut(tween(300))) using SizeTransform(clip = false)
                }) { at ->
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy((size * 0.3f).dp)) {
                    // (the line before, dim; the line being sung, big, lighting up; the two after it; all in the middle)
                    lines.getOrNull(at - 1)?.takeIf { it.text.isNotBlank() }?.let { Box(Modifier.graphicsLayer { alpha = 0.3f }) { LyricWords(it.text.trim(), size * 0.55f, T.glyph, center = true) } }
                    val l = lines.getOrNull(at)
                    if (l == null || l.text.isBlank()) Txt("♪", sz(size), T.muted)
                    else {
                        SungLine(l, st.endOf(at), pos, size, center = true)
                        if (showRd) {
                            val zk = listOf(Prefs.zhRom.value, Prefs.zhPlace.value, Prefs.rom.value, Prefs.place.value, Prefs.toneSys.value, Prefs.toneGlow.value)
                            val rd = remember(l.text, zk, Store.lang, LyricPicks.lang, LyricPicks.version) { lyricReading(l.text.trim()) }
                            rd?.let { Text(it, style = lat(size * 0.5f), color = T.greenInk, textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
                        }
                    }
                    var shown = 0
                    for (j in at + 1 until lines.size) {
                        if (shown >= 2) break
                        val n = lines[j]; if (n.text.isBlank()) continue
                        shown++
                        Box(Modifier.graphicsLayer { alpha = if (shown == 1) 0.55f else 0.3f }) { LyricWords(n.text.trim(), size * 0.6f, T.glyph, center = true) }
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { YtLink.seek(YtLink.position() - 5) }) { Icon(Icons.Filled.Replay5, tr("退 5 秒"), tint = T.glyph) }
            val playing = song?.playing == true
            IconButton(onClick = { if (playing) YtLink.pause() else YtLink.play() }, Modifier.size(56.dp)) {
                Icon(if (playing) Icons.Filled.PauseCircle else Icons.Filled.PlayCircle, if (playing) tr("暫停") else tr("播放"), tint = T.btnInk, modifier = Modifier.size(48.dp))
            }
            IconButton(onClick = { YtLink.seek(YtLink.position() + 5) }) { Icon(Icons.Filled.Forward5, tr("前進 5 秒"), tint = T.glyph) }
        }
        // (對時: the lyrics sooner or later, here too)
        Box(Modifier.padding(bottom = 10.dp)) { OffsetRow() }
    }
}
