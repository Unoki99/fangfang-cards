package com.unoki99.fangfang

import android.annotation.SuppressLint
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.GZIPInputStream
import java.util.zip.ZipFile
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

// MARK: - 詞典資料: installing the dictionaries in the app
//
// The dictionaries' licences don't allow sharing changed versions of them, so the app has no dictionary data in it.
// It fetches the original files from where their makers publish them and makes its own copy, on the phone, with
// the same converters as the iPhone app (assets/install/*.js, run in a hidden WebView). The data made is kept in
// the app's files (Dictionaries/).

/** where the dictionaries' data files are: installed in the app, or (built by hand) in its assets */
object DataFiles {
    val folder: File get() = File(Store.app.filesDir, "Dictionaries").apply { mkdirs() }
    fun installed(name: String) = File(folder, "$name.json")
    fun isInstalled(name: String) = installed(name).exists()
    fun isBuiltIn(name: String): Boolean = try { Store.app.assets.open("$name.json").close(); true } catch (_: Exception) { false }
    fun has(name: String) = isInstalled(name) || isBuiltIn(name)
    fun size(name: String): Long = installed(name).let { if (it.exists()) it.length() else 0L }
    /** the file to read line by line (the installed copy first), or null */
    fun reader(name: String): java.io.BufferedReader? {
        val f = installed(name)
        if (f.exists()) return try { java.io.BufferedReader(java.io.InputStreamReader(java.io.FileInputStream(f), Charsets.UTF_8), 1 shl 16) } catch (_: Exception) { null }
        return try { java.io.BufferedReader(java.io.InputStreamReader(Store.app.assets.open("$name.json"), Charsets.UTF_8), 1 shl 16) } catch (_: Exception) { null }
    }
    /** the file's text (the installed copy first), or null */
    fun readText(name: String): String? {
        val f = installed(name)
        if (f.exists()) return try { f.readText() } catch (_: Exception) { null }
        return try { Store.app.assets.open("$name.json").bufferedReader().use { it.readText() } } catch (_: Exception) { null }
    }
}

