#!/usr/bin/env node
// 方方詞卡: runs the app's dictionary converters (FangfangCards/Install/*.js) on a computer, with node, for
// testing them against the Python tools (or instead of them).
//   node tools/convert.js hakka SRC_DIR OUT.json [essay.txt|-] [cedict_ts.u8|-]
//   node tools/convert.js taigi kautian.ods tools/own.json essay.txt dict.json cards.json
//   node tools/convert.js japanese JMdict_e_examp.gz kanjidic2.xml.gz ja.json
//   node tools/convert.js cantonese SRC_DIR yue.json
//   node tools/convert.js swedish folkets_sv_en_public.xml sv_50k.txt|- kaikki.org-dictionary-瑞典語.jsonl|- sv.json [cedict_ts.u8|- [essay.txt]]
"use strict";
const fs = require("fs"), path = require("path"), zlib = require("zlib"), cp = require("child_process"), vm = require("vm");

function unzipEntry(file, name) {
    const b = fs.readFileSync(file);
    // the end of the central directory
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
    readLines: (p, fn) => { for (const l of fs.readFileSync(p, "utf8").split("\n")) fn(l.replace(/\r$/, "")); },
    unzipText: (p, name) => unzipEntry(p, name).toString("utf8"),
    gunzipText: p => zlib.gunzipSync(fs.readFileSync(p)).toString("utf8"),
    xzText: p => cp.execFileSync("xz", ["-dc", p], { maxBuffer: 1 << 30 }).toString("utf8"),
    writeText: (p, t) => fs.writeFileSync(p, t),
    list: d => fs.readdirSync(d),
    exists: p => fs.existsSync(p),
    log: t => console.error(t),
    progress: (f, t) => {},
};
const ctx = vm.createContext({ host, console });
const dir = path.join(__dirname, "..", "FangfangCards", "Install");
for (const f of fs.readdirSync(dir).filter(f => f.endsWith(".js")).sort((a, b) => (a === "common.js" ? -1 : b === "common.js" ? 1 : a.localeCompare(b)))) {
    vm.runInContext(fs.readFileSync(path.join(dir, f), "utf8"), ctx, { filename: f });
}
const [what, ...args] = process.argv.slice(2);
const opt = x => (x && x !== "-" ? x : null);
if (what === "hakka") {
    ctx.args = { src: args[0], out: args[1], essay: opt(args[2]), cedict: opt(args[3]) };
    vm.runInContext("buildHakka(args)", ctx);
} else if (what === "taigi") {
    ctx.args = { ods: args[0], own: opt(args[1]), essay: opt(args[2]), outDict: args[3], outCards: args[4] };
    vm.runInContext("buildTaigi(args)", ctx);
} else if (what === "mandarin") {
    // csld essay out cedict hsk tocfl moe hskChars tbclChars ids
    const [csld, essay, out, cedict, hsk, tocfl, moe, hskChars, tbclChars, ids] = args;
    ctx.args = { csld, essay, out, cedict: opt(cedict), hsk: opt(hsk), tocfl: opt(tocfl), moe: opt(moe),
        hskChars: opt(hskChars), tbclChars: opt(tbclChars), ids: opt(ids) };
    vm.runInContext("buildMandarin(args)", ctx);
} else if (what === "inputcodes") {
    const [cjBase, cjExt, wubi, out, cedict] = args;
    ctx.args = { cjBase, cjExt, wubi, out, cedict: opt(cedict) };
    vm.runInContext("buildInputCodes(args)", ctx);
} else if (what === "cantonese") {
    // DIR (cedict_ts.u8, CC-CANTO.txt, READINGS.txt, jyut6ping3.words.dict.yaml, jyut6ping3.chars.dict.yaml,
    // essay-cantonese.txt, yyzd.txt) out.json
    const d = args[0];
    ctx.args = { cedict: d + "/cedict_ts.u8", canto: d + "/CC-CANTO.txt", readings: d + "/READINGS.txt",
        words: d + "/jyut6ping3.words.dict.yaml", chars: d + "/jyut6ping3.chars.dict.yaml",
        essay: d + "/essay-cantonese.txt", yyzd: d + "/yyzd.txt", out: args[1] };
    vm.runInContext("buildCantonese(args)", ctx);
} else if (what === "japanese") {
    // JMdict_e_examp.gz kanjidic2.xml.gz|- out.json
    ctx.args = { jmdict: args[0], kanjidic: opt(args[1]), out: args[2] };
    vm.runInContext("buildJapanese(args)", ctx);
} else if (what === "shuowen") {
    // swjz.xml out.json
    ctx.args = { src: args[0], out: args[1] };
    vm.runInContext("buildShuowen(args)", ctx);
} else if (what === "swedish") {
    // folkets_sv_en_public.xml sv_50k.txt|- kaikki.org-dictionary-瑞典語.jsonl|- out.json [cedict_ts.u8|- [essay.txt]]
    ctx.args = { folkets: args[0], freq: opt(args[1]), zhwikt: opt(args[2]), out: args[3], cedict: opt(args[4]), essay: opt(args[5]) };
    vm.runInContext("buildSwedish(args)", ctx);
} else {
    console.error("usage: node tools/convert.js hakka SRC OUT [essay|-] [cedict|-]  |  taigi ODS OWN ESSAY DICT CARDS");
    process.exit(1);
}
