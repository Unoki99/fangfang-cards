// 瑞典語: Folkets lexikon (Swedish–English, KTH, CC BY-SA 2.5) → sv.json, with each word's morphemes (詞素) worked
// out here, how common the words are (FrequencyWords, OpenSubtitles 2018, CC BY-SA 4.0) and, when it can be had, the
// Chinese meanings from the Chinese Wiktionary (as extracted by kaikki.org, CC BY-SA). Downloaded and made on the
// device, like the other dictionaries.
//   buildSwedish({folkets: folkets_sv_en_public.xml, folkets2: (the same, from a copy on GitHub) | null,
//                 freq: sv_50k.txt | null, zhwikt: kaikki.org-dictionary-瑞典語.jsonl | null, out: sv.json})
//
// sv.json has the same shape as zh.json ("lang": "sv"), so 瑞典語 uses the same pages:
//   head: {v, lang: "sv", nc: how many are study cards (the common words, first), c: [], tags: {}}
//   one entry a line: {k: "läsa\t瑞vb", h: "läsa", s: the morphemes ("läs:r a:e"), d: [[meaning (English),
//     [[example, its English]…]]…], n: every meaning ("; "), w: word class (中文), m: the inflected forms
//     (läste, läst, läs, läsa, läser), j: synonyms, jp: the Chinese meanings, x = y: group of 500 (common words)}
//
// The morphemes: "text:kind[:word]", kind r 詞根 (root), p 前綴 (prefix), s 後綴 (suffix), l 連接音 (the linking
// s / e / a / u / o of a compound), e 詞尾 (the verb's -a); word: the dictionary word a root is (arbet → arbete).
// Folkets lexikon marks where a compound is put together ("arbetslös|het"); each part is taken apart again (its own
// mark, or a prefix / suffix of the list below, when what's left is a word of the dictionary).
"use strict";

const SV_CLASS = {
    nn: "名詞", vb: "動詞", jj: "形容詞", ab: "副詞", pn: "代名詞", pp: "介詞", kn: "連詞", sn: "從屬連詞",
    in: "感嘆詞", rg: "數詞", ro: "序數詞", pm: "專有名詞", abbrev: "縮寫", prefix: "前綴", suffix: "後綴",
    hp: "疑問詞", ie: "不定式標記", ps: "物主代名詞", article: "冠詞",
};

// (longest first, so "lighet" is tried before "het")
const SV_SUFFIXES = ["mässig", "aktig", "else", "skap", "ning", "ande", "ende", "ering", "itet",
    "inna", "tion", "sion", "full", "het", "dom", "isk", "bar", "sam", "lös", "fri", "vis", "lig", "are", "eri", "ism",
    "ist", "nad", "era", "ska", "ing", "ör", "ig"].sort((a, b) => b.length - a.length);
const SV_PREFIXES = ["miss", "sam", "sär", "van", "åter", "över", "under", "efter", "före", "fram", "till", "upp", "ut",
    "in", "an", "av", "be", "bi", "er", "för", "ge", "mot", "med", "om", "o", "ur", "all", "icke", "anti", "super",
    "mini", "multi", "inter", "ex", "re", "pre", "post", "sub", "trans"].sort((a, b) => b.length - a.length);
const SV_LINKS = ["s", "e", "a", "u", "o"];
// suffixes that make a word of a verb (läs-are, mät-ning): the verb is tried first (men-ing is mena's, not men's)
const SV_VERBAL = ["ing", "ning", "are", "bar", "ande", "ende", "else", "nad", "eri", "ande"];
const SV_VOWEL = /[aeiouyåäöé]/;

function svXmlAttr(tag) {
    const o = {};
    for (const m of tag.matchAll(/(\w+)="([^"]*)"/g)) o[m[1]] = svText(m[2]);
    return o;
}
// (Folkets lexikon escapes some things twice: &amp;quot;)
function svText(s) { return decodeEntities(decodeEntities(s)).trim(); }

