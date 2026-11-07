package com.unoki99.fangfang.ui

import com.unoki99.fangfang.tr
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import com.unoki99.fangfang.Player
import com.unoki99.fangfang.Prefs

// MARK: text styles (sizes as on the iPhone app; they follow the phone's font size and 設定 → 文字大小)

enum class FF(val size: Float, val weight: FontWeight = FontWeight.Normal) {
    Body(17f), Callout(16f), Subheadline(15f), Footnote(13f), Caption(12f), Caption2(11f),
    Headline(17f, FontWeight.SemiBold), Title3(20f), Title2(22f), Title(28f), LargeTitle(34f)
}

fun ff(style: FF, weight: FontWeight? = null): TextStyle = TextStyle(fontSize = style.size.sp, fontWeight = weight ?: style.weight)
fun sz(size: Float, weight: FontWeight = FontWeight.Normal): TextStyle = TextStyle(fontSize = size.sp, fontWeight = weight)
fun lat(size: Float): TextStyle = TextStyle(fontSize = size.sp, fontFamily = T.lat)

@Composable
fun Txt(text: String, style: TextStyle, color: Color = T.glyph, modifier: Modifier = Modifier, maxLines: Int = Int.MAX_VALUE) {
    Text(text, style = style, color = color, modifier = modifier, maxLines = maxLines, overflow = TextOverflow.Ellipsis)
}

@Composable
fun Txt(text: AnnotatedString, style: TextStyle, color: Color = T.glyph, modifier: Modifier = Modifier, maxLines: Int = Int.MAX_VALUE) {
    Text(text, style = style, color = color, modifier = modifier, maxLines = maxLines, overflow = TextOverflow.Ellipsis)
}

// MARK: little labels

@Composable
fun Chip(text: String, fill: Color = T.olive, edge: Color = T.oliveEdge, ink: Color = T.oliveInk) {
    Text(text, style = ff(FF.Caption, FontWeight.Bold), color = ink,
        modifier = Modifier.background(fill, RoundedCornerShape(6.dp)).border(1.5.dp, edge, RoundedCornerShape(6.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp))
}

@Composable
fun RegChip(reg: String) {
    when (reg) {
        "白" -> Chip(tr("白"), T.green, T.greenEdge, T.greenInk)
        "文" -> Chip(tr("文"), T.blue, T.blueEdge, T.blueInk)
        "俗" -> Chip(tr("俗"), T.rust, T.rustEdge, T.rustInk)
    }
}

@Composable
fun OwnChip() = Chip(tr("自訂"), T.own, T.ownEdge, T.ownInk)

@Composable
fun PlaceChip(text: String) = Chip(text, T.placeFill, T.placeEdge, T.purpleInk)

@Composable
fun NumBadge(n: Int) {
    Box(Modifier.size(20.dp).background(T.fn, CircleShape).border(1.5.dp, T.oliveEdge, CircleShape), contentAlignment = Alignment.Center) {
        Text("$n", style = ff(FF.Caption2, FontWeight.ExtraBold), color = T.oliveInk)
    }
}

@Composable
fun Panel(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().background(T.fn.copy(alpha = 0.85f), RoundedCornerShape(22.dp))
            .border(2.dp, T.fnEdge, RoundedCornerShape(22.dp)).padding(16.dp),
        content = content,
    )
}

/** a surface in the app's plain style */
fun Modifier.surface(shape: Shape = RoundedCornerShape(18.dp), fill: Color = T.fn, edge: Color = T.fnEdge, width: Dp = 2.dp) =
    this.background(fill, shape).border(width, edge, shape)

// MARK: buttons

@Composable
fun SoftButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable RowScope.() -> Unit) {
    OutlinedButton(onClick = onClick, modifier = modifier, enabled = enabled, shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = T.fn.copy(alpha = 0.85f), contentColor = T.glyph,
            disabledContainerColor = T.fn.copy(alpha = 0.5f), disabledContentColor = T.muted),
        border = BorderStroke(1.dp, T.fnEdge), content = content)
}

