// 方方詞卡 查詞: the window from the extension's button in Safari's toolbar. The switch turns the pop-up on and off;
// when it's on, its settings (the same as the card's 設定: one column per language, then the rest) and the words
// chosen to send to the app.
const DEFAULTS = { on: true, zhPlace: 0, zhRom: 1, twRom: 1, twPlace: -1, colours: true, en: false, zh: true, tw: true,
    yue: true, hak: true, hakAcc: 0, hakRom: 0, sv: true, svGuess: true, en2zh: true, font: 1, ring: false, tint: false, pos: "word", w: 0, h: 0,
    subs: true, subsPause: true, subsHideVideo: true, subsFlow: false };
const store = browser.storage.local;

function el(tag, text, cls) { const e = document.createElement(tag); if (text != null) e.textContent = text; if (cls) e.className = cls; return e; }

async function main() {
    const r = await store.get(["ffPrefs", "ffQueue"]).catch(() => ({}));
    const prefs = { ...DEFAULTS, ...(r.ffPrefs || {}) };
    if (prefs.corner === true && !(r.ffPrefs || {}).pos) prefs.pos = "tl";
    delete prefs.corner;
    let places = [], ready = true;
    try { const p = await browser.runtime.sendMessage({ op: "places" }); if (p && p.ok) { places = p.places; ready = p.ready !== false; } } catch (e) {}
    const save = () => store.set({ ffPrefs: prefs }).catch(() => {});

    const power = document.getElementById("power");
    const main = document.getElementById("main");
    const draw = () => {
        power.classList.toggle("on", !!prefs.on);
        power.setAttribute("aria-checked", prefs.on ? "true" : "false");
        main.replaceChildren();
        if (!prefs.on) { main.appendChild(el("div", "查詞關掉了：滑過中文字不會跳出卡片。按右上角的開關打開。", "off")); return; }
        if (!ready) main.appendChild(el("div", "查詞的資料不在延伸功能裡，所以不會跳出卡片：在 Mac 上執行一次 install.sh（不要加 nosafari），再安裝一次 App。", "off"));
        settings(main);
        queueBox(main, r.ffQueue || []);
        main.appendChild(el("div", "用 Apple Pencil（或游標）停在一個中文字上面，就會跳出那個詞。這裡的設定和卡片上「設定」的一樣。", "note"));
    };
    power.addEventListener("click", () => { prefs.on = !prefs.on; save(); draw(); });

    const select = (parent, label, key, options) => {
        parent.appendChild(el("label", label));
        const s = el("select");
        for (const [v, t] of options) {
            const o = el("option", t);
            o.value = String(v);
            if (String(prefs[key]) === String(v)) o.selected = true;
            s.appendChild(o);
        }
        s.addEventListener("change", () => {
            const v = s.value;
            prefs[key] = (v === "true" || v === "false") ? v === "true" : (/^-?\d+(\.\d+)?$/.test(v) ? parseFloat(v) : v);
            save();
        });
        parent.appendChild(s);
    };
    const yesNo = [[true, "顯示"], [false, "不顯示"]];

    function settings(parent) {
        // one column per language, its settings under it
        const grid = el("div", null, "grid");
        const col = (cls, name) => { const c = el("div", null, "col " + cls); c.appendChild(el("h2", name)); grid.appendChild(c); return c; };
        const zh = col("zh", "華語");
        select(zh, "顯示", "zh", yesNo);
        select(zh, "讀音", "zhPlace", [[0, "國語"], [1, "普通話"], [2, "四川話"]]);
        select(zh, "拼寫", "zhRom", [[1, "注音"], [0, "拼音"]]);
        const tw = col("tw", "台語");
        select(tw, "顯示", "tw", yesNo);
        select(tw, "拼寫", "twRom", [[0, "皓羅"], [1, "台羅"], [2, "白話字"], [3, "方音"]]);
        select(tw, "腔口", "twPlace", [[-1, "通行"], ...places.map((p, i) => [i, p.slice(0, 2)])]);
        const yue = col("yue", "粵語");
        select(yue, "顯示", "yue", yesNo);
        const hak = col("hak", "客語");
        select(hak, "顯示", "hak", yesNo);
        select(hak, "腔", "hakAcc", ["四縣", "海陸", "大埔", "饒平", "詔安", "南四縣"].map((n, i) => [i, n]));
        select(hak, "拼寫", "hakRom", [[0, "拼音"], [1, "注音"]]);
        const sv = col("sv", "瑞典語");
        select(sv, "顯示", "sv", yesNo);
        select(sv, "由英文推測中文", "svGuess", yesNo);
        parent.appendChild(grid);
        // the rest
        const gen = el("div", null, "gen");
        const g = () => { const d = el("div"); gen.appendChild(d); return d; };
        select(g(), "聲調顏色", "colours", [[true, "開"], [false, "關"]]);
        select(g(), "英文解釋", "en", [[false, "不顯示"], [true, "顯示"]]);
        select(g(), "英文查中文", "en2zh", [[true, "開"], [false, "關"]]);
        select(g(), "字的大小", "font", [[0.85, "小"], [1, "中"], [1.15, "大"], [1.3, "更大"], [1.5, "最大"]]);
        select(g(), "位置", "pos", [["word", "詞的旁邊"], ["tl", "左上角"], ["tr", "右上角"], ["bl", "左下角"], ["br", "右下角"]]);
        select(g(), "網頁上收藏的詞", "ring", [[false, "不標"], [true, "彩虹框"]]);
        select(g(), "網頁上的聲調顏色", "tint", [[false, "不上色"], ["saved", "收藏的詞"], ["all", "全部（華語）"]]);
        select(g(), "影片字幕（YouTube、Viki）", "subs", [[true, "開"], [false, "關"]]);
        select(g(), "查字幕的詞時影片暫停", "subsPause", [[true, "開"], [false, "關"]]);
        select(g(), "影片字幕的位置", "subsFlow", [[false, "旁邊（往上捲）"], [true, "下面（往旁邊流）"]]);
        const reset = el("button", "大小還原");
        reset.addEventListener("click", () => { prefs.w = 0; prefs.h = 0; save(); });
        const rd = g(); rd.appendChild(el("label", "卡片大小（拖拉角落）")); rd.appendChild(reset);
        parent.appendChild(gen);
    }

    function queueBox(parent, queue) {
        const q = el("div", null, "sec");
        parent.appendChild(q);
        if (!queue.length) { q.appendChild(el("div", "還沒有選詞（卡片上的「加到不熟」「收藏」）。", "note")); return; }
        q.appendChild(el("div", "選好的詞（" + queue.length + "）：" + queue.map(x => x.h + (x.w === "saved" ? "（收藏）" : "")).join("、"), "words"));
        const btns = el("div", null, "row");
        const send = el("button", "傳到 App", "send");
        send.addEventListener("click", async () => {
            const ops = queue.map(x => x.x ? [x.k, x.w === "saved" ? "s" : "u", x.x] : [x.k, x.w === "saved" ? "s" : "u"]);
            const b64 = btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(ops)))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
            const url = "fangfangcards://safari?ops=" + b64;
            try { await browser.tabs.update({ url }); } catch (e) { window.open(url); }
            await store.set({ ffQueue: [] }).catch(() => {});
            q.replaceChildren(el("div", "已經傳到方方詞卡。如果 App 沒有打開，請在卡片上再按一次「傳到 App」。", "note"));
        });
        const clear = el("button", "全部清掉");
        clear.addEventListener("click", async () => { await store.set({ ffQueue: [] }).catch(() => {}); q.replaceChildren(); });
        btns.append(send, clear);
        q.appendChild(btns);
    }
    draw();
}
main();