/// the <word>s of Folkets lexikon: [{value (with |), cls, comment, tr: [English], ex: [[sv, en]], inf: [forms],
/// syn: [words], def: English of the definition}]
function svWords(xml) {
    const out = [];
    let p = 0;
    for (;;) {
        const a = xml.indexOf("<word ", p);
        if (a < 0) break;
        const ae = xml.indexOf(">", a);
        const b = xml.indexOf("</word>", ae);
        if (ae < 0 || b < 0) break;
        const at = svXmlAttr(xml.slice(a, ae));
        let body = xml.slice(ae + 1, b);
        p = b + 7;
        const ex = [];
        // examples and idioms: the Swedish and its English
        for (const m of body.matchAll(/<(example|idiom)\s+([^>]*?)(\/?)>([\s\S]*?)(?:<\/\1>|$)/g)) {
            if (m[3] === "/") { const v = svXmlAttr(m[2]).value; if (v) ex.push([v, ""]); continue; }
            const v = svXmlAttr(m[2]).value;
            const t = /<translation\s+([^>]*?)\/?>/.exec(m[4]);
            if (v) ex.push([v, t ? (svXmlAttr(t[1]).value || "") : ""]);
        }
        let def = "";
        const dm = /<definition\s+[^>]*?>\s*<translation\s+([^>]*?)\/?>/.exec(body);
        if (dm) def = svXmlAttr(dm[1]).value || "";
        // (what's inside the other elements isn't the word's own translation)
        body = body.replace(/<(example|idiom|definition|explanation|compound|derivation|related|variant)\b[^>]*?\/>/g, "")
                   .replace(/<(example|idiom|definition|explanation|compound|derivation|related|variant)\b[\s\S]*?<\/\1>/g, "");
        const tr = [];
        for (const m of body.matchAll(/<translation\s+([^>]*?)\/?>/g)) { const v = svXmlAttr(m[1]).value; if (v) tr.push(v); }
        const inf = [];
        for (const m of body.matchAll(/<inflection\s+([^>]*?)\/?>/g)) { const v = svXmlAttr(m[1]).value; if (v) inf.push(v); }
        const syn = [];
        for (const m of body.matchAll(/<synonym\s+([^>]*?)\/?>/g)) { const v = svXmlAttr(m[1]).value; if (v) syn.push(v); }
        if (!at.value) continue;
        out.push({ value: at.value, cls: at.class || "", comment: at.comment || "", tr, ex, inf, syn, def });
    }
    return out;
}

