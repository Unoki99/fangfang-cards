// 英語: ECDICT (English–Chinese, skywind3000/ECDICT, MIT) → en.json, with the American readings from CMUdict (BSD),
// the Swedish words from Folkets lexikon the other way round (Swedish–English, KTH, CC BY-SA 2.5; its example
// sentences too), and the Chinese meanings in 正體 (CC-CEDICT's pairs, CC BY-SA). Downloaded and made on the device,
// like the other dictionaries.
//   buildEnglish({ecdict: ecdict.csv, cmu: cmudict.dict | null, folkets: folkets_sv_en_public.xml | null,
//                 svfreq: sv_50k.txt | null, cedict: cedict_ts.u8 | null, out: en.json})
//
// en.json has the same shape as sv.json ("lang": "en"), so 英語 uses the same pages:
//   head: {v, lang: "en", nc: how many are study cards (the common words, first), c: [], tags: {}}
//   one entry a line: {k: "run\t英", h: "run", s: "rʌn rʌn" (the British reading, the American one; "-" when there
//     isn't one), d: [[English meaning, [[example, its Swedish]…]]…], n: every English meaning ("; "), w: word
//     classes (中文), m: the forms (ran, running, runs), jp: the Chinese meanings ("n. 跑、賽跑" a line), sw: the
//     Swedish words, g: the group of how common (500 a group), x: Collins level (1 = ★★★★★ … 5 = ★), y: the first exam list it's on (1 中考 2 高考 3 CET-4
//     4 CET-6 5 考研 6 TOEFL / IELTS 7 GRE), o: 1 on the Oxford 3000, r: how common (its rank, 0 = not known)
"use strict";

const EN_CLASS = {
    "n": "名詞", "v": "動詞", "vt": "動詞", "vi": "動詞", "a": "形容詞", "adj": "形容詞", "s": "形容詞", "ad": "副詞",
    "adv": "副詞", "r": "副詞", "prep": "介詞", "conj": "連詞", "pron": "代名詞", "int": "感嘆詞", "interj": "感嘆詞",
    "num": "數詞", "art": "冠詞", "aux": "助動詞", "abbr": "縮寫", "pref": "前綴", "suf": "後綴",
};
const EN_EXAMS = [["zk", 1], ["gk", 2], ["cet4", 3], ["cet6", 4], ["ky", 5], ["toefl", 6], ["ielts", 6], ["gre", 7]];

/// one line of ECDICT's CSV (fields in "", "" inside them; \n written as the two letters)
function enCsv(line) {
    const out = [];
    let i = 0, cur = "", q = false;
    for (; i < line.length; i++) {
        const c = line[i];
        if (q) {
            if (c === '"') { if (line[i + 1] === '"') { cur += '"'; i++; } else q = false; }
            else cur += c;
        } else if (c === '"') q = true;
        else if (c === ",") { out.push(cur); cur = ""; }
        else cur += c;
    }
    out.push(cur);
    return out;
}

