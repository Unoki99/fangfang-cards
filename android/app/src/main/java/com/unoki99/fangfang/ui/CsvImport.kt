package com.unoki99.fangfang.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.unoki99.fangfang.Prefs
import com.unoki99.fangfang.Store
import com.unoki99.fangfang.tr
import com.unoki99.fangfang.engine.*

// 詞典 → 自訂 → 從 CSV 檔加入: many of your own 台語 words at once, from a CSV (or tab-separated) file. You say which
// column has what: 漢字 and 讀音 (needed), and the meaning and an example sentence (if the file has them).
// (The same as the iPhone app's CsvImport.swift.)

/** a CSV / TSV file's rows: commas, tabs or semicolons (whichever the first lines use most), quotes as in Excel */
object CsvText {
    fun decode(bytes: ByteArray): String {
        var b = bytes
        if (b.size >= 3 && b[0] == 0xEF.toByte() && b[1] == 0xBB.toByte() && b[2] == 0xBF.toByte()) b = b.copyOfRange(3, b.size)
        val s = String(b, Charsets.UTF_8)
        if (!s.contains('�')) return s
        // (an older file from Excel on a Taiwanese computer)
        return try { String(bytes, charset("Big5")) } catch (_: Exception) { s }
    }

    fun rows(text: String): List<List<String>> {
        val head = text.take(4000)
        val sep = listOf(',', '\t', ';').maxByOrNull { c -> head.count { it == c } } ?: ','
        val rows = ArrayList<List<String>>()
        var row = ArrayList<String>()
        val cell = StringBuilder()
        var quoted = false
        val t = if (text.endsWith("\n")) text else text + "\n"
        var i = 0
        fun endRow() {
            row.add(cell.toString()); cell.setLength(0)
            if (row.any { it.isNotBlank() }) rows.add(row.map { it.trim() })
            row = ArrayList()
        }
        while (i < t.length) {
            val c = t[i]
            if (quoted) {
                if (c == '"') {
                    if (i + 1 < t.length && t[i + 1] == '"') { cell.append('"'); i++ } else quoted = false
                } else cell.append(c)
            } else if (c == '"' && cell.isEmpty()) quoted = true
            else if (c == sep) { row.add(cell.toString()); cell.setLength(0) }
            else if (c == '\r') { endRow(); if (i + 1 < t.length && t[i + 1] == '\n') i++ }
            else if (c == '\n') endRow()
            else cell.append(c)
            i++
        }
        return rows
    }
}

/** one word of your own: its 漢字 and reading → the reading's syllables, or what's wrong (the same rules as 加一個詞) */
fun ownWordCheck(d: Dict, engine: ConvertEngine, hanIn: String, reading: String): Pair<List<String>?, String> {
    val h = hanIn.trim()
    val chars = h.cps()
    if (h.isEmpty()) return Pair(null, tr("先寫漢字。"))
    if (chars.any { !ConvertEngine.isHan(it.firstCp()) }) return Pair(null, tr("漢字欄只能寫漢字。"))
    if (reading.trim().isEmpty()) return Pair(null, tr("再寫讀音。"))
    val codes = ArrayList<String>()
    for (it in engine.convert(reading).items) {
        if (it.space || it.newline) continue
        val raw = it.raw
        if (raw != null) {
            if (raw.trim(' ', '-', '‑', '–').isEmpty()) continue
            return Pair(null, tr("看不懂「{0}」這個讀音。", raw))
        }
        val c = it.current.codes ?: return Pair(null, tr("看不懂這個讀音。"))
        codes.addAll(c)
    }
    val key = h + "\t" + codes.joinToString(" ")
    return when {
        codes.isEmpty() -> Pair(null, tr("看不懂這個讀音。"))
        codes.size != chars.size -> Pair(null, tr("讀音有 {0} 個音節，漢字有 {1} 個字，要一樣多。", codes.size, chars.size))
        d.baseKeys.contains(key) || d.altParent[key] != null -> Pair(null, tr("辭典裡已經有這個詞了。"))
        Store.isOwn(key) -> Pair(null, tr("這個詞已經在「自訂」裡了。"))
        else -> Pair(codes, "")
    }
}

/** the reading looks like it's written in this spelling (0 皓羅, 1 台羅, 2 白話字, 3 方音): the same letters as the app
 *  writes them, the tones and hyphens aside */
