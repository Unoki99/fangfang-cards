package com.unoki99.fangfang.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Brush
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.tr
import org.json.JSONArray
import org.json.JSONObject

// MARK: - writing in the games played together (一起玩): the same squares as the other games', and the writing sent
// to the others as lines (the same as the iPhone app's: each square a list of strokes {"c": "#rrggbb", "p": [x, y,
// width, x, y, width…]}, x / y / width as parts of the square's side), so every version can draw every other's.

class InkLine(val color: String, val p: List<Double>) {
    fun json(): JSONObject = JSONObject().put("c", color).put("p", JSONArray(p))
    companion object {
        fun of(o: JSONObject): InkLine {
            val a = o.optJSONArray("p") ?: JSONArray()
            return InkLine(o.optString("c", "#1a1a1c"), (0 until a.length()).map { a.optDouble(it) })
        }
        fun squaresJson(sq: List<List<InkLine>>): JSONArray = JSONArray(sq.map { s -> JSONArray(s.map { it.json() }) })
        fun squaresOf(a: JSONArray?): List<List<InkLine>> {
            if (a == null) return emptyList()
            return (0 until a.length()).map { i -> val s = a.optJSONArray(i) ?: JSONArray(); (0 until s.length()).map { of(s.optJSONObject(it) ?: JSONObject()) } }
        }
        /** one square's writing as lines (side: the square's side in px) */
        fun from(strokes: List<InkStroke>, side: Float, rainbow: Boolean, ink: Color): List<InkLine> {
            if (side <= 0f) return emptyList()
            val period = side * 1.6f
            var dist = 0f
            return strokes.map { s ->
                val c = if (rainbow) HandInk.color(dist, period) else ink
                for (i in 1 until s.pts.size) dist += (s.pts[i] - s.pts[i - 1]).getDistance()
                val p = ArrayList<Double>()
                for (i in s.pts.indices) { p.add((s.pts[i].x / side).toDouble()); p.add((s.pts[i].y / side).toDouble()); p.add((s.ws.getOrElse(i) { 6f } / side).toDouble()) }
                InkLine(hex(c), p)
            }
        }
        fun hex(c: Color): String = "#%02x%02x%02x".format((c.red * 255).toInt(), (c.green * 255).toInt(), (c.blue * 255).toInt())
        fun color(h: String): Color = try { Color(0xFF000000L or h.removePrefix("#").toLong(16)) } catch (_: Exception) { HandInk.dark }
    }
}

/** squares to write a word in when the app doesn't know the word (一起玩): start with one, 加一個格子 adds one, 少一格
 *  takes the last away; the pen as chosen (筆). `squares` holds the writing; `side` each square's side in px. */
@Composable
fun GameWriteSquares(squares: SnapshotStateList<SnapshotStateList<InkStroke>>, onSide: (Float) -> Unit) {
    var fixed by Prefs.handTestPad
    var cur by remember { mutableIntStateOf(0) }
    var side by remember { mutableStateOf(0f) }
    val setSide: (Float) -> Unit = { side = it; onSide(it) }
    if (squares.isEmpty()) squares.add(mutableStateListOf())
    if (cur >= squares.size) cur = squares.size - 1
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val mw = maxWidth
        val wide = mw > 600.dp
        val want = fixed.coerceIn(140f, 640f).dp
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            if (wide) {
                val n = squares.size
                val s = minOf(want, (mw - 12.dp * (n - 1)) / n).coerceAtLeast(110.dp)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { for (i in 0 until n) WordPad(squares[i], Modifier.size(s), setSide) }
            } else {
                if (squares.size > 1) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (i in squares.indices) Box(Modifier.size(52.dp).clip(RoundedCornerShape(10.dp)).background(T.fn.copy(alpha = 0.75f))
                        .border(if (i == cur) 2.5.dp else 1.dp, if (i == cur) T.btnEdge else T.fnEdge, RoundedCornerShape(10.dp)).clickable { cur = i }) {
                        InkPreview(squares[i], side)
                    }
                }
                key(cur) { WordPad(squares[cur], Modifier.size(minOf(want, mw)), setSide) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SoftButton({ if (wide) for (s in squares) s.clear() else squares[cur].clear() }, Modifier.weight(1f)) { Text(if (wide && squares.size > 1) tr("全部清掉") else tr("清掉")) }
                SoftButton({ if (squares.size > 1) { squares.removeAt(squares.size - 1); cur = minOf(cur, squares.size - 1) } }, Modifier.weight(1f), enabled = squares.size > 1) { Text(tr("少一格")) }
                SoftButton({ if (squares.size < 8) { squares.add(mutableStateListOf()); cur = squares.size - 1 } }, Modifier.weight(1f), enabled = squares.size < 8) { Text(tr("加一個格子")) }
            }
            Slider(fixed, { fixed = it }, Modifier.widthIn(max = 420.dp), valueRange = 140f..640f,
                colors = SliderDefaults.colors(thumbColor = T.btnEdge, activeTrackColor = T.btnEdge))
        }
    }
}