/** one dictionary: where its original files are, and the converter that makes the app's file from them */
class DictPack(
    val id: String,
    /** the language (0 台語, 1 華語, 2 粵語, 3 客語, 4 日語; -1 說文解字) */
    val lang: Int,
    val name: String,
    /** the app's files it makes ("hak" → hak.json) */
    val outputs: List<String>,
    val sources: List<Source>,
    /** install/<script>.js and the function in it */
    val script: String,
    val function: String,
    val from: String,
    val download: String,
    /** files in the app the converter reads too (argument → file in assets/install) */
    val bundled: Map<String, String> = emptyMap(),
) {
    class Source(val file: String, val url: String, val optional: Boolean = false, val arg: String? = null)

    companion object {
        private const val G = "https://raw.githubusercontent.com/"
        private val essay = Source("essay.txt", G + "rime/rime-essay/master/essay.txt", optional = true)
        private val cedict = Source("cedict_ts.u8", G + "cschiller/zhongwen/main/data/cedict_ts.u8", optional = true)

        val taigi = DictPack("tw", 0, "台語", listOf("dict", "cards"),
            listOf(Source("kautian.ods", "https://sutian.moe.edu.tw/media/senn/ods/kautian.ods"),
                Source("essay.txt", G + "rime/rime-essay/master/essay.txt")),
            "taigi", "buildTaigi", "教育部《臺灣台語常用詞辭典》（CC BY-ND 3.0 臺灣）、rime-essay 字頻", "約 15 MB",
            bundled = mapOf("own" to "twown.json"))

        val mandarin = DictPack("zh", 1, "華語", listOf("zh", "inputcodes"),
            listOf(Source("dict-csld.json", G + "g0v/moedict-data-csld/master/dict-csld.json", arg = "csld"),
                Source("essay.txt", G + "rime/rime-essay/master/essay.txt"),
                cedict,
                Source("hsk30.csv", G + "ivankra/hsk30/master/hsk30-expanded.csv", optional = true, arg = "hsk"),
                Source("tocfl.csv", G + "ivankra/tocfl/master/expanded/tocfl.csv", optional = true, arg = "tocfl"),
                Source("dict-revised.json.xz", G + "g0v/moedict-data/master/dict-revised.json.xz", optional = true, arg = "moe"),
                Source("hsk30-chars.csv", G + "ivankra/hsk30/master/hsk30-chars.csv", optional = true, arg = "hskChars"),
                Source("tbcl-chars.csv", G + "ivankra/tocfl/master/tbcl-chars.csv", optional = true, arg = "tbclChars"),
                Source("ids.txt", G + "cjkvi/cjkvi-ids/master/ids.txt", optional = true, arg = "ids"),
                Source("cj.yaml", G + "rime/rime-cangjie/master/cangjie5.base.dict.yaml", optional = true, arg = "cjBase"),
                Source("cjx.yaml", G + "rime/rime-cangjie/master/cangjie5.extended.dict.yaml", optional = true, arg = "cjExt"),
                Source("wb.yaml", G + "rime/rime-wubi/master/wubi86.dict.yaml", optional = true, arg = "wubi")),
            "mandarin", "buildMandarinAll",
            "中華文化總會《兩岸常用詞典》（CC BY-NC-ND，g0v 萌典整理）、教育部《重編國語辭典修訂本》、CC-CEDICT、HSK 3.0 和 TOCFL 詞表、倉頡和五筆碼表（Rime）",
            "約 60 MB")

        val cantonese = run {
            val jd = G + "aaronhktan/jyut-dict/main/src/dictionaries/cedict/data/"
            val rc = G + "rime/rime-cantonese/main/"
            DictPack("yue", 2, "粵語", listOf("yue"),
                listOf(Source(cedict.file, cedict.url, arg = "cedict"),
                    Source("CC-CANTO.txt", jd + "CC-CANTO.txt", arg = "canto"),
                    Source("READINGS.txt", jd + "READINGS.txt", arg = "readings"),
                    Source("jyut6ping3.words.dict.yaml", rc + "jyut6ping3.words.dict.yaml", arg = "words"),
                    Source("jyut6ping3.chars.dict.yaml", rc + "jyut6ping3.chars.dict.yaml", arg = "chars"),
                    Source("essay-cantonese.txt", rc + "essay-cantonese.txt", arg = "essay"),
                    Source("yyzd.txt", G + "kfcd/yyzd/master/dist/tsv/%E7%B9%81%E9%AB%94/%E7%B2%B5%E8%AA%9E%E5%AD%97%E5%85%B8_%28%E7%B2%B5%E6%8B%BC%29.txt", arg = "yyzd")),
                "cantonese", "buildCantonese",
                "CC-CEDICT、CC-Canto（CC BY-SA）、rime-cantonese（CC BY 4.0）、開放粵語字典（CC BY 3.0）", "約 25 MB")
        }

        val hakka = run {
            val base = "https://hakkadict.moe.edu.tw/static/resource/客語資源下載/本辭典的文字/"
            val files = listOf("四縣", "海陸", "大埔", "饒平", "詔安", "南四縣").map { Source(it + "腔詞條詞目文字.ods", base + it + "腔詞條詞目文字.ods", optional = it != "四縣") }
            DictPack("hak", 3, "客語", listOf("hak"), files + listOf(essay, cedict), "hakka", "buildHakka",
                "教育部《臺灣客語辭典》（六個腔，CC BY-ND 3.0 臺灣）、rime-essay 詞頻、CC-CEDICT 英文解釋", "約 20 MB")
        }

        val japanese = DictPack("ja", 4, "日語", listOf("ja"),
            listOf(Source("JMdict_e_examp.gz", "http://ftp.edrdg.org/pub/Nihongo/JMdict_e_examp.gz", arg = "jmdict"),
                Source("kanjidic2.xml.gz", "http://ftp.edrdg.org/pub/Nihongo/kanjidic2.xml.gz", optional = true, arg = "kanjidic")),
            "japanese", "buildJapanese", "JMdict 與 KANJIDIC2（Electronic Dictionary Research and Development Group，CC BY-SA 4.0），例句來自 Tatoeba（CC BY 2.0 FR）", "約 25 MB")

        val shuowen = DictPack("sw", -1, "說文解字", listOf("shuowen"),
            listOf(Source("swjz.xml", G + "cjkvi/cjkvi-dict/master/swjz.xml", arg = "src")),
            "shuowen", "buildShuowen", "段玉裁《說文解字注》（cjkvi-dict，GPLv2）：單字詞條下面顯示說文的解釋、段注和六書", "約 6 MB")

        val all = listOf(taigi, mandarin, cantonese, hakka, japanese, shuowen)
        fun of(lang: Int): DictPack? = all.firstOrNull { it.lang == lang }

        /** "cedict_ts.u8" → "cedict", "essay.txt" → "essay" (a converter's argument); an accent's file keeps its name */
        fun argName(file: String): String = when (file) {
            "cedict_ts.u8" -> "cedict"; "essay.txt" -> "essay"; "kautian.ods" -> "ods"; else -> "file:$file"
        }
    }
}