@Composable
fun ProminentButton(onClick: () -> Unit, modifier: Modifier = Modifier, tint: Color = T.btnEdge, enabled: Boolean = true,
                    content: @Composable RowScope.() -> Unit) {
    Button(onClick = onClick, modifier = modifier, enabled = enabled, shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(containerColor = tint, contentColor = Color.White,
            disabledContainerColor = tint.copy(alpha = 0.35f), disabledContentColor = Color.White.copy(alpha = 0.6f)),
        content = content)
}

@Composable
fun IconLabel(icon: ImageVector, text: String, style: TextStyle = ff(FF.Headline), color: Color = Color.Unspecified) {
    Icon(icon, null, modifier = Modifier.size(20.dp), tint = if (color == Color.Unspecified) LocalContentColor.current else color)
    Spacer(Modifier.width(8.dp))
    Text(text, style = style, color = if (color == Color.Unspecified) LocalContentColor.current else color)
}

/** a capsule with an icon and text, e.g. 收藏 */
@Composable
fun CapsuleButton(text: String, icon: ImageVector?, on: Boolean, fill: Color, edge: Color, ink: Color, onClick: () -> Unit) {
    Row(
        Modifier.clip(CircleShape).background(if (on) fill else T.fn.copy(alpha = 0.8f)).border(1.5.dp, if (on) edge else T.fnEdge, CircleShape)
            .clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) { Icon(icon, null, tint = if (on) ink else T.glyph, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(5.dp)) }
        Text(text, style = ff(FF.Subheadline, FontWeight.SemiBold), color = if (on) ink else T.glyph)
    }
}

/** Round ▶ in the 方方 style; turns red briefly if the recording can't be found. */
@Composable
fun PlayButton(path: String, size: Dp = 34.dp) {
    val on = Player.playing == path
    val bad = Player.failed == path
    val fill = if (bad) T.rust else if (on) T.btnEdge else T.btn.copy(alpha = 0.6f)
    val edge = if (bad) T.rustEdge else T.btnEdge
    Box(
        Modifier.size(size).clip(CircleShape).background(fill).border(2.dp, edge, CircleShape).clickable { Player.play(path) },
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.PlayArrow, tr("播放"), tint = T.glyph, modifier = Modifier.size(size * 0.55f))
    }
}

// MARK: swelling (a word grows a little while pressed, or under the finger while sliding over words)

@Composable
fun Modifier.swell(big: Boolean): Modifier {
    // 設定 → 畫成圖再放大: off = words don't swell
    val on = Prefs.swellAnim.value
    val target = if (big && on) 1.16f else 1f
    val s by animateFloatAsState(target, spring(dampingRatio = 0.8f, stiffness = 900f), label = "swell")
    return this.zIndex(if (big) 1f else 0f).graphicsLayer { scaleX = s; scaleY = s }
}

/** a tappable piece of text that swells while pressed */
@Composable
fun SwellText(text: AnnotatedString, style: TextStyle, color: Color, hot: Boolean = false, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    Text(text, style = style, color = color,
        modifier = modifier.swell(pressed || hot).clickable(interactionSource = src, indication = null, onClick = onClick))
}

// MARK: the top bar: page title, back, and the spelling / 腔口 / 聲調 buttons

@Composable
fun RomButton() {
    var rom by Prefs.rom
    var zhRom by Prefs.zhRom
    val zh = com.unoki99.fangfang.Store.isZh
    // 華語: 拼音 ⇄ 注音; 台語: 皓羅 → 台羅 → 白話字
    Text(tr(if (zh) com.unoki99.fangfang.engine.Lang.romNames[zhRom.coerceIn(0, 1)] else ROM_NAMES[rom.coerceIn(0, 2)]),
        style = ff(FF.Subheadline, FontWeight.Bold), color = T.btnInk,
        modifier = Modifier.clip(CircleShape).background(T.btn).border(2.dp, T.btnEdge, CircleShape)
            .clickable { if (zh) zhRom = (zhRom + 1) % 2 else rom = (rom + 1) % 3 }.padding(horizontal = 10.dp, vertical = 4.dp))
}

