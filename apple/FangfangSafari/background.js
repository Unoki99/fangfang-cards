// 方方詞卡 查詞: looks words up in the files inside the extension (d-*.json, made on the Mac by install.sh from the
// app's data). The page's script asks with the text from the character under the Pencil on; the answer is the longest
// 華語 word and the longest 台語 word it starts with, and the spelling tables for their readings.
// (Everything is inside the extension: no shared folder with the app is needed, so it also works when the app was
// installed with Sideloadly.)

const cache = new Map();
async function file(name) {
    if (cache.has(name)) return cache.get(name);
    let j = null;
    try {
        const r = await fetch(browser.runtime.getURL(name));
        if (r.ok) j = await r.json();
    } catch (e) { j = null; }
    cache.set(name, j);
    if (cache.size > 16) {
        for (const k of cache.keys()) { if (k !== "d-meta.json") { cache.delete(k); break; } }
    }
    return j;
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

browser.runtime.onMessage.addListener((msg) => {
    // a whole file, for the page's script to keep (it then looks words up by itself, at once)
    if (msg && msg.op === "file" && /^d-[a-z0-9-]+\.json$/.test(msg.name || "")) return file(msg.name).then(data => ({ ok: !!data, data }));
    if (msg && msg.op === "lookup") return lookup(msg.text || "", msg.show).catch(e => ({ ok: false, error: String(e) }));
    if (msg && msg.op === "places") return file("d-meta.json").then(m => ({ ok: true, places: (m && m.places) || [], ready: !!m }));
    return Promise.resolve({ ok: false });
});
