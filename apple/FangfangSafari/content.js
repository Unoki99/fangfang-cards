// 方方詞卡 查詞: hold the Apple Pencil (or a trackpad pointer) still over a Chinese character for a moment, and a card
// with the 華語 and 台語 words starting there pops up next to it. Selecting text with a finger works too.
// The words are inside the extension (made from the app's data when it was installed); the card writes them out
// in the spellings chosen in its own 設定. 加到不熟 and 收藏 are collected here; 傳到 App opens the app and hands
// them over (no shared folder with the app is needed, so it also works with Sideloadly).
(() => {
    if (window.__fangfangLookup) return;
    window.__fangfangLookup = true;
    // (the add-on updated, or turned off and on, while the page is open: the new copy takes over, and this one,
    // if it's the old one, stops answering, so there's never two cards or two subtitle panels)
    const GEN = String(Math.random()).slice(2);
    document.documentElement.dataset.ffGen = GEN;
    const alive = () => document.documentElement.dataset.ffGen === GEN;

    const DWELL = 60;             // ms the Pencil stays on a character before the card shows (none when it's already showing)
    const HIDE = 900;             // ms after leaving the word and the card before the card goes
    const MAXLEN = 12;
    const isHan = cp => (cp >= 0x3400 && cp <= 0x9fff) || (cp >= 0xf900 && cp <= 0xfaff) || (cp >= 0x20000 && cp <= 0x3ffff);
    // 瑞典語: a letter of a Latin-script word (a-z, å, ä, ö, é…)
    const isLat = cp => (cp >= 0x41 && cp <= 0x5a) || (cp >= 0x61 && cp <= 0x7a) || (cp >= 0xc0 && cp <= 0x24f && cp !== 0xd7 && cp !== 0xf7);

    // ── settings (the card's own; kept in the extension) ────────────────────────────────────
    // pos: where the card shows (word: next to the word; tl / tr / bl / br: a corner of the screen); w, h: its size
    // when resized (0 = by its words)
    // on: the pop-up on at all (its button in Safari's toolbar); font: the size of the letters (1 = normal);
    // yue / hak: 粵語 and 客語 (hakAcc: the accent, hakRom: 0 拼音 / 1 注音); ring: a rainbow around the words saved
    // here when they're on a page; tint: the characters of saved words in their tone colours on the page
    const DEFAULTS = { pcLink: false, pageAnno: false, on: true, zhPlace: 0, zhRom: 1, twRom: 1, twPlace: -1, colours: true, en: false, zh: true, tw: false,
        yue: false, hak: false, hakAcc: 0, hakRom: 0, sv: false, svGuess: true, eng: false, engRom: 0, engEn: true, engZh: true, engSv: false, font: 1, ring: false, tint: false, pos: "word", w: 0, h: 0,
        // 影片字幕 (YouTube, Viki): the panel on; the video stops while a word is looked up in it; the subtitles on
        // the video itself hidden while the panel shows them
        subs: true, subsPause: true, subsHideVideo: true,
        // onlyNew: the tone colours (on pages and in subtitles) only on words you don't know yet (known: from the app,
        // and the ones marked 認識 on the card here)
        onlyNew: false,
        // the subtitles' words marked (reading, meaning, colour): "new" the ones you don't know, "rare" the less
        // common ones (not among the subsRare most common words), "both" the ones that are both
        subsMark: "new", subsRare: 3000,
        // subsFlow: the subtitles in one row at the bottom, flowing sideways (always so when the video is full screen)
        subsFlow: false,
        // subsFlowStyle: that row "scroll" (moving sideways all the time) or "swap" (one line at a time, the next one
        // coming up into its place, as in the app's 卡拉 OK; the line after it small underneath)
        subsFlowStyle: "scroll",
        // subsSwell: the words of the line being said get bigger as it goes, as if timed like the lyrics (the line's
        // time shared out over its characters)
        subsSwell: false,
        // subsSwapNext: 一句一句往上換 shows the next line, small, at the bottom (off: more room for the line being said)
        subsSwapNext: true,
        // subsOffset: the subtitles shown this many seconds earlier (+) or later (−), for every video
        subsOffset: 0,
        // that row's height as dragged by its top edge (0 = as its words need); it keeps the whole width, centred
        subsFlowH: 0,
        // over / under the words you don't know in the subtitles: their reading, and their meaning (English or 中文, as 英文 is set)
        subsRd: true, subsGl: true,
        // the reading's size, against the characters'
        subsRdSize: 0.56,
        // subsGlSize: the meaning under a word, against the word's size
        subsGlSize: 0.5,
        // subsEnZh: English subtitles: the Chinese word for each English one under it (the language on)
        subsEnZh: true,
        // 簡體 subtitles shown (and read) in 繁體
        subsTrad: true,
        // the row at the bottom: a row of the same size at the top with the cards of the line's words you don't know
        subsDefs: false,
        // the panels' background: "tint" the colour of what's under them (the video, the page), kept dark enough to
        // read; "dark" always dark; "clear" none: only the subtitle lines (and buttons, cards) in boxes of their own
        subsBg: "dark",
        // the language the subtitles are read in: "auto" (from the subtitles' own language), or zh / tw / yue / hak
        subsLang: "auto",
        // keyKnown / keyNew: with the pointer on a word, the key that marks it 認識, and the one that marks it 不熟 and
        // saves it (with its sentence); keys: on or off
        keys: true, keyKnown: "a", keyNew: "s",
        // subsFont: the subtitles' size (its own, apart from the card's; A− / A+ on the panel)
        subsFont: 1,
        // subs2: a second language shown under each line, small and grey ("en", "zh-hant"…; "" none), when the video has it
        subs2: "",
        // subsColours: the tone colours in the subtitles (apart from 聲調顏色, the card's and the page's)
        subsColours: true,
        // subsBar: the panel's buttons shown (the gear in its corner hides them, and brings them back)
        subsBar: true,
        // uiLang: the add-on's own words in 中文 ("zh") or English ("en")
        uiLang: "zh" };
    let prefs = { ...DEFAULTS };
    /// the add-on's own words in English (介面語言 English; ui-en.js), else as they are
    const ffT = s => prefs.uiLang === "en" && typeof FF_EN === "object" && Object.prototype.hasOwnProperty.call(FF_EN, s) ? FF_EN[s] : s;
    let queue = [];               // [{k, w: "unknown" | "saved", h, x: the sentence}] waiting for 傳到 App
    let saved = [];               // [{h, c: [colours]}]: every word saved here (for the rainbow and the colours on the page)
    // the words you know (認識) and are learning (不熟) in the app, sent with its 把認識的詞傳到 Safari 查詞: the
    // subtitle panel marks the others and tells how much of a video you know
    let knownSet = null, learnSet = new Set();
    let localKnown = new Set();   // 認識 on the card here (sent to the app with 傳到 App, too)
    let knownBy = {}, learnBy = {};   // the same, by language (tw, zh, yue, hak, …)
    // 認識 here is kept by language ("tw:食"): a word known in 華語 isn't known in 台語 (a word without "xx:", from
    // before, counts for 華語 only)
    const localHas = (w, l) => localKnown.has(l + ":" + w) || (l === "zh" && localKnown.has(w));
    const localAdd = (w, l) => { localKnown.add(l + ":" + w); };
    const localDel = (w, l) => { localKnown.delete(l + ":" + w); if (l === "zh") localKnown.delete(w); };
    /// which language a key is of (as the app tells them): after the tab 粵 / 客 / 日 / 瑞, 注音 (華語), or letters (台語)
    function keyLang(k) {
        const t = (k || "").split("\t")[1] || "";
        const c = t.charAt(0), cp = t.codePointAt(0) || 0;
        if (c === "粵") return "yue";
        if (c === "客") return "hak";
        if (c === "日") return "ja";
        if (c === "瑞") return "sv";
        if (c === "英") return "eng";
        if ((cp >= 0x3100 && cp <= 0x312F) || (cp >= 0x31A0 && cp <= 0x31BF) || c === "˙" || c === "字") return "zh";
        return "tw";
    }
    // (a word of one language: known there; without the app's words by language, known in any)
    const isKnownIn = (w, l) => localHas(w, l) || (knownBy[l] ? knownBy[l].has(w) : !!(knownSet && knownSet.has(w)));
    const learnIn = (w, l) => learnBy[l] ? learnBy[l].has(w) : learnSet.has(w);
    let watchCache = {};          // {"2026-11-14": minutes watched with the subtitle panel}, sent with 傳到 App
    // (the sentences the app's 不熟 / 收藏 words were chosen from, of the words in no 影片詞組 yet: normalized
    // sentence → their keys. Found again in a video's subtitles, those words go into that video's group)
    let foundBy = new Map(), grouped = new Set();
    const sentNorm = t => String(t || "").replace(/\s+/g, "");
    function setKnown(o) {
        foundBy = new Map();
        for (const [k, x] of (o && o.f) || []) {
            const n = sentNorm(x);
            if (!n) continue;
            if (!foundBy.has(n)) foundBy.set(n, []);
            if (!foundBy.get(n).includes(k)) foundBy.get(n).push(k);
        }
        if (!o || !o.k) { knownSet = null; learnSet = new Set(); knownBy = {}; learnBy = {}; return; }
        knownSet = new Set(Object.values(o.k).flat());
        learnSet = new Set(Object.values(o.u || {}).flat());
        knownBy = {}; learnBy = {};
        for (const l of ["tw", "zh", "yue", "hak", "ja", "sv", "eng"]) {
            knownBy[l] = new Set(o.k[l] || []);
            learnBy[l] = new Set((o.u || {})[l] || []);
        }
    }
    const store = browser.storage && browser.storage.local;
    if (store) {
        store.get(["ffPrefs", "ffQueue", "ffSaved", "ffKnown", "ffWatch", "ffKnownLocal", "ffGrouped", "ffSeen", "ffSeenAll"]).then(r => {
            seenCache = r.ffSeen || {};
            seenAll = r.ffSeenAll || {};
            localKnown = new Set(r.ffKnownLocal || []);
            grouped = new Set(r.ffGrouped || []);
            watchCache = r.ffWatch || {};
            prefs = fixPrefs(r.ffPrefs);
            queue = r.ffQueue || [];
            saved = r.ffSaved || [];
            setKnown(r.ffKnown);
            pageMarks();
            pcLinkUpdate();
        }).catch(() => {});
        // (changed in the extension's own window, from its button in Safari's toolbar, or on another page)
        if (browser.storage.onChanged) browser.storage.onChanged.addListener((ch, area) => {
            if (ch.ffPrefs) { prefs = fixPrefs(ch.ffPrefs.newValue); if (isOpen() && last && !card.querySelector(".set")) redraw(); pcLinkUpdate(); }
            // (a dictionary installed or taken away in 設定 → 詞典: its files read again)
            if (ch.ffData) { metaP = null; shardP.clear(); foundP.clear(); entryP.clear(); warmed.clear(); }
            if (ch.ffQueue) queue = ch.ffQueue.newValue || [];
            if (ch.ffSaved) saved = ch.ffSaved.newValue || [];
            if (ch.ffWatch) watchCache = ch.ffWatch.newValue || {};
            if (ch.ffSeen) seenCache = ch.ffSeen.newValue || {};
            if (ch.ffSeenAll) seenAll = ch.ffSeenAll.newValue || {};
            if (ch.ffKnownLocal) { localKnown = new Set(ch.ffKnownLocal.newValue || []); pageMarks(); if (subs && subs.key) subsColour(subs.key); }
            if (ch.ffKnown) { setKnown(ch.ffKnown.newValue); if (subs && subs.key) subsColour(subs.key); pageMarks(); }
            if (ch.ffPrefs || ch.ffSaved) { if (!prefs.on && !(subs && subs.pausedBy) && !subsCard()) hide(); pageMarks(); }
            if (ch.ffPrefs && subs && subs.panel) {
                const o = ch.ffPrefs.oldValue || {}, n = ch.ffPrefs.newValue || {};
                subsSize(); subsLayout();
                subsTint();
                if (o.uiLang !== n.uiLang) { subsHeader(); subsStudy(); }
                if (["subsRd", "subsGl", "subsLang", "subsTrad", "subsMark", "subsRare", "subsEnZh", "zh", "tw", "yue", "hak", "sv", "eng", "engRom", "engEn", "engZh", "engSv", "en", "zhRom", "zhPlace", "twRom", "twPlace", "hakAcc", "hakRom", "colours", "subsColours", "onlyNew"].some(k => o[k] !== n[k])) subsRedraw();
            }
        });
    }
    // the app's 把認識的詞傳到 Safari 查詞 opens example.com#fangfang-known=<the words, packed>: kept here
    if (store && location.hostname === "example.com" && location.hash.startsWith("#fangfang-known=")) {
        (async () => {
            try {
                const b = location.hash.slice("#fangfang-known=".length).replace(/-/g, "+").replace(/_/g, "/");
                const bin = Uint8Array.from(atob(b + "===".slice((b.length + 3) % 4)), c => c.charCodeAt(0));
                const txt = await new Response(new Blob([bin]).stream().pipeThrough(new DecompressionStream("deflate-raw"))).text();
                const o = JSON.parse(txt);
                o.at = Date.now();
                await store.set({ ffKnown: o });
                const n = Object.values(o.k || {}).reduce((a, x) => a + x.length, 0);
                const u = Object.values(o.u || {}).reduce((a, x) => a + x.length, 0);
                history.replaceState(null, "", location.pathname);
                const box = document.createElement("div");
                box.style.cssText = "position:fixed;inset:0;display:flex;align-items:center;justify-content:center;background:#16171d;color:#eef;" +
                    "font:20px/1.6 -apple-system,'PingFang TC',sans-serif;z-index:2147483647;text-align:center;padding:24px";
                box.textContent = ffT("方方詞卡 查詞 收到了：認識的詞 ") + n + ffT(" 個、不熟的詞 ") + u + ffT(" 個。影片字幕裡沒學過的詞會有底線，面板上會顯示你懂多少。這一頁可以關掉了。");
                document.documentElement.appendChild(box);
            } catch (e) {}
        })();
    }
    const LANGS_ONE = ["zh", "tw", "yue", "hak", "sv", "eng"];
    /// the one language on
    const activeLang = () => LANGS_ONE.find(l => prefs[l]) || "zh";
    // the tone colours: 聲調顏色 (the card's and the page's); the subtitles have their own (subsColours), used while
    // their words are made (colFor)
    let colFor = null;
    const colOn = () => colFor === null ? !!prefs.colours : colFor;
    const subsCol = () => prefs.subsColours !== false;
    function fixPrefs(p) {
        const out = { ...DEFAULTS, ...(p || {}) };
        // (Firefox: the panel without its rows of buttons, only the gear and 生詞 beside the subtitles, once; the
        // gear's 面板上的按鈕 brings them back)
        if (/Firefox\//.test(navigator.userAgent) && !out.subsBarFx) { out.subsBar = false; out.subsBarFx = true; }
        if (out.corner === true && (!p || !p.pos)) out.pos = "tl";      // (the older 左上角 setting)
        delete out.corner;
        // one language at a time: the first one on (none: 華語)
        const on = LANGS_ONE.find(l => p && p[l]) || LANGS_ONE.find(l => out[l]) || "zh";
        for (const l of LANGS_ONE) out[l] = l === on;
        return out;
    }
    const savePrefs = () => store && store.set({ ffPrefs: prefs }).catch(() => {});
    const saveQueue = () => store && store.set({ ffQueue: queue }).catch(() => {});
    const saveSaved = () => store && store.set({ ffSaved: saved }).catch(() => {});
    const saveKnownLocal = () => store && store.set({ ffKnownLocal: [...localKnown].slice(-20000) }).catch(() => {});

    let host = null, root = null, card = null, body = null, grip = null;
    let dwellTimer = null, hideTimer = null, lastSpot = "", shownSpot = "", busy = 0;
    let shownAt = 0;              // (when the card last opened: a tap on the subtitles' words keeps it open a moment)
    /// the card open for a word of the subtitle panel (closed only by a tap elsewhere, Escape, or the page scrolling)
    const subsCard = () => shownSpot.startsWith("subs:");
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

    // 瑞典語: the whole word around a letter (bil|arna: from its first letter to its last), and where it starts
    function latWordAt(node, off) {
        const t = node.data;
        let a = off, b = off;
        while (a > 0 && isLat(t.charCodeAt(a - 1))) a--;
        while (b < t.length && isLat(t.charCodeAt(b))) b++;
        const w = t.slice(a, b);
        return w ? { text: w, start: a } : null;
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
    // (瑞典語: by the word's first two letters, in small letters)
    function svShard(w, meta) {
        const n = (meta && meta.shards) || 256;
        return `d-sv-${String((w.charCodeAt(0) * 31 + (w.length > 1 ? w.charCodeAt(1) : 0)) % n).padStart(3, "0")}.json`;
    }
    // (the languages looked up: the ones chosen that have a dictionary)
    // (Chinese characters with 瑞典語 or 英語 on: the subtitles' Chinese language when one is set for them, else
    // 華語, so a tap on a Chinese word still shows it instead of nothing)
    const findLangs = meta => {
        const has = l => meta[l] === undefined || meta[l] > 0;
        const on = ["zh", "tw", "yue", "hak"].filter(l => prefs[l] && has(l));
        if (on.length) return on;
        const sl = ["zh", "tw", "yue", "hak"].includes(prefs.subsLang) ? prefs.subsLang : "zh";
        return [sl, "zh"].filter((l, i, a) => a.indexOf(l) === i && has(l)).slice(0, 1);
    };
    // (the files for a character read ahead where they're kept, in the add-on: only the words found come to the page.
    // Sending whole files to the page on every new character made hovering slow on long pages in Firefox)
    let warmed = new Set();
    function prefetch(cp) {
        getMeta().then(m => {
            if (!m) return;
            const i = cp % (m.shards || 256);
            if (warmed.has(i)) return;
            warmed.add(i);
            if (warmed.size > 80) warmed = new Set([i]);
            ask({ op: "warm", cp, langs: findLangs(m) });
        });
    }
    // one entry of a file (sv / en words), asked for alone
    const entryP = new Map();
    function getEntry(name, key) {
        const k = name + "|" + key;
        if (!entryP.has(k)) {
            entryP.set(k, ask({ op: "entry", name, key }).then(r => (r && r.ok) ? r.data : null));
            if (entryP.size > 2000) entryP.delete(entryP.keys().next().value);
        }
        return entryP.get(k);
    }

    // 瑞典語: the word, or one of its forms (bilarna → bil)
    async function findSv(text) {
        const meta = await getMeta();
        if (!meta) return { ok: true, ready: false };
        const out = { ok: true, ready: true, tab: meta };
        const w = text.toLowerCase();
        if (!w || !prefs.sv || !meta.sv) return out;
        const sh = await getFile(svShard(w, meta));
        if (sh && sh[w]) {
            // (a word the dictionary has without its parts, Arvsfonden: worked out all the same)
            const list = [];
            for (const e of sh[w]) {
                if (svMs(e).length <= 1 && !svHeadOf(e).includes(" ") && w.length >= 5) {
                    const est = await svEstimate(w, meta, true);
                    if (est && est.ms.length > 1) { list.push({ ...e, est, inDict: true }); continue; }
                }
                list.push(e);
            }
            out.sv = { w: text, list, form: text };
            return out;
        }
        // a word the dictionary doesn't have, worked out by rules from words it has: omhändertagandet = omhänderta
        // + -ande (a verb made a noun) + -t (the noun's definite form); varningsområdet = varning + s + område + t
        const est = await svEstimate(w, meta);
        if (est) {
            const words = est.parts.filter(p => !p.link);
            const one = words.length === 1 ? words[0].e : null;
            const gl = words.map(p => { const g = svGloss(p.e); return svHeadOf(p.e) + (g ? "（" + g + "）" : ""); });
            out.sv = { w: text, form: text, list: [{ k: one ? one.k : "", est, w: SV_CLS_NAME[est.cls] || "", m: one ? one.m : gl.join(" ＋ "), q: one ? one.q : "", e: one ? one.e : "" }] };
            return out;
        }
        const inf = await svInflected(w, meta);
        if (inf) { out.sv = { w: text, list: [inf], form: text }; return out; }
        return out;
    }

    // ── English → the Chinese languages: the words whose English meaning it is ("eat" → 吃, 食…) ─────────────────
    // English endings, longest first, and what the word may have had before them ("" as it is; "y": happily → happy)
    const EN_ENDS = [["fully", ["ful"]], ["ically", ["ic", "ical"]], ["ily", ["y"]], ["ally", ["al", ""]], ["ly", ["", "le", "e"]],
        ["iness", ["y"]], ["ness", [""]], ["ments", [""]], ["ment", [""]], ["ities", ["ity"]], ["ity", ["", "e"]],
        ["ied", ["y"]], ["ies", ["y"]], ["ier", ["y"]], ["iest", ["y"]], ["ing", ["", "e"]], ["est", ["", "e"]], ["ers", ["", "e"]],
        ["er", ["", "e"]], ["ed", ["", "e"]], ["es", ["", "e"]], ["s", [""]], ["able", ["", "e"]], ["ible", ["", "e"]]];
    // ── 英語 (en.json, ECDICT): the word, or one of its forms (ran → run), in small letters; else without its ending ──
    function engShard(w, meta) { return svShard(w, meta).replace("d-sv-", "d-eng-"); }
    async function findEng(text) {
        const meta = await getMeta();
        if (!meta) return { ok: true, ready: false };
        const out = { ok: true, ready: true, tab: meta };
        const w = text.toLowerCase();
        if (!prefs.eng || !meta.eng || !w) return out;
        const get = async b => { const sh = await getFile(engShard(b, meta)); return (sh && sh[b]) || null; };
        let list = await get(w);
        // (a form the dictionary doesn't list: eats, happily → happy, stopped → stop)
        if (!list) for (const [end, adds] of EN_ENDS) {
            if (!w.endsWith(end) || w.length - end.length < 2) continue;
            const st = w.slice(0, -end.length);
            for (const a of adds) { if (!list && st + a !== w) list = await get(st + a); }
            if (!list && st.length > 2 && st[st.length - 1] === st[st.length - 2]) list = await get(st.slice(0, -1));
            if (list) break;
        }
        if (list) out.eng = { w: text, list, form: text };
        return out;
    }
    // a Latin word: 英語 or 瑞典語, whichever is on
    async function findLatin(text) {
        if (prefs.eng) return await findEng(text);
        return prefs.sv ? await findSv(text) : { ok: true, ready: true };
    }

    // ── 瑞典語 words worked out by rules (the same as the app's ZhDict.svEstimate) ─────────────────────────────────
    const SV_CLS = { "名詞": "n", "專有名詞": "n", "動詞": "v", "形容詞": "a", "序數詞": "a", "副詞": "d" };
    const SV_CLS_NAME = { n: "名詞", v: "動詞", a: "形容詞", d: "副詞" };
    // [text, kind (e ending, s suffix), what it's added to, what the word is then, what it does]
    const SV_RULES = [
        ["arna", "e", "n", "n", "名詞複數的限定形（the …s）"], ["erna", "e", "n", "n", "名詞複數的限定形（the …s）"], ["orna", "e", "n", "n", "名詞複數的限定形（the …s）"],
        ["ar", "e", "n", "n", "名詞複數"], ["er", "e", "n", "n", "名詞複數"], ["or", "e", "n", "n", "名詞複數"], ["na", "e", "n", "n", "名詞複數的限定形"],
        ["en", "e", "n", "n", "名詞單數的限定形（en-詞：the）"], ["et", "e", "n", "n", "名詞單數的限定形（ett-詞：the）"], ["n", "e", "n", "n", "名詞的限定形（the）"],
        ["t", "e", "n", "n", "名詞單數的限定形（ett-詞：the）"], ["s", "e", "n", "n", "所有格（…的）"],
        ["t", "e", "a", "a", "形容詞的中性（ett-詞）或副詞"], ["a", "e", "a", "a", "形容詞的複數或限定形"], ["e", "e", "a", "a", "形容詞的限定形（男性）"],
        ["are", "e", "ad", "a", "比較級（更…）"], ["ast", "e", "ad", "a", "最高級（最…）"], ["aste", "e", "a", "a", "最高級的限定形（最…的）"],
        ["ar", "e", "v", "v", "動詞現在式"], ["er", "e", "v", "v", "動詞現在式"], ["r", "e", "v", "v", "動詞現在式"],
        ["ade", "e", "v", "v", "動詞過去式"], ["de", "e", "v", "v", "動詞過去式"], ["te", "e", "v", "v", "動詞過去式"],
        ["at", "e", "v", "v", "動詞完成式（har …at）"], ["it", "e", "v", "v", "動詞完成式（har …it）"], ["s", "e", "v", "v", "被動或相互（-s 動詞）"],
        ["ad", "e", "v", "a", "過去分詞（被…的）"], ["en", "e", "v", "a", "過去分詞（被…的）"],
        ["ande", "s", "v", "n", "把動詞變成名詞：那個動作（…的行為）"], ["ende", "s", "v", "n", "把動詞變成名詞：那個動作（…的行為）"],
        ["ning", "s", "v", "n", "把動詞變成名詞：動作或它的結果"], ["ing", "s", "v", "n", "把動詞變成名詞：動作或它的結果"],
        ["are", "s", "v", "n", "把動詞變成名詞：做這件事的人或工具"], ["else", "s", "v", "n", "把動詞變成名詞：動作或它的結果"],
        ["nad", "s", "v", "n", "把動詞變成名詞：動作或它的結果"], ["eri", "s", "vn", "n", "名詞：地方、行業或一種行為"],
        ["bar", "s", "v", "a", "把動詞變成形容詞：可以被…的"], ["sam", "s", "vn", "a", "變成形容詞：有…傾向的"],
        ["het", "s", "a", "n", "把形容詞變成名詞：…性、…度"], ["lig", "s", "nv", "a", "變成形容詞：…的、像…的"],
        ["ig", "s", "n", "a", "把名詞變成形容詞：有…的"], ["isk", "s", "n", "a", "把名詞變成形容詞：…的、…式的"],
        ["lös", "s", "n", "a", "把名詞變成形容詞：沒有…的"], ["fri", "s", "n", "a", "把名詞變成形容詞：無…的"],
        ["full", "s", "n", "a", "把名詞變成形容詞：充滿…的"], ["aktig", "s", "na", "a", "變成形容詞：像…的、有點…"],
        ["mässig", "s", "n", "a", "把名詞變成形容詞：依…的"], ["skap", "s", "na", "n", "變成名詞：…關係、…身分"],
        ["dom", "s", "an", "n", "變成名詞：…狀態、…時期"], ["itet", "s", "a", "n", "把形容詞變成名詞：…性"],
        ["ism", "s", "an", "n", "變成名詞：…主義"], ["ist", "s", "n", "n", "名詞：…者、…家"], ["inna", "s", "n", "n", "名詞：女…"],
        ["vis", "s", "na", "d", "變成副詞：以…方式、按…"], ["era", "s", "n", "v", "把名詞變成動詞"],
    ];
    function svCompoundMs(parts) {
        const ms = [];
        for (const p of parts) {
            if (p.link) { ms.push({ t: p.t, k: "l", g: null }); continue; }
            // (each word of a compound whole, varning|s|område|t: what each word is made of is in its own entry)
            const g = svGloss(p.e);
            ms.push(...svForForm(p.t, svHeadOf(p.e), []).map(m => m.k === "r" ? { ...m, g } : m));
        }
        return ms;
    }
    async function svEstimate(w, meta, skipSelf) {
        if (w.length < 3 || w.length > 40 || w.includes(" ")) return null;
        const memo = new Map();
        const prefixes = Object.keys(SV_AFFIX.p).sort((a, b) => b.length - a.length);
        async function core(s, prefixOK) {
            const out = [];
            for (const e of (skipSelf && s === w ? [] : (await svWord(s, meta)) || [])) {
                if (svHeadOf(e).includes(" ")) continue;
                const c = SV_CLS[e.w] || "any";
                out.push({ ms: svForForm(s, svHeadOf(e), svMs(e)).map(m => m.k === "r" && !m.g ? { ...m, g: svGloss(e) } : m), cls: c, parts: [{ t: s, e, link: false }], steps: [], cost: c === "any" ? 1 : 0, adj: 0 });
            }
            if (out.length) return out;
            const p = await svCompound(s, meta);
            if (p) { const last = p[p.length - 1].e; return [{ ms: svCompoundMs(p), cls: SV_CLS[last.w] || "any", parts: p, steps: [], cost: 3 * (p.filter(x => !x.link).length - 1), adj: 0 }]; }
            if (prefixOK) {
                for (const pre of prefixes) {
                    if (!s.startsWith(pre) || s.length - pre.length < 3) continue;
                    const r = await core(s.slice(pre.length), false);
                    if (r.length) return r.map(x => ({ ...x, ms: [{ t: pre, k: "p", g: null }, ...x.ms],
                        steps: [{ t: pre, k: "p", zh: "前綴：" + SV_AFFIX.p[pre], cls: x.cls }, ...x.steps], cost: x.cost + 2 }));
                }
            }
            return out;
        }
        function onto(base, b, ms) {
            if (b === base) return ms;
            const out = svForForm(base, b, ms);
            if (out.length >= 2 && out[out.length - 1].k === "e" && out[out.length - 1].t.length === 1 && out[out.length - 2].k === "r") {
                out[out.length - 2] = { ...out[out.length - 2], t: out[out.length - 2].t + out[out.length - 1].t };
                out.pop();
            }
            return out;
        }
        // (the fewest guesses; then the fewest letters added to or taken off a base: tal → tala; then the fewest parts)
        const better = (x, y) => x.cost !== y.cost ? x.cost < y.cost : (x.adj !== y.adj ? x.adj < y.adj : x.ms.length < y.ms.length);
        async function analyze(s) {
            if (memo.has(s)) return memo.get(s);
            memo.set(s, []);
            const best = {};
            const keep = x => { const o = best[x.cls]; if (!o || better(x, o)) best[x.cls] = x; };
            for (const x of await core(s, true)) keep(x);
            for (const [t, k, from, to, zh] of SV_RULES) {
                if (!s.endsWith(t) || s.length - t.length < 2) continue;
                const base = s.slice(0, -t.length);
                const cands = [base];
                if (from.includes("v") || from.includes("n")) cands.push(base + "a");
                if (from.includes("n")) cands.push(base + "e");
                if (from.includes("v") && /[gd]$/.test(base) && base.length > 2) cands.push(base.slice(0, -1));
                // (vänn|en → vän: a doubled last letter as one)
                if (base.length > 3 && base[base.length - 1] === base[base.length - 2] && !/[aeiouyåäö]/.test(base[base.length - 1])) cands.push(base.slice(0, -1));
                for (const b of cands) {
                    for (const r of await analyze(b)) {
                        if (!from.includes(r.cls) && r.cls !== "any") continue;
                        keep({ ms: [...onto(base, b, r.ms), { t, k, g: null }], cls: to, parts: r.parts,
                               steps: [...r.steps, { t, k, zh, cls: to }], cost: r.cost + 1 + (r.cls === "any" ? 1 : 0), adj: r.adj + (b === base ? 0 : 1) });
                    }
                }
            }
            const out = Object.values(best).sort((x, y) => better(x, y) ? -1 : (better(y, x) ? 1 : 0));
            memo.set(s, out);
            return out;
        }
        const top = (await analyze(w))[0];
        if (!top || (!top.steps.length && top.parts.length < 2)) return null;
        return top;
    }

    // ── 瑞典語 words the dictionary doesn't have (the same as the app's ZhDict.svInflected / svCompound) ──
    async function svWord(s, meta) { const sh = await getFile(svShard(s, meta)); return (sh && sh[s]) || null; }
    const svHeadOf = e => e.k.split("\t")[0];
    async function svHead(s, meta) {
        const l = await svWord(s, meta);
        return (l && l.find(e => svHeadOf(e).toLowerCase() === s && !svHeadOf(e).includes(" "))) || null;
    }
    const SV_ENDS = ["arnas", "ernas", "ornas", "arna", "erna", "orna", "ens", "ets", "en", "et", "na", "ar", "er", "or", "ade", "de", "te", "t", "n", "s"];
    async function svInflected(s, meta) {
        for (const end of SV_ENDS) {
            if (!s.endsWith(end) || s.length - end.length < 2) continue;
            const st = s.slice(0, -end.length);
            const tries = [st];
            if (st.length > 2 && st[st.length - 1] === st[st.length - 2]) tries.push(st.slice(0, -1));
            if (end === "n") tries.push(st + "e");
            for (const t of tries) { const e = await svHead(t, meta); if (e) return e; }
        }
        return null;
    }
    async function svLast(s, meta) {
        const l = await svWord(s, meta);
        // (a form of a shorter word first: områden → område + n, though the dictionary also has områden itself)
        const base = l && l.find(e => { const h = svHeadOf(e).toLowerCase(); return h.length < s.length && s.startsWith(h) && !h.includes(" "); });
        if (base) return base;
        const h = await svHead(s, meta);
        if (h) return h;
        // (the endings are the rules' to work out: svEstimate)
        return (l && l.find(e => !svHeadOf(e).includes(" "))) || null;
    }
    async function svFront(s, meta) { return (await svHead(s, meta)) || (await svHead(s + "a", meta)) || (await svHead(s + "e", meta)); }
    async function svCompound(w, meta) {
        const n = w.length;
        if (n < 6 || n > 40) return null;
        const words = c => c.filter(p => !p.link).length, links = c => c.filter(p => p.link).length;
        const better = (c, t) => !t || (words(c) !== words(t) ? words(c) < words(t) : (links(c) !== links(t) ? links(c) < links(t) : c[0].t.length > t[0].t.length));
        const memo = new Map();
        async function best(i) {
            if (memo.has(i)) return memo.get(i);
            memo.set(i, null);
            let top = null;
            if (n - i >= 3) { const e = await svLast(w.slice(i), meta); if (e) top = [{ t: w.slice(i), e, link: false }]; }
            if (n - i >= 6) {
                for (let j = n - 3; j >= i + 3; j--) {
                    const e = await svFront(w.slice(i, j), meta);
                    if (!e) continue;
                    const head = { t: w.slice(i, j), e, link: false };
                    const r = await best(j);
                    if (r && better([head, ...r], top)) top = [head, ...r];
                    if (j < n - 3 && "seauo".includes(w[j])) {
                        const r2 = await best(j + 1);
                        if (r2) { const c = [head, { t: w[j], e: null, link: true }, ...r2]; if (better(c, top)) top = c; }
                    }
                }
            }
            memo.set(i, top);
            return top;
        }
        const r = await best(0);
        return r && words(r) >= 2 ? r : null;
    }
    // (華語 guessed from the English, ≈, when there's no Chinese meaning and the 設定 says so)
    function svGloss(e) { return e.m ? e.m.split("、")[0] : (prefs.svGuess && e.q ? "≈" + e.q.split("、")[0] : (e.e ? e.e.split(";")[0].trim() : "")); }

    const foundP = new Map();     // (the words found for a text, kept: the same text again is answered at once)
    async function find(text) {
        const meta = await getMeta();
        if (!meta) return { ok: true, ready: false };
        const chars = [...text].slice(0, meta.max || 12);
        const out = { ok: true, ready: true, tab: meta };
        if (!chars.length) return out;
        const want = findLangs(meta);
        const ck = want.join(",") + "|" + chars.join("");
        let r = foundP.get(ck);
        if (!r) {
            r = ask({ op: "find", text: chars.join(""), langs: want });
            foundP.set(ck, r);
            if (foundP.size > 400) foundP.delete(foundP.keys().next().value);
        }
        const res = await r;
        if (!res || !res.ok) { foundP.delete(ck); return res || { ok: false }; }
        if (!res.ready) { foundP.delete(ck); return { ok: true, ready: false }; }
        for (const l of want) if (res[l]) out[l] = res[l];
        return out;
    }

    // `at`: where the word starts on the page (its text node and offset), to mark it
    async function lookup(text, rect, spot, at, sv) {
        const n = ++busy;
        const res = sv ? await findLatin(text) : await find(text);
        if (n !== busy) return;                       // (a newer one was asked meanwhile)
        if (!res || !res.ok) { show(rect, spot, message(ffT("查詞沒有回應。請在 Safari 的延伸功能設定裡允許「方方詞卡 查詞」。"))); return; }
        if (!res.ready) {
            // (no dictionary yet: installed in the settings, 設定 → 詞典)
            const box = message(ffT("還沒有安裝詞典。在查詞的設定裡選一個語言安裝（詞典的原始檔案會下載到這個瀏覽器裡整理）。"));
            const go = el("button", "small", ffT("打開設定"));
            go.style.marginTop = "8px";
            go.addEventListener("click", ev => { ev.preventDefault(); ev.stopPropagation(); ask({ op: "options" }); });
            box.appendChild(el("div", null, "")).appendChild(go);
            show(rect, spot, box);
            return;
        }
        if (!res.zh && !res.tw && !res.yue && !res.hak && !res.sv && !res.eng) {
            // (a word tapped in the subtitles: say so, instead of the video just going on)
            if (spot && spot.startsWith("subs:")) { show(rect, spot, message(ffT("詞典裡沒有「") + [...text].slice(0, 4).join("") + ffT("」。"))); return; }
            hide(); return;
        }
        last = { res, rect, spot };
        show(rect, spot, render(res));
        // the word on the page, marked in light blue (the longer of the 華語 and the 台語 word found)
        const len = Math.max(...["zh", "tw", "yue", "hak", "sv", "eng"].map(l => res[l] ? [...res[l].w].length : 0));
        if (at) markWord(at.node, at.off, len); else unmark();
        shownWord = null;
        if (at && at.node.isConnected) {
            const b = wordRange(at.node, at.off, 1).getBoundingClientRect();
            shownWord = { node: at.node, off: at.off, top: b.top, left: b.left };
        }
        const sc = at && subsCueAt(at.node, at.off);
        lastSentence = sc ? sc.sentence : (at ? sentenceAt(at.node, at.off) : (window.getSelection ? sentenceOfSelection() : ""));
        lastTrans = sc ? sc.tr : "";
    }

    // ── the light blue mark around the word ─────────────────────────────────────────────────
    let marks = null;
    let shownWord = null;         // (the word the card is for, and where it was: the card stays while it doesn't move)
    function wordRange(node, off, len) {
        const r = document.createRange();
        r.setStart(node, off);
        let n = node, o = off, left = len;
        // (not the readings and meanings over and under the subtitles' words)
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT,
            { acceptNode: t => t.parentElement && t.parentElement.closest(".ffx") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT });
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
    // (an initial w before u, e or o is v: wu → vu, wo → vo, wei → vei; wa, wai, wan… stay)
    const scV = s => /^w[ueo]/i.test(s) ? (s[0] === "W" ? "V" : "v") + s.slice(1) : s;
    function sichuan(s0) {
        const s = scV(s0);
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

    // a 四川話 syllable in 注音 ("ce1" → "ㄘㆤ"; the same as the app's Zhuyin.sichuanZhuyin): ng- ㄫ, ni- ㄬ, v- ㄪ,
    // r- ㆡ, a final e ㆤ, ou ㄜㄨ (iu ㄧㄜㄨ); tones 1 none, 2 and 5 ˨˩, 3 ˋ, 4 ˇ
    const SC_INI = [["zh", "ㄓ"], ["ch", "ㄔ"], ["sh", "ㄕ"], ["ng", "ㄫ"], ["nh", "ㄬ"], ["ny", "ㄬ"], ["b", "ㄅ"], ["p", "ㄆ"],
        ["m", "ㄇ"], ["f", "ㄈ"], ["v", "ㄪ"], ["d", "ㄉ"], ["t", "ㄊ"], ["n", "ㄋ"], ["l", "ㄌ"], ["g", "ㄍ"], ["k", "ㄎ"], ["h", "ㄏ"],
        ["j", "ㄐ"], ["q", "ㄑ"], ["x", "ㄒ"], ["z", "ㄗ"], ["c", "ㄘ"], ["s", "ㄙ"], ["r", "ㆡ"]];
    const SC_FIN = { "": "", a: "ㄚ", o: "ㄛ", e: "ㆤ", "ê": "ㆤ", er: "ㄦ", ai: "ㄞ", ei: "ㄟ", ao: "ㄠ", ou: "ㄜㄨ",
        an: "ㄢ", en: "ㄣ", ang: "ㄤ", eng: "ㄥ", ong: "ㄨㄥ", ung: "ㄨㄥ",
        i: "ㄧ", ia: "ㄧㄚ", io: "ㄧㄛ", ie: "ㄧㆤ", iai: "ㄧㄞ", iao: "ㄧㄠ", iu: "ㄧㄜㄨ", iou: "ㄧㄜㄨ",
        ian: "ㄧㄢ", in: "ㄧㄣ", iang: "ㄧㄤ", ing: "ㄧㄥ", iong: "ㄩㄥ", iung: "ㄩㄥ",
        u: "ㄨ", ua: "ㄨㄚ", uo: "ㄨㄛ", ue: "ㄨㆤ", uai: "ㄨㄞ", ui: "ㄨㄟ", uei: "ㄨㄟ", uan: "ㄨㄢ", un: "ㄨㄣ", uen: "ㄨㄣ", uang: "ㄨㄤ",
        "ü": "ㄩ", "üe": "ㄩㆤ", "üo": "ㄩㄛ", "üan": "ㄩㄢ", "ün": "ㄩㄣ" };
    function sichuanZy(s0) {
        const s = scV(s0);
        const d = digitTone(s);
        if (!d) return s;
        let x = s.slice(0, -1).toLowerCase();
        if (x.startsWith("yu")) x = "ü" + x.slice(2);
        else if (x.startsWith("yi")) x = "i" + x.slice(2);
        else if (x.startsWith("y")) x = "i" + x.slice(1);
        else if (x.startsWith("wu")) x = "u" + x.slice(2);
        else if (x.startsWith("w")) x = "u" + x.slice(1);
        let ini = "", zi = "", rest = x;
        for (const [l, z] of SC_INI) if (x.startsWith(l)) { ini = l; zi = z; rest = x.slice(l.length); break; }
        if (rest.startsWith("v")) rest = "ü" + rest.slice(1);
        const iu = rest.startsWith("i") || rest.startsWith("ü");
        if (ini === "n" && iu) zi = "ㄬ";
        if ((ini === "nh" || ini === "ny") && !iu) rest = "i" + rest;
        if (["j", "q", "x"].includes(ini) && rest.startsWith("u")) rest = "ü" + rest.slice(1);
        let f;
        if (rest === "i" && ["z", "c", "s", "zh", "ch", "sh", "r"].includes(ini)) f = "";
        else if (rest in SC_FIN) f = SC_FIN[rest];
        else return sichuan(s);
        if (!ini && !f) return sichuan(s);
        return zi + f + ({ 2: "˨˩", 5: "˨˩", 3: "ˋ", 4: "ˇ" }[d] || "");
    }

    // [{t, c}] for a word's 漢字, one colour per syllable
    function hanSegs(han, tones, pal) {
        const out = [];
        let i = 0;
        for (const ch of han) {
            if (isHan(ch.codePointAt(0)) && i < tones.length) { out.push({ t: ch, c: colOn() ? pal[tones[i]] : null }); i++; }
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
        const col = (s, t) => colOn() ? (isSc ? SC : ZH)[t] : null;
        const tShown = tones.filter((_, i) => syl[i] !== "-");
        let r, r2 = null;
        const zy = () => shown.map((s, i) => ({ t: (i ? " " : "") + s, c: col(s, tShown[i]) }));
        const py = () => shown.map((s, i) => ({ t: tab.py[s] || s, c: col(s, tShown[i]) }));
        if (isSc) {
            // (四川話: 四川話拼音, or 注音 when 注音 is chosen; the other one small under it)
            const scPy = () => shown.map((s, i) => ({ t: (i ? " " : "") + sichuan(s), c: col(s, tShown[i]) }));
            const scZy = () => shown.map((s, i) => ({ t: (i ? " " : "") + sichuanZy(s), c: col(s, tShown[i]) }));
            if (prefs.zhRom === 1) { r = scZy(); r2 = scPy(); } else { r = scPy(); r2 = scZy(); }
        }
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
        // (台羅: the nasal oo written onn, not oonn)
        if (sys === 1) return tab.tl[c] ? tab.tl[c].normalize("NFD").replace(/([oO])([\u0300-\u036f]*)o(?=nn)/g, "$1$2").normalize("NFC") : (s ? s[1] : c);
        if (sys === 2) return tab.pj[c] || (s ? s[1] : c);
        return s ? s[1] : c;
    }

    // ── 台語 tones as they're said (the same as the app's 聲調顏色) ──
    // A word on its own: every syllable takes its changed tone (sandhi) except the last one, which keeps its own.
    // A syllable before "--" keeps its own tone too, and the syllables after "--" are in the light tone (grey).
    // Before 仔 a syllable takes 仔's own change. The changes follow the 腔口 (泉 places: 2→5, 5→3; 8 → 4 everywhere, 8 ending in h → 3).
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
            case 8: return h ? 3 : 4;
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
            let prevCode = false, n = 0, light = false;
            for (const t of toks) {
                if (isCode(t)) {
                    const cap = t.startsWith("^"), c = cap ? t.slice(1) : t;
                    let sp = twSpell(c, tab, sys, place);
                    if (cap && sys !== 3) sp = sp.charAt(0).toUpperCase() + sp.slice(1);
                    // 方音's light tone (after "--"): ˙ before the syllable, as 注音 writes 輕聲, its tone mark left out
                    if (sys === 3 && light) sp = "˙" + sp.replace(/[ˉˋˊ˪˫\uA715\uA718\u0307˙]/g, "");
                    out.push({ t: (prevCode && sys !== 3 ? "-" : "") + sp, c: colOn() ? TW[tones[n]] : null });
                    n++; prevCode = true;
                } else if (t === "--") { if (sys !== 3) out.push({ t: "--", c: null }); prevCode = false; light = true; }
                else if (t === "_") { out.push({ t: " ", c: null }); prevCode = false; light = false; }
                else if (t.startsWith("~")) { out.push({ t: t.slice(1), c: null }); prevCode = false; light = false; }
                else { out.push({ t, c: null }); prevCode = false; light = false; }
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
        const r = syl.map((x, i) => ({ t: (i ? " " : "") + x, c: colOn() ? YUE[tones[i]] : null }));
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
            return { t: (i ? " " : "") + body + mark, c: colOn() ? hakColour(p.acc, p.cat) : null };
        });
        const cols = {}; parsed.forEach((p, i) => { cols[i + 1] = hakColour(p.acc, p.cat); });
        return { h: hanSegs(e.k.split("\t")[0], parsed.map((_, i) => i + 1), cols), r, r2: null, guess: !!(e.a && !e.a[acc]) };
    }

    // ── 瑞典語: the word in its morphemes (roots yellow and orange, prefixes teal, suffixes pink, linking letters grey,
    // endings purple: the app's colours), each with what it means ───────────────────────────────────────────────
    const SV_COL = { r: "ffe991", r2: "ffb36b", p: "6fe0cf", s: "ff94c8", l: "bdbdbd", e: "c7a6ff" };
    const SV_KIND = { r: "詞根", p: "前綴", s: "後綴", l: "連接音", e: "詞尾" };
    const SV_AFFIX = {
        p: { o: "不、非", be: "（使動）", "för": "使…、過度", an: "向、對", av: "離開、去掉", in: "進、入", ut: "出、外", upp: "上、起",
            till: "向、加", "över": "上方、超過", under: "下方、不足", efter: "之後", "före": "之前", fram: "向前", om: "重新、圍繞",
            mot: "相對、反", med: "一起", miss: "錯、失", sam: "共同", "sär": "分開、特別", van: "不好、錯", "åter": "再、回",
            ur: "原、最初", er: "（得到）", ge: "（從德語來）", bi: "旁、副", all: "全、非常", icke: "非", anti: "反", super: "超",
            mini: "小", multi: "多", inter: "之間", ex: "前、出", re: "再、回", pre: "前", post: "後", sub: "下、次", trans: "跨、越過" },
        s: { het: "…性、…度（名詞）", ning: "…的行為（名詞）", ing: "…的行為（名詞）", are: "…的人、…器", ande: "…的人；…中的",
            ende: "…的人；…中的", lig: "…的（形容詞）", ig: "有…的", isk: "…的、…式的", bar: "可以…的", sam: "有…傾向的",
            "lös": "沒有…的", fri: "無…的", full: "充滿…的", aktig: "像…的", "mässig": "依…的", skap: "…關係、…身分", dom: "…狀態、…時期",
            else: "…的行為（名詞）", nad: "…的行為（名詞）", eri: "…店、…業", era: "（動詞）", ering: "…的行為", tion: "…的行為",
            sion: "…的行為", itet: "…性", ism: "…主義", ist: "…者、…家", inna: "女…", ska: "女…；…語", "ör": "…者", vis: "以…方式（副詞）" },
        l: { s: "（連接，無意思）", e: "（連接，無意思）", a: "（連接，無意思）", u: "（連接，無意思）", o: "（連接，無意思）", es: "（連接，無意思）" },
        e: { a: "動詞原形", are: "更…（比較級）", ast: "最…（最高級）", aste: "最…（最高級）" },
    };
    // an affix on an affix: the colour of the one next to it, a step darker for each (samtyck|lig|a: -a is -lig's
    // pink, darker; o|be|…: o- is be-'s teal, darker); roots alternate in each word of a phrase
    function darker(hex, d) {
        if (!d) return hex;
        let r = parseInt(hex.slice(0, 2), 16) / 255, g = parseInt(hex.slice(2, 4), 16) / 255, b = parseInt(hex.slice(4, 6), 16) / 255;
        const v = Math.max(r, g, b), mn = Math.min(r, g, b);
        let sat = v ? (v - mn) / v : 0;
        let h = 0;
        if (v !== mn) {
            if (v === r) h = ((g - b) / (v - mn)) % 6; else if (v === g) h = (b - r) / (v - mn) + 2; else h = (r - g) / (v - mn) + 4;
            h *= 60; if (h < 0) h += 360;
        }
        const nv = v * Math.pow(0.74, d), ns = Math.min(1, sat * (1 + 0.18 * d));
        const c = nv * ns, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = nv - c;
        const [a1, a2, a3] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
        return [a1, a2, a3].map(t => Math.round((t + m) * 255).toString(16).padStart(2, "0")).join("");
    }
    function svColours(ms) {
        return ms.map((m, i) => {
            if (m.k === "r") {
                let n = 0;
                for (let j = i - 1; j >= 0 && ms[j].k !== "w"; j--) if (ms[j].k === "r") n++;
                return n % 2 ? SV_COL.r2 : SV_COL.r;
            }
            if (m.k === "p") {
                let d = 0;
                for (let j = i + 1; j < ms.length && ms[j].k === "p"; j++) d++;
                return darker(SV_COL.p, d);
            }
            if (m.k === "s" || m.k === "e") {
                let st = i;
                while (st > 0 && (ms[st - 1].k === "s" || ms[st - 1].k === "e")) st--;
                return darker(SV_COL[ms[st].k], i - st);
            }
            return SV_COL.l;
        });
    }
    // a word's morphemes from the data ("be:p tal:r:tala a:e"), each root with its meaning (e.g)
    function svMs(e) {
        return (e.s || "").split(" ").filter(Boolean).map((x, i) => {
            const p = x.split(":");
            let g = p[1] === "r" ? (e.g || {})[String(i)] : null;
            if (g && g[0] === "≈" && !prefs.svGuess) g = null;
            return { t: p[1] === "w" ? " " : p[0], k: p[1], g };
        }).filter(m => m.t && (SV_KIND[m.k] || m.k === "w"));
    }
    // a form of a word (Hittade of hitta): the word's morphemes for what they share, the rest as an ending
    function svForForm(form, lemma, ms0) {
        const low = form.toLowerCase();
        const ms = ms0.length ? ms0.map(m => ({ ...m })) : [{ t: lemma, k: "r", g: null }];
        const fits = l => l.length > 0 && low.startsWith(l.map(m => m.t).join("").toLowerCase());
        let use = ms.slice();
        while (use.length && use[use.length - 1].k === "e") use.pop();
        if (!fits(use) || low === lemma.toLowerCase()) use = ms.slice();
        if (!fits(use)) {
            const t = ms.map(m => m.t).join("").toLowerCase();
            let n = 0;
            while (n < t.length && n < low.length && t[n] === low[n]) n++;
            const cut = [];
            let at = 0;
            for (const m of ms) { if (at >= n) break; const take = Math.min(m.t.length, n - at); cut.push({ ...m, t: m.t.slice(0, take) }); at += take; }
            use = cut;
        }
        const out = [];
        let at = 0;
        for (const m of use) { if (at + m.t.length > form.length) break; out.push({ ...m, t: form.slice(at, at + m.t.length) }); at += m.t.length; }
        const rest = form.slice(at);
        // (ta → tag-, dra → drag-: the stem's -g / -d stays with the root)
        if (/^[gd]$/i.test(rest) && out.length && out[out.length - 1].k === "r" && /[aeiouyåäö]$/i.test(out[out.length - 1].t)) out[out.length - 1] = { ...out[out.length - 1], t: out[out.length - 1].t + rest };
        else if (rest) out.push({ t: rest, k: "e", g: null });
        return out;
    }
    function svParts(e, form) {
        let ms, head;
        if (e.est) {
            // (worked out by rules: its morphemes, from the base word(s) and the suffixes and endings)
            head = form;
            ms = e.est.ms;
            // (in the letters as written on the page)
            let at = 0;
            ms = ms.map(m => { const t = form.slice(at, at + m.t.length); at += m.t.length; return { ...m, t }; });
        } else if (form && form.toLowerCase() !== svHeadOf(e).toLowerCase()) {
            head = form;
            ms = svForForm(form, svHeadOf(e), svMs(e));
        } else {
            head = form || svHeadOf(e);
            ms = svMs(e);
        }
        const cols = svColours(ms);
        const many = ms.filter(m => m.k !== "w").length > 1;
        const whole = ms.map(m => m.t).join("") === head;
        const h = whole && many ? ms.map((m, i) => ({ t: m.t, c: colOn() && m.k !== "w" ? cols[i] : null })) : [{ t: head, c: null }];
        const r = many ? ms.map((m, i) => ({ t: m.k === "w" ? " " : ((i && ms[i - 1].k !== "w" ? "-" : "") + m.t), c: colOn() && m.k !== "w" ? cols[i] : null })) : [];
        let parts = null;
        if (many) {
            parts = el("div", "parts");
            ms.forEach((m, i) => {
                if (m.k === "w") { parts.appendChild(el("span", "gap", "")); return; }
                if (i && ms[i - 1].k !== "w") parts.appendChild(el("span", "plus", "+"));
                const b = el("div", "part");
                b.style.borderColor = "#" + cols[i];
                b.style.background = "#" + cols[i] + "33";
                b.appendChild(el("span", "pt", m.k === "p" ? m.t + "-" : (m.k === "r" ? m.t : "-" + m.t)));
                b.appendChild(el("span", "pk", SV_KIND[m.k]));
                const g = m.k === "r" ? m.g : (SV_AFFIX[m.k] || {})[m.t.toLowerCase()];
                if (g) b.appendChild(el("span", "pg", g));
                parts.appendChild(b);
            });
        }
        return { h, r, r2: null, parts };
    }

    // 英語: the word (as on the page) and its IPA, British and American as the settings say
    function engIpa(e) {
        const uk = e.u || "", us = e.a || "";
        switch (prefs.engRom) {
            case 1: return (us || uk) ? "/" + (us || uk) + "/" : "";
            case 2: return (uk || us) ? "/" + (uk || us) + "/" : "";
            case 3: return "";
            default: return uk && us && uk !== us ? "UK /" + uk + "/ · US /" + us + "/" : ((uk || us) ? "/" + (uk || us) + "/" : "");
        }
    }
    function engParts(e, form) {
        const head = form || e.k.split("\t")[0];
        const r = engIpa(e);
        return { h: [{ t: head, c: null }], r: r ? [{ t: r, c: null }] : [], r2: null, parts: null };
    }

    // ── the sentence a word is in (kept with it when it's saved): from the stop before it to the stop after it ──
    let lastSentence = "";
    // (a subtitle line's: the same line in the second language under it, e.g. the English; and the video it's from)
    let lastTrans = "";
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
        pageAnno();
        if (ringBox) { ringBox.remove(); ringBox = null; }
        try { if (window.CSS && CSS.highlights) for (const k of [...CSS.highlights.keys()]) if (k.startsWith("ff-tone-")) CSS.highlights.delete(k); } catch (e) {}
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
                if (found && !(prefs.onlyNew && isKnownIn(chars.slice(i, i + len).join(""), "zh"))) {
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
    // 網頁上不認識的詞: like the subtitles, the words you don't know (by 字幕 → 標哪些詞: not known, rarer, or both)
    // get their reading over them in the tone colours and a short meaning under them, and the tone colours on the
    // word itself; in the language that's on. Drawn in a layer of their own over the page (the page itself isn't
    // changed), placed in the page so they scroll with it, and made again when the page stops scrolling.
    let annoBox = null, annoRun = 0;
    async function pageAnno() {
        const run = ++annoRun;
        const clear = () => {
            if (annoBox) { annoBox.remove(); annoBox = null; }
            try { if (window.CSS && CSS.highlights) for (const k of [...CSS.highlights.keys()]) if (k.startsWith("ff-anno-")) CSS.highlights.delete(k); } catch (e) {}
        };
        const L = ["zh", "tw", "yue", "hak"].find(l => prefs[l]);
        if (!prefs.on || !prefs.pageAnno || !L || !document.body) {
            clear();
            // (the room made between the lines taken away again)
            for (const el of document.querySelectorAll(".ff-anno-gap")) el.classList.remove("ff-anno-gap");
            return;
        }
        const meta = await getMeta();
        if (!meta || run !== annoRun) return;
        const vh = window.innerHeight, vw = window.innerWidth;
        const nodes = textNodesInView().filter(n => {
            if (n.parentElement && n.parentElement.closest("#ff-subs,#ff-anno")) return false;
            const r = document.createRange(); r.selectNodeContents(n);
            const b = r.getBoundingClientRect();
            return b.bottom > -80 && b.top < vh + 80 && b.width > 0;
        }).slice(0, 300);
        // (the words found by the add-on itself, not here: only they come to the page)
        const texts = nodes.map(n => n.nodeValue);
        const seg = nodes.length ? await ask({ op: "segment", lang: L, texts }) : { ok: true, data: [] };
        if (run !== annoRun) return;
        if (!seg || !seg.ok || !seg.data) return;
        const rd = prefs.pageAnno !== "gl", gl = prefs.pageAnno !== "rd";
        const box = document.createElement("div");
        box.id = "ff-anno";
        box.style.cssText = "position:absolute;left:0;top:0;width:0;height:0;overflow:visible;z-index:2147483644;pointer-events:none;";
        const sx = window.scrollX, sy = window.scrollY;
        const tones = {};
        const label = (x, y, up, size, parts) => {
            const d = document.createElement("div");
            d.style.cssText = `position:absolute;left:${x}px;top:${y}px;transform:translate(-50%,${up ? "-100%" : "0"});white-space:nowrap;` +
                `font:600 ${size}px/1.15 -apple-system,"PingFang TC",sans-serif;color:#eef0f6;background:rgba(22,23,28,.82);` +
                "padding:0 3px;border-radius:4px;letter-spacing:0;";
            for (const p of parts) { const sp = document.createElement("span"); sp.textContent = p.t; if (p.c) sp.style.color = "#" + p.c; d.appendChild(sp); }
            box.appendChild(d);
        };
        const markedOf = (entry, word) => {
            const head = entry.k ? entry.k.split("\t")[0] : word;
            const known = isKnownIn(word, L) || (head !== word && isKnownIn(head, L));
            const rare = entry.f == null || entry.f >= (prefs.subsRare || 3000);
            const mode = prefs.subsMark || "new";
            return mode === "rare" ? rare : mode === "both" ? (!known && rare) : !known;
        };
        // room between the lines for the readings and meanings: the text with words marked gets taller lines (only
        // the line spacing changes; the words themselves stay where they are on the line, and as big). Made before
        // the words are measured, as the lines move
        if (!document.getElementById("ff-anno-gap-style")) {
            const st = document.createElement("style");
            st.id = "ff-anno-gap-style";
            st.textContent = ".ff-anno-gap { line-height: 2.7 !important; }";
            (document.head || document.documentElement).appendChild(st);
        }
        nodes.forEach((node, ni) => {
            if (node.nodeValue !== texts[ni] || !node.isConnected) return;
            const el = node.parentElement;
            if (!el || el.classList.contains("ff-anno-gap")) return;
            const chars = [...node.nodeValue];
            if ((seg.data[ni] || []).some(([i, len, list]) => { const e = subsEntry(list, L) || list[0]; return e && markedOf(e, chars.slice(i, i + len).join("")); }))
                el.classList.add("ff-anno-gap");
        });
        let n = 0;
        nodes.forEach((node, ni) => {
            // (the text changed meanwhile: left for the next time)
            if (node.nodeValue !== texts[ni] || !node.isConnected) return;
            const chars = [...node.nodeValue];
            // (where each character starts in the text: a few take two places)
            const at = [];
            let q = 0;
            for (const ch of chars) { at.push(q); q += ch.length; }
            // (the labels' size from the text's: readable, and fitting in the room made between the lines)
            const fs = parseFloat(getComputedStyle(node.parentElement).fontSize) || 16;
            const rdSize = Math.max(10, Math.round(fs * 0.6)), glSize = Math.max(10, Math.round(fs * 0.55));
            for (const [i, len, list] of seg.data[ni] || []) {
                if (n >= 250) break;
                if (i + len > chars.length) continue;
                const entry = subsEntry(list, L) || list[0];
                if (!entry) continue;
                const word = chars.slice(i, i + len).join("");
                const pos = at[i];
                if (!markedOf(entry, word)) continue;
                const r = document.createRange();
                r.setStart(node, pos); r.setEnd(node, pos + word.length);
                const rects = r.getClientRects();
                const b = r.getBoundingClientRect();
                // (on one line, on screen)
                if (!(rects.length === 1 && b.width > 0 && b.bottom > -40 && b.top < vh + 40 && b.right > 0 && b.left < vw)) continue;
                n++;
                let parts = {};
                try { parts = subsParts(entry, L, meta) || {}; } catch (err) { parts = {}; }
                const cx = b.left + b.width / 2 + sx;
                if (rd && parts.r && parts.r.length) {
                    label(cx, b.top + sy - 1, true, rdSize,
                        parts.r.map((sg, j) => ({ t: j && L === "zh" && !sg.t.startsWith(" ") ? " " + sg.t : sg.t, c: sg.c })));
                }
                if (gl) {
                    const g = subsGloss(entry);
                    if (g) label(cx, b.bottom + sy + 1, false, glSize, [{ t: g }]);
                }
                // (the word's characters in their tone colours)
                const cols = (parts.h || []).flatMap(sg => [...sg.t].map(() => sg.c || null));
                for (let j = 0; j < len; j++) {
                    if (!cols[j]) continue;
                    const rr = document.createRange();
                    rr.setStart(node, at[i + j]); rr.setEnd(node, at[i + j] + chars[i + j].length);
                    (tones[cols[j]] = tones[cols[j]] || []).push(rr);
                }
            }
        });
        if (run !== annoRun) return;
        clear();
        document.documentElement.appendChild(box);
        annoBox = box;
        if (window.CSS && CSS.highlights && window.Highlight) try {
            let style = document.getElementById("ff-anno-style");
            if (!style) { style = document.createElement("style"); style.id = "ff-anno-style"; (document.head || document.documentElement).appendChild(style); }
            let css = "";
            for (const [c, ranges] of Object.entries(tones)) {
                CSS.highlights.set("ff-anno-" + c, new Highlight(...ranges));
                css += `::highlight(ff-anno-${c}) { color: #${c}; }\n`;
            }
            style.textContent = css;
        } catch (e) {}
    }
    window.addEventListener("scroll", pageMarks, { passive: true });
    window.addEventListener("resize", pageMarks, { passive: true });
    // (a part of the page that scrolls on its own)
    document.addEventListener("scroll", e => { if (e.target !== document && prefs.pageAnno) pageMarks(); }, { passive: true, capture: true });

    // ── the card ────────────────────────────────────────────────────────────────────────────
    const CSS_TEXT = `
        /* (the box the card lives in is out of the page's flow, size 0 in the corner: changing the card then doesn't make the
           browser lay out the whole page again, which on long pages, Wikipedia or YouTube's comments, made it slow) */
        :host { all: initial; position: fixed !important; left: 0 !important; top: 0 !important; width: 0 !important;
            height: 0 !important; overflow: visible !important; z-index: 2147483647 !important; contain: style; }
        .card { position: fixed; z-index: 2147483647; contain: layout style; width: max-content; max-width: min(360px, calc(100vw - 16px));
            max-height: min(70vh, 540px); display: flex; flex-direction: column; box-sizing: border-box; overflow: hidden;
            background: rgba(30, 31, 35, 0.97); color: #f2f2f2; border: 1.5px solid #4b4b4e;
            border-radius: 14px; box-shadow: 0 8px 28px rgba(0,0,0,.45);
            font: 15px/1.35 -apple-system, "PingFang TC", "Heiti TC", sans-serif; -webkit-text-size-adjust: none; }
        /* opening and closing: grows out of the word and fades in; shrinks back and fades out */
        .card { transition: opacity .2s ease-out, transform .26s cubic-bezier(.2, .9, .3, 1.15); will-change: opacity, transform; }
        .card.off { opacity: 0; transform: scale(.92) translateY(var(--ff-dy, -6px));
            transition: opacity .16s ease-in, transform .18s ease-in; }
        @media (prefers-reduced-motion: reduce) { .card, .card.off { transition: opacity .12s linear; transform: none; } }
        .body { flex: 1 1 auto; min-height: 0; overflow-y: auto; -webkit-overflow-scrolling: touch; padding: 8px 12px 14px; }
        .grip { position: absolute; width: 22px; height: 22px; touch-action: none; cursor: nwse-resize; }
        .grip::after { content: ""; position: absolute; width: 10px; height: 10px; border: 0 solid #8e8e93; }
        .grip.br { right: 0; bottom: 0; } .grip.br::after { right: 5px; bottom: 5px; border-right-width: 2px; border-bottom-width: 2px; border-bottom-right-radius: 3px; }
        .grip.bl { left: 0; bottom: 0; cursor: nesw-resize; } .grip.bl::after { left: 5px; bottom: 5px; border-left-width: 2px; border-bottom-width: 2px; border-bottom-left-radius: 3px; }
        .grip.tr { right: 0; top: 0; cursor: nesw-resize; } .grip.tr::after { right: 5px; top: 5px; border-right-width: 2px; border-top-width: 2px; border-top-right-radius: 3px; }
        .grip.tl { left: 0; top: 0; } .grip.tl::after { left: 5px; top: 5px; border-left-width: 2px; border-top-width: 2px; border-top-left-radius: 3px; }
        .top { display: flex; justify-content: flex-end; gap: 6px; margin-bottom: 4px; }
        .sec { border-radius: 10px; padding: 6px 9px 8px; }
        .sec + .sec { margin-top: 8px; }
        .sec.zh { background: rgba(79, 125, 255, 0.10); }
        .sec.tw { background: rgba(63, 174, 102, 0.10); }
        .sec.yue { background: rgba(201, 162, 39, 0.10); }
        .sec.hak { background: rgba(216, 67, 79, 0.10); }
        .sec.sv { background: rgba(63, 201, 189, 0.08); }
        .sec.eng { background: rgba(240, 138, 60, 0.08); }
        .cols { display: flex; gap: 8px; align-items: flex-start; }
        .cols > .sec { flex: 1 1 0; min-width: 190px; margin-top: 0; }
        .lang { display: inline-block; font-size: 12px; padding: 1px 7px; border-radius: 6px; margin-bottom: 4px; }
        .lang.zh { background: #1f3d6b; border: 1px solid #4f7dff; color: #9ad0ff; }
        .lang.tw { background: #1d4630; border: 1px solid #3fae66; color: #b6f0c8; }
        .lang.yue { background: #5a4a14; border: 1px solid #c9a227; color: #ffe58a; }
        .lang.hak { background: #5a1e2a; border: 1px solid #d8434f; color: #ffb3b8; }
        .lang.sv { background: #0f4a4a; border: 1px solid #3fc9bd; color: #9cf0e6; }
        .chip.sv { background: #163f3c; border-color: #3fc9bd; color: #9cf0e6; }
        .lang.eng { background: #5a3214; border: 1px solid #f08a3c; color: #ffd2a8; }
        .chip.eng { background: #4a2a12; border-color: #f08a3c; color: #ffd2a8; }
        .parts { display: flex; flex-wrap: wrap; gap: 4px; align-items: stretch; margin-top: 4px; }
        .part { display: flex; flex-direction: column; align-items: center; padding: 2px 7px; border-radius: 7px; border: 1.5px solid; }
        .part .pt { font-size: 15px; font-weight: 600; color: #f2f2f2; }
        .part .pk { font-size: 10px; color: #a3a3a8; }
        .part .pg { font-size: 11px; color: #e8e8e8; max-width: 9em; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .plus { color: #8e8e93; align-self: center; font-size: 12px; }
        .gap { width: 10px; }
        .steps { margin-top: 5px; padding: 5px 7px; border-radius: 7px; background: rgba(255,255,255,0.05); }
        .step { font-size: 12px; color: #d8d8dc; line-height: 1.45; }
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
        button.on.k { background: #2f5a3d; border-color: #3fae66; color: #c8f2d4; }
        button.send { background: #44503a; border-color: #4f6c32; color: #d4efc0; }
        .msg { font-size: 14px; color: #f2f2f2; }
        .set { font-size: 13px; }
        .set label { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin: 6px 0; }
        .set select { font-size: 13px; background: #2b2b2d; color: #f2f2f2; border: 1px solid #4b4b4e; border-radius: 6px; padding: 2px 4px; }
        .note { font-size: 12px; color: #a3a3a8; margin-top: 6px; }
        .mark { position: fixed; z-index: 2147483646; pointer-events: none; box-sizing: border-box;
            border: 2px solid #7cc4ff; border-radius: 5px; background: rgba(124, 196, 255, 0.16); }

        /* ── the app's look: a dark, warm night with the words glowing in their tone colours, round pill buttons and
           boxes edged in each language's colour ── */
        .card { background: linear-gradient(180deg, rgba(38, 30, 29, .97), rgba(23, 18, 18, .97)); color: #f4ece8;
            border: 1px solid rgba(255, 255, 255, .10); border-radius: 20px;
            box-shadow: 0 0 0 1px rgba(195, 155, 255, .16), 0 0 26px rgba(195, 155, 255, .14), 0 14px 40px rgba(0, 0, 0, .55);
            font: 15px/1.4 -apple-system, "PingFang TC", "Heiti TC", sans-serif; }
        .body { padding: 10px 14px 16px; }
        .sec { --lc: #c39bff; border-radius: 16px; padding: 10px 12px 12px;
            background: linear-gradient(180deg, color-mix(in srgb, var(--lc) 10%, transparent), color-mix(in srgb, var(--lc) 4%, transparent));
            border: 1px solid color-mix(in srgb, var(--lc) 38%, transparent);
            box-shadow: inset 0 0 18px color-mix(in srgb, var(--lc) 8%, transparent); }
        .sec + .sec { margin-top: 10px; }
        .sec.zh { --lc: #4f7dff; } .sec.tw { --lc: #3fae66; } .sec.yue { --lc: #e0b830; }
        .sec.hak { --lc: #ff5a6a; } .sec.sv { --lc: #3fc9bd; } .sec.eng { --lc: #f08a3c; }
        .lang { border-radius: 999px; padding: 2px 10px; font-size: 12px; font-weight: 600; margin-bottom: 6px;
            box-shadow: 0 0 10px color-mix(in srgb, var(--lc) 45%, transparent); }
        .han { font-size: 32px; font-weight: 700; letter-spacing: .02em;
            text-shadow: 0 0 4px color-mix(in srgb, currentColor 70%, transparent), 0 0 14px color-mix(in srgb, currentColor 45%, transparent); }
        .han span { text-shadow: 0 0 4px color-mix(in srgb, currentColor 70%, transparent), 0 0 14px color-mix(in srgb, currentColor 45%, transparent); }
        .r { font-size: 18px; color: #c8f0a8; text-shadow: 0 0 8px color-mix(in srgb, currentColor 45%, transparent); }
        .r span, .r2 span { text-shadow: 0 0 8px color-mix(in srgb, currentColor 45%, transparent); }
        .r2 { font-size: 14px; color: #e3c6f7; }
        .m { font-size: 15px; color: #f4ece8; margin-top: 4px; }
        .en { font-size: 13.5px; color: #b9aea9; margin-top: 3px; }
        .via, .note, .part .pk { color: #b0a39e; }
        .chip { border-radius: 999px; padding: 1px 8px; background: rgba(255, 255, 255, .05); border-color: rgba(255, 255, 255, .16); color: #c8bcb7; }
        .part { border-radius: 12px; background: rgba(255, 255, 255, .03); }
        .steps { border-radius: 12px; background: rgba(255, 255, 255, .04); }
        .btns { gap: 8px; margin-top: 10px; flex-wrap: wrap; }
        button { border-radius: 999px; padding: 6px 14px; font-size: 13.5px; font-weight: 600;
            background: rgba(255, 255, 255, .05); border: 1.5px solid rgba(255, 255, 255, .18); color: #f4ece8;
            transition: box-shadow .2s ease, background-color .2s ease; }
        button.small { padding: 3px 10px; font-size: 12px; }
        button.u { border-color: #ff8a5c; color: #ffc6ad; }
        button.s { border-color: #ffd84d; color: #fff1a8; }
        button.k { border-color: #b9aea9; color: #e8e0dc; }
        button.on.u { background: rgba(255, 138, 92, .28); border-color: #ff8a5c; color: #fff; box-shadow: 0 0 12px rgba(255, 138, 92, .55); }
        button.on.s { background: rgba(255, 216, 77, .30); border-color: #ffd84d; color: #fff; box-shadow: 0 0 12px rgba(255, 216, 77, .5); }
        button.on.k { background: rgba(63, 174, 102, .30); border-color: #5fd68a; color: #fff; box-shadow: 0 0 12px rgba(95, 214, 138, .5); }
        button.send { background: rgba(195, 155, 255, .22); border-color: #c39bff; color: #fff; box-shadow: 0 0 12px rgba(195, 155, 255, .45); }
        .msg { font-size: 15px; }
        .set select { border-radius: 10px; background: rgba(255, 255, 255, .06); border-color: rgba(255, 255, 255, .18); }
        .mark { border-color: #c39bff; border-radius: 7px; background: rgba(195, 155, 255, .16); box-shadow: 0 0 12px rgba(195, 155, 255, .45); }
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
            const send = el("button", "small send", ffT("傳到 App（") + queue.length + ffT("）"));
            send.addEventListener("click", ev => { ev.preventDefault(); ev.stopPropagation(); sendToApp(); });
            top.appendChild(send);
        }
        const gear = el("button", "small", onSettings ? ffT("完成") : ffT("設定"));
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
        const NAMES = { zh: ffT("華語"), tw: ffT("台語"), yue: ffT("粵語"), hak: ffT("客語"), sv: ffT("瑞典語"), eng: ffT("英語") };
        for (const lang of ["zh", "tw", "yue", "hak", "sv", "eng"]) {
            const part = res[lang];
            if (!part) continue;
            const sec = el("div", "sec " + lang);
            sec.appendChild(el("span", "lang " + lang, NAMES[lang] + (lang === "hak" && tab.hacc && tab.hacc[prefs.hakAcc] ? ffT("・") + tab.hacc[prefs.hakAcc] : "") + (part.en ? ffT("・英文「") + part.w + (part.base ? " → " + part.base : "") + ffT("」") : "")));
            for (const e of part.list) {
                if (lang === "zh" && e.p === 3 && prefs.zhPlace !== 2) continue;     // (四川話's own words: with 四川話 only)
                const p = lang === "eng" ? engParts(e, part.form) : lang === "sv" ? svParts(e, part.form) : lang === "zh" ? zhParts(e, tab) : (lang === "tw" ? twParts(e, tab) : (lang === "yue" ? yueParts(e) : hakParts(e, tab)));
                const d = el("div", "e");
                if (e.v) d.appendChild(el("div", "via", ffT("華語「") + e.v + ffT("」的台語講法")));
                const head = el("div", "head");
                head.appendChild(segs("han", p.h));
                head.appendChild(segs("r", p.r));
                if (p.r2) head.appendChild(segs("r2", p.r2));
                d.appendChild(head);
                const chips = [];
                if (lang === "zh") {
                    if (e.p === 1) chips.push([ffT("臺灣用語"), ""]);
                    else if (e.p === 2) chips.push([ffT("大陸用語"), ""]);
                    else if (e.p === 3) chips.push([ffT("四川話"), "sc"]);
                    if (prefs.zhPlace === 2) {
                        if (!e.s) chips.push([ffT("普通話讀音"), "p0"]);
                        else if (e.q === 1) chips.push([ffT("推算"), "p1"]);
                        else if (e.q === 2) chips.push([ffT("預測"), "p2"]);
                    }
                }
                if (lang === "hak" && p.guess) chips.push([ffT("這個腔沒有收"), "p0"]);
                if (lang === "sv" && e.w) chips.push([e.w, "sv"]);
                if (lang === "eng" && e.w) chips.push([e.w, "eng"]);
                if (lang === "eng" && part.form && part.form.toLowerCase() !== e.k.split("\t")[0].toLowerCase()) chips.push([ffT("「") + e.k.split("\t")[0] + ffT("」的變化"), "eng"]);
                if (lang === "sv" && e.est && !e.inDict) chips.push([ffT("詞典裡沒有：照詞和構詞規則推算，可能有誤"), "p0"]);
                if (lang === "sv" && part.form && !e.est && part.form.toLowerCase() !== e.k.split("\t")[0].toLowerCase()) chips.push([ffT("「") + e.k.split("\t")[0] + ffT("」的變化"), "sv"]);
                if (chips.length) {
                    const c = el("div", "chips");
                    for (const [t, k] of chips) c.appendChild(el("span", "chip " + k, t));
                    d.appendChild(c);
                }
                // 瑞典語: the parts of the word, each in its colour with what it means
                if (lang === "sv" && p.parts) d.appendChild(p.parts);
                // (worked out: the base word(s) and each step)
                if (lang === "sv" && e.est) {
                    const box = el("div", "steps");
                    for (const q of e.est.parts) if (!q.link) box.appendChild(el("div", "step", svHeadOf(q.e) + (q.e.w ? "（" + q.e.w + "）" : "") + "：" + svGloss(q.e)));
                    for (const st of e.est.steps) {
                        const row = el("div", "step");
                        const t = el("b", null, st.k === "p" ? st.t + "-" : "-" + st.t);
                        t.style.color = "#" + (st.k === "p" ? SV_COL.p : (st.k === "s" ? SV_COL.s : SV_COL.e));
                        row.append(t, document.createTextNode(" " + st.zh + (st.k !== "p" && SV_CLS_NAME[st.cls] ? " → " + SV_CLS_NAME[st.cls] : "")));
                        box.appendChild(row);
                    }
                    d.appendChild(box);
                }
                if (lang === "eng") {
                    // 英語: the meanings chosen (英文, 中文, 瑞典文; at least one)
                    const none = !prefs.engZh && !prefs.engSv;
                    if (prefs.engZh && e.m) d.appendChild(el("div", "m", e.m));
                    if (prefs.engSv && e.s) d.appendChild(el("div", "m", ffT("瑞典文：") + e.s));
                    if ((prefs.engEn || none || (!e.m && !e.s)) && e.e) d.appendChild(el("div", "en", e.e));
                } else if (e.m) d.appendChild(el("div", "m", e.m));
                else if (lang === "sv" && e.q && prefs.svGuess) d.appendChild(el("div", "m", "≈ " + e.q + ffT("（由英文推測）")));
                if (e.eq && e.eq.length && lang === "zh" && prefs.zhPlace === 2) d.appendChild(el("div", "en", ffT("華語：") + e.eq.join("、")));
                if (lang !== "eng" && (prefs.en || (lang === "sv" && !e.m)) && e.e) d.appendChild(el("div", "en", e.e));
                if (e.k) d.appendChild(buttons(e.k, e.k.split("\t")[0], p.h));
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
        const u = el("button", "u"), sv = el("button", "s"), kn = el("button", "k");
        const paint = () => {
            const qu = queued(key, "unknown"), qs = queued(key, "saved"), qk = queued(key, "known");
            kn.textContent = qk ? ffT("已選：認識") : ffT("認識");
            kn.classList.toggle("on", qk);
            u.textContent = qu ? ffT("已選：加到不熟") : ffT("加到不熟");
            u.classList.toggle("on", qu);
            sv.textContent = qs ? ffT("已選：收藏") : ffT("收藏");
            sv.classList.toggle("on", qs);
        };
        paint();
        const go = w => ev => {
            ev.preventDefault(); ev.stopPropagation();
            if (queued(key, w)) {
                queue = queue.filter(q => !(q.k === key && q.w === w));
                if (w === "known") { localDel(han, keyLang(key)); saveKnownLocal(); }
            } else {
                // (認識 and 加到不熟 don't go together)
                if (w === "known") queue = queue.filter(q => !(q.k === key && q.w === "unknown"));
                if (w === "unknown") { queue = queue.filter(q => !(q.k === key && q.w === "known")); localDel(han, keyLang(key)); saveKnownLocal(); }
                if (w === "known") { localAdd(han, keyLang(key)); saveKnownLocal(); }
                queue.push(withGroup({ k: key, w, h: han, x: lastSentence || "", tr: lastSentence ? lastTrans : "", t: Date.now() }));
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
        kn.addEventListener("click", go("known"));
        row.append(u, sv, kn);
        return row;
    }

    // a word for the app's link (the same as settings.js's ffOp): [key, what, the sentence, its 影片詞組, the
    // sentence in the second language]
    function ffOp(op) {
        return x => {
            const tr = x.x ? (x.tr || "") : "";
            if (tr) return [x.k, op(x.w), x.x || "", x.g || "", tr];
            return x.g ? [x.k, op(x.w), x.x || "", x.g] : (x.x ? [x.k, op(x.w), x.x] : [x.k, op(x.w)]);
        };
    }

    // opens the app with the words (Safari asks first whether to open it)
    function sendToApp() {
        if (!queue.length) return;
        const op = w => w === "saved" ? "s" : (w === "known" ? "k" : (w === "group" ? "g" : "u"));
        const ops = queue.map(ffOp(op));
        const pack = o => btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(o)))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
        // (影片詞組: each word's video, its name and address)
        const groups = {};
        for (const q of queue) if (q.g) groups[q.g] = [q.gn || q.g, q.gu || ""];
        // (and the minutes watched with the subtitle panel, for 練習統計)
        // (kept in memory too, so the app opens straight from the tap: Safari only opens it from a tap)
        let w = Object.keys(groups).length ? "&gr=" + pack(groups) : "";
        if (Object.keys(watchCache).length) { w = "&w=" + pack(watchCache); watchCache = {}; if (store) store.set({ ffWatch: {} }).catch(() => {}); }
        // (and each video's 懂 %, for the app's 影片懂多少)
        if (Object.keys(seenCache).length) { w += "&vk=" + pack(seenCache); seenCache = {}; if (store) store.set({ ffSeen: {} }).catch(() => {}); }
        const a = document.createElement("a");
        // (on Android, Firefox hands an intent:// link to the app)
        a.href = /Android/i.test(navigator.userAgent) ? "intent://safari?ops=" + pack(ops) + w + "#Intent;scheme=fangfangcards;end"
            : "fangfangcards://safari?ops=" + pack(ops) + w;
        a.style.display = "none";
        (document.body || document.documentElement).appendChild(a);
        a.click();
        a.remove();
        const n = queue.length;
        queue = [];
        saveQueue();
        body.replaceChildren(topBar(false), message(ffT("已經把 ") + n + ffT(" 個詞傳到方方詞卡。如果 App 沒有打開，請再試一次。")));
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
        const yesNo = [[true, ffT("顯示")], [false, ffT("不顯示")]];
        // (one language at a time)
        {
            const l = el("label");
            l.appendChild(el("span", null, ffT("語言")));
            const s = el("select");
            for (const [v, t] of [["zh", ffT("華語")], ["tw", ffT("台語")], ["yue", ffT("粵語")], ["hak", ffT("客語")], ["sv", ffT("瑞典語")], ["eng", ffT("英語")]]) {
                const o = el("option", null, t); o.value = v;
                if (activeLang() === v) o.selected = true;
                s.appendChild(o);
            }
            s.addEventListener("change", () => { for (const x of LANGS_ONE) prefs[x] = x === s.value; savePrefs(); });
            l.appendChild(s);
            box.appendChild(l);
        }
        row(ffT("華語讀音"), "zhPlace", [[0, ffT("國語")], [1, ffT("普通話")], [2, ffT("四川話")]]);
        row(ffT("華語拼寫"), "zhRom", [[1, ffT("注音")], [0, ffT("拼音")]]);
        row(ffT("台語拼寫"), "twRom", [[0, ffT("皓羅")], [1, ffT("台羅")], [2, ffT("白話字")], [3, ffT("方音")]]);
        const places = [[-1, ffT("通行")]];
        (placeNames || []).forEach((p, i) => places.push([i, p.slice(0, 2)]));
        row(ffT("台語腔口"), "twPlace", places);
        row(ffT("客語腔"), "hakAcc", [ffT("四縣"), ffT("海陸"), ffT("大埔"), ffT("饒平"), ffT("詔安"), ffT("南四縣")].map((n, i) => [i, n]));
        row(ffT("客語拼寫"), "hakRom", [[0, ffT("拼音")], [1, ffT("注音")]]);
        row(ffT("英語讀音"), "engRom", [[0, ffT("英式＋美式")], [1, ffT("美式")], [2, ffT("英式")], [3, ffT("不顯示")]]);
        row(ffT("英語：英文解釋"), "engEn", yesNo);
        row(ffT("英語：中文解釋"), "engZh", yesNo);
        row(ffT("英語：瑞典文"), "engSv", yesNo);
        row(ffT("瑞典語：由英文推測中文"), "svGuess", [[true, ffT("顯示")], [false, ffT("不顯示")]]);
        row(ffT("聲調顏色"), "colours", [[true, ffT("開")], [false, ffT("關")]]);
        row(ffT("字的大小"), "font", [[0.85, ffT("小")], [1, ffT("中")], [1.15, ffT("大")], [1.3, ffT("更大")], [1.5, ffT("很大")], [1.8, ffT("特大")], [2.2, ffT("超大")], [2.7, ffT("最大")]]);
        row(ffT("網頁上收藏的詞"), "ring", [[false, ffT("不標")], [true, ffT("彩虹框")]]);
        row(ffT("網頁上的聲調顏色"), "tint", [[false, ffT("不上色")], ["saved", ffT("收藏的詞")], ["all", ffT("全部（華語）")]]);
        row(ffT("英文解釋"), "en", [[false, ffT("不顯示")], [true, ffT("顯示")]]);
        row(ffT("位置"), "pos", POSITIONS.map(([v, t]) => [v, ffT(t)]));
        const size = el("button", "small", ffT("大小還原"));
        size.addEventListener("click", ev => { ev.preventDefault(); ev.stopPropagation(); prefs.w = 0; prefs.h = 0; savePrefs(); place(); });
        const sl = el("label"); sl.append(el("span", null, ffT("大小（拖拉角落調整）")), size); box.appendChild(sl);
        box.appendChild(el("div", "note", ffT("加到不熟和收藏的詞會先存在這裡，按「傳到 App」就會打開方方詞卡加進去。台語的聲調顏色照說出來的聲調：只有最後一個音節保持本調，其餘變調；輕聲是灰色。收藏的時候也會記住詞所在的那一句話。")));
        return box;
    }
    const POSITIONS = [["word", "詞的旁邊"], ["tl", "左上角"], ["tr", "右上角"], ["bl", "左下角"], ["br", "右下角"]];
    let placeNames = null;
    ask({ op: "places" }).then(r => { if (r && r.ok) placeNames = r.places; });

    function redraw() { if (last) show(last.rect, last.spot, render(last.res)); }

    let shownRect = null;
    // the card is closing (its animation running): the time it's put away
    let closeTimer = 0, closing = false;
    /// the card is on the screen (and not on its way out)
    function isOpen() { return !!card && card.style.display !== "none" && !closing; }
    function show(rect, spot, content) {
        ensureHost();
        // (a video full screen: the card goes inside it, or it couldn't be seen)
        const fsT = fsTarget();
        if (host.parentNode !== fsT) fsT.appendChild(host);
        clearTimeout(hideTimer);
        // (already showing: only its words change, no animation)
        const opening = !isOpen();
        clearTimeout(closeTimer); closing = false;
        body.replaceChildren(content);
        if (opening) card.classList.add("off");
        card.style.display = "flex";
        shownRect = rect;
        place();
        if (opening || spot !== shownSpot) shownAt = Date.now();
        shownSpot = spot;
        if (opening) {
            void card.offsetWidth;              // (the hidden state is drawn first, so the change animates)
            requestAnimationFrame(() => { if (!closing) card.classList.remove("off"); });
        }
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
        const w = card.offsetWidth, rect = shownRect || { left: 8, top: 8, bottom: 8 };
        const pos = prefs.pos || "word";
        let h = card.offsetHeight;
        let left, top;
        if (pos === "word") {
            // (strictly under or over the word, never over its line: under it when it fits, else over it when it fits
            // there, else on the side with more room, made only as tall as that room, its words scrolling inside)
            const gap = 8, edge = 8;
            const below = vh - rect.bottom - gap - edge, over = rect.top - gap - edge;
            const up = h > below && (h <= over || over > below);
            const room = Math.max(40, Math.floor(up ? over : below));
            if (h > room) {
                if (prefs.h) card.style.height = room + "px"; else card.style.maxHeight = room + "px";
                h = card.offsetHeight;
            }
            left = Math.min(Math.max(8, rect.left), vw - w - 8);
            top = up ? rect.top - gap - h : rect.bottom + gap;
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
        // (the animation grows out of the word: from the card's edge next to it)
        const cl = Math.max(8, left), ct = Math.max(8, top);
        const above = shownRect && ct + h <= shownRect.top + 2;
        const wx = shownRect ? Math.min(Math.max((shownRect.left + shownRect.right) / 2 - cl, 12), w - 12) : w / 2;
        card.style.transformOrigin = (pos === "word" ? wx + "px " : (pos[1] === "l" ? "0 " : "100% ")) + (above || (pos !== "word" && pos[0] === "b") ? "100%" : "0");
        card.style.setProperty("--ff-dy", (above || (pos !== "word" && pos[0] === "b")) ? "6px" : "-6px");
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
        subsCardHidden();
        unmark();
        shownSpot = "";
        if (!isOpen()) return;
        // fades and shrinks away, then is put away
        closing = true;
        card.classList.add("off");
        clearTimeout(closeTimer);
        closeTimer = setTimeout(() => { if (closing) { card.style.display = "none"; closing = false; } }, 200);
    }
    function hideSoon() {
        clearTimeout(hideTimer);
        if (subsCard()) return;                    // (a subtitle word's card: not closed by the pointer moving)
        if (isOpen() && !card.querySelector(".set")) hideTimer = setTimeout(hide, HIDE);
    }
    const inCard = e => host && e.composedPath && e.composedPath().includes(host);
    /// the pointer over the subtitle panel (its words open with a tap or a click there, never by hovering)
    function overSubs(e) {
        if (e.target && e.target.closest && e.target.closest("#ff-subs, #ff-mine, #ff-defs")) return true;
        const p = typeof subs !== "undefined" && subs && subs.panel;
        if (!p || p.classList.contains("hidden")) return false;
        const r = p.getBoundingClientRect();
        return e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom;
    }

    // ── the Pencil (or a trackpad / mouse) hovering ─────────────────────────────────────────
    // (the Pencil, a trackpad or a mouse; on the Mac, Safari may send only mouse events)
    let lastPointer = 0;
    let px = -1, py = -1;          // (where the pointer is: for the keys that mark the word under it)
    // (at most once a frame: a mouse can tell of its moves far more often than the screen is drawn, and on a long
    // page like Wikipedia's each look at the text under the pointer takes a while)
    let moveEv = null, moveRaf = 0;
    function hoverSoon(e) {
        moveEv = e;
        if (moveRaf) return;
        moveRaf = requestAnimationFrame(() => { moveRaf = 0; const ev = moveEv; moveEv = null; if (ev) hover(ev); });
    }
    document.addEventListener("pointermove", e => {
        if (e.pointerType === "touch") return;
        lastPointer = Date.now();
        px = e.clientX; py = e.clientY;
        hoverSoon(e);
    }, { capture: true, passive: true });
    document.addEventListener("mousemove", e => {
        px = e.clientX; py = e.clientY;
        if (Date.now() - lastPointer < 300) return;               // (already handled as a pointer event)
        hoverSoon(e);
    }, { capture: true, passive: true });

    // ── keys: the word under the pointer, 認識 (A) or 不熟 + 收藏 (S), without opening anything ──────────
    document.addEventListener("keydown", async e => {
        if (!alive() || !prefs.keys || e.metaKey || e.ctrlKey || e.altKey || e.repeat) return;
        const k = (e.key || "").toLowerCase();
        const want = k === String(prefs.keyKnown || "a").toLowerCase() ? "known" : (k === String(prefs.keyNew || "s").toLowerCase() ? "new" : "");
        if (!want) return;
        // (typing somewhere: not ours)
        const a = document.activeElement;
        if (a && (a.isContentEditable || /^(input|textarea|select)$/i.test(a.tagName))) return;
        if (px < 0 || document.getElementById("ff-mine")) return;
        // (over a card above the subtitles: its word)
        const over = document.elementFromPoint(px, py);
        const dc = over && over.closest ? over.closest("#ff-defs .dc") : null;
        if (dc && dc.__o) {
            e.preventDefault(); e.stopImmediatePropagation();
            keyMark(want, dc.__o.e.k, dc.__o.x || "", dc.__o.L);
            return;
        }
        const hit = charAt(px, py);
        if (!hit) return;
        const inSubs = hit.node.parentElement && hit.node.parentElement.closest("#ff-subs");
        if (!prefs.on && !inSubs) return;
        const lat = !isHan(hit.cp) && (prefs.sv || prefs.eng) && isLat(hit.cp) ? latWordAt(hit.node, hit.off) : null;
        if (!isHan(hit.cp) && !lat) return;
        // (the site's own use of the key, e.g. YouTube's, doesn't happen: the pointer is on a word)
        e.preventDefault(); e.stopImmediatePropagation();
        const sc = inSubs ? subsCueAt(hit.node, hit.off) : null;
        const text = lat ? lat.text : (sc && sc.text ? sc.text : textFrom(hit.node, hit.off));
        const res = lat ? await findLatin(text) : await find(text);
        if (!res || !res.ok) return;
        // the first language the card would show
        let pick = null, lang = "";
        const order = ["zh", "tw", "yue", "hak", "sv", "eng"];
        if (inSubs && subs && subs.lang) order.sort((a, b) => (b === subs.lang) - (a === subs.lang));
        for (const l of order) {
            const part = res[l];
            if (!part || !part.list) continue;
            const e0 = part.list.find(x => x.k && !(l === "zh" && x.p === 3 && prefs.zhPlace !== 2));
            if (e0) { pick = e0; lang = l; break; }
        }
        if (!pick) return;
        const sentence = (sc ? sc.sentence : sentenceAt(hit.node, lat ? lat.start : hit.off)) || "";
        keyMark(want, pick.k, sentence, lang, sc ? sc.tr : "");
    }, true);

    /// A / S on a word: 認識, or 不熟 + 收藏 (with its sentence)
    function keyMark(want, key, sentence, lang, trans) {
        const han = key.split("\t")[0];
        if (want === "known") {
            queue = queue.filter(q => !(q.k === key && (q.w === "unknown" || q.w === "known")));
            queue.push({ k: key, w: "known", h: han, t: Date.now() });
            localAdd(han, keyLang(key)); saveKnownLocal();
        } else {
            queue = queue.filter(q => !(q.k === key && (q.w === "known" || q.w === "unknown" || q.w === "saved")));
            queue.push(withGroup({ k: key, w: "unknown", h: han, x: sentence, tr: trans || "", t: Date.now() }));
            queue.push(withGroup({ k: key, w: "saved", h: han, x: sentence, tr: trans || "", t: Date.now() }));
            localDel(han, keyLang(key)); saveKnownLocal();
            if (!saved.some(x => x.h === han)) { saved.push({ h: han, c: [] }); saveSaved(); }
        }
        saveQueue();
        pageMarks();
        if (subs && subs.key) subsColour(subs.key);
        if (isOpen() && last && !card.querySelector(".set")) redraw();
        const NAMES = { zh: ffT("華語"), tw: ffT("台語"), yue: ffT("粵語"), hak: ffT("客語"), sv: ffT("瑞典語"), eng: ffT("英語") };
        toast((want === "known" ? ffT("認識：") : ffT("不熟＋收藏：")) + han + ffT("（") + NAMES[lang] + ffT("）"), want === "known" ? "#3fae66" : "#c9a227");
        if (subs) subsDefs(true);
    }

    /// a short note near the pointer, fading away
    function toast(text, colour) {
        const t = document.createElement("div");
        t.textContent = text;
        t.style.cssText = "all:initial;position:fixed;z-index:2147483647;padding:7px 12px;border-radius:10px;" +
            "font:600 14px -apple-system,'PingFang TC',sans-serif;color:#fff;background:rgba(20,22,30,.92);" +
            "border:1px solid " + colour + ";box-shadow:0 6px 18px rgba(0,0,0,.35);pointer-events:none;" +
            "opacity:1;" +
            "left:" + Math.max(8, Math.min(window.innerWidth - 220, px + 12)) + "px;top:" + Math.max(8, py - 46) + "px";
        fsTarget().appendChild(t);
        t.animate([{ opacity: 0, transform: "translateY(6px)" }, { opacity: 1, transform: "none" }], { duration: 220, easing: "ease-out" });
        setTimeout(() => {
            const out = t.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "translateY(-6px)" }], { duration: 400, easing: "ease-in", fill: "forwards" });
            out.onfinish = () => t.remove();
        }, 1400);
    }

    let hitBox = null;            // (the character the pointer was last found over, where it is on the screen)
    function hover(e) {
        // (網頁查詞 turned off in Safari's toolbar: only the subtitle panel's words are still looked up)
        if (!alive() || (!prefs.on && !(e.target && e.target.closest && e.target.closest("#ff-subs")))) return;
        // (the subtitle panel: nothing by hovering; its words open with a tap or a click)
        // (checked three ways: the element under the pointer, the panel's place on the screen, and the text found)
        if (overSubs(e)) { clearTimeout(dwellTimer); return; }
        if (e.buttons !== 0) return;                              // writing / dragging, not hovering
        if (!metaP) getMeta();                                    // (the Pencil is near: the tables read already)
        if (inCard(e)) { clearTimeout(hideTimer); clearTimeout(dwellTimer); return; }
        // (still over the same character as last time: nothing to find again; reading where the text is under the
        // pointer is slow on long pages, so it's done once per character, not on every move)
        if (hitBox && e.clientX >= hitBox.left && e.clientX <= hitBox.right && e.clientY >= hitBox.top && e.clientY <= hitBox.bottom) {
            if (lastSpot && lastSpot === shownSpot) clearTimeout(hideTimer);
            return;
        }
        const hit = charAt(e.clientX, e.clientY);
        hitBox = hit && hit.rect && hit.node && hit.node.isConnected ? hit.rect : null;
        if (hit && hit.node && hit.node.parentElement && hit.node.parentElement.closest("#ff-subs")) { clearTimeout(dwellTimer); return; }
        // (瑞典語: a Latin letter, the whole word around it)
        // (a Latin word: 瑞典語, and English → the Chinese languages)
        const lat = hit && !isHan(hit.cp) && (prefs.sv || prefs.eng) && isLat(hit.cp) ? latWordAt(hit.node, hit.off) : null;
        if (!hit || (!isHan(hit.cp) && !lat)) { clearTimeout(dwellTimer); lastSpot = ""; hideSoon(); return; }
        const spot = lat ? "w" + lat.start + ":" + lat.text + "@" + Math.round(hit.rect.top) : hit.off + "@" + Math.round(hit.rect.left) + "," + Math.round(hit.rect.top);
        if (spot === shownSpot) { clearTimeout(hideTimer); return; }
        if (spot === lastSpot) return;
        lastSpot = spot;
        clearTimeout(dwellTimer);
        if (lat) {
            getMeta().then(m => {
                if (m && m.sv && prefs.sv) getFile(svShard(lat.text.toLowerCase(), m));
                if (m && m.eng && prefs.eng) getFile(engShard(lat.text.toLowerCase(), m));
            });
        } else prefetch(hit.cp);
        const go = () => {
            if (lat) { lookup(lat.text, hit.rect, spot, { node: hit.node, off: lat.start }, true); return; }
            const text = textFrom(hit.node, hit.off);
            if (text) lookup(text, hit.rect, spot, { node: hit.node, off: hit.off });
        };
        // (moving along a line with the card showing: the next word at once)
        if (isOpen()) go(); else dwellTimer = setTimeout(go, DWELL);
    }

    document.addEventListener("pointerleave", e => { if (e.pointerType === "pen") { clearTimeout(dwellTimer); lastSpot = ""; } }, true);
    document.addEventListener("pointerdown", e => { if (!inCard(e)) { clearTimeout(dwellTimer); hide(); } }, true);
    window.addEventListener("scroll", e => {
        if (host && e.target === host) return;          // (scrolling inside the card)
        // (Firefox also tells of scrolls inside the page's parts, e.g. YouTube's player when the video pauses on the
        // tap: those, and the subtitle panel's own, don't close the card of a subtitle word; only the page scrolling
        // does, and not in the first moment after it opened)
        const t = e.target;
        const page = t === document || t === document.documentElement || t === document.body || t === document.scrollingElement;
        const inSubs = t && t.nodeType === 1 && t.closest && t.closest("#ff-subs, #ff-mine, #ff-defs");
        if (inSubs && !page) return;
        hitBox = null;
        if (subsCard() && (!page || Date.now() - shownAt < 600)) return;
        if (!subsCard() && isOpen()) {
            // (a word on the page: closed only when the word itself has moved. Sites like YouTube scroll parts of
            // the page by themselves all the time, which used to close the card the moment it opened)
            if (scrollRaf) return;
            scrollRaf = requestAnimationFrame(() => {
                scrollRaf = 0;
                if (!isOpen() || subsCard()) return;
                if (shownWord && shownWord.node.isConnected) {
                    const b = wordRange(shownWord.node, shownWord.off, 1).getBoundingClientRect();
                    if (Math.abs(b.top - shownWord.top) < 4 && Math.abs(b.left - shownWord.left) < 4) return;
                }
                clearTimeout(dwellTimer); lastSpot = ""; hide();
            });
            return;
        }
        clearTimeout(dwellTimer); lastSpot = ""; hide();
    }, { passive: true, capture: true });
    let scrollRaf = 0;
    document.addEventListener("keydown", e => { if (e.key === "Escape") hide(); }, true);

    // ── selecting text with a finger (for iPads without Pencil hover) ───────────────────────
    let selTimer = null;
    document.addEventListener("selectionchange", () => {
        clearTimeout(selTimer);
        selTimer = setTimeout(() => {
            if (!prefs.on || !alive()) return;
            const sel = document.getSelection();
            if (!sel || sel.isCollapsed || sel.rangeCount === 0) return;
            // (text selected in the subtitle panel: its words open with a tap there)
            const an = sel.anchorNode && (sel.anchorNode.nodeType === 1 ? sel.anchorNode : sel.anchorNode.parentElement);
            if (an && an.closest && an.closest("#ff-subs")) return;
            const s = sel.toString().trim();
            if (!s) return;
            // (瑞典語: one Latin word)
            const sv = (prefs.sv || prefs.eng) && isLat(s.charCodeAt(0)) && [...s].every(c => isLat(c.charCodeAt(0)));
            if (!sv && ([...s].length > MAXLEN || !isHan(s.codePointAt(0)))) return;
            const rect = sel.getRangeAt(0).getBoundingClientRect();
            const spot = "sel:" + s + "@" + Math.round(rect.left) + "," + Math.round(rect.top);
            if (spot === shownSpot) return;
            lookup(s, rect, spot, null, sv);
        }, 600);
    });

    // ── 影片字幕: the video's subtitles in a panel beside it (under it on a phone) ─────────────
    // The lines before and after the one being said are there too; the panel glides up as the video plays. Words
    // in it are looked up with a tap or a click (not by hovering, as elsewhere on the page), and when one is
    // saved, its line is kept with it as its sentence. The subtitles are the ones the site itself has: on YouTube
    // the video's own (or YouTube's automatic ones), on Viki the ones its player loads, and on any site whose
    // player has subtitle tracks Safari can read.
    const SUBS_SITE = /(^|\.)youtube\.com$|(^|\.)viki\.com$/.test(location.hostname);
    let subs = null;                // the panel's state, once a video with subtitles is there
    // (set before the panel starts below: the copy of the add-on the panel belongs to)
    const SUBS_GEN = String(Math.random()).slice(2);
    // (the card closed after a tap on a word in the panel: the video goes on, unless another word is tapped at once)
    function subsCardHidden() {
        if (!subs || subs.pausedBy !== "tap") return;
        clearTimeout(subs.resumeTimer);
        subs.resumeTimer = setTimeout(() => {
            if (subs.pausedBy !== "tap" || isOpen()) return;
            subs.pausedBy = "";
            const v = subsVideo(); if (v && v.paused) v.play().catch(() => {});
        }, 350);
    }
    // YouTube and Viki: from the start; other sites: once a video is there (its subtitle tracks, when Safari has them)
    if (SUBS_SITE) subsStart();
    else {
        const look = setInterval(() => {
            if (!document.querySelector("video")) return;
            clearInterval(look);
            subsStart();
        }, 3000);
    }

    // (one panel only: when the add-on is updated or turned off and on, the copy already running in the page stops
    // and takes its panel away)
    function subsMine() {
        if (document.documentElement.dataset.ffSubsGen === SUBS_GEN) return true;
        if (subs && subs.panel) { subs.panel.remove(); subs.panel = null; subs.cues = []; }
        return false;
    }
    function subsStart() {
        document.documentElement.dataset.ffSubsGen = SUBS_GEN;
        for (const old of document.querySelectorAll("#ff-subs, #ff-subs-pill")) old.remove();
        const st = {
            files: new Map(),       // key → { cues: [{s, e, t}], han: the share of 漢字, at: when it came }
            key: "",                // the file shown
            vid: "",                // (YouTube) the video the subtitles are for
            ytTracks: [], ytTrans: [], cur: "",
            panel: null, rail: null, view: null, lines: [], cues: [], now: -2,
            manual: 0, manualUntil: 0, collapsed: false, pausedBy: "", tried: new Set(), textTracksAt: 0,
            loop: -1, slow: false, pauseEach: false, stopped: -1, known: null,
        };
        subs = st;
        // the page's own part (sees the player's downloads): in the page's world. Safari runs it from the manifest;
        // when it didn't say hello, it's put in the page here
        let hello = false;
        window.addEventListener("message", e => {
            const d = e.data;
            if (!d || !d.__ffSubs || e.source !== window) return;
            if (d.kind === "hello") hello = true;
            else if (d.kind === "file") subsFile(d.url, d.text);
            else if (d.kind === "tracks") subsTracks(d.text);
            else if (d.kind === "manifest") subsManifest(d.url, d.text);
            else if (d.kind === "got" && pageAsks.has(d.id)) { pageAsks.get(d.id)(d.text || ""); pageAsks.delete(d.id); }
        });
        if (SUBS_SITE) setTimeout(() => {
            if (hello) return;
            try {
                const sc = document.createElement("script");
                sc.src = browser.runtime.getURL("subs-page.js");
                sc.onload = () => sc.remove();
                (document.head || document.documentElement).appendChild(sc);
            } catch (e) {}
        }, 1500);
        // (another video on the same page, as YouTube does; subtitle tracks Safari reads itself)
        setInterval(subsTick, 1000);
    }

    /// where the panel and the card go: inside the element shown full screen (not a bare <video>: iOS's own player)
    function fsTarget() {
        const fs = document.fullscreenElement || document.webkitFullscreenElement;
        return fs && fs.tagName !== "VIDEO" ? fs : document.documentElement;
    }

    function subsVideo() {
        let best = null, area = 0;
        for (const v of document.querySelectorAll("video")) {
            const r = v.getBoundingClientRect(), a = r.width * r.height;
            if (a > area) { area = a; best = v; }
        }
        return best;
    }
    // AirPlay: the video plays on the TV, so the whole screen here is for the subtitles
    function subsAir() {
        const v = subsVideo();
        return !!(v && v.webkitCurrentPlaybackTargetIsWireless);
    }
    // (the letters on the whole screen: twice as big, A− / A+ still change them)
    const subsScale = () => (prefs.subsFont || 1) * (subs && subs.air ? 2 : 1);
    function ytVideoId() {
        if (!/youtube\.com$/.test(location.hostname)) return "";
        const u = new URL(location.href);
        return u.searchParams.get("v") || (u.pathname.match(/\/(shorts|live|embed)\/([\w-]{6,})/) || [])[2] || "";
    }

    // every second: a new video? subtitle tracks Safari has (sites without a file to see)?
    function subsTick() {
        const st = subs;
        if (!subsMine()) return;
        if (!prefs.subs) { if (st.panel) st.panel.style.display = "none"; subsDefs(false); return; }
        subsTint();
        if (subsAir() !== !!st.air) subsLayout();
        const vid = ytVideoId() || (SUBS_SITE ? location.pathname : "");
        if (vid !== st.vid) {
            st.vid = vid; st.files.clear(); st.key = ""; st.ytTracks = []; st.ytTrans = []; st.cur = ""; st.tried.clear();
            st.fullTracks = []; st.fullUrl = ""; st.fullFailed = new Set(); st.hlsSrc = ""; st.fullShift = 0;
            st.ytTransAll = []; st.sec = null; st.secWant = ""; st.secFailed = new Set();
            subsShow([]);
            if (ytVideoId()) subsAskTracks(0);
        }
        // tracks the browser itself loads (<track>, Safari's own HLS subtitles): only the one the site is showing
        // (the language chosen in its player); other languages are never turned on. (Not on YouTube: its own way.)
        const v = subsVideo();
        // (a stream Safari plays itself, .m3u8: its list of parts tells where each language's subtitles are)
        const src = v && (v.currentSrc || v.src) || "";
        if (!ytVideoId() && /\.m3u8\b/i.test(src) && st.hlsSrc !== src) {
            st.hlsSrc = src;
            pageGet(src).then(t => { if (t) subsManifest(src, t); });
        }
        subsFullPick();
        subs2Pick();
        if (!ytVideoId() && v && v.textTracks && v.textTracks.length && Date.now() - st.textTracksAt > 2000 && !String(st.key).startsWith("full:")) {
            st.textTracksAt = Date.now();
            const list = [...v.textTracks].filter(tt => /subtitles|captions/.test(tt.kind));
            let tt = list.find(x => x.mode === "showing");
            if (!tt) { const h = list.filter(x => x.mode === "hidden" && x.cues && x.cues.length); if (h.length === 1) tt = h[0]; }
            if (tt && tt.cues && tt.cues.length) {
                const key = "track:" + (tt.language || tt.label || tt.id);
                const old = st.files.get(key);
                if (!old || old.cues.length !== tt.cues.length) {
                    const cues = [];
                    for (const c of tt.cues) {
                        const t = String(c.text || "").replace(/<[^>]+>/g, "").replace(/\s*\n\s*/g, " ").trim();
                        if (t) cues.push({ s: c.startTime, e: c.endTime, t });
                    }
                    subsAdd(key, cues);
                }
            }
        }
        // the subtitles on the video itself, hidden while the panel shows them (YouTube; players using video.js)
        let hid = document.getElementById("ff-subs-hide");
        const want = st.panel && st.panel.style.display !== "none" && !st.collapsed && prefs.subsHideVideo;
        if (want && !hid) {
            hid = document.createElement("style"); hid.id = "ff-subs-hide";
            hid.textContent = ".ytp-caption-window-container, .caption-window, .ytp-caption-segment, .captions-text, " +
                ".ytm-captions-container, .vjs-text-track-display, .shaka-text-container, video::cue, video::-webkit-media-text-track-container " +
                "{ opacity: 0 !important; visibility: hidden !important; }";
            (document.head || document.documentElement).appendChild(hid);
        } else if (!want && hid) hid.remove();
    }

    // YouTube: the video's subtitle languages (asked of the page; the player takes a moment to have them)
    function subsAskTracks(n) {
        window.postMessage({ __ffSubsAsk: "tracks" }, "*");
        if (n < 8) setTimeout(() => { if (!subs.ytTracks.length && subs.vid === ytVideoId()) subsAskTracks(n + 1); }, 1500);
    }
    // the language wanted: 台語, then 繁體, 粵語, 簡體, 日語, 瑞典語; written ones before automatic ones
    const SUBS_ORDER = ["nan", "zh-TW", "zh-Hant", "zh-HK", "yue", "zh", "zh-Hans", "zh-CN", "zh-SG", "ja", "sv"];
    /// the main subtitles wanted: English ones when 主要的字幕 is 英語, or it's 自動 with 英語 the lookup language
    /// (but not when English is the second subtitles: then Chinese ones are the main, English under them)
    function subsWantEnglish() {
        const sl = prefs.subsLang || "auto";
        if (sl === "eng") return true;
        if (sl !== "auto") return false;
        return activeLang() === "eng" && !/^en/i.test(prefs.subs2 || "");
    }
    function subsRank(t) {
        if (subsWantEnglish() && /^en/i.test(t.lang)) return t.kind === "asr" ? 1 : 0;
        // (the second subtitles' language: not the main one, so both show)
        if (prefs.subs2 && subs2Match(t.lang, prefs.subs2)) return 500 + (t.kind === "asr" ? 1 : 0);
        let i = SUBS_ORDER.findIndex(l => t.lang === l || t.lang.toLowerCase() === l.toLowerCase());
        if (i < 0) i = /^zh/i.test(t.lang) ? 8 : 99;
        return i * 2 + (t.kind === "asr" ? 1 : 0);
    }
    // (a language's name: the track, and 自動翻譯 into another one)
    const subsId = (lang, kind, tl) => lang + "|" + (kind || "") + (tl ? ">" + tl : "");
    // 自動翻譯 offered into these (the add-on's languages)
    const SUBS_TRANS = ["zh-Hant", "zh-TW", "zh-Hans", "zh-CN", "ja", "sv"];
    async function subsTracks(text) {
        let j = null;
        try { j = JSON.parse(text); } catch (e) { return; }
        if (!j || !j.tracks || !j.tracks.length) return;
        if (j.vid && j.vid !== ytVideoId()) return;
        const first = !subs.ytTracks.length;
        subs.ytTracks = j.tracks;
        subs.ytTrans = (j.trans || []).filter(t => SUBS_TRANS.includes(t.lang));
        subs.ytTransAll = j.trans || [];
        // (the first time: the language wanted; after that, whatever the player shows stays). No subtitles in a
        // language of the add-on: YouTube's translation of them into 繁體中文
        if (first && !subs.key) {
            const pick = [...j.tracks].sort((a, b) => subsRank(a) - subsRank(b))[0];
            const zh = subs.ytTrans.find(t => t.lang === "zh-Hant") || subs.ytTrans.find(t => t.lang === "zh-TW");
            if (pick && subsRank(pick) >= 198 && zh) subsUseTrack(subsBase(), zh);
            else if (pick) subsUseTrack(pick);
        }
        subsHeader();
    }
    /// 主要的字幕 or the second subtitles changed: the main ones picked again the same way as at the start
    function subsRepick() {
        const st = subs;
        if (!st || !st.ytTracks || !st.ytTracks.length) return;
        const pick = [...st.ytTracks].sort((a, b) => subsRank(a) - subsRank(b))[0];
        const zh = (st.ytTrans || []).find(t => t.lang === "zh-Hant") || (st.ytTrans || []).find(t => t.lang === "zh-TW");
        let id = "";
        if (pick && subsRank(pick) >= 198 && zh) { const b = subsBase(); id = subsId(b.lang, b.kind, zh.lang); if (id !== st.cur) subsUseTrack(b, zh); }
        else if (pick) { id = subsId(pick.lang, pick.kind); if (id !== st.cur) subsUseTrack(pick); }
        setTimeout(() => subs2Pick(true), 400);
    }
    /// what YouTube translates from: the video's own subtitles (written ones before automatic ones)
    function subsBase() {
        const ts = subs.ytTracks;
        return ts.find(t => t.kind !== "asr") || ts[0];
    }
    // a YouTube language (or its 自動翻譯): read straight from YouTube when it allows that, and the player is asked
    // to show the same (when YouTube doesn't allow it, the copy of what the player downloads is used)
    function subsUseTrack(t, tr) {
        const st = subs;
        const id = subsId(t.lang, t.kind, tr && tr.lang);
        st.cur = id;
        st.want = id;
        subsDrop();                                  // (the old language: gone at once)
        window.postMessage({ __ffSubsAsk: "use", lang: t.lang, kind: t.kind || "", tl: tr ? tr.lang : "", tlName: tr ? tr.name : "" }, "*");
        clearTimeout(st.wantTimer);
        st.wantTimer = setTimeout(async () => {
            if (st.want !== id || st.key) return;
            try {
                let url = t.url + (tr ? "&tlang=" + encodeURIComponent(tr.lang) : "");
                if (!url.includes("fmt=")) url += "&fmt=json3";
                const r = await fetch(url, { credentials: "include" });
                const txt = r.ok ? await r.text() : "";
                const cues = txt ? subsParse(txt) : [];
                if (cues.length && st.want === id && !st.key) subsAdd("yt:" + st.vid + ":" + id, cues);
            } catch (e) {}
        }, 0);
        subsHeader();
    }
    /// every line gone (a new language coming)
    function subsDrop() {
        subs.files.clear();
        subs.key = "";
        subsShow([]);
    }

    // a subtitle file the page downloaded
    function subsFile(url, text) {
        if (!prefs.subs || !text || !subsMine()) return;
        // (the whole subtitles already loaded from the stream's list: the player's own pieces aren't needed)
        if (String(subs.key).startsWith("full:") && !/timedtext/.test(url)) return;
        const cues = subsParse(text);
        if (!cues.length) return;
        let key;
        try {
            const u = new URL(url, location.href);
            if (/timedtext/.test(u.pathname)) {
                const v = u.searchParams.get("v") || subs.vid;
                if (v && subs.vid && v !== subs.vid) return;                // (another video's)
                // the language the player shows (chosen in the panel or in the player's own menu; a translation,
                // "lang>tlang", is a language of its own)
                const id = subsId(u.searchParams.get("lang") || "", u.searchParams.get("kind") || "", u.searchParams.get("tlang") || "");
                key = "yt:" + v + ":" + id;
                if (subs.cur !== id) { subs.cur = id; subsHeader(); }
                subs.want = "";
            } else {
                // (a file in pieces, as streams send them: the pieces of one language go together)
                key = "f:" + u.hostname + u.pathname.replace(/[^/]*$/, "").replace(/\d{2,}/g, "#") + (u.pathname.match(/[a-z]{2}(-[A-Za-z]{2,4})?(?=[._/-])/g) || []).slice(-1)[0];
            }
        } catch (e) { key = "f:" + url; }
        subsAdd(key, cues);
    }

    // ── 詞卡 over the row at the bottom: a panel of the same size at the top of the screen, with a card for each word
    // of the line being said that you don't know yet (reading, word, meaning). Tap a card for the whole entry;
    // A / S over a card marks its word.
    function subsDefs(force) {
        const st = subs;
        let box = document.getElementById("ff-defs");
        const on = st && st.panel && st.flow && !st.collapsed && prefs.subsDefs && prefs.subs &&
            !st.panel.classList.contains("hidden") && st.panel.style.display !== "none";
        if (!on) { if (box) box.remove(); return; }
        const fsT = fsTarget();
        if (!box) {
            box = document.createElement("div");
            box.id = "ff-defs";
            if (/Firefox\//.test(navigator.userAgent)) box.classList.add("fx");
            box.addEventListener("pointerdown", e => e.stopPropagation());
            st.defsAt = null;
        }
        if (box.parentNode !== fsT) fsT.appendChild(box);
        box.classList.toggle("clear", subsBgMode() === "clear" && !st.air);
        // (AirPlay: the top part of the screen, the subtitles under it)
        box.classList.toggle("air", !!st.air);
        box.style.height = st.air ? Math.max(120, Math.round(window.innerHeight * 0.42) - 96) + "px" : st.panel.offsetHeight + "px";
        box.style.setProperty("--ff-defs-font", Math.round(18 * subsScale()) + "px");
        // (the line being said; before the first one, the first)
        const at = st.now >= 0 ? st.now : 0;
        const cue = st.cues[at];
        const sig = at + "|" + (cue && cue.unk ? cue.unk.map(u => u.w).join(",") : "?");
        if (!force && st.defsAt === sig) return;
        st.defsAt = sig;
        box.replaceChildren();
        const list = (cue && cue.unk) || [];
        if (!list.length) {
            const n = document.createElement("div");
            n.className = "none";
            n.textContent = cue && cue.unk ? ffT("這句沒有不認識的詞") : "";
            box.appendChild(n);
            return;
        }
        const meta = st.meta;
        const sentence = cue.t.replace(/\s+/g, " ").trim();
        const t2 = st.lines && st.lines[at] && st.lines[at].querySelector(".t2");
        const trans = (st.trs && st.trs[at]) || (t2 ? t2.textContent.replace(/\s+/g, " ").trim() : "");
        for (const o of list) {
            const c = document.createElement("div");
            c.className = "dc" + (o.learn ? " learn" : "");
            c.__o = { ...o, x: sentence };
            let p = { h: [], r: [] };
            try { p = subsParts(o.e, o.L, meta); } catch (err) {}
            const rd = document.createElement("div"); rd.className = "rd";
            (p.r || []).forEach((sg, i) => { const x = document.createElement("span"); x.textContent = i && o.L === "zh" && !sg.t.startsWith(" ") ? " " + sg.t : sg.t; if (sg.c && subsCol()) x.style.color = "#" + sg.c; rd.appendChild(x); });
            const h = document.createElement("div"); h.className = "h";
            (p.h || []).forEach(sg => { const x = document.createElement("span"); x.textContent = sg.t; if (sg.c && subsCol()) x.style.color = "#" + sg.c; h.appendChild(x); });
            if (!h.textContent) h.textContent = o.w;
            const gl = document.createElement("div"); gl.className = "gl";
            gl.textContent = subsGlossLong(o.e);
            c.append(rd, h, gl);
            c.addEventListener("click", ev => {
                ev.stopPropagation();
                const v = subsVideo();
                if (prefs.subsPause && v && !v.paused) { v.pause(); st.pausedBy = "tap"; }
                lookup(o.w, c.getBoundingClientRect(), "defs:" + o.w, null).then(() => { lastSentence = sentence; lastTrans = trans; });
            });
            box.appendChild(c);
        }
    }
    /// a word's meaning on its card: more than under the word (the first two senses), English or 中文 as 英文 is set
    function subsGlossLong(e) {
        const en = () => e.e ? e.e.split(";").slice(0, 3).map(x => x.trim()).filter(Boolean).join("; ") : "";
        const zh = () => {
            if (!e.m) return "";
            const m = e.m.replace(/^\s*[0-9０-９]+[.．、]\s*/, "").replace(/\s+/g, " ").trim();
            return [...m].length > 60 ? [...m].slice(0, 58).join("") + "…" : m;
        };
        return prefs.en ? (en() || zh()) : (zh() || en());
    }

    // ── the panels' colour: the colour most of what's under them has (the part of the video under them, or the
    // page's background), darkened when it's light so the words stay easy to read. A video that can't be read
    // (protected, like some streams' are) leaves them dark.
    const tintCv = document.createElement("canvas");
    tintCv.width = 32; tintCv.height = 10;
    function subsBgMode() { return ["tint", "dark", "clear"].includes(prefs.subsBg) ? prefs.subsBg : "dark"; }
    function subsTint() {
        const st = subs;
        const mode = subsBgMode();
        for (const el of [st && st.panel, document.getElementById("ff-defs")]) {
            if (!el) continue;
            el.classList.toggle("clear", mode === "clear");
            const c = mode === "tint" ? tintUnder(el) : null;
            if (c) el.style.setProperty("--ff-bg", c); else el.style.removeProperty("--ff-bg");
        }
    }
    function tintUnder(el) {
        const r = el.getBoundingClientRect();
        if (!r.width || !r.height) return null;
        // (a video under the panel: its picture, or nothing when it can't be read; never what's around it, like the
        // player's own coloured box behind the picture)
        for (const v of document.querySelectorAll("video")) {
            const vr = v.getBoundingClientRect();
            if (vr.width && vr.right > r.left && vr.left < r.right && vr.bottom > r.top && vr.top < r.bottom) return videoTint(v, r);
        }
        let stack = [];
        try { stack = document.elementsFromPoint(r.left + r.width / 2, r.top + r.height / 2); } catch (e) { return null; }
        for (const x of stack) {
            if (x.closest && x.closest("#ff-subs, #ff-defs, #ff-mine")) continue;
            if (x.tagName === "VIDEO") return videoTint(x, r);
            const m = (getComputedStyle(x).backgroundColor || "").match(/rgba?\(([^)]+)\)/);
            if (!m) continue;
            const [cr, cg, cb, ca = 1] = m[1].split(",").map(Number);
            if (ca >= 0.5) return tintOf(cr, cg, cb);
        }
        return null;
    }
    function videoTint(v, r) {
        const st = subs;
        if (!v.videoWidth || (st.tintFail && Date.now() - st.tintFail < 15000)) return null;
        // (a protected video, as Viki's often are: its picture can't be read, and what comes back isn't its colour)
        if (v.mediaKeys || v.webkitKeys) return null;
        const vr = v.getBoundingClientRect();
        // (where the picture is in the video's box: the rest is black bars)
        const sc = Math.min(vr.width / v.videoWidth, vr.height / v.videoHeight);
        const cw = v.videoWidth * sc, ch = v.videoHeight * sc, cx = vr.left + (vr.width - cw) / 2, cy = vr.top + (vr.height - ch) / 2;
        const x0 = Math.max(r.left, cx), y0 = Math.max(r.top, cy), x1 = Math.min(r.right, cx + cw), y1 = Math.min(r.bottom, cy + ch);
        if (x1 - x0 < 4 || y1 - y0 < 4) return tintOf(0, 0, 0);
        try {
            const g = tintCv.getContext("2d", { willReadFrequently: true });
            g.drawImage(v, (x0 - cx) / sc, (y0 - cy) / sc, (x1 - x0) / sc, (y1 - y0) / sc, 0, 0, tintCv.width, tintCv.height);
            const d = g.getImageData(0, 0, tintCv.width, tintCv.height).data;
            // (the colour most of it has: the pixels sorted into rough colours, the biggest group's average)
            const groups = new Map();
            for (let i = 0; i < d.length; i += 4) {
                const k = (d[i] >> 5) << 6 | (d[i + 1] >> 5) << 3 | (d[i + 2] >> 5);
                const a = groups.get(k) || [0, 0, 0, 0];
                a[0] += d[i]; a[1] += d[i + 1]; a[2] += d[i + 2]; a[3]++;
                groups.set(k, a);
            }
            let best = null;
            for (const a of groups.values()) if (!best || a[3] > best[3]) best = a;
            return best ? tintOf(best[0] / best[3], best[1] / best[3], best[2] / best[3]) : null;
        } catch (e) {
            st.tintFail = Date.now();
            return null;
        }
    }
    /// the colour as the panels' background: light ones darkened (the words on it are light)
    function tintOf(r, g, b) {
        const lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
        const k = lum > 0.3 ? 0.3 / lum : 1;
        return `rgba(${Math.round(r * k)}, ${Math.round(g * k)}, ${Math.round(b * k)}, 0.9)`;
    }

    // ── 影片詞組: the words chosen while a video with subtitles is on go into its group (one per video / episode),
    // which the app keeps together: g its id (the video), gn its name (the page's title), gu its address
    function videoGroup() {
        const st = subs;
        if (!st || !st.cues || !st.cues.length) return null;
        const yt = ytVideoId();
        const id = yt ? "yt:" + yt : (/viki\./.test(location.hostname) ? "viki:" : location.hostname + ":") + location.pathname;
        const name = (document.title || "").replace(/^\(\d+\)\s*/, "").replace(/\s*[-|｜]\s*(YouTube|Viki|Rakuten Viki)\s*$/i, "").trim() || id;
        const u = yt ? "https://www.youtube.com/watch?v=" + yt : location.origin + location.pathname;
        return { id, name, u };
    }
    /// words chosen before there were 影片詞組, whose sentence is a line of this video: into its group (once each)
    function subsRegroup(st) {
        if (!foundBy.size || !st.cues.length) return;
        const g = videoGroup();
        if (!g) return;
        const add = [];
        for (const c of st.cues) {
            for (const t of [c.t, c.o]) {
                const ks = t != null && foundBy.get(sentNorm(t));
                if (!ks) continue;
                for (const k of ks) if (!grouped.has(k) && !add.includes(k)) add.push(k);
            }
        }
        if (!add.length) return;
        for (const k of add) {
            grouped.add(k);
            queue.push({ k, w: "group", h: k.split("\t")[0], g: g.id, gn: g.name, gu: g.u });
        }
        saveQueue();
        store.set({ ffGrouped: [...grouped] }).catch(() => {});
        toast(ffT("這部影片裡有 ") + add.length + ffT(" 個之前選的詞：放進它的影片詞組了（按「傳到 App」）"), "#6eaaff");
    }
    function withGroup(q) {
        const g = videoGroup();
        if (g) { q.g = g.id; q.gn = g.name; q.gu = g.u; }
        return q;
    }

    // ── whole subtitles of a stream (Viki and the like): the player loads them a line or two at a time, as the video
    // plays; the stream's list of parts (manifest.mpd / .m3u8) says where all of them are, so they're loaded at once
    const pageAsks = new Map();
    /// a file loaded by the page itself (the stream's files are allowed to it)
    function pageGet(url) {
        return new Promise(res => {
            const id = "g" + Math.random().toString(36).slice(2);
            pageAsks.set(id, res);
            window.postMessage({ __ffSubsAsk: "get", url, id }, "*");
            setTimeout(() => { if (pageAsks.has(id)) { pageAsks.delete(id); res(""); } }, 20000);
        });
    }
    /// a stream's list of parts: the subtitle languages in it, and where each one's file (or list of pieces) is
    function subsManifest(url, text) {
        const st = subs;
        if (!st || !text || !subsMine()) return;
        st.fullTracks = st.fullTracks || [];
        const found = [];
        try {
            if (text.trim().startsWith("#EXTM3U")) {
                for (const line of text.split(/\r?\n/)) {
                    if (!/^#EXT-X-MEDIA:/.test(line) || !/TYPE=SUBTITLES/.test(line)) continue;
                    const at = k => (line.match(new RegExp(k + '="([^"]*)"')) || [])[1] || "";
                    const uri = at("URI");
                    if (uri) found.push({ lang: at("LANGUAGE") || at("NAME"), name: at("NAME"), url: new URL(uri, url).href, kind: "hls" });
                }
            } else if (/<MPD[\s>]/.test(text)) {
                const x = new DOMParser().parseFromString(text, "text/xml");
                const base = (el, from) => { const b = [...el.children].find(c => c.localName === "BaseURL"); return b ? new URL(b.textContent.trim(), from).href : from; };
                const root = base(x.documentElement, url);
                for (const per of x.getElementsByTagName("Period")) {
                    const pb = base(per, root);
                    for (const as of per.getElementsByTagName("AdaptationSet")) {
                        const reps = [...as.getElementsByTagName("Representation")];
                        const mime = (as.getAttribute("mimeType") || "") + " " + reps.map(r => r.getAttribute("mimeType") || "").join(" ");
                        if (as.getAttribute("contentType") !== "text" && !/text\/vtt|vtt|ttml|text\//.test(mime)) continue;
                        if (/mp4/.test(mime)) continue;          // (pieces packed in video files: not read)
                        const ab = base(as, pb);
                        const r = reps[0];
                        const href = r && [...r.children].some(c => c.localName === "BaseURL") ? base(r, ab) : (ab !== pb ? ab : "");
                        if (!href) continue;
                        const lab = [...as.children].find(c => c.localName === "Label");
                        found.push({ lang: as.getAttribute("lang") || "", name: lab ? lab.textContent : "", url: href, kind: "file" });
                    }
                }
            }
        } catch (e) {}
        for (const f of found) if (!st.fullTracks.some(t => t.url === f.url)) st.fullTracks.push(f);
        if (found.length) { subsFullPick(); if (st.panel) subsHeader(); subs2Pick(); }
    }
    /// which language's whole subtitles to load: the one the player shows; else the add-on's language
    function subsFullPick() {
        const st = subs;
        if (!st || !st.fullTracks || !st.fullTracks.length || st.fullBusy) return;
        const v = subsVideo();
        const showing = v && v.textTracks ? [...v.textTracks].find(t => t.mode === "showing") : null;
        const norm = l => String(l || "").toLowerCase();
        const pref = { zh: ["zt", "zh-hant", "zh-tw", "zh-hk", "zh", "zh-hans", "zh-cn", "cmn"], tw: ["nan", "zh-min", "zt", "zh-hant", "zh-tw", "zh"],
            yue: ["yue", "zh-hk", "zt", "zh-hant", "zh"], hak: ["hak", "zt", "zh-hant", "zh"], sv: ["sv"], eng: ["en", "en-us", "en-gb"] }[activeLang()] || ["zh"];
        const want = showing ? [norm(showing.language), norm(showing.label)] : [];
        let tr = null;
        for (const w of want) { if (!w) continue; tr = st.fullTracks.find(t => norm(t.lang) === w) || st.fullTracks.find(t => norm(t.lang).startsWith(w) || w.startsWith(norm(t.lang)) && norm(t.lang)); if (tr) break; }
        if (!tr) for (const w of pref) { tr = st.fullTracks.find(t => norm(t.lang) === w); if (tr) break; }
        if (!tr || tr.url === st.fullUrl || (st.fullFailed && st.fullFailed.has(tr.url))) return;
        subsFullLoad(tr, showing);
    }
    /// a language's whole subtitles from the stream (its file, or its list of pieces), in order, each line once;
    /// null: another video by then
    async function subsFullFetch(tr) {
        const st = subs, vid = st.vid;
        let cues = [];
        try {
            if (tr.kind === "hls") {
                const list = await pageGet(tr.url);
                const parts = list.split(/\r?\n/).map(l => l.trim()).filter(l => l && !l.startsWith("#")).map(l => new URL(l, tr.url).href);
                for (let i = 0; i < parts.length; i += 8) {
                    const texts = await Promise.all(parts.slice(i, i + 8).map(pageGet));
                    for (const t of texts) cues.push(...subsParse(t));
                    if (st.vid !== vid) return null;
                }
            } else {
                cues = subsParse(await pageGet(tr.url));
            }
        } catch (e) { cues = []; }
        if (st.vid !== vid) return null;
        // (in order, each line once: pieces of a stream repeat the lines at their edges)
        cues.sort((a, b) => a.s - b.s);
        return cues.filter((c, i) => !i || !(Math.abs(c.s - cues[i - 1].s) < 0.05 && c.t === cues[i - 1].t));
    }
    async function subsFullLoad(tr, showing) {
        const st = subs;
        st.fullBusy = true;
        let cues;
        try { cues = await subsFullFetch(tr); } finally { st.fullBusy = false; }
        if (!cues) return;
        if (!cues.length) { (st.fullFailed = st.fullFailed || new Set()).add(tr.url); return; }
        // (the same times as the player's: a line it already has tells how far off the file's clock is)
        if (showing && showing.cues && showing.cues.length) {
            const norm = t => String(t || "").replace(/<[^>]+>/g, "").replace(/\s+/g, "");
            for (const c of showing.cues) {
                const m = cues.find(x => norm(x.t) === norm(c.text));
                if (m) { const d = c.startTime - m.s; if (Math.abs(d) > 0.2) { cues.forEach(x => { x.s += d; x.e += d; }); st.fullShift = d; } break; }
            }
        }
        st.fullUrl = tr.url;
        st.cur = tr.lang;
        subsAdd("full:" + tr.lang, cues);
        subsHeader();
    }

    // the lines of a file: ONE language at a time. A file of another language than the one shown takes its place
    // completely (the language was changed in the player); pieces of the same file are joined
    function subsAdd(key, cues) {
        const st = subs;
        let old = st.files.get(key);
        if (key !== st.key) {
            st.files.clear();
            old = null;
        } else if (old && old.cues.length && cues.length) {
            // (the same name but the same times with other words: another language after all)
            const a = old.cues[0].s, b = old.cues[old.cues.length - 1].e;
            const texts = new Set(old.cues.map(c => c.t));
            const inside = cues.filter(c => c.s >= a && c.s <= b);
            if (inside.length > cues.length * 0.5 && inside.filter(c => texts.has(c.t)).length < inside.length * 0.5) old = null;
        }
        const map = new Map((old ? old.cues : []).map(c => [c.s.toFixed(2) + c.t, c]));
        for (const c of cues) map.set(c.s.toFixed(2) + c.t, c);
        const all = [...map.values()].sort((a, b) => a.s - b.s);
        st.files.set(key, { cues: all, at: Date.now() });
        // (nothing new: nothing drawn again)
        if (key === st.key && old && old.cues.length === all.length) return;
        st.key = key;
        subsShow(all);
    }

    // ── reading subtitle files: YouTube's (json3, xml), WebVTT, SRT ──
    function subsParse(text) {
        text = String(text).replace(/^﻿/, "").trim();
        try {
            if (text.startsWith("{")) {
                const j = JSON.parse(text);
                if (!j.events) return [];
                return subsClean(j.events.filter(e => e.segs && !e.aAppend).map(e => ({
                    s: (e.tStartMs || 0) / 1000, e: ((e.tStartMs || 0) + (e.dDurationMs || 0)) / 1000,
                    t: e.segs.map(g => g.utf8 || "").join("") })));
            }
            if (text.startsWith("<")) {
                const x = new DOMParser().parseFromString(text, "text/xml");
                const out = [];
                for (const n of x.querySelectorAll("text")) {
                    const s = parseFloat(n.getAttribute("start")) || 0;
                    out.push({ s, e: s + (parseFloat(n.getAttribute("dur")) || 0), t: n.textContent });
                }
                for (const n of x.querySelectorAll("p")) {
                    const s = (parseFloat(n.getAttribute("t")) || 0) / 1000;
                    out.push({ s, e: s + (parseFloat(n.getAttribute("d")) || 0) / 1000, t: n.textContent });
                }
                return subsClean(out);
            }
            if (text.includes("-->")) {
                const time = str => {
                    const m = str.trim().replace(",", ".").match(/(?:(\d+):)?(\d+):(\d+(?:\.\d+)?)/);
                    return m ? (parseInt(m[1] || "0") * 3600 + parseInt(m[2]) * 60 + parseFloat(m[3])) : NaN;
                };
                const out = [];
                for (const block of text.split(/\r?\n\s*\r?\n/)) {
                    const ls = block.split(/\r?\n/);
                    const k = ls.findIndex(l => l.includes("-->"));
                    if (k < 0) continue;
                    const [a, b] = ls[k].split("-->");
                    const s = time(a), e = time((b || "").split(/\s+/).filter(Boolean)[0] || "");
                    if (isNaN(s)) continue;
                    out.push({ s, e: isNaN(e) ? s + 2 : e, t: ls.slice(k + 1).join(" ") });
                }
                return subsClean(out);
            }
        } catch (e) {}
        return [];
    }
    // (the subtitles' &amp; &#39; &nbsp; … as the characters they stand for: worked out here, not by the page's HTML)
    const SUBS_ENT = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", hellip: "…", mdash: "—", ndash: "–", lrm: "", rlm: "" };
    function subsEntities(s) {
        return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
            if (e[0] === "#") {
                const n = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
                return n > 0 && n < 0x110000 ? String.fromCodePoint(n) : m;
            }
            const v = SUBS_ENT[e.toLowerCase()];
            return v == null ? m : v;
        });
    }
    function subsClean(cues) {
        const out = [];
        for (const c of cues) {
            const raw = subsEntities(String(c.t).replace(/<[^>]+>/g, "").replace(/\{\\[^}]*\}/g, ""));
            const t = raw.replace(/\s*\n\s*/g, " ").replace(/\s+/g, " ").trim();
            if (!t) continue;
            const prev = out[out.length - 1];
            // (the same words again straight after: one line)
            if (prev && prev.t === t && c.s - prev.e < 0.6) { prev.e = Math.max(prev.e, c.e); continue; }
            out.push({ s: c.s, e: c.e, t });
        }
        return out.sort((a, b) => a.s - b.s);
    }

    // ── the panel ──
    function subsPanel() {
        const st = subs;
        if (st.panel) return st.panel;
        const css = document.createElement("style");
        css.textContent = `
#ff-subs { all: initial; position: fixed; z-index: 2147483640; box-sizing: border-box; display: block;
  background: var(--ff-bg, rgba(0, 0, 0, 0.88)); -webkit-backdrop-filter: blur(14px); backdrop-filter: blur(14px);
  border: 1px solid rgba(255,255,255,0.10); border-radius: 16px; box-shadow: 0 10px 30px rgba(0,0,0,0.35);
  color: #e9eaf2; font: 18px/1.55 -apple-system, "PingFang TC", "Heiti TC", system-ui, sans-serif; overflow: hidden;
  transition: opacity .3s ease, transform .35s cubic-bezier(.2,.9,.3,1), background-color 1.2s ease; }
#ff-subs.fx, #ff-defs.fx { -webkit-backdrop-filter: none; backdrop-filter: none; }
#ff-subs.wide { top: 72px; right: 12px; bottom: 12px; width: min(380px, 34vw); }
#ff-subs.narrow { left: 8px; right: 8px; bottom: 8px; height: 40vh; }
/* (no background: only the lines, the buttons and the cards, each in a box of its own) */
#ff-subs.clear { background: transparent !important; border-color: transparent; box-shadow: none; -webkit-backdrop-filter: none; backdrop-filter: none; }
#ff-subs.clear .top, #ff-subs.clear .study { border-bottom-color: transparent; }
#ff-subs.clear .top b, #ff-subs.clear .meter { text-shadow: 0 1px 4px rgba(0,0,0,.9); }
#ff-subs.clear .btn, #ff-subs.clear select { background: rgba(16,18,28,.82); }
#ff-subs.clear .line { background: rgba(16,18,28,.8); }
#ff-subs.clear .line.now { background: rgba(28,32,50,.94); }
#ff-subs.hidden { opacity: 0; transform: translateY(12px); pointer-events: none; }
#ff-subs .top { position: absolute; left: 0; right: 0; top: 0; height: 38px; display: flex; align-items: center; gap: 8px;
  padding: 0 10px 0 14px; box-sizing: border-box; border-bottom: 1px solid rgba(255,255,255,0.07); font-size: 13px; color: #a7abc0; }
#ff-subs .top b { font-weight: 600; color: #e9eaf2; margin-right: auto; font-size: 13px; white-space: nowrap; flex: none; }
#ff-subs select { all: revert; font: 12px -apple-system, system-ui; background: rgba(255,255,255,0.08); color: #e9eaf2;
  border: 1px solid rgba(255,255,255,0.12); border-radius: 7px; padding: 2px 4px; max-width: 150px; min-width: 0; flex: 0 1 auto; }
#ff-subs.narrow select, #ff-subs.flow select { max-width: 96px; }
#ff-subs .top .btn { flex: none; }
#ff-subs .top { overflow: hidden; }
#ff-subs .btn { all: unset; cursor: pointer; padding: 3px 8px; border-radius: 7px; font-size: 12px; color: #c9cce0;
  background: rgba(255,255,255,0.08); }
#ff-subs .study { position: absolute; left: 0; right: 0; top: 38px; height: 34px; display: flex; align-items: center; gap: 6px;
  padding: 0 10px; box-sizing: border-box; overflow-x: auto; border-bottom: 1px solid rgba(255,255,255,0.07); scrollbar-width: none; }
#ff-subs .study::-webkit-scrollbar { display: none; }
#ff-subs .study .btn { flex: none; }
#ff-subs .study select { flex: none; max-width: 120px; }
#ff-subs .study .btn.on { background: rgba(120,200,255,0.25); color: #e9f6ff; box-shadow: inset 0 0 0 1px rgba(150,215,255,0.55); }
#ff-subs .study .meter { flex: none; margin-left: auto; font-size: 12px; color: #a7abc0; padding-left: 6px; }
#ff-subs.mini .study { display: none; }
#ff-subs .view { position: absolute; left: 0; right: 0; top: 72px; bottom: 0; overflow: hidden; touch-action: none;
  -webkit-mask-image: linear-gradient(transparent 0, #000 14%, #000 84%, transparent 100%);
  mask-image: linear-gradient(transparent 0, #000 14%, #000 84%, transparent 100%); }
#ff-subs .rail { position: absolute; left: 0; right: 0; top: 0; padding: 0 12px; will-change: transform;
  transition: transform .7s cubic-bezier(.22,.8,.25,1); }
#ff-subs .line { display: block; padding: 7px 10px; margin: 2px 0; border-radius: 10px; opacity: .62;
  transition: opacity .45s ease, background-color .45s ease; }
#ff-subs .line.past { opacity: .34; }
#ff-subs .line.now { opacity: 1; background: rgba(255,255,255,0.07); }
#ff-subs .tm { display: inline-block; font: 11px ui-monospace, Menlo, monospace; color: #8b90a8; margin-right: 8px;
  cursor: pointer; vertical-align: 2px; user-select: none; -webkit-user-select: none; }
