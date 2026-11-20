package com.unoki99.fangfang.ui

import androidx.compose.animation.*
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.AnnotatedString
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

    val lines: List<TimedLine> get() = pick?.lines ?: emptyList()
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
        // (a song tagged 華語, 粵語 or 客語: the app goes to that language, its dictionary then reads the lyrics; 台語's
        // is always there, so a 台語 song needs no switch)
        if (tag != null && tag in 1..3 && Store.lang != tag) Store.setLanguage(tag)
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
    val st = YtLyricsState
    val song = YtLink.song
    val live = YtLink.live()
    LaunchedEffect(song?.id, song?.title) { st.follow() }
    PicksFor(song)
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
            // 浮動歌詞: the line being sung in a small window over everything
            IconButton(onClick = { UI.lyricsFloat = !UI.lyricsFloat }) {
                Icon(Icons.Filled.PictureInPicture, tr("浮動歌詞"), tint = if (UI.lyricsFloat) T.btnInk else T.glyph)
            }
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
        Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { SearchField(st.query, { st.query = it }, tr("歌名或歌手")) }
            TextButton(onClick = { if (st.query.isNotBlank()) st.lookFor(st.query, "", YtLink.song?.d ?: 0.0, false, st.ownId(YtLink.song)) }) { Text(tr("找"), color = T.btnInk) }
        }
        Row(Modifier.fillMaxWidth().clickable { Prefs.lyricsReadings.value = !showReadings }.padding(horizontal = 16.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Txt(tr("顯示讀音"), ff(FF.Subheadline), T.glyph, Modifier.weight(1f))
            Switch(showReadings, { Prefs.lyricsReadings.value = it },
                colors = SwitchDefaults.colors(checkedTrackColor = T.btnEdge, checkedThumbColor = T.btnInk))
        }
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
@Composable
private fun SongLangRow(key: String?) {
    if (key == null) return
    SongLangs.version
    val tag = SongLangs.get(key)
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Txt(tr("歌的語言"), ff(FF.Footnote), T.muted)
        val opts = listOf<Pair<Int?, String>>(null to tr("跟著 App"), 0 to tr("台語"), 1 to tr("華語"), 2 to tr("粵語"), 3 to tr("客語"))
        for ((v, name) in opts) {
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
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
            TextButton(onClick = { st.offset -= 0.3 }) { Text(tr("歌詞晚一點"), color = T.btnInk) }
            Txt(if (st.offset == 0.0) tr("歌詞時間") else String.format("%+.1f s", st.offset), ff(FF.Footnote), T.muted)
            TextButton(onClick = { st.offset += 0.3 }) { Text(tr("歌詞早一點"), color = T.btnInk) }
        }
    }
}

/** the line being sung, word by word: the words already sung lit, the one being sung swelling, the rest dim. A word's
 *  time: from the lyrics' own word times (歌詞對時 on the iPad, or here) when they have them, else the line's time spread
 *  over its words by their length */
@Composable
internal fun SungLine(line: TimedLine, end: Double, pos: Double, size: Float) {
    val zk = listOf(Prefs.zhPlace.value, Prefs.rom.value, Prefs.place.value, Prefs.toneSys.value, Prefs.toneGlow.value)
    val words = remember(line.text, zk, Store.isZh, Store.lang, LyricPicks.songKey, LyricPicks.lang, LyricPicks.version) { lyricWords(line.text.trim()) }
    var menu by remember { mutableIntStateOf(-1) }
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
    TapWords(
        count = words.size,
        isTappable = { i -> words.getOrNull(i)?.let { it.open != null || it.pick != null } == true },
        onTap = { i -> val w = words.getOrNull(i); if (w?.pick != null) menu = i else w?.open?.invoke() },
    ) { i, hot ->
        val sung = pos >= starts[i]
        val now = sung && (i == words.size - 1 || pos < starts[i + 1])
        val scale by animateFloatAsState(if (now || hot) 1.14f else 1f, label = "sung")
        val alpha by animateFloatAsState(if (sung) 1f else 0.42f, label = "lit")
        Box {
            Text(words[i].text, style = sz(size, FontWeight.SemiBold), color = T.glyph,
                modifier = Modifier.graphicsLayer { scaleX = scale; scaleY = scale; this.alpha = alpha }.padding(vertical = 2.dp)
                    .then(if (words[i].pick != null) Modifier.dottedUnder() else Modifier))
            if (menu == i) ReadingMenu(words[i]) { menu = -1 }
        }
    }
}