private fun looksLike(d: Dict, reading: String, codes: List<String>, system: Int): Boolean {
    fun plain(s: String) = java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD)
        .filter { it.code !in 0x300..0x36F && !it.isDigit() && it != ' ' && it != '-' && it != '‑' && it != '–' }.lowercase()
    return plain(reading) == plain(d.codes(codes.joinToString(" "), system, -1))
}

class CsvFile(val name: String, val rows: List<List<String>>)

private class CsvRow(val line: Int, val han: String, val codes: List<String>?, val problem: String,
                     val meaning: String, val example: String, val unlike: Boolean)

/** which column has what, a look at the result, and 加入 */
@Composable
fun CsvImportDialog(d: Dict, file: CsvFile, onDone: (Int?) -> Unit) {
    val engine = remember { ConvertEngine(d, Prefs) }
    val columns = remember(file) { file.rows.maxOfOrNull { it.size } ?: 0 }
    var header by remember { mutableStateOf(true) }
    var colHan by remember { mutableStateOf(0) }
    var colReading by remember { mutableStateOf(1) }
    var colMeaning by remember { mutableStateOf(-1) }
    var colExample by remember { mutableStateOf(-1) }
    /** the reading's spelling: -1 any, 0 皓羅, 1 台羅, 2 白話字, 3 方音 */
    var system by remember { mutableStateOf(-1) }
    // a first guess: a title line or not, and which column has the 漢字, the reading and the meaning
    LaunchedEffect(file) {
        val first = file.rows.firstOrNull() ?: return@LaunchedEffect
        fun isHan(s: String) = s.isNotEmpty() && s.cps().all { ConvertEngine.isHan(it.firstCp()) }
        fun isReading(s: String) = s.isNotEmpty() && s.any { it.isLetter() } && s.cps().none { ConvertEngine.isHan(it.firstCp()) }
        val body = file.rows.drop(1).take(30)
        fun share(c: Int, f: (String) -> Boolean): Double {
            val xs = body.mapNotNull { it.getOrNull(c) }
            return if (xs.isEmpty()) 0.0 else xs.count(f).toDouble() / xs.size
        }
        val hc = (0 until columns).maxByOrNull { share(it, ::isHan) } ?: 0
        val rc = (0 until columns).filter { it != hc }.maxByOrNull { share(it, ::isReading) } ?: minOf(1, columns - 1)
        colHan = hc; colReading = rc
        colMeaning = (0 until columns).firstOrNull { it != hc && it != rc } ?: -1
        header = !isHan(first.getOrElse(hc) { "" }) || !isReading(first.getOrElse(rc) { "" })
        // (a file this app exported, or one with its columns named: the meaning and example columns by their names)
        val names = first.map { it.lowercase() }
        names.indexOfFirst { it == "meaning" || it == "意思" }.let { if (it >= 0 && it != hc && it != rc) colMeaning = it }
        names.indexOfFirst { it == "example" || it == "例句" }.let { if (it >= 0 && it != hc && it != rc && it != colMeaning) colExample = it }
    }
    val results = remember(header, colHan, colReading, colMeaning, colExample, system, Store.rev) {
        val out = ArrayList<CsvRow>(); val seen = HashSet<String>()
        val off = if (header) 2 else 1
        val rows = if (header) file.rows.drop(1) else file.rows
        for ((i, r) in rows.withIndex()) {
            fun at(c: Int) = if (c >= 0) r.getOrElse(c) { "" } else ""
            val han = at(colHan); val reading = at(colReading)
            val (codes, problem) = ownWordCheck(d, engine, han, reading)
            if (codes == null) { out.add(CsvRow(i + off, han, null, problem, "", "", false)); continue }
            val key = han.trim() + "\t" + codes.joinToString(" ")
            if (!seen.add(key)) { out.add(CsvRow(i + off, han, null, tr("檔案裡已經有這個詞了。"), "", "", false)); continue }
            out.add(CsvRow(i + off, han.trim(), codes, "", at(colMeaning), at(colExample), system >= 0 && !looksLike(d, reading, codes, system)))
        }
        out
    }
    val good = results.filter { it.codes != null }
    fun sample(c: Int): String {
        val s = file.rows.firstOrNull()?.getOrNull(c) ?: return ""
        if (s.isEmpty()) return ""
        return "：" + (if (s.length > 14) s.take(14) + "…" else s)
    }
    fun colName(c: Int) = if (c < 0) tr("沒有") else tr("第 {0} 欄", c + 1) + sample(c)

    Dialog(onDismissRequest = { onDone(null) }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth(0.94f).fillMaxHeight(0.9f), shape = RoundedCornerShape(18.dp), color = T.fn) {
            Column(Modifier.padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { onDone(null) }) { Text(tr("取消"), color = T.muted) }
                    Txt(tr("從 CSV 檔加入"), ff(FF.Headline), T.glyph, Modifier.weight(1f))
                    TextButton(onClick = {
                        Store.addOwn(good.map { Triple(it.han + "\t" + it.codes!!.joinToString(" "), it.meaning, it.example) })
                        onDone(good.size)
                    }, enabled = good.isNotEmpty()) { Text(tr("加入 {0} 個", good.size), color = if (good.isNotEmpty()) T.btnInk else T.muted) }
                }
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    item {
                        Txt(file.name + "　" + tr("{0} 行", if (header) file.rows.size - 1 else file.rows.size), ff(FF.Footnote), T.muted)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Txt(tr("第一行是標題"), ff(FF.Body), T.glyph, Modifier.weight(1f))
                            Switch(header, { header = it })
                        }
                        SectionTitle(tr("哪一欄是什麼"))
                        Chooser(tr("漢字"), colName(colHan), (0 until columns).map { it to colName(it) }) { colHan = it }
                        Chooser(tr("讀音"), colName(colReading), (0 until columns).map { it to colName(it) }) { colReading = it }
                        val systems = listOf(-1 to tr("自動（每個讀音照它的寫法讀）"), 0 to tr("皓羅"), 1 to tr("台羅"), 2 to tr("白話字"), 3 to tr("方音"))
                        Chooser(tr("讀音的寫法"), systems.first { it.first == system }.second, systems) { system = it }
                        Chooser(tr("意思"), colName(colMeaning), listOf(-1 to tr("沒有")) + (0 until columns).map { it to colName(it) }) { colMeaning = it }
                        Chooser(tr("例句"), colName(colExample), listOf(-1 to tr("沒有")) + (0 until columns).map { it to colName(it) }) { colExample = it }
                        Txt(tr("漢字和讀音一定要有；意思和例句可以沒有。讀音用皓羅、台羅、白話字或方音都可以，聲調寫符號或數字都可以。選了寫法的話，不像那種寫法的讀音會標出來，請看一下對不對。"),
                            ff(FF.Caption), T.muted, Modifier.padding(vertical = 4.dp))
                        SectionTitle(tr("結果"))
                        Txt(tr("可以加入 {0} 個詞", good.size) + (if (results.size > good.size) tr("；{0} 行沒辦法加入", results.size - good.size) else ""), ff(FF.Headline), T.glyph)
                    }
                    items(results.take(60), key = { it.line }) { r ->
                        val codes = r.codes
                        if (codes != null) {
                            val cs = codes.joinToString(" ")
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Txt(r.han, sz(19f, FontWeight.SemiBold), T.ownInk)
                                    Txt(d.codes(cs, 0, -1), lat(15f), T.greenInk)
                                    if (TwRom.line) Txt(d.codes(cs, 3, -1), ff(FF.Footnote), T.purpleInk)
                                }
                                if (r.meaning.isNotEmpty()) Txt(r.meaning, ff(FF.Footnote), T.glyph.copy(alpha = 0.8f), maxLines = 2)
                                if (r.example.isNotEmpty()) Txt(tr("例：") + r.example, ff(FF.Footnote), T.muted, maxLines = 2)
                                if (r.unlike) Txt(tr("第 {0} 行：讀音不像選的寫法，請看一下對不對。", r.line), ff(FF.Caption), T.rustInk)
                            }
                        } else Txt(tr("第 {0} 行", r.line) + (if (r.han.isEmpty()) "" else "「${r.han}」") + "：" + r.problem, ff(FF.Footnote), T.rustInk)
                    }
                    if (results.size > 60) item { Txt(tr("（只列出前 60 行）"), ff(FF.Footnote), T.muted) }
                }
            }
        }
    }
}

/** a choice from a list (which column, which spelling) */
@Composable
private fun Chooser(label: String, current: String, options: List<Pair<Int, String>>, onPick: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(T.bg.copy(alpha = 0.35f)).clickable { open = true }
            .padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Txt(label, ff(FF.Body), T.glyph, Modifier.weight(1f))
            Txt(current, ff(FF.Body), T.btnInk, maxLines = 1)
        }
        DropdownMenu(open, { open = false }) {
            for ((v, name) in options) DropdownMenuItem(text = { Text(name) }, onClick = { onPick(v); open = false })
        }
    }
}
