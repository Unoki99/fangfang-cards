// 華語: 中華文化總會《兩岸常用詞典》 (g0v's dict-csld.json) → zh.json, with CC-CEDICT's English, the HSK 3.0 and
// TOCFL word lists, 教育部《重編國語辭典修訂本》 (dict-revised.json.xz) for the character cards and 近義／反義, and
// cjkvi-ids for 部首組合. The same as tools/build_mandarin.py (see there for the file's shape).
//   buildMandarin({csld, essay, out, cedict, hsk, tocfl, moe, hskChars, tbclChars, ids})
// And the input method codes (tools/build_inputcodes.py): buildInputCodes({cjBase, cjExt, wubi, out, cedict})
"use strict";

/** a CSV file's rows as objects by the header (Python's csv.DictReader; a BOM at the start is left out) */
function readCsvDicts(path) {
    let t = host.readText(path);
    if (t.charCodeAt(0) === 0xFEFF) t = t.slice(1);
    const rows = [];
    let row = [], f = "", i = 0, q = false;
    while (i < t.length) {
        const c = t[i];
        if (q) {
            if (c === "\"") { if (t[i + 1] === "\"") { f += "\""; i += 2; continue; } q = false; i++; continue; }
            f += c; i++; continue;
        }
        if (c === "\"") { q = true; i++; continue; }
        if (c === ",") { row.push(f); f = ""; i++; continue; }
        if (c === "\r") { i++; continue; }
        if (c === "\n") { row.push(f); rows.push(row); row = []; f = ""; i++; continue; }
        f += c; i++;
    }
    if (f !== "" || row.length) { row.push(f); rows.push(row); }
    const nonEmpty = rows.filter(r => !(r.length === 1 && r[0] === "") && r.length);
    if (!nonEmpty.length) return [];
    const head = nonEmpty[0];
    return nonEmpty.slice(1).map(r => {
        const o = {};
        head.forEach((h, j) => { o[h] = j < r.length ? r[j] : null; });
        return o;
    });
}