#ff-subs .tx { display: inline; }
#ff-subs .new { text-decoration: underline dotted rgba(255,255,255,0.55); text-underline-offset: 5px; text-decoration-thickness: 2px; }
#ff-subs .learn { text-decoration: underline solid rgba(255,214,102,0.85); text-underline-offset: 5px; text-decoration-thickness: 2px; }
#ff-subs .h { text-shadow: 0 0 7px currentColor; }
#ff-subs .w { display: inline-block; position: relative; vertical-align: baseline; line-height: 1.2; }
#ff-subs .w.r { padding-top: calc(var(--ff-rd, .56em) * 1.25 + 1px); }
#ff-subs .w.g { padding-bottom: calc(var(--ff-gl, .5em) * 1.25 + 2px); }
#ff-subs .line:has(.w) .tm { vertical-align: middle; }
#ff-subs .cw { white-space: nowrap; }
#ff-subs .rd, #ff-subs .gl { user-select: none; -webkit-user-select: none; white-space: nowrap; pointer-events: none;
  font-family: -apple-system, system-ui, "PingFang TC", sans-serif; }
#ff-subs .rd { font-size: var(--ff-rd, .56em); line-height: 1.25; position: absolute; top: 0; left: 50%; transform: translateX(-50%); }
#ff-subs .gl { font-size: var(--ff-gl, .5em); line-height: 1.25; color: #b6bad0; max-width: 9em; overflow: hidden; text-overflow: ellipsis;
  position: absolute; bottom: 0; left: 50%; transform: translateX(-50%); }