/// the morphemes of every word: [[text, kind, word]…] (null: one piece)
function svMorphemes(words) {
    const known = new Set(), marks = new Map(), verbs = new Set();
    for (const w of words) {
        if (w.cls === "prefix" || w.cls === "suffix") continue;
        const plain = w.value.replace(/\|/g, "").toLowerCase();
        if (plain.length >= 2 && !/[\s\-.,]/.test(plain)) known.add(plain);
        if (w.cls === "vb") verbs.add(plain);
        if (w.value.indexOf("|") > 0 && !marks.has(plain)) marks.set(plain, w.value.toLowerCase().split("|").filter(x => x));
    }
    const isWord = x => x.length >= 2 && known.has(x);

    function seg(w, depth) {
        if (depth > 5) return [[w, "r", isWord(w) ? w : ""]];
        const parts = marks.get(w);
        if (parts && parts.length > 1) {
            const out = [];
            parts.forEach((p, i) => {
                const last = i === parts.length - 1;
                // (lös, full, fri, het, ut, över… are words too, but at the end / start of a word they're its suffix / prefix)
                if (last && i > 0 && SV_SUFFIXES.indexOf(p) >= 0) { out.push([p, "s", ""]); return; }
                if (i === 0 && !last && SV_PREFIXES.indexOf(p) >= 0) { out.push([p, "p", ""]); return; }
                for (const x of part(p, last, depth)) out.push(x);
            });
            return out;
        }
        return affixes(w, depth) || compound(w, depth) || [[w, "r", isWord(w) ? w : ""]];
    }
    // a compound Folkets lexikon didn't mark: two words of the dictionary (the first as long as it can be), maybe
    // with a linking letter between them (bil-försäkring, kärlek-s-brev)
    function compound(w, depth) {
        if (depth > 5 || w.length < 6) return null;
        // (short parts only next to a long one: kan-vas and fjor-ton aren't compounds, bil-försäkring is)
        const fits = (a, b) => (a >= 4 && b >= 4) || (Math.min(a, b) >= 3 && Math.max(a, b) >= 6);
        for (let i = w.length - 3; i >= 3; i--) {
            const left = w.slice(0, i), right = w.slice(i);
            if (!isWord(right) || !SV_VOWEL.test(right) || !fits(left.length, right.length)) continue;
            if (isWord(left) && SV_VOWEL.test(left)) return seg(left, depth + 1).concat(seg(right, depth + 1));
            const l = left[left.length - 1];
            if (left.length > 3 && SV_LINKS.indexOf(l) >= 0) {
                const b = left.slice(0, -1);
                if (isWord(b) && SV_VOWEL.test(b)) return seg(b, depth + 1).concat([[l, "l", ""]], seg(right, depth + 1));
            }
        }
        return null;
    }
    // a part of a compound
    function part(p, last, depth) {
        if (isWord(p)) return seg(p, depth + 1);
        if (!last && p.length > 3) {
            for (const l of SV_LINKS) {
                if (!p.endsWith(l)) continue;
                const b = p.slice(0, -1);
                if (isWord(b)) return seg(b, depth + 1).concat([[l, "l", ""]]);
                for (const e of ["e", "a"]) if (isWord(b + e)) return root(b, b + e, depth).concat([[l, "l", ""]]);
            }
            // (-es-: hyr-es-hus, from hyra)
            if (p.endsWith("es") && p.length > 4) {
                const b = p.slice(0, -2);
                for (const e of ["a", "e", ""]) if (isWord(b + e)) return root(b, b + e, depth).concat([["es", "l", ""]]);
            }
        }
        for (const e of ["a", "e"]) if (isWord(p + e)) return root(p, p + e, depth);
        return affixes(p, depth) || [[p, "r", ""]];
    }
    // a root that's a word without its last letter (läs from läsa): the word's own morphemes, its last one shorter
    function root(text, word, depth) {
        const s = seg(word, depth + 1);
        const cut = word.length - text.length;
        const l = s[s.length - 1];
        if (s.length > 1 && l[1] === "e" && l[0].length === cut) return s.slice(0, -1);
        if (s.length > 1 && l[1] === "r" && l[0].length > cut) {
            const out = s.slice(0, -1);
            out.push([l[0].slice(0, l[0].length - cut), "r", l[2] || word]);
            return out;
        }
        return [[text, "r", word]];
    }
    // a prefix or suffix of the lists, when what's left is a word (or a verb without its -a)
    function affixes(w, depth) {
        if (depth > 5) return null;
        for (const suf of SV_SUFFIXES) {
            if (!w.endsWith(suf) || w.length - suf.length < 3) continue;
            const r = w.slice(0, -suf.length);
            if (!SV_VOWEL.test(r)) continue;
            if (SV_VERBAL.indexOf(suf) >= 0 && verbs.has(r + "a") && r + "a" !== w) return root(r, r + "a", depth).concat([[suf, "s", ""]]);
            if (isWord(r) && r !== w) return seg(r, depth + 1).concat([[suf, "s", ""]]);
            for (const e of ["a", "e"]) if (isWord(r + e) && r + e !== w) return root(r, r + e, depth).concat([[suf, "s", ""]]);
            // (a linking letter before it: arbet-s-lös)
            if (r.length > 3 && SV_LINKS.indexOf(r[r.length - 1]) >= 0) {
                const b = r.slice(0, -1);
                if (isWord(b)) return seg(b, depth + 1).concat([[r[r.length - 1], "l", ""], [suf, "s", ""]]);
                for (const e of ["e", "a"]) if (isWord(b + e)) return root(b, b + e, depth).concat([[r[r.length - 1], "l", ""], [suf, "s", ""]]);
            }
        }
        for (const pre of SV_PREFIXES) {
            if (!w.startsWith(pre)) continue;
            const r = w.slice(pre.length);
            // (three of a letter are written two: till + lägg → tillägg)
            const c = pre[pre.length - 1];
            if (r.length >= 3 && r[0] !== c && !/[aeiouyåäö]/.test(c)) {
                for (const e of ["", "a"]) if (isWord(c + r + e)) return [[pre, "p", ""], [r, "r", c + r + e]];
            }
            if (r.length >= 3 && SV_VOWEL.test(r) && isWord(r)) return [[pre, "p", ""]].concat(seg(r, depth + 1));
        }
        return null;
    }

    const out = new Map();
    for (const w of words) {
        const plain = w.value.replace(/\|/g, "");
        const low = plain.toLowerCase();
        if (out.has(low + "\t" + w.cls) || /[\s\-.,]/.test(low) || w.cls === "prefix" || w.cls === "suffix") continue;
        let s = seg(low, 0);
        // a verb: its stem and the -a of the infinitive (läs + a)
        if (w.cls === "vb" && low.length >= 4 && low.endsWith("a")) {
            const l = s[s.length - 1];
            if (l[1] === "r" && l[0].length > 2 && l[0].endsWith("a")) s = s.slice(0, -1).concat([[l[0].slice(0, -1), "r", l[2] || low], ["a", "e", ""]]);
        }
        // (the pieces in the word's own letters: a capital stays)
        let at = 0;
        s = s.map(x => { const t = plain.substr(at, x[0].length); at += x[0].length; return [t, x[1], x[2]]; });
        out.set(low + "\t" + w.cls, s.length > 1 && at === plain.length ? s : null);
    }
    return out;
}

