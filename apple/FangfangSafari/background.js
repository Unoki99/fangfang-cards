// 方方詞卡 查詞: looks words up in the lookup files (d-*.json): the ones installed in the browser (設定 → 詞典,
// kept by datastore.js), else the ones inside the extension (made on the Mac by install.sh from the app's data). The page's script asks with the text from the character under the Pencil on; the answer is the longest
// 華語 word and the longest 台語 word it starts with, and the spelling tables for their readings.
// (Everything is inside the extension: no shared folder with the app is needed, so it also works when the app was
// installed with Sideloadly.)

// (the files read, kept here: a page asks for the words it needs, not the whole files, since sending a whole file to
// the page each time is slow in Firefox; the newest 96 files are kept, the meta file always)
const cache = new Map();
function file(name) {
    if (cache.has(name)) {
        const p = cache.get(name);
        cache.delete(name); cache.set(name, p);          // (most recently used last)
        return p;
    }
    const p = load(name);
    cache.set(name, p);
    if (cache.size > 96) {
        for (const k of cache.keys()) { if (k !== "d-meta.json") { cache.delete(k); break; } }
    }
    return p;
}
async function load(name) {
    let j = null;
    try { j = await ffDB.get(name); } catch (e) { j = null; }
    if (j === null || j === undefined) {
        try {
            const r = await fetch(browser.runtime.getURL(name));
            if (r.ok) j = await r.json();
        } catch (e) { j = null; }
    }
    return j === undefined ? null : j;
}
// (a file read once for a job and let go, unless it's kept already: 網頁上不認識的詞 reads many at a time, and an
// add-on that keeps too much in memory is slow, or stopped by the browser)
const once = name => cache.has(name) ? file(name) : load(name);
const shardOf = (lang, cp, meta) => `d-${lang}-${String(cp % ((meta && meta.shards) || 256)).padStart(3, "0")}.json`;

/// the longest word each language has at the start of the text (only those words go back to the page)
async function findWords(text, langs) {
    const meta = await file("d-meta.json");
    if (!meta) return { ok: true, ready: false };
    const chars = [...text].slice(0, meta.max || 12);
    const out = { ok: true, ready: true };
    if (!chars.length) return out;
    const cp = chars[0].codePointAt(0);
    await Promise.all((langs || []).filter(l => /^[a-z]+$/.test(l)).map(async lang => {
        const sh = await file(shardOf(lang, cp, meta));
        if (!sh) return;
        for (let n = chars.length; n >= 1; n--) {
            const w = chars.slice(0, n).join("");
            if (sh[w]) { out[lang] = { w, list: sh[w] }; break; }
        }
    }));
    return out;
}

async function lookup(text, show) {
    const meta = await file("d-meta.json");
    if (!meta) return { ok: true, ready: false };
    const chars = [...text].slice(0, meta.max || 12);
    if (!chars.length) return { ok: true, ready: true };
    const i = String((chars[0].codePointAt(0) % (meta.shards || 256))).padStart(3, "0");
    const out = { ok: true, ready: true };
    const tab = { py: {}, syl: {}, tl: {}, pj: {} };
    for (const lang of ["zh", "tw"]) {
        if (show && show[lang] === false) continue;
        const sh = await file(`d-${lang}-${i}.json`);
        if (!sh) continue;
        for (let n = chars.length; n >= 1; n--) {
            const w = chars.slice(0, n).join("");
            if (sh[w]) { out[lang] = { w, list: sh[w] }; break; }
        }
    }
    // the spelling tables, only for the syllables in the answer
    for (const e of (out.zh ? out.zh.list : [])) {
        for (const s of [...(e.t || "").split(" "), ...(e.l || "").split(" ")]) if (s && meta.py[s]) tab.py[s] = meta.py[s];
    }
    for (const e of (out.tw ? out.tw.list : [])) {
        const all = [e.c, ...Object.values(e.d || {})].join(" ").split(" ");
        for (const c of all) {
            if (!c) continue;
            if (meta.syl && meta.syl[c]) tab.syl[c] = meta.syl[c];
            if (meta.tl && meta.tl[c]) tab.tl[c] = meta.tl[c];
            if (meta.pj && meta.pj[c]) tab.pj[c] = meta.pj[c];
        }
    }
    out.tab = tab;
    return out;
}

// 連到方方詞卡（Windows）: the song playing on YouTube (which, where in it) to the 方方詞卡 program on this computer,
// for its 歌詞 screen; its answer: what to do with the song (jump, pause, play, speed). Only to 127.0.0.1 (this
// computer, nothing over the internet), only when the setting is on and Firefox was allowed to (optional permission).
const PC_PORT = 47291;
async function pcSend(now) {
    try {
        const ctl = new AbortController();
        const timer = setTimeout(() => ctl.abort(), 800);
        const r = await fetch(`http://127.0.0.1:${PC_PORT}/now`, {
            method: "POST", body: JSON.stringify(now), signal: ctl.signal, headers: { "Content-Type": "text/plain" } });
        clearTimeout(timer);
        if (!r.ok) return { ok: false };
        const j = await r.json();
        return { ok: true, cmds: Array.isArray(j.cmds) ? j.cmds : [] };
    } catch (e) { return { ok: false }; }
}

