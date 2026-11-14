// 方方詞卡 查詞: what the settings page (options.html) and the toolbar window (popup.html) share: the settings'
// defaults, saving them, and sending the chosen words (and the minutes watched) to the app.
const FF_DEFAULTS = { on: true, zhPlace: 0, zhRom: 1, twRom: 1, twPlace: -1, colours: true, en: false, zh: true, tw: true,
    yue: true, hak: true, hakAcc: 0, hakRom: 0, sv: true, svGuess: true, en2zh: true, font: 1, ring: false, tint: false, pos: "word", w: 0, h: 0,
    subs: true, subsPause: true, subsHideVideo: true, subsFlow: false, subsFont: 1, subsRd: true, subsGl: true, subsRdSize: 0.56, subsLang: "auto", onlyNew: false,
    keys: true, keyKnown: "a", keyNew: "s" };
const FF_SIZES = [[0.85, "小"], [1, "中"], [1.15, "大"], [1.3, "更大"], [1.5, "很大"], [1.8, "特大"], [2.2, "超大"], [2.7, "最大"]];
const ffStore = browser.storage.local;

async function ffLoad() {
    const r = await ffStore.get(["ffPrefs", "ffQueue", "ffWatch", "ffKnown"]).catch(() => ({}));
    const prefs = { ...FF_DEFAULTS, ...(r.ffPrefs || {}) };
    if (prefs.corner === true && !(r.ffPrefs || {}).pos) prefs.pos = "tl";
    delete prefs.corner;
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
function ffSave(prefs) { return ffStore.set({ ffPrefs: prefs }).catch(() => {}); }

/// the words chosen (加到不熟 / 收藏) and the minutes watched with the subtitle panel, to the app
async function ffSend(queue, watch) {
    const pack = o => btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(o)))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const op = w => w === "saved" ? "s" : (w === "known" ? "k" : "u");
    const ops = queue.map(x => x.x ? [x.k, op(x.w), x.x] : [x.k, op(x.w)]);
    const url = "fangfangcards://safari?ops=" + pack(ops) + (Object.keys(watch || {}).length ? "&w=" + pack(watch) : "");
    try { await browser.tabs.update({ url }); } catch (e) { window.open(url); }
    await ffStore.set({ ffQueue: [], ffWatch: {} }).catch(() => {});
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
            const b = ffEl("button", t, String(prefs[key]) === String(v) ? "on" : "");
            b.addEventListener("click", () => { prefs[key] = v; ffSave(prefs); draw(); if (onChange) onChange(); });
            g.appendChild(b);
        }
    };
    draw();
    return g;
}