sealed class InstallState {
    object Idle : InstallState()
    data class Working(val fraction: Double, val text: String) : InstallState()
    data class Failed(val message: String) : InstallState()
}

object DictInstaller {
    private val scope = MainScope()
    val states = mutableStateMapOf<String, InstallState>()
    /** (redrawn after installing or removing) */
    var version by mutableIntStateOf(0); private set

    fun state(p: DictPack): InstallState = states[p.id] ?: InstallState.Idle
    val busy: Boolean get() = states.values.any { it is InstallState.Working }

    fun remove(p: DictPack) {
        for (o in p.outputs) DataFiles.installed(o).delete()
        states[p.id] = InstallState.Idle
        version++
        Store.dictionaryChanged(p.lang)
    }

    fun install(p: DictPack) {
        if (state(p) is InstallState.Working) return
        states[p.id] = InstallState.Working(0.0, tr("下載中…"))
        scope.launch {
            val work = File(Store.app.cacheDir, "install-" + p.id)
            try {
                withContext(Dispatchers.IO) { work.deleteRecursively(); work.mkdirs() }
                // 1. the original files
                val have = HashMap<String, String>()
                for ((i, s) in p.sources.withIndex()) {
                    states[p.id] = InstallState.Working(0.3 * i / maxOf(p.sources.size, 1), tr("下載 {0}…", s.file))
                    try {
                        val dest = File(work, s.file)
                        withContext(Dispatchers.IO) { download(s.url, dest) }
                        have[s.file] = dest.path
                    } catch (e: Exception) {
                        if (!s.optional) throw InstallException(tr("下載不到 {0}：{1}", s.file, e.message ?: e.javaClass.simpleName))
                    }
                }
                // 2. the app's files, made from them
                states[p.id] = InstallState.Working(0.3, tr("整理資料…"))
                val out = File(work, "out").apply { mkdirs() }
                val args = JSONObject()
                args.put("src", work.path); args.put("outDir", out.path)
                for (o in p.outputs) args.put("out_$o", File(out, "$o.json").path)
                p.outputs.firstOrNull()?.let { args.put("out", File(out, "$it.json").path) }
                for (s in p.sources) {
                    val a = s.arg ?: DictPack.argName(s.file)
                    if (a.startsWith("file:")) continue
                    args.put(a, have[s.file] ?: JSONObject.NULL)
                }
                for ((arg, file) in p.bundled) {
                    val copy = File(work, file)
                    val ok = withContext(Dispatchers.IO) {
                        try { Store.app.assets.open("install/$file").use { i -> copy.outputStream().use { i.copyTo(it) } }; true } catch (_: Exception) { false }
                    }
                    args.put(arg, if (ok) copy.path else JSONObject.NULL)
                }
                val id = p.id
                JsRunner.run(p.script, p.function, args) { f, text ->
                    Handler(Looper.getMainLooper()).post { states[id] = InstallState.Working(0.3 + 0.7 * f.coerceIn(0.0, 1.0), text) }
                }
                // 3. in place (only now: a half-made file is never read)
                withContext(Dispatchers.IO) {
                    for (o in p.outputs) {
                        val made = File(out, "$o.json")
                        if (!made.exists()) {
                            // (the first file is the dictionary; the others, like 華語's 倉頡／五筆 codes, can be missing)
                            if (o == p.outputs.first()) throw InstallException(tr("沒有做出 {0}.json。", o)) else continue
                        }
                        val dest = DataFiles.installed(o)
                        dest.delete()
                        if (!made.renameTo(dest)) { made.copyTo(dest, overwrite = true); made.delete() }
                    }
                }
                states[p.id] = InstallState.Idle
                version++
                Store.dictionaryChanged(p.lang)
            } catch (e: InstallException) {
                states[p.id] = InstallState.Failed(e.message ?: "")
            } catch (e: Throwable) {
                states[p.id] = InstallState.Failed(e.message ?: e.javaClass.simpleName)
            } finally {
                withContext(Dispatchers.IO) { work.deleteRecursively() }
            }
        }
    }

    class InstallException(msg: String) : Exception(msg)