const isHanBg = cp => (cp >= 0x3400 && cp <= 0x9fff) || (cp >= 0xf900 && cp <= 0xfaff) || (cp >= 0x20000 && cp <= 0x3ffff);
/// 網頁上不認識的詞: the page's texts cut into the words the dictionary has (longest first, from the left), each with
/// its entries; only those go back to the page, not the dictionary's files (sending a page full of files to the page
/// was too slow in Firefox, and nothing was marked). Each file is read once, for all the places that need it.
async function segment(texts, lang) {
    const meta = await file("d-meta.json");
    if (!meta) return { ok: true, ready: false };
    if (!/^[a-z]+$/.test(lang)) return { ok: false };
    const max = meta.max || 12;
    const T = (texts || []).slice(0, 400).map(t => [...String(t || "")].slice(0, 4000));
    const byShard = new Map();
    T.forEach((chars, ti) => chars.forEach((ch, i) => {
        const cp = ch.codePointAt(0);
        if (!isHanBg(cp)) return;
        const nm = shardOf(lang, cp, meta);
        if (!byShard.has(nm)) byShard.set(nm, []);
        byShard.get(nm).push([ti, i]);
    }));
    const best = T.map(() => new Map());
    for (const [nm, spots] of byShard) {
        const sh = await once(nm);
        if (!sh) continue;
        for (const [ti, i] of spots) {
            const chars = T[ti];
            for (let k = Math.min(max, chars.length - i); k >= 1; k--) {
                const w = chars.slice(i, i + k).join("");
                if (Object.prototype.hasOwnProperty.call(sh, w)) { best[ti].set(i, [k, sh[w]]); break; }
            }
        }
    }
    const data = T.map((chars, ti) => {
        const f = [];
        let i = 0;
        while (i < chars.length) { const b = best[ti].get(i); if (b) { f.push([i, b[0], b[1]]); i += b[0]; } else i++; }
        return f;
    });
    return { ok: true, ready: true, data };
}

// (a dictionary installed or taken away in 設定 → 詞典: read the files again)
browser.runtime.onMessage.addListener((msg) => {
    if (msg && msg.op === "pcNow" && msg.now) return pcSend(msg.now);
    if (msg && msg.op === "dataChanged") { cache.clear(); return Promise.resolve({ ok: true }); }
    if (msg && msg.op === "options") {
        return browser.tabs.create({ url: browser.runtime.getURL("options.html#dicts") })
            .catch(() => browser.runtime.openOptionsPage()).then(() => ({ ok: true }), () => ({ ok: false }));
    }
    // a whole file, for the page's script to keep (it then looks words up by itself, at once)
    if (msg && msg.op === "file" && /^d-[a-z0-9-]+\.json$/.test(msg.name || "")) return file(msg.name).then(data => ({ ok: !!data, data }));
    if (msg && msg.op === "segment") return segment(msg.texts, String(msg.lang || "")).catch(e => ({ ok: false, error: String(e) }));
    if (msg && msg.op === "find") return findWords(String(msg.text || ""), msg.langs).catch(e => ({ ok: false, error: String(e) }));
    // one entry of a file (the words of one key)
    if (msg && msg.op === "entry" && /^d-[a-z0-9-]+\.json$/.test(msg.name || "")) {
        return file(msg.name).then(sh => ({ ok: !!sh, data: (sh && Object.prototype.hasOwnProperty.call(sh, msg.key) && sh[msg.key]) || null }));
    }
    // (read ahead into the cache here, nothing sent back)
    if (msg && msg.op === "warm") {
        return file("d-meta.json").then(meta => {
            if (meta) for (const l of (msg.langs || [])) if (/^[a-z]+$/.test(l)) file(shardOf(l, msg.cp | 0, meta));
            return { ok: true };
        });
    }
    if (msg && msg.op === "lookup") return lookup(msg.text || "", msg.show).catch(e => ({ ok: false, error: String(e) }));
    if (msg && msg.op === "places") return file("d-meta.json").then(m => ({ ok: true, places: (m && m.places) || [], ready: !!m }));
    return Promise.resolve({ ok: false });
});

// (just installed, and no dictionary yet: the settings page, where they're installed)
if (browser.runtime.onInstalled) browser.runtime.onInstalled.addListener(async d => {
    if (!d || d.reason !== "install") return;
    if (await file("d-meta.json")) return;
    try { await browser.tabs.create({ url: browser.runtime.getURL("options.html#dicts") }); } catch (e) {}
});
