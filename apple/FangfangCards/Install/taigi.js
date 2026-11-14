// 台語: 教育部《臺灣台語常用詞辭典》's file (kautian.ods) → dict.json and cards.json. The same as the Python tools
// (ods2csv.py → build_moe.py → to_app_data.py → build_cards.py, with anchor.py's syllable codes); see there for
// what each step does. The dictionary's licence (CC BY-ND 3.0 TW) doesn't allow sharing changed versions, so each
// phone (or computer) makes its own copy from the original file.
//   buildTaigi({ods, own: own.json's text or null, essay, outDict, outCards})
"use strict";

// ───────────────────────────── anchor.py: the syllable code ─────────────────────────────
const TwCode = (() => {
    const CODE_RE = /^([pPbtTdkKgcCzsh]?)(N?)([iuaoøeIUɨəɵ]*)([BDG]?)([1-9])$/u;
    function parse(code) {
        const m = CODE_RE.exec(code);
        if (!m) return null;
        const [, ini, nas, vow, fin, tone] = m;
        if (!vow && !fin) return null;
        return [ini, !!nas, vow, fin, parseInt(tone, 10)];
    }
    const TL_TONE = { "́": 2, "̀": 3, "̂": 5, "̌": 6, "̄": 7, "̍": 8, "̋": 9 };
    function tlSplit(s) {
        let tone = null; const out = [];
        for (const ch of s.normalize("NFD")) { if (ch in TL_TONE) tone = TL_TONE[ch]; else out.push(ch); }
        let w = out.join("").normalize("NFC");
        const first = cps(w)[0] || "";
        const cap = first !== "" && first !== first.toLowerCase() && first === first.toUpperCase();
        w = w.toLowerCase();
        if (tone === null) tone = /[ptkh]$/.test(w) ? 4 : 1;
        return [w, tone, cap];
    }
    const TL_INI = [["tsh", "C"], ["ts", "c"], ["ph", "P"], ["th", "T"], ["kh", "K"], ["ng", "gN"],
        ["p", "p"], ["b", "b"], ["t", "t"], ["k", "k"], ["g", "g"], ["h", "h"], ["s", "s"],
        ["j", "z"], ["l", "d"], ["m", "bN"], ["n", "dN"]];
    const TL_INI_MAP = Object.fromEntries(TL_INI);
    const TL_V = [["ir", "ɨ"], ["er", "ə"], ["or", "ɵ"], ["ai", "I"], ["au", "U"], ["oo", "o"],
        ["a", "a"], ["e", "e"], ["i", "i"], ["o", "ø"], ["u", "u"]];
    function tlToCode(w, tone) {
        const m = /^(tsh|ts|ph|th|kh|p|b|t|k|g|h|s|j|l|m|n)?(m|ng)(h?)$/.exec(w);
        if (m) {
            if (m[3] && tone !== 4 && tone !== 8) return null;
            const i = m[1] ? TL_INI_MAP[m[1]].slice(0, 1) : "";
            return i + (m[2] === "m" ? "B" : "G") + tone;
        }
        let ini = "";
        for (const [t, c] of TL_INI) {
            if (w.startsWith(t) && w.length > t.length) { ini = c; w = w.slice(t.length); break; }
        }
        let nasal = false;
        if (ini.endsWith("N")) { ini = ini[0]; if (/^[aeiou]/.test(w)) nasal = true; }
        if (w.endsWith("nnh")) { nasal = true; w = w.slice(0, -3) + "h"; }
        else if (w.endsWith("nn")) { nasal = true; w = w.slice(0, -2); }
        let fin = "";
        for (const [t, c] of [["ng", "G"], ["m", "B"], ["n", "D"], ["p", "B"], ["t", "D"], ["k", "G"], ["h", ""]]) {
            if (w.endsWith(t) && w.length > t.length) { fin = c; w = w.slice(0, -t.length); break; }
        }
        let vow = "", rest = w;
        while (rest) {
            const v = TL_V.find(([t]) => rest.startsWith(t));
            if (!v) return null;
            vow += v[1]; rest = rest.slice(v[0].length);
        }
        if (!vow) return null;
        if (vow === "i" && fin === "G") vow = "iø";
        if ((vow === "ø" || vow === "iø") && (fin === "G" || fin === "B") && vow !== "iø") vow = "o";
        if (vow === "iø" && fin === "G" && w.includes("io")) vow = "io";
        if (nasal && vow.endsWith("ø")) vow = vow.slice(0, -1) + "o";
        return ini + (nasal ? "N" : "") + vow + fin + tone;
    }

    const ZY_INI = { p: "ㄅ", P: "ㄆ", b: "ㆠ", t: "ㄉ", T: "ㄊ", d: "ㄌ", k: "ㄍ", K: "ㄎ", g: "ㆣ", h: "ㄏ", c: "ㄗ", C: "ㄘ", s: "ㄙ", z: "ㆡ" };
    const ZY_PAL = { c: "ㄐ", C: "ㄑ", s: "ㄒ", z: "ㆢ" };
    const ZY_NASINI = { b: "ㄇ", d: "ㄋ", g: "ㄫ" };
    const ZY_V = { i: "ㄧ", u: "ㄨ", a: "ㄚ", o: "ㆦ", "ø": "ㄜ", e: "ㆤ", I: "ㄞ", U: "ㄠ", "ɨ": "ㆨ", "ə": "ㄜ", "ɵ": "ㄜ" };
    const ZY_NAS = { "ㄧ": "ㆪ", "ㄨ": "ㆫ", "ㄚ": "ㆩ", "ㆦ": "ㆧ", "ㆤ": "ㆥ", "ㄞ": "ㆮ", "ㄠ": "ㆯ" };
    const ZY_TONE = { 1: "ˉ", 2: "ˋ", 3: "˪", 4: "", 5: "ˊ", 6: "꜕", 7: "˫", 8: "̇", 9: "ꜘ" };
    const need = (o, k) => { if (!(k in o)) throw new Error("KeyError " + k); return o[k]; };
    function toZhuyin(code) {
        const p = parse(code);
        if (!p) return null;
        let [ini, nas, vow, fin, tone] = p;
        const stop = tone === 4 || tone === 8;
        const out = [];
        const v = cps(vow);
        if (ini) {
            if (ini in ZY_NASINI && ((nas && vow) || !vow)) { out.push(ZY_NASINI[ini]); nas = false; }
            else if ((v[0] === "i" || v[0] === "ɨ") && ini in ZY_PAL && v[0] === "i") out.push(ZY_PAL[ini]);
            else out.push(need(ZY_INI, ini));
        }
        let vv = v;
        if (stop && fin === "G" && vow === "iø") vv = ["i"];
        let syms = vv.map((x, i) => (x === "e" && i > 0 && vv[i - 1] === "ə") ? "ㄝ" : need(ZY_V, x));
        if (nas && syms.length) syms[syms.length - 1] = ZY_NAS[syms[syms.length - 1]] || syms[syms.length - 1];
        if (stop) {
            let f = { B: "ㆴ", D: "ㆵ", G: "ㆻ", "": "ㆷ" }[fin];
            if (!vow && fin === "B") f = "ㆬㆷ";
            if (!vow && fin === "G") f = "ㆭㆷ";
            out.push(...syms, f);
        } else {
            const last = vv.length ? vv[vv.length - 1] : "";
            if (fin === "B" && (last === "a" || last === "o")) syms[syms.length - 1] = { a: "ㆰ", o: "ㆱ" }[last];
            else if (fin === "D" && last === "a") syms[syms.length - 1] = "ㄢ";
            else if (fin === "G" && last === "a") syms[syms.length - 1] = "ㄤ";
            else if (fin === "G" && last === "o") syms[syms.length - 1] = "ㆲ";
            else if (fin === "G" && vow === "iø") syms = ["ㄧ", "ㄥ"];
            else if (fin) syms.push({ B: "ㆬ", D: "ㄣ", G: "ㆭ" }[fin]);
            out.push(...syms);
        }
        return out.join("") + ZY_TONE[tone];
    }

    const HL_INI = { p: "p", P: "ph", b: "b", t: "t", T: "th", d: "l", k: "k", K: "kh", g: "g", h: "h", c: "z", C: "c", s: "s", z: "ł" };
    const HL_PAL = { c: "j", C: "q", s: "x", z: "ł" };
    const HL_NASINI = { b: "m", d: "n", g: "ng" };
    const HL_V = { i: "i", u: "u", a: "a", o: "oo", "ø": "o", e: "e", I: "ai", U: "au", "ɨ": "ir", "ə": "er", "ɵ": "o" };
    const HL_TONE = { 1: "̍", 2: "̀", 3: "̣", 4: "̣", 5: "́", 6: "̱", 7: "̄", 8: "̍", 9: "̋" };
    function markPos(body) {
        for (const v of ["a", "oo", "o", "e"]) if (body.includes(v)) return body.indexOf(v);
        if (body === "iu" || body === "ui") return 1;
        return 0;
    }
    function toHaolo(code) {
        const p = parse(code);
        if (!p) return null;
        let [ini, nas, vow, fin, tone] = p;
        const stop = tone === 4 || tone === 8;
        let head = "";
        const v0 = cps(vow);
        if (ini) {
            if (ini in HL_NASINI && ((nas && vow) || !vow)) { head = HL_NASINI[ini]; if (vow) nas = false; }
            else if (v0[0] === "i" && ini in HL_PAL) head = HL_PAL[ini];
            else head = need(HL_INI, ini);
        }
        let v = v0;
        if (fin === "G" && vow === "iø") v = ["i"];
        if (v.join("").endsWith("əe")) v = v.slice(0, -2).concat(["ERE"]);
        const parts = v.map(x => x === "ERE" ? "oe" : need(HL_V, x));
        if (fin && v.length && v[v.length - 1] === "o") parts[parts.length - 1] = "o";
        let tail;
        if (stop) {
            tail = { B: "p", D: "t", G: "k", "": "h" }[fin];
            if (!vow) tail = need({ B: "m", G: "ng" }, fin) + "h";
        } else tail = { B: "m", D: "n", G: "ng", "": "" }[fin];
        let body = parts.join("");
        if (body) { const pos = markPos(body); body = body.slice(0, pos + 1) + HL_TONE[tone] + body.slice(pos + 1); }
        else tail = tail[0] + HL_TONE[tone] + tail.slice(1);
        return (head + body + (nas ? "ⁿ" : "") + tail).normalize("NFC");
    }

    const TLM = { 1: "", 2: "́", 3: "̀", 4: "", 5: "̂", 6: "̌", 7: "̄", 8: "̍", 9: "̋" };
    const TL_INI_OUT = { p: "p", P: "ph", b: "b", t: "t", T: "th", d: "l", k: "k", K: "kh", g: "g", h: "h", c: "ts", C: "tsh", s: "s", z: "j" };
    const TL_V_OUT = { i: "i", u: "u", a: "a", o: "oo", "ø": "o", e: "e", I: "ai", U: "au", "ɨ": "ir", "ə": "er", "ɵ": "or" };
    function letters(code, poj) {
        let [ini, nas, vow, fin, tone] = parse(code);
        const stop = tone === 4 || tone === 8;
        let head = "";
        if (ini) {
            if (ini in HL_NASINI && ((nas && vow) || !vow)) { head = HL_NASINI[ini]; if (vow) nas = false; }
            else head = need(TL_INI_OUT, ini);
        }
        let v = cps(vow);
        if (fin === "G" && vow === "iø") v = ["i"];
        let body = v.map(x => need(TL_V_OUT, x)).join("");
        if (fin && v.length && v[v.length - 1] === "o") body = body.slice(0, -2) + "o";
        let tail;
        if (stop) {
            tail = { B: "p", D: "t", G: "k", "": "h" }[fin];
            if (!vow) tail = need({ B: "m", G: "ng" }, fin) + "h";
        } else tail = { B: "m", D: "n", G: "ng", "": "" }[fin];
        if (fin === "G" && vow === "iø" && poj) body = "e";
        return [head, body, tail, nas, tone];
    }
    function toTl(code) {
        if (!parse(code)) return null;
        let [head, body, tail, nas, tone] = letters(code, false);
        const nn = nas ? "nn" : "";
        if (body) {
            let pos;
            if (body.includes("a")) pos = body.indexOf("a");
            else if (body.includes("oo")) pos = body.indexOf("oo");
            else if (body.includes("o")) pos = body.indexOf("o");
            else if (body.includes("e")) pos = body.indexOf("e");
            else if (body === "iu" || body === "ui") pos = 1;
            else pos = 0;
            body = body.slice(0, pos + 1) + TLM[tone] + body.slice(pos + 1);
            if (tail.endsWith("h") && nas) return (head + body + tail.slice(0, -1) + nn + "h").normalize("NFC");
            return (head + body + tail + nn).normalize("NFC");
        }
        let t = tail;
        const k = t.startsWith("ng") ? 1 : 0;
        t = k === 0 ? t.slice(0, k + 1) + TLM[tone] + t.slice(k + 1) : t.slice(0, 1) + TLM[tone] + t.slice(1);
        return (head + t).normalize("NFC");
    }
    const POJ_INI = { ts: "ch", tsh: "chh" };
    function toPoj(code) {
        if (!parse(code)) return null;
        let [head, body, tail, nas, tone] = letters(code, true);
        head = POJ_INI[head] || head;
        body = body.split("oo").join("o͘");
        if (body.startsWith("ua") || body.includes("ua")) body = body.split("ua").join("oa");
        if (body.includes("ue")) body = body.split("ue").join("oe");
        const nn = nas ? "ⁿ" : "";
        if (body) {
            const b = body.split("͘").join("");
            let pos;
            if (b.includes("oai")) pos = b.indexOf("oai") + 1;
            else if ((b.includes("oa") || b.includes("oe")) && !tail) pos = b.indexOf("o");
            else if (b.includes("oa") || b.includes("oe")) pos = b.indexOf("o") + 1;
            else if (b.includes("a")) pos = b.indexOf("a");
            else if (b.includes("o")) pos = b.indexOf("o");
            else if (b.includes("e")) pos = b.indexOf("e");
            else if (b === "iu") pos = 1;
            else pos = 0;
            const out = []; let j = 0;
            for (const ch of body) {
                out.push(ch);
                if (ch !== "͘") { if (j === pos) out.push(TLM[tone]); j++; }
            }
            body = out.join("");
            if (tail === "h" && nas) return (head + body + "h" + nn).normalize("NFC");
            return (head + body + tail + nn).normalize("NFC");
        }
        if (head === "n") return (head.slice(0, 1) + TLM[tone] + head.slice(1) + tail).normalize("NFC");
        return (head + tail.slice(0, 1) + TLM[tone] + tail.slice(1)).normalize("NFC");
    }
    return { parse, tlSplit, tlToCode, toZhuyin, toHaolo, toTl, toPoj };
})();