/** a 台語 word of the lyrics with more than one reading (dotted underline): its readings to pick from, the one
 *  picked kept for this song (always used in its lyrics), and its dictionary entry */
@Composable
internal fun ReadingMenu(w: LyricWord, onClose: () -> Unit) {
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
                onClick = { onClose(); o() })
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
@Composable
fun FloatingLyrics(onClose: () -> Unit) {
    val st = YtLyricsState
    val song = YtLink.song
    LaunchedEffect(song?.id, song?.title) { st.follow() }
    PicksFor(song)
    val pos = rememberSongPos()
    val lines = st.lines
    val cur = st.lineAt(pos)
    val size = Prefs.lyricsFloatSize.value
    val showRd = Prefs.lyricsFloatReadings.value
    Box(Modifier.fillMaxSize().clip(RoundedCornerShape(16.dp)).background(T.bg.copy(alpha = 0.88f))
        .border(1.dp, T.fnEdge, RoundedCornerShape(16.dp)).padding(start = 16.dp, end = 8.dp, top = 6.dp, bottom = 6.dp)) {
        Box(Modifier.fillMaxSize().padding(end = 62.dp).clipToBounds(), contentAlignment = Alignment.CenterStart) {
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
            IconButton(onClick = onClose, Modifier.size(30.dp)) { Icon(Icons.Filled.Close, tr("關"), tint = T.muted) }
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
        else SungLine(l, st.endOf(at), pos, size)
        if (rd != null) Txt(rd, lat(size * 0.6f), T.greenInk, maxLines = 1)
        next?.let { Box(Modifier.graphicsLayer { alpha = 0.5f }) { LyricWords(lines[it].text.trim(), size * 0.68f, T.glyph) } }
    }
}

/** the floating window's height for the letters' size chosen (and the reading on or off): just the lines, no more */
fun floatingLyricsHeight(): Float {
    val size = Prefs.lyricsFloatSize.value
    val rd = if (Prefs.lyricsFloatReadings.value) size * 0.6f * 1.35f + 2f else 0f
    return 12f + size * 1.14f * 1.45f + 6f + rd + size * 0.68f * 1.45f + 6f
}
/** …and its width: wider for bigger letters */
fun floatingLyricsWidth(): Float = maxOf(560f, Prefs.lyricsFloatSize.value * 27f)

// MARK: - 歌詞對時: write or fix the lyrics, then time them along with the song

/** the editor: ① 歌詞 (type, paste, or the lyrics found to fix), ② 對時間 (one click as each line starts). Saved as
 *  your own lyrics (LRC) for this song, in the backup folder's 歌詞 like the iPhone / iPad's */
@Composable
private fun YtLyricsEditor() {
    val st = YtLyricsState
    val song = YtLink.song
    var page by remember { mutableIntStateOf(0) }
    val lines = remember { mutableStateListOf<TimedLine>().apply { addAll(st.lines) } }
    var text by remember { mutableStateOf(st.lines.joinToString("\n") { it.text }) }
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
    fun save() {
        if (page == 0) toTiming()
        val s = YtLink.song ?: return
        val id = st.ownId(s) ?: return
        val lrc = LRC.make(lines.toList(), s.title, s.artist, s.d.takeIf { it > 0 })
        OwnLyrics.set(OwnLyric(id, s.title, s.artist, s.d.takeIf { it > 0 }, lrc, System.currentTimeMillis()))
        st.reloadOwn()
        saved = true
        // (into the backup folder's 歌詞 at once)
        try { Backup.syncNow() } catch (_: Exception) {}
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
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Ctl(Icons.Filled.Notes, tr("① 歌詞"), Modifier.weight(1f), on = page == 0) { if (page != 0) toText() }
            Ctl(Icons.Filled.Timer, tr("② 對時間"), Modifier.weight(1f), on = page == 1) { if (page != 1) toTiming() }
        }
        if (page == 0) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Txt(tr("打或貼上歌詞，一行一句；空一行是間奏。找到的歌詞可以在這裡改。改好以後到「對時間」。"), ff(FF.Footnote), T.muted, Modifier.weight(1f))
                SoftButton(onClick = { pickFile.launch(arrayOf("*/*")) }) {
                    IconLabel(Icons.Filled.FileOpen, tr("從檔案匯入"), ff(FF.Subheadline), T.btnInk)
                }
            }
            note?.let { Txt(it, ff(FF.Footnote), T.btnInk, Modifier.padding(horizontal = 16.dp)) }
            Box(Modifier.weight(1f).fillMaxWidth().padding(12.dp).clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.7f))
                .border(1.dp, T.fnEdge, RoundedCornerShape(12.dp)).padding(12.dp)) {
                BasicTextField(text, { text = it; saved = false }, Modifier.fillMaxSize(),
                    textStyle = TextStyle(fontSize = 18.sp, color = T.glyph), cursorBrush = SolidColor(T.btnInk))
            }
        } else {
            Txt(tr("放歌，每一句開始唱的時候按「這一句開始」。點一行可以從那一行再來；−¼／+¼ 微調。"), ff(FF.Footnote), T.muted, Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
            val list = rememberLazyListState()
            LaunchedEffect(next) { if (next in lines.indices) try { list.animateScrollToItem(next, -200) } catch (_: Exception) {} }
            val playingLine = lines.indexOfLast { it.t != null && it.t <= pos }
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                itemsIndexed(lines) { i, l ->
                    val isNext = i == next
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp))
                        .background(if (isNext) T.btnEdge.copy(alpha = 0.18f) else if (i == playingLine) T.fn.copy(alpha = 0.6f) else androidx.compose.ui.graphics.Color.Transparent)
                        .clickable { next = i; l.t?.let { YtLink.seek(it) } }
                        .padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Txt(l.t?.let { LRC.shown(it) } ?: "—", lat(13f), if (l.t != null) T.btnInk else T.muted, Modifier.widthIn(min = 52.dp))
                        Txt(if (l.text.isEmpty()) tr("（間奏）") else l.text, sz(17f), if (l.text.isEmpty()) T.muted else T.glyph, Modifier.weight(1f))
                        if (l.t != null) {
                            TextButton(onClick = { setTime(i, l.t - 0.25); saved = false }, contentPadding = PaddingValues(4.dp)) { Text("−¼", color = T.btnInk) }
                            TextButton(onClick = { setTime(i, l.t + 0.25); saved = false }, contentPadding = PaddingValues(4.dp)) { Text("+¼", color = T.btnInk) }
                        }
                    }
                }
            }
            // the taps: this line starts now (a little before the click: a click comes late), back a line, a break, skip
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Ctl(Icons.Filled.Undo, tr("退一行"), Modifier.weight(1f)) {
                    if (next > 0) { next--; setTime(next, null); saved = false }
                }
                Ctl(Icons.Filled.TouchApp, tr("這一句開始"), Modifier.weight(2f), on = true) {
                    if (next in lines.indices) { setTime(next, YtLink.position() - 0.15); next++; saved = false }
                }
                Ctl(Icons.Filled.MoreHoriz, tr("空行"), Modifier.weight(1f)) {
                    lines.add(next.coerceIn(0, lines.size), TimedLine("", Math.round((YtLink.position() - 0.15) * 100) / 100.0)); next++; saved = false
                }
                Ctl(Icons.Filled.SkipNext, tr("跳過"), Modifier.weight(1f)) { if (next < lines.size) next++ }
            }
        }
        // (your own lyrics for this song: delete them, back to LRCLIB's)
        val own = st.ownId(song)?.let { OwnLyrics.get(it) }
        if (own != null) TextButton(onClick = { OwnLyrics.remove(own.id); st.reloadOwn(); try { Backup.syncNow() } catch (_: Exception) {}; UI.ytEditOpen = false },
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