#ff-subs .gl.zh { color: #d9ddf2; }
#ff-subs.flow .view { top: 0; bottom: 38px; }
/* (the row at the bottom: its buttons under the lines, at the very bottom of the screen) */
#ff-subs.flow .top { top: auto; bottom: 0; border-bottom: none; border-top: 1px solid rgba(255,255,255,0.07); }
#ff-subs.flow.mini .top, #ff-subs.flow.clear .top { border-top-color: transparent; }
#ff-subs.flow .top b { margin-right: 2px; }
#ff-subs.flow .top .study { position: static; flex: 1 1 auto; min-width: 0; height: 38px; border-bottom: none; padding: 0 4px; }
#ff-subs .t2 { display: block; font-size: .58em; line-height: 1.3; color: #9a9fb5; margin-top: 3px; white-space: normal;
  font-family: -apple-system, system-ui, "PingFang TC", sans-serif; }
#ff-subs .t2:empty { display: none; }
#ff-subs.flow .t2 { white-space: nowrap; }
/* the gear: the buttons hidden or shown (in the corner of the button row; with the buttons hidden, alone there) */
#ff-subs .gear { position: absolute; z-index: 3; left: 8px; top: 5px; width: 28px; height: 28px; border-radius: 8px; cursor: pointer;
  display: flex; align-items: center; justify-content: center; color: #c9cce0; background: rgba(255,255,255,0.08); }