/// the Chinese meanings of the Chinese Wiktionary's Swedish words (word → class → [meaning])
function svChinese(path) {
    const out = new Map();
    if (!path) return out;
    const POS = { noun: "nn", verb: "vb", adj: "jj", adv: "ab", pron: "pn", prep: "pp", conj: "kn", intj: "in", num: "rg" };
    const formOf = /(的|之)(複數|单数|單數|定指|不定指|定式|不定式|屬格|所有格|過去|过去|現在|现在|命令|分詞|分词|比較級|比较级|最高級|最高级|被動|被动|中性|陰性|陽性|通性|變格|变格|變位|变位|形式)|^(複數|复数|單數|单数)(形式)?$/;
    host.readLines(path, line => {
        if (line.length < 10 || line.indexOf("\"sv\"") < 0) return;
        let e;
        try { e = JSON.parse(line); } catch (x) { return; }
        if (e.lang_code !== "sv" || !e.word || !e.senses) return;
        const gl = [];
        for (const s of e.senses) {
            if (s.form_of || (s.tags && s.tags.indexOf("form-of") >= 0)) continue;
            for (const g of s.glosses || []) {
                const t = String(g).trim();
                if (!t || formOf.test(t) || /[a-zA-ZåäöÅÄÖ]{3}/.test(t.replace(/[（(][^）)]*[）)]/g, ""))) continue;
                if (gl.indexOf(t) < 0) gl.push(t);
            }
        }
        if (!gl.length) return;
        const w = e.word.toLowerCase(), c = POS[e.pos] || "";
        if (!out.has(w)) out.set(w, new Map());
        const m = out.get(w);
        m.set(c, (m.get(c) || []).concat(gl).filter((x, i, a) => a.indexOf(x) === i).slice(0, 6));
    });
    return out;
}

