#!/usr/bin/env node
// 方方詞卡: makes the add-on's lookup files with FangfangSafari/shards.js (what the add-on's 詞典 settings do in
// the browser) from the app's data in DIR, and, given the files tools/build_safari.py made, tells where they differ.
//   node tools/check_shards.js DIR OUT_DIR [PY_OUT_DIR]
"use strict";
const fs = require("fs"), path = require("path");
const ffShards = require(path.join(__dirname, "..", "FangfangSafari", "shards.js"));
const [dir, out, pyOut] = process.argv.slice(2);
const load = n => { const p = path.join(dir, n + ".json"); return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, "utf8")) : null; };
const parts = {}, files = {};
const want = { zh: ["zh", "zh_sc"], tw: ["dict", "cards", "tw_en"], yue: ["yue"], hak: ["hak"], sv: ["sv"] };
for (const [lang, names] of Object.entries(want)) {
    const data = {};
    for (const n of names) data[n] = load(n);
    if (!data[names[0]]) continue;
    const r = ffShards.build(lang, data, t => console.error(t));
    parts[lang] = { en: r.en, meta: r.meta };
    Object.assign(files, r.files);
}
Object.assign(files, ffShards.merge(parts));
fs.mkdirSync(out, { recursive: true });
for (const [n, o] of Object.entries(files)) fs.writeFileSync(path.join(out, n), JSON.stringify(o));
console.error(Object.keys(files).length + " files → " + out);
if (pyOut) {
    const canon = o => Array.isArray(o) ? o.map(canon) : (o && typeof o === "object" ? Object.fromEntries(Object.keys(o).sort().map(k => [k, canon(o[k])])) : o);
    const py = fs.readdirSync(pyOut).filter(f => /^d-.*\.json$/.test(f));
    let same = 0, diff = 0, words = 0;
    const missing = py.filter(f => !files[f]), extra = Object.keys(files).filter(f => !py.includes(f));
    for (const f of py) {
        if (!files[f]) continue;
        const a = canon(JSON.parse(fs.readFileSync(path.join(pyOut, f), "utf8"))), b = canon(files[f]);
        if (JSON.stringify(a) === JSON.stringify(b)) { same++; continue; }
        diff++;
        if (typeof a === "object" && !Array.isArray(a)) {
            for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
                if (JSON.stringify(a[k]) !== JSON.stringify(b[k])) {
                    if (words++ < 12) console.log(f, JSON.stringify(k), "\n  py:", JSON.stringify(a[k]).slice(0, 300), "\n  js:", JSON.stringify(b[k]).slice(0, 300));
                }
            }
        }
    }
    console.log(`same ${same}, different ${diff} (${words} keys), only in Python ${missing.length} ${missing.slice(0, 5)}, only here ${extra.length} ${extra.slice(0, 5)}`);
}
