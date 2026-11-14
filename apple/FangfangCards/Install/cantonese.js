// 粵語: CC-CEDICT and CC-Canto (CC BY-SA), rime-cantonese (CC BY 4.0 / ODbL), 開放粵語字典 (CC BY 3.0) → yue.json.
// The same as tools/build_cantonese.py run without Wiktionary (its 2.5 GB file is too big for a phone): the words,
// readings, English meanings, how common they are, the characters. Made on the device, like the other dictionaries.
//   buildCantonese({cedict, canto, readings, words, chars, essay, yyzd, out})
"use strict";

function buildCantonese(a) {
    const JP = /^[a-z]+[1-6]$/;
    const K = (...xs) => xs.join("\u0001");
    const lines = p => host.readText(p).split("\n");

    function cleanJp(s) {
        let sy = s.toLowerCase().replace(/,/g, " ").split(/\s+/).filter(x => x);
        sy = sy.filter(x => x !== "，" && x !== "·" && x !== "-");
        return sy.length && sy.every(x => JP.test(x)) ? sy.join(" ") : null;
    }
    function senses(defs) {
        const out = [];
        for (let d of defs.replace(/^\/+|\/+$/g, "").split("/")) {
            d = d.trim();
            if (d && !out.includes(d)) out.push(d);
        }
        return out;
    }
    const LINE = /^(\S+) (\S+) \[([^\]]*)\](?: \{([^}]*)\})? \/(.*)\/\s*(?:#.*)?$/;
    const isHanCh = c => (c >= "㐀" && c <= "鿿") || (c >= "\u{20000}" && c <= "\u{3ffff}") || (c >= "豈" && c <= "﫿");

    // ------------------------------------------------------------ CC-CEDICT + its Cantonese readings
    host.progress(0.05, "CC-CEDICT…");
    const reading = new Map();
    for (const line of lines(a.readings)) {
        if (line.startsWith("#")) continue;
        const m = /^(\S+) (\S+) \[([^\]]*)\] \{([^}]*)\}/.exec(line);
        if (m) {
            const j = cleanJp(m[4]);
            if (j) reading.set(K(m[1], m[2], m[3].replace(/ /g, "").toLowerCase()), j);
        }
    }
    const entries = new Map();      // (h, j) → entry
    function entry(h, s, j) {
        const k = K(h, j);
        let e = entries.get(k);
        if (!e) { e = { h, s: s !== h ? s : null, j, en: [], yue: 0, src: [] }; entries.set(k, e); }
        return e;
    }
    let noReading = 0;
    const later = [];
    for (const line of lines(a.cedict)) {
        if (line.startsWith("#")) continue;
        const m = LINE.exec(line);
        if (!m) continue;
        const [, h, s, py, , defs] = m;
        const j = reading.get(K(h, s, py.replace(/ /g, "").toLowerCase()));
        if (!j) { later.push([h, s, defs]); continue; }
        const e = entry(h, s, j);
        for (const d of senses(defs)) if (!e.en.includes(d)) e.en.push(d);
        if (!e.src.includes("cedict")) e.src.push("cedict");
    }

    // ------------------------------------------------------------ CC-Canto
    host.progress(0.2, "CC-Canto…");
    let canto = 0;
    for (const line of lines(a.canto)) {
        if (line.startsWith("#")) continue;
        const m = LINE.exec(line);
        if (!m || !m[4]) continue;
        const [, h, s, , jy, defs] = m;
        const j = cleanJp(jy);
        if (!j) continue;
        const e = entry(h, s, j);
        const fresh = senses(defs).filter(d => !e.en.includes(d));
        e.en = fresh.concat(e.en);
        if (!e.src.includes("cedict")) e.yue = 1;
        if (!e.src.includes("canto")) e.src.push("canto");
        canto++;
    }

    // ------------------------------------------------------------ rime-cantonese
    host.progress(0.35, "rime-cantonese…");
    const freq = new Map();
    const fq = w => freq.get(w) || 0;
    for (const line of lines(a.essay)) {
        const p = line.split("\t");
        if (p.length === 2 && /^\d+$/.test(p[1])) freq.set(p[0], parseInt(p[1], 10));
    }
    const rimeWords = new Map();
    function readRime(path) {
        let body = false;
        for (const line of lines(path)) {
            if (line.startsWith("...")) { body = true; continue; }
            if (!body || line.startsWith("#") || !line.trim()) continue;
            const p = line.split("\t");
            if (p.length < 2) continue;
            const j = cleanJp(p[1]);
            if (!j) continue;
            let w = 1.0;
            if (p.length > 2 && p[2].endsWith("%")) {
                const t = p[2].slice(0, -1);
                const v = Number(t);
                if (t.trim() !== "" && !isNaN(v)) w = v / 100;
            }
            if (!rimeWords.has(p[0])) rimeWords.set(p[0], []);
            rimeWords.get(p[0]).push([j, w]);
        }
    }
    readRime(a.words);
    readRime(a.chars);

    for (const [h, s, defs] of later) {
        const rs = rimeWords.get(h);
        if (!rs) { noReading++; continue; }
        const e = entry(h, s, rs[0][0]);
        for (const d of senses(defs)) if (!e.en.includes(d)) e.en.push(d);
        if (!e.src.includes("cedict")) e.src.push("cedict");
        e.yue = 0;
    }

    // rime-cantonese's reading, when it has only one and CC-CEDICT spells it differently
    let fixed = 0;
    for (const [key, e] of Array.from(entries)) {
        const h = e.h, j = e.j;
        const rs = rimeWords.get(h);
        if (cpLen(h) > 1 && rs && new Set(rs.map(r => r[0])).size === 1 && rs[0][0] !== j && !entries.has(K(h, rs[0][0]))) {
            entries.delete(key);
            e.j = rs[0][0];
            entries.set(K(h, e.j), e);
            fixed++;
        }
    }
    // Cantonese words only rime-cantonese has
    let onlyRime = 0;
    const heads = new Set(Array.from(entries.values()).map(e => e.h));
    for (const [h, rs] of rimeWords) {
        if (cpLen(h) < 2 || fq(h) < 200 || heads.has(h)) continue;
        const e = entry(h, null, rs[0][0]); e.src.push("rime"); e.yue = 1; onlyRime++;
    }

    // how common
    const STAND_IN = { "哋": "地", "咗": "左", "嘅": "既", "嚟": "黎", "喺": "係", "噉": "咁" };
    const standIn = h => cps(h).map(c => STAND_IN[c] || c).join("");
    for (const e of entries.values()) {
        const h = e.h;
        e.f = Math.max(fq(h), cpLen(h) > 1 ? fq(standIn(h)) : 0);
        if (h === "左" || h === "既" || h === "黎") e.f = Math.floor(e.f / 20);
        if (e.f === 0 && cpLen(h) > 1 && rimeWords.has(h) && cps(h).every(c => fq(c))) {
            e.f = Math.floor(Math.min(...cps(h).map(c => fq(c))) / 50);
        }
    }

    // ------------------------------------------------------------ characters (開放粵語字典)
    host.progress(0.5, "開放粵語字典…");
    const chars = new Map();
    for (const line of lines(a.yyzd)) {
        const p = line.split("\t");
        if (p.length < 3) continue;
        if (cpLen(p[0]) !== 1) continue;
        for (const x of p[2].split("/")) {
            const j = cleanJp(x);
            if (!j) continue;
            if (!chars.has(p[0])) chars.set(p[0], []);
            chars.get(p[0]).push([j, p.length > 4 ? p[4] : "", p.length > 3 ? p[3] : ""]);
        }
    }
    const use = new Map();
    for (const e of entries.values()) {
        const hs = cps(e.h), js = e.j.split(" ");
        if (hs.length > 1 && hs.length === js.length) {
            for (let i = 0; i < hs.length; i++) { const k = K(hs[i], js[i]); use.set(k, (use.get(k) || 0) + 1 + e.f); }
        }
    }
    const weight = new Map();
    for (const [ch, rs] of rimeWords) {
        if (cpLen(ch) !== 1) continue;
        for (const [r, w] of rs) { const k = K(ch, r); weight.set(k, Math.max(weight.has(k) ? weight.get(k) : 0, w)); }
    }
    const charScore = (ch, r) => [weight.get(K(ch, r)) || 0, use.get(K(ch, r)) || 0];
    const cmpScoreDesc = (x, y) => (y[0] - x[0]) || (y[1] - x[1]);
    for (const [ch, rs] of Array.from(chars)) {
        const merged = new Map();
        for (const [j, m, w] of rs) {
            if (merged.has(j)) {
                const r = merged.get(j);
                if (m && !r[1].includes(m)) r[1] = (r[1] ? r[1] + "；" : "") + m;
                if (w && !r[2].includes(w)) r[2] = (r[2] ? r[2] + "，" : "") + w;
            } else merged.set(j, [j, m, w]);
        }
        chars.set(ch, Array.from(merged.values()).sort((x, y) => cmpScoreDesc(charScore(ch, x[0]), charScore(ch, y[0]))));
    }
    // a character with only CC-CEDICT's rarer reading as a word (嘅 ge2): the usual reading's
    for (const [key, e] of Array.from(entries)) {
        const h = e.h, j = e.j;
        const w0 = weight.has(K(h, j)) ? weight.get(K(h, j)) : 1;
        if (cpLen(h) !== 1 || e.src.length !== 1 || e.src[0] !== "cedict" || w0 >= 1) continue;
        const main = [];
        for (const [k, w] of weight) { const [c, r] = k.split("\u0001"); if (c === h && w >= 1) main.push(r); }
        if (main.length === 1 && !entries.has(K(h, main[0]))) {
            entries.delete(key); e.j = main[0]; entries.set(K(h, main[0]), e);
        }
    }
    // characters 開放粵語字典 doesn't have
    for (const [ch, rs] of rimeWords) {
        if (cpLen(ch) === 1 && !chars.has(ch) && fq(ch) > 0) {
            const best = rs.slice().sort((x, y) => cmpScoreDesc(charScore(ch, x[0]), charScore(ch, y[0])));
            chars.set(ch, best.slice(0, 3).map(([r]) => [r, "", ""]));
        }
    }

    // a word read more than one way: the usual one first, the others "alt"
    host.progress(0.65, "整理詞…");
    const byh = new Map();
    for (const e of entries.values()) { if (!byh.has(e.h)) byh.set(e.h, []); byh.get(e.h).push(e); }
    function rank(e) {
        const h = e.h, j = e.j;
        if (cpLen(h) === 1) {
            const order = (chars.get(h) || []).map(r => r[0]);
            return (order.includes(j) ? order.indexOf(j) : 99);
        }
        const rs = (rimeWords.get(h) || []).map(r => r[0]);
        return (rs.includes(j) ? rs.indexOf(j) : 50) - (e.yue ? 0.5 : 0) - (e.src.includes("canto") ? 0.2 : 0);
    }
    for (const es of byh.values()) {
        if (es.length > 1) {
            const sorted = es.map((e, i) => [rank(e), i, e]).sort((x, y) => x[0] - y[0] || x[1] - y[1]).map(x => x[2]);
            for (const e of sorted.slice(1)) { e.alt = 1; delete e.zh; }
        }
    }
    // the 華語 word a meaning gives ("Mandarin equivalent: 沒有|没有[mei2 you3]")
    const MEQ = /Mandarin equivalent:?\s*([^\s|\[\]();,]+)/g;
    for (const e of entries.values()) {
        if (e.alt) continue;
        for (const g of e.en) {
            MEQ.lastIndex = 0;
            let m;
            while ((m = MEQ.exec(g)) !== null) {
                if (m[1] !== e.h) {
                    if (!e.zh) e.zh = [];
                    if (!e.zh.includes(m[1])) e.zh.push(m[1]);
                }
            }
        }
    }

    let out = Array.from(entries.values()).filter(e => e.en.length || e.f >= 200);
    out = out.map((e, i) => [e, i]).sort((x, y) => (y[0].f - x[0].f) || ((x[0].alt || 0) - (y[0].alt || 0)) || (x[1] - y[1])).map(x => x[0]);

    // ------------------------------------------------------------ the app's file (the shape of zh.json)
    host.progress(0.8, "寫入…");
    const GROUP = 500, CARDS = 12000;
    const glossOk = g => !g.startsWith("CL:") && !/^(variant of|old variant of|see )/.test(g);
    function appEntry(e) {
        const o = { k: e.h + "\t粵" + e.j, h: e.h, s: e.j };
        if (e.s && e.s !== e.h) o.a = e.s;
        const en = e.en.filter(glossOk);
        o.d = en.slice(0, 8).map(g => [g, []]);
        if (en.length) o.n = en.join("; ");
        if (e.zh && e.zh.length) o.m = e.zh;
        return o;
    }
    const cardsOrder = out.filter(e => !e.alt && e.f > 0 && e.en.some(glossOk) && cps(e.h).every(isHanCh)).slice(0, CARDS);
    const carded = new Set(cardsOrder);
    const appEntries = [];
    cardsOrder.forEach((e, n) => { const o = appEntry(e); o.x = Math.floor(n / GROUP) + 1; o.y = o.x; appEntries.push(o); });
    for (const e of out) {
        if (carded.has(e)) continue;
        const o = appEntry(e);
        if (o.d.length) appEntries.push(o);
    }

    // the characters, the most common first
    const charUse = new Map();
    for (const e of out) for (const c of cps(e.h)) charUse.set(c, (charUse.get(c) || 0) + e.f);
    const wordOf = new Map();
    for (const e of out) if (cpLen(e.h) === 1 && !e.alt) wordOf.set(e.h, e);
    const YALE_TONE = { "1": "̄", "2": "́", "3": "", "4": "̀", "5": "́", "6": "" };
    function yale(s) {
        const m = /^([a-z]+)([1-6])$/.exec(s);
        if (!m) return s;
        const b = m[1], t = m[2];
        let ini = "";
        for (const i0 of ["gw", "kw", "ng", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "w", "z", "c", "s", "j"]) {
            if (b.startsWith(i0) && b.length > i0.length) { ini = i0; break; }
        }
        let fin = b.slice(ini.length);
        ini = { z: "j", c: "ch", j: "y" }[ini] !== undefined ? { z: "j", c: "ch", j: "y" }[ini] : ini;
        if (ini === "y" && fin.startsWith("yu")) ini = "";
        if (fin === "aa") fin = "a";
        fin = fin.replace(/^eo|^oe/, "eu");
        if (ini === "" && !fin) fin = b;
        const syl = ini + fin;
        let v;
        if ((fin === "m" || fin === "ng") && !ini) v = 0;
        else {
            v = -1;
            for (let i = 0; i < syl.length; i++) if ("aeiou".includes(syl[i])) { v = i; break; }
            if (v < 0) v = ini.length;
        }
        let o = syl.slice(0, v + 1) + YALE_TONE[t] + syl.slice(v + 1);
        if ("456".includes(t)) {
            let k = v + 1 + YALE_TONE[t].length;
            while (k < o.length && ("aeiouy".includes(o[k]) || "̀́̄".includes(o[k]))) k++;
            if ((fin === "m" || fin === "ng") && !ini) k = o.length;
            o = o.slice(0, k) + "h" + o.slice(k);
        }
        return o;
    }
    const ranked = Array.from(chars.keys()).map((c, i) => [c, i])
        .sort((x, y) => ((charUse.get(y[0]) || 0) - (charUse.get(x[0]) || 0)) || (x[1] - y[1])).map(x => x[0]);
    const appChars = [];
    ranked.forEach((ch, n) => {
        const rs = [];
        for (const [j, meaning, words] of chars.get(ch).slice(0, 4)) {
            const defs = [];
            if (meaning) defs.push(["", meaning]);
            if (words) defs.push(["", "例：" + words.split("，").slice(0, 12).join("，")]);
            if (!defs.length) {
                const w = wordOf.get(ch);
                if (w && w.j === j) {
                    const g = w.en.find(glossOk) || "";
                    if (g) defs.push(["", g]);
                }
            }
            rs.push([yale(j), j, defs]);
        }
        if (!rs.some(r => r[2].length) && !(charUse.get(ch) || 0)) return;
        const lvl = n < GROUP * 7 ? Math.floor(n / GROUP) + 1 : 0;
        appChars.push({ h: ch, m: rs, x: lvl, y: lvl });
    });

    const head = { v: 2, lang: "yue", nc: cardsOrder.length, c: appChars };
    host.writeText(a.out, dumps(head).slice(0, -1) + ',"e":[\n' + appEntries.map(dumps).join(",\n") + "\n]}");
    host.log("粵語: " + appEntries.length + " words, " + cardsOrder.length + " cards, " + appChars.length + " characters; " +
        "no reading " + noReading + ", CC-Canto " + canto + ", fixed " + fixed + ", rime only " + onlyRime);
    return { words: appEntries.length, cards: cardsOrder.length, chars: appChars.length };
}