/** Python's round(x, 1) */
function round1(x) { return parseFloat(x.toFixed(1)); }
/** Python's str.isdigit() for a field of a table */
const isDigits = s => /^\p{Nd}+$/u.test(s);

function buildTaigi(a) {
    const { parse, tlSplit, tlToCode, toZhuyin, toHaolo, toTl, toPoj } = TwCode;
    host.progress(0.02, "讀 kautian.ods…");
    const S = readOdsSheets(a.ods);
    const OWN = a.own ? JSON.parse(host.readText(a.own)) : { own: [], defs: {} };
    host.progress(0.2, "整理詞條…");

    // ═════════════════════ build_moe.py ═════════════════════
    const PLACES = S["語音差異"][0].slice(2);
    const G1 = new Set(["宜蘭偏漳腔", "臺南混合腔", "高雄混合腔", "臺中偏漳腔"].map(p => PLACES.indexOf(p)));
    const TYPES = ["主詞目", "臺華共同詞", "單字不成詞者", "附錄", "近反義詞不單列詞目者", "自補"];
    const rows = n => (S[n] || []).slice(1);
    const SYL = /[A-Za-z̀-ͯⁿ]+/gu;

    function separators(sep0, inside, tail) {
        let out = [];
        const sep = sep0.normalize("NFC");
        let i = 0;
        while (i < sep.length) {
            if (sep.startsWith("--", i)) { out.push("--"); i += 2; }
            else if (sep[i] === "-") i += 1;
            else if (sep[i] === " ") { if (!(out.length && out[out.length - 1] === "_")) out.push("_"); i += 1; }
            else {
                const cp = sep.codePointAt(i); const ch = String.fromCodePoint(cp);
                out.push(ch); i += ch.length;
            }
        }
        if (!inside) out = out.filter(x => x !== "_");
        if (tail) out = out.filter(x => x !== "_");
        return out;
    }
    function reading(text) {
        const t = pyStrip(text.replace(/　/g, " ")).normalize("NFD");
        let toks = [], pos = 0, m;
        SYL.lastIndex = 0;
        while ((m = SYL.exec(t)) !== null) {
            const sep = t.slice(pos, m.index);
            pos = m.index + m[0].length;
            toks = toks.concat(separators(sep, toks.length > 0, false));
            const [w, tone, cap] = tlSplit(m[0]);
            const c = tlToCode(w, tone);
            if (c === null) toks.push("~" + m[0].normalize("NFC"));
            else toks.push((cap ? "^" : "") + c);
        }
        toks = toks.concat(separators(t.slice(pos), true, true));
        return toks;
    }
    const rstr = toks => toks.join(" ");
    const strip1 = t => t.startsWith("^") ? t.slice(1) : t;     // (lstrip("^") on one ^)
    const lstripCaret = t => t.replace(/^\^+/, "");
    const codesOnly = toks => toks.map(lstripCaret).filter(t => parse(t));
    const split = s => s.split(/\s+/).filter(x => x);
    const eqList = (x, y) => x.length === y.length && x.every((v, i) => v === y[i]);
    const inLists = (x, ls) => ls.some(l => eqList(x, l));

    function alternatives(raw) {
        let reg = "";
        const m = /^【(白|文|俗)】/.exec(raw);
        if (m) reg = m[1];
        raw = raw.replace(/【.*?】/g, "");
        const alts = raw.split("/").filter(x => pyStrip(x)).map(x => rstr(reading(x)));
        return [reg, alts];
    }

    const pad = (r, n) => r.length >= n ? r : r.concat(Array(n - r.length).fill(""));
    const E = [], byId = new Map();
    const cats = [], catIx = new Map();
    for (const r0 of rows("詞目")) {
        const r = pad(r0, 6);
        const [eid, typ, han, rom, cat, audio] = r;
        const sub = han.includes("【替】");
        const h = pyStrip(han.replace(/【.*?】/g, ""));
        const e = { i: parseInt(eid, 10), h, t: TYPES.indexOf(typ) };
        if (sub) e.s = 1;
        if (rom) {
            const [reg, alts] = alternatives(rom);
            e.r = alts[0];
            if (reg) e.g = reg;
            if (alts.length > 1) e.a = alts.slice(1).map(x => [x, ""]);
        }
        const cl = [];
        for (const c of cat.split(",").map(x => pyStrip(x)).filter(x => x)) {
            if (!catIx.has(c)) { catIx.set(c, cats.length); cats.push(c); }
            cl.push(catIx.get(c));
        }
        if (cl.length) e.c = cl;
        const am = /^(\d+)\(1\)$/.exec(audio);
        if (am) e.au = parseInt(am[1], 10);
        E.push(e); byId.set(eid, e);
    }
    for (const [sheet, label] of [["又唸作", "又"], ["俗唸作", "俗"], ["合音唸作", "合"]]) {
        for (const r of rows(sheet)) {
            if (r.length < 3 || !byId.has(r[0])) continue;
            const e = byId.get(r[0]);
            for (const x of r[2].split("/")) if (pyStrip(x)) { (e.a = e.a || []).push([rstr(reading(x)), label]); }
        }
    }
    // (place-keyed tables are Maps: the order things were put in matters, as in Python)
    const mget = (e, f) => e[f] || (e[f] = new Map());
    for (const r of rows("語音差異")) {
        if (!byId.has(r[0])) continue;
        const e = byId.get(r[0]);
        r.slice(2).forEach((cell, i) => {
            if (!pyStrip(cell)) return;
            const forms = cell.split(",").filter(x => pyStrip(x)).map(x => rstr(reading(x)));
            mget(e, "sf").set(String(i), forms);
            const first = forms[0];
            if (first !== e.r) mget(e, "d").set(String(i), first);
            if (forms.length > 1) mget(e, "dd").set(String(i), forms.slice(1));
        });
    }
    const explicit = new Set();
    const ek = (i, p) => i + "\u0001" + p;
    for (const e of E) if (e.sf) for (const k of e.sf.keys()) explicit.add(ek(e.i, k));
    for (const e of E) if (e.d && e.d.size) e.dx = Array.from(e.d.keys()).sort((x, y) => parseInt(x, 10) - parseInt(y, 10));

    const byHan = new Map();
    for (const e of E) if ("r" in e) { if (!byHan.has(e.h)) byHan.set(e.h, []); byHan.get(e.h).push(e); }
    const said = new Map();     // han \u0001 place → [readings]
    for (const r of rows("詞彙比較")) {
        if (r.length < 5 || !PLACES.includes(r[2]) || !pyStrip(r[4])) continue;
        const k = r[3] + "\u0001" + String(PLACES.indexOf(r[2]));
        const rs = rstr(reading(r[4]));
        if (!said.has(k)) said.set(k, []);
        if (!said.get(k).includes(rs)) said.get(k).push(rs);
    }
    const allForms = new Map();
    for (const [k, forms] of said) {
        const han = k.split("\u0001")[0];
        if (!allForms.has(han)) allForms.set(han, []);
        for (const f of forms) allForms.get(han).push(codesOnly(split(f)));
    }
    function entryFor(han, n) {
        const cands = (byHan.get(han) || []).filter(e => codesOnly(split(e.r)).length === n);
        if (cands.length <= 1) return cands.length ? cands[0] : null;
        const overlap = e => {
            const m = codesOnly(split(e.r));
            let s = 0;
            for (const f of allForms.get(han) || []) if (f.length === n) for (let i = 0; i < Math.min(m.length, f.length); i++) if (m[i] === f[i]) s++;
            return s;
        };
        const best = Math.max(...cands.map(overlap));
        const top = cands.filter(e => overlap(e) === best);
        return top.length === 1 ? top[0] : null;
    }
    for (const [k, forms] of said) {
        const [han, pl] = k.split("\u0001");
        const fc = forms.map(f => codesOnly(split(f)));
        const e = entryFor(han, fc[0].length);
        if (e === null) continue;
        const main = codesOnly(split(e.r));
        let stated = [];
        if (explicit.has(ek(e.i, pl))) stated = e.sf.get(pl).slice();
        else if (e.dd && e.dd.has(pl)) stated = [e.r].concat(e.dd.get(pl));
        for (const f of forms) if (!inLists(codesOnly(split(f)), stated.map(x => codesOnly(split(x))))) stated.push(f);
        if (!stated.length) continue;
        if (!explicit.has(ek(e.i, pl))) {
            if (eqList(codesOnly(split(stated[0])), main)) { if (e.d) e.d.delete(pl); }
            else mget(e, "d").set(pl, stated[0]);
            if (!e.dx) e.dx = [];
            if (!e.dx.includes(pl)) e.dx.push(pl);
            (e.vx = e.vx || []).push(pl);
        }
        mget(e, "sf").set(pl, stated);
        const extra = stated.slice(1).filter(x => !eqList(codesOnly(split(x)), codesOnly(split(stated[0]))));
        if (extra.length) mget(e, "dd").set(pl, extra);
    }
    for (const e of E) for (const p of e.dx || []) explicit.add(ek(e.i, p));

    const senseTexts = new Map();
    for (const r of rows("義項")) { if (!senseTexts.has(r[0])) senseTexts.set(r[0], []); senseTexts.get(r[0]).push(r.length > 3 ? r[3] : ""); }
    const oneMeaning = new Set();
    const reEsc = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    for (const e of E) {
        if (cpLen(e.h) !== 1 || !e.d) continue;
        for (const pl of (e.vx || []).slice()) {
            const n = codesOnly(split(e.d.get(pl) || ""));
            if (n.length !== 1) continue;
            const tl = toTl(n[0]);
            const re = new RegExp("唸作\\s*" + reEsc(tl) + "(?![A-Za-z\\u00C0-\\u024F\\u0300-\\u036F])", "u");
            const hit = [];
            (senseTexts.get(String(e.i)) || []).forEach((t, i) => { if (re.test(t)) hit.push(i); });
            if (!hit.length) continue;
            oneMeaning.add(ek(e.i, pl));
            for (const i of hit) {
                const sd = mget(e, "sd");
                if (!sd.has(String(i))) sd.set(String(i), new Map());
                sd.get(String(i)).set(pl, e.d.get(pl));
            }
            e.d.delete(pl);
            if (e.dx && e.dx.includes(pl)) e.dx.splice(e.dx.indexOf(pl), 1);
        }
    }

    const rrule = new Map();     // char \u0001 code → Map(place → code)
    const rk = (h, c) => h + "\u0001" + c;
    for (const e of E) {
        if (cpLen(e.h) !== 1 || !("r" in e) || !e.d) continue;
        const m = split(e.r);
        if (m.length !== 1) continue;
        for (const [pl, r] of e.d) {
            if (!explicit.has(ek(e.i, pl)) || oneMeaning.has(ek(e.i, pl))) continue;
            const n = split(r);
            const also = ((e.dd && e.dd.get(pl)) || []).map(x => codesOnly(split(x)));
            if (inLists([m[0]], also)) continue;
            if (n.length === 1 && n[0] !== m[0]) {
                if (!rrule.has(rk(e.h, m[0]))) rrule.set(rk(e.h, m[0]), new Map());
                rrule.get(rk(e.h, m[0])).set(pl, n[0]);
                for (const [alt, label] of e.a || []) {
                    const al = split(alt);
                    if (label === "" && al.length === 1 && al[0] !== n[0] && !rrule.has(rk(e.h, al[0]))) {
                        rrule.set(rk(e.h, al[0]), new Map([[pl, n[0]]]));
                    }
                }
            }
        }
    }
    const wrule = new Map();     // chars \u0001 codes → Map(place → [codes])
    for (const e of E) {
        if (!("r" in e) || cpLen(e.h) < 2) continue;
        const m = codesOnly(split(e.r));
        if (m.length !== cpLen(e.h)) continue;
        for (const pl of e.dx || []) {
            if (!explicit.has(ek(e.i, pl))) continue;
            const n = codesOnly(split((e.d && e.d.has(pl)) ? e.d.get(pl) : e.r));
            if (inLists(m, ((e.dd && e.dd.get(pl)) || []).map(x => codesOnly(split(x))))) continue;
            if (n.length === m.length) {
                const key = rk(e.h, m.join(" "));
                if (!wrule.has(key)) wrule.set(key, new Map());
                wrule.get(key).set(pl, n);
            }
        }
    }
    function charReadings(ch, codes, pl) {
        for (const e of byHan.get(ch) || []) {
            let own = [codesOnly(split(e.r))].concat((e.a || []).filter(([, l]) => l === "").map(([x]) => codesOnly(split(x))));
            own = own.filter(o => o.length === 1).map(o => o[0]);
            if (!codes.some(c => own.includes(c))) continue;
            const forms = !oneMeaning.has(ek(e.i, pl)) ? (e.sf && e.sf.get(pl)) : null;
            if (forms && forms.length) {
                const out = [];
                for (const f of forms) { const fc = codesOnly(split(f)); if (fc.length === 1 && !out.includes(fc[0])) out.push(fc[0]); }
                if (out.length) return out;
            }
        }
        return null;
    }
    for (const e of E) {
        if (!("r" in e)) continue;
        const toks = split(e.r);
        const codePos = []; toks.forEach((t, i) => { if (parse(lstripCaret(t))) codePos.push(i); });
        const chars = cps(e.h);
        const main = codePos.map(i => lstripCaret(toks[i]));
        const slash = (e.a || []).filter(([x, l]) => l === "" && codesOnly(split(x)).length === main.length).map(([x]) => x);
        for (let pi = 0; pi < PLACES.length; pi++) {
            const pl = String(pi);
            if (explicit.has(ek(e.i, pl))) continue;
            const side = (!slash.length || G1.has(pi)) ? e.r : slash[0];
            const base = split(side);
            const fpos = []; base.forEach((t, i) => { if (parse(lstripCaret(t))) fpos.push(i); });
            const sc = fpos.map(i => lstripCaret(base[i]));
            if (sc.length === chars.length && chars.length === main.length) {
                const local = new Map();
                for (let L = chars.length - 1; L > 1; L--) {
                    for (let st = 0; st < chars.length - L + 1; st++) {
                        let taken = false; for (let n = st; n < st + L; n++) if (local.has(n)) taken = true;
                        if (taken) continue;
                        const r = wrule.get(rk(chars.slice(st, st + L).join(""), main.slice(st, st + L).join(" ")));
                        const w = r && r.get(pl);
                        if (w && w.length === L) for (let j = 0; j < L; j++) local.set(st + j, w[j]);
                    }
                }
                chars.forEach((ch, n) => {
                    if (local.has(n)) return;
                    const rd = chars.length > 1 ? charReadings(ch, [main[n], sc[n]], pl) : null;
                    if (!rd) return;
                    local.set(n, rd.length === 1 ? rd[0] : (rd.includes(sc[n]) ? sc[n] : rd[0]));
                });
                fpos.forEach((i, n) => { if (local.has(n)) base[i] = (base[i].startsWith("^") ? "^" : "") + local.get(n); });
            }
            if (eqList(codesOnly(base), main)) { if (e.d) e.d.delete(pl); continue; }
            mget(e, "d").set(pl, base.join(" "));
        }
    }

    const senseEntry = new Map(), senseOrd = new Map();
    for (const r0 of rows("義項")) {
        const [eid, sid, pos, text] = pad(r0, 4);
        if (!byId.has(eid)) continue;
        const e = byId.get(eid);
        (e.m = e.m || []).push({ p: pos, t: text });
        senseEntry.set(sid, eid); senseOrd.set(sid, e.m.length - 1);
    }
    function template(text) {
        const t = text.normalize("NFD");
        const out = []; let pos = 0, m;
        SYL.lastIndex = 0;
        while ((m = SYL.exec(t)) !== null) {
            out.push(t.slice(pos, m.index).normalize("NFC"));
            pos = m.index + m[0].length;
            const [w, tone, cap] = tlSplit(m[0]);
            const c = tlToCode(w, tone);
            if (c === null) out.push(m[0].normalize("NFC"));
            else out.push("{" + (cap ? "^" : "") + c + "}");
        }
        out.push(t.slice(pos).normalize("NFC"));
        return out.join("");
    }
    for (const r0 of rows("例句")) {
        const [, sid, , han, rom, zh, name] = pad(r0, 7);
        if (!senseEntry.has(sid)) continue;
        const e = byId.get(senseEntry.get(sid));
        const mm = e.m[senseOrd.get(sid)];
        (mm.x = mm.x || []).push([han, template(rom), zh, name]);
    }
    const addLink = (e, key, target, own) => {
        if (target === own) return;
        const l = e[key] || (e[key] = []);
        if (!l.includes(target)) l.push(target);
    };
    for (const [sheet, key] of [["義項tuì義項近義", "sy"], ["義項tuì義項反義", "an"]]) for (const r of rows(sheet)) {
        if (senseEntry.has(r[0]) && senseEntry.has(r[3])) {
            const e = byId.get(senseEntry.get(r[0]));
            addLink(e.m[senseOrd.get(r[0])], key, parseInt(senseEntry.get(r[3]), 10), e.i);
        }
    }
    for (const [sheet, key] of [["義項tuì詞目近義", "sy"], ["義項tuì詞目反義", "an"]]) for (const r of rows(sheet)) {
        if (senseEntry.has(r[0]) && byId.has(r[3])) {
            const e = byId.get(senseEntry.get(r[0]));
            addLink(e.m[senseOrd.get(r[0])], key, parseInt(r[3], 10), e.i);
        }
    }
    for (const [sheet, key] of [["詞目tuì詞目近義", "sy"], ["詞目tuì詞目反義", "an"]]) for (const r of rows(sheet)) {
        if (byId.has(r[0]) && byId.has(r[2])) addLink(byId.get(r[0]), key, parseInt(r[2], 10), byId.get(r[0]).i);
    }
    for (const r of rows("異用字")) {
        if (r.length >= 3 && byId.has(r[0]) && pyStrip(r[2])) (byId.get(r[0]).v = byId.get(r[0]).v || []).push(pyStrip(r[2]));
    }
    const have = new Set(E.map(e => e.h + "\t" + codesOnly(split(e.r || "")).join(" ")));
    let ownId = 900000;
    for (const k of OWN.own || []) {
        const [h, c] = k.split("\t");
        if (have.has(h + "\t" + c)) continue;
        ownId++;
        const e = { i: ownId, h, t: 5, r: c };
        const ds = (OWN.defs || {})[k];
        if (ds && ds.length) e.m = ds.map(t => ({ p: "", t }));
        E.push(e);
    }
    const cmpM = new Map();
    for (const r of rows("詞彙比較")) {
        if (r.length < 5) continue;
        const [, zh, place, han, rom] = r;
        if (!PLACES.includes(place)) continue;
        const item = [PLACES.indexOf(place), han, rstr(reading(rom))];
        if (!cmpM.has(zh)) cmpM.set(zh, []);
        if (!cmpM.get(zh).some(x => x[0] === item[0] && x[1] === item[1] && x[2] === item[2])) cmpM.get(zh).push(item);
    }
    function nameSheet(sheet) {
        const out = new Map();
        for (const r0 of rows(sheet)) {
            const [han, rom, , typ] = pad(r0, 4);
            if (!han || !rom) continue;
            if (!out.has(han)) out.set(han, []);
            out.get(han).push([rstr(reading(rom)), typ]);
        }
        return out;
    }
    const D = { places: PLACES, g1: Array.from(G1).sort((x, y) => x - y), types: TYPES, cats, E,
        cmp: Array.from(cmpM), names: nameSheet("名"), sur: nameSheet("姓") };

    // ═════════════════════ to_app_data.py ═════════════════════
    host.progress(0.45, "整理詞典…");
    const codesOnlyApp = rs => {
        const out = [];
        for (const t of split(rs)) {
            const c = lstripCaret(t);
            if (parse(c)) out.push(c);
            else if (t.startsWith("~")) return null;
        }
        return out.join(" ");
    };
    const needsTokens = rs => split(rs).some(t => !parse(t));
    const groups = new Map();
    for (const e of D.E) {
        const c = "r" in e ? codesOnlyApp(e.r) : null;
        const k = c ? e.h + "\t" + c : null;
        if (k === null) continue;
        if (!groups.has(k)) groups.set(k, []);
        groups.get(k).push(e);
    }
    const mergedInto = new Map();
    for (const [, es] of groups) {
        const base = es[0];
        for (const o of es.slice(1)) {
            mergedInto.set(o.i, base.i);
            if (o.sd) for (const [si, v] of o.sd) mget(base, "sd").set(String(parseInt(si, 10) + (base.m || []).length), v);
            if (o.m && o.m.length) (base.m = base.m || []).push(...o.m);
            for (const c of o.c || []) { const l = base.c || (base.c = []); if (!l.includes(c)) l.push(c); }
            if (o.r !== base.r) (base.a = base.a || []).push([o.r, ""]);
            for (const x of o.a || []) (base.a = base.a || []).push(x);
            if (o.d) for (const [p, r] of o.d) { const d = mget(base, "d"); if (!d.has(p)) d.set(p, r); }
            if (o.dd) for (const [p, xs] of o.dd) { const d = mget(base, "dd"); if (!d.has(p)) d.set(p, xs); }
            for (const p of o.dx || []) {
                // (base["d"].get(p_) == o["d"].get(p_): Python would fail on an entry without "d"; such an entry has no dx)
                const bd = base.d ? base.d.get(p) : undefined, od = o.d ? o.d.get(p) : undefined;
                const dx = base.dx || (base.dx = []);
                if (bd === od && !dx.includes(p)) dx.push(p);
            }
            if (!("au" in base) && "au" in o) base.au = o.au;
            for (const f of ["sy", "an", "v"]) for (const x of o[f] || []) { const l = base[f] || (base[f] = []); if (!l.includes(x)) l.push(x); }
            if (o.g && !base.g) base.g = o.g;
            o._merged = true;
        }
    }
    const words = [], seen = new Set(), keyOf = new Map();
    const defsT = [], defsM = {}, posM = {}, ex = {}, reg = {}, au = {}, alt = {}, dia = {}, tok = {}, subL = [], typ = {}, catM = {}, own = [], dex = {}, dia2 = {};
    const sdia = {};
    const used = new Set();
    for (const e of D.E) {
        if (e._merged) continue;
        if (!("r" in e)) { keyOf.set(e.i, e.h + "\t"); continue; }
        const c = codesOnlyApp(e.r);
        if (!c) { keyOf.set(e.i, e.h + "\t"); continue; }
        const k = e.h + "\t" + c;
        keyOf.set(e.i, k);
        if (seen.has(k)) continue;
        seen.add(k);
        words.push([e.h, c]);
        for (const x of split(c)) used.add(x);
        if (needsTokens(e.r)) tok[k] = e.r;
        if (e.m && e.m.length) {
            const lines = e.m.map(m => m.t);
            const text = lines.length === 1 ? lines[0] : lines.map((t, i) => (i + 1) + ". " + t).join("\n");
            defsM[k] = defsT.length; defsT.push(text);
            if (e.m.some(m => m.p)) posM[k] = e.m.map(m => m.p).join("|");
            if (e.m.some(m => m.x && m.x.length)) {
                ex[k] = e.m.map(m => m.x || []);
                for (const m of e.m) for (const x of m.x || []) for (const mm of x[1].matchAll(/\{\^?([^}]+)\}/g)) used.add(mm[1]);
            }
        }
        if (e.g) reg[k] = e.g;
        if ("au" in e) au[k] = e.au;
        if (e.s) subL.push(k);
        if (e.t !== 0) typ[k] = e.t;
        if (e.t === 5) own.push(k);
        if (e.c && e.c.length) catM[k] = e.c;
        for (const [x, label] of e.a || []) {
            const ac = codesOnlyApp(x);
            if (ac && ac !== c) {
                (alt[k] = alt[k] || []).push([ac, label].concat(needsTokens(x) ? [x] : []));
                for (const y of split(ac)) used.add(y);
            }
        }
        if (e.d) for (const [p, r] of e.d) {
            const rc = codesOnlyApp(r);
            if (rc && rc !== c) {
                (dia[k] = dia[k] || {})[p] = rc;
                for (const y of split(rc)) used.add(y);
                if ((e.dx || []).includes(p)) dex[k] = (dex[k] || "") + p;
            }
        }
        if (e.sd) for (const [si, v] of e.sd) for (const [p, r] of v) {
            const rc = codesOnlyApp(r);
            if (rc && rc !== c) {
                const s1 = sdia[k] || (sdia[k] = {});
                (s1[si] = s1[si] || {})[p] = rc;
                for (const y of split(rc)) used.add(y);
            }
        }
        if (e.dd) for (const [p, xs] of e.dd) {
            const cs = xs.map(codesOnlyApp).filter(x => x);
            if (cs.length) { (dia2[k] = dia2[k] || {})[p] = cs; for (const x of cs) for (const y of split(x)) used.add(y); }
        }
    }
    for (const [o, b] of mergedInto) keyOf.set(o, keyOf.get(b));
    function links(field) {
        const out = {};
        for (const e of D.E) {
            if (e._merged) continue;
            const k = keyOf.get(e.i);
            if (!k || k.endsWith("\t") || (!(k in defsM) && !(field in e) && !(e.m || []).some(m => field in m))) continue;
            const rec = {};
            (e.m || []).forEach((m, i) => {
                const t = (m[field] || []).filter(x => keyOf.has(x)).map(x => keyOf.get(x));
                if (t.length) rec[String(i)] = t;
            });
            const t = (e[field] || []).filter(x => keyOf.has(x)).map(x => keyOf.get(x));
            if (t.length) rec.e = t;
            if (Object.keys(rec).length && !(k in out)) out[k] = rec;
        }
        return out;
    }
    const sy = links("sy"), an = links("an");
    const varM = {};
    for (const e of D.E) {
        const k = keyOf.get(e.i);
        if (!k || k.endsWith("\t")) continue;
        for (const v of e.v || []) { const l = varM[v] || (varM[v] = []); if (!l.includes(k)) l.push(k); }
    }
    const cmp = [];
    for (const [zh, items] of D.cmp) {
        const row = [];
        for (const [p, han, r] of items) {
            const rc = codesOnlyApp(r);
            row.push([p, han, rc || ""]);
            if (rc) for (const y of split(rc)) used.add(y);
        }
        cmp.push([zh, row]);
    }
    function namesOf(src) {
        const out = {};
        for (const [ch, lst] of src) {
            const row = [];
            for (const [r, t] of lst) { const rc = codesOnlyApp(r); if (rc) { row.push([rc, t]); for (const y of split(rc)) used.add(y); } }
            if (row.length) out[ch] = row;
        }
        return out;
    }
    const nm = namesOf(D.names), sr = namesOf(D.sur);
    const HAN = /^[㐀-鿿豈-﫿\u{20000}-\u{3134f}]+$/u;
    function termsOf(text) {
        const out = [];
        for (let t of text.split(/[、，,；;]/)) {
            t = pyStrip(pyStrip(t), "「」『』（）()");
            const n = cpLen(t);
            if (n >= 1 && n <= 6 && HAN.test(t)) out.push(t);
        }
        return out;
    }
    const G = new Map();
    const gput = (k, t, s) => { if (!G.has(k)) G.set(k, new Map()); const g = G.get(k); if (!g.has(t)) g.set(t, s); };
    for (const e of D.E) {
        if (e._merged || !keyOf.has(e.i)) continue;
        const k = keyOf.get(e.i);
        if (k.endsWith("\t") || !seen.has(k)) continue;
        for (const m of e.m || []) {
            const g = m.t.split("。")[0];
            if (cpLen(g) <= 12) for (const t of termsOf(g)) gput(k, t, 1);
            for (const x of m.x || []) {
                const w = x[0], zh = x[2];
                if (HAN.test(w) && cpLen(w) <= 5 && cpLen(zh) <= 6 && HAN.test(zh)) {
                    const xk = w + "\t" + Array.from(x[1].matchAll(/\{\^?([^}]+)\}/g)).map(mm => mm[1]).join(" ");
                    if (seen.has(xk)) gput(xk, zh, 2);
                }
            }
        }
    }
    const gl = new Map();
    for (const [k, v] of G) gl.set(k, Array.from(v).map(([t, s]) => s === 1 ? t : "~" + t).join("|"));
    for (const [zh, row] of cmp) for (const [, han, rc] of row) {
        const k = han + "\t" + rc;
        if (seen.has(k)) {
            const terms = gl.get(k) ? gl.get(k).split("|") : [];
            if (!terms.map(t => t.replace(/^~+/, "")).includes(zh)) terms.push(zh);
            gl.set(k, terms.join("|"));
        }
    }
    function sandhiCodes(c) {
        const p = parse(c);
        if (!p) return [];
        const [, , vow, fin, t] = p;
        const stop = !!vow && !!fin;
        const base = c.slice(0, -1);
        let targets;
        if (t === 4 || t === 8) targets = !stop ? (t === 4 ? [2] : [3]) : (t === 4 ? [8] : [4, 3]);
        else targets = ({ 1: [7], 2: [1, 5], 3: [2], 5: [7, 3], 6: [3], 7: [3] })[t] || [];
        targets = targets.concat(t !== 4 ? (({ 2: [1], 3: [1], 1: [7], 5: [7], 6: [7], 7: [7], 8: [7] })[t] || []) : (stop ? [8] : [7]));
        return targets.map(n => base + n);
    }
    for (const c of Array.from(used)) {
        for (const n of sandhiCodes(c)) {
            try { if (parse(n) && toHaolo(n) && toTl(n) && toPoj(n) && toZhuyin(n)) used.add(n); } catch (err) { }
        }
    }
    const sylT = {};
    const sortedUsed = Array.from(used).sort((x, y) => x < y ? -1 : x > y ? 1 : 0);
    for (const c of sortedUsed) if (parse(c)) sylT[c] = [toZhuyin(c), toHaolo(c)];
    const tl = {}, pj = {};
    for (const c of Object.keys(sylT)) {
        const m = toTl(c);
        tl[c] = [m, m.normalize("NFD").replace(/[̀-ͯ]/g, "") + c.slice(-1)];
    }
    for (const c of Object.keys(sylT)) pj[c] = toPoj(c);
    // reading in context
    const HANC = /[㐀-䶿一-鿿豈-﫿\u{20000}-\u{3134f}〇]/gu;
    const single = new Map();
    for (const [h, c] of words) if (cpLen(h) === 1) { if (!single.has(h)) single.set(h, new Set()); single.get(h).add(c); }
    const amb = new Set(Array.from(single).filter(([, cs]) => cs.size > 1).map(([h]) => h));
    const cu = new Map(), cl = new Map(), cr = new Map();
    const inc = (m, k) => m.set(k, (m.get(k) || 0) + 1);
    for (const senses of Object.values(ex)) for (const xs of senses) for (const x of xs) {
        const hs = x[0].match(HANC) || [];
        const cs = Array.from(x[1].matchAll(/\{\^?([^}]+)\}/g)).map(mm => mm[1]);
        if (hs.length !== cs.length) continue;
        hs.forEach((h, i) => {
            const c = cs[i];
            if (!amb.has(h) || !single.get(h).has(c)) return;
            inc(cu, h + "\t" + c);
            if (i > 0) inc(cl, hs[i - 1] + "\t" + h + "\t" + c);
            if (i + 1 < hs.length) inc(cr, h + "\t" + c + "\t" + hs[i + 1]);
        });
    }
    const ctx = { u: Object.fromEntries(cu), l: Object.fromEntries(cl), r: Object.fromEntries(cr) };
    // how common each character is
    const counts = new Map();
    const essayLines = a.essay ? host.readText(a.essay).split("\n") : [];
    for (const line of essayLines) {
        const p = line.replace(/\n$/, "").split("\t");
        if (p.length >= 2 && cpLen(p[0]) === 1 && isDigits(p[1])) counts.set(p[0], (counts.get(p[0]) || 0) + parseInt(p[1].normalize("NFKC"), 10));
    }
    const charsAll = new Set();
    for (const [h] of words) for (const ch of cps(h)) charsAll.add(ch);
    const freq = {};
    for (const ch of Array.from(charsAll).sort((x, y) => x < y ? -1 : x > y ? 1 : 0)) {
        const n = counts.get(ch) || 0;
        if (n > 0) freq[ch] = round1(Math.log(n));
    }
    const mapObj = m => { const o = {}; for (const [k, v] of m) o[k] = v; return o; };
    const dict = {
        v: 2, words, syl: sylT, tl, pj,
        defs: { t: defsT, m: defsM }, pos: posM, ex, reg, own, au,
        gl: Array.from(gl), freq, dex, ctx, dia2, sdia,
        places: D.places, g1: D.g1, types: D.types, cats: D.cats,
        alt, dia, tok, sub: subL, typ, cat: catM,
        sy, an, var: varM, cmp, names: nm, sur: sr,
    };
    host.progress(0.65, "寫 dict.json…");
    host.writeText(a.outDict || a.out_dict, JSON.stringify(dict));

    // ═════════════════════ build_cards.py ═════════════════════
    host.progress(0.7, "整理詞卡…");
    const freqW = new Map();
    for (const line of essayLines) {
        const p = line.replace(/\n$/, "").split("\t");
        if (p.length >= 2 && isDigits(p[1])) freqW.set(p[0], Math.max(freqW.get(p[0]) || 0, parseInt(p[1].normalize("NFKC"), 10)));
    }
    const SYLT = dict.syl;
    const isCode = t => Object.prototype.hasOwnProperty.call(SYLT, t);
    const upper1 = x => { const c = cps(x); return c.length ? c[0].toUpperCase() + c.slice(1).join("") : x; };
    function syl(c, s, place) {
        if (s === 3) {
            const z = SYLT[c][0];
            return (place !== undefined && place !== null && c.includes("ø") && !(PLACES[place].startsWith("臺南") || PLACES[place].startsWith("高雄"))) ? z.split("ㄜ").join("ㄛ") : z;
        }
        if (s === 1) return dict.tl[c][0];
        if (s === 2) return dict.pj[c];
        return SYLT[c][1];
    }
    function render(tokens, s, place) {
        let out = "", prev = false;
        for (const t of tokens) {
            const cap = t.startsWith("^"), c = cap ? t.slice(1) : t;
            if (isCode(c)) {
                if (s !== 3 && prev) out += "-";
                let x = syl(c, s, place);
                if (cap && s !== 3) x = upper1(x);
                out += x; prev = true;
            } else if (t === "--") { if (s !== 3) out += "--"; prev = false; }
            else if (t === "_") { out += " "; prev = false; }
            else if (t.startsWith("~")) { out += t.slice(1); prev = false; }
            else { out += t; prev = false; }
        }
        return out;
    }
    function tokensFor(k, codes) {
        const cs = split(codes);
        const base = dict.tok[k];
        if (!base) return cs;
        let i = 0; const out = [];
        for (const t of split(base)) {
            const cap = t.startsWith("^"), c = cap ? t.slice(1) : t;
            if (isCode(c)) { out.push((cap ? "^" : "") + (i < cs.length ? cs[i] : c)); i++; }
            else out.push(t);
        }
        return out;
    }
    function forms(k, codes, place) {
        const tk = tokensFor(k, codes);
        return [[0, 1, 2].map(s => render(tk, s, place)), render(tk, 3, place)];
    }
    const TOK = /\{(\^?)([^}]+)\}/g;
    function sent(tpl, s, blank) {
        const toks = Array.from(tpl.matchAll(TOK));
        let res = "", pos = 0;
        toks.forEach((m, idx) => {
            res += tpl.slice(pos, m.index);
            const cap = m[1], c = m[2];
            if (blank && blank[0] <= idx && idx < blank[0] + blank[1]) {
                if (idx === blank[0]) res += "＿＿";
                else res = res.replace(/[-‑]$/, "");
            } else {
                const t = isCode(c) ? syl(c, s) : c;
                res += cap ? upper1(t) : t;
            }
            pos = m.index + m[0].length;
        });
        return res + tpl.slice(pos);
    }
    const BAD_TOPIC = /畫|全部|線|捷運|輕軌|鐵路|機場|縣$|市$|其他$|海港|外交/;
    const RANK = { "白": 0, "俗": 1, "": 2, "文": 3 };
    const TYPE_LABEL = { 1: "臺華共同", 3: "附錄" };
    const EXS = [];
    for (const per of Object.values(dict.ex)) for (const lst of per) for (const [eh, tpl] of lst) {
        EXS.push([eh, Array.from(tpl.matchAll(TOK)).map(mm => mm[2])]);
    }
    const byChar = new Map();
    EXS.forEach(([eh], i) => { for (const ch of new Set(cps(eh))) { if (!byChar.has(ch)) byChar.set(ch, []); byChar.get(ch).push(i); } });
    const findAt = (tc, codes) => {
        const L = codes.length;
        for (let j = 0; j < tc.length - L + 1; j++) { let ok = true; for (let q = 0; q < L; q++) if (tc[j + q] !== codes[q]) { ok = false; break; } if (ok) return j; }
        return null;
    };
    function twCount(h, codes) {
        let n = 0;
        for (const i of byChar.get(cps(h)[0]) || []) {
            const [eh, tc] = EXS[i];
            if (eh.includes(h) && findAt(tc, codes) !== null) n++;
        }
        return n;
    }
    function linkList(keys) {
        return keys.slice(0, 8).map(k => { const [h, c] = k.split("\t"); return [h, c ? forms(k, c)[0][0] : ""]; });
    }
    const topicCount = new Map();
    const cardsOut = [], seenC = new Set();
    words.forEach(([h, c], wi) => {
        if (wi % 2000 === 0) host.progress(0.7 + 0.25 * wi / words.length, "整理詞卡…");
        const k = h + "\t" + c;
        const di = dict.defs.m[k];
        if (di === undefined || seenC.has(k)) return;
        seenC.add(k);
        const codes = split(c).filter(isCode);
        if (!codes.length) return;
        const lines = dict.defs.t[di].split("\n");
        const pos = (dict.pos[k] || "").split("|");
        const exs = dict.ex[k] || [];
        const syk = dict.sy[k] || {}, ank = dict.an[k] || {};
        const defs = lines.map((line, i) => {
            const m = /^(\d+)\.\s*(.*)$/.exec(line);
            const text = m ? m[2] : line;
            const xs = (i < exs.length ? exs[i] : []).map(([eh, tpl, zh, name]) => {
                const x = { h: eh, r: [0, 1, 2].map(s => sent(tpl, s)), z: zh, n: name };
                const tc = Array.from(tpl.matchAll(TOK)).map(mm => mm[2]);
                const at = findAt(tc, codes);
                if (eh.includes(h) && at !== null) {
                    x.bh = eh.replace(h, "＿＿");
                    x.br = [0, 1, 2].map(s => sent(tpl, s, [at, codes.length]));
                }
                return x;
            });
            const dd = { p: i < pos.length ? pos[i] : "", t: text, x: xs };
            if (syk[String(i)]) dd.sy = linkList(syk[String(i)]);
            if (ank[String(i)]) dd.an = linkList(ank[String(i)]);
            return dd;
        });
        const regK = dict.reg[k] || "";
        const [r, z] = forms(k, c);
        const card = { k, h, r, z, c: codes, a: k in dict.au ? dict.au[k] : null, g: regK, d: defs };
        const zo = forms(k, c, 0)[1];
        if (zo !== z) card.zo = zo;
        const v = {};
        for (const [p, dc] of Object.entries(dict.dia[k] || {})) { const [rr, zz] = forms(k, dc, parseInt(p, 10)); v[p] = { r: rr, z: zz }; }
        if (Object.keys(v).length) card.v = v;
        const o = [];
        for (const al of dict.alt[k] || []) {
            const [ac, label] = al;
            const tk = al.length > 2 ? split(al[2]) : split(ac);
            o.push({ l: label || "又", r: [0, 1, 2].map(s => render(tk, s)), z: render(tk, 3) });
        }
        if (o.length) card.o = o;
        if (subL.includes(k)) card.s = 1;
        if (TYPE_LABEL[dict.typ[k]]) card.t = TYPE_LABEL[dict.typ[k]];
        const others = (rec, x) => Object.keys(rec).filter(i => i !== "e").some(i => rec[i].includes(x));
        const ws = (syk.e || []).filter(x => !others(syk, x));
        const wa = (ank.e || []).filter(x => !others(ank, x));
        if (ws.length) card.sy = linkList(ws);
        if (wa.length) card.an = linkList(wa);
        const cs = (dict.cat[k] || []).filter(i => !BAD_TOPIC.test(dict.cats[i]));
        if (cs.length) { card.cats = cs; for (const i of cs) topicCount.set(i, (topicCount.get(i) || 0) + 1); }
        card._t = twCount(h, codes); card._f = freqW.get(h) || 0; card._r = regK in RANK ? RANK[regK] : 2;
        cardsOut.push(card);
    });
    const subSet = null;     // (sub is a list, as in Python)
    cardsOut.forEach((e, i) => { e._i = i; });
    cardsOut.sort((x, y) => (y._t - x._t) || (y._f - x._f) || (x._r - y._r) || (x._i - y._i));
    for (const e of cardsOut) { delete e._t; delete e._f; delete e._r; delete e._i; }
    const toneSyl = {};
    for (const e of cardsOut) {
        const last = e.c[e.c.length - 1];
        if (!parse(last)) continue;
        const base = last.slice(0, -1);
        for (const t of [1, 2, 3, 4, 5, 7, 8]) {
            const cc = base + t;
            if (parse(cc) && !(cc in toneSyl)) {
                try { toneSyl[cc] = [toHaolo(cc), toTl(cc), toPoj(cc)]; } catch (err) { }
            }
        }
    }
    for (const e of cardsOut) for (const x of e.c) if (!(x in toneSyl)) toneSyl[x] = [syl(x, 0), syl(x, 1), syl(x, 2)];
    const topics = Array.from(topicCount).map((x, i) => [x, i]).sort((p, q) => (q[0][1] - p[0][1]) || (p[1] - q[1]))
        .map(x => x[0]).filter(([, n]) => n >= 8).map(([i, n]) => [i, dict.cats[i], n]);
    host.progress(0.97, "寫 cards.json…");
    host.writeText(a.outCards || a.out_cards, JSON.stringify({ v: 2, cards: cardsOut, syl: toneSyl, places: PLACES, topics }));
    host.log(cardsOut.length + " cards, " + words.length + " words");
    return { words: words.length, cards: cardsOut.length };
}
