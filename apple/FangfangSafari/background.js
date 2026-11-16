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
    const p = (async () => {
        let j = null;
        try { j = await ffDB.get(name); } catch (e) { j = null; }
        if (j === null || j === undefined) {
            try {
                const r = await fetch(browser.runtime.getURL(name));
                if (r.ok) j = await r.json();
            } catch (e) { j = null; }
        }
        return j === undefined ? null : j;
    })();
    cache.set(name, p);
    if (cache.size > 96) {
        for (const k of cache.keys()) { if (k !== "d-meta.json") { cache.delete(k); break; } }
    }
    return p;
}
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

// (a dictionary installed or taken away in 設定 → 詞典: read the files again)
browser.runtime.onMessage.addListener((msg) => {
    if (msg && msg.op === "dataChanged") { cache.clear(); return Promise.resolve({ ok: true }); }
    if (msg && msg.op === "options") {
        return browser.tabs.create({ url: browser.runtime.getURL("options.html#dicts") })
            .catch(() => browser.runtime.openOptionsPage()).then(() => ({ ok: true }), () => ({ ok: false }));
    }
    // a whole file, for the page's script to keep (it then looks words up by itself, at once)
    if (msg && msg.op === "file" && /^d-[a-z0-9-]+\.json$/.test(msg.name || "")) return file(msg.name).then(data => ({ ok: !!data, data }));
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
