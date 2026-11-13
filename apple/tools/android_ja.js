#!/usr/bin/env node
// 方方詞卡 (Android): the 日語 dictionary made smaller for the Android app, which has much less memory than an
// iPhone or iPad (Android gives an app about 512 MB, and the whole of JMdict as the app's objects doesn't fit).
// Kept: every common word (the study cards), then the other words in JMdict's order up to 60,000 words in all;
// at most one example sentence for each of a word's first three meanings. The iOS app isn't changed by this.
//   node tools/android_ja.js ja.json ja-android.json
"use strict";
const fs = require("fs");
const [src, out] = process.argv.slice(2);
const MAX = 60000;
const text = fs.readFileSync(src, "utf8");
const marker = ',"e":[\n';
const mi = text.indexOf(marker);
if (mi < 0) { fs.writeFileSync(out, text); process.exit(0); }
const head = text.slice(0, mi);
const end = text.lastIndexOf("\n]}");
const lines = text.slice(mi + marker.length, end > mi ? end : text.length).split("\n");
const keep = [];
let rest = 0;
for (const raw of lines) {
    const line = raw.trim().replace(/,$/, "");
    if (!line) continue;
    const e = JSON.parse(line);
    if (!e.x) {
        if (keep.length >= MAX) continue;
        rest++;
    }
    if (Array.isArray(e.d)) e.d = e.d.map((s, i) => (Array.isArray(s) && Array.isArray(s[1]) ? [s[0], i < 3 ? s[1].slice(0, 1) : []] : s));
    if (Array.isArray(e.m)) e.m = e.m.slice(0, 4);
    keep.push(JSON.stringify(e));
}
fs.writeFileSync(out, head + marker + keep.join(",\n") + "\n]}");
console.error(`日語 (Android): ${keep.length} words (${keep.length - rest} common), from ${lines.length}`);