/// English → 華語 (CC-CEDICT the other way round): for a word without Chinese meanings, the 華語 words whose
/// meaning is its English one (shown marked as guessed, and only when 設定 says so). "v:pay" (CC-CEDICT's "to pay"),
/// "n:hand"; each with how good a match it is (a word's first meaning, two characters, first)
function svEnglishIndex(path) {
    const out = new Map();
    if (!path) return out;
    host.readLines(path, line0 => {
        const line = line0.replace(/\r$/, "");
        if (!line || line[0] === "#") return;
        const m = /^(\S+) (\S+) \[[^\]]*\] \/(.*)\/$/.exec(line);
        if (!m) return;
        const trad = m[1];
        if (/[A-Za-z0-9]/.test(trad) || [...trad].length > 4) return;
        m[3].split("/").forEach((d0, i) => {
            if (i > 2) return;
            const d = d0.replace(/\([^)]*\)/g, "").trim().toLowerCase();
            // (a meaning narrowed in brackets, "hand (in card games)": a worse match)
            const narrow = d0.indexOf("(") >= 0 ? 5 : 0;
            if (!d || /^(surname|variant of|old variant|see |used in|abbr|cl:|erhua|japanese|taiwan pr|also pr|classifier)/.test(d)) return;
            for (const piece of d.split(/;\s*/)) {
                const t = piece.trim();
                if (!t) continue;
                const key = t.startsWith("to ") ? "v:" + t.slice(3) : "n:" + t;
                const list = out.get(key) || [];
                if (!list.some(x => x[0] === trad)) { list.push([trad, i * 3 + narrow + Math.abs([...trad].length - 2)]); out.set(key, list); }
            }
        });
    });
    return out;
}

/// how common each 華語 word is (rime-essay): word → count
function svEssay(path) {
    const out = new Map();
    if (!path) return out;
    host.readLines(path, l => { const p = l.replace(/\r$/, "").split("\t"); if (p.length === 2) out.set(p[0], parseInt(p[1], 10) || 0); });
    return out;
}

/// (with rime-essay: only words used at least 1000 times there, the more common the better)
function svGuessChinese(idx, cls, terms, freq) {
    const got = [];
    for (const t0 of terms.flatMap(x => x.split(/,\s*/)).slice(0, 2)) {
        const t = t0.replace(/\([^)]*\)/g, "").trim().toLowerCase().replace(/^(to|a|an|the) /, "");
        if (!t) continue;
        let list = idx.get((cls === "vb" ? "v:" : "n:") + t) || [];
        if (freq.size) list = list.filter(x => (freq.get(x[0]) || 0) >= 1000);
        const key = x => x[1] - 4 * Math.log10((freq.get(x[0]) || 0) + 1);
        list = list.slice().sort((x, y) => key(x) - key(y));
        for (const [w] of list.slice(0, 2)) if (got.indexOf(w) < 0) got.push(w);
    }
    return got.slice(0, 3);
}

/// 華語 → English (CC-CEDICT), for looking Swedish words up in Chinese through the English: the 華語 words used at
/// least 300 times in rime-essay (正體 and 簡體), each with its first English meanings
function svChineseEnglish(path, freq) {
    const out = {};
    if (!path || !freq.size) return out;
    host.readLines(path, line0 => {
        const line = line0.replace(/\r$/, "");
        if (!line || line[0] === "#") return;
        const m = /^(\S+) (\S+) \[[^\]]*\] \/(.*)\/$/.exec(line);
        if (!m || (freq.get(m[1]) || 0) < 300) return;
        const en = [];
        for (const d0 of m[3].split("/")) {
            const d = d0.replace(/\([^)]*\)/g, "").trim();
            if (!d || /^(surname|variant of|old variant|see |used in|abbr|cl:|erhua|japanese|taiwan pr|also pr|classifier)/i.test(d)) continue;
            for (const p of d.split(/;\s*/)) { const t = p.trim(); if (t && en.indexOf(t) < 0) en.push(t); }
        }
        if (!en.length) return;
        // (a word read several ways: its meanings put together, the first line's first)
        for (const w of [m[1], m[2]]) {
            const have = out[w] ? out[w].split("; ") : [];
            for (const t of en) if (have.length < 4 && have.indexOf(t) < 0) have.push(t);
            out[w] = have.join("; ");
        }
    });
    return out;
}

