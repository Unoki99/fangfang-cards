// 方方詞卡 查詞: what the settings page (options.html) and the toolbar window (popup.html) share: the settings'
// defaults, saving them, and sending the chosen words (and the minutes watched) to the app.
const FF_DEFAULTS = { on: true, zhPlace: 0, zhRom: 1, twRom: 1, twPlace: -1, colours: true, en: false, zh: true, tw: false,
    yue: false, hak: false, hakAcc: 0, hakRom: 0, sv: false, svGuess: true, en2zh: true, font: 1, ring: false, tint: false, pos: "word", w: 0, h: 0,
    subs: true, subsPause: true, subsHideVideo: true, subsFlow: false, subsFlowH: 0, subs2: "", subsColours: true, subsBar: true, subsFont: 1, subsRd: true, subsGl: true, subsRdSize: 0.56, subsGlSize: 0.5, subsEnZh: true, subsLang: "auto", subsTrad: true, subsDefs: false, subsBg: "dark", subsMark: "new", subsRare: 3000, onlyNew: false,
    keys: true, keyKnown: "a", keyNew: "s", uiLang: "zh" };
const FF_SIZES = [[0.85, "小"], [1, "中"], [1.15, "大"], [1.3, "更大"], [1.5, "很大"], [1.8, "特大"], [2.2, "超大"], [2.7, "最大"]];
const ffStore = browser.storage.local;
/// 介面語言: the add-on's own words in 中文 or English (ui-en.js); set from the settings when they're loaded
let ffUILang = "zh";
function ffT(s) { return ffUILang === "en" && typeof FF_EN === "object" && Object.prototype.hasOwnProperty.call(FF_EN, s) ? FF_EN[s] : s; }

async function ffLoad() {
    const r = await ffStore.get(["ffPrefs", "ffQueue", "ffWatch", "ffKnown"]).catch(() => ({}));
    const prefs = { ...FF_DEFAULTS, ...(r.ffPrefs || {}) };
    if (prefs.corner === true && !(r.ffPrefs || {}).pos) prefs.pos = "tl";
    delete prefs.corner;
    ffOneLang(prefs, FF_LANGS.find(l => (r.ffPrefs || {})[l]));
    ffUILang = prefs.uiLang === "en" ? "en" : "zh";
    document.documentElement.lang = ffUILang === "en" ? "en" : "zh-Hant";
    let places = [], ready = true;
    try { const p = await browser.runtime.sendMessage({ op: "places" }); if (p && p.ok) { places = p.places; ready = p.ready !== false; } } catch (e) {}
    return { prefs, queue: r.ffQueue || [], watch: r.ffWatch || {}, known: r.ffKnown || null, places, ready };
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
/// one language at a time (華語, 台語, 粵語, 客語 or 瑞典語): the first one on, or 華語; `pick`: that one
const FF_LANGS = ["zh", "tw", "yue", "hak", "sv"];
function ffOneLang(prefs, pick) {
    const on = pick || FF_LANGS.find(l => prefs[l]) || "zh";
    for (const l of FF_LANGS) prefs[l] = l === on;
    return on;
}
function ffSave(prefs) { return ffStore.set({ ffPrefs: prefs }).catch(() => {}); }

/// the words chosen (加到不熟 / 收藏) and the minutes watched with the subtitle panel, to the app
async function ffSend(queue, watch) {
    const pack = o => btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(o)))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const op = w => w === "saved" ? "s" : (w === "known" ? "k" : (w === "group" ? "g" : "u"));
    // (影片詞組: each word's group as a fourth, the groups' names and addresses in gr)
    const groups = {};
    for (const x of queue) if (x.g) groups[x.g] = [x.gn || x.g, x.gu || ""];
    const ops = queue.map(x => x.g ? [x.k, op(x.w), x.x || "", x.g] : (x.x ? [x.k, op(x.w), x.x] : [x.k, op(x.w)]));
    const url = ffAppURL("ops=" + pack(ops) + (Object.keys(watch || {}).length ? "&w=" + pack(watch) : "") +
        (Object.keys(groups).length ? "&gr=" + pack(groups) : ""));
    try { await browser.tabs.update({ url }); } catch (e) { window.open(url); }
    await ffStore.set({ ffQueue: [], ffWatch: {} }).catch(() => {});
    return url;
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
    if ((cp >= 0x3100 && cp <= 0x312F) || (cp >= 0x31A0 && cp <= 0x31BF) || c === "˙" || c === "字") return "zh";
    return "tw";
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
async function ffFolderFile(queue) {
    const r = await ffStore.get(["ffDeviceId"]).catch(() => ({}));
    let id = r.ffDeviceId;
    if (!id) { id = Math.random().toString(16).slice(2, 6).toUpperCase(); await ffStore.set({ ffDeviceId: id }).catch(() => {}); }
    const now = Date.now() / 1000;
    const status = {}, added = {}, saved = {};
    for (const x of queue || []) {
        const t = (x.t || Date.now()) / 1000;
        if (x.w === "known" || x.w === "unknown") { status[x.k] = x.w === "known" ? 1 : 2; added[x.k] = t; }
        else if (x.w === "saved") saved[x.k] = t;
    }
    const browserName = /Firefox/i.test(navigator.userAgent) ? "Firefox" : (/Edg\//.test(navigator.userAgent) ? "Edge" : (/Chrome/i.test(navigator.userAgent) ? "Chrome" : "Safari"));
    const obj = { app: "fangfang-cards", version: 1, exported: new Date().toISOString(), from: "add-on", status, added, saved,
        streak: {}, own: {}, ownInfo: {}, senses: {}, week: {}, weekStart: {}, srs: {}, log: {}, groupTime: {}, groupInfo: {}, groupWords: {} };
    const name = "方方詞卡-查詞-" + browserName + "-" + id + ".json";
    const url = URL.createObjectURL(new Blob([JSON.stringify(obj, null, 1)], { type: "application/json" }));
    const a = document.createElement("a");
    a.href = url; a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
    return { name, n: Object.keys(status).length + Object.keys(saved).length, now };
}
