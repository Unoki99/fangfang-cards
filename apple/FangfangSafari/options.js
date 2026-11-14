// 方方詞卡 查詞: the settings page (a whole page, opened from the toolbar window's 所有設定, or from Safari's
// settings for the extension), in parts like the app's own 設定: each part with its colour, and notes in three
// colours: blue 怎麼用, green 小技巧, yellow 注意.
(async () => {
    const d = await ffLoad();
    const { prefs, places } = d;
    const main = document.getElementById("main"), nav = document.getElementById("nav");
    const el = ffEl;

    const part = (id, title, colour, lead) => {
        const s = el("section", null, "part");
        s.id = id;
        s.style.setProperty("--c", colour);
        const h = el("h2"); h.append(el("span", null, "dot"), title);
        s.appendChild(h);
        if (lead) s.appendChild(el("p", lead, "lead"));
        main.appendChild(s);
        const a = el("a"); a.href = "#" + id; a.style.setProperty("--c", colour);
        a.append(el("span", null, "dot"), title);
        nav.appendChild(a);
        return s;
    };
    const row = (parent, title, sub, control, stack) => {
        const r = el("div", null, "row" + (stack ? " stack" : ""));
        const w = el("div", null, "what");
        w.appendChild(el("b", title));
        if (sub) w.appendChild(el("small", sub));
        r.append(w, control);
        parent.appendChild(r);
        return r;
    };
    const tip = (parent, kind, text) => {
        const t = el("div", null, "tip " + kind);
        t.append(el("b", { how: "怎麼用", good: "小技巧", warn: "注意" }[kind]), text);
        parent.appendChild(t);
    };
    const v = c => getComputedStyle(document.documentElement).getPropertyValue(c).trim();

    if (!d.ready) {
        const o = el("div", "查詞的資料不在延伸功能裡，所以不會跳出卡片：在 Mac 上執行一次 install.sh（不要加 nosafari），再安裝一次 App。", "off");
        main.appendChild(o);
    }

    // ── 開關 ──
    const sw = part("switches", "開關", v("--web"), "兩個功能各有自己的開關：只看影片字幕的話，網頁上停在詞上不會跳出卡片。");
    const legend = el("div", null, "legend");
    for (const [t, c] of [["怎麼用", "--tip"], ["小技巧", "--good"], ["注意", "--warn"]]) {
        const s = el("span"); const i = el("i"); i.style.setProperty("--t", v(c)); s.append(i, t); legend.appendChild(s);
    }
    sw.appendChild(legend);
    const webSw = ffSwitch(prefs, "on", () => webPart.classList.toggle("dim", !prefs.on));
    webSw.style.setProperty("--c", v("--web"));
    row(sw, "網頁查詞", "游標或 Apple Pencil 停在一個詞上，就跳出那個詞的卡片", webSw);
    const subSw = ffSwitch(prefs, "subs", () => subPart.classList.toggle("dim", !prefs.subs));
    subSw.style.setProperty("--c", v("--subs"));
    row(sw, "影片字幕", "YouTube、Viki：影片的字幕在旁邊的面板捲動，點一下字幕裡的詞查詞（停在上面不會跳出來）", subSw);
    tip(sw, "how", "iPad 用 Apple Pencil 懸停在字上面（不要碰到螢幕），Mac 用觸控板或滑鼠的游標停在字上。沒有懸停的 iPad 和 iPhone：用手指選取一個詞。");

    // ── 語言 ──
    const lg = part("languages", "語言", v("--tw"), "卡片上顯示哪些語言，和它們的讀音、拼寫。顏色和 App 裡每個語言的顏色一樣。");
    const langs = el("div", null, "langs");
    lg.appendChild(langs);
    const yesNo = [[true, "顯示"], [false, "不顯示"]];
    const lang = (cls, name, key, opts) => {
        const c = el("div", null, "lang " + cls);
        const h = el("h3"); h.append(name);
        const s = ffSwitch(prefs, key, () => c.querySelectorAll(".seg").forEach(x => x.classList.toggle("dim", !prefs[key])));
        s.style.setProperty("--c", getComputedStyle(c).getPropertyValue("--c") || v("--" + cls));
        h.appendChild(s);
        c.appendChild(h);
        for (const [label, k, o] of opts) {
            c.appendChild(el("label", label));
            const g = ffChoice(prefs, k, o);
            g.style.setProperty("--c", v("--" + cls));
            if (!prefs[key]) g.classList.add("dim");
            c.appendChild(g);
        }
        if (!opts.length) c.appendChild(el("label", "粵拼。沒有其他要選的。"));
        langs.appendChild(c);
        s.style.setProperty("--c", v("--" + cls));
    };
    lang("zh", "華語", "zh", [["讀音", "zhPlace", [[0, "國語"], [1, "普通話"], [2, "四川話"]]], ["拼寫", "zhRom", [[1, "注音"], [0, "拼音"]]]]);
    lang("tw", "台語", "tw", [["拼寫", "twRom", [[0, "皓羅"], [1, "台羅"], [2, "白話字"], [3, "方音"]]],
        ["腔口", "twPlace", [[-1, "通行"], ...places.map((p, i) => [i, p.slice(0, 2)])]]]);
    lang("yue", "粵語", "yue", []);
    lang("hak", "客語", "hak", [["腔", "hakAcc", ["四縣", "海陸", "大埔", "饒平", "詔安", "南四縣"].map((n, i) => [i, n])],
        ["拼寫", "hakRom", [[0, "拼音"], [1, "注音"]]]]);
    lang("sv", "瑞典語", "sv", [["由英文推測中文", "svGuess", [[true, "開"], [false, "關"]]]]);
    tip(lg, "good", "一個詞好幾個語言都有的話，卡片上會一個語言一塊，順序和顏色跟這裡一樣。");

    // ── 卡片 ──
    const cd = part("card", "卡片", v("--card"), "跳出來的卡片長什麼樣子。");
    const ch = (p, k, o) => { const g = ffChoice(prefs, k, o); g.style.setProperty("--c", v("--card")); return g; };
    row(cd, "聲調顏色", "字照聲調上色（和 App 選的顏色一樣）", ch(cd, "colours", [[true, "開"], [false, "關"]]));
    row(cd, "英文解釋", null, ch(cd, "en", [[false, "不顯示"], [true, "顯示"]]));
    row(cd, "英文查中文", "游標停在英文字上，找中文的詞", ch(cd, "en2zh", [[true, "開"], [false, "關"]]));
    row(cd, "字的大小", null, ch(cd, "font", FF_SIZES), true);
    row(cd, "位置", "卡片出現在哪裡", ch(cd, "pos", [["word", "詞的旁邊"], ["tl", "左上角"], ["tr", "右上角"], ["bl", "左下角"], ["br", "右下角"]]), true);
    const reset = el("button", "大小還原", "act");
    reset.addEventListener("click", () => { prefs.w = 0; prefs.h = 0; ffSave(prefs); reset.textContent = "還原了"; });
    row(cd, "卡片大小", "拖拉卡片右下角可以改大小", reset);

    // ── 鍵盤 ──
    const kb = part("keys", "鍵盤", "#ffe066", "游標（觸控板、滑鼠或 Pencil）停在一個詞上，按一個鍵就標記它，不用打開卡片。網頁和影片字幕上都可以。");
    const kSw = ffSwitch(prefs, "keys"); kSw.style.setProperty("--c", "#ffe066");
    row(kb, "用鍵盤標記", null, kSw);
    const keyBox = name => {
        const i = el("input");
        i.value = String(prefs[name] || "").toUpperCase();
        i.maxLength = 1;
        i.style.cssText = "width:56px;height:44px;text-align:center;font:700 20px -apple-system,sans-serif;border-radius:10px;" +
            "background:#23242c;color:#fff;border:1px solid #ffe066";
        i.addEventListener("input", () => {
            const c = i.value.trim().slice(-1).toLowerCase();
            if (!c) return;
            const other = name === "keyKnown" ? "keyNew" : "keyKnown";
            if (c === String(prefs[other]).toLowerCase()) { i.value = String(prefs[name]).toUpperCase(); return; }
            prefs[name] = c; i.value = c.toUpperCase(); ffSave(prefs);
        });
        return i;
    };
    row(kb, "認識", "標成認識：馬上不上色（只替不認識的詞上色開著的話），傳到 App 時變成熟悉", keyBox("keyKnown"));
    row(kb, "不熟＋收藏", "加到不熟，也收藏（連同那一句話）", keyBox("keyNew"));
    tip(kb, "how", "游標停在詞上按鍵，旁邊會跳出一個小提示說標了什麼。標的是卡片上第一個語言的那個詞。按「傳到 App」的時候一起傳過去。");
    tip(kb, "warn", "YouTube 自己用 K、J、L 和數字鍵控制影片，所以預設是 A 和 S。游標沒有停在詞上的時候，按鍵照網站原本的用法。");

    // ── 網頁 ──
    const webPart = part("web", "網頁", v("--web"), "網頁上的字本身（網頁查詞開著的時候）。");
    if (!prefs.on) webPart.classList.add("dim");
    const wc = (k, o) => { const g = ffChoice(prefs, k, o); g.style.setProperty("--c", v("--web")); return g; };
    row(webPart, "收藏的詞", "網頁上出現收藏過的詞時", wc("ring", [[false, "不標"], [true, "彩虹框"]]));
    row(webPart, "聲調顏色", "網頁上的中文字照聲調上色", wc("tint", [[false, "不上色"], ["saved", "收藏的詞"], ["all", "全部（華語）"]]));
    tip(webPart, "warn", "「全部」會替整頁的字上色，很長的網頁可能會慢一點。");

    // ── 影片字幕 ──
    const subPart = part("subs", "影片字幕", v("--subs"), "在 YouTube 和 Viki 看影片時，字幕出現在旁邊（iPhone 在下面），說到哪一句就亮到哪一句。");
    if (!prefs.subs) subPart.classList.add("dim");
    const sc = (k, o) => { const g = ffChoice(prefs, k, o); g.style.setProperty("--c", v("--subs")); return g; };
    row(subPart, "位置", "旁邊往上捲，或下面一行往旁邊流（全螢幕時一定在下面）", sc("subsFlow", [[false, "旁邊"], [true, "下面"]]));
    row(subPart, "大小", "面板上的 A− A+ 也可以調", sc("subsFont", FF_SIZES), true);
    row(subPart, "查詞時影片暫停", "點字幕的詞時（卡片關掉後繼續）", sc("subsPause", [[true, "開"], [false, "關"]]));
    row(subPart, "影片上原本的字幕", "面板開著的時候", sc("subsHideVideo", [[true, "隱藏"], [false, "顯示"]]));
    row(subPart, "不認識的詞：上面標讀音", "注音或拼音（照華語的設定），也有聲調顏色", sc("subsRd", [[true, "開"], [false, "關"]]));
    row(subPart, "讀音的大小", "注音或拼音和字的大小比", sc("subsRdSize", [[0.45, "小"], [0.56, "中"], [0.7, "大"], [0.85, "更大"], [1, "和字一樣"]]));
    row(subPart, "不認識的詞：下面標意思", prefs.en ? "現在是英文（語言裡的「英文」開著）" : "現在是中文（語言裡的「英文」打開就變英文）", sc("subsGl", [[true, "開"], [false, "關"]]));
    const tools = el("div", null, "tools");
    for (const [b, t] of [["上一句", "回到上一句"], ["重複", "一直重複這一句，練聽和跟讀"], ["慢速", "放慢到 0.75 倍"],
        ["一句一停", "每一句說完就暫停，按播放再說下一句（跟讀用）"], ["下一句", "跳到下一句"], ["讀音", "不認識的詞上面標讀音"], ["意思", "不認識的詞下面標意思"], ["懂 87%", "你認識這部影片多少的詞（要先從 App 傳認識的詞過來）"]]) {
        const x = el("div", null, "tool"); x.append(el("b", b), el("span", t)); tools.appendChild(x);
    }
    const tr = el("div", null, "row stack"); const tw = el("div", null, "what"); tw.append(el("b", "面板上的學習工具"));
    tr.append(tw, tools); subPart.appendChild(tr);
    tip(subPart, "how", "點每一行前面的時間會跳到那裡。用手指拖（或捲動）可以往前往後看，幾秒後會自己跟回影片。");
    tip(subPart, "how", "「不認識」是還沒在 App 裡標成熟悉的詞（用 A 標認識以後，讀音和意思就會拿掉）。還沒從 App 傳認識的詞過來時，每個詞都會標。");
    tip(subPart, "good", "在 YouTube 字幕語言可以選「自動翻譯」：影片沒有中文字幕時，會自己用自動翻譯成繁體中文。");
    tip(subPart, "warn", "iPhone 上影片全螢幕時看不到面板（全螢幕是 iOS 自己的播放器），要在網頁裡看。");

    // ── 認識的詞 ──
    const kn = part("known", "認識的詞", v("--known"), "從 App 傳過來的「熟悉」和「不熟」的詞：影片字幕裡沒學過的詞有虛線，不熟的詞有黃線，面板上顯示你懂多少。");
    const k = d.known;
    const onlySw = ffSwitch(prefs, "onlyNew");
    onlySw.style.setProperty("--c", v("--known"));
    row(kn, "只替不認識的詞上色", "網頁和影片字幕上，認識的詞不上聲調顏色，只有還沒學的詞有顏色", onlySw);
    const st = el("div", null, "stats");
    const count = o => Object.values(o || {}).reduce((a, x) => a + x.length, 0);
    const s1 = el("div"); s1.append(el("div", String(k ? count(k.k) : 0), "big"), el("small", "認識的詞"));
    const s2 = el("div"); s2.append(el("div", String(k ? count(k.u) : 0), "big"), el("small", "不熟的詞"));
    const s3 = el("div"); s3.append(el("div", k && k.at ? new Date(k.at).toLocaleDateString() : "—", "big"), el("small", "上次傳過來"));
    st.append(s1, s2, s3);
    kn.appendChild(st);
    // 貼上: the words copied in the app (設定 → Safari 查詞 → 複製認識的詞)
    const pasteRow = el("div", null, "btns"); pasteRow.style.marginTop = "12px";
    const paste = el("button", "貼上從 App 複製的詞", "act main"); paste.style.setProperty("--c", v("--known"));
    const msg = el("p", null, "lead"); msg.style.margin = "8px 0 0";
    const take = async text => {
        try {
            if (!/^fangfang-known[:=]/.test((text || "").trim())) throw new Error("x");
            const o = await ffTakeKnown(text);
            const n = Object.values(o.k || {}).reduce((a, x) => a + x.length, 0), u = Object.values(o.u || {}).reduce((a, x) => a + x.length, 0);
            msg.textContent = "收到了：認識的詞 " + n + " 個、不熟的詞 " + u + " 個。";
            setTimeout(() => location.reload(), 1200);
        } catch (e) { msg.textContent = "剪貼簿裡不是從 App 複製的詞。先在 App 按「複製認識的詞」，再回來按「貼上」。"; }
    };
    paste.addEventListener("click", async () => {
        try { await take(await navigator.clipboard.readText()); }
        catch (e) {
            // (no access to the clipboard: a box to paste into by hand)
            const ta = el("textarea"); ta.placeholder = "長按這裡，貼上"; ta.style.cssText = "width:100%;height:70px;margin-top:8px;border-radius:10px;background:#23242c;color:#eef0f6;border:1px solid #2e3039;padding:8px";
            ta.addEventListener("input", () => take(ta.value));
            if (!kn.querySelector("textarea")) pasteRow.after(ta);
            ta.focus();
        }
    });
    pasteRow.appendChild(paste);
    kn.append(pasteRow, msg);
    tip(kn, "how", "在 App 的「設定 → Safari 查詞」按「複製認識的詞」，再回到這裡按「貼上從 App 複製的詞」。或者按「把認識的詞傳到 Safari 查詞」：它會在 Safari 打開 example.com，詞放在網址的 # 後面，不會傳到網路上（Safari 查詞要允許在 example.com 上，或允許所有網站）。");
    tip(kn, "good", "學了新詞以後再傳一次，懂的百分比就會更新。卡片上的「認識」按鈕也算：按了馬上不上色，傳到 App 的時候 App 也會把它標成熟悉。");
    tip(kn, "warn", "網頁上要上色，「網頁」的聲調顏色要選「全部（華語）」。"); 
    if (k) {
        const clr = el("button", "清除", "act");
        clr.addEventListener("click", async () => { await ffStore.set({ ffKnown: null }).catch(() => {}); clr.textContent = "清除了"; });
        const r = el("div", null, "btns"); r.appendChild(clr); r.style.marginTop = "12px"; kn.appendChild(r);
    }

    // ── 傳到 App ──
    const sd = part("send", "傳到 App", v("--send"), "卡片上按「加到不熟」「收藏」的詞先存在這裡，傳到 App 的時候連你存詞的那一句話一起傳。看影片字幕的時間也一起傳（App 的練習統計）。");
    const q = d.queue;
    const mins = Object.values(d.watch).reduce((a, x) => a + x, 0);
    // (the buttons first, the words under them)
    if (q.length || mins >= 1) {
        const b = el("div", null, "btns");
        const send = el("button", "傳到 App", "act main");
        send.style.setProperty("--c", v("--send"));
        send.addEventListener("click", async () => { await ffSend(q, d.watch); send.textContent = "傳了"; });
        const clr = el("button", "全部清掉", "act");
        clr.addEventListener("click", async () => { await ffStore.set({ ffQueue: [] }).catch(() => {}); location.reload(); });
        b.append(send, clr);
        sd.appendChild(b);
    }
    if (mins >= 1) sd.appendChild(el("p", "看影片字幕的時間：" + Math.round(mins) + " 分鐘", "lead"));
    if (q.length) {
        const w = el("div", null, "words");
        for (const x of q) w.appendChild(el("span", x.h + (x.w === "saved" ? "・收藏" : x.w === "known" ? "・認識" : ""), x.w === "saved" ? "s" : ""));
        sd.appendChild(w);
    } else sd.appendChild(el("p", "還沒有選詞。", "lead"));
    tip(sd, "warn", "Safari 會先問要不要打開方方詞卡：按「打開」。App 沒有打開的話再按一次。");
})();
