package com.unoki99.fangfang

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

// (Windows) the dictionaries' converters (install/*.js, the same as the Android and iPhone apps') run by Node.js:
// install-windows.bat downloads one into %LOCALAPPDATA%\FangfangCards\node when the computer has none.
object JsRunner {
    private fun node(): File? {
        val path = System.getenv("PATH") ?: ""
        for (d in path.split(File.pathSeparator)) {
            val f = File(d.trim('"'), "node.exe")
            if (f.isFile) return f
        }
        val own = File(com.unoki99.fangfang.desktop.DesktopContext.base, "node")
        return own.walkTopDown().maxDepth(3).firstOrNull { it.name.equals("node.exe", true) && it.isFile }
    }

    private const val RUNNER = """
"use strict";
const fs = require("fs"), path = require("path"), zlib = require("zlib"), vm = require("vm");
const [dir, script, fn, argsFile] = process.argv.slice(2);
function unzipEntry(file, name) {
    const b = fs.readFileSync(file);
    let e = b.length - 22;
    while (e >= 0 && b.readUInt32LE(e) !== 0x06054b50) e--;
    if (e < 0) throw new Error("not a zip file: " + file);
    const n = b.readUInt16LE(e + 10);
    let p = b.readUInt32LE(e + 16);
    for (let i = 0; i < n; i++) {
        const method = b.readUInt16LE(p + 10), csize = b.readUInt32LE(p + 20);
        const nlen = b.readUInt16LE(p + 28), xlen = b.readUInt16LE(p + 30), clen = b.readUInt16LE(p + 32);
        const local = b.readUInt32LE(p + 42);
        const fname = b.toString("utf8", p + 46, p + 46 + nlen);
        if (fname === name) {
            const lnlen = b.readUInt16LE(local + 26), lxlen = b.readUInt16LE(local + 28);
            const data = b.subarray(local + 30 + lnlen + lxlen, local + 30 + lnlen + lxlen + csize);
            return method === 0 ? data : zlib.inflateRawSync(data);
        }
        p += 46 + nlen + xlen + clen;
    }
    throw new Error(name + " not in " + file);
}
const host = {
    readText: p => fs.readFileSync(p, "utf8"),
    readLines: (p, f) => { for (const l of fs.readFileSync(p, "utf8").split("\n")) f(l.replace(/\r$/, "")); },
    unzipText: (p, name) => unzipEntry(p, name).toString("utf8"),
    gunzipText: p => zlib.gunzipSync(fs.readFileSync(p)).toString("utf8"),
    xzText: p => { throw new Error("xz: " + p); },
    writeText: (p, t) => { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, t); return true; },
    list: d => fs.readdirSync(d),
    exists: p => fs.existsSync(p),
    log: t => console.error(t),
    progress: (f, t) => console.log("@@" + JSON.stringify([f, String(t || "")])),
};
const ctx = vm.createContext({ host, console });
for (const f of ["common.js", script + ".js"]) vm.runInContext(fs.readFileSync(path.join(dir, f), "utf8"), ctx, { filename: f });
ctx.__args = JSON.parse(fs.readFileSync(argsFile, "utf8"));
vm.runInContext(fn + "(__args)", ctx);
"""

    /** runs install/<script>.js's function with args; progress: (0…1, what it's doing) */
    suspend fun run(script: String, function: String, args: JSONObject, progress: (Double, String) -> Unit) = withContext(Dispatchers.IO) {
        val node = node() ?: throw Exception(tr("要用 Node.js 整理詞典：先執行一次 install-windows.bat（它會下載 Node.js），或從 nodejs.org 安裝。"))
        val work = File(Store.app.cacheDir, "js-" + System.nanoTime()).apply { mkdirs() }
        try {
            // the converters, out of the program's own files
            for (f in listOf("common.js", "$script.js")) {
                val text = Store.app.assets.open("install/$f").bufferedReader().use { it.readText() }
                File(work, f).writeText(text)
            }
            // (.xz: unpacked here, so the converter reads it as it is)
            for (k in args.keys().asSequence().toList()) {
                val v = args.opt(k) as? String ?: continue
                if (v.endsWith(".xz") && File(v).isFile) {
                    val out = File(v.removeSuffix(".xz"))
                    org.tukaani.xz.XZInputStream(File(v).inputStream().buffered(1 shl 16)).use { i -> out.outputStream().use { i.copyTo(it, 1 shl 16) } }
                    args.put(k, out.path)
                }
            }
            File(work, "runner.js").writeText(RUNNER)
            File(work, "args.json").writeText(args.toString())
            val p = ProcessBuilder(node.path, "--max-old-space-size=6144", "--stack-size=16000", File(work, "runner.js").path,
                work.path, script, function, File(work, "args.json").path).start()
            val err = StringBuilder()
            val t = Thread { try { p.errorStream.bufferedReader().forEachLine { synchronized(err) { err.append(it).append('\n'); if (err.length > 4000) err.delete(0, err.length - 4000) } } } catch (_: Exception) {} }
            t.start()
            p.inputStream.bufferedReader(Charsets.UTF_8).forEachLine { line ->
                if (line.startsWith("@@")) try {
                    val a = org.json.JSONArray(line.substring(2))
                    progress(a.optDouble(0, 0.0), a.optString(1, ""))
                } catch (_: Exception) {}
            }
            val code = p.waitFor()
            t.join(2000)
            if (code != 0) throw Exception(synchronized(err) { err.toString() }.lines().filter { it.isNotBlank() }.takeLast(4).joinToString("\n").ifEmpty { "Node.js: $code" })
        } finally {
            work.deleteRecursively()
        }
    }
}