function buildMandarin(a) {
    host.progress(0.02, "讀《兩岸常用詞典》…");
    const D = JSON.parse(host.readText(a.csld));

    // 注音 → 拼音
    const INIT = {};
    "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ".split("").forEach((z, i) => { INIT[z] = "b p m f d t n l g k h j q x zh ch sh r z c s".split(" ")[i]; });
    const FIN = { "": "", "ㄚ": "a", "ㄛ": "o", "ㄜ": "e", "ㄝ": "ê", "ㄞ": "ai", "ㄟ": "ei", "ㄠ": "ao", "ㄡ": "ou",
        "ㄢ": "an", "ㄣ": "en", "ㄤ": "ang", "ㄥ": "eng", "ㄦ": "er",
        "ㄧ": "i", "ㄧㄚ": "ia", "ㄧㄛ": "io", "ㄧㄝ": "ie", "ㄧㄞ": "iai", "ㄧㄠ": "iao", "ㄧㄡ": "iu",
        "ㄧㄢ": "ian", "ㄧㄣ": "in", "ㄧㄤ": "iang", "ㄧㄥ": "ing",
        "ㄨ": "u", "ㄨㄚ": "ua", "ㄨㄛ": "uo", "ㄨㄞ": "uai", "ㄨㄟ": "ui", "ㄨㄢ": "uan", "ㄨㄣ": "un",
        "ㄨㄤ": "uang", "ㄨㄥ": "ong",
        "ㄩ": "ü", "ㄩㄝ": "üe", "ㄩㄢ": "üan", "ㄩㄣ": "ün", "ㄩㄥ": "iong" };
    const ALONE = { i: "yi", ia: "ya", io: "yo", ie: "ye", iai: "yai", iao: "yao", iu: "you", ian: "yan",
        in: "yin", iang: "yang", ing: "ying", u: "wu", ua: "wa", uo: "wo", uai: "wai",
        ui: "wei", uan: "wan", un: "wen", uang: "wang", ong: "weng", "ü": "yu", "üe": "yue",
        "üan": "yuan", "ün": "yun", iong: "yong" };
    const MARKS = { a: "āáǎà", e: "ēéěè", i: "īíǐì", o: "ōóǒò", u: "ūúǔù", "ü": "ǖǘǚǜ", "ê": "ê̄ếê̌ề" };
    const TONE_CH = { "ˊ": 2, "ˇ": 3, "ˋ": 4 };
    const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
    function zyParse(s) {
        let t = 1;
        if (s.startsWith("˙")) { t = 0; s = s.slice(1); }
        if (s.endsWith("˙")) { t = 0; s = s.slice(0, -1); }
        if (s && has(TONE_CH, s[s.length - 1])) { t = TONE_CH[s[s.length - 1]]; s = s.slice(0, -1); }
        if (!s) return null;
        const er = s.endsWith("ㄦ") && s.length > 1;
        if (er) s = s.slice(0, -1);
        const ini = INIT[s[0]] || "";
        const rest = ini ? s.slice(1) : s;
        if (!has(FIN, rest)) return null;
        let f = FIN[rest], p;
        if (ini) {
            if (f === "" && ["zh", "ch", "sh", "r", "z", "c", "s"].includes(ini)) f = "i";
            else if (f === "") return null;
            if (ini === "j" || ini === "q" || ini === "x") f = f.split("ü").join("u");
            p = ini + f;
        } else p = has(ALONE, f) ? ALONE[f] : f;
        if (er) p += "r";
        if (t >= 1 && t <= 4) {
            let v = null;
            if (p.includes("a")) v = p.indexOf("a");
            else if (p.includes("e") && !p.includes("ê")) v = p.indexOf("e");
            else if (p.includes("ê")) v = p.indexOf("ê");
            else if (p.includes("ou")) v = p.indexOf("o");
            else { for (let i = p.length - 1; i >= 0; i--) if ("iouü".includes(p[i])) { v = i; break; } }
            if (v !== null) p = p.slice(0, v) + cps(MARKS[p[v]])[t - 1] + p.slice(v + 1);
        }
        return [p, t];
    }
    const cleanZy = s => pyStrip(s.replace(/[臺陸]⃟/g, "").split("").join(""));
    function syllables(zy, title) {
        const parts = cleanZy(zy).split(/[　\s，,－\-﹐｜]+/u).filter(x => x);
        const hs = cps(title).filter(isHan);
        const out = [];
        for (const p of parts) {
            const r = zyParse(p);
            if (r === null) return null;
            out.push([p, r[0], r[1]]);
            const bare = p.replace(/[ˊˇˋ˙]+$/u, "");
            if (bare.endsWith("ㄦ") && cpLen(bare.replace(/^˙+/u, "")) > 1) {
                if (out.length < hs.length && hs[out.length] === "兒") out.push(["", "", r[1]]);
            }
        }
        if (out.length !== hs.length) return null;
        return out;
    }
    function joinPy(sy) {
        let s = "";
        for (const p of sy) {
            if (!p) continue;
            if (s && "aāáǎàoōóǒòeēéěèê".includes(cps(p)[0])) s += "'";
            s += p;
        }
        return s;
    }

    // frequency
    const freq = new Map();
    for (const line of host.readText(a.essay).split("\n")) {
        const p = line.split("\t");
        if (p.length >= 2 && /^\p{Nd}+$/u.test(p[1])) freq.set(p[0], Math.max(freq.get(p[0]) || 0, parseInt(p[1].normalize("NFKC"), 10)));
    }
    const fq = w => freq.get(w) || 0;

    // entries
    const cleanDef = t => pyStrip(t.replace(/<[^>]+>/g, "").split("臺⃝").join("〔臺灣〕").split("陸⃝").join("〔大陸〕"));
    const entries = [];
    const seenKeys = new Map();
    host.progress(0.08, "整理詞條…");
    for (const e of D) {
        const title = e.title;
        for (const h of e.heteronyms || []) {
            const zyparts = h.bopomofo.split("<br>");
            const tw = cleanZy(zyparts[0]);
            let lu = null;
            for (const x of zyparts.slice(1)) if (x.startsWith("陸⃝")) lu = cleanZy(x.slice(2));
            const spec = (h.specific_to || "") + (h.bopomofo.includes("臺⃟") ? "臺⃟" : "") + (h.bopomofo.includes("陸⃟") ? "陸⃟" : "");
            const sp = spec.includes("臺") ? 1 : (spec.includes("陸") ? 2 : 0);
            const sylTw = syllables(tw, title);
            const sylLu = lu ? syllables(lu, title) : null;
            if (sylTw === null) continue;
            const defs = [];
            let head = "";
            for (const x of h.definitions || []) {
                let t = cleanDef(x.def);
                const exs = [];
                for (const ex of x.example || []) {
                    for (const mm of ex.matchAll(/「(.*?)」/g)) {
                        let q = mm[1], src = "";
                        const m = /（([^（）]*)）$/.exec(q);
                        if (m) { src = m[1]; q = q.slice(0, m.index); }
                        q = pyStrip(q);
                        if (q) exs.push([q, src]);
                    }
                }
                if (t.endsWith("：") && !exs.length) { head = t; continue; }
                if (head && /^\(\d+\)/.test(t)) t = head + t;
                else head = "";
                const quoted = q => (q[1].includes("‧") || q[1].includes("•") || q[1].includes("《") || q[1].includes("〈")) ? 1 : 0;
                const sorted = exs.map((q, i) => [q, i]).sort((x, y) => quoted(x[0]) - quoted(y[0]) || x[1] - y[1]).map(x => x[0]);
                defs.push([t, sorted]);
            }
            if (!defs.length) continue;
            let k = title + "\t" + sylTw.filter(s => s[0]).map(s => s[0]).join(" ");
            seenKeys.set(k, (seenKeys.get(k) || 0) + 1);
            if (seenKeys.get(k) > 1) k += "#" + seenKeys.get(k);
            entries.push({ k, h: title, tw: sylTw, lu: sylLu, sp, alt: h.alt === undefined ? null : h.alt, defs });
        }
    }

    // splitting sentences into words
    const words = new Map();
    for (const en of entries) { if (!words.has(en.h)) words.set(en.h, []); words.get(en.h).push(en); }
    let MAXLEN = 0; for (const w of words.keys()) MAXLEN = Math.max(MAXLEN, cpLen(w));
    const ALONE_READING = { "的": "˙ㄉㄜ", "了": "˙ㄌㄜ", "著": "˙ㄓㄜ", "得": "˙ㄉㄜ", "們": "˙ㄇㄣ", "麼": "˙ㄇㄜ", "嗎": "˙ㄇㄚ",
        "呢": "˙ㄋㄜ", "吧": "˙ㄅㄚ", "啊": "˙ㄚ", "都": "ㄉㄡ", "還": "ㄏㄞˊ", "個": "ㄍㄜˋ", "沒": "ㄇㄟˊ",
        "給": "ㄍㄟˇ", "那": "ㄋㄚˋ", "哪": "ㄋㄚˇ", "誰": "ㄕㄟˊ", "會": "ㄏㄨㄟˋ", "要": "ㄧㄠˋ", "說": "ㄕㄨㄛ",
        "為": "ㄨㄟˋ", "中": "ㄓㄨㄥ", "好": "ㄏㄠˇ", "看": "ㄎㄢˋ", "只": "ㄓˇ", "長": "ㄔㄤˊ", "重": "ㄓㄨㄥˋ",
        "地": "ㄉㄧˋ", "大": "ㄉㄚˋ", "和": "ㄏㄜˊ", "把": "ㄅㄚˇ", "少": "ㄕㄠˇ", "種": "ㄓㄨㄥˇ", "行": "ㄒㄧㄥˊ" };
    function readingOf(han) {
        const ens = words.get(han);
        if (!ens || !ens.length) return null;
        let en;
        if (ens.length > 1) {
            const want = ALONE_READING[han];
            for (const x of ens) if (want && x.tw[0][0] === want) return [x.tw, x.lu];
            en = ens[0];
            for (const x of ens) if (x.defs.length > en.defs.length) en = x;
        } else en = ens[0];
        return [en.tw, en.lu];
    }
    const zyStr = syl => syl.map(s => s[0] ? s[0] : "-").join(" ");
    const NUM = new Set(cps("〇零一二三四五六七八九十百千萬億兩第"));
    function segment(text0, own) {
        const text = cps(text0);
        const n = text.length;
        const best = Array(n + 1).fill(null), back = Array(n + 1).fill(null);
        best[0] = [0, 0];
        for (let i = 0; i < n; i++) {
            if (best[i] === null) continue;
            const [cnt, sc] = best[i];
            const ch = text[i];
            const cands = [];
            if (!isHan(ch)) cands.push([i + 1, null]);
            else {
                for (let L = Math.min(MAXLEN, n - i); L > 0; L--) {
                    const w = text.slice(i, i + L).join("");
                    if ((own && w === own[0]) || words.has(w)) cands.push([i + L, w]);
                }
                if (!cands.length) cands.push([i + 1, "?"]);
            }
            for (const [j, w] of cands) {
                const ns = [cnt + 1, sc - (w && w !== "?" ? fq(w) : 0)];
                if (best[j] === null || ns[0] < best[j][0] || (ns[0] === best[j][0] && ns[1] < best[j][1])) { best[j] = ns; back[j] = [i, w]; }
            }
        }
        const pieces = [];
        let j = n;
        while (j > 0) { const [i, w] = back[j]; pieces.push([text.slice(i, j).join(""), w]); j = i; }
        pieces.reverse();
        const out = [];
        for (const [seg, w] of pieces) {
            if (w === null || w === "?") { out.push([seg, "", "", "", "", "", "", ""]); continue; }
            let tw, lu;
            if (own && w === own[0]) { tw = own[1]; lu = own[2]; } else [tw, lu] = readingOf(w);
            const twpy = tw.map(s => s[1]), twzy = tw.map(s => s[0]), tones = tw.map(s => String(s[2])).join("");
            let lupy = "", luzy = "";
            if (lu) { lupy = joinPy(lu.map(s => s[1])); luzy = lu.filter(s => s[0]).map(s => s[0]).join(" "); }
            const luDiff = lu && (lu.length !== tw.length || lu.some((s, i) => s[0] !== tw[i][0]));
            out.push([seg, joinPy(twpy), twzy.filter(z => z).join(" "), lupy, luzy, tones, zyStr(tw), luDiff ? zyStr(lu) : ""]);
        }
        out.forEach((p, idx) => {
            if ((p[0] !== "一" && p[0] !== "不") || !p[5]) return;
            let nxt = null;
            for (const q of out.slice(idx + 1)) if (q[5]) { nxt = q; break; }
            if (nxt === null || out[idx + 1][5] === "") return;
            const prev = idx > 0 ? out[idx - 1][0] : "";
            const pc = cps(prev);
            if (p[0] === "一" && ((pc.length && NUM.has(pc[pc.length - 1])) || NUM.has(cps(nxt[0])[0]))) return;
            const t = nxt[5][0];
            if (p[0] === "不") { if (t === "4") { p[1] = "bú"; p[2] = "ㄅㄨˊ"; p[5] = "2"; p[6] = "ㄅㄨˊ"; } }
            else {
                if (t === "4") { p[1] = "yí"; p[2] = "ㄧˊ"; p[5] = "2"; p[6] = "ㄧˊ"; }
                else if ("123".includes(t)) { p[1] = "yì"; p[2] = "ㄧˋ"; p[5] = "4"; p[6] = "ㄧˋ"; }
            }
        });
        out.forEach((p, idx) => {
            if (cpLen(p[0]) < 2 || !p[0].endsWith("不") || !p[5].endsWith("4")) return;
            const nxt = idx + 1 < out.length ? out[idx + 1] : null;
            if (!nxt || !nxt[5] || nxt[5][0] !== "4") return;
            if (!p[1].endsWith("bù")) return;
            p[1] = p[1].slice(0, -2) + "bú";
            p[5] = p[5].slice(0, -1) + "2";
            for (const k of [2, 6]) if (p[k].endsWith("ㄅㄨˋ")) p[k] = p[k].slice(0, -3) + "ㄅㄨˊ";
            if (p[3].endsWith("bù")) p[3] = p[3].slice(0, -2) + "bú";
            for (const k of [4, 7]) if (p[k].endsWith("ㄅㄨˋ")) p[k] = p[k].slice(0, -3) + "ㄅㄨˊ";
        });
        return out;
    }
    const luDiffers = en => en.lu !== null && (en.lu.length !== en.tw.length || en.lu.some((s, i) => s[0] !== en.tw[i][0]));
    const isReference = en => en.defs.every(([t]) => /^(參見|見|同|「.*」的(異體字|簡化字|俗字|本字))/.test(t) || t === "姓。");
    function perChar(text, zys) {
        const sy = zys.split(" ");
        const out = []; let i = 0;
        for (const ch of cps(text)) { if (isHan(ch) && i < sy.length) { out.push(sy[i]); i++; } else out.push("_"); }
        return out.join(" ");
    }
    const pieceCode = p => !p[5] ? "" : perChar(p[0], p[6]) + (p[7] ? "/" + perChar(p[0], p[7]) : "");

    // English (CC-CEDICT)
    const ced = new Map(), cedRead = new Map();
    const SKIP = ["CL:", "variant of", "old variant of", "see ", "surname ", "also written", "abbr. for", "Taiwan pr.", "used in "];
    if (a.cedict) {
        for (const line of host.readText(a.cedict).split("\n")) {
            if (line.startsWith("#")) continue;
            const m = /^(\S+) (\S+) \[([^\]]*)\] \/(.*)\/\s*$/.exec(line.replace(/\r$/, ""));
            if (!m) continue;
            const [, trad, , py, defs] = m;
            const sy = py.toLowerCase().split("u:").join("v").split(/\s+/).filter(x => x);
            const toned = sy.join("").split("5").join("");
            const plain = toned.replace(/\d/g, "");
            const gl = [];
            for (let d of defs.split("/")) {
                d = pyStrip(d);
                if (!d || SKIP.some(s => d.startsWith(s))) continue;
                if (cpLen(d) > 60) d = d.replace(/\s*\([^()]*\b(?:Tw|PRC|lit\.|fig\.)\b[^()]*\)/g, "");
                if (cpLen(d) > 90) d = cps(d).slice(0, 88).join("").replace(/[\s\u0085\u001c-\u001f]+$/u, "") + "…";
                gl.push(d);
            }
            if (gl.length) { if (!ced.has(trad)) ced.set(trad, []); ced.get(trad).push([plain, toned, gl]); }
            const twm = /Taiwan pr\. \[([^\]]+)\]/.exec(defs);
            if (!cedRead.has(trad)) cedRead.set(trad, [sy, twm ? twm[1].toLowerCase().split("u:").join("v").split(/\s+/).filter(x => x) : null]);
        }
    }
    const stripMarks = s => s.normalize("NFD").replace(/\p{M}/gu, "");
    function numbered(syl) {
        const out = [];
        for (const s of syl) {
            if (!s[1]) continue;
            const base = stripMarks(s[1]).split("ü").join("v").toLowerCase();
            out.push(base + ([1, 2, 3, 4].includes(s[2]) ? String(s[2]) : ""));
        }
        return out.join("");
    }
    function english(en) {
        const cands = ced.get(en.h);
        if (!cands) return "";
        const want = new Set([numbered(en.tw)].concat(en.lu ? [numbered(en.lu)] : []));
        let exact = cands.filter(([, t]) => want.has(t)).map(c => c[2]);
        if (!exact.length) {
            const plain = new Set(Array.from(want).map(w => w.replace(/\d/g, "")));
            exact = cands.filter(([p]) => plain.has(p)).map(c => c[2]);
        }
        if (!exact.length && cands.length === 1 && (words.get(en.h) || []).length <= 1) exact = [cands[0][2]];
        const gl = [];
        for (const g of exact) for (const d of g) if (!gl.includes(d)) gl.push(d);
        return gl.slice(0, 8).join("; ");
    }

    // word lists: HSK 3.0 and TOCFL
    function lettersTones(py) {
        let tones = "", out = "";
        for (const ch of py.toLowerCase().normalize("NFD")) {
            if (ch === "̄") tones += "1";
            else if (ch === "́") tones += "2";
            else if (ch === "̌") tones += "3";
            else if (ch === "̀") tones += "4";
            else if (ch === "̈") out += "";
            else if (/\p{L}/u.test(ch)) out += ch;
        }
        return out.split("ü").join("v") + "\u0001" + tones;
    }
    const entryLt = syl => lettersTones(syl.filter(s => s[1]).map(s => s[1]).join(" ").split(" ").join(""));
    const ltLetters = lt => lt.split("\u0001")[0];
    const byTrad = new Map();
    entries.forEach((en, i) => { if (!byTrad.has(en.h)) byTrad.set(en.h, []); byTrad.get(en.h).push(i); });
    const added = new Map();
    const py2zy = new Map();
    for (const en of entries) for (const [z] of en.tw.concat(en.lu || [])) {
        if (!z) continue;
        const b = z.replace(/^[˙ˊˇˋ]+|[˙ˊˇˋ]+$/gu, "");
        let plain = zyParse(b)[0].normalize("NFD");
        plain = cps(plain).filter(c => !/\p{M}/u.test(c) || c === "̈").join("").split("ü").join("v").split("ü").join("v");
        if (!py2zy.has(plain)) py2zy.set(plain, b);
    }
    function cedZhuyin(sy) {
        const out = [];
        for (const s of sy) {
            if (s === "r5" && out.length && out[out.length - 1][0]) {
                const z0 = out[out.length - 1][0];
                const lead = z0.startsWith("˙") ? "˙" : "";
                const b0 = z0.replace(/^[˙ˊˇˋ]+|[˙ˊˇˋ]+$/gu, "");
                const mark = "ˊˇˋ".includes(z0[z0.length - 1]) ? z0[z0.length - 1] : "";
                const z = lead + b0 + "ㄦ" + mark;
                const pr = zyParse(z);
                if (pr === null) return null;
                out[out.length - 1] = [z, pr[0], pr[1]];
                out.push(["", "", pr[1]]);
                continue;
            }
            const m = /^([a-zv]+)([1-5])$/.exec(s);
            if (!m) return null;
            const b = py2zy.get(m[1]);
            if (!b) return null;
            const t = parseInt(m[2], 10);
            const z = t === 5 ? "˙" + b : b + ({ 1: "", 2: "ˊ", 3: "ˇ", 4: "ˋ" })[t];
            const pr = zyParse(z);
            if (pr === null) return null;
            out.push([z, pr[0], pr[1]]);
        }
        return out;
    }
    const POS_NAMES = { N: "名詞", V: "動詞", Vi: "動詞", Vst: "動詞", Vp: "動詞", Vpt: "動詞",
        Adj: "形容詞", Vs: "形容詞", "Vs-attr": "形容詞", "Vs-pred": "形容詞",
        "V-sep": "離合詞", "Vp-sep": "離合詞", "Vs-sep": "離合詞",
        Adv: "副詞", M: "量詞", Conj: "連詞", conj: "連詞", Pron: "代詞", Pr: "代詞",
        Prep: "介詞", Num: "數詞", Aux: "助動詞", Vaux: "助動詞", Ptc: "助詞", Intj: "嘆詞",
        Phonetic: "擬聲詞", Det: "限定詞", Suffix: "後綴", Prefix: "前綴", Name: "專有名詞" };
    const posOf = new Map();
    function addPos(i, pos) {
        for (const p of (pos || "").split("/")) {
            const n = POS_NAMES[pyStrip(p)];
            if (!n || !has(POS_NAMES, pyStrip(p))) continue;
            if (!posOf.has(i)) posOf.set(i, []);
            if (!posOf.get(i).includes(n)) posOf.get(i).push(n);
        }
    }
    function applyList(rows) {
        const levelOf = new Map(), missing = [];
        for (const [trads, simp, py, lvl, pos] of rows) {
            const want = lettersTones(py);
            let found = null;
            for (const trad of trads) {
                const cands = byTrad.get(trad) || [];
                if (!cands.length) continue;
                const exact = cands.filter(i => entryLt(entries[i].tw) === want || (entries[i].lu && entryLt(entries[i].lu) === want));
                const loose = cands.filter(i => ltLetters(entryLt(entries[i].tw)) === ltLetters(want));
                const pick = exact.length ? exact : (loose.length ? loose
                    : cands.map((i, n) => [i, n]).sort((x, y) => (entries[y[0]].defs.length - entries[x[0]].defs.length) || x[1] - y[1]).map(x => x[0]));
                found = pick[0];
                break;
            }
            if (found === null && trads.length && added.has(trads[0])) found = added.get(trads[0]);
            if (found !== null) {
                if (!levelOf.has(found) || levelOf.get(found) > lvl) levelOf.set(found, lvl);
                addPos(found, pos);
            } else missing.push([trads, simp, lvl, pos]);
        }
        for (const [trads, simp, lvl, pos] of missing) {
            const trad = trads.length ? trads[0] : "";
            if (!trad) continue;
            if (added.has(trad)) {
                const i = added.get(trad);
                if (!levelOf.has(i) || levelOf.get(i) > lvl) levelOf.set(i, lvl);
                addPos(i, pos);
                continue;
            }
            const nh = cps(trad).filter(isHan).length;
            const pcs = segment(trad);
            let tw = null, lu = null;
            if (cedRead.has(trad)) {
                const [sy, twsy] = cedRead.get(trad);
                const main = cedZhuyin(sy);
                const tws = twsy ? cedZhuyin(twsy) : null;
                if (main && main.length === nh) {
                    tw = tws && tws.length === nh ? tws : main;
                    if (tws && tws.length === nh && tws.some((x, i) => x[0] !== main[i][0])) lu = main;
                }
            }
            if (tw === null) {
                if (pcs.some(p => cps(p[0]).some(isHan) && !p[5])) continue;
                tw = [];
                for (const p of pcs) {
                    if (!p[5]) continue;
                    for (const z of p[6].split(" ")) {
                        if (z === "-") { tw.push(["", "", tw.length ? tw[tw.length - 1][2] : 1]); continue; }
                        const pr = zyParse(z);
                        tw.push([z, pr[0], pr[1]]);
                    }
                }
            }
            if (tw.length !== nh) continue;
            const g = english({ h: trad, tw, lu });
            const parts = pcs.filter(p => p[5]).map(p => p[0]).join("＋");
            const t = g ? "（英）" + g : "由「" + parts + "」組成。";
            entries.push({ k: trad + "\t" + tw.filter(s => s[0]).map(s => s[0]).join(" "), h: trad, tw, lu, sp: 0,
                alt: simp && simp !== trad ? simp : null, defs: [[t, []]], extra: true });
            added.set(trad, entries.length - 1);
            levelOf.set(entries.length - 1, lvl);
            addPos(entries.length - 1, pos);
            if (!words.has(trad)) words.set(trad, []);
            words.get(trad).push(entries[entries.length - 1]);
        }
        return levelOf;
    }
    host.progress(0.25, "HSK、TOCFL 詞表…");
    let hskOf = new Map(), tocflOf = new Map();
    if (a.hsk) {
        const rows = readCsvDicts(a.hsk).map(row => [
            row.Traditional.split("|").map(t => pyStrip(t)).filter(t => t), row.Simplified.split("|")[0], row.Pinyin,
            row.Level.startsWith("7") ? 7 : parseInt(row.Level, 10), row.POS || ""]);
        hskOf = applyList(rows);
    }
    const TOCFL_LEVELS = { "L0-1": 1, "L0-2": 2, L1: 3, L2: 4, L3: 5, L4: 6, L5: 7 };
    const TOCFL_NAMES = [["準備級一", 1], ["準備級1", 1], ["準備級二", 2], ["準備級2", 2], ["準備一", 1], ["準備1", 1], ["novice 1", 1], ["novice1", 1], ["準備二", 2], ["準備2", 2], ["novice 2", 2],
        ["novice2", 2], ["入門", 3], ["基礎", 4], ["進階", 5], ["高階", 6], ["流利", 7]];
    const lowerRow = row => { const r = {}; for (const k of Object.keys(row)) if (k) r[pyStrip(k).toLowerCase()] = pyStrip(row[k] || ""); return r; };
    const tl = s => has(TOCFL_LEVELS, s) ? TOCFL_LEVELS[s] : undefined;
    function tocflLevel(row) {
        const r = lowerRow(row);
        const idv = r.id || "";
        let lvl = tl(idv.slice(0, 4)) || tl(idv.slice(0, 2));
        if (lvl) return lvl;
        for (const key of ["level", "band", "等級", "級別"]) {
            const v = r[key] || "";
            if (!v) continue;
            const lv = v.toLowerCase();
            for (const [name, n] of TOCFL_NAMES) if (lv.includes(name)) return n;
            lvl = tl(v.slice(0, 4)) || tl(v.slice(0, 2));
            if (lvl) return lvl;
            const m = /\d+/.exec(v);
            if (m && lv.includes("level") && parseInt(m[0], 10) >= 1 && parseInt(m[0], 10) <= 5) return parseInt(m[0], 10) + 2;
            if (m && /^\p{Nd}+$/u.test(v) && parseInt(v, 10) >= 1 && parseInt(v, 10) <= 7) return parseInt(v, 10);
        }
        return null;
    }
    const first = (row, ...keys) => { const r = lowerRow(row); for (const k of keys) if (r[k]) return r[k]; return ""; };
    if (a.tocfl) {
        const rows = [];
        for (const row of readCsvDicts(a.tocfl)) {
            const lvl = tocflLevel(row);
            if (!lvl) continue;
            const trad = first(row, "traditional", "word", "詞語", "詞彙", "hanzi");
            if (!trad) continue;
            const ts = trad.split(/[/|／]/).map(t => pyStrip(t)).filter(t => t);
            rows.push([ts.slice(0, 1), first(row, "simplified"), first(row, "pinyin", "拼音"), lvl, first(row, "pos", "詞類")]);
        }
        tocflOf = applyList(rows);
    }

    // 近義詞 / 反義詞 (《重編國語辭典修訂本》)
    host.progress(0.35, "讀《重編國語辭典修訂本》…");
    const moeAll = a.moe ? JSON.parse(a.moe.endsWith(".xz") ? host.xzText(a.moe) : host.readText(a.moe)) : [];
    const synOf = new Map(), antOf = new Map();
    const noParen = s => pyStrip(s.replace(/[（(].*?[）)]/g, ""));
    for (const e of moeAll) {
        const t = e.title || "";
        for (const h of e.heteronyms || []) {
            const zy = noParen(h.bopomofo || "");
            const sy = [], an = [];
            for (const d of h.definitions || []) {
                for (let w of (d.synonyms || "").split(",")) { w = pyStrip(w); if (w && w !== t && !sy.includes(w)) sy.push(w); }
                for (let w of (d.antonyms || "").split(",")) { w = pyStrip(w); if (w && w !== t && !an.includes(w)) an.push(w); }
            }
            if (sy.length) { synOf.set(t + "\u0001" + zy, sy); if (!synOf.has(t + "\u0002")) synOf.set(t + "\u0002", sy); }
            if (an.length) { antOf.set(t + "\u0001" + zy, an); if (!antOf.has(t + "\u0002")) antOf.set(t + "\u0002", an); }
        }
    }

    host.progress(0.45, "整理例句的讀音…");
    const outEntries = [];
    entries.forEach((en, idx) => {
        if (idx % 5000 === 0) host.progress(0.45 + 0.25 * idx / entries.length, "整理例句的讀音…");
        const tw = en.tw;
        const own = [en.h, tw, luDiffers(en) ? en.lu : null];
        const ds = en.defs.map(([t, exs]) => [t, exs.map(([q, src]) => [q, src, segment(q, own).map(pieceCode).join("|")])]);
        const c = { k: en.k, h: en.h, s: zyStr(tw), d: ds };
        if (luDiffers(en)) c.l = zyStr(en.lu);
        if (en.sp) c.p = en.sp;
        if (en.alt) c.a = en.alt;
        const g = english(en);
        if (g) c.n = g;
        if (hskOf.has(idx)) c.x = hskOf.get(idx);
        if (tocflOf.has(idx)) c.y = tocflOf.get(idx);
        if (en.extra) c.q = 1;
        if (posOf.get(idx) && posOf.get(idx).length) c.w = posOf.get(idx);
        const zs = pyStrip(zyStr(tw).split("-").join(""));
        const sy = synOf.get(en.h + "\u0001" + zs) || synOf.get(en.h + "\u0002");
        const an = antOf.get(en.h + "\u0001" + zs) || antOf.get(en.h + "\u0002");
        if (sy) c.j = sy.slice(0, 8);
        if (an) c.f = an.slice(0, 8);
        c._f = fq(en.h); c._ref = isReference(en); c._i = idx;
        outEntries.push(c);
    });
    const late = c => (c._ref || c._f === 0) ? 1 : 0;
    outEntries.sort((x, y) => (late(x) - late(y)) || (y._f - x._f) || (x._i - y._i));
    const nc = outEntries.filter(c => !late(c)).length;
    for (const c of outEntries) { delete c._f; delete c._ref; delete c._i; }

    // 漢字 cards
    host.progress(0.72, "整理漢字卡…");
    const cfreq = new Map();
    for (const [w, f] of freq) for (const ch of cps(w)) if (isHan(ch)) cfreq.set(ch, (cfreq.get(ch) || 0) + f);
    const cf = ch => cfreq.get(ch) || 0;
    // (by code point, as Python compares strings: not by UTF-16, which puts 𢠳 before 慨 U+FA3E)
    const byCp = (x, y) => { const p = cps(x), q = cps(y); for (let i = 0; i < Math.min(p.length, q.length); i++) { const d = p[i].codePointAt(0) - q[i].codePointAt(0); if (d) return d; } return p.length - q.length; };
    const charsOut = [];
    if (moeAll.length) {
        const moe = new Map();
        for (const e of moeAll) { const t = e.title || ""; if (cpLen(t) === 1 && isHan(t)) moe.set(t, e); }
        function lvlOf(path, colChar, colLvl) {
            const out = new Map();
            if (!path) return out;
            for (const row of readCsvDicts(path)) {
                const ch = pyStrip((row[colChar] || "").split("/")[0]);
                const l = parseInt(String(row[colLvl]).split("-")[0], 10);
                if (!/^\s*[+-]?\d+\s*$/.test(String(row[colLvl]).split("-")[0]) || isNaN(l)) continue;
                if (cpLen(ch) === 1 && (!out.has(ch) || out.get(ch) > l)) out.set(ch, l);
            }
            return out;
        }
        const hskCh = new Map(Array.from(lvlOf(a.hskChars, "Traditional", "Level")).map(([c, l]) => [c, Math.min(l, 7)]));
        const tbclCh = lvlOf(a.tbclChars, "Traditional", "Level");
        function moeReadings(e) {
            const out = [];
            for (const h of e.heteronyms || []) {
                const bp = h.bopomofo || "";
                const zy = noParen(bp);
                const label = Array.from(bp.matchAll(/[（(](.*?)[）)]/g)).map(m => m[1]);
                const py = noParen(h.pinyin || "");
                const ds = [];
                for (const d of h.definitions || []) {
                    const t = pyStrip((d.def || "").replace(/<[^>]+>/g, ""));
                    if (!t) continue;
                    const ex = (d.example || []).map(x => pyStrip(x.replace(/<[^>]+>/g, ""))).join("");
                    ds.push([d.type === undefined ? "" : d.type, ex ? t + ex : t]);
                }
                if (!ds.length || !zy || zy.includes(" ")) continue;
                out.push([zy, py, ds].concat(label.length ? [label[0]] : []));
            }
            return out;
        }
        const real = rs => rs.some(r => r[2].some(d => !/^「.」的異體字。$/u.test(d[1])));
        const listed = new Set([...hskCh.keys(), ...tbclCh.keys()]);
        const picked = Array.from(listed).sort((x, y) => (cf(y) - cf(x)) || byCp(x, y)).filter(ch => moe.has(ch) && real(moeReadings(moe.get(ch))));
        const MORE = 3000;
        const mostCommon = Array.from(cfreq).map((x, i) => [x, i]).sort((p, q) => (q[0][1] - p[0][1]) || (p[1] - q[1])).map(x => x[0][0]);
        const more = mostCommon.filter(ch => !listed.has(ch) && moe.has(ch) && words.has(ch) && real(moeReadings(moe.get(ch)))).slice(0, MORE);
        const usage = new Map();
        for (const [w, ens] of words) {
            const wc = cps(w);
            if (wc.length < 2 || !ens.length) continue;
            const tw = ens[0].tw;
            if (tw.length !== wc.length) continue;
            const f = fq(w) + 1;
            wc.forEach((ch, i) => {
                if (isHan(ch) && tw[i][0] && !tw[i][0].startsWith("˙")) {
                    if (!usage.has(ch)) usage.set(ch, new Map());
                    const u = usage.get(ch); u.set(tw[i][0], (u.get(tw[i][0]) || 0) + f);
                }
            });
        }
        for (const ch of picked.concat(more)) {
            const rs = moeReadings(moe.get(ch));
            const u = usage.get(ch) || new Map();
            const ug = z => u.get(z) || 0;
            const main = readingOf(ch);
            let mz = main && main[0] ? main[0][0][0] : (rs.length ? rs[0][0] : null);
            if (has(ALONE_READING, ch) && rs.some(r => r[0] === ALONE_READING[ch])) mz = ALONE_READING[ch];
            else if (rs.length && !(mz || "").startsWith("˙")) {
                let best = rs[0];
                for (const r of rs) {
                    const kb = [ug(best[0]), -(best.length > 3 ? 1 : 0)], kr = [ug(r[0]), -(r.length > 3 ? 1 : 0)];
                    if (kr[0] > kb[0] || (kr[0] === kb[0] && kr[1] > kb[1])) best = r;
                }
                const b = best[0];
                if (ug(b) > 0 && ug(mz) * 2 < ug(b)) mz = b;
            }
            const sortedRs = rs.map((r, i) => [r, i]).sort((p, q) => {
                const a1 = p[0][0] === mz ? 0 : 1, b1 = q[0][0] === mz ? 0 : 1;
                return (a1 - b1) || (ug(q[0][0]) - ug(p[0][0])) || ((p[0].length > 3 ? 1 : 0) - (q[0].length > 3 ? 1 : 0)) || (p[1] - q[1]);
            }).map(x => x[0]);
            const c = { h: ch, m: sortedRs };
            if (hskCh.has(ch)) c.x = hskCh.get(ch);
            if (tbclCh.has(ch)) c.y = tbclCh.get(ch);
            const e = moe.get(ch);
            if (e.radical) c.b = pyStrip(e.radical);
            if (e.stroke_count) c.n = e.stroke_count;
            charsOut.push(c);
        }
    }

    // 部首 lookup
    host.progress(0.85, "整理部首…");
    const radOf = new Map();
    for (const e of D.concat(moeAll)) {
        const t = e.title || "";
        if (cpLen(t) !== 1 || !isHan(t) || radOf.has(t)) continue;
        const r = e.radical, n = e.non_radical_stroke_count;
        if (r && n !== undefined && n !== null) radOf.set(t, [pyStrip(r), parseInt(n, 10), parseInt(e.stroke_count || 0, 10)]);
    }
    const radStrokes = new Map();
    for (const [t, [r, n, total]] of radOf) if (t === r && n === 0 && total) radStrokes.set(r, total);
    const rs99 = r => radStrokes.has(r) ? radStrokes.get(r) : 99;
    const rads = Array.from(new Set(Array.from(radOf.values()).map(x => x[0]))).sort((x, y) => (rs99(x) - rs99(y)) || (cf(y) - cf(x)) || byCp(x, y));
    const radList = rads.map(r => [r, radStrokes.get(r) || 0]);
    const charsByRad = new Map();
    for (const [t, [r, n]] of radOf) { if (!charsByRad.has(r)) charsByRad.set(r, []); charsByRad.get(r).push([n, -cf(t), t]); }
    const tupleSort = v => v.slice().sort((p, q) => (p[0] - q[0]) || (p[1] - q[1]) || byCp(p[2], q[2]));
    const radChars = new Map(), radRes = new Map();
    for (const [r, v] of charsByRad) { const s = tupleSort(v); radChars.set(r, s.map(x => x[2]).join("")); radRes.set(r, s.map(x => x[0])); }

    // 部首組合
    let radIn = null;
    if (a.ids) {
        const RADSET = new Set(rads);
        const VARIANT = { "亻": "人", "𠆢": "人", "刂": "刀", "⺈": "刀", "㔾": "卩", "氵": "水", "氺": "水", "扌": "手", "龵": "手",
            "忄": "心", "㣺": "心", "犭": "犬", "礻": "示", "衤": "衣", "糹": "糸", "纟": "糸", "訁": "言", "讠": "言",
            "釒": "金", "钅": "金", "飠": "食", "饣": "食", "艹": "艸", "䒑": "艸", "⺾": "艸", "⺿": "艸", "辶": "辵", "⻌": "辵",
            "⻍": "辵", "灬": "火", "爫": "爪", "罒": "网", "⺲": "网", "罓": "网", "王": "玉", "𤣩": "玉", "⺼": "肉",
            "攵": "攴", "歺": "歹", "牜": "牛", "⺧": "牛", "耂": "老", "覀": "襾", "西": "襾", "镸": "長", "长": "長",
            "𧾷": "足", "⻊": "足", "彑": "彐", "⺕": "彐", "丬": "爿", "𦍌": "羊", "⺶": "羊", "⺷": "羊", "𥫗": "竹",
            "⺮": "竹", "尣": "尢", "旡": "无", "⺊": "卜", "⺍": "小", "⺌": "小", "门": "門", "贝": "貝", "车": "車",
            "见": "見", "鱼": "魚", "鸟": "鳥", "马": "馬", "页": "頁", "风": "風", "韦": "韋", "齿": "齒", "龙": "龍",
            "龟": "龜", "麦": "麥", "黄": "黃", "齐": "齊", "卤": "鹵", "黾": "黽", "飞": "飛", "⻗": "青", "戸": "戶", "户": "戶", "母": "毋", "⺟": "毋" };
        const ids = new Map();
        for (const line of host.readText(a.ids).split("\n")) {
            if (line.startsWith("#") || !line.includes("\t")) continue;
            const parts = line.replace(/\r$/, "").split("\t");
            if (parts.length < 3) continue;
            const ch = parts[1], alts = parts.slice(2);
            const best = alts.find(x => { const m = /\[([A-Z]*)\]/.exec(x); return (m ? m[1] : "").includes("T"); }) || alts[0];
            ids.set(ch, best.replace(/\[[A-Z]*\]/g, ""));
        }
        const memo = new Map();
        const IDC = "⿰⿱⿲⿳⿴⿵⿶⿷⿸⿹⿺⿻〾";
        function comps(c, depth) {
            if (memo.has(c)) return memo.get(c);
            const out = new Set([c]);
            const d = ids.get(c);
            if (d && d !== c && depth < 12) {
                for (const m of d.matchAll(/&[^;]+;|./gu)) {
                    const x = m[0];
                    if (IDC.includes(x)) continue;
                    for (const y of comps(x, depth + 1)) out.add(y);
                }
            }
            memo.set(c, out);
            return out;
        }
        const byRad = new Map();
        for (const [t, [r, , total]] of radOf) {
            const rs = new Set([r]);
            const d = ids.get(t) || "";
            for (const x of comps(t, 0)) {
                if (x === "阝") rs.add(r === "阜" || r === "邑" ? r : (d.startsWith("⿰阝") ? "阜" : "邑"));
                else if (x === "月" && r === "肉") rs.add("肉");
                else if (RADSET.has(x)) rs.add(x);
                else if (has(VARIANT, x)) rs.add(VARIANT[x]);
            }
            for (const x of rs) if (RADSET.has(x)) { if (!byRad.has(x)) byRad.set(x, []); byRad.get(x).push([total || 99, -cf(t), t]); }
        }
        radIn = {};
        for (const [r, v] of byRad) radIn[r] = tupleSort(v).map(x => x[2]).join("");
    }

    const head = { v: 1, nc };
    head.r = radList.map(([r, n]) => [r, n, radChars.get(r), radRes.get(r)]);
    if (radIn && Object.keys(radIn).length) head.rx = radIn;
    if (charsOut.length) head.c = charsOut;
    host.progress(0.95, "寫 zh.json…");
    host.writeText(a.out, JSON.stringify(head).slice(0, -1) + ',"e":[\n' + outEntries.map(c => JSON.stringify(c)).join(",\n") + "\n]}");
    host.log("zh.json: " + outEntries.length + " words, " + nc + " cards, " + charsOut.length + " characters");
    return { words: outEntries.length, cards: nc };
}