#ff-subs .gear svg { width: 18px; height: 18px; display: block; }
#ff-subs.flow .gear { top: auto; bottom: 5px; }
#ff-subs .top { padding-left: 78px; }
/* 生詞, next to the gear: all the words of the video you don't know yet */
#ff-subs .gear.words { left: 42px; }
#ff-subs.bare .top, #ff-subs.bare .study { display: none; }
#ff-subs.bare .view { top: 0; }
#ff-subs.bare.flow .view { bottom: 0; }
#ff-subs.bare .gear { opacity: .55; background: rgba(16,18,28,.7); }
#ff-subs.bare .gear:hover { opacity: 1; }
/* (橫排 without the buttons: the gear and 生詞 one above the other at the left, beside the subtitles, not over them) */
#ff-subs.bare.flow .gear { top: 8px; bottom: auto; left: 8px; }
#ff-subs.bare.flow .gear.words { top: 42px; left: 8px; }
#ff-subs.bare.flow .view { left: 42px; }
/* (直排 without the buttons: the two side by side in the corner, the first line a little lower) */
#ff-subs.bare:not(.flow) .view { top: 40px; }
#ff-subs .empty { display: block; padding: 18px; color: #8b90a8; font-size: 14px; }
#ff-subs.flow { left: 12px; right: 12px; bottom: 12px; top: auto; width: auto; height: 116px; }
/* (橫排: the edges faded by the panel's own colour laid over them, not by a mask: a masked box with a moving row in
   it made Safari sometimes drop the row's left part while it was still on the screen) */
