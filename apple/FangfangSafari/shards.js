// 方方詞卡 查詞: the lookup files (d-*.json) made from the app's data, the same as tools/build_safari.py makes on a
// Mac, but in the browser: the add-on's own 詞典 settings download the dictionaries' original files, the app's
// converters (FangfangCards/Install/*.js) make the app's data from them, and this makes the lookup files from that.
// One language at a time (ffShards.build), then the files that need all of them (ffShards.merge: d-meta.json and the
// English words, d-en-*.json). Runs in a worker (install-worker.js) and with node (tools/check_shards.js).
"use strict";

var ffShards = (() => {
    const SHARDS = 256, MAXLEN = 12;
    const cps = s => Array.from(s || "");
    const cpLen = s => { let n = 0; for (const _ of (s || "")) n++; return n; };

    function short(s, n) {
        n = n || 120;
        s = (s || "").split(/\s+/).filter(Boolean).join(" ");
        const a = cps(s);
        return a.length > n ? a.slice(0, n).join("") + "…" : s;
    }

    // ── 注音 → 拼音 (the same as the app's Zhuyin.pinyin) ──
    const INI = { "ㄅ": "b", "ㄆ": "p", "ㄇ": "m", "ㄈ": "f", "ㄉ": "d", "ㄊ": "t", "ㄋ": "n", "ㄌ": "l", "ㄍ": "g", "ㄎ": "k",
        "ㄏ": "h", "ㄐ": "j", "ㄑ": "q", "ㄒ": "x", "ㄓ": "zh", "ㄔ": "ch", "ㄕ": "sh", "ㄖ": "r", "ㄗ": "z", "ㄘ": "c", "ㄙ": "s" };
    const FIN = { "": "", "ㄚ": "a", "ㄛ": "o", "ㄜ": "e", "ㄝ": "ê", "ㄞ": "ai", "ㄟ": "ei", "ㄠ": "ao", "ㄡ": "ou",
        "ㄢ": "an", "ㄣ": "en", "ㄤ": "ang", "ㄥ": "eng", "ㄦ": "er",
        "ㄧ": "i", "ㄧㄚ": "ia", "ㄧㄛ": "io", "ㄧㄝ": "ie", "ㄧㄞ": "iai", "ㄧㄠ": "iao", "ㄧㄡ": "iu",
        "ㄧㄢ": "ian", "ㄧㄣ": "in", "ㄧㄤ": "iang", "ㄧㄥ": "ing",
        "ㄨ": "u", "ㄨㄚ": "ua", "ㄨㄛ": "uo", "ㄨㄞ": "uai", "ㄨㄟ": "ui", "ㄨㄢ": "uan", "ㄨㄣ": "un",
        "ㄨㄤ": "uang", "ㄨㄥ": "ong",
        "ㄩ": "ü", "ㄩㄝ": "üe", "ㄩㄢ": "üan", "ㄩㄣ": "ün", "ㄩㄥ": "iong" };
    const ALONE = { "i": "yi", "ia": "ya", "io": "yo", "ie": "ye", "iai": "yai", "iao": "yao", "iu": "you", "ian": "yan",
        "in": "yin", "iang": "yang", "ing": "ying", "u": "wu", "ua": "wa", "uo": "wo", "uai": "wai",
        "ui": "wei", "uan": "wan", "un": "wen", "uang": "wang", "ong": "weng", "ü": "yu", "üe": "yue",
        "üan": "yuan", "ün": "yun", "iong": "yong" };
    const MARKS = { "a": "āáǎà", "e": "ēéěè", "i": "īíǐì", "o": "ōóǒò", "u": "ūúǔù", "ü": "ǖǘǚǜ" };
    const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);

    function zyTone(s) {
        if (s.startsWith("˙") || s.endsWith("˙")) return 0;
        return { "ˊ": 2, "ˇ": 3, "ˋ": 4 }[s.slice(-1)] || 1;
    }
    function pinyin(s0) {
        const t = zyTone(s0);
        let s = cps(s0).filter(c => !"ˊˇˋ˙".includes(c)).join("");
        if (!s) return "";
        const er = cpLen(s) > 1 && s.endsWith("ㄦ");
        if (er) s = s.slice(0, -1);
        const first = cps(s)[0];
        const ini = has(INI, first) ? INI[first] : "";
        const rest = ini ? s.slice(first.length) : s;
        if (!has(FIN, rest)) return s0;
        let f = FIN[rest], p;
        if (ini) {
            if (!f) {
                if (!["zh", "ch", "sh", "r", "z", "c", "s"].includes(ini)) return s0;
                f = "i";
            }
            if (["j", "q", "x"].includes(ini)) f = f.split("ü").join("u");
            p = ini + f;
        } else {
            p = has(ALONE, f) ? ALONE[f] : f;
        }
        if (er) p += "r";
        if (![1, 2, 3, 4].includes(t)) return p;
        const a = cps(p);
        let v = a.indexOf("a");
        if (v < 0) v = a.findIndex(c => c === "e" || c === "ê");
        if (v < 0 && p.includes("ou")) v = a.indexOf("o");
        if (v < 0) { for (let i = 0; i < a.length; i++) if ("iouü".includes(a[i])) v = i; }
        if (v < 0) return p;
        const c = a[v];
        const m = c === "ê" ? "ê" + "̄́̌̀"[t - 1] : cps(MARKS[c])[t - 1];
        return (a.slice(0, v).join("") + m + a.slice(v + 1).join("")).normalize("NFC");
    }

    function shardOf(lang, word) {
        const a = cps(word);
        if (lang === "sv" || lang === "eng") return (a[0].codePointAt(0) * 31 + (a.length > 1 ? a[1].codePointAt(0) : 0)) % SHARDS;
        return a[0].codePointAt(0) % SHARDS;
    }
    const pad = i => String(i).padStart(3, "0");

    /// one language's lookup files: data is the app's files it's made from ({zh, zh_sc} 華語, {dict, cards, tw_en}
    /// 台語, {yue} 粵語, {hak} 客語, {sv} 瑞典語); → {files: {name: data}, en: {English: [its words]}, meta: {…}}
    function build(lang, data, log) {
        log = log || (() => {});
        const shards = Array.from({ length: SHARDS }, () => new Map());
        const add = (word, e, most) => {
            if (!word || (lang !== "sv" && lang !== "eng" && cpLen(word) > MAXLEN)) return;
            const d = shards[shardOf(lang, word)];
            if (!d.has(word)) d.set(word, []);
            const lst = d.get(word);
            if (lst.length < (most || 6) && !lst.some(x => x.k === e.k)) lst.push(e);
        };
        // English → this language's words
        const EN = new Map();
        let order = 0;
        const enNorm = t => {
            t = t.replace(/\([^)]*\)|\[[^\]]*\]/g, "").trim().toLowerCase();
            t = t.replace(/^(to|a|an|the) /, "");
            return t.replace(/[.!?…]+$/u, "").trim();
        };
        const enAdd = (h, en) => {
            if (!en || !h) return;
            const seen = new Set();
            en.replace(/^\*+/, "").split(/[;/]/).slice(0, 6).forEach((seg, i) => {
                for (const part of seg.split(",")) {
                    const t = enNorm(part);
                    if (!t || seen.has(t) || cpLen(t) > 30 || t.split(/\s+/).filter(Boolean).length > 3 || !/^[a-z]/.test(t)) continue;
                    seen.add(t);
                    order++;
                    if (!EN.has(t)) EN.set(t, []);
                    EN.get(t).push([i * 2 + (cpLen(h) <= 2 ? 0 : 1), order, h]);
                }
            });
        };
        const files = {}, meta = {};
        const splitEn = n => (n || "").split(";").map(x => x.trim()).filter(Boolean).slice(0, 3).join("; ");

        if (lang === "zh" && data.zh) {
            const zh = data.zh, sc = data.zh_sc || {};
            const zyPy = {};
            let count = 0;
            const S2T = new Map(), TRAD = new Map(), SIMP_OF = new Map(), VARIANT = new Map(), KEEP = new Set(cps("台干"));
            const varLater = [];
            const s2tPair = (h, a) => {
                const ha = cps(h);
                for (const c of ha) TRAD.set(c, (TRAD.get(c) || 0) + 1);
                if (!a || a === h) return;
                const aa = cps(a);
                if (aa.length !== ha.length) return;
                ha.forEach((t, i) => {
                    const c = aa[i];
                    if (t === c) return;
                    if (!S2T.has(c)) S2T.set(c, new Map());
                    const m = S2T.get(c); m.set(t, (m.get(t) || 0) + 1);
                });
            };
            const setDefault = (m, k, v) => { if (!m.has(k)) m.set(k, v); };
            const variantOf = (h, senses, en) => {
                if (cpLen(h) !== 1) return;
                for (const t of senses) {
                    for (const m of t.matchAll(/「(.)」的異體字/gu)) if (m[1] !== h) setDefault(VARIANT, h, m[1]);
                    for (const m of t.matchAll(/「(.)」的簡化字/gu)) if (m[1] !== h) setDefault(SIMP_OF, h, m[1]);
                    const m = /^(?:〈[^〉]*〉)?同「(.)」。?$/u.exec(t);
                    if (m && m[1] !== h) setDefault(VARIANT, h, m[1]);
                }
                for (const m of en.matchAll(/variant of (.)(?:\|.)?\[/gu)) if (m[1] !== h) setDefault(VARIANT, h, m[1]);
            };
            const scRead = new Map();
            for (const [kind, name] of [[2, "p"], [1, "g"], [0, "s"]]) {
                for (const [k, v] of Object.entries(sc[name] || {})) scRead.set(k, [v, kind]);
            }
            const eqs = sc.q || {};
            const zhAdd = (k, h, alt, tw, lu, scr, kind, spec, m, en, eq, f) => {
                const e = { k, t: tw };
                if (f !== undefined && f !== null) e.f = f;
                if (lu) e.l = lu;
                if (scr) { e.s = scr; e.q = kind; }
                if (spec) e.p = spec;
                if (m) e.m = m;
                if (en) e.e = en;
                if (eq && eq.length) e.eq = eq;
                for (const s of [...tw.split(" "), ...(lu || "").split(" ")]) {
                    if (s && s !== "-" && s !== "_" && !has(zyPy, s)) zyPy[s] = pinyin(s);
                }
                add(h, e, 4);
                if (alt && alt !== h) add(alt, e, 4);
                varLater.push([h, e]);
                count++;
            };
            (zh.e || []).forEach((e, zi) => {
                const k = e.k, h = e.h, tw = e.s;
                if (!(k && h && tw)) return;
                s2tPair(h, e.a);
                const senses = (e.d || []).filter(d => d && d[0]).map(d => d[0]);
                variantOf(h, senses, e.n || "");
                let [scr, kind] = scRead.get(k) || [null, 0];
                if (scr && scr.split(" ").length !== tw.split(" ").length) scr = null;
                zhAdd(k, h, e.a, tw, e.l, scr, kind, e.p || 0, short(senses.slice(0, 2).join("　")), splitEn(e.n), eqs[h], zi);
                enAdd(h, e.n);
            });
            // 異體字: each word also under its spelling with a variant character, when that isn't a word of its own
            const std2var = new Map();
            for (const [v, s0] of VARIANT) { if (!std2var.has(s0)) std2var.set(s0, []); std2var.get(s0).push(v); }
            const heads = new Set((zh.e || []).map(e => e.h).filter(Boolean));
            let nvar = 0;
            for (const [vh, ve] of varLater) {
                for (const c of new Set(cps(vh))) {
                    for (const v of (std2var.get(c) || []).slice(0, 3)) {
                        const w = vh.split(c).join(v);
                        if (!heads.has(w)) { add(w, ve, 4); nvar++; }
                    }
                }
            }
            log("華語 異體字 spellings: " + nvar);
            // 四川話's own words
            for (const w of sc.w || []) {
                const h = w.h, s = w.s, z = w.z;
                if (!(h && s && z) || s.split(" ").length !== z.split(" ").length) continue;
                const ms = w.m || [];
                const m = ms.length ? "四川話，意思同「" + ms.slice(0, 3).join("」、「") + "」。" : "四川話的詞。";
                zhAdd(h + "\t" + z + "#川", h, null, z, null, s, w.k !== undefined ? w.k : 2, 3, m, (w.e || []).slice(0, 3).join("; "), ms, null);
            }
            // 簡體 → 繁體
            const strict = [...S2T.keys()].filter(c => !TRAD.get(c));
            const s2t = {};
            for (const [c, ts] of S2T) {
                let n = 0, best = null, bn = -1;
                for (const [t, x] of ts) { n += x; if (x > bn) { best = t; bn = x; } }
                const t = TRAD.get(c) || 0;
                if (!KEEP.has(c) && (t === 0 || (n >= 2 && n >= 4 * t))) s2t[c] = best;
            }
            for (const [c, t] of SIMP_OF) if (!KEEP.has(c) && !has(s2t, c)) s2t[c] = t;
            files["d-s2t.json"] = { m: s2t, s: strict.join("") };
            meta.py = zyPy;
            meta.s2t = Object.keys(s2t).length;
            meta.zh = count;
            // HSK 3.0 (x) and TOCFL (y) levels of the words, for 認識的詞's 「HSK／TOCFL 懂多少」
            const lx = {}, ly = {};
            for (const e of zh.e || []) {
                if (!e.h) continue;
                if (e.x && !(lx[e.h] <= e.x)) lx[e.h] = e.x;
                if (e.y && !(ly[e.h] <= e.y)) ly[e.h] = e.y;
            }
            files["d-levels.json"] = { x: lx, y: ly };
            log("華語 words: " + count);
        }

        if (lang === "tw" && data.dict) {
            const d = data.dict;
            const twEn = (data.tw_en && data.tw_en.e) || {};
            const gl = new Map();
            for (const [k, v] of d.gl || []) gl.set(k, v.split("|").map(t => t.replace(/^~+/, "")).filter(Boolean));
            const defs = d.defs || {}, dm = defs.m || {}, dt = defs.t || [];
            const dia = d.dia || {}, tok = d.tok || {};
            const rank = new Map(((data.cards && data.cards.cards) || []).map((c, i) => [c.k, i]));
            const twEntry = (k, via) => {
                // (the 輕聲 one of a pair, 的\t-- e5: its syllables without the "--"; its spelling is in tok)
                const codes = k.slice(k.indexOf("\t") + 1).split(" ").filter(x => x && x !== "--").join(" ");
                const e = { k, c: codes };
                if (has(dia, k)) e.d = dia[k];
                if (has(tok, k)) e.o = tok[k];
                const g = gl.get(k);
                const m = g && g.length ? g.join("、") : (has(dm, k) && dm[k] < dt.length ? short(dt[dm[k]].split("\n")[0]) : "");
                if (m) e.m = m;
                const en = twEn[k];
                if (en) e.e = en.replace(/^\*+/, "").split("; ").slice(0, 3).join("; ");
                if (via) e.v = via;
                if (rank.has(k)) e.f = rank.get(k);
                return e;
            };
            let count = 0;
            const keys = [];
            for (const [h, codes] of d.words || []) {
                const k = h + "\t" + codes;
                if (!has(dm, k) && !gl.has(k)) continue;
                add(h, twEntry(k)); keys.push(k); count++;
                enAdd(h, twEn[k]);
            }
            // (華語 → 台語: the 台語 words for a 華語 word, the more common first)
            const headOf = k => k.slice(0, k.indexOf("\t"));
            const heads = new Set(keys.map(headOf));
            const byTerm = new Map();
            for (const k of keys) {
                for (const t of gl.get(k) || []) {
                    if (!(heads.has(t) && headOf(k) === t)) { if (!byTerm.has(t)) byTerm.set(t, []); byTerm.get(t).push(k); }
                }
            }
            const rk = k => rank.has(k) ? rank.get(k) : 1e6;
            for (const [t, ks0] of byTerm) {
                const ks = ks0.slice().sort((a, b) => rk(a) - rk(b));
                for (const k of ks.slice(0, heads.has(t) ? 2 : 4)) add(t, twEntry(k, t), 6);
            }
            meta.syl = d.syl || {};
            meta.tl = {};
            for (const [c, v] of Object.entries(d.tl || {})) meta.tl[c] = v[0];
            meta.pj = d.pj || {};
            meta.places = d.places || [];
            meta.tw = count;
            log("台語 words: " + count);
        }

        if ((lang === "yue" || lang === "hak") && data[lang]) {
            const d = data[lang];
            let n = 0;
            (d.e || []).forEach((e, i) => {
                const k = e.k, h = e.h, s = e.s;
                if (!(k && h && s)) return;
                const senses = (e.d || []).filter(x => x && x[0]).map(x => x[0]);
                const o = { k, s, f: i };
                if (e.v) o.a = e.v;
                const m = short(senses.slice(0, 2).join("　"));
                if (m) o.m = m;
                const en = splitEn(e.n);
                if (en && lang !== "yue") o.e = en;
                add(h, o, 4);
                enAdd(h, e.n);
                n++;
            });
            if (lang === "hak") { meta.ht = d.ht || []; meta.hz = d.hz || {}; meta.hacc = d.acc || []; }
            meta[lang] = n;
            log((lang === "yue" ? "粵語" : "客語") + " words: " + n);
        }

        if (lang === "sv" && data.sv) {
            meta.sv = buildSv(data.sv, add);
            log("瑞典語 words: " + meta.sv);
        }

        if (lang === "eng" && data.en) {
            meta.eng = buildEng(data.en, add);
            log("英語 words: " + meta.eng);
        }

        shards.forEach((sh, i) => {
            if (!sh.size) return;
            const o = {};
            for (const [w, l] of sh) o[w] = l;
            files[`d-${lang}-${pad(i)}.json`] = o;
        });
        // (each English word's 3 best words in this language)
        const en = {};
        for (const [t, lst] of EN) {
            lst.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
            const hs = [];
            for (const [, , h] of lst) { if (!hs.includes(h)) hs.push(h); if (hs.length >= 3) break; }
            en[t] = hs;
        }
        return { files, en, meta };
    }

    // ── 英語 (en.json, ECDICT): by the word and each of its forms, in small letters ──
    // each: {k, u: British IPA, a: American IPA, w: its first word class, m: the Chinese meanings ("n. 跑、賽跑；vi. …"),
    // s: the Swedish words, e: the English meanings, f: where it is}
    function buildEng(en, add) {
        let count = 0;
        (en.e || []).forEach((e, i) => {
            const k = e.k, h = e.h;
            if (!(k && h)) return;
            const [uk, us] = (e.s || "").split(" ");
            const o = { k, f: i };
            if (uk && uk !== "-") o.u = uk;
            if (us && us !== "-") o.a = us;
            if (e.w && e.w.length) o.w = e.w[0];
            if (e.jp && e.jp.length) o.m = short(e.jp.slice(0, 3).join("；"), 140);
            if (e.sw && e.sw.length) o.s = e.sw.slice(0, 4).join("、");
            const defs = (e.d || []).map(d => d[0]).filter(Boolean).slice(0, 3).join("; ");
            if (defs) o.e = short(defs, 160);
            for (const w0 of [h, ...(e.m || [])]) {
                const w = (w0 || "").toLowerCase();
                if (w && w.length <= 40) add(w, o, 4);
            }
            count++;
        });
        return count;
    }

    // ── 瑞典語 (sv.json, Folkets lexikon): by the word and each of its forms, in small letters ──
    function buildSv(sv, add) {
        const es = sv.e || [];
        const lower = s => (s || "").toLowerCase();
        const byPlain = new Map();
        es.forEach((e, i) => {
            for (const w of [e.h || "", ...(e.m || [])]) {
                const l = lower(w);
                if (!byPlain.has(l)) byPlain.set(l, []);
                byPlain.get(l).push(i);
            }
        });
        const plain = w => byPlain.get(lower(w)) || [];
        const wset = e => new Set(e.w || []);
        const describes = w => plain(w).some(i => { const s = wset(es[i]); return s.has("形容詞") || s.has("副詞"); });
        const parse = s => {
            const out = [];
            for (const x of (s || "").split(/\s+/).filter(Boolean)) {
                const p = x.split(":");
                if (p.length >= 2 && p[0]) out.push([p[1] === "w" ? " " : p[0], p[1], p.length > 2 ? p[2] : ""]);
            }
            return out;
        };
        const code = m => m[1] === "w" ? "_:w" : m[0] + ":" + m[1] + (m[2] ? ":" + m[2] : "");
        const joined = ms => ms.map(m => m[0]).join("");
        const forForm = (form, lemma, ms) => {
            const low = lower(form);
            ms = ms && ms.length ? ms : [[lemma, "r", ""]];
            const fits = lst => lst.length > 0 && low.startsWith(lower(joined(lst)));
            let use = ms.slice();
            while (use.length && use[use.length - 1][1] === "e") use.pop();
            if (!fits(use) || low === lower(lemma)) use = ms.slice();
            if (!fits(use)) {
                const t = lower(joined(ms));
                let n = 0;
                while (n < t.length && n < low.length && t[n] === low[n]) n++;
                const cut = []; let at = 0;
                for (const m of ms) {
                    if (at >= n) break;
                    const take = Math.min(m[0].length, n - at);
                    cut.push([m[0].slice(0, take), m[1], m[2]]); at += take;
                }
                use = cut;
            }
            const out = []; let at = 0;
            for (const m of use) {
                if (at + m[0].length > form.length) break;
                out.push([form.slice(at, at + m[0].length), m[1], m[2]]); at += m[0].length;
            }
            if (at < form.length) out.push([form.slice(at), "e", ""]);
            return out;
        };
        const wordMorphemes = w => {
            const idx = plain(w).filter(i => !(es[i].h || "").includes(" "));
            if (!idx.length) return [];
            const e = (idx.map(i => es[i]).find(x => lower(x.h) === lower(w))) || es[idx[0]];
            const ms = parse(e.s);
            if (lower(e.h) === lower(w)) {
                if (!ms.length || lower(joined(ms)) !== lower(w)) return [[w, "r", ""]];
            }
            return forForm(w, e.h, ms);
        };
        for (const e of es) {
            const h = e.h || "";
            if (h.includes(" ")) continue;
            const ms = parse(e.s);
            const ws = wset(e);
            const noun = ws.has("名詞") || ws.has("動詞");
            if (ms.length >= 2 && ms[ms.length - 1][1] === "s" && lower(ms[ms.length - 1][0]) === "are" && !noun) {
                const stem = joined(ms.slice(0, -1));
                const root = ms[ms.length - 2][2] || ms[ms.length - 2][0];
                if (ws.has("形容詞") || ws.has("副詞") || describes(stem) || describes(root)) {
                    ms[ms.length - 1][1] = "e";
                    e.s = ms.map(code).join(" ");
                }
            } else if (!ms.length && !noun) {
                for (const end of ["aste", "ast", "are"]) {
                    if (lower(h).endsWith(end) && h.length > end.length + 1 && describes(h.slice(0, -end.length))) {
                        const st = h.slice(0, -end.length);
                        e.s = st + ":r:" + lower(st) + " " + h.slice(-end.length) + ":e";
                        break;
                    }
                }
            }
        }
        const headword = w => plain(w).some(i => lower(es[i].h) === lower(w) && !es[i].h.includes(" "));
        // splits that make two words better: det|s|amma → det|samma, allt|ing → all|ting
        for (const e of es) {
            const ms = parse(e.s);
            if (ms.length < 2) continue;
            let changed = false, j = 0;
            while (j + 1 < ms.length) {
                if (ms[j][1] === "l" && lower(ms[j][0]) === "s" && ms[j + 1][1] === "r" && j > 0 && ms[j + 1][0].length >= 3 && headword("s" + ms[j + 1][0])) {
                    const t = ms[j][0] + ms[j + 1][0];
                    ms[j + 1] = [t, "r", lower(t)];
                    ms.splice(j, 1);
                    changed = true;
                    continue;
                }
                if (ms[j][1] === "r" && ms[j + 1][1] === "s" && ms[j][0].length >= 4 && j + 2 === ms.length) {
                    const x = ms[j][0], sfx = ms[j + 1][0];
                    const a = x.slice(0, -1), w2 = x.slice(-1) + sfx;
                    if (a.length >= 3 && w2.length >= 4 && headword(a) && headword(w2)) {
                        ms[j] = [a, "r", lower(a)];
                        ms[j + 1] = [w2, "r", lower(w2)];
                        changed = true;
                    }
                }
                j++;
            }
            if (changed) e.s = ms.map(code).join(" ");
        }
        // o- that isn't "not"
        const B = "(?<![\\p{L}\\p{N}_])", A = "(?![\\p{L}\\p{N}_])", W = "[\\p{L}\\p{N}_]";
        const NEG = new RegExp(B + "(un|in|im|ir|il|non|dis|mis)" + W + "|" + B + "not" + A + "|" + B + "without" + A + "|" + B + "no" + A + "|" + B + "bad|不|非|無|沒|未|失", "iu");
        const negated = e => NEG.test([e.n || "", ...(e.jp || [])].join(" "));
        const bothWays = w => {
            const hs = plain(w).map(i => es[i]).filter(x => lower(x.h) === lower(w));
            return hs.some(x => !negated(x)) && hs.some(x => negated(x));
        };
        for (const e of es) {
            const ms = parse(e.s);
            if (ms.length < 2 || ms[0][1] !== "p" || lower(ms[0][0]) !== "o" || ms[1][1] !== "r") continue;
            if (!bothWays("o" + ms[1][0]) || negated(e)) continue;
            const t = ms[0][0] + ms[1][0];
            ms[1] = [t, "r", lower(t)];
            ms.splice(0, 1);
            e.s = ms.map(code).join(" ");
        }
        // -ning that's -ing on a verb ending in -n
        const isVerb = w => plain(w).some(i => (es[i].w || []).includes("動詞") && lower(es[i].h) === lower(w));
        for (const e of es) {
            const ms = parse(e.s);
            let changed = false;
            for (let j = 1; j < ms.length; j++) {
                if (ms[j][1] === "s" && lower(ms[j][0]) === "ning" && ms[j - 1][1] === "r" && isVerb(ms[j - 1][0] + "na")) {
                    ms[j - 1] = [ms[j - 1][0] + "n", "r", lower(ms[j - 1][0] + "na")];
                    ms[j] = [ms[j][0].slice(1), "s", ""];
                    changed = true;
                }
            }
            if (changed) e.s = ms.map(code).join(" ");
        }
        // verbs made of a short verb (omhänder|ta)
        const SHORT = [["ta", "tog"], ["dra", "drog"], ["ge", "gav"], ["be", "bad"], ["gå", "gick"], ["se", "såg"], ["få", "fick"],
            ["stå", "stod"], ["slå", "slog"], ["dö", "dog"], ["le", "log"]];
        const PREFIXES = ["miss", "sam", "sär", "van", "åter", "över", "under", "efter", "före", "fram", "till", "upp", "ut",
            "in", "an", "av", "be", "bi", "er", "för", "ge", "mot", "med", "om", "o", "ur", "all", "icke", "anti",
            "super", "mini", "multi", "inter", "ex", "re", "pre", "post", "sub", "trans"].sort((a, b) => b.length - a.length);
        for (const e of es) {
            const h = e.h || "";
            if (h.includes(" ") || !(e.w || []).includes("動詞")) continue;
            const ms = parse(e.s);
            if (ms.length && ms[ms.length - 1][1] !== "e") continue;
            const low = lower(h);
            const forms = (e.m || []).map(f => lower(f).split("|").join(""));
            for (const [v, past] of SHORT) {
                if (!(low.endsWith(v) && low.length > v.length + 1)) continue;
                const front = h.slice(0, -v.length);
                if (!forms.includes(lower(front) + past)) continue;
                let pm = wordMorphemes(front);
                if (!pm.length) {
                    const fl = lower(front);
                    const p = PREFIXES.find(x => fl.startsWith(x) && fl.length - x.length >= 3 && (byPlain.get(fl.slice(x.length)) || []).length);
                    pm = p ? [[front.slice(0, p.length), "p", ""], [front.slice(p.length), "r", ""]] : [[front, "r", ""]];
                }
                e.s = [...pm, [h.slice(-v.length), "r", v]].map(code).join(" ");
                break;
            }
        }
        for (const e of es) {
            const h = e.h || "";
            if (h.includes(" ") && !parse(e.s).length) {
                const out = [];
                h.split(" ").forEach((w, j) => {
                    if (j) out.push([" ", "w", ""]);
                    const wm = wordMorphemes(w);
                    out.push(...(wm.length ? wm : [[w, "r", ""]]));
                });
                e.s = out.map(code).join(" ");
            }
        }
        const byWord = new Map();
        for (const e of es) { const l = lower(e.h); if (!byWord.has(l)) byWord.set(l, []); byWord.get(l).push(e); }
        const real = e => (e.jp || []).filter(x => !x.startsWith("≈"));
        const guessed = e => (e.jp || []).filter(x => x.startsWith("≈")).map(x => x.slice(1));
        const svGloss = e => real(e).length ? real(e)[0] : (guessed(e).length ? "≈" + guessed(e)[0] : short((e.n || "").split(";")[0].trim(), 30));
        let count = 0;
        es.forEach((e, i) => {
            const k = e.k, h = e.h;
            if (!(k && h)) return;
            const o = { k, s: e.s || "", f: i };
            if (e.w && e.w.length) o.w = e.w[0];
            if (real(e).length) o.m = real(e).slice(0, 4).join("、");
            else if (guessed(e).length) o.q = guessed(e).slice(0, 3).join("、");
            const en = (e.n || "").split(";").map(x => x.trim()).filter(Boolean).slice(0, 3).join("; ");
            if (en) o.e = short(en, 100);
            const g = {};
            (e.s || "").split(/\s+/).filter(Boolean).forEach((m, j) => {
                const p = m.split(":");
                if (p.length >= 2 && p[1] === "r") {
                    const lw = lower(p.length > 2 ? p[2] : p[0]);
                    const gs = [];
                    for (const r of byWord.get(lw) || []) {
                        if (r.k === k) continue;
                        const t = svGloss(r);
                        if (t && !gs.includes(t)) gs.push(t);
                    }
                    if (gs.length) g[String(j)] = gs.slice(0, 2).join("／");
                }
            });
            if (Object.keys(g).length) o.g = g;
            for (const w0 of [h, ...(e.m || [])]) {
                const w = lower(w0);
                if (w && w.length <= 40) add(w, o, 4);
            }
            count++;
        });
        return count;
    }

    /// the files that need every language: d-meta.json (the spelling tables and how many words each has) and the
    /// English words (d-en-*.json); parts: {lang: build(…)'s en and meta}
    function merge(parts) {
        const meta = { v: 1, shards: SHARDS, max: MAXLEN, py: {} };
        for (const l of ["zh", "tw", "yue", "hak", "sv", "eng"]) meta[l] = 0;
        const EN = new Map();
        for (const [lang, p] of Object.entries(parts)) {
            if (!p) continue;
            Object.assign(meta, p.meta || {});
            for (const [t, hs] of Object.entries(p.en || {})) {
                if (!EN.has(t)) EN.set(t, {});
                EN.get(t)[lang] = hs;
            }
        }
        if (!meta.s2t) meta.s2t = 0;
        // (English words are looked up with 英語's own dictionary now: no English → Chinese files)
        meta.en = 0;
        const files = {};
        files["d-meta.json"] = meta;
        return files;
    }

    return { build, merge, pinyin, SHARDS };
})();
if (typeof module !== "undefined") module.exports = ffShards;