function buildInputCodes(a) {
    function rimeTable(path) {
        const out = new Map();
        let body = false;
        for (const line0 of host.readText(path).split("\n")) {
            const line = line0.replace(/\r$/, "");
            if (!body) { body = pyStrip(line) === "..."; continue; }
            if (!line || line.startsWith("#")) continue;
            const p = line.split("\t");
            if (p.length < 2 || cpLen(p[0]) !== 1) continue;
            if (!out.has(p[0])) out.set(p[0], []);
            if (!out.get(p[0]).includes(p[1])) out.get(p[0]).push(p[1]);
        }
        return out;
    }
    const cj = rimeTable(a.cjBase);
    for (const [ch, cs] of rimeTable(a.cjExt)) if (!cj.has(ch)) cj.set(ch, cs);
    const wbAll = rimeTable(a.wubi);
    const wb = new Map();
    for (const [ch, cs] of wbAll) wb.set(ch, cs.slice().sort((x, y) => (y.length - x.length) || (x < y ? -1 : x > y ? 1 : 0)).slice(0, 1));
    if (a.cedict) {
        for (const line of host.readText(a.cedict).split("\n")) {
            if (line.startsWith("#")) continue;
            const i1 = line.indexOf(" "), i2 = i1 < 0 ? -1 : line.indexOf(" ", i1 + 1);
            const p = i1 < 0 ? [line] : [line.slice(0, i1), i2 < 0 ? line.slice(i1 + 1) : line.slice(i1 + 1, i2)];
            if (p.length >= 2 && cpLen(p[0]) === 1 && cpLen(p[1]) === 1 && !wb.has(p[0]) && wb.has(p[1])) wb.set(p[0], wb.get(p[1]));
        }
    }
    const obj = m => { const o = {}; for (const [k, v] of m) o[k] = v; return o; };
    const out = { c: obj(new Map(Array.from(cj).map(([ch, cs]) => [ch, cs.slice(0, 2).join(" ")]))),
        w: obj(new Map(Array.from(wb).map(([ch, cs]) => [ch, cs.join(" ")]))) };
    host.writeText(a.out, JSON.stringify(out));
    return { cangjie: cj.size, wubi: wb.size };
}

/** 華語 in the app: zh.json, then the input method codes (inputcodes.json) when their tables were downloaded */
function buildMandarinAll(a) {
    const r = buildMandarin(Object.assign({}, a, { out: a.out_zh || a.out }));
    if (a.cjBase && a.cjExt && a.wubi && a.out_inputcodes) {
        host.progress(0.97, "整理倉頡、五筆碼…");
        buildInputCodes({ cjBase: a.cjBase, cjExt: a.cjExt, wubi: a.wubi, out: a.out_inputcodes, cedict: a.cedict });
    }
    return r;
}
