// 方方詞卡 查詞: hold the Apple Pencil (or a trackpad pointer) still over a Chinese character for a moment, and a card
// with the 華語 and 台語 words starting there pops up next to it. Selecting text with a finger works too.
// The words are inside the extension (made from the app's data when it was installed); the card writes them out
// in the spellings chosen in its own 設定. 加到不熟 and 收藏 are collected here; 傳到 App opens the app and hands
// them over (no shared folder with the app is needed, so it also works with Sideloadly).
(() => {
    if (window.__fangfangLookup) return;
    window.__fangfangLookup = true;

    const DWELL = 60;             // ms the Pencil stays on a character before the card shows (none when it's already showing)
    const HIDE = 900;             // ms after leaving the word and the card before the card goes
    const MAXLEN = 12;
    const isHan = cp => (cp >= 0x3400 && cp <= 0x9fff) || (cp >= 0xf900 && cp <= 0xfaff) || (cp >= 0x20000 && cp <= 0x3ffff);

    // ── settings (the card's own; kept in the extension) ────────────────────────────────────
    // pos: where the card shows (word: next to the word; tl / tr / bl / br: a corner of the screen); w, h: its size
    // when resized (0 = by its words)
    // on: the pop-up on at all (its button in Safari's toolbar); font: the size of the letters (1 = normal);
    // yue / hak: 粵語 and 客語 (hakAcc: the accent, hakRom: 0 拼音 / 1 注音); ring: a rainbow around the words saved
    // here when they're on a page; tint: the characters of saved words in their tone colours on the page
    const DEFAULTS = { on: true, zhPlace: 0, zhRom: 1, twRom: 1, twPlace: -1, colours: true, en: false, zh: true, tw: true,
        yue: true, hak: true, hakAcc: 0, hakRom: 0, font: 1, ring: false, tint: false, pos: "word", w: 0, h: 0 };
    let prefs = { ...DEFAULTS };
    let queue = [];               // [{k, w: "unknown" | "saved", h, x: the sentence}] waiting for 傳到 App
    let saved = [];               // [{h, c: [colours]}]: every word saved here (for the rainbow and the colours on the page)
    const store = browser.storage && browser.storage.local;
    if (store) {
        store.get(["ffPrefs", "ffQueue", "ffSaved"]).then(r => {
            prefs = fixPrefs(r.ffPrefs);
            queue = r.ffQueue || [];
            saved = r.ffSaved || [];
            pageMarks();
        }).catch(() => {});
        // (changed in the extension's own window, from its button in Safari's toolbar, or on another page)
        if (browser.storage.onChanged) browser.storage.onChanged.addListener((ch, area) => {
            if (ch.ffPrefs) { prefs = fixPrefs(ch.ffPrefs.newValue); if (card && card.style.display !== "none" && last && !card.querySelector(".set")) redraw(); }
            if (ch.ffQueue) queue = ch.ffQueue.newValue || [];
            if (ch.ffSaved) saved = ch.ffSaved.newValue || [];
            if (ch.ffPrefs || ch.ffSaved) { if (!prefs.on) hide(); pageMarks(); }
        });
    }
    function fixPrefs(p) {
        const out = { ...DEFAULTS, ...(p || {}) };
        if (out.corner === true && (!p || !p.pos)) out.pos = "tl";      // (the older 左上角 setting)
        delete out.corner;
        return out;
    }
    const savePrefs = () => store && store.set({ ffPrefs: prefs }).catch(() => {});
    const saveQueue = () => store && store.set({ ffQueue: queue }).catch(() => {});
    const saveSaved = () => store && store.set({ ffSaved: saved }).catch(() => {});

    let host = null, root = null, card = null, body = null, grip = null;
    let dwellTimer = null, hideTimer = null, lastSpot = "", shownSpot = "", busy = 0;
    let last = null;              // the last answer and where it was shown (redrawn after a setting changes)

    // ── the character under a point ─────────────────────────────────────────────────────────
    function caretAt(x, y) {
        if (document.caretRangeFromPoint) {
            const r = document.caretRangeFromPoint(x, y);
            if (r) return { node: r.startContainer, off: r.startOffset };
        }
        if (document.caretPositionFromPoint) {
            const p = document.caretPositionFromPoint(x, y);
            if (p) return { node: p.offsetNode, off: p.offset };
        }
        return null;
    }
    function charAt(x, y) {
        const r = caretAt(x, y);
        if (!r || !r.node || r.node.nodeType !== Node.TEXT_NODE) return null;
        const node = r.node, t = node.data;
        for (let o of [r.off, r.off - 1, r.off - 2]) {
            if (o < 0 || o >= t.length) continue;
            const c = t.charCodeAt(o);
            if (c >= 0xdc00 && c <= 0xdfff && o > 0) o -= 1;          // (the second half of a character beyond 0xffff)
            const cp = t.codePointAt(o), len = cp > 0xffff ? 2 : 1;
            const rr = document.createRange();
            rr.setStart(node, o); rr.setEnd(node, o + len);
            const b = rr.getBoundingClientRect();
            if (b.width && x >= b.left - 1 && x <= b.right + 1 && y >= b.top - 1 && y <= b.bottom + 1) {
                return { node, off: o, cp, rect: b };
            }
        }
        return null;
    }

    // the text from there on (into the next bits of text of the same paragraph), up to the first non-Chinese character
    function textFrom(node, off) {
        let s = node.data.slice(off);
        const block = n => { let e = n.parentElement; while (e && getComputedStyle(e).display.startsWith("inline")) e = e.parentElement; return e; };
        const b0 = block(node);
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        walker.currentNode = node;
        while ([...s].length < MAXLEN) {
            const n = walker.nextNode();
            if (!n || block(n) !== b0) break;
            s += n.data;
        }
        let out = "";
        for (const ch of s) {
            if (!isHan(ch.codePointAt(0)) || [...out].length >= MAXLEN) break;
            out += ch;
        }
        return out;
    }

    // ── looking up ──────────────────────────────────────────────────────────────────────────
    function ask(msg) {
        return browser.runtime.sendMessage(msg).catch(e => ({ ok: false, error: String(e) }));
    }

    // the files, kept in the page once read: a word is then found at once. A character's file is read as soon as
    // the Pencil reaches it, before the card is asked for
    let metaP = null;
    const shardP = new Map();
    function getFile(name) {
        if (!shardP.has(name)) {
            shardP.set(name, ask({ op: "file", name }).then(r => (r && r.ok) ? r.data : null));
            if (shardP.size > 24) shardP.delete(shardP.keys().next().value);
        }
        return shardP.get(name);
    }
    function getMeta() {
        if (!metaP) metaP = ask({ op: "file", name: "d-meta.json" }).then(r => (r && r.ok) ? r.data : null).then(m => { if (!m) metaP = null; return m; });
        return metaP;
    }
    function shardName(lang, cp, meta) { return `d-${lang}-${String(cp % ((meta && meta.shards) || 256)).padStart(3, "0")}.json`; }
    function prefetch(cp) {
        getMeta().then(m => {
            if (!m) return;
            for (const l of ["zh", "tw", "yue", "hak"]) if (prefs[l] && (m[l] === undefined || m[l] > 0)) getFile(shardName(l, cp, m));
        });
    }

    async function find(text) {
        const meta = await getMeta();
        if (!meta) return { ok: true, ready: false };
        const chars = [...text].slice(0, meta.max || 12);
        const out = { ok: true, ready: true, tab: meta };
        if (!chars.length) return out;
        const cp = chars[0].codePointAt(0);
        const want = ["zh", "tw", "yue", "hak"].filter(l => prefs[l] && (meta[l] === undefined || meta[l] > 0));
        const files = await Promise.all(want.map(l => getFile(shardName(l, cp, meta))));
        want.forEach((lang, j) => {
            const sh = files[j];
            if (!sh) return;
            for (let n = chars.length; n >= 1; n--) {
                const w = chars.slice(0, n).join("");
                if (sh[w]) { out[lang] = { w, list: sh[w] }; break; }
            }
        });
        return out;
    }

    // `at`: where the word starts on the page (its text node and offset), to mark it
    async function lookup(text, rect, spot, at) {
        const n = ++busy;
        const res = await find(text);
        if (n !== busy) return;                       // (a newer one was asked meanwhile)
        if (!res || !res.ok) { show(rect, spot, message("查詞沒有回應。請在 Safari 的延伸功能設定裡允許「方方詞卡 查詞」。")); return; }
        if (!res.ready) { show(rect, spot, message("查詞的資料不在延伸功能裡：請在 Mac 上重新執行一次安裝。")); return; }
        if (!res.zh && !res.tw && !res.yue && !res.hak) { hide(); return; }
        last = { res, rect, spot };
        show(rect, spot, render(res));
        // the word on the page, marked in light blue (the longer of the 華語 and the 台語 word found)
        const len = Math.max(...["zh", "tw", "yue", "hak"].map(l => res[l] ? [...res[l].w].length : 0));
        if (at) markWord(at.node, at.off, len); else unmark();
        lastSentence = at ? sentenceAt(at.node, at.off) : (window.getSelection ? sentenceOfSelection() : "");
    }

    // ── the light blue mark around the word ─────────────────────────────────────────────────
    let marks = null;
    function wordRange(node, off, len) {
        const r = document.createRange();
        r.setStart(node, off);
        let n = node, o = off, left = len;
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        walker.currentNode = node;
        while (n) {
            const t = n.data;
            while (o < t.length && left > 0) { o += t.codePointAt(o) > 0xffff ? 2 : 1; left--; }
            r.setEnd(n, o);
            if (left <= 0) break;
            n = walker.nextNode(); o = 0;
        }
        return r;
    }
    function markWord(node, off, len) {
        ensureHost();
        unmark();
        if (!len || !node.isConnected) return;
        const rects = [...wordRange(node, off, len).getClientRects()].filter(b => b.width > 0 && b.height > 0);
        marks = document.createElement("div");
        marks.className = "marks";
        for (const b of rects) {
            const m = document.createElement("div");
            m.className = "mark";
            m.style.left = (b.left - 2) + "px"; m.style.top = (b.top - 1) + "px";
            m.style.width = (b.width + 4) + "px"; m.style.height = (b.height + 2) + "px";
            marks.appendChild(m);
        }
        root.insertBefore(marks, card);
    }
    function unmark() { if (marks) { marks.remove(); marks = null; } }

    // ── writing readings out ────────────────────────────────────────────────────────────────
    const ZH = { 1: "ff6b6b", 2: "6fdc7f", 3: "6eaaff", 4: "c39bff", 0: "8e8e93" };
    const TW = { 1: "ff6b6b", 2: "c39bff", 3: "6eaaff", 4: "ffa94d", 5: "6fdc7f", 6: "4fd8c4", 7: "ffe066", 8: "ff8cc6", 0: "8e8e93" };
    const SC = { 1: "ff6b6b", 2: "4fd8c4", 3: "c39bff", 4: "6eaaff", 5: "4fd8c4" };

    const zyTone = s => (s.startsWith("˙") || s.endsWith("˙")) ? 0 : ({ "ˊ": 2, "ˇ": 3, "ˋ": 4 }[s.slice(-1)] || 1);
    const digitTone = s => { const d = parseInt(s.slice(-1), 10); return isNaN(d) ? 0 : d; };

    // a 四川話 syllable: the tone as a mark on the vowel ("ce1" → "cē"; 2 and 5: a line under it)
    function sichuan(s) {
        const d = digitTone(s);
        const L = [...s.slice(0, -1)];
        const mark = { 1: "̄", 2: "̱", 5: "̱", 3: "̀", 4: "̌" }[d];
        if (!mark) return L.join("");
        let v = L.indexOf("a");
        if (v < 0) v = L.findIndex(c => c === "e" || c === "ê");
        if (v < 0) { const o = L.indexOf("o"); if (o >= 0 && L[o + 1] === "u") v = o; }
        if (v < 0) { for (let i = L.length - 1; i >= 0; i--) if ("iouüv".includes(L[i])) { v = i; break; } }
        if (v < 0) v = 0;
        return (L.slice(0, v + 1).join("") + mark + L.slice(v + 1).join("")).normalize("NFC");
    }

    // [{t, c}] for a word's 漢字, one colour per syllable
    function hanSegs(han, tones, pal) {
        const out = [];
        let i = 0;
        for (const ch of han) {
            if (isHan(ch.codePointAt(0)) && i < tones.length) { out.push({ t: ch, c: prefs.colours ? pal[tones[i]] : null }); i++; }
            else out.push({ t: ch, c: null });
        }
        return out;
    }

    function zhParts(e, tab) {
        const place = prefs.zhPlace;
        const isSc = place === 2 && e.s;
        const syl = (isSc ? e.s : (place >= 1 && e.l ? e.l : e.t)).split(" ").filter(s => s && s !== "_");
        let lastT = 1;
        const tones = syl.map(s => s === "-" ? lastT : (lastT = isSc ? digitTone(s) : zyTone(s)));
        const shown = syl.filter(s => s !== "-");
        const col = (s, t) => prefs.colours ? (isSc ? SC : ZH)[t] : null;
        const tShown = tones.filter((_, i) => syl[i] !== "-");
        let r, r2 = null;
        const zy = () => shown.map((s, i) => ({ t: (i ? " " : "") + s, c: col(s, tShown[i]) }));
        const py = () => shown.map((s, i) => ({ t: tab.py[s] || s, c: col(s, tShown[i]) }));
        if (isSc) r = shown.map((s, i) => ({ t: (i ? " " : "") + sichuan(s), c: col(s, tShown[i]) }));
        else if (prefs.zhRom === 1) { r = zy(); r2 = py(); }
        else { r = py(); r2 = zy(); }
        const pal = isSc ? SC : ZH;
        return { h: hanSegs(e.h || e.k.split("\t")[0], tones, pal), r, r2 };
    }

    function twSpell(c, tab, sys, place) {
        const s = tab.syl[c];
        if (sys === 3) {
            let f = s ? s[0] : c;
            if (place >= 0 && c.includes("ø") && place !== 4 && place !== 5) f = f.replace(/ㄜ/g, "ㄛ");
            return f;
        }
        if (sys === 1) return tab.tl[c] || (s ? s[1] : c);
        if (sys === 2) return tab.pj[c] || (s ? s[1] : c);
        return s ? s[1] : c;
    }

    // ── 台語 tones as they're said (the same as the app's 聲調顏色) ──
    // A word on its own: every syllable takes its changed tone (sandhi) except the last one, which keeps its own.
    // A syllable before "--" keeps its own tone too, and the syllables after "--" are in the light tone (grey).
    // Before 仔 a syllable takes 仔's own change. The changes follow the 腔口 (泉 places: 2→5, 5→3, 8→3).
    function toneOf(code) {
        const t = parseInt(code.slice(-1), 10);
        if (isNaN(t)) return { t: 0, h: false };
        const body = code.slice(0, -1);
        const hasVowel = /[iuaoøeIUɨəɵ]/.test(body);
        const stop = hasVowel && /[BDG]$/.test(body);
        return { t, h: !stop };
    }
    function quan(place) { return place >= 0 && placeNames && placeNames[place] && placeNames[place].includes("泉"); }
    function sandhiTone(code, place) {
        const { t, h } = toneOf(code), q = quan(place);
        switch (t) {
            case 1: return 7;
            case 2: return q ? 5 : 1;
            case 3: return 2;
            case 5: return q ? 3 : 7;
            case 7: case 6: return 3;
            case 4: return h ? 2 : 8;
            case 8: return h ? 3 : (q ? 3 : 4);
            default: return t;
        }
    }
    function aSandhiTone(code) {
        const { t, h } = toneOf(code);
        if (t === 2 || t === 3) return 1;
        if ([1, 5, 6, 7, 8].includes(t)) return 7;
        if (t === 4) return h ? 7 : 8;
        return t;
    }
    // the word's tokens with the place's syllables in them ("--" light tone, "_" a space, "^" a capital, "~" text)
    function twTokens(e, tab, place) {
        const codes = ((place >= 0 && e.d && e.d[String(place)]) || e.c).split(" ").filter(Boolean);
        if (!e.o) return codes;
        let i = 0;
        return e.o.split(" ").filter(Boolean).map(t => {
            const cap = t.startsWith("^"), c = cap ? t.slice(1) : t;
            if (!tab.syl[c]) return t;
            const n = i < codes.length ? codes[i] : c;
            i++;
            return (cap ? "^" : "") + n;
        });
    }

    function twParts(e, tab) {
        const place = prefs.twPlace;
        const toks = twTokens(e, tab, place);
        const isCode = t => !!tab.syl[t.startsWith("^") ? t.slice(1) : t];
        // the syllables: light (after "--"), before "--", before 仔
        const units = [];
        let lightNext = false;
        for (const t of toks) {
            if (isCode(t)) units.push({ code: t.replace(/^\^/, ""), light: lightNext, beforeLight: false, beforeA: false });
            else if (t === "--") { if (units.length) units[units.length - 1].beforeLight = true; lightNext = true; }
            else if (t === "_") lightNext = false;
        }
        const han = [...e.k.split("\t")[0]];
        if (han.length === units.length) for (let i = 0; i < units.length - 1; i++) if (han[i + 1] === "仔") units[i].beforeA = true;
        const tones = units.map((u, i) => {
            if (u.light) return 0;
            if (u.beforeA && !u.beforeLight) return aSandhiTone(u.code);
            if (i === units.length - 1 || u.beforeLight) return toneOf(u.code).t;
            return sandhiTone(u.code, place);
        });
        const line = sys => {
            const out = [];
            let prevCode = false, n = 0;
            for (const t of toks) {
                if (isCode(t)) {
                    const cap = t.startsWith("^"), c = cap ? t.slice(1) : t;
                    let sp = twSpell(c, tab, sys, place);
                    if (cap && sys !== 3) sp = sp.charAt(0).toUpperCase() + sp.slice(1);
                    out.push({ t: (prevCode && sys !== 3 ? "-" : "") + sp, c: prefs.colours ? TW[tones[n]] : null });
                    n++; prevCode = true;
                } else if (t === "--") { if (sys !== 3) out.push({ t: "--", c: null }); prevCode = false; }
                else if (t === "_") { out.push({ t: " ", c: null }); prevCode = false; }
                else if (t.startsWith("~")) { out.push({ t: t.slice(1), c: null }); prevCode = false; }
                else { out.push({ t, c: null }); prevCode = false; }
            }
            return out;
        };
        return { h: hanSegs(han.join(""), tones, TW), r: line(prefs.twRom), r2: prefs.twRom === 3 ? null : line(3) };
    }

    // ── 粵語 and 客語 ────────────────────────────────────────────────────────────────────────
    const YUE = { 1: "ff6b6b", 2: "6fdc7f", 3: "ffe066", 4: "6eaaff", 5: "c39bff", 6: "4fd8c4" };
    function yueParts(e) {
        const syl = e.s.split(" ").filter(Boolean);
        const tones = syl.map(x => parseInt(x.slice(-1), 10) || 0);
        const r = syl.map((x, i) => ({ t: (i ? " " : "") + x, c: prefs.colours ? YUE[tones[i]] : null }));
        return { h: hanSegs(e.k.split("\t")[0], tones, YUE), r, r2: null };
    }
    // 客語: a syllable is its letters, the tone category as a superscript digit and the accent as a subscript one
    // ("bau¹₀"); written with the accent's tone mark, coloured by how the accent says the tone (the same pitch the
    // same colour in every accent, as in the app)
    const SUPS = "⁰¹²³⁴⁵⁶⁷⁸⁹", SUBS = "₀₁₂₃₄₅₆₇₈₉";
    const HAK_PITCH = [{ 1: "24", 5: "11", 2: "31", 3: "55", 4: "2", 8: "5" }, { 1: "53", 5: "55", 2: "24", 3: "11", 7: "33", 4: "5", 8: "2" },
        { 1: "35", 5: "113", 2: "31", 3: "53", 4: "21", 8: "54" }, { 1: "11", 5: "55", 2: "53", 7: "24", 4: "2", 8: "5" },
        { 1: "11", 2: "31", 4: "24", 5: "53", 7: "55", 8: "43" }, { 1: "24", 5: "11", 2: "31", 3: "55", 4: "2", 8: "5" }];
    function hakColour(acc, cat) {
        const p = (HAK_PITCH[acc] || {})[cat];
        if (!p) return null;
        if (cat === 4 || cat === 8) return ["2", "21", "24"].includes(p) ? "ffa94d" : "ff8cc6";
        return { "24": "6fdc7f", "35": "6fdc7f", "11": "6eaaff", "113": "6eaaff", "31": "4fd8c4", "55": "ff6b6b", "53": "c39bff", "33": "ffe066" }[p] || null;
    }
    function hakParts(e, tab) {
        const acc = prefs.hakAcc;
        const own = e.a && e.a[acc] ? e.a[acc] : e.s;
        const syl = own.split(" ").filter(Boolean);
        const parsed = syl.map(x => { const c = [...x]; return { l: c.slice(0, -2).join(""), cat: SUPS.indexOf(c[c.length - 2]), acc: SUBS.indexOf(c[c.length - 1]) }; });
        const marks = (tab && tab.ht) || [];
        const hz = (tab && tab.hz) || {};
        const r = parsed.map((p, i) => {
            const mark = (marks[p.acc] || [])[p.cat] || "";
            const body = prefs.hakRom === 1 ? (hz[p.l] || p.l) : p.l;
            return { t: (i ? " " : "") + body + mark, c: prefs.colours ? hakColour(p.acc, p.cat) : null };
        });
        const cols = {}; parsed.forEach((p, i) => { cols[i + 1] = hakColour(p.acc, p.cat); });
        return { h: hanSegs(e.k.split("\t")[0], parsed.map((_, i) => i + 1), cols), r, r2: null, guess: !!(e.a && !e.a[acc]) };
    }

    // ── the sentence a word is in (kept with it when it's saved): from the stop before it to the stop after it ──
    let lastSentence = "";
    const STOPS = "。！？!?；;\n";
    function blockOf(node) {
        let e = node.nodeType === 3 ? node.parentElement : node;
        while (e && e !== document.body && !/^(P|LI|TD|TH|DD|DT|BLOCKQUOTE|H[1-6]|DIV|ARTICLE|SECTION|FIGCAPTION|CAPTION)$/.test(e.tagName)) e = e.parentElement;
        return e || document.body;
    }
    function sentenceAt(node, off) {
        try {
            const block = blockOf(node);
            const w = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
            let text = "", at = -1;
            for (let n = w.nextNode(); n; n = w.nextNode()) {
                if (n === node) at = text.length + off;
                text += n.nodeValue;
                if (text.length > 4000 && at >= 0) break;
            }
            if (at < 0) return "";
            return cutSentence(text, at);
        } catch (err) { return ""; }
    }
    function cutSentence(text, at) {
        let a = at, b = at;
        while (a > 0 && !STOPS.includes(text[a - 1])) a--;
        while (b < text.length && !STOPS.includes(text[b])) b++;
        if (b < text.length && text[b] !== "\n") b++;          // (the 。 itself)
        const sv = text.slice(a, b).replace(/\s+/g, " ").trim();
        return [...sv].length > 160 ? [...sv].slice(0, 160).join("") + "…" : sv;
    }
    function sentenceOfSelection() {
        const sel = document.getSelection();
        if (!sel || sel.rangeCount === 0) return "";
        const r = sel.getRangeAt(0);
        return sentenceAt(r.startContainer, r.startOffset);
    }

    // ── on the page: a rainbow around the words saved here, and their characters in their tone colours ──
    let ringBox = null, ringTimer = null;
    // the rainbow of the app (the standard tone colours: red, orange, yellow, green, teal, blue, purple, pink), all the way round
    const RING = "conic-gradient(from 225deg,#ff6b6b,#ffa94d,#ffe066,#6fdc7f,#4fd8c4,#6eaaff,#c39bff,#ff8cc6,#ff6b6b)";
    function textNodesInView() {
        const out = [];
        const w = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, {
            acceptNode: n => (n.nodeValue && /[\u3400-\u9fff]/.test(n.nodeValue) && n.parentElement && !n.parentElement.closest("script,style,textarea,input,fangfang-lookup"))
                ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT });
        for (let n = w.nextNode(); n && out.length < 3000; n = w.nextNode()) out.push(n);
        return out;
    }
    function pageMarks() {
        clearTimeout(ringTimer);
        ringTimer = setTimeout(drawPageMarks, 250);
    }
    function drawPageMarks() {
        if (ringBox) { ringBox.remove(); ringBox = null; }
        if (window.CSS && CSS.highlights) for (const k of [...CSS.highlights.keys()]) if (k.startsWith("ff-tone-")) CSS.highlights.delete(k);
        if (prefs.on && prefs.tint === "all" && document.body) { tintAll(); if (!prefs.ring) return; }
        if (!prefs.on || (!prefs.ring && !prefs.tint) || !saved.length || !document.body) return;
        const words = saved.map(s => s.h).filter(Boolean).sort((a, b) => b.length - a.length);
        const colourOf = new Map(saved.map(s => [s.h, s.c || []]));
        const vh = window.innerHeight, vw = window.innerWidth;
        ringBox = document.createElement("div");
        ringBox.style.cssText = "position:fixed;left:0;top:0;width:0;height:0;z-index:2147483645;pointer-events:none;";
        const tones = {};
        let n = 0;
        for (const node of textNodesInView()) {
            const t = node.nodeValue;
            for (const wd of words) {
                let i = t.indexOf(wd);
                while (i >= 0 && n < 400) {
                    const r = document.createRange();
                    r.setStart(node, i); r.setEnd(node, i + wd.length);
                    const b = r.getBoundingClientRect();
                    if (b.bottom > 0 && b.top < vh && b.right > 0 && b.left < vw && b.width > 0) {
                        n++;
                        if (prefs.ring) {
                            const m = document.createElement("div");
                            // (only the ring is painted: the mask cuts the inside out, so the word stays readable)
                            m.style.cssText = `position:fixed;left:${b.left - 5}px;top:${b.top - 4}px;width:${b.width + 10}px;height:${b.height + 8}px;` +
                                "box-sizing:border-box;border-radius:7px;padding:2.5px;background:" + RING + ";" +
                                "-webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;" +
                                "mask:linear-gradient(#000 0 0) content-box exclude,linear-gradient(#000 0 0);";
                            ringBox.appendChild(m);
                        }
                        if (prefs.tint && prefs.tint !== "all") {
                            const cs = colourOf.get(wd) || [];
                            [...wd].forEach((ch, j) => {
                                const c = cs[j];
                                if (!c) return;
                                const rr = document.createRange();
                                const st = i + [...wd].slice(0, j).join("").length;
                                rr.setStart(node, st); rr.setEnd(node, st + ch.length);
                                (tones[c] = tones[c] || []).push(rr);
                            });
                        }
                    }
                    i = t.indexOf(wd, i + wd.length);
                }
            }
        }
        (document.body || document.documentElement).appendChild(ringBox);
        if (prefs.tint && prefs.tint !== "all") setToneHighlights(tones);
    }
    // (CSS highlights colour the letters without changing the page)
    function setToneHighlights(tones) {
        if (window.CSS && CSS.highlights && window.Highlight) {
            let style = document.getElementById("ff-tone-style");
            if (!style) { style = document.createElement("style"); style.id = "ff-tone-style"; document.head.appendChild(style); }
            let css = "";
            for (const [c, ranges] of Object.entries(tones)) {
                CSS.highlights.set("ff-tone-" + c, new Highlight(...ranges));
                css += `::highlight(ff-tone-${c}) { color: #${c}; }\n`;
            }
            style.textContent = css;
        }
    }

    // every 華語 word on the screen in its tone colours (the longest word the dictionary has at each place)
    let tintRun = 0;
    async function tintAll() {
        const run = ++tintRun;
        const meta = await getMeta();
        if (!meta || run !== tintRun) return;
        const vh = window.innerHeight;
        const nodes = textNodesInView().filter(n => {
            const r = document.createRange(); r.selectNodeContents(n);
            const b = r.getBoundingClientRect();
            return b.bottom > -50 && b.top < vh + 50;
        }).slice(0, 400);
        // the files for the characters on screen
        const cps = new Set();
        for (const n of nodes) for (const ch of n.nodeValue) { const c = ch.codePointAt(0); if (isHan(c)) cps.add(c % (meta.shards || 256)); }
        const files = new Map();
        await Promise.all([...cps].slice(0, 120).map(async i => {
            const nm = `d-zh-${String(i).padStart(3, "0")}.json`;
            files.set(nm, await getFile(nm));
        }));
        if (run !== tintRun) return;
        const tones = {};
        for (const n of nodes) {
            const t = n.nodeValue;
            const chars = [...t];
            let i = 0, pos = 0;          // (pos: in UTF-16 units)
            while (i < chars.length) {
                const cp = chars[i].codePointAt(0);
                if (!isHan(cp)) { pos += chars[i].length; i++; continue; }
                const sh = files.get(`d-zh-${String(cp % (meta.shards || 256)).padStart(3, "0")}.json`);
                let found = null, len = 1;
                if (sh) for (let L = Math.min(meta.max || 12, chars.length - i); L >= 1; L--) {
                    const w = chars.slice(i, i + L).join("");
                    if (sh[w]) { found = sh[w][0]; len = L; break; }
                }
                if (found) {
                    const segsH = zhParts(found, meta).h || [];
                    const cols = segsH.flatMap(sg => [...sg.t].map(() => sg.c || null));
                    let p2 = pos;
                    for (let j = 0; j < len; j++) {
                        const ch = chars[i + j];
                        const c = cols[j];
                        if (c) {
                            const r = document.createRange();
                            r.setStart(n, p2); r.setEnd(n, p2 + ch.length);
                            (tones[c] = tones[c] || []).push(r);
                        }
                        p2 += ch.length;
                    }
                }
                for (let j = 0; j < len; j++) pos += chars[i + j].length;
                i += len;
            }
        }
        setToneHighlights(tones);
    }
    window.addEventListener("scroll", pageMarks, { passive: true });
    window.addEventListener("resize", pageMarks, { passive: true });

    // ── the card ────────────────────────────────────────────────────────────────────────────
    const CSS_TEXT = `
        :host { all: initial; }
        .card { position: fixed; z-index: 2147483647; width: max-content; max-width: min(360px, calc(100vw - 16px));
            max-height: min(70vh, 540px); display: flex; flex-direction: column; box-sizing: border-box; overflow: hidden;
            background: rgba(30, 31, 35, 0.97); color: #f2f2f2; border: 1.5px solid #4b4b4e;
            border-radius: 14px; box-shadow: 0 8px 28px rgba(0,0,0,.45);
            font: 15px/1.35 -apple-system, "PingFang TC", "Heiti TC", sans-serif; -webkit-text-size-adjust: none; }
        .body { flex: 1 1 auto; min-height: 0; overflow-y: auto; -webkit-overflow-scrolling: touch; padding: 8px 12px 14px; }
        .grip { position: absolute; width: 22px; height: 22px; touch-action: none; cursor: nwse-resize; }
        .grip::after { content: ""; position: absolute; width: 10px; height: 10px; border: 0 solid #8e8e93; }
        .grip.br { right: 0; bottom: 0; } .grip.br::after { right: 5px; bottom: 5px; border-right-width: 2px; border-bottom-width: 2px; border-bottom-right-radius: 3px; }
        .grip.bl { left: 0; bottom: 0; cursor: nesw-resize; } .grip.bl::after { left: 5px; bottom: 5px; border-left-width: 2px; border-bottom-width: 2px; border-bottom-left-radius: 3px; }
        .grip.tr { right: 0; top: 0; cursor: nesw-resize; } .grip.tr::after { right: 5px; top: 5px; border-right-width: 2px; border-top-width: 2px; border-top-right-radius: 3px; }
        .grip.tl { left: 0; top: 0; } .grip.tl::after { left: 5px; top: 5px; border-left-width: 2px; border-top-width: 2px; border-top-left-radius: 3px; }
        .top { display: flex; justify-content: flex-end; gap: 6px; margin-bottom: 4px; }
        .sec { border-radius: 10px; padding: 6px 9px 8px; border-left: 4px solid transparent; }
        .sec + .sec { margin-top: 8px; }
        .sec.zh { background: rgba(79, 125, 255, 0.10); border-left-color: #4f7dff; }
        .sec.tw { background: rgba(63, 174, 102, 0.10); border-left-color: #3fae66; }
        .sec.yue { background: rgba(201, 162, 39, 0.10); border-left-color: #c9a227; }
        .sec.hak { background: rgba(216, 67, 79, 0.10); border-left-color: #d8434f; }
        .cols { display: flex; gap: 8px; align-items: flex-start; }
        .cols > .sec { flex: 1 1 0; min-width: 190px; margin-top: 0; }
        .lang { display: inline-block; font-size: 12px; padding: 1px 7px; border-radius: 6px; margin-bottom: 4px; }
        .lang.zh { background: #1f3d6b; border: 1px solid #4f7dff; color: #9ad0ff; }
        .lang.tw { background: #1d4630; border: 1px solid #3fae66; color: #b6f0c8; }
        .lang.yue { background: #5a4a14; border: 1px solid #c9a227; color: #ffe58a; }
        .lang.hak { background: #5a1e2a; border: 1px solid #d8434f; color: #ffb3b8; }
        .via { font-size: 12px; color: #a3a3a8; margin: 2px 0 1px; }
        .e + .e { margin-top: 8px; }
        .head { display: flex; align-items: baseline; flex-wrap: wrap; gap: 4px 10px; }
        .han { font-size: 26px; font-weight: 600; color: #f2f2f2; }
        .r { font-size: 17px; color: #d4efc0; }
        .r2 { font-size: 13px; color: #e3c6f7; }
        .m { font-size: 14px; color: #f2f2f2; margin-top: 2px; }
        .en { font-size: 13px; color: #a3a3a8; margin-top: 2px; }
        .chips { margin-top: 3px; }
        .chip { display: inline-block; font-size: 11px; padding: 0 6px; border-radius: 5px; margin-right: 4px;
            background: #2b2b2d; border: 1px solid #4b4b4e; color: #a3a3a8; }
        .chip.p1 { background: #5a2346; border-color: #ff8cc6; color: #ffc9e4; }
        .chip.p2 { background: #57501a; border-color: #ffd84d; color: #fff1a8; }
        .chip.p0 { background: #5c3f1a; border-color: #ffa94d; color: #ffd29a; }
        .chip.sc { background: #1d4a44; border-color: #4fd8c4; color: #b4f2e8; }
        .btns { display: flex; gap: 8px; margin-top: 6px; }
        button { all: unset; cursor: pointer; font-size: 13px; padding: 4px 10px; border-radius: 8px;
            background: #2b2b2d; border: 1px solid #4b4b4e; color: #f2f2f2; }
        button.small { font-size: 12px; padding: 2px 8px; }
        button.on.u { background: #5b4136; border-color: #8b4a2d; color: #f3c9b2; }
        button.on.s { background: #5a5238; border-color: #8c7a38; color: #f1e3ae; }
        button.send { background: #44503a; border-color: #4f6c32; color: #d4efc0; }
        .msg { font-size: 14px; color: #f2f2f2; }
        .set { font-size: 13px; }
        .set label { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin: 6px 0; }
        .set select { font-size: 13px; background: #2b2b2d; color: #f2f2f2; border: 1px solid #4b4b4e; border-radius: 6px; padding: 2px 4px; }
        .note { font-size: 12px; color: #a3a3a8; margin-top: 6px; }
        .mark { position: fixed; z-index: 2147483646; pointer-events: none; box-sizing: border-box;
            border: 2px solid #7cc4ff; border-radius: 5px; background: rgba(124, 196, 255, 0.16); }
    `;

    function ensureHost() {
        if (host && host.isConnected) return;
        host = document.createElement("fangfang-lookup");
        root = host.attachShadow({ mode: "closed" });
        const style = document.createElement("style");
        style.textContent = CSS_TEXT;
        root.appendChild(style);
        card = document.createElement("div");
        card.className = "card";
        card.style.display = "none";
        body = document.createElement("div");
        body.className = "body";
        grip = document.createElement("div");
        grip.className = "grip";
        card.append(body, grip);
        root.appendChild(card);
        setUpGrip();
        (document.body || document.documentElement).appendChild(host);
        card.addEventListener("pointerenter", () => clearTimeout(hideTimer));
        card.addEventListener("pointermove", () => clearTimeout(hideTimer));
    }

    function el(tag, cls, text) {
        const e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text != null) e.textContent = text;
        return e;
    }
    function segs(cls, list) {
        const e = el("span", cls);
        for (const s of list || []) {
            const sp = el("span", null, s.t);
            if (s.c) sp.style.color = "#" + s.c;
            e.appendChild(sp);
        }
        return e;
    }
    function message(text) { return el("div", "msg", text); }

    function topBar(onSettings) {
        const top = el("div", "top");
        if (queue.length) {
            const send = el("button", "small send", "傳到 App（" + queue.length + "）");
            send.addEventListener("click", ev => { ev.preventDefault(); ev.stopPropagation(); sendToApp(); });
            top.appendChild(send);
        }
        const gear = el("button", "small", onSettings ? "完成" : "設定");
        gear.addEventListener("click", ev => {
            ev.preventDefault(); ev.stopPropagation();
            if (onSettings) { if (last) redraw(); else hide(); } else { body.replaceChildren(settings()); }
        });
        top.appendChild(gear);
        return top;
    }

    function render(res) {
        const box = el("div");
        box.appendChild(topBar(false));
        const tab = res.tab || { py: {}, syl: {}, tl: {}, pj: {} };
        // (at a corner of the screen: the languages side by side; next to the word: one under the other)
        const holder = (prefs.pos || "word") !== "word" ? el("div", "cols") : box;
        if (holder !== box) box.appendChild(holder);
        const NAMES = { zh: "華語", tw: "台語", yue: "粵語", hak: "客語" };
        for (const lang of ["zh", "tw", "yue", "hak"]) {
            const part = res[lang];
            if (!part) continue;
            const sec = el("div", "sec " + lang);
            sec.appendChild(el("span", "lang " + lang, NAMES[lang] + (lang === "hak" && tab.hacc && tab.hacc[prefs.hakAcc] ? "・" + tab.hacc[prefs.hakAcc] : "")));
            for (const e of part.list) {
                if (lang === "zh" && e.p === 3 && prefs.zhPlace !== 2) continue;     // (四川話's own words: with 四川話 only)
                const p = lang === "zh" ? zhParts(e, tab) : (lang === "tw" ? twParts(e, tab) : (lang === "yue" ? yueParts(e) : hakParts(e, tab)));
                const d = el("div", "e");
                if (e.v) d.appendChild(el("div", "via", "華語「" + e.v + "」的台語講法"));
                const head = el("div", "head");
                head.appendChild(segs("han", p.h));
                head.appendChild(segs("r", p.r));
                if (p.r2) head.appendChild(segs("r2", p.r2));
                d.appendChild(head);
                const chips = [];
                if (lang === "zh") {
                    if (e.p === 1) chips.push(["臺灣用語", ""]);
                    else if (e.p === 2) chips.push(["大陸用語", ""]);
                    else if (e.p === 3) chips.push(["四川話", "sc"]);
                    if (prefs.zhPlace === 2) {
                        if (!e.s) chips.push(["普通話讀音", "p0"]);
                        else if (e.q === 1) chips.push(["推算", "p1"]);
                        else if (e.q === 2) chips.push(["預測", "p2"]);
                    }
                }
                if (lang === "hak" && p.guess) chips.push(["這個腔沒有收", "p0"]);
                if (chips.length) {
                    const c = el("div", "chips");
                    for (const [t, k] of chips) c.appendChild(el("span", "chip " + k, t));
                    d.appendChild(c);
                }
                if (e.m) d.appendChild(el("div", "m", e.m));
                if (e.eq && e.eq.length && lang === "zh" && prefs.zhPlace === 2) d.appendChild(el("div", "en", "華語：" + e.eq.join("、")));
                if (prefs.en && e.e) d.appendChild(el("div", "en", e.e));
                d.appendChild(buttons(e.k, e.k.split("\t")[0], p.h));
                sec.appendChild(d);
            }
            if (sec.children.length > 1) holder.appendChild(sec);
        }
        return box;
    }

    // 加到不熟 / 收藏: collected until 傳到 App
    function queued(k, w) { return queue.some(q => q.k === k && q.w === w); }
    function buttons(key, han, hanSegsList) {
        const row = el("div", "btns");
        const u = el("button", "u"), sv = el("button", "s");
        const paint = () => {
            const qu = queued(key, "unknown"), qs = queued(key, "saved");
            u.textContent = qu ? "已選：加到不熟" : "加到不熟";
            u.classList.toggle("on", qu);
            sv.textContent = qs ? "已選：收藏" : "收藏";
            sv.classList.toggle("on", qs);
        };
        paint();
        const go = w => ev => {
            ev.preventDefault(); ev.stopPropagation();
            if (queued(key, w)) queue = queue.filter(q => !(q.k === key && q.w === w));
            else {
                queue.push({ k: key, w, h: han, x: lastSentence || "" });
                // (remembered here too: the rainbow and the colours on pages)
                if (w === "saved" && !saved.some(x => x.h === han)) {
                    saved.push({ h: han, c: (hanSegsList || []).flatMap(sg => [...sg.t].map(() => sg.c || null)) });
                    if (saved.length > 2000) saved = saved.slice(-2000);
                    saveSaved(); pageMarks();
                }
            }
            saveQueue();
            paint();
            const top = card.querySelector(".top");
            if (top) top.replaceWith(topBar(false));
        };
        u.addEventListener("click", go("unknown"));
        sv.addEventListener("click", go("saved"));
        row.append(u, sv);
        return row;
    }

    // opens the app with the words (Safari asks first whether to open it)
    function sendToApp() {
        if (!queue.length) return;
        const ops = queue.map(q => q.x ? [q.k, q.w === "saved" ? "s" : "u", q.x] : [q.k, q.w === "saved" ? "s" : "u"]);
        const json = JSON.stringify(ops);
        const b64 = btoa(String.fromCharCode(...new TextEncoder().encode(json))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
        const a = document.createElement("a");
        a.href = "fangfangcards://safari?ops=" + b64;
        a.style.display = "none";
        (document.body || document.documentElement).appendChild(a);
        a.click();
        a.remove();
        const n = queue.length;
        queue = [];
        saveQueue();
        body.replaceChildren(topBar(false), message("已經把 " + n + " 個詞傳到方方詞卡。如果 App 沒有打開，請再試一次。"));
    }

    // the card's own settings
    function settings() {
        const box = el("div", "set");
        box.appendChild(topBar(true));
        const row = (label, key, options) => {
            const l = el("label");
            l.appendChild(el("span", null, label));
            const s = el("select");
            for (const [v, t] of options) {
                const o = el("option", null, t);
                o.value = String(v);
                if (String(prefs[key]) === String(v)) o.selected = true;
                s.appendChild(o);
            }
            s.addEventListener("change", () => {
                const v = s.value;
                prefs[key] = (v === "true" || v === "false") ? v === "true" : (/^-?\d+(\.\d+)?$/.test(v) ? parseFloat(v) : v);
                savePrefs();
                if (key === "pos") place();
            });
            l.appendChild(s);
            box.appendChild(l);
        };
        const yesNo = [[true, "顯示"], [false, "不顯示"]];
        row("華語", "zh", yesNo);
        row("華語讀音", "zhPlace", [[0, "國語"], [1, "普通話"], [2, "四川話"]]);
        row("華語拼寫", "zhRom", [[1, "注音"], [0, "拼音"]]);
        row("台語", "tw", yesNo);
        row("台語拼寫", "twRom", [[0, "皓羅"], [1, "台羅"], [2, "白話字"], [3, "方音"]]);
        const places = [[-1, "通行"]];
        (placeNames || []).forEach((p, i) => places.push([i, p.slice(0, 2)]));
        row("台語腔口", "twPlace", places);
        row("粵語", "yue", yesNo);
        row("客語", "hak", yesNo);
        row("客語腔", "hakAcc", ["四縣", "海陸", "大埔", "饒平", "詔安", "南四縣"].map((n, i) => [i, n]));
        row("客語拼寫", "hakRom", [[0, "拼音"], [1, "注音"]]);
        row("聲調顏色", "colours", [[true, "開"], [false, "關"]]);
        row("字的大小", "font", [[0.85, "小"], [1, "中"], [1.15, "大"], [1.3, "更大"], [1.5, "最大"]]);
        row("網頁上收藏的詞", "ring", [[false, "不標"], [true, "彩虹框"]]);
        row("網頁上的聲調顏色", "tint", [[false, "不上色"], ["saved", "收藏的詞"], ["all", "全部（華語）"]]);
        row("英文解釋", "en", [[false, "不顯示"], [true, "顯示"]]);
        row("位置", "pos", POSITIONS);
        const size = el("button", "small", "大小還原");
        size.addEventListener("click", ev => { ev.preventDefault(); ev.stopPropagation(); prefs.w = 0; prefs.h = 0; savePrefs(); place(); });
        const sl = el("label"); sl.append(el("span", null, "大小（拖拉角落調整）"), size); box.appendChild(sl);
        box.appendChild(el("div", "note", "加到不熟和收藏的詞會先存在這裡，按「傳到 App」就會打開方方詞卡加進去。台語的聲調顏色照說出來的聲調：只有最後一個音節保持本調，其餘變調；輕聲是灰色。收藏的時候也會記住詞所在的那一句話。"));
        return box;
    }
    const POSITIONS = [["word", "詞的旁邊"], ["tl", "左上角"], ["tr", "右上角"], ["bl", "左下角"], ["br", "右下角"]];
    let placeNames = null;
    ask({ op: "places" }).then(r => { if (r && r.ok) placeNames = r.places; });

    function redraw() { if (last) show(last.rect, last.spot, render(last.res)); }

    let shownRect = null;
    function show(rect, spot, content) {
        ensureHost();
        clearTimeout(hideTimer);
        body.replaceChildren(content);
        card.style.display = "flex";
        shownRect = rect;
        place();
        shownSpot = spot;
    }

    // the card's size (as resized, or by its words) and place (next to the word, or a corner of the screen)
    function place() {
        if (!card || card.style.display === "none") return;
        const vw = window.innerWidth, vh = window.innerHeight;
        card.style.visibility = "hidden";
        card.style.left = "0px"; card.style.top = "0px";
        body.style.zoom = String(prefs.font || 1);        // (the letters bigger or smaller; the card follows)
        const corner = (prefs.pos || "word") !== "word";
        card.style.width = prefs.w ? Math.min(prefs.w, vw - 16) + "px" : "";
        card.style.maxWidth = prefs.w ? "none" : (corner ? "min(900px, calc(100vw - 16px))" : "");
        card.style.height = prefs.h ? Math.min(prefs.h, vh - 16) + "px" : "";
        card.style.maxHeight = prefs.h ? "none" : "";
        const w = card.offsetWidth, h = card.offsetHeight, rect = shownRect || { left: 8, top: 8, bottom: 8 };
        const pos = prefs.pos || "word";
        let left, top;
        if (pos === "word") {
            left = Math.min(Math.max(8, rect.left), vw - w - 8);
            top = rect.bottom + 8;
            if (top + h > vh - 8 && rect.top - h - 8 >= 8) top = rect.top - h - 8;
            top = Math.max(8, Math.min(top, vh - h - 8));
        } else {
            left = pos[1] === "l" ? 12 : vw - w - 12;
            top = pos[0] === "t" ? 12 : vh - h - 12;
            // the word is under where the card would be: the other side of the screen (top ↔ bottom, else left ↔ right)
            const over = (l, t) => shownRect && shownRect.right > l && shownRect.left < l + w && shownRect.bottom > t && shownRect.top < t + h;
            if (over(left, top)) {
                const t2 = pos[0] === "t" ? vh - h - 12 : 12;
                if (!over(left, t2)) top = t2;
                else left = pos[1] === "l" ? vw - w - 12 : 12;
            }
        }
        card.style.left = Math.max(8, left) + "px"; card.style.top = Math.max(8, top) + "px";
        // the corner to drag: the one away from the screen's corner the card is in (next to a word: bottom right)
        grip.className = "grip " + { word: "br", tl: "br", tr: "bl", bl: "tr", br: "tl" }[pos];
        card.style.visibility = "visible";
    }

    // resizing: drag the grip; the opposite corner stays where it is
    function setUpGrip() {
        let start = null;
        grip.addEventListener("pointerdown", e => {
            e.preventDefault(); e.stopPropagation();
            const b = card.getBoundingClientRect();
            start = { x: e.clientX, y: e.clientY, w: b.width, h: b.height, l: b.left, t: b.top, side: grip.className.split(" ")[1] };
            grip.setPointerCapture(e.pointerId);
        });
        grip.addEventListener("pointermove", e => {
            if (!start) return;
            e.preventDefault(); e.stopPropagation();
            const vw = window.innerWidth, vh = window.innerHeight;
            const dx = e.clientX - start.x, dy = e.clientY - start.y;
            const right = start.side[1] === "r", bottom = start.side[0] === "b";
            const w = Math.max(220, Math.min(vw - 16, start.w + (right ? dx : -dx)));
            const h = Math.max(120, Math.min(vh - 16, start.h + (bottom ? dy : -dy)));
            card.style.width = w + "px"; card.style.maxWidth = "none";
            card.style.height = h + "px"; card.style.maxHeight = "none";
            if (!right) card.style.left = (start.l + start.w - w) + "px";
            if (!bottom) card.style.top = (start.t + start.h - h) + "px";
        });
        const end = e => {
            if (!start) return;
            e.stopPropagation();
            const b = card.getBoundingClientRect();
            prefs.w = Math.round(b.width); prefs.h = Math.round(b.height);
            start = null;
            savePrefs();
        };
        grip.addEventListener("pointerup", end);
        grip.addEventListener("pointercancel", end);
    }
    function hide() {
        clearTimeout(hideTimer);
        if (card) card.style.display = "none";
        unmark();
        shownSpot = "";
    }
    function hideSoon() {
        clearTimeout(hideTimer);
        if (card && card.style.display !== "none" && !card.querySelector(".set")) hideTimer = setTimeout(hide, HIDE);
    }
    const inCard = e => host && e.composedPath && e.composedPath().includes(host);

    // ── the Pencil (or a trackpad / mouse) hovering ─────────────────────────────────────────
    // (the Pencil, a trackpad or a mouse; on the Mac, Safari may send only mouse events)
    let lastPointer = 0;
    document.addEventListener("pointermove", e => {
        if (e.pointerType === "touch") return;
        lastPointer = Date.now();
        hover(e);
    }, { capture: true, passive: true });
    document.addEventListener("mousemove", e => {
        if (Date.now() - lastPointer < 300) return;               // (already handled as a pointer event)
        hover(e);
    }, { capture: true, passive: true });

    function hover(e) {
        if (!prefs.on) return;                                    // (turned off with its button in Safari's toolbar)
        if (e.buttons !== 0) return;                              // writing / dragging, not hovering
        if (!metaP) getMeta();                                    // (the Pencil is near: the tables read already)
        if (inCard(e)) { clearTimeout(hideTimer); clearTimeout(dwellTimer); return; }
        const hit = charAt(e.clientX, e.clientY);
        if (!hit || !isHan(hit.cp)) { clearTimeout(dwellTimer); lastSpot = ""; hideSoon(); return; }
        const spot = hit.off + "@" + Math.round(hit.rect.left) + "," + Math.round(hit.rect.top);
        if (spot === shownSpot) { clearTimeout(hideTimer); return; }
        if (spot === lastSpot) return;
        lastSpot = spot;
        clearTimeout(dwellTimer);
        prefetch(hit.cp);
        const go = () => {
            const text = textFrom(hit.node, hit.off);
            if (text) lookup(text, hit.rect, spot, { node: hit.node, off: hit.off });
        };
        // (moving along a line with the card showing: the next word at once)
        if (card && card.style.display !== "none") go(); else dwellTimer = setTimeout(go, DWELL);
    }

    document.addEventListener("pointerleave", e => { if (e.pointerType === "pen") { clearTimeout(dwellTimer); lastSpot = ""; } }, true);
    document.addEventListener("pointerdown", e => { if (!inCard(e)) { clearTimeout(dwellTimer); hide(); } }, true);
    window.addEventListener("scroll", e => {
        if (host && e.target === host) return;          // (scrolling inside the card)
        clearTimeout(dwellTimer); lastSpot = ""; hide();
    }, { passive: true, capture: true });
    document.addEventListener("keydown", e => { if (e.key === "Escape") hide(); }, true);

    // ── selecting text with a finger (for iPads without Pencil hover) ───────────────────────
    let selTimer = null;
    document.addEventListener("selectionchange", () => {
        clearTimeout(selTimer);
        selTimer = setTimeout(() => {
            if (!prefs.on) return;
            const sel = document.getSelection();
            if (!sel || sel.isCollapsed || sel.rangeCount === 0) return;
            const s = sel.toString().trim();
            if (!s || [...s].length > MAXLEN || !isHan(s.codePointAt(0))) return;
            const rect = sel.getRangeAt(0).getBoundingClientRect();
            const spot = "sel:" + s + "@" + Math.round(rect.left) + "," + Math.round(rect.top);
            if (spot === shownSpot) return;
            lookup(s, rect, spot);
        }, 600);
    });
})();