#ff-subs.flow .view { -webkit-mask-image: none; mask-image: none; }
#ff-subs.flow .view::before, #ff-subs.flow .view::after { content: ""; position: absolute; top: 0; bottom: 0; width: 10%; z-index: 2;
  pointer-events: none; }
#ff-subs.flow .view::before { left: 0; background: linear-gradient(90deg, var(--ff-bg, rgba(0, 0, 0, 0.88)), transparent); }
#ff-subs.flow .view::after { right: 0; background: linear-gradient(270deg, var(--ff-bg, rgba(0, 0, 0, 0.88)), transparent); }
#ff-subs.flow.clear .view::before, #ff-subs.flow.clear .view::after { display: none; }
#ff-subs.air.flow .view::before { background: linear-gradient(90deg, #000, transparent); }
#ff-subs.air.flow .view::after { background: linear-gradient(270deg, #000, transparent); }
#ff-subs.flow .rail { display: flex; flex-wrap: nowrap; align-items: center; height: 100%; padding: 0; gap: 4px;
  white-space: nowrap; transition: none; right: auto; width: max-content; }
#ff-subs.flow .line.far { display: none; }
#ff-subs.flow .line { flex: none; margin: 0; padding: 8px 14px; }
#ff-subs.mini { height: 38px !important; }
#ff-subs .vgrip { display: none; }
#ff-subs.flow:not(.mini):not(.air) .vgrip { display: block; position: absolute; z-index: 4; top: 0; left: 50%; transform: translateX(-50%);
  width: 72px; height: 16px; cursor: ns-resize; touch-action: none; }
#ff-subs .vgrip::after { content: ""; position: absolute; left: 18px; right: 18px; top: 5px; height: 4px; border-radius: 2px;
  background: rgba(255,255,255,0.28); }
#ff-subs .vgrip:hover::after { background: rgba(255,255,255,0.55); }
#ff-subs.air { left: 0 !important; right: 0 !important; top: 0 !important; bottom: 0 !important; width: auto !important;
  height: auto !important; border-radius: 0; border: none; background: #000 !important; }
#ff-subs.air.mini { top: auto !important; height: 38px !important; }
#ff-subs.air.flow .view { top: 42%; bottom: 38px; }
#ff-subs.air.flow.bare .view { bottom: 0; }
#ff-subs.air.clear .line { background: transparent; }
#ff-subs.air .line { padding: .35em .6em; }
#ff-subs.air:not(.flow) .rail { padding: 0 6vw; }
#ff-subs.air .tm { font-size: 14px; }
#ff-defs.air { z-index: 2147483641; top: 84px; left: 24px; right: 24px; background: transparent !important; border-color: transparent; box-shadow: none; }
#ff-defs { all: initial; position: fixed; z-index: 2147483639; left: 12px; right: 12px; top: 12px; box-sizing: border-box;
  display: flex; gap: 10px; align-items: stretch; padding: 10px; overflow-x: auto; overflow-y: hidden;
  background: var(--ff-bg, rgba(0, 0, 0, 0.88)); -webkit-backdrop-filter: blur(14px); backdrop-filter: blur(14px);
  transition: background-color 1.2s ease;
  border: 1px solid rgba(255,255,255,0.10); border-radius: 16px; box-shadow: 0 10px 30px rgba(0,0,0,0.35);
  color: #e9eaf2; font: 15px/1.4 -apple-system, "PingFang TC", "Heiti TC", system-ui, sans-serif; scrollbar-width: none; }
#ff-defs::-webkit-scrollbar { display: none; }
#ff-defs .dc { flex: none; box-sizing: border-box; min-width: 150px; max-width: 340px; padding: 6px 14px; border-radius: 12px; cursor: pointer;
  background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.12); display: flex; flex-direction: column;
  justify-content: center; overflow: hidden; animation: ffDefIn .3s cubic-bezier(.2,.9,.3,1); }
@keyframes ffDefIn { from { opacity: 0; transform: translateY(-6px); } }
#ff-defs.clear { background: transparent !important; border-color: transparent; box-shadow: none; -webkit-backdrop-filter: none; backdrop-filter: none; }
#ff-defs.clear .dc { background: rgba(16,18,28,.88); }
#ff-defs.clear .none { display: none; }
#ff-defs .dc.learn { border-color: rgba(255,209,102,.45); }
#ff-defs .dc:hover { background: rgba(255,255,255,0.09); }
#ff-defs .rd { font-size: 12.5px; white-space: nowrap; }
#ff-defs .h { font-size: var(--ff-defs-font, 18px); font-weight: 600; line-height: 1.25; white-space: nowrap; text-shadow: 0 0 7px currentColor; }
#ff-defs .gl { font-size: 13px; color: #c3c7d9; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
#ff-defs .none { margin: auto; color: #8b90a8; font-size: 14px; }
#ff-subs.wide.mini { bottom: auto; }
#ff-subs.mini .view { display: none; }
#ff-subs.mini .top { border-bottom: none; }
/* 一句一句往上換: the line being said, the next one small under it; a new line comes up into its place */
#ff-subs .swapbox { display: none; }
#ff-subs.flow.swap .rail { visibility: hidden; }
#ff-subs.flow.swap .swapbox { display: block; position: absolute; inset: 0; overflow: hidden; z-index: 1; }
#ff-subs .swapbox .line { position: absolute; left: 0; right: 0; top: 0; margin: 0 auto; width: fit-content; max-width: calc(100% - 24px);
  box-sizing: border-box; white-space: normal; text-align: center; transform-origin: 50% 0;
  transition: transform .5s cubic-bezier(.2,.9,.3,1), opacity .45s ease; }