/// ECDICT's reading (British, mostly) in IPA as dictionaries write it: ' → ˈ, , → ˌ, : → ː
function enIpaUk(p) {
    if (!p) return "";
    return p.replace(/ә/g, "ə").replace(/'/g, "ˈ").replace(/,/g, "ˌ").replace(/:/g, "ː").replace(/ɡ/g, "ɡ").replace(/\s+/g, "").trim();
}

const ARPA = {
    AA: "ɑ", AE: "æ", AH: "ʌ", AO: "ɔ", AW: "aʊ", AY: "aɪ", EH: "ɛ", ER: "ɝ", EY: "eɪ", IH: "ɪ", IY: "i", OW: "oʊ",
    OY: "ɔɪ", UH: "ʊ", UW: "u", B: "b", CH: "tʃ", D: "d", DH: "ð", F: "f", G: "ɡ", HH: "h", JH: "dʒ", K: "k", L: "l",
    M: "m", N: "n", NG: "ŋ", P: "p", R: "ɹ", S: "s", SH: "ʃ", T: "t", TH: "θ", V: "v", W: "w", Y: "j", Z: "z", ZH: "ʒ",
};
/// CMUdict's phones → American IPA, the stress mark before the consonants that start the stressed syllable
function enIpaUs(phones) {
    const toks = [];
    for (const p of phones.trim().split(/\s+/)) {
        const m = /^([A-Z]+)([012])?$/.exec(p);
        if (!m || ARPA[m[1]] === undefined) continue;
        let t = ARPA[m[1]];
        // (unstressed ʌ and ɝ are ə and ɚ)
        if (m[2] === "0" && m[1] === "AH") t = "ə";
        if (m[2] === "0" && m[1] === "ER") t = "ɚ";
        toks.push({ t, v: m[2] !== undefined, s: m[2] });
    }
    const vowels = toks.filter(x => x.v).length;
    const onset2 = /^(s[ptkmnlw]|[pbtdkɡfθʃ][ɹlw]|[ptkbdɡmnfvθszʃh]j)$/;
    let out = "";
    for (let i = 0; i < toks.length; i++) {
        out += toks[i].t;
        // (the mark goes before the next stressed vowel's consonants: all of them at the start of the word, else the
        // last one or the last two when they can start a syllable, "st", "pl", "tɹ")
        const nx = toks.slice(i + 1);
        const vi = nx.findIndex(x => x.v);
        if (vi < 0 || !(nx[vi].s === "1" || nx[vi].s === "2") || vowels < 2) continue;
        // (the word's first vowel: its mark goes at the very start, below)
        if (!toks.slice(0, i + 1).some(x => x.v)) continue;
        const run = nx.slice(0, vi).map(x => x.t);
        const take = run.length <= 1 ? run.length : (onset2.test(run.slice(-2).join("")) ? 2 : 1);
        const mark = nx[vi].s === "1" ? "ˈ" : "ˌ";
        out += run.slice(0, run.length - take).join("") + mark + run.slice(run.length - take).join("") + nx[vi].t;
        i += vi + 1;
    }
    // (a stressed first syllable: its mark at the very start)
    if (vowels >= 2) {
        const fv = toks.findIndex(x => x.v);
        if (fv >= 0 && (toks[fv].s === "1" || toks[fv].s === "2")) out = (toks[fv].s === "1" ? "ˈ" : "ˌ") + out;
    }
    return out;
}

function enCmu(path) {
    const out = new Map();
    if (!path) return out;
    host.readLines(path, line => {
        if (!line || line.startsWith(";;;")) return;
        const sp = line.indexOf(" ");
        if (sp < 0) return;
        const w = line.slice(0, sp);
        if (w.indexOf("(") >= 0) return;
        const ph = line.slice(sp + 1).replace(/#.*$/, "");
        if (!out.has(w)) out.set(w, enIpaUs(ph));
    });
    return out;
}

/// 簡體 → 正體 with CC-CEDICT's pairs: whole words first (the longest that fits), else one character at a time, and
/// a character only when it isn't a 正體 character of its own in more words (法 stays 法)
function enTraditional(path) {
    const words = new Map(), votes = new Map(), kept = new Map();
    if (path) host.readLines(path, line => {
        if (!line || line[0] === "#") return;
        const m = /^(\S+) (\S+) \[/.exec(line);
        if (!m) return;
        const t = Array.from(m[1]), s = Array.from(m[2]);
        if (t.length !== s.length) return;
        if (m[1] !== m[2] && t.length > 1 && t.length <= 4 && !words.has(m[2])) words.set(m[2], m[1]);
        for (let i = 0; i < t.length; i++) {
            if (t[i] === s[i]) { kept.set(s[i], (kept.get(s[i]) || 0) + 1); continue; }
            const v = votes.get(s[i]) || new Map();
            v.set(t[i], (v.get(t[i]) || 0) + 1);
            votes.set(s[i], v);
        }
    });
    const chars = new Map();
    for (const [s, v] of votes) {
        let best = null, n = 0;
        for (const [t, c] of v) if (c > n) { best = t; n = c; }
        if (best && n > (kept.get(s) || 0)) chars.set(s, best);
    }
    return text => {
        const cs = Array.from(text);
        let out = "";
        for (let i = 0; i < cs.length;) {
            let done = false;
            for (let len = Math.min(4, cs.length - i); len >= 2; len--) {
                const w = words.get(cs.slice(i, i + len).join(""));
                if (w) { out += w; i += len; done = true; break; }
            }
            if (done) continue;
            out += chars.get(cs[i]) || cs[i];
            i++;
        }
        return out;
    };
}

/// Folkets lexikon the other way round: English word → its Swedish words (the most common Swedish first), and
/// English example sentences with their Swedish
function enFolkets(path) {
    const sv = new Map(), ex = new Map();
    if (!path) return { sv, ex };
    const xml = host.readText(path);
    let p = 0, order = 0;
    const attr = t => { const o = {}; for (const m of t.matchAll(/(\w+)="([^"]*)"/g)) o[m[1]] = decodeEntities(decodeEntities(m[2])).trim(); return o; };
    for (;;) {
        const a = xml.indexOf("<word ", p);
        if (a < 0) break;
        const ae = xml.indexOf(">", a), b = xml.indexOf("</word>", ae);
        if (ae < 0 || b < 0) break;
        const at = attr(xml.slice(a, ae));
        let body = xml.slice(ae + 1, b);
        p = b + 7;
        order++;
        const word = (at.value || "").replace(/\|/g, "");
        if (!word || at.class === "prefix" || at.class === "suffix") continue;
        // examples: [Swedish, English]
        for (const m of body.matchAll(/<example\s+([^>]*?)>([\s\S]*?)<\/example>/g)) {
            const v = attr(m[1]).value, t = /<translation\s+([^>]*?)\/?>/.exec(m[2]);
            const en = t ? attr(t[1]).value : "";
            if (!v || !en) continue;
            for (const w of unique(en.toLowerCase().match(/[a-z']+/g) || [])) {
                const list = ex.get(w) || [];
                if (list.length < 40 && !list.some(x => x[0] === en)) { list.push([en, v]); ex.set(w, list); }
            }
        }
        body = body.replace(/<(example|idiom|definition|explanation|compound|derivation|related|variant)\b[^>]*?\/>/g, "")
                   .replace(/<(example|idiom|definition|explanation|compound|derivation|related|variant)\b[\s\S]*?<\/\1>/g, "");
        for (const m of body.matchAll(/<translation\s+([^>]*?)\/?>/g)) {
            let t = (attr(m[1]).value || "").toLowerCase().replace(/\([^)]*\)/g, "").trim();
            if (at.class === "vb") t = t.replace(/^to /, "");
            t = t.replace(/^(a|an|the) /, "").trim();
            if (!t || t.length > 30) continue;
            const list = sv.get(t) || [];
            if (!list.some(x => x[0] === word)) { list.push([word, order]); sv.set(t, list); }
        }
    }
    return { sv, ex };
}

/// ECDICT's lines ("n. 跑, 賽跑\nvi. 跑"): the class and the text of each. A line without a class goes on from the
/// one before (the older definitions are wrapped at the end of a line)
const EN_SHOWN = { a: "adj", s: "adj", r: "adv", ad: "adv", int: "interj" };
function enLines(s) {
    const out = [];
    for (const l0 of s.split("\\n")) {
        const l = l0.trim();
        if (!l) continue;
        const m = /^([a-z]+)\.?\s+(.*)$/.exec(l);
        if (m && EN_CLASS[m[1]]) out.push({ c: EN_SHOWN[m[1]] || m[1], cls: m[1], t: m[2].trim() });
        else if (out.length && /^[a-z(]/.test(l)) out[out.length - 1].t += " " + l;
        else out.push({ c: "", cls: "", t: l });
    }
    // (cross-references of the older definitions: "v. i. See Thee.")
    return out.filter(x => !/^([a-z]\.\s*)*See\s/.test(x.t));
}

function buildEnglish(a) {
    host.progress(0.05, "讀 CMUdict…");
    const cmu = enCmu(a.cmu);
    host.log("CMUdict: " + cmu.size + " words");
    host.progress(0.15, "讀 Folkets lexikon…");
    const folk = enFolkets(a.folkets);
    host.log("Folkets lexikon (the other way round): " + folk.sv.size + " English words");
    // how common the Swedish words are (FrequencyWords), so the most common comes first
    const svFreq = new Map();
    if (a.svfreq) { let i = 0; host.readLines(a.svfreq, l => { const w = l.split(" ")[0]; if (w && !svFreq.has(w)) svFreq.set(w, ++i); }); }
    host.progress(0.3, "正體字…");
    const trad = enTraditional(a.cedict);
    host.progress(0.4, "讀 ECDICT…");
    if (!a.ecdict) throw new Error("ECDICT wasn't downloaded");
    const entries = [];
    let head = null;
    host.readLines(a.ecdict, line => {
        if (!line) return;
        const f = enCsv(line);
        if (!head) { head = f; return; }
        const r = {};
        for (let i = 0; i < head.length; i++) r[head[i]] = f[i] || "";
        const w = r.word;
        if (!/^[A-Za-z][A-Za-z' -]*$/.test(w) || !r.translation) return;
        const frq = parseInt(r.frq, 10) || 0, bnc = parseInt(r.bnc, 10) || 0;
        const tags = r.tag ? r.tag.split(" ") : [];
        if (!((frq > 0 && frq <= 60000) || (bnc > 0 && bnc <= 60000) || r.collins || r.oxford === "1" || tags.length)) return;
        // (names and the like, marked [人名] or only capitalised: kept only when common)
        if (/^\[(人名|地名|姓氏)\]/.test(r.translation) && !(frq > 0 && frq <= 20000)) return;
        entries.push({ r, w, frq, bnc, tags });
    });
    host.log("ECDICT: " + entries.length + " words");
    host.progress(0.7, "整理…");
    const out = [];
    const keys = new Set();
    for (const { r, w, frq, bnc, tags } of entries) {
        let k = w + "\t英";
        while (keys.has(k)) k += "＊";
        keys.add(k);
        const low = w.toLowerCase();
        const en = enLines(r.definition).filter(x => x.t && !/^See\s/.test(x.t));
        const zh = enLines(r.translation).filter(x => x.t && !/^\[网络\]/.test(x.t)
            && !/的(过去式|过去分词|现在分词|复数|第三人称单数|比较级|最高级)/.test(x.t));
        const cls = unique(en.concat(zh).map(x => EN_CLASS[x.cls]).filter(Boolean));
        // (Folkets lexikon's sentences with the word; for a common word, which is in many sentences, only the ones
        // whose Swedish has one of its Swedish words)
        const svw = (folk.sv.get(low) || []).map(x => x[0].toLowerCase().slice(0, Math.max(3, x[0].length - 2)));
        const exs = (folk.ex.get(low) || []).filter(x => !(frq && frq <= 3000) || svw.some(t => x[1].toLowerCase().indexOf(t) >= 0));
        const d = en.length ? en.slice(0, 8).map((x, i) => [(x.c ? x.c + ". " : "") + x.t, i === 0 ? exs.slice(0, 4) : []])
            : [["", exs.slice(0, 4)]];
        const o = { k, h: w, s: (enIpaUk(r.phonetic) || "-") + " " + (cmu.get(low) || "-"), d,
                    n: en.map(x => x.t).join("; ") };
        if (cls.length) o.w = cls;
        const jp = zh.map(x => (x.c ? x.c + ". " : "") + trad(x.t).replace(/,\s*/g, "、")).slice(0, 8);
        if (jp.length) o.jp = jp;
        // the forms: p past, d past participle, i -ing, 3 third person, s plural, r comparative, t superlative
        const forms = [];
        for (const part of (r.exchange || "").split("/")) {
            const m = /^([pdi3srt]):(.+)$/.exec(part);
            if (m && m[2] !== w && forms.indexOf(m[2]) < 0) forms.push(m[2]);
        }
        if (forms.length) o.m = forms;
        // the Swedish words: the English word's own (and, for a verb, "to …")
        const svRank = x => svFreq.get(x[0].toLowerCase()) || 1e6 + x[1];
        const sw = (folk.sv.get(low) || []).slice().sort((x, y) => svRank(x) - svRank(y)).map(x => x[0]);
        if (sw.length) o.sw = unique(sw).slice(0, 6);
        const col = parseInt(r.collins, 10) || 0;
        if (col) o.x = 6 - col;
        let exam = 0;
        for (const [t, l] of EN_EXAMS) if (tags.indexOf(t) >= 0 && (!exam || l < exam)) exam = l;
        if (exam) o.y = exam;
        if (r.oxford === "1") o.o = 1;
        // how common: COCA's rank, else the British National Corpus's
        o._r = frq || bnc || 0;
        out.push(o);
    }
    // the common words first (by how common), then the rest
    const ranked = out.filter(e => e._r > 0 && e._r <= 30000).sort((x, y) => x._r - y._r);
    const rest = out.filter(e => !(e._r > 0 && e._r <= 30000)).sort((x, y) => (x.x || 9) - (y.x || 9) || (x.y || 9) - (y.y || 9));
    // (the common words in groups of 500, the same as the other languages' 常用詞)
    ranked.forEach((e, i) => { e.g = Math.floor(i / 500) + 1; });
    const outEntries = ranked.concat(rest).map(e => { if (e._r) e.r = e._r; delete e._r; return e; });
    const headOut = { v: 1, lang: "en", nc: ranked.length, c: [], tags: {} };
    host.progress(0.95, "寫入…");
    host.writeText(a.out, dumps(headOut).slice(0, -1) + ',"e":[\n' + outEntries.map(dumps).join(",\n") + "\n]}");
    host.log("en.json: " + outEntries.length + " entries, " + ranked.length + " common");
}
