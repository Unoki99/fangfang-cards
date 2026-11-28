// 方方詞卡 查詞: what the settings page (options.html) and the toolbar window (popup.html) share: the settings'
// defaults, saving them, and sending the chosen words (and the minutes watched) to the app.
const FF_DEFAULTS = { pcLink: false, pageAnno: false, on: true, zhPlace: 0, zhRom: 1, twRom: 1, twPlace: -1, colours: true, en: false, zh: true, tw: false,
    yue: false, hak: false, hakAcc: 0, hakRom: 0, sv: false, svGuess: true, eng: false, engRom: 0, engEn: true, engZh: true, engSv: false, font: 1, ring: false, tint: false, pos: "word", w: 0, h: 0,
    subs: true, subsPause: true, subsHideVideo: true, subsFlow: false, subsFlowStyle: "scroll", subsSwell: false, subsSwapNext: true, subsOffset: 0, subsFlowH: 0, subs2: "", subsColours: true, subsBar: true, subsFont: 1, subsRd: true, subsGl: true, subsRdSize: 0.56, subsGlSize: 0.5, subsEnZh: true, subsLang: "auto", subsTrad: true, subsDefs: false, subsBg: "dark", subsMark: "new", subsRare: 3000, onlyNew: false,
    keys: true, keyKnown: "a", keyNew: "s", uiLang: "zh" };
const FF_SIZES = [[0.85, "小"], [1, "中"], [1.15, "大"], [1.3, "更大"], [1.5, "很大"], [1.8, "特大"], [2.2, "超大"], [2.7, "最大"]];
const ffStore = browser.storage.local;
/// 介面語言: the add-on's own words in 中文 or English (ui-en.js); set from the settings when they're loaded
let ffUILang = "zh";
function ffT(s) { return ffUILang === "en" && typeof FF_EN === "object" && Object.prototype.hasOwnProperty.call(FF_EN, s) ? FF_EN[s] : s; }

async function ffLoad() {
    const r = await ffStore.get(["ffPrefs", "ffQueue", "ffWatch", "ffKnown", "ffSeen"]).catch(() => ({}));
    const prefs = { ...FF_DEFAULTS, ...(r.ffPrefs || {}) };
    if (prefs.corner === true && !(r.ffPrefs || {}).pos) prefs.pos = "tl";
    delete prefs.corner;
    ffOneLang(prefs, FF_LANGS.find(l => (r.ffPrefs || {})[l]));
    ffUILang = prefs.uiLang === "en" ? "en" : "zh";
    document.documentElement.lang = ffUILang === "en" ? "en" : "zh-Hant";
    let places = [], ready = true;
    try { const p = await browser.runtime.sendMessage({ op: "places" }); if (p && p.ok) { places = p.places; ready = p.ready !== false; } } catch (e) {}
    return { prefs, queue: r.ffQueue || [], watch: r.ffWatch || {}, known: r.ffKnown || null, seen: r.ffSeen || {}, places, ready };
}
/// the words you know, as the app packs them (base64url of raw-deflated JSON) → stored for the add-on
async function ffTakeKnown(b64) {
    const b = b64.trim().replace(/^fangfang-known[:=]/, "").replace(/-/g, "+").replace(/_/g, "/");
    const bin = Uint8Array.from(atob(b + "===".slice((b.length + 3) % 4)), c => c.charCodeAt(0));
    const txt = await new Response(new Blob([bin]).stream().pipeThrough(new DecompressionStream("deflate-raw"))).text();
    const o = JSON.parse(txt);
    o.at = Date.now();
    await ffStore.set({ ffKnown: o });
    return o;
}
/// one language at a time (華語, 台語, 粵語, 客語, 瑞典語 or 英語): the first one on, or 華語; `pick`: that one
const FF_LANGS = ["zh", "tw", "yue", "hak", "sv", "eng"];
function ffOneLang(prefs, pick) {
    const on = pick || FF_LANGS.find(l => prefs[l]) || "zh";
    for (const l of FF_LANGS) prefs[l] = l === on;
    return on;
}
function ffSave(prefs) { return ffStore.set({ ffPrefs: prefs }).catch(() => {}); }