    /** a URL with characters that aren't ASCII (客語's file names) made into one a connection can use */
    private fun ascii(s: String): String {
        val b = StringBuilder()
        for (ch in s) {
            if (ch.code < 128 && ch != ' ') b.append(ch)
            else for (x in ch.toString().toByteArray(Charsets.UTF_8)) b.append('%').append("%02X".format(x.toInt() and 0xff))
        }
        return b.toString()
    }

    /** downloads a file (following redirects, http and https; a GitHub link is followed to the file it names) */
    private fun download(s: String, dest: File, depth: Int = 0) {
        var url = URL(ascii(s))
        var conn: HttpURLConnection
        var hops = 0
        while (true) {
            conn = url.openConnection() as HttpURLConnection
            conn.instanceFollowRedirects = false
            conn.connectTimeout = 30000; conn.readTimeout = 60000
            conn.setRequestProperty("User-Agent", "FangfangCards")
            val code = conn.responseCode
            if (code in 300..399 && hops < 8) {
                val loc = conn.getHeaderField("Location") ?: break
                url = URL(url, loc); hops++; conn.disconnect(); continue
            }
            if (code !in 200..299) { conn.disconnect(); throw Exception("HTTP $code") }
            break
        }
        dest.delete()
        conn.inputStream.use { i -> dest.outputStream().use { i.copyTo(it, 1 shl 16) } }
        conn.disconnect()
        // a link on GitHub (expanded/tocfl.csv → tocfl-202307.csv) comes as the name of the file it points to
        if (dest.length() < 300 && depth < 3) {
            val name = dest.readText().trim()
            if (Regex("^[A-Za-z0-9_./-]+\\.(csv|txt|json)$").matches(name)) {
                val next = URL(url, name).toString()
                if (next != url.toString()) download(next, dest, depth + 1)
            }
        }
    }
}

// MARK: the converters (a hidden WebView runs assets/install/*.js)
//
// The files are read with synchronous requests the WebView makes to https://ff.local/…, which the app answers
// (a 60 MB dictionary file doesn't go well through the JavaScript bridge); the app's files are written back in parts.

object JsRunner {
    private fun asset(name: String): String? = try { Store.app.assets.open(name).bufferedReader().use { it.readText() } } catch (_: Exception) { null }

    private class Bridge(val progress: (Double, String) -> Unit) {
        @Volatile var lastError: String = ""
        private val writing = HashMap<String, StringBuilder>()

        @JavascriptInterface fun begin(p: String) { synchronized(writing) { writing[p] = StringBuilder() } }
        @JavascriptInterface fun append(p: String, s: String) { synchronized(writing) { writing[p]?.append(s) } }
        @JavascriptInterface fun end(p: String): Boolean {
            val sb = synchronized(writing) { writing.remove(p) } ?: return false
            return try { File(p).parentFile?.mkdirs(); File(p).writeText(sb.toString()); true } catch (e: Exception) { lastError = "寫不進 $p"; false }
        }
        @JavascriptInterface fun list(d: String): String = JSONArray((File(d).list() ?: emptyArray()).toList()).toString()
        @JavascriptInterface fun exists(p: String): Boolean = File(p).exists()
        @JavascriptInterface fun log(t: String) { android.util.Log.i("FangfangInstall", t) }
        @JavascriptInterface fun progress(f: Double, t: String) { progress.invoke(f, t) }
        @JavascriptInterface fun lastError(): String = lastError

        /** a file (or a file out of a zip, an .xz, a .gz) as text, for a request to https://ff.local/… */
        fun serve(u: Uri): WebResourceResponse {
            val p = u.getQueryParameter("p") ?: ""
            val stream: InputStream? = try {
                when (u.path) {
                    "/read" -> File(p).inputStream()
                    "/unzip" -> {
                        val z = ZipFile(p)
                        val e = z.getEntry(u.getQueryParameter("n") ?: "") ?: throw Exception("no entry")
                        ByteArrayInputStream(z.getInputStream(e).use { it.readBytes() }).also { z.close() }
                    }
                    "/gunzip" -> GZIPInputStream(File(p).inputStream().buffered(1 shl 16), 1 shl 16)
                    "/xz" -> org.tukaani.xz.XZInputStream(File(p).inputStream().buffered(1 shl 16))
                    else -> null
                }
            } catch (e: Exception) {
                lastError = (if (u.path == "/read") "讀不到 " else "解不開 ") + p
                null
            }
            val headers = mapOf("Access-Control-Allow-Origin" to "*", "Cache-Control" to "no-store")
            return if (stream != null) WebResourceResponse("text/plain", "utf-8", 200, "OK", headers, stream)
            else WebResourceResponse("text/plain", "utf-8", 404, "Not Found", headers, ByteArrayInputStream(ByteArray(0)))
        }
    }