#ff-subs .swapbox .line .tm { display: none; }
#ff-subs .swapbox .line .t2 { white-space: normal; }
/* 字跟著時間變大: the part said so far a little bigger, the one being said the biggest */
#ff-subs.swell .tx .h, #ff-subs.swell .tx .su { display: inline-block; transform-origin: 50% 85%; transition: transform .22s ease-out; }
#ff-subs.swell .tx .sw1 { transform: scale(1.06); }
#ff-subs.swell .tx .sw2 { transform: scale(1.3); }
@media (prefers-reduced-motion: reduce) { #ff-subs .rail, #ff-subs .swapbox .line { transition: none; } }`;
        (document.head || document.documentElement).appendChild(css);
        const p = document.createElement("div");
        p.id = "ff-subs";
        p.className = "hidden";
        // (Firefox: no blur of the video behind the panel. Firefox blurs it again on every frame of the video, which
        // with the row moving made the moving words stutter; the panel's colour is nearly opaque, so it looks the same)
        if (/Firefox\//.test(navigator.userAgent)) p.classList.add("fx");
        const top = document.createElement("div"); top.className = "top";
        const view = document.createElement("div"); view.className = "view";
        const rail = document.createElement("div"); rail.className = "rail";
        view.appendChild(rail);
        // the study row: the line before / after, this line again and again, slower, a stop after each line
        const study = document.createElement("div"); study.className = "study";
        // the gear: the buttons hidden or shown
        const gear = document.createElement("div"); gear.className = "gear";
        gear.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" fill-rule="evenodd" d="M17.47 10.78 L19.14 11.07 L19.14 12.93 L17.47 13.22 L16.73 15.00 L17.71 16.39 L16.39 17.71 L15.00 16.73 L13.22 17.47 L12.93 19.14 L11.07 19.14 L10.78 17.47 L9.00 16.73 L7.61 17.71 L6.29 16.39 L7.27 15.00 L6.53 13.22 L4.86 12.93 L4.86 11.07 L6.53 10.78 L7.27 9.00 L6.29 7.61 L7.61 6.29 L9.00 7.27 L10.78 6.53 L11.07 4.86 L12.93 4.86 L13.22 6.53 L15.00 7.27 L16.39 6.29 L17.71 7.61 L16.73 9.00 Z M12 9.6 A2.4 2.4 0 1 0 12 14.4 A2.4 2.4 0 1 0 12 9.6 Z"/></svg>';
        // (the subtitles' settings on a page of their own, big enough to tap: the row of small buttons was hard to hit)
        gear.addEventListener("click", e => { e.stopPropagation(); subsSheet(); });
        // 生詞: next to the gear, always there (the video's words you don't know yet, in a big window)
        const words = document.createElement("div"); words.className = "gear words";
        words.setAttribute("role", "button");
        words.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M4 5.5h2.2v2.2H4zM8.5 5.6h11.5v2H8.5zM4 10.9h2.2v2.2H4zM8.5 11h11.5v2H8.5zM4 16.3h2.2v2.2H4zM8.5 16.4h11.5v2H8.5z"/></svg>';
        words.addEventListener("click", e => { e.stopPropagation(); subsWordList(); });
        // 橫排: its top edge dragged up or down makes the row taller or lower (the width stays the screen's, centred);
        // a double click (or double tap) back to the height its words need
        const vgrip = document.createElement("div"); vgrip.className = "vgrip";
        vgrip.title = ffT("拖拉改高度（點兩下還原）");
        let hDrag = null, hRaf = 0;
        vgrip.addEventListener("pointerdown", e => {
            e.preventDefault(); e.stopPropagation();
            hDrag = { y: e.clientY, h: p.getBoundingClientRect().height };
            vgrip.setPointerCapture(e.pointerId);
        });
        vgrip.addEventListener("pointermove", e => {
            if (!hDrag) return;
            prefs.subsFlowH = Math.max(1, Math.round(hDrag.h - (e.clientY - hDrag.y)));
            if (!hRaf) hRaf = requestAnimationFrame(() => { hRaf = 0; subsLayout(); });
        });
        let hTap = 0;
        const hEnd = e => {
            if (!hDrag) return;
            const moved = Math.abs(e.clientY - hDrag.y) > 4;
            hDrag = null;
            // (a double tap: a finger has no double click)
            if (!moved && e.pointerType !== "mouse") {
                if (Date.now() - hTap < 400) { prefs.subsFlowH = 0; hTap = 0; } else hTap = Date.now();
            }
            savePrefs(); subsLayout();
        };
        vgrip.addEventListener("pointerup", hEnd);
        vgrip.addEventListener("pointercancel", hEnd);
        vgrip.addEventListener("dblclick", e => { e.stopPropagation(); prefs.subsFlowH = 0; savePrefs(); subsLayout(); });
        vgrip.addEventListener("click", e => e.stopPropagation());
        p.append(top, study, view, gear, words, vgrip);
        st.study = study; st.gear = gear; st.wordsBtn = words;
        document.documentElement.appendChild(p);
        st.panel = p; st.rail = rail; st.view = view; st.top = top;

        // a word: looked up with a tap (a finger); the time: the video goes there
        let down = null;
        view.addEventListener("pointerdown", e => { down = { x: e.clientX, y: e.clientY, t: Date.now(), type: e.pointerType }; }, true);
        view.addEventListener("pointerup", e => {
            const d = down; down = null;
            if (!d || Math.hypot(e.clientX - d.x, e.clientY - d.y) > 8) return;
            const tm = e.target.closest && e.target.closest(".tm");
            if (tm) {
                const v = subsVideo(); const i = +tm.dataset.i;
                if (v && st.cues[i]) {
                    v.currentTime = Math.max(0, st.cues[i].s - subsOff() + 0.01); st.manual = 0; st.manualUntil = 0;
                    if (st.loop >= 0) { st.loop = i; subsStudy(); }        // (repeating: now this line)
                    st.stopped = -1;
                }
                return;
            }
            // (a tap with a finger, the Pencil or a click: the subtitles' words open only this way, not by hovering)
            if (d.type === "mouse" && e.button !== 0) return;
            const hit = charAt(e.clientX, e.clientY);
            if (!hit) return;
            const lat = !isHan(hit.cp) && (prefs.sv || prefs.eng) && isLat(hit.cp) ? latWordAt(hit.node, hit.off) : null;
            if (!isHan(hit.cp) && !lat) return;
            const v = subsVideo();
            clearTimeout(st.resumeTimer);
            if (prefs.subsPause && v && !v.paused) { v.pause(); st.pausedBy = "tap"; }
            const spot = "subs:" + hit.off + "@" + Math.round(hit.rect.left) + "," + Math.round(hit.rect.top);
            setTimeout(() => {
                if (lat) lookup(lat.text, hit.rect, spot, { node: hit.node, off: lat.start }, true);
                else { const c = subsCueAt(hit.node, hit.off); const t = c && c.text ? c.text : textFrom(hit.node, hit.off); if (t) lookup(t, hit.rect, spot, { node: hit.node, off: hit.off }); }
            }, 30);
        });
        // the Pencil or a trackpad over the subtitles: the video waits (and goes on when it leaves)
        // looking back or ahead: drag (or scroll) the lines; they follow the video again a few seconds later
        let drag = null;
        const along = e => st.flow ? e.touches[0].clientX : e.touches[0].clientY;
        view.addEventListener("touchstart", e => { drag = along(e); }, { passive: true });
        view.addEventListener("touchmove", e => {
            if (drag == null) return;
            const y = along(e);
            st.manual += y - drag; drag = y; st.manualUntil = Date.now() + 4000;
            subsPlace(false);
            e.preventDefault();
        }, { passive: false });
        view.addEventListener("touchend", () => { drag = null; }, { passive: true });
        view.addEventListener("wheel", e => {
            st.manual -= st.flow ? (e.deltaX || e.deltaY) : e.deltaY; st.manualUntil = Date.now() + 4000; subsPlace(false);
            e.preventDefault(); e.stopPropagation();
        }, { passive: false });
        window.addEventListener("resize", () => subsLayout(), { passive: true });
        // a video full screen (Mac, iPad): the panel goes inside it, as a row at the bottom
        for (const ev of ["fullscreenchange", "webkitfullscreenchange"]) document.addEventListener(ev, () => setTimeout(subsLayout, 50));
        // AirPlay starting or ending (the event doesn't bubble: caught on its way down)
        document.addEventListener("webkitcurrentplaybacktargetiswirelesschanged", () => setTimeout(subsLayout, 50), true);
        subsLayout();
        return p;
    }

    function subsLayout() {
        const st = subs;
        if (!st.panel) return;
        const fsT = fsTarget();
        if (st.panel.parentNode !== fsT) fsT.appendChild(st.panel);
        // (AirPlay: the whole screen, 直排 or 橫排 as chosen)
        const air = subsAir();
        const airChanged = air !== !!st.air;
        st.air = air;
        const flow = !!prefs.subsFlow || (!air && fsT !== document.documentElement);
        const wide = window.innerWidth >= 900 && window.innerWidth > window.innerHeight;
        const changed = flow !== st.flow || airChanged;
        st.flow = flow;
        st.panel.classList.toggle("air", air);
        st.panel.classList.toggle("flow", flow);
        st.panel.classList.toggle("wide", !flow && wide);
        st.panel.classList.toggle("narrow", !flow && !wide);
        st.panel.classList.toggle("mini", st.collapsed);
        // (下面一行: one line at a time, or moving all the time)
        const swap = flow && prefs.subsFlowStyle === "swap";
        const swapChanged = swap !== !!st.swap;
        st.swap = swap;
        st.panel.classList.toggle("swap", swap);
        st.panel.classList.toggle("swell", !!prefs.subsSwell);
        const bare = prefs.subsBar === false;
        st.panel.classList.toggle("bare", bare);
        if (st.gear) st.gear.title = ffT("字幕設定");
        if (st.wordsBtn) { st.wordsBtn.title = ffT("生詞：這部影片裡還不認識的詞"); st.wordsBtn.setAttribute("aria-label", ffT("生詞")); }
        st.panel.classList.toggle("clear", subsBgMode() === "clear");
        // (the row at the bottom: tall enough for the letters)
        // (one line on top; the readings and meanings over and under the words need room too)
        const fs = 18 * (prefs.subsFont || 1), anno = prefs.subsRd || prefs.subsGl || st.hasEn;
        // (the second language: a smaller line under each one)
        const two = st.sec && st.sec.cues.length ? fs * 0.58 * 1.3 * 2 + 3 : 0;
        // (一句一句往上換: room for the next line, small, under the one being said)
        const nextRoom = swap && prefs.subsSwapNext !== false ? fs * 0.75 + 8 : 0;
        const autoH = Math.round((bare ? 0 : 38) + two + nextRoom + Math.max(76, fs * (anno ? 2.9 + 1.25 * ((prefs.subsRd ? prefs.subsRdSize || 0.56 : 0) + (prefs.subsGl ? prefs.subsGlSize || 0.5 : 0)) : 3)));
        // (dragged taller or lower by its top edge: as dragged, between a little room for one line and most of the screen)
        const flowH = prefs.subsFlowH > 0 ? Math.round(Math.min(Math.max(prefs.subsFlowH, (bare ? 0 : 38) + 44), window.innerHeight * 0.85)) : autoH;
        st.panel.style.height = flow && !st.collapsed && !air ? flowH + "px" : "";
        const has = st.cues.length > 0 && prefs.subs;
        st.panel.classList.toggle("hidden", !has);
        if (changed) { st.manual = 0; st.manualUntil = 0; subsHeader(); }
        if (swap && (swapChanged || changed)) subsSwapShow(st.now, false);
        else if (swap) subsSwapPlace();
        if (airChanged) { subsSize(); return; }
        // (a new width: the words may break onto other rows)
        const wNow = st.view ? st.view.clientWidth : 0;
        if (wNow !== st.spreadW) { st.spreadW = wNow; subsSpread(); }
        subsMeasure();
        subsPlace(false);
        subsDefs(true);
    }

    /// the subtitles' settings, a page over the video with big buttons: 拼音／注音 first, the script (繁 / as it
    /// came / 簡), the second language, the size, readings and meanings, where the panel goes, the panel's buttons
    function subsSheet() {
        const st = subs;
        if (!st || !st.panel) return;
        let sh = document.getElementById("ff-subs-sheet");
        if (sh) { sh.remove(); return; }
        if (!document.getElementById("ff-subs-sheet-css")) {
            const css = document.createElement("style");
            css.id = "ff-subs-sheet-css";
            css.textContent = `
#ff-subs-sheet { position: fixed; inset: 0; z-index: 2147483646; display: flex; align-items: center; justify-content: center;
  background: rgba(0,0,0,.45); font: 15px -apple-system, system-ui, sans-serif; color: #e8eaf3; }
#ff-subs-sheet .card { width: min(900px, calc(100vw - 24px)); max-height: calc(100vh - 32px); overflow-y: auto; padding: 16px 16px 12px;
  border-radius: 18px; background: rgba(22,24,36,.97); border: 1px solid rgba(255,255,255,.14); box-shadow: 0 12px 40px rgba(0,0,0,.5); }
#ff-subs-sheet h3 { margin: 0 0 10px; font-size: 18px; }
/* (the settings in a grid of tiles, as many side by side as fit) */
#ff-subs-sheet .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 10px; }
#ff-subs-sheet .row { margin: 0; padding: 10px 12px 12px; border-radius: 14px; background: rgba(255,255,255,.04);
  border: 1px solid rgba(255,255,255,.09); }
#ff-subs-sheet .row button { min-height: 40px; padding: 0 12px; }
#ff-subs-sheet .lab { font-size: 13px; color: #9aa0b8; margin-bottom: 6px; }
#ff-subs-sheet .seg { display: flex; flex-wrap: wrap; gap: 8px; }
#ff-subs-sheet button, #ff-subs-sheet select { min-height: 44px; padding: 0 16px; border-radius: 12px; font: inherit; cursor: pointer;
  color: #e8eaf3; background: rgba(255,255,255,.07); border: 1.5px solid rgba(255,255,255,.16); }
#ff-subs-sheet button.on { background: rgba(195,155,255,.28); border-color: #c39bff; color: #fff; font-weight: 600; }
#ff-subs-sheet select { width: 100%; }
#ff-subs-sheet .done { width: 100%; margin-top: 14px; background: rgba(195,155,255,.35); border-color: #c39bff; font-weight: 600; }`;
            (document.head || document.documentElement).appendChild(css);
        }
        sh = document.createElement("div"); sh.id = "ff-subs-sheet";
        const card = document.createElement("div"); card.className = "card";
        sh.appendChild(card);
        sh.addEventListener("click", e => { if (e.target === sh) sh.remove(); });
        for (const ev of ["pointerdown", "pointerup", "mousedown", "mouseup", "keydown", "wheel", "touchstart"]) card.addEventListener(ev, e => e.stopPropagation());
        const h = document.createElement("h3"); h.textContent = ffT("字幕設定"); card.appendChild(h);
        // (the tiles go in a grid; a heading starts a new one)
        let grid = null;
        const row = (label, kids) => {
            if (!grid) { grid = document.createElement("div"); grid.className = "grid"; card.appendChild(grid); }
            const r = document.createElement("div"); r.className = "row";
            const l = document.createElement("div"); l.className = "lab"; l.textContent = label;
            const g = document.createElement("div"); g.className = "seg"; g.append(...kids);
            r.append(l, g); grid.appendChild(r);
        };
        const redraw = () => { sh.remove(); subsSheet(); };
        const choice = (key, opts, after) => opts.map(([v, t]) => {
            const b = document.createElement("button"); b.textContent = t;
            if (prefs[key] === v || (prefs[key] === undefined && v === opts[0][0])) b.className = "on";
            b.addEventListener("click", () => { prefs[key] = v; savePrefs(); if (after) after(); redraw(); });
            return b;
        });
        // (every subtitle setting: the ones used most first)
        const onOff = [[true, ffT("開")], [false, ffT("關")]];
        const relay = () => { subsSize(); subsLayout(); subsRedraw(); };
        const sec = t => { const x = document.createElement("h3"); x.textContent = t; x.style.cssText = "margin:18px 0 8px;font-size:15px;color:#c39bff"; card.appendChild(x); grid = null; };
        row(ffT("注音／拼音"), choice("zhRom", [[1, ffT("注音")], [0, ffT("拼音")]], relay));
        row(ffT("繁體／簡體"), choice("subsTrad", [[true, ffT("轉成繁體")], ["simp", ffT("轉成簡體")], [false, ffT("照原樣")]]));
        // (顏色: none, every word, or only the words you don't know yet: two settings as one choice)
        const colourNow = prefs.subsColours === false ? "none" : prefs.onlyNew ? "new" : "all";
        row(ffT("顏色"), [["none", ffT("不上色")], ["all", ffT("全部的詞")], ["new", ffT("不熟的詞")]].map(([v, t]) => {
            const b = document.createElement("button"); b.textContent = t;
            if (v === colourNow) b.className = "on";
            b.addEventListener("click", () => {
                prefs.subsColours = v !== "none"; prefs.onlyNew = v === "new";
                savePrefs(); relay(); redraw();
            });
            return b;
        }));
        row(ffT("字幕直的還是橫的") + (fsTarget() === document.documentElement || st.air ? "" : ffT("（全螢幕時都是橫的）")),
            choice("subsFlow", [[false, ffT("直的（旁邊，往上捲）")], [true, ffT("橫的（下面一行）")]], () => subsLayout()));
        row(ffT("橫的字幕怎麼動"), choice("subsFlowStyle", [["scroll", ffT("一直往旁邊移")], ["swap", ffT("一句一句往上換")]], () => subsLayout()));
        const SIZES = [0.85, 1, 1.15, 1.3, 1.5, 1.8, 2.2, 2.7];
        const size = d => {
            const b = document.createElement("button"); b.textContent = d < 0 ? "A−" : "A+";
            b.addEventListener("click", () => {
                const i = SIZES.findIndex(x => x >= (prefs.subsFont || 1) - 0.001);
                prefs.subsFont = SIZES[Math.max(0, Math.min(SIZES.length - 1, (i < 0 ? 1 : i) + d))];
                savePrefs(); subsSize(); subsLayout();
            });
            return b;
        };
        row(ffT("字的大小"), [size(-1), size(1)]);
        // 字幕時間: a tenth of a second at a time (for every video)
        const offNow = subsOff();
        const offLabel = Math.abs(offNow) < 0.05 ? ffT("準時") : (offNow > 0 ? ffT("提早 ") : ffT("延後 ")) + Math.abs(offNow).toFixed(1) + ffT(" 秒");
        const offBtn = (t, d) => {
            const b = document.createElement("button"); b.textContent = t;
            b.addEventListener("click", () => {
                prefs.subsOffset = d === 0 ? 0 : Math.round((subsOff() + d) * 10) / 10;
                prefs.subsOffset = Math.max(-5, Math.min(5, prefs.subsOffset));
                savePrefs(); st.now = -2; redraw();
            });
            return b;
        };
        const offShow = document.createElement("span"); offShow.textContent = offLabel;
        offShow.style.cssText = "align-self:center;min-width:6.5em;text-align:center;font-weight:600";
        row(ffT("字幕時間（每部影片都一樣）"), [offBtn(ffT("延後"), -0.1), offShow, offBtn(ffT("提早"), 0.1), offBtn(ffT("歸零"), 0)]);
        sec(ffT("字幕的語言"));
        row(ffT("主要的字幕"), choice("subsLang", [["auto", ffT("自動（跟查詞的語言）")], ["zh", ffT("華語")], ["tw", ffT("台語")], ["yue", ffT("粵語")], ["hak", ffT("客語")], ["eng", ffT("英語")]], () => { relay(); subsRepick(); }));
        const s2 = subs2Select();
        if (s2) row(ffT("第二種字幕（每一句下面）"), [s2]);
        row(ffT("英文字幕下面標中文"), choice("subsEnZh", onOff, relay));
        sec(ffT("其他"));
        row(ffT("下一句（一句一句往上換）"), choice("subsSwapNext", [[true, ffT("小小的顯示在下面")], [false, ffT("不顯示（字更大）")]], () => subsLayout()));
        row(ffT("字跟著時間變大"), choice("subsSwell", [[false, ffT("關")], [true, ffT("開")]], () => subsLayout()));
        row(ffT("標哪些詞（加讀音和意思）"), choice("subsMark", [["new", ffT("不認識的詞")], ["rare", ffT("不常用的詞")], ["both", ffT("不認識又不常用的詞")]], relay));
        row(ffT("多不常用才標"), choice("subsRare", [[1000, ffT("第 1001 個以後的詞")], [3000, ffT("第 3001 個以後的詞")], [8000, ffT("第 8001 個以後的詞")], [20000, ffT("第 20001 個以後的詞")]], relay));
        row(ffT("詞上的讀音、詞下的意思"), [
            ...choice("subsRd", [[true, ffT("讀音：開")], [false, ffT("讀音：關")]], relay),
            ...choice("subsGl", [[true, ffT("意思：開")], [false, ffT("意思：關")]], relay),
        ]);
        row(ffT("讀音的大小"), choice("subsRdSize", [[0.32, ffT("很小")], [0.45, ffT("小")], [0.56, ffT("中")], [0.7, ffT("大")], [1, ffT("和字一樣")]], relay));
        row(ffT("意思的大小"), choice("subsGlSize", [[0.32, ffT("很小")], [0.4, ffT("小一點")], [0.5, ffT("中")], [0.6, ffT("大")], [0.75, ffT("更大")]], relay));
        row(ffT("面板的底"), choice("subsBg", [["dark", ffT("黑色")], ["tint", ffT("跟著底下的畫面")], ["clear", ffT("沒有底")]], () => { subsTint(); subsLayout(); }));
        row(ffT("面板上的按鈕"), choice("subsBar", [[true, ffT("顯示")], [false, ffT("隱藏")]], () => subsLayout()));
        row(ffT("影片上原本的字幕"), choice("subsHideVideo", [[false, ffT("顯示")], [true, ffT("隱藏")]], () => { subsHeader(); subsTick(); }));
        row(ffT("查詞時影片暫停"), choice("subsPause", onOff));
        row(ffT("橫的字幕：畫面上面的詞卡"), choice("subsDefs", [[true, ffT("顯示")], [false, ffT("不顯示")]], () => subsDefs(true)));
        const done = document.createElement("button"); done.className = "done"; done.textContent = ffT("完成");
        done.addEventListener("click", () => sh.remove());
        card.appendChild(done);
        fsTarget().appendChild(sh);
    }

    function subsHeader() {
        const st = subs;
        if (!st.top) return;
        st.top.replaceChildren();
        const title = document.createElement("b"); title.textContent = ffT("字幕");
        st.top.appendChild(title);
        // (YouTube: the video's languages, its automatic ones, and YouTube's translations of them)
        if (st.ytTracks.length > 1 || st.ytTrans.length) {
            const sel = document.createElement("select");
            const add = (parent, value, text) => {
                const o = document.createElement("option");
                o.value = value; o.textContent = text;
                parent.appendChild(o);
                return o;
            };
            st.ytTracks.forEach((t, i) => add(sel, "t" + i, t.name + (t.kind === "asr" ? ffT("（自動）") : "")));
            const base = subsBase();
            if (st.ytTrans.length && base) {
                const g = document.createElement("optgroup");
                g.label = ffT("自動翻譯");
                st.ytTrans.forEach((t, i) => add(g, "x" + i, "→ " + t.name));
                sel.appendChild(g);
            }
            // (the one showing)
            st.ytTracks.forEach((t, i) => { if (subsId(t.lang, t.kind) === st.cur) sel.value = "t" + i; });
            st.ytTrans.forEach((t, i) => { if (base && st.cur.endsWith(">" + t.lang)) sel.value = "x" + i; });
            sel.addEventListener("change", () => {
                const v = sel.value;
                if (v[0] === "t") subsUseTrack(st.ytTracks[+v.slice(1)]);
                else if (base) subsUseTrack(base, st.ytTrans[+v.slice(1)]);
            });
            st.top.appendChild(sel);
        }
        const eye = document.createElement("span"); eye.className = "btn";
        eye.textContent = prefs.subsHideVideo ? ffT("影片上：關") : ffT("影片上：開");
        eye.title = ffT("影片上的字幕");
        eye.addEventListener("click", e => { e.stopPropagation(); prefs.subsHideVideo = !prefs.subsHideVideo; savePrefs(); subsHeader(); subsTick(); });
        // (full screen: always the row at the bottom)
        const lay = document.createElement("span"); lay.className = "btn";
        lay.textContent = st.flow ? ffT("直排") : ffT("橫排");
        lay.title = st.flow ? ffT("字幕在旁邊，往上捲") : ffT("字幕在下面，往旁邊流");
        if (fsTarget() !== document.documentElement && !st.air) lay.style.display = "none";
        lay.addEventListener("click", e => { e.stopPropagation(); prefs.subsFlow = !prefs.subsFlow; savePrefs(); subsLayout(); });
        const min = document.createElement("span"); min.className = "btn"; min.textContent = st.collapsed ? ffT("展開") : ffT("收起");
        min.addEventListener("click", e => { e.stopPropagation(); st.collapsed = !st.collapsed; subsHeader(); subsLayout(); subsTick(); });
        // the letters bigger or smaller
        const SIZES = [0.85, 1, 1.15, 1.3, 1.5, 1.8, 2.2, 2.7];
        const step = d => e => {
            e.stopPropagation();
            const i = SIZES.findIndex(x => x >= (prefs.subsFont || 1) - 0.001);
            prefs.subsFont = SIZES[Math.max(0, Math.min(SIZES.length - 1, (i < 0 ? 1 : i) + d))];
            savePrefs(); subsSize(); subsLayout();
        };
        const smaller = document.createElement("span"); smaller.className = "btn"; smaller.textContent = "A−";
        smaller.title = ffT("字小一點"); smaller.addEventListener("click", step(-1));
        const bigger = document.createElement("span"); bigger.className = "btn"; bigger.textContent = "A+";
        bigger.title = ffT("字大一點"); bigger.addEventListener("click", step(1));
        // 拼音 ⇄ 注音, right on the panel (it was only in the settings page)
        const rom = document.createElement("span"); rom.className = "btn";
        rom.textContent = prefs.zhRom === 1 ? ffT("注音") : ffT("拼音");
        rom.title = ffT("華語讀音：拼音或注音");
        rom.addEventListener("click", e => { e.stopPropagation(); prefs.zhRom = prefs.zhRom === 1 ? 0 : 1; savePrefs(); subsHeader(); });
        st.top.append(rom, smaller, bigger, eye, lay, min);
        // (the row at the bottom: one line on top, the study buttons and 懂 % in it, after 字幕; at the side: their own line)
        if (st.study) {
            if (st.flow) title.after(st.study);
            else if (st.study.parentNode !== st.panel) st.panel.insertBefore(st.study, st.view);
        }
        subsStudy();
    }

    // ── a second language under each line (small and grey), e.g. English under the Chinese: from the stream's list
    // of languages (Viki and the like), YouTube's languages (or its translation), or the video's own tracks
    const subs2Norm = l => String(l || "").toLowerCase().replace(/_/g, "-");
    /// a language code is the one wanted ("en" is en-US too; "zh-hant" is zh-TW / zt …)
    function subs2Match(code, want) {
        const c = subs2Norm(code), w = subs2Norm(want);
        if (!c || !w) return false;
        if (c === w || c.startsWith(w + "-") || w.startsWith(c + "-")) return true;
        const trad = ["zt", "zh-hant", "zh-tw", "zh-hk"];
        return trad.includes(c) && trad.includes(w);
    }
    /// the languages this video has, other than the one shown: {code, name, key, get() → cues}
    function subs2Options() {
        const st = subs;
        if (!st) return [];
        const out = [];
        if (ytVideoId()) {
            const ytGet = url => async () => {
                if (!url.includes("fmt=")) url += "&fmt=json3";
                const r = await fetch(url, { credentials: "include" });
                return subsParse(r.ok ? await r.text() : "");
            };
            for (const t of st.ytTracks || []) {
                const id = subsId(t.lang, t.kind);
                if (id === st.cur || !t.url) continue;
                out.push({ code: subs2Norm(t.lang), name: t.name + (t.kind === "asr" ? ffT("（自動）") : ""), key: "yt:" + id, get: ytGet(t.url) });
            }
            // (no subtitles of its own in a language: YouTube's translation into it)
            const base = subsBase();
            if (base && base.url) for (const t of st.ytTransAll || []) {
                const code = subs2Norm(t.lang);
                if (out.some(o => subs2Match(o.code, code)) || st.cur.endsWith(">" + t.lang)) continue;
                if (!["en", "zh-hant", "zh-hans", "ja", "ko", "sv"].includes(code)) continue;
                out.push({ code, name: "→ " + t.name, key: "yt:" + subsId(base.lang, base.kind, t.lang), get: ytGet(base.url + "&tlang=" + encodeURIComponent(t.lang)) });
            }
            return out;
        }
        for (const t of st.fullTracks || []) {
            if (t.url === st.fullUrl) continue;
            out.push({ code: subs2Norm(t.lang), name: t.name || t.lang, key: "full2:" + t.url, get: async () => {
                const cues = await subsFullFetch(t) || [];
                if (st.fullShift) cues.forEach(x => { x.s += st.fullShift; x.e += st.fullShift; });
                return cues;
            } });
        }
        // (tracks the browser itself has loaded: only ones already there, none is turned on)
        const v = subsVideo();
        if (v && v.textTracks) for (const tt of v.textTracks) {
            if (!/subtitles|captions/.test(tt.kind) || tt.mode === "showing" || !tt.cues || !tt.cues.length) continue;
            const code = subs2Norm(tt.language || tt.label);
            if (!code || out.some(o => o.code === code) || "track:" + (tt.language || tt.label || tt.id) === st.key) continue;
            out.push({ code, name: tt.label || tt.language, key: "track2:" + code + ":" + tt.cues.length, get: async () => {
                const cues = [];
                for (const c of tt.cues) {
                    const t = String(c.text || "").replace(/<[^>]+>/g, "").replace(/\s*\n\s*/g, " ").trim();
                    if (t) cues.push({ s: c.startTime, e: c.endTime, t });
                }
                return subsClean(cues);
            } });
        }
        return out;
    }
    /// the second language: loaded when chosen (and when the video has it); none chosen: taken away
    async function subs2Pick(changed) {
        const st = subs;
        if (!st || !subsMine()) return;
        const want = subs2Norm(prefs.subs2);
        if (!want) { if (st.sec) { st.sec = null; subs2Fill(); subsLayout(); } if (changed) subsHeader(); return; }
        const opts = subs2Options();
        const o = opts.find(x => x.code === want) || opts.find(x => subs2Match(x.code, want));
        if (changed) subsHeader();
        if (!o) { if (changed && st.sec) { st.sec = null; subs2Fill(); subsLayout(); } return; }
        if ((st.sec && st.sec.key === o.key) || st.secWant === o.key || (st.secFailed && st.secFailed.has(o.key))) return;
        st.secWant = o.key;
        const vid = st.vid;
        let cues = [];
        try { cues = await o.get(); } catch (e) { cues = []; }
        if (st.vid !== vid || st.secWant !== o.key) return;
        st.secWant = "";
        if (!cues || !cues.length) { (st.secFailed = st.secFailed || new Set()).add(o.key); return; }
        st.sec = { key: o.key, cues: subsClean(cues) };
        subs2Fill();
        subsLayout();
    }
    /// each line's second-language words: every line of the second language goes under the line it's said with
    /// (the most time in common)
    function subs2Fill() {
        const st = subs;
        if (!st || !st.lines) return;
        const texts = st.lines.map(() => []);
        const sec = st.sec ? st.sec.cues : [];
        const cs = st.cues;
        if (sec.length && cs.length) {
            let j = 0;
            for (const x of sec) {
                while (j < cs.length && cs[j].e <= x.s) j++;
                let best = -1, most = 0;
                for (let k = Math.max(0, j - 1); k < cs.length && cs[k].s < x.e; k++) {
                    const o = Math.min(cs[k].e, x.e) - Math.max(cs[k].s, x.s);
                    if (o > most) { most = o; best = k; }
                }
                if (best >= 0 && !texts[best].includes(x.t)) texts[best].push(x.t);
            }
        }
        // (kept by line too: a word marked goes to the app with its line's, wherever on the screen it was tapped)
        st.trs = texts.map(a => a.join(" ").replace(/\s+/g, " ").trim());
        st.lines.forEach((line, i) => {
            const t2 = line.querySelector(".t2");
            if (t2) t2.textContent = texts[i].join(" ");
        });
        st.centers = [];
    }

    /// the second language's menu (small and grey under each line): the languages this video has; null: none
    function subs2Select() {
        const st = subs;
        const opts2 = subs2Options();
        if (!opts2.length && !prefs.subs2) return null;
        {
            const sel2 = document.createElement("select");
            sel2.title = ffT("第二種語言：小小的灰色字，在每一行下面");
            const o0 = document.createElement("option"); o0.value = ""; o0.textContent = ffT("第二語言：無");
            sel2.appendChild(o0);
            const seen = new Set();
            for (const o of opts2) {
                if (seen.has(o.code)) continue;
                seen.add(o.code);
                const x = document.createElement("option"); x.value = o.code; x.textContent = "+ " + o.name;
                sel2.appendChild(x);
            }
            const want = String(prefs.subs2 || "").toLowerCase();
            if (want && !seen.has(want)) {
                // (the one chosen before, not in this video)
                const m = opts2.find(o => subs2Match(o.code, want));
                if (m) sel2.value = m.code;
                else { const x = document.createElement("option"); x.value = want; x.textContent = "+ " + want + ffT("（這部影片沒有）"); sel2.appendChild(x); sel2.value = want; }
            } else sel2.value = want;
            sel2.addEventListener("change", () => { prefs.subs2 = sel2.value; savePrefs(); subs2Pick(true); subsRepick(); });
            return sel2;
        }
    }

    // the subtitles' size (from 設定, or A− / A+ on the panel)
    function subsSize() {
        const st = subs;
        if (!st || !st.rail) return;
        st.rail.style.fontSize = Math.round(18 * subsScale()) + "px";
        st.rail.style.setProperty("--ff-rd", (prefs.subsRdSize || 0.56) + "em");
        st.rail.style.setProperty("--ff-gl", (prefs.subsGlSize || 0.5) + "em");
        st.centers = [];
        requestAnimationFrame(() => { subsSpread(); subsMeasure(); subsPlace(false); subsDefs(true); });
    }

    /// the words with a reading / meaning: close together, unless their readings or meanings would run into each
    /// other (or past the start of the line); then just as far apart as needed. Measured all at once, then moved.
    function subsSpread() {
        const st = subs;
        if (!st || !st.rail) return;
        const all = [...st.rail.querySelectorAll(".w.a")];
        for (const w of all) { w.style.marginLeft = ""; }
        if (!all.length) return;
        const fs = parseFloat(getComputedStyle(st.rail).fontSize) || 18;
        const gap = fs * 0.25;
        const ext = w => {
            let l = Infinity, r = -Infinity;
            for (const x of w.children) {
                const b = x.getBoundingClientRect();
                if (!b.width) continue;
                l = Math.min(l, b.left); r = Math.max(r, b.right);
            }
            return { l, r, top: Math.round(w.getBoundingClientRect().top) };
        };
        const moves = [];
        for (const line of st.lines) {
            const ws = [...line.querySelectorAll(".w.a")];
            if (!ws.length) continue;
            const tx = line.querySelector(".tx");
            const start = (tx || line).getBoundingClientRect().left;
            const box = ws.map(ext);
            let shift = 0, row = null, prevR = -Infinity;
            box.forEach((b, i) => {
                if (b.top !== row) { row = b.top; shift = 0; prevR = start - gap; }
                const need = prevR + gap - (b.l + shift);
                if (need > 0.5) { moves.push([ws[i], need]); shift += need; }
                prevR = b.r + shift;
            });
        }
        for (const [w, m] of moves) w.style.marginLeft = (m / fs).toFixed(3) + "em";
    }

    // the lines of a new subtitle file
    function subsShow(cues) {
        const st = subs;
        st.cues = cues;
        st.now = -2; st.manual = 0;
        if (!cues.length && !st.panel) return;
        subsPanel();
        subsHeader();
        const frag = document.createDocumentFragment();
        st.panel.classList.toggle("anno", !!(prefs.subsRd || prefs.subsGl));
        st.lines = cues.map((c, i) => {
            const line = document.createElement("div");
            line.className = "line";
            const tm = document.createElement("span");
            tm.className = "tm"; tm.dataset.i = i;
            const sec = Math.floor(c.s);
            tm.textContent = Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0");
            // (its own block: the sentence kept with a saved word is this line, without the time)
            const tx = document.createElement("div");
            tx.className = "tx"; tx.textContent = c.t;
            // (the second language's words for this line, small and grey)
            const t2 = document.createElement("div");
            t2.className = "t2";
            line.append(tm, tx, t2);
            frag.appendChild(line);
            return line;
        });
        st.rail.replaceChildren(frag);
        subs2Fill();
        subsSize();
        st.centers = [];
        subsLayout();
        subsColour(st.key);
        if (cues.length && !st.running) { st.running = true; requestAnimationFrame(subsFrame); }
    }

    // the 漢字 in their tone colours (華語's, as the page colours work), glowing a little; letters stay plain
    // ── 簡體 subtitles → 繁體 (on by default): each word as the 華語 dictionary writes it (头发 → 頭髮, 后来 → 後來),
    // the rest character by character (d-s2t.json: characters that are only ever 簡體). The words you know (繁體, from
    // the app) are found that way too, and a word saved keeps its sentence in 繁體. The subtitles' own text is kept.
    // (d-s2t.json: m the characters to change, s the ones only ever 簡體, which tell 簡體 subtitles from 繁體 ones;
    // an older file: one table, every character only 簡體)
    let s2tTable = null, s2tStrict = null;
    async function getS2T() {
        if (s2tTable === null) {
            let o = {};
            try { o = (await getFile("d-s2t.json")) || {}; } catch (e) {}
            if (o.m) { s2tTable = o.m; s2tStrict = new Set([...(o.s || "")]); }
            else { s2tTable = o; s2tStrict = new Set(Object.keys(o)); }
        }
        return s2tTable;
    }
    // 繁 → 簡 (the s2t table turned round: each 繁體 character to its 簡體 one)
    let t2sTable = null;
    async function getT2S() {
        if (t2sTable === null) {
            const tb = await getS2T();
            t2sTable = {};
            for (const [sc, tc] of Object.entries(tb || {})) for (const ch of [...String(tc)]) if (!t2sTable[ch] && ch !== sc) t2sTable[ch] = sc;
        }
        return t2sTable;
    }
    async function subsTrad(st, key, meta) {
        if (prefs.subsTrad === "simp") {
            // (only 簡體: every line as it came, its 繁體 characters turned into 簡體 ones)
            const m = await getT2S();
            if (st.key !== key) return;
            for (const c of st.cues) {
                if (c.tc === "s") continue;
                const orig = c.o != null ? c.o : c.t;
                c.o = orig;
                c.t = [...orig].map(ch => m[ch] || ch).join("");
                c.tc = "s";
            }
            st.simpKey = null; st.simp = null;
            return;
        }
        // (from 簡體 back: the lines as they came, then as chosen below)
        for (const c of st.cues) if (c.tc === "s") { c.t = c.o; delete c.o; delete c.tc; }
        if (prefs.subsTrad === false) {
            // (turned off: the subtitles as they came)
            for (const c of st.cues) { if (c.o != null) { c.t = c.o; delete c.o; } delete c.tc; }
            st.simpKey = null; st.simp = null;
            return;
        }
        const tb = await getS2T();
        if (!tb || !Object.keys(tb).length) return;
        // (簡體 or not: decided once a few characters only 簡體 has are seen, or enough lines without any)
        if (st.simpKey !== key) { st.simpKey = key; st.simp = null; }
        if (st.simp === null) {
            let n = 0, han = 0;
            for (const c of st.cues) for (const ch of c.o != null ? c.o : c.t) { if (s2tStrict.has(ch)) n++; if (isHan(ch.codePointAt(0))) han++; }
            if (n >= 3) st.simp = true;
            else if (han > 300) st.simp = false;
            else return;
        }
        if (!st.simp) return;
        // (the lines not changed yet: new ones come in as a stream plays)
        const todo = st.cues.filter(c => !c.tc);
        if (!todo.length) return;
        const sh = meta.shards || 256, zf = new Map();
        const cps = new Set();
        for (const c of todo) for (const ch of c.t) { const cp = ch.codePointAt(0); if (isHan(cp)) cps.add(cp % sh); }
        await Promise.all([...cps].map(async i => { const nm = `d-zh-${String(i).padStart(3, "0")}.json`; zf.set(nm, await getFile(nm)); }));
        if (st.key !== key) return;
        for (const c of todo) {
            if (c.tc) continue;
            const chars = [...c.t];
            let out = "", i = 0;
            while (i < chars.length) {
                const cp = chars[i].codePointAt(0);
                if (!isHan(cp)) { out += chars[i]; i++; continue; }
                const f = zf.get(`d-zh-${String(cp % sh).padStart(3, "0")}.json`);
                let done = false;
                if (f) for (let L = Math.min(meta.max || 12, chars.length - i); L >= 2; L--) {
                    const w = chars.slice(i, i + L).join("");
                    const list = f[w];
                    if (!list) continue;
                    const hd = x => (x.k || "").split("\t")[0];
                    const e = list.find(x => hd(x) === w) || list.find(x => x.k && [...hd(x)].length === L);
                    if (!e) continue;
                    out += hd(e); i += L; done = true;
                    break;
                }
                if (!done) { out += tb[chars[i]] || chars[i]; i++; }
            }
            if (out !== c.t) { c.o = c.t; c.t = out; }
            c.tc = true;
        }
    }

    // ── the subtitles' language: 華語, 台語, 粵語 or 客語 (its words, readings, colours and meanings) ──
    const SUBS_LANGS = [["zh", "華語"], ["tw", "台語"], ["yue", "粵語"], ["hak", "客語"]];
    const subsHas = (l, meta) => !!meta && (l === "zh" || (meta[l] !== undefined ? meta[l] > 0 : l === "tw"));
    /// from the subtitles' language code (YouTube's: nan-TW 台語, yue 粵語, hak 客語, the rest 華語)
    function subsLangOfTrack() {
        const id = (subs && subs.cur) || "";
        const code = (id.includes(">") ? id.split(">")[1] : id.split("|")[0]).toLowerCase();
        if (/^(nan|zh-min|tw-nan|tai)/.test(code)) return "tw";
        if (/^(yue|zh-yue|can)/.test(code)) return "yue";
        if (/^hak/.test(code)) return "hak";
        return "zh";
    }
    function subsLangNow(meta) {
        // (自動: the add-on's one language, when it's one the subtitles can be read in; else the subtitles' own)
        const a = activeLang();
        const auto = ["zh", "tw", "yue", "hak", "eng"].includes(a) ? a : subsLangOfTrack();
        const want = prefs.subsLang && prefs.subsLang !== "auto" ? prefs.subsLang : auto;
        return subsHas(want, meta) ? want : "zh";
    }
    /// a word's characters (in the tone colours) and reading, in the subtitles' language
    function subsParts(e, L, meta) {
        // (the subtitles' own tone-colour setting, while their words are made)
        colFor = subsCol();
        try { return L === "eng" ? engParts(e) : L === "tw" ? twParts(e, meta) : L === "yue" ? yueParts(e) : L === "hak" ? hakParts(e, meta) : zhParts(e, meta); }
        finally { colFor = null; }
    }
    /// the entry to use of a word's entries (華語: not 四川話's own words, unless 四川話 is chosen)
    // (of a word's readings, the most common: 的 de, not dì)
    const subsEntry = (list, L) => {
        const ok = list.filter(x => x.k && !(L === "zh" && x.p === 3 && prefs.zhPlace !== 2));
        if (!ok.length) return null;
        return ok.reduce((a, b) => (b.f != null && (a.f == null || b.f < a.f)) ? b : a);
    };

    async function subsColour(key) {
        if (!subsCol() && !knownSet && !localKnown.size && !prefs.subsRd && !prefs.subsGl && !prefs.subsEnZh) {
            subs.lines.forEach((line, li) => { const tx = line.querySelector(".tx"); if (tx.querySelector(".w")) tx.textContent = subs.cues[li].t; });
            return;
        }
        const meta = await getMeta();
        const st = subs;
        if (!meta || st.key !== key) return;
        await subsTrad(st, key, meta);
        if (st.key !== key) return;
        st.meta = meta;
        const SL = subsLangNow(meta);
        st.lang = SL;
        const cps = new Set();
        for (const c of st.cues) for (const ch of c.t) { const cp = ch.codePointAt(0); if (isHan(cp)) cps.add(cp % (meta.shards || 256)); }
        // (the video's dictionary parts, kept with it: 生詞 and redrawing use them again without asking for them)
        const files = st.dict && st.dictKey === key ? st.dict : new Map();
        await Promise.all([...cps].map(async i => {
            const nm = `d-${SL}-${String(i).padStart(3, "0")}.json`;
            if (!files.has(nm)) files.set(nm, await getFile(nm));
        }));
        // English subtitles: the parts of the 英語 dictionary their words are in (each word, and without -s / -ing / -ed).
        // 英語 on: the words you don't know marked, with their Chinese over them (engMode); else, with 英文字幕下面標中文,
        // the Chinese under every English word (enOn)
        const engMode = SL === "eng" && !!meta.eng;
        const enOn = !engMode && !!(prefs.subsEnZh && meta.eng);
        if (enOn || engMode) {
            const names = new Set();
            for (const c of st.cues) for (const m of String(c.t).matchAll(/[A-Za-z][A-Za-z'-]+/g)) {
                for (const w of subsEnForms(m[0].toLowerCase())) names.add(engShard(w, meta));
            }
            await Promise.all([...names].map(async nm => { if (!files.has(nm)) files.set(nm, await getFile(nm)); }));
        }
        st.hasEn = false;
        if (st.key !== key) return;
        st.dict = files; st.dictKey = key;
        let total = 0, knownN = 0;
        st.lines.forEach((line, li) => {
            const tx = line.querySelector(".tx");
            const chars = [...st.cues[li].t];
            // (the line's words you don't know: 有生詞才停, and the cards over the row at the bottom)
            const unk = [];
            st.cues[li].unk = unk;
            const frag = document.createDocumentFragment();
            let plain = "";
            // (readings / meanings on: every word, also the ones without them, in a box of the same height, so the
            // characters of a line stay on one level)
            const annoOn = !!(prefs.subsRd || prefs.subsGl);
            const flush = () => {
                if (!plain) return;
                if (!annoOn && !enOn && !engMode) frag.appendChild(document.createTextNode(plain));
                else for (const t of plain.split(/(\s+)/)) {
                    if (!t) continue;
                    if (/^\s+$/.test(t)) { frag.appendChild(document.createTextNode(t)); continue; }
                    // 英語: a word you don't know (認識 ones as they are): its Chinese over it, a line under it
                    if (engMode) {
                        const hit = subsEngEntry(t, files, meta);
                        if (hit) {
                            const head = hit.e.k.split("\t")[0];
                            const known = isKnownIn(hit.w, "eng") || isKnownIn(head, "eng") || isKnownIn(head.toLowerCase(), "eng");
                            const rare = hit.e.f == null || hit.e.f >= (prefs.subsRare || 3000);
                            const mode = prefs.subsMark || "new";
                            const marked = mode === "rare" ? rare : mode === "both" ? (!known && rare) : !known;
                            if (knownSet) { total++; if (known) knownN++; }
                            if (marked) {
                                if (!unk.some(u => u.w === head)) unk.push({ w: head, e: hit.e, L: "eng", learn: learnIn(head, "eng") });
                                st.hasEn = true;
                                let box = subsEngBox(frag, subsEngZh(hit.e));
                                if (knownSet && !known) {
                                    const u = document.createElement("span");
                                    u.className = learnIn(head, "eng") ? "learn" : "new";
                                    box.appendChild(u); box = u;
                                }
                                box.appendChild(document.createTextNode(t));
                                continue;
                            }
                        }
                        if (annoOn) subsAnnotate(frag, null, null).appendChild(document.createTextNode(t));
                        else frag.appendChild(document.createTextNode(t));
                        continue;
                    }
                    // (an English word: the Chinese for it under it)
                    const g = enOn ? subsEnGloss(t, SL, files, meta) : "";
                    if (g) { st.hasEn = true; subsEnBox(frag, g).appendChild(document.createTextNode(t)); }
                    else if (annoOn) subsAnnotate(frag, null, null).appendChild(document.createTextNode(t));
                    else frag.appendChild(document.createTextNode(t));
                }
                plain = "";
            };
            let i = 0;
            while (i < chars.length) {
                const cp = chars[i].codePointAt(0);
                if (!isHan(cp)) { plain += chars[i]; i++; continue; }
                const wordStart = i;
                const sh = files.get(`d-${SL}-${String(cp % (meta.shards || 256)).padStart(3, "0")}.json`);
                let cols = [], len = 1, entry = null;
                if (sh) for (let L = Math.min(meta.max || 12, chars.length - i); L >= 1; L--) {
                    const w = chars.slice(i, i + L).join("");
                    if (sh[w]) {
                        len = L; entry = subsEntry(sh[w], SL) || sh[w][0];
                        try { cols = (subsParts(entry, SL, meta).h || []).flatMap(sg => [...sg.t].map(() => sg.c || null)); } catch (err) { cols = []; }
                        break;
                    }
                }
                flush();
                // (the word: 認識 → as it is; 不熟 → a line under it; never seen → a dotted line)
                const word = chars.slice(wordStart, wordStart + len).join("");
                let box = frag;
                // (known as written, or as the dictionary writes it: 裡 / 裏, 台 / 臺…)
                const head = entry && entry.k ? entry.k.split("\t")[0] : word;
                const known = isKnownIn(word, SL) || (head !== word && isKnownIn(head, SL));
                // (the words marked: the ones you don't know, the less common ones (past the place set: f is how
                // common, 0 the most), or the ones that are both)
                const rare = !!entry && (entry.f == null || entry.f >= (prefs.subsRare || 3000));
                const mode = prefs.subsMark || "new";
                const marked = !!entry && (mode === "rare" ? rare : mode === "both" ? (!known && rare) : !known);
                if (marked && !unk.some(u => u.w === word)) unk.push({ w: word, e: entry, L: SL, learn: learnIn(word, SL) || learnIn(head, SL) });
                // (a word marked: its reading over it and its meaning under it)
                if (annoOn) box = subsAnnotate(frag, marked ? entry : null, meta, SL);
                if (knownSet) {
                    total++;
                    const k = known;
                    if (k) knownN++;
                    else {
                        const u = document.createElement("span");
                        u.className = learnIn(word, SL) || learnIn(head, SL) ? "learn" : "new";
                        box.appendChild(u);
                        box = u;
                    }
                }
                for (let j = 0; j < len; j++) {
                    const sp = document.createElement("span");
                    sp.className = "h";
                    // (只替標出來的詞上色: a word not marked stays plain, without its glow)
                    if (cols[j] && subsCol() && !(prefs.onlyNew && !marked)) sp.style.color = "#" + cols[j];
                    else if (prefs.onlyNew && !marked) sp.className = "";
                    sp.textContent = chars[i + j];
                    sp.dataset.ci = li + ":" + (i + j);
                    box.appendChild(sp);
                }
                i += len;
            }
            flush();
            tx.replaceChildren(frag);
        });
        // 懂 %: the words of the video you know
        st.known = knownSet && total ? Math.round(100 * knownN / total) : null;
        noteSeen(st);
        subsRegroup(st);
        subsStudy();
        subsSpread();
        subsMeasure();
        subsPlace(false);
        subsDefs(true);
    }

    /// the subtitles' words again (a setting changed): readings and meanings on or off
    function subsRedraw() {
        const st = subs;
        if (!st || !st.panel) return;
        st.panel.classList.toggle("anno", !!(prefs.subsRd || prefs.subsGl));
        subsColour(st.key);
    }
    /// a word you don't know in the subtitles: a box with its reading (注音 or 拼音, in the tone colours) over it
    /// and a short meaning under it; returns where its characters go
    /// (e null: a word without them, the same height: an empty line over and under it)
    function subsAnnotate(frag, e, meta, L) {
        // (the reading and meaning take no room of their own: they may reach over the words beside it; subsSpread
        // moves a word over only when two of them would run into each other)
        const w = document.createElement("span"); w.className = (e ? "w a" : "w") + (prefs.subsRd ? " r" : "") + (prefs.subsGl ? " g" : "");
        if (prefs.subsRd) {
            const rd = document.createElement("span"); rd.className = "rd ffx";
            if (!e) rd.textContent = "\u00a0";
            else {
                let r = [];
                try { r = subsParts(e, L || "zh", meta).r || []; } catch (err) { r = []; }
                r.forEach((sg, i) => {
                const x = document.createElement("span");
                // (華語's 拼音 comes without spaces; the others bring their own spaces and hyphens)
                x.textContent = i && (L || "zh") === "zh" && !sg.t.startsWith(" ") ? " " + sg.t : sg.t;
                if (sg.c && subsCol()) x.style.color = "#" + sg.c;
                rd.appendChild(x);
                });
            }
            w.appendChild(rd);
        }
        const cw = document.createElement("span"); cw.className = "cw";
        w.appendChild(cw);
        if (prefs.subsGl) {
            const g = e ? subsGloss(e) : "";
            const gl = document.createElement("span"); gl.className = "gl ffx";
            gl.textContent = g || "\u00a0";
            if (g) gl.title = g;
            w.appendChild(gl);
        }
        frag.appendChild(w);
        return cw;
    }
    /// an English word of the subtitles: the Chinese words for it in the language on (the most usual first; at most two),
    /// or "" (short words like "the", "and", "you" are left as they are)
    const SUBS_EN_SKIP = new Set(("a an the to of and or but so if is am are was were be been being i you he she it we they me him her us " +
        "them my your his its our their this that these those in on at for with by from as not no do does did have has had will would " +
        "can could shall should may might must just oh ok okay yeah yes uh um ah hey hi what who how why when where there here than " +
        "then too very all any some").split(" "));
    // (the word, then without its ending the same way as on the page, then shorter a letter at a time down to about
    // two thirds of it; all in the same part of the list, which goes by the first two letters)
    function subsEnForms(w) {
        const out = [w];
        const add = b => { if (b.length >= 3 && !out.includes(b)) out.push(b); };
        for (const [end, adds] of EN_ENDS) {
            if (!w.endsWith(end) || w.length - end.length < 3) continue;
            const st = w.slice(0, -end.length);
            for (const a of adds) add(st + a);
            if (st.length > 3 && st[st.length - 1] === st[st.length - 2] && !/[aeiouls]/.test(st[st.length - 1])) add(st.slice(0, -1));
        }
        for (let n = w.length - 1; n >= Math.max(3, Math.ceil(w.length * 0.6)); n--) add(w.slice(0, n));
        return out;
    }
    function subsEnGloss(token, SL, files, meta) {
        const m = token.match(/^[^A-Za-z]*([A-Za-z][A-Za-z'-]*)[^A-Za-z]*$/);
        if (!m) return "";
        const w = m[1].toLowerCase();
        if (w.length < 2 || SUBS_EN_SKIP.has(w)) return "";
        let hit = null;
        for (const f of subsEnForms(w)) { const sh = files.get(engShard(f, meta)); if (sh && sh[f]) { hit = sh[f]; break; } }
        if (!hit || !hit.length) return "";
        // (the 英語 dictionary's first Chinese meaning, without its word class: "n. 跑、賽跑" → 跑、賽跑)
        const zh = String(hit[0].m || "").split("；")[0].replace(/^\s*([a-z]+\.\s*)+/, "");
        return zh.split(/[、，,]/).map(x => x.trim()).filter(Boolean).slice(0, 2).join("、");
    }
    /// 英語: a word of the subtitles in the dictionary (as it is, or a form of it): {e: its entry, w: as looked up}
    function subsEngEntry(token, files, meta) {
        const m = token.match(/^[^A-Za-z]*([A-Za-z][A-Za-z'-]*)[^A-Za-z]*$/);
        if (!m) return null;
        const w = m[1].toLowerCase();
        if (w.length < 2 || SUBS_EN_SKIP.has(w)) return null;
        for (const f of subsEnForms(w)) {
            const sh = files.get(engShard(f, meta));
            if (sh && sh[f] && sh[f].length) return { e: sh[f][0], w: f };
        }
        return null;
    }
    /// 英語: a word's Chinese, short (its first meaning, without the word class)
    function subsEngZh(e) {
        const zh = String(e.m || "").split("；")[0].replace(/^\s*([a-z]+\.\s*)+/, "").replace(/^(\s*[［\[（(][^］\]）)]*[］\]）)])+/, "");
        const t = zh.split(/[、，,]/).map(x => x.trim()).filter(Boolean).slice(0, 2).join("、");
        return t || (e.e ? e.e.replace(/^([a-z]+\.\s*)+/, "").split(/[;,]/)[0].trim() : "");
    }
    /// 英語: the box of a word you don't know: the Chinese over it (where the other languages have the reading)
    function subsEngBox(frag, g) {
        const w = document.createElement("span"); w.className = "w a r" + (prefs.subsGl ? " g" : "");
        const rd = document.createElement("span"); rd.className = "rd ffx zh"; rd.textContent = g || "\u00a0";
        if (g) rd.title = g;
        w.appendChild(rd);
        const cw = document.createElement("span"); cw.className = "cw";
        w.appendChild(cw);
        if (prefs.subsGl) { const gl = document.createElement("span"); gl.className = "gl ffx"; gl.textContent = "\u00a0"; w.appendChild(gl); }
        frag.appendChild(w);
        return cw;
    }
    /// the box of an English word: the Chinese under it (the same box as a marked word's, so the line stays level)
    function subsEnBox(frag, g) {
        const w = document.createElement("span"); w.className = "w a g" + (prefs.subsRd ? " r" : "");
        if (prefs.subsRd) { const rd = document.createElement("span"); rd.className = "rd ffx"; rd.textContent = "\u00a0"; w.appendChild(rd); }
        const cw = document.createElement("span"); cw.className = "cw";
        w.appendChild(cw);
        const gl = document.createElement("span"); gl.className = "gl ffx zh"; gl.textContent = g;
        w.appendChild(gl);
        frag.appendChild(w);
        return cw;
    }
    /// its meaning in a few words: the first English sense when 英文 is on, else the start of the 中文 one
    function subsGloss(e) {
        const en = () => e.e ? e.e.split(";")[0].replace(/\([^)]*\)/g, "").trim() : "";
        const zh = () => {
            if (!e.m) return "";
            let m = e.m.replace(/^\s*[0-9０-９]+[.．、]\s*/, "").replace(/^(\s*[〔［\[（(][^〕］\]）)]*[〕］\]）)])+/, "").split(/[。；]/)[0].trim();
            return [...m].length > 10 ? [...m].slice(0, 9).join("") + "…" : m;
        };
        return prefs.en ? (en() || zh()) : (zh() || en());
    }
    /// a character of the subtitles: the words from there on and its line (the sentence kept with a word)
    function subsCueAt(node, off) {
        const st = subs;
        if (!st || !node || !node.parentElement) return null;
        const line = node.parentElement.closest("#ff-subs .line");
        const h = node.parentElement.closest(".h[data-ci], [data-ci]");
        if (!line && !h) return null;
        // (which line: its time's number, else the line's own place, else the number in the character's data-ci,
        // the same line shown somewhere else, bigger)
        const tm = line && line.querySelector(".tm");
        let li = tm ? +tm.dataset.i : (line ? st.lines.indexOf(line) : -1);
        if (li < 0 && h) li = +h.dataset.ci.split(":")[0];
        const cue = st.cues[li];
        if (!cue) return null;
        let text = "";
        if (h) {
            const chars = [...cue.t];
            for (let i = +h.dataset.ci.split(":")[1]; i < chars.length && [...text].length < MAXLEN; i++) {
                if (!isHan(chars[i].codePointAt(0))) break;
                text += chars[i];
            }
        }
        // (the same line in the second language, e.g. the English under it)
        const t2 = line && line.querySelector(".t2");
        const tr = (st.trs && st.trs[li]) || (t2 ? t2.textContent.replace(/\s+/g, " ").trim() : "");
        return { text, sentence: cue.t.replace(/\s+/g, " ").trim(), tr };
    }

    // the line being said: lit, and moved to a third of the way down; the earlier ones above it, the next below
    function subsFrame() {
        const st = subs;
        // (only while there are subtitles: then it stops)
        if (!st || !st.cues.length) { if (st) st.running = false; return; }
        requestAnimationFrame(subsFrame);
        if (!st.panel || st.collapsed) return;
        const v = subsVideo();
        if (!v) return;
        subsClock(v);
        // (字幕時間: earlier or later, the same for every video)
        const off = subsOff();
        const t = v.currentTime + off;
        // (the last line that has started)
        let lo = 0, hi = st.cues.length - 1, at = -1;
        while (lo <= hi) { const m = (lo + hi) >> 1; if (st.cues[m].s <= t + 0.05) { at = m; lo = m + 1; } else hi = m - 1; }
        if (st.manualUntil && Date.now() > st.manualUntil) { st.manualUntil = 0; st.manual = 0; subsPlace(true); }
        if (st.slow && v.playbackRate !== 0.75) v.playbackRate = 0.75;
        // (the row at the bottom: moving all the time, at the pace of the lines)
        const tNow = smoothTime(v) + off;
        if (st.flow && !st.swap && !st.manualUntil) subsFlowAt(tNow, at);
        // (一句一句往上換: a line coloured since it was put up (the words, readings, meanings) put up again)
        if (st.swap) subsSwapFresh(at);
        // 字跟著時間變大
        subsSwell(tNow, at);
        // 重複: back to the line's start when it's over
        if (st.loop >= 0 && st.cues[st.loop]) {
            const c = st.cues[st.loop], end = subsEnd(st.loop);
            if (t >= end + 0.12 || t < c.s - 1.5) { v.currentTime = Math.max(0, c.s - off + 0.01); return; }
        }
        // 一句一停: the video waits at the end of each line (play goes on to the next)
        // (有生詞才停: only after a line with a word you don't know yet)
        else if (st.pauseEach && at >= 0 && st.stopped !== at && !v.paused && t >= subsEnd(at) - 0.08 &&
                 (st.pauseEach !== "new" || (st.cues[at].unk && st.cues[at].unk.length))) {
            st.stopped = at; v.pause();
        }
        if (at === st.now) return;
        const prev = st.now;
        st.now = at;
        if (prev >= 0 && st.lines[prev]) st.lines[prev].classList.remove("now");
        // (the lines already said: dimmer; going back in the video lights them again)
        const from = Math.max(0, Math.min(prev, at)), to = Math.max(prev, at);
        if (prev < 0 || Math.abs(at - prev) > 1) st.lines.forEach((l, i) => l.classList.toggle("past", i < at));
        else for (let i = from; i <= to; i++) if (st.lines[i]) st.lines[i].classList.toggle("past", i < at);
        if (at >= 0 && st.lines[at]) st.lines[at].classList.add("now");
        if (st.swap) subsSwapShow(at, Math.abs(at - prev) === 1);
        if (!st.manualUntil) subsPlace(true);
        subsDefs(false);
    }

    // 影片懂多少 in the app: each video's 懂 % as it was last (video id → [its name, address, %, when in seconds]),
    // sent with 傳到 App (ffSeen, then emptied) and kept for the sync folder's file (ffSeenAll, the newest 300)
    let seenCache = {}, seenAll = {};
    function noteSeen(st) {
        if (st.known == null || !store) return;
        const g = videoGroup();
        if (!g) return;
        const now = Date.now() / 1000, old = seenAll[g.id];
        if (old && old[2] === st.known && now - old[3] < 600) return;
        const v = [g.name, g.u, st.known, now];
        seenCache[g.id] = v; seenAll[g.id] = v;
        const ids = Object.keys(seenAll);
        if (ids.length > 300) for (const id of ids.sort((a, b) => seenAll[a][3] - seenAll[b][3]).slice(0, ids.length - 300)) delete seenAll[id];
        store.set({ ffSeen: seenCache, ffSeenAll: seenAll }).catch(() => {});
    }

    // 連到方方詞卡（Windows）: on YouTube and YouTube Music, the song playing (its video, name, singer, where in it,
    // playing or not, speed) goes to the 方方詞卡 program on this computer twice a second, through the add-on's
    // background (only to 127.0.0.1); what the program's 歌詞 screen asks back is done to the video (jump, pause,
    // play, speed). This page's own mark, so the program follows the tab that's playing
    const pcTab = Math.random().toString(36).slice(2, 10);
    let pcTimer = null;
    function pcSongInfo(v) {
        const music = location.hostname === "music.youtube.com";
        const txt = sel => { const e = document.querySelector(sel); return e ? e.textContent.replace(/\s+/g, " ").trim() : ""; };
        let title = "", artist = "", id = "";
        // (the player's own idea of the video playing first: in a playlist the page's heading can still be the song
        // before for a while, and YouTube keeps old hidden copies of it, so the program looked up the wrong lyrics)
        try {
            const p = document.getElementById("movie_player");
            const w = p && p.wrappedJSObject;
            const vd = w && typeof w.getVideoData === "function" ? w.getVideoData() : null;
            if (vd) { id = String(vd.video_id || ""); title = String(vd.title || "").trim(); artist = String(vd.author || "").trim(); }
        } catch (e) {}
        if (!id) try { id = new URL(location.href).searchParams.get("v") || ""; } catch (e) {}
        if (music) {
            title = txt("ytmusic-player-bar .title") || title;
            artist = (txt("ytmusic-player-bar .byline").split("•")[0] || "").trim() || artist;
        } else if (!title) {
            title = txt("ytd-watch-metadata:not([hidden]) h1 yt-formatted-string") || document.title.replace(/^\(\d+\)\s*/, "").replace(/\s*-\s*YouTube\s*$/, "");
            artist = txt("ytd-watch-metadata:not([hidden]) #owner #channel-name a") || txt("#owner #channel-name a");
        }
        return { id, title, artist, t: v.currentTime || 0, d: isFinite(v.duration) ? v.duration : 0,
            playing: !v.paused && !v.ended, rate: v.playbackRate || 1, tab: pcTab, site: music ? "music" : "youtube" };
    }
    function pcTick() {
        if (!prefs.pcLink || !/(^|\.)youtube\.com$/.test(location.hostname)) return;
        const v = document.querySelector("video");
        if (!v || !(v.duration > 0)) return;
        ask({ op: "pcNow", now: pcSongInfo(v) }).then(r => {
            if (!r || !r.ok || !r.cmds) return;
            for (const c of r.cmds) {
                if (c.op === "seek" && isFinite(c.t)) v.currentTime = Math.max(0, c.t);
                else if (c.op === "pause") v.pause();
                else if (c.op === "play") v.play().catch(() => {});
                else if (c.op === "rate" && c.r > 0) v.playbackRate = c.r;
            }
        });
    }
    function pcLinkUpdate() {
        const want = !!prefs.pcLink && /(^|\.)youtube\.com$/.test(location.hostname);
        if (want && !pcTimer) pcTimer = setInterval(pcTick, 500);
        else if (!want && pcTimer) { clearInterval(pcTimer); pcTimer = null; }
    }

    // 練習統計 in the app: the time watched with the subtitle panel (playing, the panel open), kept by day and sent
    // with 傳到 App
    let watchSince = 0, watchSecs = 0;
    function subsClock(v) {
        const now = Date.now();
        if (!v.paused && !v.ended && document.visibilityState === "visible") {
            if (watchSince) watchSecs += Math.min(1, (now - watchSince) / 1000);
            watchSince = now;
        } else watchSince = 0;
        if (watchSecs >= 30 && store) {
            const add = watchSecs; watchSecs = 0;
            const d = new Date(), day = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
            watchCache[day] = (watchCache[day] || 0) + add / 60;
            store.set({ ffWatch: watchCache }).catch(() => {});
        }
    }

    // (the video's time for the moving row, every frame: browsers tell the time only now and then, Firefox about as
    // often as the video's own frames, so the row moved in little steps on a fast screen. Between those, the time
    // goes on by the clock; it never goes back a little, and a jump (a seek) is followed at once)
    let smooth = { ct: -1, at: 0, out: 0 };
    function smoothTime(v) {
        const now = performance.now(), ct = v.currentTime;
        if (v.paused || v.seeking || v.ended || !(v.playbackRate > 0)) { smooth = { ct, at: now, out: ct }; return ct; }
        if (ct !== smooth.ct) { smooth.ct = ct; smooth.at = now; }
        let t = smooth.ct + Math.min(0.5, (now - smooth.at) / 1000) * v.playbackRate;
        if (Math.abs(t - smooth.out) > 0.6) smooth.out = t;          // (a jump)
        else smooth.out = Math.max(smooth.out, t);
        return smooth.out;
    }

    // ── 一句一句往上換 (下面一行): the line being said, and the next one small under it. When the next line starts it
    // moves up into place, getting big, and the one said goes up and away; a new next line comes in from below.
    // The lines shown are copies of the row's own (so a tap on a word looks it up the same way) ──
    function subsSwapBox() {
        const st = subs;
        if (!st.swapbox) { st.swapbox = document.createElement("div"); st.swapbox.className = "swapbox"; }
        if (st.swapbox.parentNode !== st.view) st.view.appendChild(st.swapbox);
        st.swapbox.style.setProperty("--ff-rd", (prefs.subsRdSize || 0.56) + "em");
        st.swapbox.style.setProperty("--ff-gl", (prefs.subsGlSize || 0.5) + "em");
        return st.swapbox;
    }
    function subsSwapCopy(i) {
        const st = subs, src = st.lines[i];
        if (!src) return null;
        const c = src.cloneNode(true);
        c.classList.remove("far", "past", "now");
        c.dataset.src = i;
        const tx = src.querySelector(".tx");
        c.dataset.n = tx ? tx.childNodes.length + ":" + tx.textContent.length + ":" + (tx.firstChild ? tx.firstChild.nodeName : "") : "";
        return c;
    }
    // (the subtitles' own size, readings and meanings: the same as the row's)
    function subsSwapBase() {
        const st = subs;
        return parseFloat(st.rail && st.rail.style.fontSize) || 18 * subsScale();
    }
    // (the line as big as the room allows: up to three times the subtitles' size, as long as it fits above the next
    // line (or in the whole box, without one), wrapping when it's long. Each line gets the size it will have when
    // it's being said; the next one is that line made small)
    function subsSwapFit(el) {
        const st = subs, box = st.swapbox;
        const H = box.clientHeight || 100;
        const base = subsSwapBase();
        const room = H - (prefs.subsSwapNext === false ? 0 : Math.min(H * 0.3, base * 0.8 + 10)) - 6;
        let lo = base * 0.7, hi = base * 3, best = lo;
        for (let k = 0; k < 8; k++) {
            const mid = (lo + hi) / 2;
            el.style.fontSize = mid.toFixed(1) + "px";
            if (el.offsetHeight <= room) { best = mid; lo = mid; } else hi = mid;
        }
        el.style.fontSize = best.toFixed(1) + "px";
        el.dataset.fs = best;
    }
    // (where each one goes: the line being said in the middle of the room above the next one; the next one small,
    // at the bottom)
    function subsSwapSet(el, role) {
        if (!el) return;
        const st = subs, box = st.swapbox, H = box.clientHeight || 100, h = el.offsetHeight;
        const base = subsSwapBase(), next = prefs.subsSwapNext !== false;
        const sN = Math.min(1, base * 0.6 / (+el.dataset.fs || base));
        const room = H - (next ? Math.min(H * 0.3, base * 0.8 + 10) : 0) - 6;
        let y, sc = 1, op = 1;
        if (role === "cur") y = Math.max(0, (room - h) / 2);
        else if (role === "nxt") { y = H - h * sN - 2; sc = sN; op = next ? 0.55 : 0; }
        else if (role === "in") { y = H + 4; sc = sN; op = 0; }
        else { y = -h * 0.7; op = 0; }                                  // (out: up and away)
        el.style.transform = `translate3d(0,${y.toFixed(1)}px,0) scale(${sc.toFixed(3)})`;
        el.style.opacity = op;
    }
    function subsSwapPlace() {
        const st = subs;
        if (!st.swapbox) return;
        const cur = st.swapbox.querySelector(".sw-cur"), nxt = st.swapbox.querySelector(".sw-nxt");
        if (cur) subsSwapFit(cur);
        if (nxt) subsSwapFit(nxt);
        subsSwapSet(nxt, "nxt"); subsSwapSet(cur, "cur");
    }
    function subsSwapShow(at, anim) {
        const st = subs;
        if (!st.panel || !st.view) return;
        const box = subsSwapBox();
        const mk = (i, cls) => { const c = subsSwapCopy(i); if (c) { c.classList.add(cls); c.style.transition = "none"; box.appendChild(c); subsSwapFit(c); } return c; };
        if (!anim) {
            box.replaceChildren();
            const cur = at >= 0 ? mk(at, "sw-cur") : null, nxt = mk(at + 1, "sw-nxt");
            if (cur) cur.classList.add("now");
            for (const el of box.children) el.style.transition = "none";
            subsSwapPlace();
            void box.offsetWidth;
            for (const el of box.children) el.style.transition = "";
            return;
        }
        const oldCur = box.querySelector(".sw-cur"), oldNxt = box.querySelector(".sw-nxt");
        if (oldCur) {
            oldCur.classList.remove("sw-cur", "now"); oldCur.classList.add("sw-out");
            subsSwapSet(oldCur, "out");
            setTimeout(() => oldCur.remove(), 550);
        }
        // (the one that was next: a fresh copy (it may have been coloured since) in its place, then up)
        let cur = mk(at, "sw-cur");
        if (cur) {
            if (oldNxt && +oldNxt.dataset.src === at) { cur.style.transform = oldNxt.style.transform; cur.style.opacity = oldNxt.style.opacity; oldNxt.remove(); }
            else { if (oldNxt) oldNxt.remove(); subsSwapSet(cur, "nxt"); }
        } else if (oldNxt) oldNxt.remove();
        const nxt = mk(at + 1, "sw-nxt");
        if (nxt) subsSwapSet(nxt, "in");
        void box.offsetWidth;
        if (cur) { cur.style.transition = ""; cur.classList.add("now"); subsSwapSet(cur, "cur"); }
        if (nxt) { nxt.style.transition = ""; subsSwapSet(nxt, "nxt"); }
    }
    // (a line coloured after it was put up: put up again, where it is)
    function subsSwapFresh(at) {
        const st = subs;
        if (!st.swapbox || at < 0) return;
        for (const el of st.swapbox.querySelectorAll(".sw-cur, .sw-nxt")) {
            const i = +el.dataset.src, src = st.lines[i], tx = src && src.querySelector(".tx");
            if (!tx) continue;
            const n = tx.childNodes.length + ":" + tx.textContent.length + ":" + (tx.firstChild ? tx.firstChild.nodeName : "");
            if (n === el.dataset.n) continue;
            const c = subsSwapCopy(i);
            const role = el.classList.contains("sw-cur") ? "cur" : "nxt";
            c.classList.add("sw-" + role);
            if (role === "cur") c.classList.add("now");
            c.style.transition = "none";
            el.replaceWith(c);
            subsSwapFit(c);
            subsSwapSet(c, role);
            void c.offsetWidth;
            c.style.transition = "";
        }
    }

    // ── 字跟著時間變大: the line being said, its characters (and words in letters) bigger as the line goes on, the
    // line's time shared out by how long each one is; as if it were timed like the lyrics ──
    function subsSwellUnits(line) {
        const tx = line && line.querySelector(".tx");
        if (!tx) return null;
        if (line._sw && line._sw.tx === tx && line._sw.first === tx.firstChild) return line._sw;
        // (words in letters: each in a box of its own, once; the 漢字 are already one to a box)
        const texts = [];
        const w = document.createTreeWalker(tx, NodeFilter.SHOW_TEXT);
        let n;
        while ((n = w.nextNode())) texts.push(n);
        for (const t of texts) {
            const pe = t.parentElement;
            if (!pe || pe.closest(".rd, .gl, .h, .su")) continue;
            if (!/\S/.test(t.textContent)) continue;
            const frag = document.createDocumentFragment();
            for (const part of t.textContent.split(/(\s+)/)) {
                if (!part) continue;
                if (/^\s+$/.test(part)) { frag.appendChild(document.createTextNode(part)); continue; }
                const s = document.createElement("span"); s.className = "su"; s.textContent = part;
                frag.appendChild(s);
            }
            t.replaceWith(frag);
        }
        const units = [...tx.querySelectorAll(".h, .su")].filter(e => !e.closest(".rd, .gl"));
        const cum = [];
        let total = 0;
        for (const u of units) {
            const letters = u.classList.contains("su") ? u.textContent.replace(/[^\p{L}\p{N}]/gu, "").length : 1;
            total += Math.max(letters ? 1 : 0.3, Math.min(letters, 12) * (u.classList.contains("su") ? 0.45 : 1));
            cum.push(total);
        }
        line._sw = { tx, first: tx.firstChild, units, cum, total };
        return line._sw;
    }
    function subsSwellClear(line) {
        if (!line || !line._sw) return;
        for (const u of line._sw.units) u.classList.remove("sw1", "sw2");
    }
    function subsSwell(t, at) {
        const st = subs;
        const target = !prefs.subsSwell || at < 0 ? null
            : st.swap ? (st.swapbox && st.swapbox.querySelector(".sw-cur")) : st.lines[at];
        if (st.swellEl && st.swellEl !== target) { subsSwellClear(st.swellEl); st.swellEl = null; st.swellK = -1; }
        if (!target) return;
        const sw = subsSwellUnits(target);
        if (!sw || !sw.units.length) return;
        const c = st.cues[at], end = subsEnd(at);
        // (said a little ahead of the clock, the way it sounds; past the end: all of it)
        const p = Math.min(1, Math.max(0, (t + 0.08 - c.s) / Math.max(0.3, end - c.s)));
        let k = sw.cum.findIndex(x => x > p * sw.total);
        if (k < 0) k = sw.units.length;
        if (target === st.swellEl && k === st.swellK) return;
        st.swellEl = target; st.swellK = k;
        sw.units.forEach((u, i) => { u.classList.toggle("sw1", i < k); u.classList.toggle("sw2", i === k); });
    }

    /// 字幕時間: how many seconds earlier (+) the subtitles are shown, at most 5 either way
    function subsOff() { const o = +prefs.subsOffset; return isFinite(o) ? Math.max(-5, Math.min(5, o)) : 0; }

    /// where a line ends: its own end, or the next line's start when that comes first
    function subsEnd(i) {
        const st = subs, c = st.cues[i], n = st.cues[i + 1];
        return n ? Math.min(c.e, n.s) : c.e;
    }
    // the study row's buttons
    function subsStudy() {
        const st = subs;
        if (!st.study) return;
        st.study.replaceChildren();
        const b = (text, on, title, f) => {
            const x = document.createElement("span");
            x.className = "btn" + (on ? " on" : ""); x.textContent = text; x.title = title;
            x.addEventListener("click", e => { e.stopPropagation(); f(); subsStudy(); });
            st.study.appendChild(x);
        };
        const v = () => subsVideo();
        const go = d => {
            const vv = v(); if (!vv || !st.cues.length) return;
            const i = Math.max(0, Math.min(st.cues.length - 1, (st.now < 0 ? 0 : st.now) + d));
            vv.currentTime = Math.max(0, st.cues[i].s - subsOff() + 0.01); st.stopped = -1; st.manual = 0; st.manualUntil = 0;
            if (st.loop >= 0) st.loop = i;
            if (vv.paused) vv.play().catch(() => {});
        };
        // (the language the subtitles are read in: 自動 follows the subtitles' own language)
        const ls = document.createElement("select");
        ls.className = "lang"; ls.title = ffT("字幕的讀音和意思用哪個語言");
        const LN = { zh: ffT("華語"), tw: ffT("台語"), yue: ffT("粵語"), hak: ffT("客語") };
        const auto = document.createElement("option"); auto.value = "auto";
        auto.textContent = ffT("自動") + (st.lang ? ffT("（") + LN[st.lang] + ffT("）") : "");
        ls.appendChild(auto);
        for (const [v, t] of SUBS_LANGS) { const o = document.createElement("option"); o.value = v; o.textContent = ffT(t); ls.appendChild(o); }
        ls.value = prefs.subsLang || "auto";
        ls.addEventListener("click", e => e.stopPropagation());
        ls.addEventListener("change", () => { prefs.subsLang = ls.value; savePrefs(); subsRedraw(); });
        st.study.appendChild(ls);
        const sel2 = subs2Select();
        if (sel2) st.study.appendChild(sel2);
        b(ffT("上一句"), false, ffT("回到上一句"), () => go(-1));
        b(ffT("重複"), st.loop >= 0, ffT("一直重複這一句"), () => { st.loop = st.loop >= 0 ? -1 : Math.max(0, st.now); });
        b(ffT("慢速"), !!st.slow, ffT("放慢到 0.75 倍"), () => { st.slow = !st.slow; const vv = v(); if (vv) vv.playbackRate = st.slow ? 0.75 : 1; });
        // (一句一停 → 有生詞才停 → off)
        b(st.pauseEach === "new" ? ffT("有生詞才停") : ffT("一句一停"), !!st.pauseEach,
          ffT("按一下：每一句說完都停；再按：只在有不認識的詞的句子停；再按：關掉"),
          () => { st.pauseEach = !st.pauseEach ? true : (st.pauseEach === true ? "new" : false); st.stopped = Math.max(-1, st.now - 1); });
        b(ffT("下一句"), false, ffT("跳到下一句"), () => go(1));
        // (over and under the words you don't know yet)
        // (the cards at the top: only with the row at the bottom)
        if (st.flow) b(ffT("詞卡"), !!prefs.subsDefs, ffT("畫面最上面顯示這句不認識的詞的詞卡"), () => { prefs.subsDefs = !prefs.subsDefs; savePrefs(); subsDefs(true); });
        b(ffT("讀音"), !!prefs.subsRd, ffT("不認識的詞上面標讀音"), () => { prefs.subsRd = !prefs.subsRd; savePrefs(); subsRedraw(); });
        b(ffT("意思"), !!prefs.subsGl, ffT("不認識的詞下面標意思（英文或中文，跟著「英文」的設定）"), () => { prefs.subsGl = !prefs.subsGl; savePrefs(); subsRedraw(); });
        // (生詞: the button next to the gear)
        // (how much of the video's words you know: 懂 87%)
        const m = document.createElement("span"); m.className = "meter";
        m.textContent = st.known != null ? ffT("懂 ") + st.known + "%" : "";
        m.title = ffT("這部影片的字幕裡，你認識的詞佔多少");
        st.study.appendChild(m);
    }

    // ── 生詞: the words of the video you don't know yet, all in one big window ──────────────────
    // Tap the ones you do know. 確定: those become 認識. 確定，其他加到不熟: the rest go to 不熟 too (with the line each
    // was first heard in as its sentence). Both wait in 傳到 App, like the card's buttons.
    async function subsWordListWords() {
        const st = subs, meta = await getMeta();
        if (!meta || !st.cues.length) return [];
        await subsTrad(st, st.key, meta);
        const sh = meta.shards || 256;
        const SL = subsLangNow(meta);
        const files = st.dict && st.dictKey === st.key ? st.dict : new Map();
        const cps = new Set();
        for (const c of st.cues) for (const ch of c.t) { const cp = ch.codePointAt(0); if (isHan(cp)) cps.add(cp % sh); }
        await Promise.all([...cps].map(async i => { const nm = `d-${SL}-${String(i).padStart(3, "0")}.json`; if (!files.has(nm)) files.set(nm, await getFile(nm)); }));
        st.dict = files; st.dictKey = st.key;
        const words = new Map();
        st.cues.forEach((cue, li) => {
            const chars = [...cue.t];
            let i = 0;
            while (i < chars.length) {
                const cp = chars[i].codePointAt(0);
                if (!isHan(cp)) { i++; continue; }
                const f = files.get(`d-${SL}-${String(cp % sh).padStart(3, "0")}.json`);
                let len = 1, e = null;
                if (f) for (let L = Math.min(meta.max || 12, chars.length - i); L >= 1; L--) {
                    const w = chars.slice(i, i + L).join("");
                    if (f[w]) { len = L; e = subsEntry(f[w], SL); break; }
                }
                const w = chars.slice(i, i + len).join("");
                i += len;
                if (!e) continue;
                const o = words.get(w);
                if (o) { o.n++; continue; }
                words.set(w, { w, e, k: e.k, li, n: 1, at: words.size, L: SL });
            }
        });
        // (not the ones known, already in 不熟, or already chosen here)
        // (not the ones known; the ones already marked 不熟, in the app or here, in a section of their own)
        const inQueue = w => new Set(queue.filter(q => q.w === w && keyLang(q.k) === SL).map(q => q.h));
        const qKnown = inQueue("known"), qUnknown = inQueue("unknown");
        const head = o => o.k.split("\t")[0];
        const out = [];
        for (const o of words.values()) {
            if (isKnownIn(o.w, SL) || isKnownIn(head(o), SL) || qKnown.has(o.w) || qKnown.has(head(o))) continue;
            o.learn = learnIn(o.w, SL) || learnIn(head(o), SL) || qUnknown.has(o.w) || qUnknown.has(head(o));
            out.push(o);
        }
        return out;
    }

    async function subsWordList() {
        const st = subs;
        const v = subsVideo();
        if (v && !v.paused) { v.pause(); }
        let list = await subsWordListWords();
        const meta = await getMeta();
        if (!document.getElementById("ff-mine-css")) {
            const css = document.createElement("style");
            css.id = "ff-mine-css";
            css.textContent = `
#ff-mine { all: initial; position: fixed; inset: 0; z-index: 2147483647; display: grid; place-items: center;
  background: rgba(6,7,12,.62); -webkit-backdrop-filter: blur(10px); backdrop-filter: blur(10px);
  font: 15px/1.45 -apple-system, "PingFang TC", "Heiti TC", system-ui, sans-serif; color: #eef0f6; }
#ff-mine * { box-sizing: border-box; }
#ff-mine .win { width: min(1180px, 94vw); height: min(900px, 90vh); display: flex; flex-direction: column;
  background: #15161d; border: 1px solid #2e3039; border-radius: 22px; box-shadow: 0 30px 80px rgba(0,0,0,.55); overflow: hidden;
  animation: ffMineIn .28s cubic-bezier(.2,.9,.3,1); }
@keyframes ffMineIn { from { opacity: 0; transform: translateY(14px) scale(.985); } }
#ff-mine .hd { flex: none; padding: 20px 26px 14px; border-bottom: 1px solid #262833; display: flex; flex-wrap: wrap; align-items: center; gap: 10px 18px; }
#ff-mine .hd h2 { margin: 0; font-size: 22px; font-weight: 700; }
#ff-mine .hd .sub { color: #9a9eb0; font-size: 14px; flex: 1 1 260px; }
#ff-mine .seg { display: flex; gap: 6px; }
#ff-mine button { all: unset; cursor: pointer; font-size: 14px; padding: 7px 14px; border-radius: 11px; background: #23242c;
  border: 1px solid #2e3039; color: #eef0f6; white-space: nowrap; }
#ff-mine button:hover { background: #2b2c36; }
#ff-mine .seg button.on { background: rgba(195,155,255,.22); border-color: #c39bff; }
#ff-mine .grid { flex: 1; overflow-y: auto; padding: 20px 26px 28px; display: grid; gap: 14px;
  grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); align-content: start; }
#ff-mine .t { position: relative; cursor: pointer; padding: 14px 16px 12px; border-radius: 16px; background: #1c1d25;
  border: 1.5px solid #2e3039; transition: border-color .15s, background-color .15s, transform .12s; user-select: none; -webkit-user-select: none; }
#ff-mine .t:active { transform: scale(.98); }
#ff-mine .t.on { border-color: #6fdc7f; background: rgba(111,220,127,.10); }
#ff-mine .t .rd { font-size: 13px; letter-spacing: .5px; min-height: 18px; }
#ff-mine .t .h { font-size: 30px; font-weight: 600; line-height: 1.25; text-shadow: 0 0 8px currentColor; }
#ff-mine .t .gl { color: #c9ccdb; font-size: 13.5px; margin-top: 4px; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
#ff-mine .t .sn { color: #7f8399; font-size: 12.5px; margin-top: 6px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
#ff-mine .t .n { position: absolute; top: 10px; right: 12px; font-size: 12px; color: #8b90a8; }
#ff-mine .t .ok { position: absolute; top: 9px; right: 10px; font-size: 12px; font-weight: 700; color: #0f2d16; background: #6fdc7f;
  border-radius: 8px; padding: 1px 8px; display: none; }
#ff-mine .t.on .ok { display: block; } #ff-mine .t.on .n { display: none; }
#ff-mine .sec { grid-column: 1 / -1; display: flex; align-items: baseline; gap: 12px; margin: 6px 2px -2px; font-size: 17px; font-weight: 700; }
#ff-mine .sec small { font-size: 13px; font-weight: 400; color: #8b90a8; }
#ff-mine .sec.learn { margin-top: 18px; padding-top: 16px; border-top: 1px solid #262833; color: #ffd166; }
#ff-mine .t.learn { border-color: rgba(255,209,102,.35); }
#ff-mine .t.learn.on { border-color: #6fdc7f; }
#ff-mine .empty { grid-column: 1 / -1; padding: 60px 0; text-align: center; color: #9a9eb0; font-size: 16px; }
#ff-mine .ft { flex: none; padding: 14px 26px 18px; border-top: 1px solid #262833; display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }
#ff-mine .ft .sp { flex: 1; }
#ff-mine .ft .count { color: #9a9eb0; font-size: 14px; }
#ff-mine button.go { background: rgba(111,220,127,.18); border-color: #6fdc7f; font-weight: 600; }
#ff-mine button.rest { background: rgba(255,169,77,.16); border-color: #ffa94d; font-weight: 600; }`;
            (document.head || document.documentElement).appendChild(css);
        }
        const old = document.getElementById("ff-mine"); if (old) old.remove();
        const box = document.createElement("div"); box.id = "ff-mine";
        const el = (tag, cls, text) => { const x = document.createElement(tag); if (cls) x.className = cls; if (text != null) x.textContent = text; return x; };
        const win = el("div", "win");
        box.appendChild(win);
        const known = new Set();
        let order = "at";

        const hd = el("div", "hd");
        const LN = { zh: ffT("華語"), tw: ffT("台語"), yue: ffT("粵語"), hak: ffT("客語") };
        hd.appendChild(el("h2", null, ffT("這部影片的生詞") + (list[0] ? ffT("（") + LN[list[0].L] + ffT("）") : "")));
        const sub = el("div", "sub");
        hd.appendChild(sub);
        const seg = el("div", "seg");
        const sortBtn = (o, t) => { const b = el("button", order === o ? "on" : "", t); b.addEventListener("click", () => { order = o; [...seg.children].forEach(x => x.classList.toggle("on", x === b)); draw(); }); seg.appendChild(b); };
        sortBtn("at", ffT("出現順序")); sortBtn("n", ffT("出現次數"));
        hd.appendChild(seg);
        const grid = el("div", "grid");
        const ft = el("div", "ft");
        const allBtn = el("button", null, ffT("全部認識")), noneBtn = el("button", null, ffT("全部取消"));
        const count = el("span", "count");
        const close = el("button", null, ffT("關掉"));
        const go = el("button", "go"), rest = el("button", "rest");
        ft.append(allBtn, noneBtn, count, el("span", "sp"), close, go, rest);
        win.append(hd, grid, ft);

        const fresh = () => list.filter(o => !o.learn);
        const paint = () => {
            const k = known.size, r = fresh().filter(o => !known.has(o.w)).length;
            sub.textContent = list.length ? ffT("點你已經認識的詞（綠色）。上面是還沒標過的詞，下面是已經標成不熟的詞。") : "";
            count.textContent = list.length ? ffT("認識 ") + k + ffT(" 個・其他 ") + r + ffT(" 個") : "";
            go.textContent = ffT("確定（") + k + ffT(" 個認識）");
            rest.textContent = ffT("確定，其他 ") + r + ffT(" 個加到不熟");
            go.style.display = list.length ? "" : "none";
            rest.style.display = list.length ? "" : "none";
            allBtn.style.display = noneBtn.style.display = list.length ? "" : "none";
        };
        const draw = () => {
            grid.replaceChildren();
            if (!list.length) { grid.appendChild(el("div", "empty", ffT("這部影片裡沒有還不認識的詞了。"))); paint(); return; }
            const sorted = [...list].sort(order === "n" ? (a, b) => b.n - a.n || a.at - b.at : (a, b) => a.at - b.at);
            // (two sections: the words not marked yet, then the ones already in 不熟)
            const groups = [[sorted.filter(o => !o.learn), ffT("還沒標過的詞"), "new"], [sorted.filter(o => o.learn), ffT("已經標成不熟的詞"), "learn"]];
            for (const [items, title, cls] of groups) {
            if (!items.length) continue;
            const sec = el("div", "sec " + cls);
            sec.append(el("span", null, title), el("small", null, items.length + ffT(" 個") + (cls === "learn" ? ffT("・點認識的，其他的照舊留在不熟") : "")));
            grid.appendChild(sec);
            for (const o of items) {
                const t = el("div", "t" + (o.learn ? " learn" : "") + (known.has(o.w) ? " on" : ""));
                let p = { h: [], r: [] };
                try { p = subsParts(o.e, o.L, meta); } catch (err) {}
                const rd = el("div", "rd");
                (p.r || []).forEach((sg, i) => { const x = el("span", null, i && o.L === "zh" && !sg.t.startsWith(" ") ? " " + sg.t : sg.t); if (sg.c && subsCol()) x.style.color = "#" + sg.c; rd.appendChild(x); });
                const h = el("div", "h");
                (p.h || []).forEach(sg => { const x = el("span", null, sg.t); if (sg.c && subsCol()) x.style.color = "#" + sg.c; h.appendChild(x); });
                if (!h.textContent) h.textContent = o.w;
                const gl = el("div", "gl", subsGloss(o.e));
                const sn = el("div", "sn", subs.cues[o.li] ? subs.cues[o.li].t : "");
                t.append(rd, h, gl, sn, el("span", "n", o.n > 1 ? "×" + o.n : ""), el("span", "ok", ffT("認識")));
                t.addEventListener("click", () => { if (known.has(o.w)) known.delete(o.w); else known.add(o.w); t.classList.toggle("on", known.has(o.w)); paint(); });
                grid.appendChild(t);
            }
            }
            paint();
        };
        const shut = () => { box.remove(); document.removeEventListener("keydown", esc, true); };
        const esc = e => { if (e.key === "Escape") { e.stopPropagation(); shut(); } };
        document.addEventListener("keydown", esc, true);
        box.addEventListener("click", e => { if (e.target === box) shut(); });
        close.addEventListener("click", shut);
        // (全部認識: the words not marked yet; the ones in 不熟 one by one)
        allBtn.addEventListener("click", () => { fresh().forEach(o => known.add(o.w)); draw(); });
        noneBtn.addEventListener("click", () => { known.clear(); draw(); });
        const finish = restToo => {
            for (const o of list) {
                const han = o.k.split("\t")[0];
                if (known.has(o.w)) {
                    queue = queue.filter(q => !(q.k === o.k && (q.w === "unknown" || q.w === "known")));
                    queue.push({ k: o.k, w: "known", h: han });
                    localAdd(o.w, o.L); localAdd(han, o.L);
                } else if (restToo && !o.learn) {
                    queue = queue.filter(q => !(q.k === o.k && (q.w === "unknown" || q.w === "known")));
                    queue.push(withGroup({ k: o.k, w: "unknown", h: han, x: subs.cues[o.li] ? subs.cues[o.li].t.replace(/\s+/g, " ").trim() : "" }));
                }
            }
            saveQueue(); saveKnownLocal();
            pageMarks();
            if (subs && subs.key) subsColour(subs.key);
            const k = known.size, r = restToo ? fresh().filter(o => !known.has(o.w)).length : 0;
            shut();
            toast(ffT("認識 ") + k + ffT(" 個") + (r ? ffT("・不熟 ") + r + ffT(" 個") : "") + ffT("（按「傳到 App」傳過去）"), "#3fae66");
        };
        go.addEventListener("click", () => finish(false));
        rest.addEventListener("click", () => finish(true));
        draw();
        fsTarget().appendChild(box);
    }

    // where each line's middle is (the row at the bottom), measured once its words are drawn
    function subsMeasure() {
        const st = subs;
        // (measured with every line there: the ones far away are put back first, see flowTo)
        flowAll();
        st.centers = st.flow ? st.lines.map(l => l.offsetLeft + l.offsetWidth / 2) : [];
        st.lineL = st.flow ? st.lines.map(l => l.offsetLeft) : null;
        st.lineR = st.flow ? st.lines.map(l => l.offsetLeft + l.offsetWidth) : null;
    }
    // (every line of the row back, after flowTo left the far ones out)
    function flowAll() {
        const st = subs;
        if (!st.win) return;
        for (const l of st.lines) l.classList.remove("far");
        st.rail.style.left = "";
        st.win = null;
    }
    // the row at the bottom: the line being said is in the middle halfway through it (it comes in from the right as
    // it starts, and moves on to the left as it ends), and the row moves on steadily from line to line (so it flows
    // evenly at the speed of the talking)
    function subsFlowAt(t, at) {
        const st = subs;
        if (!st.centers.length) subsMeasure();
        const c = st.centers;
        if (!c.length) return;
        const cs = st.cues;
        // (each line's middle in time: halfway through it, or to the next line when that starts sooner)
        const mid = i => { const q = cs[i], nx = cs[i + 1]; return q.s + 0.5 * Math.max(0.2, Math.min(q.e - q.s, nx ? nx.s - q.s : q.e - q.s)); };
        let k = Math.max(0, Math.min(at, c.length - 1));
        while (k > 0 && mid(k) > t) k--;
        while (k < c.length - 1 && mid(k + 1) <= t) k++;
        let x;
        const m0 = mid(k);
        if (t < m0) x = c[k] - (m0 - t) * 60;                 // (before the first line)
        else if (k >= c.length - 1) x = c[k];
        else {
            const m1 = mid(k + 1);
            const f = Math.min(1, Math.max(0, (t - m0) / Math.max(0.3, m1 - m0)));
            x = c[k] + (c[k + 1] - c[k]) * f;
        }
        flowTo(st.view.clientWidth / 2 - x + st.manual);
    }

    // (橫排: the row moved smoothly by a transform, with only the lines near the screen in it. With every line of
    // the video in it, the row was one very wide layer, which Safari draws in tiles; it sometimes dropped the tiles on
    // the left while they were still on the screen, and the words there vanished. The lines further than a screen
    // away are left out, and the row starts where the first line left in was)
    function flowTo(x) {
        const st = subs;
        const L = st.lineL, R = st.lineR, n = st.lines.length;
        if (L && R && L.length === n && n) {
            const W = st.view.clientWidth || 1;
            const need0 = -x - W * 0.5, need1 = -x + W * 1.5;
            if (!st.win || L[st.win[0]] > need0 || R[st.win[1]] < need1) {
                let a = 0; while (a < n - 1 && R[a] < -x - W) a++;
                let b = a; while (b < n - 1 && L[b + 1] < -x + 2 * W) b++;
                for (let i = 0; i < n; i++) st.lines[i].classList.toggle("far", i < a || i > b);
                st.rail.style.left = L[a].toFixed(1) + "px";
                st.win = [a, b];
            }
        }
        st.rail.style.transform = `translate3d(${x.toFixed(2)}px,0,0)`;
    }

    function subsPlace(glide) {
        const st = subs;
        if (!st.panel || !st.view || !st.lines.length) return;
        if (st.flow) {
            const v = subsVideo();
            if (st.manualUntil) {
                const c = st.centers.length ? st.centers : (subsMeasure(), st.centers);
                const i = Math.max(0, st.now);
                if (c[i] != null) flowTo(st.view.clientWidth / 2 - c[i] + st.manual);
            } else if (v) subsFlowAt(v.currentTime, st.now);
            return;
        }
        const h = st.view.clientHeight;
        const i = Math.max(0, st.now);
        const line = st.lines[i];
        if (!line) return;
        const y = h * 0.34 - (line.offsetTop + line.offsetHeight / 2) + st.manual;
        flowAll();
        st.rail.style.transition = glide ? "" : "none";
        st.rail.style.transform = `translateY(${Math.round(y)}px)`;
        if (!glide) { void st.rail.offsetHeight; st.rail.style.transition = ""; }
    }
})();