/// the words chosen (加到不熟 / 收藏) and the minutes watched with the subtitle panel, to the app
async function ffSend(queue, watch, seen) {
    const pack = o => btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(o)))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const op = w => w === "saved" ? "s" : (w === "known" ? "k" : (w === "group" ? "g" : "u"));
    // (影片詞組: each word's group as a fourth, the groups' names and addresses in gr)
    const groups = {};
    for (const x of queue) if (x.g) groups[x.g] = [x.gn || x.g, x.gu || ""];
    const ops = queue.map(ffOp(op));
    const url = ffAppURL("ops=" + pack(ops) + (Object.keys(watch || {}).length ? "&w=" + pack(watch) : "") +
        (Object.keys(groups).length ? "&gr=" + pack(groups) : "") +
        (seen && Object.keys(seen).length ? "&vk=" + pack(seen) : ""));
    try { await browser.tabs.update({ url }); } catch (e) { window.open(url); }
    await ffKeepMine(queue);
    await ffStore.set({ ffQueue: [], ffWatch: {}, ffSeen: {} }).catch(() => {});
    return url;
}

/// a word for the app's link: [key, what, the sentence, its 影片詞組, the sentence in the second language (a
/// subtitle line's English, say)], as short as it can be
function ffOp(op) {
    return x => {
        const tr = x.x ? (x.tr || "") : "";
        if (tr) return [x.k, op(x.w), x.x || "", x.g || "", tr];
        return x.g ? [x.k, op(x.w), x.x || "", x.g] : (x.x ? [x.k, op(x.w), x.x] : [x.k, op(x.w)]);
    };
}

/// the app's link: fangfangcards://safari?… (iPhone, iPad, Mac); on Android (Firefox) the same as an intent:// link,
/// the way Android browsers hand a link to an app
function ffAppURL(query) {
    return /Android/i.test(navigator.userAgent)
        ? "intent://safari?" + query + "#Intent;scheme=fangfangcards;end"
        : "fangfangcards://safari?" + query;
}

function ffEl(tag, text, cls) {
    const e = document.createElement(tag);
    if (text != null) e.textContent = text;
    if (cls) e.className = cls;
    return e;
}

/// a switch (role="switch") bound to prefs[key]
function ffSwitch(prefs, key, onChange) {
    const sw = ffEl("button", null, "switch");
    sw.setAttribute("role", "switch");
    const set = () => { sw.classList.toggle("on", !!prefs[key]); sw.setAttribute("aria-checked", prefs[key] ? "true" : "false"); };
    set();
    sw.addEventListener("click", () => { prefs[key] = !prefs[key]; ffSave(prefs); set(); if (onChange) onChange(); });
    return sw;
}

/// a row of choices (like the app's segmented pickers) bound to prefs[key]
function ffChoice(prefs, key, options, onChange) {
    const g = ffEl("div", null, "seg");
    const draw = () => {
        g.replaceChildren();
        for (const [v, t] of options) {
            const b = ffEl("button", ffT(t), String(prefs[key]) === String(v) ? "on" : "");
            b.addEventListener("click", () => { prefs[key] = v; ffSave(prefs); draw(); if (onChange) onChange(); });
            g.appendChild(b);
        }
    };
    draw();
    return g;
}