/** 台語 / 華語, and where it's said: always the coloured capsule (台語 purple, 華語 blue), so you see which dictionary you're in */
@Composable
fun PlaceMenu() {
    var place by Prefs.place
    var zhPlace by Prefs.zhPlace
    val store = com.unoki99.fangfang.Store
    val zh = store.isZh
    var open by remember { mutableStateOf(false) }
    val fill = if (zh) Color(0xFF1F3D6B) else T.placeFill
    val edge = if (zh) Color(0xFF4F7DFF) else T.placeEdge
    val ink = if (zh) Color(0xFF9AD0FF) else T.purpleInk
    val name = if (zh) "華・" + com.unoki99.fangfang.engine.Lang.placeNames[zhPlace.coerceIn(0, 1)]
        else "台・" + (if (place in PLACE_NAMES.indices) PLACE_NAMES[place].take(2) else "通行")
    Box {
        Row(Modifier.clip(CircleShape).background(fill).border(2.dp, edge, CircleShape).clickable { open = true }
            .padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            if (store.switching) { CircularProgressIndicator(Modifier.size(12.dp), color = ink, strokeWidth = 2.dp); Spacer(Modifier.width(4.dp)) }
            Text(name, style = ff(FF.Subheadline, FontWeight.Bold), color = ink)
            Icon(Icons.Filled.KeyboardArrowDown, null, tint = ink, modifier = Modifier.size(14.dp))
        }
        DropdownMenu(open, { open = false }, containerColor = T.fn) {
            @Composable fun item(text: String, on: Boolean, onClick: () -> Unit) =
                DropdownMenuItem(text = { Text(text, color = T.glyph) },
                    leadingIcon = { if (on) Icon(Icons.Filled.Check, null, tint = T.greenInk) else Spacer(Modifier.size(24.dp)) },
                    onClick = onClick)
            Text(tr("語言"), style = ff(FF.Caption, FontWeight.Bold), color = T.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            item(tr("台語"), !zh) { store.setLanguage(false); open = false }
            item(tr("華語"), zh) { store.setLanguage(true); open = false }
            HorizontalDivider(color = T.fnEdge)
            if (zh) {
                Text(tr("華語讀音"), style = ff(FF.Caption, FontWeight.Bold), color = T.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
                com.unoki99.fangfang.engine.Lang.placeNames.forEachIndexed { i, p -> item(tr(p), zhPlace == i) { zhPlace = i; open = false } }
            } else {
                Text(tr("台語腔口"), style = ff(FF.Caption, FontWeight.Bold), color = T.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
                item(tr("通行"), place < 0) { place = -1; open = false }
                PLACE_NAMES.forEachIndexed { i, p -> item(tr(p), place == i) { place = i; open = false } }
            }
        }
    }
}

@Composable
fun ToneMenu() {
    var system by Prefs.toneSys
    var marks by Prefs.toneMarks
    var glow by Prefs.toneGlow
    var open by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.clip(CircleShape).background(T.fn).border(2.dp, T.fnEdge, CircleShape).clickable { open = true }
            .padding(horizontal = 9.dp, vertical = 7.dp), horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
            if (system == 0) Text(tr("調"), style = ff(FF.Subheadline, FontWeight.Bold), color = T.muted)
            else for (t in if (system == 5) listOf(1, 2, 3, 5, 6, 7) else listOf(1, 2, 3, 4, 5, 6, 7, 8)) {
                Box(Modifier.size(5.dp).background(Color(com.unoki99.fangfang.engine.ToneColors.color(t, system) ?: 0xFF888888.toInt()), CircleShape))
            }
        }
        DropdownMenu(open, { open = false }, containerColor = T.fn) {
            for ((v, name) in listOf(0 to tr("關"), 7 to tr("七聲（1 2 3 4 5 7 8）"), 5 to tr("五聲（1=8、3=4）"))) {
                DropdownMenuItem(text = { Text(name, color = if (system == v) T.greenInk else T.glyph) },
                    leadingIcon = { if (system == v) Icon(Icons.Filled.Check, null, tint = T.greenInk) }, onClick = { system = v; open = false })
            }
            if (system != 0) {
                HorizontalDivider(color = T.fnEdge)
                DropdownMenuItem(text = { Text(tr("聲調符號照變調寫"), color = T.glyph) },
                    leadingIcon = { Checkbox(marks, null) }, onClick = { marks = !marks })
                DropdownMenuItem(text = { Text(tr("聲調光暈"), color = T.glyph) },
                    leadingIcon = { Checkbox(glow, null) }, onClick = { glow = !glow })
            }
        }
    }
}

@Composable
fun BarButtons(settings: Boolean = true) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        RomButton(); PlaceMenu(); ToneMenu()
        if (settings) IconButton(onClick = { UI.settingsOpen = true }) { Icon(Icons.Filled.Settings, tr("設定"), tint = T.glyph) }
    }
}