/** a square's writing, small (the strokes as they were written; side: the square they were written in, px) */
@Composable
private fun InkPreview(strokes: List<InkStroke>, side: Float) {
    Canvas(Modifier.fillMaxSize()) {
        if (side <= 0f) return@Canvas
        val k = size.width / side
        for (s in strokes) {
            if (s.pts.size == 1) drawCircle(HandInk.solid, (s.ws[0] * k / 2).coerceAtLeast(1f), s.pts[0] * k)
            for (i in 1 until s.pts.size) drawLine(HandInk.solid, s.pts[i - 1] * k, s.pts[i] * k, (s.ws.getOrElse(i) { 6f } * k).coerceAtLeast(1f), cap = StrokeCap.Round)
        }
    }
}

/** someone's writing in squares, as they wrote it (一起玩: the answer on the others' screens) */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WrittenSquares(squares: List<List<InkLine>>, size: Dp = 120.dp) {
    val edge = T.fnEdge
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (sq in squares) Box(Modifier.size(size).clip(RoundedCornerShape(12.dp)).background(T.fn.copy(alpha = 0.75f)).border(1.dp, T.fnEdge, RoundedCornerShape(12.dp))) {
            Canvas(Modifier.fillMaxSize()) {
                val w = this.size.width; val h = this.size.height
                val dash = PathEffect.dashPathEffect(floatArrayOf(5 * density, 5 * density))
                drawLine(edge, Offset(w / 2, 0f), Offset(w / 2, h), density, pathEffect = dash)
                drawLine(edge, Offset(0f, h / 2), Offset(w, h / 2), density, pathEffect = dash)
                for (l in sq) {
                    val c = InkLine.color(l.color)
                    val n = l.p.size / 3
                    if (n == 1) drawCircle(c, (l.p[2] * w / 2).toFloat().coerceAtLeast(1f), Offset((l.p[0] * w).toFloat(), (l.p[1] * h).toFloat()))
                    for (i in 1 until n) {
                        val a = Offset((l.p[(i - 1) * 3] * w).toFloat(), (l.p[(i - 1) * 3 + 1] * h).toFloat())
                        val b = Offset((l.p[i * 3] * w).toFloat(), (l.p[i * 3 + 1] * h).toFloat())
                        drawLine(c, a, b, ((l.p[i * 3 + 2] * w).toFloat()).coerceAtLeast(1f), cap = StrokeCap.Round)
                    }
                }
            }
        }
    }
}

/** 筆: the pen's settings (粗細, 延遲, 筆壓, 顏色), as in 手寫練習 */
@Composable
fun PenButton() {
    var open by remember { mutableStateOf(false) }
    IconButton(onClick = { open = true }) { Icon(Icons.Filled.Brush, tr("筆"), tint = T.glyph) }
    if (open) AlertDialog(onDismissRequest = { open = false }, containerColor = T.bg,
        confirmButton = { TextButton(onClick = { open = false }) { Text(tr("完成"), color = T.btnInk) } },
        title = { Txt(tr("筆"), ff(FF.Headline, FontWeight.SemiBold), T.glyph) },
        text = { Column(Modifier.dragScrollY(rememberScrollState())) { PenControls(); Spacer(Modifier.height(12.dp)); InkColorControls() } })
}

/** 房間: the room code (open a new room, or join one), the relay chosen in 設定, and who's here */
@Composable
fun RoomBar(link: com.unoki99.fangfang.RoomLink, locked: Boolean) {
    var code by remember { mutableStateOf(link.code) }
    val server = Prefs.relayServer.value
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(T.fn.copy(alpha = 0.55f)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (link.status != 2) {
            Txt(tr("用同一個房間代碼和別人連線（透過網路；iPhone、Android、電腦都可以一起玩）。"), ff(FF.Footnote), T.muted)
            GameField(code, { code = it.uppercase() }, tr("房間代碼，例如 KX7P-2MQA"), style = lat(18f)) { link.open(server, code) }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SoftButton({ code = com.unoki99.fangfang.RoomCrypto.newCode(); link.open(server, code) }, Modifier.weight(1f)) { Text(tr("開一個新房間")) }
                ProminentButton({ link.open(server, code) }, Modifier.weight(1f), enabled = code.isNotBlank() && link.status != 1) {
                    Text(if (link.status == 1) tr("連線中…") else tr("進房間"))
                }
            }
            link.error?.let { Txt(it, ff(FF.Footnote), T.rustInk) }
            if (server.isBlank()) Txt(tr("還沒有連線伺服器：設定 → 卡片與練習 → 一起玩 → 連線伺服器（專案的 relay 資料夾說明怎麼免費放一個）。"), ff(FF.Caption), T.muted)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Txt(tr("房間"), ff(FF.Caption), T.muted)
                Txt(link.code, lat(18f), T.glyph, Modifier.weight(1f))
                if (!locked) TextButton(onClick = { link.close() }) { Text(tr("離開房間"), color = T.rustInk) }
            }
            Txt(tr("請其他人在「一起玩」輸入同一個代碼。訊息在 App 裡就加密了，伺服器看不懂。"), ff(FF.Caption), T.muted)
        }
    }
}