/// which language an app key is of: after the tab 粵 / 客 / 日 / 瑞, 注音 (華語), or letters (台語) (as content.js)
function ffKeyLang(k) {
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

/// every word marked in this add-on (認識, 不熟, 收藏), with when, kept for its file in the sync folder also after
/// the words have gone to the app (ffMine: s key → [1 認識 / 2 不熟, seconds], v key → seconds 收藏)
async function ffKeepMine(queue) {
    const r = await ffStore.get(["ffMine"]).catch(() => ({}));
    const m = r.ffMine || { s: {}, v: {} };
    // (and each word's sentences, the newest 5; a subtitle line's second-language line and its video, by sentence)
    m.f = m.f || {}; m.fi = m.fi || {}; m.gi = m.gi || {};
    for (const x of queue || []) {
        const t = (x.t || Date.now()) / 1000;
        const sx = (x.x || "").trim();
        if (sx && x.w !== "known" && x.w !== "group") {
            const l = (m.f[x.k] || []).filter(y => y !== sx);
            l.push(sx);
            m.f[x.k] = l.slice(-5);
            if (x.tr || x.g) m.fi[sx] = [x.tr || "", x.g || ""];
            if (x.g) m.gi[x.g] = [x.gn || x.g, x.gu || "", ""];
        }
        if (x.w === "known" || x.w === "unknown") { if (!m.s[x.k] || m.s[x.k][1] <= t) m.s[x.k] = [x.w === "known" ? 1 : 2, t]; }
        else if (x.w === "saved") { if (!(m.v[x.k] >= t)) m.v[x.k] = t; }
    }
    // (the lines of sentences no longer kept: let go)
    const kept = new Set(Object.values(m.f).flat());
    for (const sx of Object.keys(m.fi)) if (!kept.has(sx)) delete m.fi[sx];
    await ffStore.set({ ffMine: m }).catch(() => {});
    return m;
}

/// 資料夾同步: every device's backup in the folder (方方詞卡-*.json, the app's iPhone / iPad / Android / Windows ones
/// and this add-on's), each word as it was changed last → the words you know and are learning, kept here as if the
/// app had sent them. → how many of each
async function ffReadFolder(files) {
    const best = new Map();       // key → [status, time]
    let read = 0;
    for (const f of files) {
        if (!/^方方詞卡-.*\.json$/.test(f.name) || /舊備份/.test(f.webkitRelativePath || "")) continue;
        let o;
        try { o = JSON.parse(await f.text()); } catch (e) { continue; }
        if (!o || o.app !== "fangfang-cards" || !o.status) continue;
        read++;
        const added = o.added || {};
        for (const [k, st] of Object.entries(o.status)) {
            const t = added[k] || 0, b = best.get(k);
            if (!b || t > b[1]) best.set(k, [st, t]);
        }
    }
    // (and the words marked here, by when, the newest winning)
    const mine = await ffKeepMine((await ffStore.get(["ffQueue"]).catch(() => ({}))).ffQueue || []);
    for (const [key, [st, t]] of Object.entries(mine.s)) {
        const b = best.get(key);
        if (!b || t > b[1]) best.set(key, [st, t]);
    }
    const k = {}, u = {};
    for (const [key, [st]] of best) {
        if (st !== 1 && st !== 2) continue;
        const head = key.split("\t")[0];
        if (!head) continue;
        const l = ffKeyLang(key), to = st === 1 ? k : u;
        (to[l] = to[l] || new Set()).add(head);
    }
    const arr = m => Object.fromEntries(Object.entries(m).map(([l, s]) => [l, [...s]]));
    const r = await ffStore.get(["ffKnown"]).catch(() => ({}));
    const o = { v: 1, k: arr(k), u: arr(u), f: (r.ffKnown && r.ffKnown.f) || [], at: Date.now(), from: "folder" };
    await ffStore.set({ ffKnown: o });
    const n = x => Object.values(x).reduce((a, s) => a + s.size, 0);
    return { files: read, known: n(k), unknown: n(u) };
}

/// this add-on's own file for the folder: the words chosen here (認識, 不熟, 收藏), in the app's backup form, so
/// the apps take them when they sync. Saved as a download: choose the sync folder when the browser asks.
async function ffFolderFile(queue, dir) {
    const f = await ffFolderBuild(queue);
    if (dir) {
        // (straight into the folder, in place of the one before)
        const w = await (await dir.getFileHandle(f.name, { create: true })).createWritable();
        await w.write(f.text); await w.close();
        return f;
    }
    const url = URL.createObjectURL(new Blob([f.text], { type: "application/json" }));
    const a = document.createElement("a");
    a.href = url; a.download = f.name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
    return f;
}

/// iPhone / iPad: Safari doesn't download a file made in the add-on's page, so it goes through the share sheet
/// (儲存到「檔案」 → the backup folder; one of the same name is replaced). Called straight from a tap, with the file
/// made beforehand (ffFolderBuild): the share sheet opens only from a tap.
const ffIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
function ffShareFile(f) {
    const file = new File([f.text], f.name, { type: "application/json" });
    return navigator.share({ files: [file] }).then(() => true, e => (e && e.name === "AbortError") ? false : Promise.reject(e));
}

/// this add-on's file for the folder: { name, text, n words }
async function ffFolderBuild(queue) {
    const r = await ffStore.get(["ffDeviceId"]).catch(() => ({}));
    let id = r.ffDeviceId;
    if (!id) { id = Math.random().toString(16).slice(2, 6).toUpperCase(); await ffStore.set({ ffDeviceId: id }).catch(() => {}); }
    const now = Date.now() / 1000;
    // (every word marked here, also the ones sent to the app already: each device's file has all of its own. The
    // words waiting are read now, not taken from the page: one marked on a video after this page was opened counts)
    const fresh = (await ffStore.get(["ffQueue"]).catch(() => ({}))).ffQueue || queue || [];
    const mine = await ffKeepMine(fresh);
    const status = {}, added = {}, saved = Object.assign({}, mine.v);
    for (const [key, [st, t]] of Object.entries(mine.s)) { status[key] = st; added[key] = t; }
    const browserName = /Firefox/i.test(navigator.userAgent) ? "Firefox" : (/Edg\//.test(navigator.userAgent) ? "Edge" : (/Chrome/i.test(navigator.userAgent) ? "Chrome" : "Safari"));
    // (each video's 懂 % as it was last, and its name)
    const all = (await ffStore.get(["ffSeenAll"]).catch(() => ({}))).ffSeenAll || {};
    const seen = {}, groupInfo = {};
    for (const [id, [name, u, pct, t]] of Object.entries(all)) { seen[id] = [pct, t]; groupInfo[id] = [name, u, ""]; }
    for (const [id, i] of Object.entries(mine.gi || {})) if (!groupInfo[id]) groupInfo[id] = i;
    // (the sentences the words were saved from, kept used by the fi entries of sentences still kept)
    const found = mine.f || {}, foundInfo = {};
    const keptS = new Set(Object.values(found).flat());
    for (const [s, i] of Object.entries(mine.fi || {})) if (keptS.has(s)) foundInfo[s] = i;
    const obj = { app: "fangfang-cards", version: 1, exported: new Date().toISOString(), from: "add-on", status, added, saved,
        streak: {}, own: {}, ownInfo: {}, senses: {}, week: {}, weekStart: {}, srs: {}, log: {}, groupTime: {}, groupInfo, groupWords: {}, seen, found, foundInfo };
    const name = "方方詞卡-查詞-" + browserName + "-" + id + ".json";
    const text = JSON.stringify(obj, null, 1);
    const n = Object.keys(status).length + Object.keys(saved).length;
    return { name, text, n, now };
}

/// 立刻同步 where the browser can keep a folder (Chrome, Edge on a computer): the folder chosen once (again with
/// pick), then each time: every device's backup read (ffReadFolder) and this add-on's file written into it.
/// → {files, known, unknown, name, n}; null: no folder chosen
async function ffSyncFolder(queue, pick) {
    const db = await new Promise((ok, fail) => {
        const r = indexedDB.open("fangfang-sync", 1);
        r.onupgradeneeded = () => r.result.createObjectStore("h");
        r.onsuccess = () => ok(r.result); r.onerror = () => fail(r.error);
    });
    const io = (mode, f) => new Promise((ok, fail) => {
        const t = db.transaction("h", mode), q = f(t.objectStore("h"));
        q.onsuccess = () => ok(q.result); q.onerror = () => fail(q.error);
    });
    let dir = pick ? null : await io("readonly", st => st.get("dir")).catch(() => null);
    if (!dir) {
        dir = await window.showDirectoryPicker({ id: "fangfang", mode: "readwrite" }).catch(() => null);
        if (!dir) return null;
        await io("readwrite", st => st.put(dir, "dir")).catch(() => {});
    }
    if ((await dir.queryPermission({ mode: "readwrite" })) !== "granted" &&
        (await dir.requestPermission({ mode: "readwrite" })) !== "granted") return null;
    const files = [];
    for await (const [name, h] of dir.entries()) if (h.kind === "file" && /^方方詞卡-.*\.json$/.test(name)) files.push(await h.getFile());
    const r = await ffReadFolder(files);
    const w = await ffFolderFile(queue, dir);
    return Object.assign(r, { name: w.name, n: w.n, folder: dir.name });
}

/// 資料夾同步's buttons, for the settings page and the toolbar window: 立刻同步 (and 換資料夾) in sb, 讀資料夾 and
/// 把這裡選的詞存到資料夾 in fb, what happened in said
async function ffSyncControls(d, colour, saidClass) {
    const el = ffEl;
    // (Safari: no picking a whole folder, so its files: 選擇 → 全選 in 檔案)
    const safari = !(await fetch(browser.runtime.getURL("install/common.js")).then(r => r.ok, () => false));
    const pick = el("input");
    pick.type = "file"; pick.multiple = true; pick.style.display = "none";
    if (safari) pick.accept = ".json,application/json"; else pick.webkitdirectory = true;
    const fb = el("div", null, "btns");
    const readB = el("button", ffT("讀資料夾"), "act main");
    readB.style.setProperty("--c", colour);
    const saveB = el("button", ffT("把這裡選的詞存到資料夾"), "act");
    const said = el("p", "", saidClass);
    readB.addEventListener("click", () => pick.click());
    pick.addEventListener("change", async () => {
        said.textContent = ffT("讀取中…");
        try {
            const r = await ffReadFolder([...pick.files]);
            said.textContent = r.files ? ffT("讀了 ") + r.files + ffT(" 個裝置的備份：認識的詞 ") + r.known + ffT(" 個、不熟的詞 ") + r.unknown + ffT(" 個。")
                : ffT("這個資料夾裡沒有方方詞卡的備份（方方詞卡-….json）。");
            // (立刻同步 without a folder the browser keeps: now this add-on's file, saved where you choose; on an
            // iPhone / iPad with one more tap, for the share sheet)
            if (syncAfterRead && ffIOS) {
                ready = await ffFolderBuild(d.queue);
                saving = true;
                syncB.textContent = ffT("存回資料夾");
                said.textContent += ffT("再按「存回資料夾」→「儲存到檔案」→ 選備份資料夾 →「儲存」（問的時候按「取代」）。");
            } else if (syncAfterRead) {
                const w = await ffFolderFile(d.queue);
                said.textContent += ffT("存了 ") + w.n + ffT(" 個詞：") + w.name;
            }
        } catch (e) { said.textContent = ffT("讀不到這個資料夾。"); }
        syncAfterRead = false;
        pick.value = "";
    });
    // (iPhone / iPad: the file made beforehand, so the tap opens the share sheet straight away)
    let ready = null, saving = false;
    // (made again whenever words are marked in another tab, and when this page is shown again)
    const remake = () => { if (ffIOS) ffFolderBuild(d.queue).then(f => { ready = f; }, () => {}); };
    remake();
    if (browser.storage && browser.storage.onChanged) browser.storage.onChanged.addListener(ch => {
        if (ch.ffQueue || ch.ffSeenAll) remake();      // (not ffMine: making the file writes it)
    });
    document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") remake(); });
    const shareNow = () => {
        if (!ready) { said.textContent = ffT("還在準備檔案，再按一次。"); return; }
        const f = ready;
        ffShareFile(f).then(ok => {
            said.textContent = ok ? ffT("存了 ") + f.n + ffT(" 個詞：") + f.name : ffT("沒有存。");
        }, () => { said.textContent = ffT("這個瀏覽器沒辦法存檔案。"); });
        ffFolderBuild(d.queue).then(x => { ready = x; }, () => {});
    };
    saveB.addEventListener("click", async () => {
        if (ffIOS) return shareNow();
        const r = await ffFolderFile(d.queue);
        said.textContent = ffT("存了 ") + r.n + ffT(" 個詞：") + r.name;
    });
    fb.append(readB, saveB);
    // 立刻同步: both ways in one go: every device's file read and merged (each word as it was changed last), then this
    // add-on's own file written beside them. Chrome / Edge on a computer: straight with the folder (chosen once).
    // Elsewhere (Safari, Firefox): its files picked, and this add-on's file saved as a download (into that folder:
    // the browser's download place set to it).
    const direct = !safari && typeof window.showDirectoryPicker === "function";
    const sb = el("div", null, "btns");
    const syncB = el("button", ffT("立刻同步"), "act main");
    syncB.style.setProperty("--c", colour);
    let syncAfterRead = false;
    const syncDirect = async pickNew => {
        said.textContent = ffT("同步中…");
        try {
            const r = await ffSyncFolder(d.queue, pickNew);
            said.textContent = !r ? ffT("沒有選資料夾，或瀏覽器不讓讀寫。")
                : ffT("同步了「") + r.folder + ffT("」：讀了 ") + r.files + ffT(" 個裝置的備份（認識的詞 ") + r.known + ffT(" 個、不熟的詞 ") + r.unknown + ffT(" 個），存了這裡選的 ") + r.n + ffT(" 個詞。");
        } catch (e) { said.textContent = ffT("同步失敗：讀不到或寫不進這個資料夾。"); }
    };
    syncB.addEventListener("click", async () => {
        if (direct) return syncDirect(false);
        if (saving) { saving = false; syncB.textContent = ffT("立刻同步"); return shareNow(); }
        syncAfterRead = true;
        pick.click();
    });
    sb.append(syncB, pick);
    if (direct) {
        const other = el("button", ffT("換資料夾"), "act");
        other.addEventListener("click", () => syncDirect(true));
        sb.appendChild(other);
    }
    return { safari, direct, sb, fb, said };
}

/// Safari (the add-on inside the app, its words made on the Mac) rather than Firefox (which installs its dictionaries
/// itself, with the converters in install/). 資料夾同步 is Safari's only
async function ffIsSafari() {
    return !(await fetch(browser.runtime.getURL("install/common.js")).then(r => r.ok, () => false));
}
