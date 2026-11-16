// 方方詞卡 查詞: installs one dictionary in the browser (設定 → 詞典), in a worker of its own so the page stays
// responsive: the original files the page downloaded → the app's converter (install/<script>.js, the same code the
// app runs when it installs a dictionary) → the app's data → the lookup files (shards.js) → the add-on's storage
// (datastore.js), and then the files made from every language (d-meta.json, d-en-*.json) again.
// The page sends {op: "install", dict: an entry of FF_DICTS, files: {file name: ArrayBuffer}, bundled: {arg: text}};
// the worker answers {op: "progress", f: 0…1, text}, then {op: "done", meta} or {op: "error", text}.
"use strict";
importScripts("datastore.js", "shards.js");

let busy = false;
self.onmessage = async ev => {
    const m = ev.data || {};
    if (m.op !== "install" || busy) return;
    busy = true;
    try {
        const meta = await install(m.dict, m.files || {}, m.bundled || {});
        self.postMessage({ op: "done", meta });
    } catch (e) {
        self.postMessage({ op: "error", text: String((e && e.message) || e) });
    }
    busy = false;
};
const say = (f, text) => self.postMessage({ op: "progress", f, text });

/// a zip file's entry (an .ods sheet's content.xml), unpacked
async function unzipEntry(buf, name) {
    const b = new DataView(buf), u8 = new Uint8Array(buf);
    let e = buf.byteLength - 22;
    while (e >= 0 && b.getUint32(e, true) !== 0x06054b50) e--;
    if (e < 0) throw new Error("not a zip file");
    const n = b.getUint16(e + 10, true);
    let p = b.getUint32(e + 16, true);
    const dec = new TextDecoder();
    for (let i = 0; i < n; i++) {
        const method = b.getUint16(p + 10, true), csize = b.getUint32(p + 20, true);
        const nlen = b.getUint16(p + 28, true), xlen = b.getUint16(p + 30, true), clen = b.getUint16(p + 32, true);
        const local = b.getUint32(p + 42, true);
        if (dec.decode(u8.subarray(p + 46, p + 46 + nlen)) === name) {
            const at = local + 30 + b.getUint16(local + 26, true) + b.getUint16(local + 28, true);
            const data = u8.slice(at, at + csize);
            if (method === 0) return data;
            const out = new Blob([data]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
            return new Uint8Array(await new Response(out).arrayBuffer());
        }
        p += 46 + nlen + xlen + clen;
    }
    throw new Error(name + " isn't in the file");
}

async function install(dict, bufs, bundled) {
    // the files, as the app's converters read them (host: the same functions the app gives them)
    const SRC = "/src", OUT = "/out";
    const files = new Map(), texts = new Map(), unzipped = new Map(), written = new Map();
    for (const [name, buf] of Object.entries(bufs)) files.set(SRC + "/" + name, buf);
    for (const [arg, text] of Object.entries(bundled)) texts.set("/bundled/" + arg, text);
    // (.ods: its content.xml unpacked now; the converters read it without waiting)
    for (const [p, buf] of files) {
        if (p.toLowerCase().endsWith(".ods")) unzipped.set(p, await unzipEntry(buf, "content.xml"));
    }
    const utf8 = new TextDecoder("utf-8", { ignoreBOM: true });
    const fail = t => { throw new Error(t); };
    const host = {
        readText: p => texts.has(p) ? texts.get(p) : (files.has(p) ? utf8.decode(files.get(p)) : fail("讀不到 " + p)),
        unzipText: (p, name) => name === "content.xml" && unzipped.has(p) ? utf8.decode(unzipped.get(p)) : fail("解不開 " + p),
        xzText: p => fail("解不開 " + p),
        gunzipText: p => fail("解不開 " + p),
        writeText: (p, t) => { written.set(p, t); return true; },
        list: d => [...files.keys()].filter(p => p.startsWith(d + "/")).map(p => p.slice(d.length + 1)),
        exists: p => files.has(p) || texts.has(p),
        log: t => {},
        progress: (f, t) => say(0.05 + 0.6 * Math.min(Math.max(f, 0), 1), t),
    };
    host.readLines = (p, fn) => {
        const t = host.readText(p);
        if (t === null || t === undefined) return;
        const ls = t.split("\n");
        for (let i = 0; i < ls.length; i++) fn(ls[i].endsWith("\r") ? ls[i].slice(0, -1) : ls[i]);
    };
    self.host = host;
    importScripts("install/common.js", "install/" + dict.script + ".js");

    // the converter's arguments, as the app gives them ({src, out, out_<name>, and each file by its argument})
    const args = { src: SRC, outDir: OUT };
    for (const o of dict.outs) args["out_" + o] = OUT + "/" + o + ".json";
    args.out = OUT + "/" + dict.outs[0] + ".json";
    for (const s of dict.sources) {
        if (!s.arg) continue;
        if (files.has(SRC + "/" + s.file)) args[s.arg] = SRC + "/" + s.file;
        else if (!(s.arg in args)) args[s.arg] = null;
    }
    for (const arg of Object.keys(bundled)) args[arg] = "/bundled/" + arg;
    if (args.outDict === undefined && dict.outs.includes("dict")) { args.outDict = args.out_dict; args.outCards = args.out_cards; }
    say(0.05, "整理資料…");
    self[dict.fn](args);
    files.clear(); unzipped.clear();

    // the app's data → the lookup files
    say(0.68, "做查詞的檔案…");
    const data = {};
    for (const o of dict.outs) {
        const t = written.get(OUT + "/" + o + ".json");
        if (!t) { if (o === dict.outs[0]) throw new Error("沒有做出 " + o + ".json"); continue; }
        data[o] = JSON.parse(t);
        written.delete(OUT + "/" + o + ".json");
    }
    const r = ffShards.build(dict.id, data);
    say(0.85, "存起來…");
    await ffDB.putLang(dict.id, r.files, { en: r.en, meta: r.meta, at: Date.now(), ver: dict.ver || 0 });
    say(0.95, "整理英文查詞…");
    const merged = ffShards.merge(await ffDB.parts());
    await ffDB.putMerged(merged);
    say(1, "");
    return r.meta;
}
