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
    const DEFAULTS = { on: true, zhPlace: 0, zhRom: 1, twRom: 1, twPlace: -1, colours: true, en: false, zh: true, tw: true,
        yue: true, hak: true, hakAcc: 0, hakRom: 0, sv: true, svGuess: true, en2zh: true, font: 1, ring: false, tint: false, pos: "word", w: 0, h: 0,
        // 影片字幕 (YouTube, Viki): the panel on; the video stops while a word is looked up in it; the subtitles on
        // the video itself hidden while the panel shows them
        subs: true, subsPause: true, subsHideVideo: true,
        // onlyNew: the tone colours (on pages and in subtitles) only on words you don't know yet (known: from the app,
        // and the ones marked 認識 on the card here)
        onlyNew: false,
        // subsFlow: the subtitles in one row at the bottom, flowing sideways (always so when the video is full screen)
        subsFlow: false,
        // over / under the words you don't know in the subtitles: their reading, and their meaning (English or 中文, as 英文 is set)
        subsRd: true, subsGl: true,
        // the reading's size, against the characters'
        subsRdSize: 0.56,
        // keyKnown / keyNew: with the pointer on a word, the key that marks it 認識, and the one that marks it 不熟 and
        // saves it (with its sentence); keys: on or off
        keys: true, keyKnown: "a", keyNew: "s",
        // subsFont: the subtitles' size (its own, apart from the card's; A− / A+ on the panel)
        subsFont: 1 };
    let prefs = { ...DEFAULTS };
    let queue = [];               // [{k, w: "unknown" | "saved", h, x: the sentence}] waiting for 傳到 App
    let saved = [];               // [{h, c: [colours]}]: every word saved here (for the rainbow and the colours on the page)
    // the words you know (認識) and are learning (不熟) in the app, sent with its 把認識的詞傳到 Safari 查詞: the
    // subtitle panel marks the others and tells how much of a video you know
    let knownSet = null, learnSet = new Set();
    let localKnown = new Set();   // 認識 on the card here (sent to the app with 傳到 App, too)
    const isKnown = w => (knownSet && knownSet.has(w)) || localKnown.has(w);
    let watchCache = {};          // {"2026-11-14": minutes watched with the subtitle panel}, sent with 傳到 App
    function setKnown(o) {
        if (!o || !o.k) { knownSet = null; learnSet = new Set(); return; }
        knownSet = new Set(Object.values(o.k).flat());
        learnSet = new Set(Object.values(o.u || {}).flat());
    }
    const store = browser.storage && browser.storage.local;
    if (store) {
        store.get(["ffPrefs", "ffQueue", "ffSaved", "ffKnown", "ffWatch", "ffKnownLocal"]).then(r => {
            localKnown = new Set(r.ffKnownLocal || []);
            watchCache = r.ffWatch || {};
            prefs = fixPrefs(r.ffPrefs);
            queue = r.ffQueue || [];
            saved = r.ffSaved || [];
            setKnown(r.ffKnown);
            pageMarks();
        }).catch(() => {});
        // (changed in the extension's own window, from its button in Safari's toolbar, or on another page)
        if (browser.storage.onChanged) browser.storage.onChanged.addListener((ch, area) => {
            if (ch.ffPrefs) { prefs = fixPrefs(ch.ffPrefs.newValue); if (isOpen() && last && !card.querySelector(".set")) redraw(); }
            if (ch.ffQueue) queue = ch.ffQueue.newValue || [];
            if (ch.ffSaved) saved = ch.ffSaved.newValue || [];
            if (ch.ffWatch) watchCache = ch.ffWatch.newValue || {};
            if (ch.ffKnownLocal) { localKnown = new Set(ch.ffKnownLocal.newValue || []); pageMarks(); if (subs && subs.key) subsColour(subs.key); }
            if (ch.ffKnown) { setKnown(ch.ffKnown.newValue); if (subs && subs.key) subsColour(subs.key); }
            if (ch.ffPrefs || ch.ffSaved) { if (!prefs.on && !(subs && subs.pausedBy)) hide(); pageMarks(); }
            if (ch.ffPrefs && subs && subs.panel) {
                const o = ch.ffPrefs.oldValue || {}, n = ch.ffPrefs.newValue || {};
                subsSize(); subsLayout();
                if (["subsRd", "subsGl", "en", "zhRom", "zhPlace", "colours", "onlyNew"].some(k => o[k] !== n[k])) subsRedraw();
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
                box.textContent = "方方詞卡 查詞 收到了：認識的詞 " + n + " 個、不熟的詞 " + u + " 個。影片字幕裡沒學過的詞會有底線，面板上會顯示你懂多少。這一頁可以關掉了。";
                document.documentElement.appendChild(box);
            } catch (e) {}
        })();
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
    const saveKnownLocal = () => store && store.set({ ffKnownLocal: [...localKnown].slice(-20000) }).catch(() => {});

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
    function prefetch(cp) {
        getMeta().then(m => {
            if (!m) return;
            for (const l of ["zh", "tw", "yue", "hak"]) if (prefs[l] && (m[l] === undefined || m[l] > 0)) getFile(shardName(l, cp, m));
        });
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
    function enShard(w, meta) { return svShard(w, meta).replace("d-sv-", "d-en-"); }
    async function findEn(text) {
        const meta = await getMeta();
        if (!meta) return { ok: true, ready: false };
        const out = { ok: true, ready: true, tab: meta };
        let w = text.toLowerCase();
        if (!prefs.en2zh || !meta.en || w.length < 2) return out;
        const sh = await getFile(enShard(w, meta));
        let hit = sh && sh[w];
        // (eats, eating, eaten: the word without its ending)
        if (!hit) for (const end of ["ing", "ed", "es", "s"]) {
            if (!w.endsWith(end) || w.length - end.length < 3) continue;
            for (const b of [w.slice(0, -end.length), w.slice(0, -end.length) + "e"]) {
                const s2 = await getFile(enShard(b, meta));
                if (s2 && s2[b]) { hit = s2[b]; break; }
            }
            if (hit) break;
        }
        if (!hit) return out;
        for (const lang of ["zh", "tw", "yue", "hak"]) {
            if (!prefs[lang] || !hit[lang]) continue;
            const list = [];
            for (const h of hit[lang]) {
                const s2 = await getFile(shardName(lang, h.codePointAt(0), meta));
                for (const e of (s2 && s2[h]) || []) {
                    // (the word's own entries, not the 台語 words given for a 華語 word)
                    if (e.k.split("\t")[0] !== h || e.v || list.some(x => x.k === e.k)) continue;
                    list.push(e);
                }
            }
            if (list.length) out[lang] = { w: text, list: list.slice(0, 6), en: true };
        }
        return out;
    }
    // a Latin word: 瑞典語 and English together
    async function findLatin(text) {
        const a = prefs.sv ? await findSv(text) : { ok: true, ready: true };
        if (!a.ok || !a.ready) return a;
        const b = await findEn(text);
        if (!b.ready) return a.tab ? a : b;
        for (const l of ["zh", "tw", "yue", "hak"]) if (b[l]) a[l] = b[l];
        if (!a.tab) a.tab = b.tab;
        return a;
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
    async function lookup(text, rect, spot, at, sv) {
        const n = ++busy;
        const res = sv ? await findLatin(text) : await find(text);
        if (n !== busy) return;                       // (a newer one was asked meanwhile)
        if (!res || !res.ok) { show(rect, spot, message("查詞沒有回應。請在 Safari 的延伸功能設定裡允許「方方詞卡 查詞」。")); return; }
        if (!res.ready) { show(rect, spot, message("查詞的資料不在延伸功能裡：請在 Mac 上重新執行一次安裝。")); return; }
        if (!res.zh && !res.tw && !res.yue && !res.hak && !res.sv) { hide(); return; }
        last = { res, rect, spot };
        show(rect, spot, render(res));
        // the word on the page, marked in light blue (the longer of the 華語 and the 台語 word found)
        const len = Math.max(...["zh", "tw", "yue", "hak", "sv"].map(l => res[l] ? [...res[l].w].length : 0));
        if (at) markWord(at.node, at.off, len); else unmark();
        const sc = at && subsCueAt(at.node, at.off);
        lastSentence = sc ? sc.sentence : (at ? sentenceAt(at.node, at.off) : (window.getSelection ? sentenceOfSelection() : ""));
    }

    // ── the light blue mark around the word ─────────────────────────────────────────────────
    let marks = null;
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
        const h = whole && many ? ms.map((m, i) => ({ t: m.t, c: prefs.colours && m.k !== "w" ? cols[i] : null })) : [{ t: head, c: null }];
        const r = many ? ms.map((m, i) => ({ t: m.k === "w" ? " " : ((i && ms[i - 1].k !== "w" ? "-" : "") + m.t), c: prefs.colours && m.k !== "w" ? cols[i] : null })) : [];
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
                if (found && !(prefs.onlyNew && isKnown(chars.slice(i, i + len).join("")))) {
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
        .sec { border-radius: 10px; padding: 6px 9px 8px; border-left: 4px solid transparent; }
        .sec + .sec { margin-top: 8px; }
        .sec.zh { background: rgba(79, 125, 255, 0.10); border-left-color: #4f7dff; }
        .sec.tw { background: rgba(63, 174, 102, 0.10); border-left-color: #3fae66; }
        .sec.yue { background: rgba(201, 162, 39, 0.10); border-left-color: #c9a227; }
        .sec.hak { background: rgba(216, 67, 79, 0.10); border-left-color: #d8434f; }
        .sec.sv { background: rgba(63, 201, 189, 0.08); border-left-color: #3fc9bd; }
        .cols { display: flex; gap: 8px; align-items: flex-start; }
        .cols > .sec { flex: 1 1 0; min-width: 190px; margin-top: 0; }
        .lang { display: inline-block; font-size: 12px; padding: 1px 7px; border-radius: 6px; margin-bottom: 4px; }
        .lang.zh { background: #1f3d6b; border: 1px solid #4f7dff; color: #9ad0ff; }
        .lang.tw { background: #1d4630; border: 1px solid #3fae66; color: #b6f0c8; }
        .lang.yue { background: #5a4a14; border: 1px solid #c9a227; color: #ffe58a; }
        .lang.hak { background: #5a1e2a; border: 1px solid #d8434f; color: #ffb3b8; }
        .lang.sv { background: #0f4a4a; border: 1px solid #3fc9bd; color: #9cf0e6; }
        .chip.sv { background: #163f3c; border-color: #3fc9bd; color: #9cf0e6; }
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
        const NAMES = { zh: "華語", tw: "台語", yue: "粵語", hak: "客語", sv: "瑞典語" };
        for (const lang of ["zh", "tw", "yue", "hak", "sv"]) {
            const part = res[lang];
            if (!part) continue;
            const sec = el("div", "sec " + lang);
            sec.appendChild(el("span", "lang " + lang, NAMES[lang] + (lang === "hak" && tab.hacc && tab.hacc[prefs.hakAcc] ? "・" + tab.hacc[prefs.hakAcc] : "") + (part.en ? "・英文「" + part.w + "」" : "")));
            for (const e of part.list) {
                if (lang === "zh" && e.p === 3 && prefs.zhPlace !== 2) continue;     // (四川話's own words: with 四川話 only)
                const p = lang === "sv" ? svParts(e, part.form) : lang === "zh" ? zhParts(e, tab) : (lang === "tw" ? twParts(e, tab) : (lang === "yue" ? yueParts(e) : hakParts(e, tab)));
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
                if (lang === "sv" && e.w) chips.push([e.w, "sv"]);
                if (lang === "sv" && e.est && !e.inDict) chips.push(["詞典裡沒有：照詞和構詞規則推算，可能有誤", "p0"]);
                if (lang === "sv" && part.form && !e.est && part.form.toLowerCase() !== e.k.split("\t")[0].toLowerCase()) chips.push(["「" + e.k.split("\t")[0] + "」的變化", "sv"]);
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
                if (e.m) d.appendChild(el("div", "m", e.m));
                else if (lang === "sv" && e.q && prefs.svGuess) d.appendChild(el("div", "m", "≈ " + e.q + "（由英文推測）"));
                if (e.eq && e.eq.length && lang === "zh" && prefs.zhPlace === 2) d.appendChild(el("div", "en", "華語：" + e.eq.join("、")));
                if ((prefs.en || (lang === "sv" && !e.m)) && e.e) d.appendChild(el("div", "en", e.e));
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
            kn.textContent = qk ? "已選：認識" : "認識";
            kn.classList.toggle("on", qk);
            u.textContent = qu ? "已選：加到不熟" : "加到不熟";
            u.classList.toggle("on", qu);
            sv.textContent = qs ? "已選：收藏" : "收藏";
            sv.classList.toggle("on", qs);
        };
        paint();
        const go = w => ev => {
            ev.preventDefault(); ev.stopPropagation();
            if (queued(key, w)) {
                queue = queue.filter(q => !(q.k === key && q.w === w));
                if (w === "known") { localKnown.delete(han); saveKnownLocal(); }
            } else {
                // (認識 and 加到不熟 don't go together)
                if (w === "known") queue = queue.filter(q => !(q.k === key && q.w === "unknown"));
                if (w === "unknown") { queue = queue.filter(q => !(q.k === key && q.w === "known")); localKnown.delete(han); saveKnownLocal(); }
                if (w === "known") { localKnown.add(han); saveKnownLocal(); }
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
        kn.addEventListener("click", go("known"));
        row.append(u, sv, kn);
        return row;
    }

    // opens the app with the words (Safari asks first whether to open it)
    function sendToApp() {
        if (!queue.length) return;
        const op = w => w === "saved" ? "s" : (w === "known" ? "k" : "u");
        const ops = queue.map(q => q.x ? [q.k, op(q.w), q.x] : [q.k, op(q.w)]);
        const pack = o => btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(o)))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
        // (and the minutes watched with the subtitle panel, for 練習統計)
        // (kept in memory too, so the app opens straight from the tap: Safari only opens it from a tap)
        let w = "";
        if (Object.keys(watchCache).length) { w = "&w=" + pack(watchCache); watchCache = {}; if (store) store.set({ ffWatch: {} }).catch(() => {}); }
        const a = document.createElement("a");
        a.href = "fangfangcards://safari?ops=" + pack(ops) + w;
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
        row("瑞典語", "sv", yesNo);
        row("英文查中文", "en2zh", yesNo);
        row("瑞典語：由英文推測中文", "svGuess", [[true, "顯示"], [false, "不顯示"]]);
        row("聲調顏色", "colours", [[true, "開"], [false, "關"]]);
        row("字的大小", "font", [[0.85, "小"], [1, "中"], [1.15, "大"], [1.3, "更大"], [1.5, "很大"], [1.8, "特大"], [2.2, "超大"], [2.7, "最大"]]);
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
        if (isOpen() && !card.querySelector(".set")) hideTimer = setTimeout(hide, HIDE);
    }
    const inCard = e => host && e.composedPath && e.composedPath().includes(host);
    /// the pointer over the subtitle panel (its words open with a tap or a click there, never by hovering)
    function overSubs(e) {
        if (e.target && e.target.closest && e.target.closest("#ff-subs")) return true;
        const p = typeof subs !== "undefined" && subs && subs.panel;
        if (!p || p.classList.contains("hidden")) return false;
        const r = p.getBoundingClientRect();
        return e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom;
    }

    // ── the Pencil (or a trackpad / mouse) hovering ─────────────────────────────────────────
    // (the Pencil, a trackpad or a mouse; on the Mac, Safari may send only mouse events)
    let lastPointer = 0;
    let px = -1, py = -1;          // (where the pointer is: for the keys that mark the word under it)
    document.addEventListener("pointermove", e => {
        if (e.pointerType === "touch") return;
        lastPointer = Date.now();
        px = e.clientX; py = e.clientY;
        hover(e);
    }, { capture: true, passive: true });
    document.addEventListener("mousemove", e => {
        px = e.clientX; py = e.clientY;
        if (Date.now() - lastPointer < 300) return;               // (already handled as a pointer event)
        hover(e);
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
        if (px < 0) return;
        const hit = charAt(px, py);
        if (!hit) return;
        const inSubs = hit.node.parentElement && hit.node.parentElement.closest("#ff-subs");
        if (!prefs.on && !inSubs) return;
        const lat = !isHan(hit.cp) && (prefs.sv || prefs.en2zh) && isLat(hit.cp) ? latWordAt(hit.node, hit.off) : null;
        if (!isHan(hit.cp) && !lat) return;
        // (the site's own use of the key, e.g. YouTube's, doesn't happen: the pointer is on a word)
        e.preventDefault(); e.stopImmediatePropagation();
        const sc = inSubs ? subsCueAt(hit.node, hit.off) : null;
        const text = lat ? lat.text : (sc && sc.text ? sc.text : textFrom(hit.node, hit.off));
        const res = lat ? await findLatin(text) : await find(text);
        if (!res || !res.ok) return;
        // the first language the card would show
        let pick = null, lang = "";
        for (const l of ["zh", "tw", "yue", "hak", "sv"]) {
            const part = res[l];
            if (!part || !part.list) continue;
            const e0 = part.list.find(x => x.k && !(l === "zh" && x.p === 3 && prefs.zhPlace !== 2));
            if (e0) { pick = e0; lang = l; break; }
        }
        if (!pick) return;
        const key = pick.k, han = key.split("\t")[0];
        const sentence = (sc ? sc.sentence : sentenceAt(hit.node, lat ? lat.start : hit.off)) || "";
        if (want === "known") {
            queue = queue.filter(q => !(q.k === key && (q.w === "unknown" || q.w === "known")));
            queue.push({ k: key, w: "known", h: han });
            localKnown.add(han); saveKnownLocal();
        } else {
            queue = queue.filter(q => !(q.k === key && (q.w === "known" || q.w === "unknown" || q.w === "saved")));
            queue.push({ k: key, w: "unknown", h: han, x: sentence });
            queue.push({ k: key, w: "saved", h: han, x: sentence });
            localKnown.delete(han); saveKnownLocal();
            if (!saved.some(x => x.h === han)) { saved.push({ h: han, c: [] }); saveSaved(); }
        }
        saveQueue();
        pageMarks();
        if (subs && subs.key) subsColour(subs.key);
        if (isOpen() && last && !card.querySelector(".set")) redraw();
        const NAMES = { zh: "華語", tw: "台語", yue: "粵語", hak: "客語", sv: "瑞典語" };
        toast((want === "known" ? "認識：" : "不熟＋收藏：") + han + "（" + NAMES[lang] + "）", want === "known" ? "#3fae66" : "#c9a227");
    }, true);

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

    function hover(e) {
        // (網頁查詞 turned off in Safari's toolbar: only the subtitle panel's words are still looked up)
        if (!alive() || (!prefs.on && !(e.target && e.target.closest && e.target.closest("#ff-subs")))) return;
        // (the subtitle panel: nothing by hovering; its words open with a tap or a click)
        // (checked three ways: the element under the pointer, the panel's place on the screen, and the text found)
        if (overSubs(e)) { clearTimeout(dwellTimer); return; }
        if (e.buttons !== 0) return;                              // writing / dragging, not hovering
        if (!metaP) getMeta();                                    // (the Pencil is near: the tables read already)
        if (inCard(e)) { clearTimeout(hideTimer); clearTimeout(dwellTimer); return; }
        const hit = charAt(e.clientX, e.clientY);
        if (hit && hit.node && hit.node.parentElement && hit.node.parentElement.closest("#ff-subs")) { clearTimeout(dwellTimer); return; }
        // (瑞典語: a Latin letter, the whole word around it)
        // (a Latin word: 瑞典語, and English → the Chinese languages)
        const lat = hit && !isHan(hit.cp) && (prefs.sv || prefs.en2zh) && isLat(hit.cp) ? latWordAt(hit.node, hit.off) : null;
        if (!hit || (!isHan(hit.cp) && !lat)) { clearTimeout(dwellTimer); lastSpot = ""; hideSoon(); return; }
        const spot = lat ? "w" + lat.start + ":" + lat.text + "@" + Math.round(hit.rect.top) : hit.off + "@" + Math.round(hit.rect.left) + "," + Math.round(hit.rect.top);
        if (spot === shownSpot) { clearTimeout(hideTimer); return; }
        if (spot === lastSpot) return;
        lastSpot = spot;
        clearTimeout(dwellTimer);
        if (lat) {
            getMeta().then(m => {
                if (m && m.sv && prefs.sv) getFile(svShard(lat.text.toLowerCase(), m));
                if (m && m.en && prefs.en2zh) getFile(enShard(lat.text.toLowerCase(), m));
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
        clearTimeout(dwellTimer); lastSpot = ""; hide();
    }, { passive: true, capture: true });
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
            const sv = (prefs.sv || prefs.en2zh) && isLat(s.charCodeAt(0)) && [...s].every(c => isLat(c.charCodeAt(0)));
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
    function ytVideoId() {
        if (!/youtube\.com$/.test(location.hostname)) return "";
        const u = new URL(location.href);
        return u.searchParams.get("v") || (u.pathname.match(/\/(shorts|live|embed)\/([\w-]{6,})/) || [])[2] || "";
    }

    // every second: a new video? subtitle tracks Safari has (sites without a file to see)?
    function subsTick() {
        const st = subs;
        if (!subsMine()) return;
        if (!prefs.subs) { if (st.panel) st.panel.style.display = "none"; return; }
        const vid = ytVideoId() || (SUBS_SITE ? location.pathname : "");
        if (vid !== st.vid) {
            st.vid = vid; st.files.clear(); st.key = ""; st.ytTracks = []; st.ytTrans = []; st.cur = ""; st.tried.clear();
            subsShow([]);
            if (ytVideoId()) subsAskTracks(0);
        }
        // tracks the browser itself loads (<track>, Safari's own HLS subtitles): only the one the site is showing
        // (the language chosen in its player); other languages are never turned on. (Not on YouTube: its own way.)
        const v = subsVideo();
        if (!ytVideoId() && v && v.textTracks && v.textTracks.length && Date.now() - st.textTracksAt > 2000) {
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
    function subsRank(t) {
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
    function subsClean(cues) {
        const ta = document.createElement("textarea");
        const out = [];
        for (const c of cues) {
            ta.innerHTML = String(c.t).replace(/<[^>]+>/g, "").replace(/\{\\[^}]*\}/g, "");
            const t = ta.value.replace(/\s*\n\s*/g, " ").replace(/\s+/g, " ").trim();
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
  background: rgba(16, 18, 28, 0.9); -webkit-backdrop-filter: blur(14px); backdrop-filter: blur(14px);
  border: 1px solid rgba(255,255,255,0.10); border-radius: 16px; box-shadow: 0 10px 30px rgba(0,0,0,0.35);
  color: #e9eaf2; font: 18px/1.55 -apple-system, "PingFang TC", "Heiti TC", system-ui, sans-serif; overflow: hidden;
  transition: opacity .3s ease, transform .35s cubic-bezier(.2,.9,.3,1); }
#ff-subs.wide { top: 72px; right: 12px; bottom: 12px; width: min(380px, 34vw); }
#ff-subs.narrow { left: 8px; right: 8px; bottom: 8px; height: 40vh; }
#ff-subs.hidden { opacity: 0; transform: translateY(12px); pointer-events: none; }
#ff-subs .top { position: absolute; left: 0; right: 0; top: 0; height: 38px; display: flex; align-items: center; gap: 8px;
  padding: 0 10px 0 14px; box-sizing: border-box; border-bottom: 1px solid rgba(255,255,255,0.07); font-size: 13px; color: #a7abc0; }
#ff-subs .top b { font-weight: 600; color: #e9eaf2; margin-right: auto; font-size: 13px; }
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
#ff-subs .w { display: inline-flex; flex-direction: column; align-items: center; vertical-align: top; line-height: 1.2; }
#ff-subs .w.a { margin: 0 .14em; }
#ff-subs .line:has(.w) .tm { vertical-align: middle; }
#ff-subs .cw { white-space: nowrap; }
#ff-subs .rd, #ff-subs .gl { user-select: none; -webkit-user-select: none; white-space: nowrap; pointer-events: none;
  font-family: -apple-system, system-ui, "PingFang TC", sans-serif; }
#ff-subs .rd { font-size: var(--ff-rd, .56em); margin-bottom: 1px; }
#ff-subs .gl { font-size: .5em; color: #b6bad0; max-width: 9em; overflow: hidden; text-overflow: ellipsis; margin-top: 2px; }
#ff-subs.flow .view { top: 38px; }
#ff-subs.flow .top b { margin-right: 2px; }
#ff-subs.flow .top .study { position: static; flex: 1 1 auto; min-width: 0; height: 38px; border-bottom: none; padding: 0 4px; }
#ff-subs .empty { display: block; padding: 18px; color: #8b90a8; font-size: 14px; }
#ff-subs.flow { left: 12px; right: 12px; bottom: 12px; top: auto; width: auto; height: 116px; }
#ff-subs.flow .view { -webkit-mask-image: linear-gradient(90deg, transparent 0, #000 10%, #000 90%, transparent 100%);
  mask-image: linear-gradient(90deg, transparent 0, #000 10%, #000 90%, transparent 100%); }
#ff-subs.flow .rail { display: flex; flex-wrap: nowrap; align-items: center; height: 100%; padding: 0; gap: 4px;
  white-space: nowrap; transition: none; }
#ff-subs.flow .line { flex: none; margin: 0; padding: 8px 14px; }
#ff-subs.mini { height: 38px !important; }
#ff-subs.wide.mini { bottom: auto; }
#ff-subs.mini .view { display: none; }
#ff-subs.mini .top { border-bottom: none; }
@media (prefers-reduced-motion: reduce) { #ff-subs .rail { transition: none; } }`;
        (document.head || document.documentElement).appendChild(css);
        const p = document.createElement("div");
        p.id = "ff-subs";
        p.className = "hidden";
        const top = document.createElement("div"); top.className = "top";
        const view = document.createElement("div"); view.className = "view";
        const rail = document.createElement("div"); rail.className = "rail";
        view.appendChild(rail);
        // the study row: the line before / after, this line again and again, slower, a stop after each line
        const study = document.createElement("div"); study.className = "study";
        p.append(top, study, view);
        st.study = study;
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
                    v.currentTime = st.cues[i].s + 0.01; st.manual = 0; st.manualUntil = 0;
                    if (st.loop >= 0) { st.loop = i; subsStudy(); }        // (repeating: now this line)
                    st.stopped = -1;
                }
                return;
            }
            // (a tap with a finger, the Pencil or a click: the subtitles' words open only this way, not by hovering)
            if (d.type === "mouse" && e.button !== 0) return;
            const hit = charAt(e.clientX, e.clientY);
            if (!hit) return;
            const lat = !isHan(hit.cp) && (prefs.sv || prefs.en2zh) && isLat(hit.cp) ? latWordAt(hit.node, hit.off) : null;
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
        subsLayout();
        return p;
    }

    function subsLayout() {
        const st = subs;
        if (!st.panel) return;
        const fsT = fsTarget();
        if (st.panel.parentNode !== fsT) fsT.appendChild(st.panel);
        const flow = !!prefs.subsFlow || fsT !== document.documentElement;
        const wide = window.innerWidth >= 900 && window.innerWidth > window.innerHeight;
        const changed = flow !== st.flow;
        st.flow = flow;
        st.panel.classList.toggle("flow", flow);
        st.panel.classList.toggle("wide", !flow && wide);
        st.panel.classList.toggle("narrow", !flow && !wide);
        st.panel.classList.toggle("mini", st.collapsed);
        // (the row at the bottom: tall enough for the letters)
        // (one line on top; the readings and meanings over and under the words need room too)
        const fs = 18 * (prefs.subsFont || 1), anno = prefs.subsRd || prefs.subsGl;
        st.panel.style.height = flow && !st.collapsed ? Math.round(38 + Math.max(76, fs * (anno ? 3.6 + (prefs.subsRdSize || 0.56) : 3))) + "px" : "";
        const has = st.cues.length > 0 && prefs.subs;
        st.panel.classList.toggle("hidden", !has);
        if (changed) { st.manual = 0; st.manualUntil = 0; subsHeader(); }
        subsMeasure();
        subsPlace(false);
    }

    function subsHeader() {
        const st = subs;
        if (!st.top) return;
        st.top.replaceChildren();
        const title = document.createElement("b"); title.textContent = "字幕";
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
            st.ytTracks.forEach((t, i) => add(sel, "t" + i, t.name + (t.kind === "asr" ? "（自動）" : "")));
            const base = subsBase();
            if (st.ytTrans.length && base) {
                const g = document.createElement("optgroup");
                g.label = "自動翻譯";
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
        eye.textContent = prefs.subsHideVideo ? "影片上：關" : "影片上：開";
        eye.title = "影片上的字幕";
        eye.addEventListener("click", e => { e.stopPropagation(); prefs.subsHideVideo = !prefs.subsHideVideo; savePrefs(); subsHeader(); subsTick(); });
        // (full screen: always the row at the bottom)
        const lay = document.createElement("span"); lay.className = "btn";
        lay.textContent = st.flow ? "直排" : "橫排";
        lay.title = st.flow ? "字幕在旁邊，往上捲" : "字幕在下面，往旁邊流";
        if (fsTarget() !== document.documentElement) lay.style.display = "none";
        lay.addEventListener("click", e => { e.stopPropagation(); prefs.subsFlow = !prefs.subsFlow; savePrefs(); subsLayout(); });
        const min = document.createElement("span"); min.className = "btn"; min.textContent = st.collapsed ? "展開" : "收起";
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
        smaller.title = "字小一點"; smaller.addEventListener("click", step(-1));
        const bigger = document.createElement("span"); bigger.className = "btn"; bigger.textContent = "A+";
        bigger.title = "字大一點"; bigger.addEventListener("click", step(1));
        st.top.append(smaller, bigger, eye, lay, min);
        // (the row at the bottom: one line on top, the study buttons and 懂 % in it, after 字幕; at the side: their own line)
        if (st.study) {
            if (st.flow) title.after(st.study);
            else if (st.study.parentNode !== st.panel) st.panel.insertBefore(st.study, st.view);
        }
        subsStudy();
    }

    // the subtitles' size (from 設定, or A− / A+ on the panel)
    function subsSize() {
        const st = subs;
        if (!st || !st.rail) return;
        st.rail.style.fontSize = Math.round(18 * (prefs.subsFont || 1)) + "px";
        st.rail.style.setProperty("--ff-rd", (prefs.subsRdSize || 0.56) + "em");
        st.centers = [];
        requestAnimationFrame(() => { subsMeasure(); subsPlace(false); });
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
            line.append(tm, tx);
            frag.appendChild(line);
            return line;
        });
        st.rail.replaceChildren(frag);
        subsSize();
        st.centers = [];
        subsLayout();
        subsColour(st.key);
        if (cues.length && !st.running) { st.running = true; requestAnimationFrame(subsFrame); }
    }

    // the 漢字 in their tone colours (華語's, as the page colours work), glowing a little; letters stay plain
    async function subsColour(key) {
        if (!prefs.colours && !knownSet && !localKnown.size && !prefs.subsRd && !prefs.subsGl) {
            subs.lines.forEach((line, li) => { const tx = line.querySelector(".tx"); if (tx.querySelector(".w")) tx.textContent = subs.cues[li].t; });
            return;
        }
        const meta = await getMeta();
        const st = subs;
        if (!meta || st.key !== key) return;
        const cps = new Set();
        for (const c of st.cues) for (const ch of c.t) { const cp = ch.codePointAt(0); if (isHan(cp)) cps.add(cp % (meta.shards || 256)); }
        const files = new Map();
        await Promise.all([...cps].map(async i => {
            const nm = `d-zh-${String(i).padStart(3, "0")}.json`;
            files.set(nm, await getFile(nm));
        }));
        if (st.key !== key) return;
        let total = 0, knownN = 0;
        st.lines.forEach((line, li) => {
            const tx = line.querySelector(".tx");
            const chars = [...st.cues[li].t];
            const frag = document.createDocumentFragment();
            let plain = "";
            // (readings / meanings on: every word, also the ones without them, in a box of the same height, so the
            // characters of a line stay on one level)
            const annoOn = !!(prefs.subsRd || prefs.subsGl);
            const flush = () => {
                if (!plain) return;
                if (!annoOn) frag.appendChild(document.createTextNode(plain));
                else for (const t of plain.split(/(\s+)/)) {
                    if (!t) continue;
                    if (/^\s+$/.test(t)) frag.appendChild(document.createTextNode(t));
                    else subsAnnotate(frag, null, null).appendChild(document.createTextNode(t));
                }
                plain = "";
            };
            let i = 0;
            while (i < chars.length) {
                const cp = chars[i].codePointAt(0);
                if (!isHan(cp)) { plain += chars[i]; i++; continue; }
                const wordStart = i;
                const sh = files.get(`d-zh-${String(cp % (meta.shards || 256)).padStart(3, "0")}.json`);
                let cols = [], len = 1, entry = null;
                if (sh) for (let L = Math.min(meta.max || 12, chars.length - i); L >= 1; L--) {
                    const w = chars.slice(i, i + L).join("");
                    if (sh[w]) {
                        len = L; entry = sh[w][0];
                        cols = (zhParts(entry, meta).h || []).flatMap(sg => [...sg.t].map(() => sg.c || null));
                        break;
                    }
                }
                flush();
                // (the word: 認識 → as it is; 不熟 → a line under it; never seen → a dotted line)
                const word = chars.slice(wordStart, wordStart + len).join("");
                let box = frag;
                const known = isKnown(word);
                // (a word you don't know: its reading over it and its meaning under it)
                if (annoOn) box = subsAnnotate(frag, entry && !known ? entry : null, meta);
                if (knownSet) {
                    total++;
                    const k = known;
                    if (k) knownN++;
                    else {
                        const u = document.createElement("span");
                        u.className = learnSet.has(word) ? "learn" : "new";
                        box.appendChild(u);
                        box = u;
                    }
                }
                for (let j = 0; j < len; j++) {
                    const sp = document.createElement("span");
                    sp.className = "h";
                    // (只替不認識的詞上色: a word you know stays plain, without its glow)
                    if (cols[j] && prefs.colours && !(prefs.onlyNew && known)) sp.style.color = "#" + cols[j];
                    else if (prefs.onlyNew && known) sp.className = "";
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
        subsStudy();
        subsMeasure();
        subsPlace(false);
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
    function subsAnnotate(frag, e, meta) {
        const w = document.createElement("span"); w.className = e ? "w a" : "w";
        if (prefs.subsRd) {
            const rd = document.createElement("span"); rd.className = "rd ffx";
            if (!e) rd.textContent = "\u00a0";
            else (zhParts(e, meta).r || []).forEach((sg, i) => {
                const x = document.createElement("span");
                x.textContent = i && !sg.t.startsWith(" ") ? " " + sg.t : sg.t;
                if (sg.c && prefs.colours) x.style.color = "#" + sg.c;
                rd.appendChild(x);
            });
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
    /// its meaning in a few words: the first English sense when 英文 is on, else the start of the 中文 one
    function subsGloss(e) {
        const en = () => e.e ? e.e.split(";")[0].replace(/\([^)]*\)/g, "").trim() : "";
        const zh = () => {
            if (!e.m) return "";
            let m = e.m.replace(/^(\s*[〔［\[（(][^〕］\]）)]*[〕］\]）)])+/, "").split(/[。；]/)[0].trim();
            return [...m].length > 10 ? [...m].slice(0, 9).join("") + "…" : m;
        };
        return prefs.en ? (en() || zh()) : (zh() || en());
    }
    /// a character of the subtitles: the words from there on and its line (the sentence kept with a word)
    function subsCueAt(node, off) {
        const st = subs;
        if (!st || !node || !node.parentElement) return null;
        const line = node.parentElement.closest("#ff-subs .line");
        if (!line) return null;
        const tm = line.querySelector(".tm");
        const li = tm ? +tm.dataset.i : st.lines.indexOf(line);
        const cue = st.cues[li];
        if (!cue) return null;
        const h = node.parentElement.closest(".h[data-ci], [data-ci]");
        let text = "";
        if (h) {
            const chars = [...cue.t];
            for (let i = +h.dataset.ci.split(":")[1]; i < chars.length && [...text].length < MAXLEN; i++) {
                if (!isHan(chars[i].codePointAt(0))) break;
                text += chars[i];
            }
        }
        return { text, sentence: cue.t.replace(/\s+/g, " ").trim() };
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
        const t = v.currentTime;
        // (the last line that has started)
        let lo = 0, hi = st.cues.length - 1, at = -1;
        while (lo <= hi) { const m = (lo + hi) >> 1; if (st.cues[m].s <= t + 0.05) { at = m; lo = m + 1; } else hi = m - 1; }
        if (st.manualUntil && Date.now() > st.manualUntil) { st.manualUntil = 0; st.manual = 0; subsPlace(true); }
        if (st.slow && v.playbackRate !== 0.75) v.playbackRate = 0.75;
        // (the row at the bottom: moving all the time, at the pace of the lines)
        if (st.flow && !st.manualUntil) subsFlowAt(t, at);
        // 重複: back to the line's start when it's over
        if (st.loop >= 0 && st.cues[st.loop]) {
            const c = st.cues[st.loop], end = subsEnd(st.loop);
            if (t >= end + 0.12 || t < c.s - 1.5) { v.currentTime = c.s + 0.01; return; }
        }
        // 一句一停: the video waits at the end of each line (play goes on to the next)
        else if (st.pauseEach && at >= 0 && st.stopped !== at && !v.paused && t >= subsEnd(at) - 0.08) {
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
        if (!st.manualUntil) subsPlace(true);
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
            vv.currentTime = st.cues[i].s + 0.01; st.stopped = -1; st.manual = 0; st.manualUntil = 0;
            if (st.loop >= 0) st.loop = i;
            if (vv.paused) vv.play().catch(() => {});
        };
        b("上一句", false, "回到上一句", () => go(-1));
        b("重複", st.loop >= 0, "一直重複這一句", () => { st.loop = st.loop >= 0 ? -1 : Math.max(0, st.now); });
        b("慢速", !!st.slow, "放慢到 0.75 倍", () => { st.slow = !st.slow; const vv = v(); if (vv) vv.playbackRate = st.slow ? 0.75 : 1; });
        b("一句一停", !!st.pauseEach, "每一句說完影片就暫停，按播放再說下一句", () => { st.pauseEach = !st.pauseEach; st.stopped = Math.max(-1, st.now - 1); });
        b("下一句", false, "跳到下一句", () => go(1));
        // (over and under the words you don't know yet)
        b("讀音", !!prefs.subsRd, "不認識的詞上面標讀音", () => { prefs.subsRd = !prefs.subsRd; savePrefs(); subsRedraw(); });
        b("意思", !!prefs.subsGl, "不認識的詞下面標意思（英文或中文，跟著「英文」的設定）", () => { prefs.subsGl = !prefs.subsGl; savePrefs(); subsRedraw(); });
        // (how much of the video's words you know: 懂 87%)
        const m = document.createElement("span"); m.className = "meter";
        m.textContent = st.known != null ? "懂 " + st.known + "%" : "";
        m.title = "這部影片的字幕裡，你認識的詞佔多少";
        st.study.appendChild(m);
    }

    // where each line's middle is (the row at the bottom), measured once its words are drawn
    function subsMeasure() {
        const st = subs;
        st.centers = st.flow ? st.lines.map(l => l.offsetLeft + l.offsetWidth / 2) : [];
    }
    // the row at the bottom: the line being said reaches the middle as it starts, and moves on steadily until
    // the next one does (so the row flows evenly at the speed of the talking)
    function subsFlowAt(t, at) {
        const st = subs;
        if (!st.centers.length) subsMeasure();
        const c = st.centers;
        if (!c.length) return;
        let x;
        if (at < 0) {
            const first = st.cues[0];
            x = c[0] - Math.max(0, first.s - t) * 60;
        } else if (at >= c.length - 1) {
            x = c[c.length - 1];
        } else {
            const a = st.cues[at], b = st.cues[at + 1];
            const f = Math.min(1, Math.max(0, (t - a.s) / Math.max(0.3, b.s - a.s)));
            x = c[at] + (c[at + 1] - c[at]) * f;
        }
        const y = st.view.clientWidth / 2 - x + st.manual;
        st.rail.style.transform = `translateX(${y.toFixed(1)}px)`;
    }

    function subsPlace(glide) {
        const st = subs;
        if (!st.panel || !st.view || !st.lines.length) return;
        if (st.flow) {
            const v = subsVideo();
            if (st.manualUntil) {
                const c = st.centers.length ? st.centers : (subsMeasure(), st.centers);
                const i = Math.max(0, st.now);
                if (c[i] != null) st.rail.style.transform = `translateX(${(st.view.clientWidth / 2 - c[i] + st.manual).toFixed(1)}px)`;
            } else if (v) subsFlowAt(v.currentTime, st.now);
            return;
        }
        const h = st.view.clientHeight;
        const i = Math.max(0, st.now);
        const line = st.lines[i];
        if (!line) return;
        const y = h * 0.34 - (line.offsetTop + line.offsetHeight / 2) + st.manual;
        st.rail.style.transition = glide ? "" : "none";
        st.rail.style.transform = `translateY(${Math.round(y)}px)`;
        if (!glide) { void st.rail.offsetHeight; st.rail.style.transition = ""; }
    }
})();
