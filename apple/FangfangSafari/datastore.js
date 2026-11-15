// 方方詞卡 查詞: the lookup files installed in the browser (設定 → 詞典), kept in the add-on's own IndexedDB:
// "files" (d-*.json by name) and "parts" (each language: its files' names, and what d-meta.json and the English
// words need from it). The background page reads them (background.js), the install worker writes them.
"use strict";

globalThis.ffDB = (() => {
    let dbP = null;
    function open() {
        if (!dbP) dbP = new Promise((ok, fail) => {
            const r = indexedDB.open("fangfang-lookup", 1);
            r.onupgradeneeded = () => {
                const db = r.result;
                if (!db.objectStoreNames.contains("files")) db.createObjectStore("files");
                if (!db.objectStoreNames.contains("parts")) db.createObjectStore("parts");
            };
            r.onsuccess = () => ok(r.result);
            r.onerror = () => { dbP = null; fail(r.error); };
        });
        return dbP;
    }
    const done = t => new Promise((ok, fail) => { t.oncomplete = () => ok(); t.onerror = () => fail(t.error); t.onabort = () => fail(t.error); });
    const req = r => new Promise((ok, fail) => { r.onsuccess = () => ok(r.result); r.onerror = () => fail(r.error); });

    async function get(name) {
        const db = await open();
        return req(db.transaction("files").objectStore("files").get(name)).then(x => x === undefined ? null : x);
    }
    async function parts() {
        const db = await open();
        const st = db.transaction("parts").objectStore("parts");
        const [keys, vals] = await Promise.all([req(st.getAllKeys()), req(st.getAll())]);
        const out = {};
        keys.forEach((k, i) => { out[k] = vals[i]; });
        return out;
    }
    /// one language's files (in place of the ones it had); part: {en, meta, at}
    async function putLang(lang, files, part) {
        const db = await open();
        const old = await req(db.transaction("parts").objectStore("parts").get(lang));
        const t = db.transaction(["files", "parts"], "readwrite");
        const fs = t.objectStore("files");
        for (const n of (old && old.files) || []) if (!(n in files)) fs.delete(n);
        for (const [n, o] of Object.entries(files)) fs.put(o, n);
        t.objectStore("parts").put(Object.assign({}, part, { files: Object.keys(files) }), lang);
        await done(t);
    }
    async function removeLang(lang) {
        const db = await open();
        const old = await req(db.transaction("parts").objectStore("parts").get(lang));
        const t = db.transaction(["files", "parts"], "readwrite");
        for (const n of (old && old.files) || []) t.objectStore("files").delete(n);
        t.objectStore("parts").delete(lang);
        await done(t);
    }
    /// the files made from every language (d-meta.json, d-en-*.json), in place of the ones before; none at all
    /// (no language left): only taken away
    async function putMerged(files) {
        const db = await open();
        const t = db.transaction("files", "readwrite");
        const st = t.objectStore("files");
        const keys = await req(st.getAllKeys());
        for (const k of keys) if ((k === "d-meta.json" || /^d-en-\d+\.json$/.test(k)) && !(k in files)) st.delete(k);
        for (const [n, o] of Object.entries(files)) st.put(o, n);
        await done(t);
    }
    return { get, parts, putLang, removeLang, putMerged };
})();