function buildSwedish(a) {
    host.progress(0.05, "讀 Folkets lexikon…");
    const path = a.folkets || a.folkets2;
    if (!path) throw new Error("Folkets lexikon wasn't downloaded");
    const xml = host.readText(path);
    const words = svWords(xml);
    host.log("Folkets lexikon: " + words.length + " words");
    host.progress(0.3, "找詞素…");
    const morph = svMorphemes(words);
    // how common: the rank of the word (or of its most common form)
    host.progress(0.5, "常用詞…");
    const rank = new Map();
    if (a.freq) {
        let i = 0;
        host.readLines(a.freq, l => { const w = l.split(" ")[0]; if (w && !rank.has(w)) rank.set(w, ++i); });
    }
    host.progress(0.6, "中文意思…");
    const zh = svChinese(a.zhwikt);
    host.log("Chinese meanings: " + zh.size + " words");
    const enZh = svEnglishIndex(a.cedict);
    const essay = enZh.size ? svEssay(a.essay) : new Map();
    host.progress(0.8, "整理…");
    // one entry for each word and class: its <word>s are its meanings
    const groups = new Map(), order = [];
    for (const w of words) {
        if (w.cls === "prefix" || w.cls === "suffix") continue;
        const h = w.value.replace(/\|/g, "");
        const id = h + "\t" + w.cls;
        if (!groups.has(id)) { groups.set(id, []); order.push(id); }
        groups.get(id).push(w);
    }
    const entries = [];
    const keys = new Set();
    for (const id of order) {
        const ws = groups.get(id);
        const h = ws[0].value.replace(/\|/g, ""), cls = ws[0].cls, low = h.toLowerCase();
        let k = h + "\t瑞" + cls;
        while (keys.has(k)) k += "＊";
        keys.add(k);
        const d = [], all = [];
        for (const w of ws) {
            if (!w.tr.length && !w.def) continue;
            let t = w.tr.join("; ") || w.def;
            if (w.def && w.tr.length) t += " (" + w.def + ")";
            d.push([t, w.ex.slice(0, 4)]);
            for (const x of w.tr) if (all.indexOf(x) < 0) all.push(x);
        }
        if (!d.length) continue;
        // (a few "forms" in the data are the English word: left out)
        const inf = unique(ws.flatMap(w => w.inf)).filter(x => x !== h && all.indexOf(x) < 0);
        const ms = morph.get(low + "\t" + cls);
        const o = { k, h, s: ms ? ms.map(x => x[0] + ":" + x[1] + (x[2] && x[2] !== low ? ":" + x[2] : "")).join(" ") : "", d, n: all.join("; ") };
        if (SV_CLASS[cls]) o.w = [SV_CLASS[cls]];
        if (inf.length) o.m = inf.slice(0, 12);
        const syn = unique(ws.flatMap(w => w.syn)).filter(x => x !== h);
        if (syn.length) o.j = syn.slice(0, 8);
        const z = zh.get(low);
        if (z) {
            const c = z.get(cls) || z.get("") || (z.size === 1 ? Array.from(z.values())[0] : null);
            if (c && c.length) o.jp = c;
        }
        // (no Chinese meaning: 華語 words with its English meaning, marked ≈)
        if (!o.jp && enZh.size) {
            const g = svGuessChinese(enZh, cls, all, essay);
            if (g.length) o.jp = g.map(x => "≈" + x);
        }
        // (the most common of the word and its forms)
        let r = rank.get(low) || 0;
        for (const f of inf) { const x = rank.get(f.toLowerCase()); if (x && (!r || x < r)) r = x; }
        o._r = r;
        entries.push(o);
    }
    // the common words first (by how common), then the rest in the dictionary's order
    const ranked = entries.filter(e => e._r > 0 && e._r <= 30000).sort((x, y) => x._r - y._r);
    const rest = entries.filter(e => !(e._r > 0 && e._r <= 30000));
    const GROUP = 500;
    ranked.forEach((e, i) => { e.x = e.y = Math.floor(i / GROUP) + 1; });
    const outEntries = ranked.concat(rest).map(e => { delete e._r; return e; });
    const head = { v: 3, lang: "sv", nc: ranked.length, c: [], tags: {} };
    const ce = svChineseEnglish(a.cedict, essay);
    if (Object.keys(ce).length) head.ce = ce;
    host.progress(0.95, "寫入…");
    host.writeText(a.out, dumps(head).slice(0, -1) + ',"e":[\n' + outEntries.map(dumps).join(",\n") + "\n]}");
    host.log("sv.json: " + outEntries.length + " entries, " + ranked.length + " common");
}
