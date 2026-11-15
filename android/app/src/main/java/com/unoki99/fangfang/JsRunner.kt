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
import androidx.compose.runtime.mutableStateOf
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
