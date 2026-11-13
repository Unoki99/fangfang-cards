// 說文解字 (段玉裁《說文解字注》, cjkvi-dict's swjz.xml, GPLv2) → shuowen.json: for each character, 許慎's text
// ("瑞玉圜也。从王。辟聲。"), 段玉裁's notes, and the 六書 the text says (形聲 when it has "…聲", 象形, 指事, or
// 會意 when it's made of parts with no sound part). Downloaded and made on the device, like the dictionaries.
//   buildShuowen({src: swjz.xml, out: shuowen.json})
"use strict";

function liushuOf(text) {
    if (text.includes("亦聲")) return "會意兼形聲";
    if (/[从從][^。]*。?[^。]*聲/u.test(text) && /聲/u.test(text.replace(/讀若[^。]*。/gu, ""))) return "形聲";
    if (/象[^。]*形|象形/u.test(text)) return "象形";
    if (text.includes("指事")) return "指事";
    if (/[从從]/u.test(text)) return "會意";
    return null;
}

function buildShuowen(a) {
    host.progress(0.1, "讀《說文解字注》…");
    const xml = host.readText(a.src);
    const strip = s => decodeEntities(s.replace(/<[^>]+>/g, "")).replace(/\s+/g, "");
    const out = {};
    let n = 0;
    for (const m of xml.matchAll(/<shuowen>([\s\S]*?)<\/shuowen>/g)) {
        const body = m[1];
        // (a <shuowen> can have several characters: each <wordhead> starts one)
        const parts = body.split(/(?=<wordhead[\s>])/);
        for (const p of parts) {
            const h = /<wordhead[^>]*>([\s\S]*?)<\/wordhead>/.exec(p);
            if (!h) continue;
            const ch = strip(h[1]);
            if (cpLen(ch) !== 1) continue;
            const ex = Array.from(p.matchAll(/<explanation>([\s\S]*?)<\/explanation>/g)).map(x => strip(x[1])).join("");
            const notes = Array.from(p.matchAll(/<duan_note>([\s\S]*?)<\/duan_note>/g)).map(x => strip(x[1])).filter(x => x);
            if (!ex) continue;
            const e = { e: ex };
            if (notes.length) e.d = notes.join("　");
            const l = liushuOf(ex);
            if (l) e.l = l;
            (out[ch] = out[ch] || []).push(e);
            n++;
        }
    }
    host.writeText(a.out, JSON.stringify({ v: 1, c: out }));
    host.log("說文解字: " + n + " characters");
    return { chars: n };
}