/** a page's top bar: back (or close), title, the page's own buttons, then the spelling / 腔口 / 聲調 buttons */
@Composable
fun TopBar(title: String, onBack: (() -> Unit)? = null, close: Boolean = false, settings: Boolean = true,
           extra: @Composable RowScope.() -> Unit = {}) {
    Row(Modifier.fillMaxWidth().statusBarsPadding().height(52.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        if (onBack != null) {
            IconButton(onClick = onBack) {
                Icon(if (close) Icons.Filled.Close else Icons.AutoMirrored.Filled.ArrowBack, if (close) tr("結束") else tr("返回"), tint = T.glyph)
            }
        } else Spacer(Modifier.width(12.dp))
        Text(title, style = ff(FF.Headline), color = T.glyph, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        extra()
        Spacer(Modifier.width(4.dp))
        BarButtons(settings)
        Spacer(Modifier.width(4.dp))
    }
}

/** a section title in a list */
@Composable
fun SectionTitle(text: String) {
    Text(text, style = ff(FF.Footnote, FontWeight.SemiBold), color = T.muted, modifier = Modifier.padding(start = 4.dp, top = 14.dp, bottom = 6.dp))
}

/** rows of a list on a dark panel */
@Composable
fun ListCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(T.fn.copy(alpha = 0.7f)), content = content)
}

@Composable
fun RowDivider() = HorizontalDivider(color = T.fnEdge.copy(alpha = 0.6f), thickness = 0.5.dp, modifier = Modifier.padding(start = 14.dp))

/** a search field in the app's style */
@Composable
fun SearchField(value: String, onChange: (String) -> Unit, hint: String, modifier: Modifier = Modifier, fontSize: TextUnit = 18.sp, family: FontFamily? = null) {
    val focus = remember { androidx.compose.ui.focus.FocusRequester() }
    TextField(
        value, onChange, modifier = modifier.fillMaxWidth().focusRequester(focus), singleLine = true,
        placeholder = { Text(hint, color = T.muted, style = TextStyle(fontSize = 15.sp)) },
        textStyle = TextStyle(fontSize = fontSize, color = T.glyph, fontFamily = family),
        leadingIcon = { Icon(Icons.Filled.Search, null, tint = T.muted) },
        trailingIcon = { ClearIcon(value, onChange, focus) },
        shape = RoundedCornerShape(14.dp),
        colors = TextFieldDefaults.colors(focusedContainerColor = T.fn.copy(alpha = 0.85f), unfocusedContainerColor = T.fn.copy(alpha = 0.7f),
            focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent, cursorColor = T.greenInk),
    )
}

/** the ⓧ at the end of a text field while it has text: empties it and puts the cursor back in it */
@Composable
fun ClearIcon(value: String, onChange: (String) -> Unit, focus: FocusRequester) {
    if (value.isNotEmpty()) IconButton(onClick = { onChange(""); try { focus.requestFocus() } catch (_: Exception) {} }) {
        Icon(Icons.Filled.Cancel, tr("清除"), tint = T.muted)
    }
}