    private const val PRELUDE = """
var host = {
  _get: function (path) {
    var x = new XMLHttpRequest();
    x.open("GET", path, false);
    x.overrideMimeType("text/plain; charset=utf-8");
    x.send(null);
    if (x.status !== 200) throw new Error(ffb.lastError() || ("讀不到 " + path));
    return x.responseText;
  },
  readText: function (p) { if (p === null || p === undefined) return null; return host._get("https://ff.local/read?p=" + encodeURIComponent(p)); },
  unzipText: function (p, n) { return host._get("https://ff.local/unzip?p=" + encodeURIComponent(p) + "&n=" + encodeURIComponent(n)); },
  xzText: function (p) { return host._get("https://ff.local/xz?p=" + encodeURIComponent(p)); },
  gunzipText: function (p) { return host._get("https://ff.local/gunzip?p=" + encodeURIComponent(p)); },
  writeText: function (p, t) {
    ffb.begin(p);
    var n = 1 << 20;
    for (var i = 0; i < t.length; i += n) ffb.append(p, t.substring(i, i + n));
    if (!ffb.end(p)) throw new Error(ffb.lastError() || ("寫不進 " + p));
    return true;
  },
  list: function (d) { return JSON.parse(ffb.list(d)); },
  exists: function (p) { return ffb.exists(p); },
  log: function (t) { ffb.log(String(t)); },
  progress: function (f, t) { ffb.progress(Number(f) || 0, String(t === undefined ? "" : t)); }
};
host.readLines = function (p, fn) {
  var t = host.readText(p); if (t === null || t === undefined) return;
  var ls = t.split("\n"); for (var i = 0; i < ls.length; i++) fn(ls[i].endsWith("\r") ? ls[i].slice(0, -1) : ls[i]);
};
"""

    /** runs install/<script>.js's function with args; progress: (0…1, what it's doing) */
    @SuppressLint("SetJavaScriptEnabled")
    suspend fun run(script: String, function: String, args: JSONObject, progress: (Double, String) -> Unit) {
        val code = withContext(Dispatchers.IO) {
            val common = asset("install/common.js") ?: throw DictInstaller.InstallException(tr("整理資料的時候出錯：{0}", "common.js"))
            val mine = asset("install/$script.js") ?: throw DictInstaller.InstallException(tr("整理資料的時候出錯：{0}", "$script.js"))
            PRELUDE + "\n" + common + "\n" + mine + "\n" +
                "(function () { try { var r = $function(${args}); return \"OK\"; } catch (e) { return \"ERR:\" + (e && e.message ? e.message : String(e)); } })();"
        }
        withContext(Dispatchers.Main) {
            suspendCancellableCoroutine<Unit> { cont ->
                val wv = WebView(Store.app)
                wv.settings.javaScriptEnabled = true
                wv.settings.allowFileAccess = false
                val bridge = Bridge(progress)
                wv.addJavascriptInterface(bridge, "ffb")
                var started = false
                var finished = false
                fun finish(err: String?) {
                    if (finished) return
                    finished = true
                    Handler(Looper.getMainLooper()).post { try { wv.destroy() } catch (_: Exception) {} }
                    if (err == null) cont.resume(Unit) else cont.resumeWithException(DictInstaller.InstallException(tr("整理資料的時候出錯：{0}", err)))
                }
                wv.webViewClient = object : WebViewClient() {
                    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                        val u = request.url
                        return if (u.host == "ff.local" && u.path != "/") bridge.serve(u) else null
                    }
                    override fun onPageFinished(view: WebView, url: String) {
                        if (started) return
                        started = true
                        view.evaluateJavascript(code) { result ->
                            val r = try { JSONArray("[$result]").optString(0, result ?: "") } catch (_: Exception) { result ?: "" }
                            if (r == "OK") finish(null) else finish(r.removePrefix("ERR:").ifEmpty { "JavaScript" })
                        }
                    }
                    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                        finish(tr("記憶體不夠"))
                        return true
                    }
                }
                wv.loadDataWithBaseURL("https://ff.local/", "<html><body></body></html>", "text/html", "utf-8", null)
            }
        }
    }
}
