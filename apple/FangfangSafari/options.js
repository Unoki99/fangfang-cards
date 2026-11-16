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
        t.append(el("b", { how: ffT("怎麼用"), good: ffT("小技巧"), warn: ffT("注意") }[kind]), text);
        parent.appendChild(t);
    };
    const v = c => getComputedStyle(document.documentElement).getPropertyValue(c).trim();

    if (!d.ready) {
        const o = el("div", ffT("還沒有安裝詞典，所以不會跳出卡片：在下面的「詞典」選一個語言安裝。"), "off");
        main.appendChild(o);
    }

    // ── 開關 ──
    const sw = part("switches", ffT("開關"), v("--web"), ffT("兩個功能各有自己的開關：只看影片字幕的話，網頁上停在詞上不會跳出卡片。"));
    const legend = el("div", null, "legend");
    for (const [t, c] of [[ffT("怎麼用"), "--tip"], [ffT("小技巧"), "--good"], [ffT("注意"), "--warn"]]) {
        const s = el("span"); const i = el("i"); i.style.setProperty("--t", v(c)); s.append(i, t); legend.appendChild(s);
    }
    sw.appendChild(legend);
    // (介面語言: the add-on's own words in 中文 or English)
    const ui = ffChoice(prefs, "uiLang", [["zh", "中文"], ["en", "English"]], () => location.reload());
    ui.style.setProperty("--c", v("--web"));
    row(sw, ffT("介面語言"), "中文 / English", ui);
    {   // (the page's own heading, in the language chosen)
        const h = document.querySelector("header h1"), p = document.querySelector("header p");
        if (h) h.textContent = ffT(h.textContent); if (p) p.textContent = ffT(p.textContent);
        document.title = ffT(document.title);
    }
    const webSw = ffSwitch(prefs, "on", () => webPart.classList.toggle("dim", !prefs.on));
    webSw.style.setProperty("--c", v("--web"));
    row(sw, ffT("網頁查詞"), ffT("游標或 Apple Pencil 停在一個詞上，就跳出那個詞的卡片"), webSw);
    const subSw = ffSwitch(prefs, "subs", () => subPart.classList.toggle("dim", !prefs.subs));
    subSw.style.setProperty("--c", v("--subs"));
    row(sw, ffT("影片字幕"), ffT("YouTube、Viki：影片的字幕在旁邊的面板捲動，點一下字幕裡的詞查詞（停在上面不會跳出來）"), subSw);
    tip(sw, "how", ffT("iPad 用 Apple Pencil 懸停在字上面（不要碰到螢幕），Mac 用觸控板或滑鼠的游標停在字上。沒有懸停的 iPad 和 iPhone：用手指選取一個詞。"));

    // ── 詞典 ──
    dictPart(part("dicts", ffT("詞典"), "#7fd1b9", ffT("查詞要用的詞典。詞典的授權不允許散布改過的版本，所以查詞裡面沒有附詞典：按「安裝」會下載詞典原本的檔案（先從方方詞卡在 GitHub 上的原檔副本，沒有的話從原本發布的地方），在這個瀏覽器裡整理好，存在瀏覽器裡。只會下載詞典的檔案，不會傳出任何東西。")));

    // ── 語言 ──
    const lg = part("languages", ffT("語言"), v("--tw"), ffT("查詞用哪一個語言（一次一個：打開一個，其他的會自己關掉），和它們的讀音、拼寫。顏色和 App 裡每個語言的顏色一樣。"));
    const langs = el("div", null, "langs");
    lg.appendChild(langs);
    const yesNo = [[true, ffT("顯示")], [false, ffT("不顯示")]];
    // (one language at a time: turning one on turns the others off; the one on can't be turned off)
    const langCards = [];
    const paintLangs = () => {
        for (const [c, sw, key] of langCards) {
            sw.classList.toggle("on", !!prefs[key]); sw.setAttribute("aria-checked", prefs[key] ? "true" : "false");
            c.querySelectorAll(".seg").forEach(x => x.classList.toggle("dim", !prefs[key]));
            c.classList.toggle("off", !prefs[key]);
        }
    };
    const lang = (cls, name, key, opts) => {
        const c = el("div", null, "lang " + cls);
        const h = el("h3"); h.append(name);
        const s = ffSwitch(prefs, key, () => { ffOneLang(prefs, key); ffSave(prefs); paintLangs(); });
        langCards.push([c, s, key]);
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
        if (!opts.length) c.appendChild(el("label", ffT("粵拼。沒有其他要選的。")));
        langs.appendChild(c);
        s.style.setProperty("--c", v("--" + cls));
    };
    lang("zh", ffT("華語"), "zh", [[ffT("讀音"), "zhPlace", [[0, ffT("國語")], [1, ffT("普通話")], [2, ffT("四川話")]]], [ffT("拼寫"), "zhRom", [[1, ffT("注音")], [0, ffT("拼音")]]]]);
    lang("tw", ffT("台語"), "tw", [[ffT("拼寫"), "twRom", [[0, ffT("皓羅")], [1, ffT("台羅")], [2, ffT("白話字")], [3, ffT("方音")]]],
        [ffT("腔口"), "twPlace", [[-1, ffT("通行")], ...places.map((p, i) => [i, p.slice(0, 2)])]]]);
    lang("yue", ffT("粵語"), "yue", []);
    lang("hak", ffT("客語"), "hak", [[ffT("腔"), "hakAcc", [ffT("四縣"), ffT("海陸"), ffT("大埔"), ffT("饒平"), ffT("詔安"), ffT("南四縣")].map((n, i) => [i, n])],
        [ffT("拼寫"), "hakRom", [[0, ffT("拼音")], [1, ffT("注音")]]]]);
    lang("sv", ffT("瑞典語"), "sv", [[ffT("由英文推測中文"), "svGuess", [[true, ffT("開")], [false, ffT("關")]]]]);
    paintLangs();
    tip(lg, "how", ffT("一次只開一個語言：卡片、網頁上的顏色、影片字幕（「自動」的時候）和按鍵標的詞都用這個語言。傳到 App 的詞也照它自己的語言放，不會混在一起。"));

    // ── 卡片 ──
    const cd = part("card", ffT("卡片"), v("--card"), ffT("跳出來的卡片長什麼樣子。"));
    const ch = (p, k, o) => { const g = ffChoice(prefs, k, o); g.style.setProperty("--c", v("--card")); return g; };
    row(cd, ffT("聲調顏色"), ffT("字照聲調上色（和 App 選的顏色一樣）"), ch(cd, "colours", [[true, ffT("開")], [false, ffT("關")]]));
    row(cd, ffT("英文解釋"), null, ch(cd, "en", [[false, ffT("不顯示")], [true, ffT("顯示")]]));
    row(cd, ffT("英文查中文"), ffT("游標停在英文字上，找中文的詞"), ch(cd, "en2zh", [[true, ffT("開")], [false, ffT("關")]]));
    row(cd, ffT("字的大小"), null, ch(cd, "font", FF_SIZES), true);
    row(cd, ffT("位置"), ffT("卡片出現在哪裡"), ch(cd, "pos", [["word", ffT("詞的旁邊")], ["tl", ffT("左上角")], ["tr", ffT("右上角")], ["bl", ffT("左下角")], ["br", ffT("右下角")]]), true);
    const reset = el("button", ffT("大小還原"), "act");
    reset.addEventListener("click", () => { prefs.w = 0; prefs.h = 0; ffSave(prefs); reset.textContent = ffT("還原了"); });
    row(cd, ffT("卡片大小"), ffT("拖拉卡片右下角可以改大小"), reset);

    // ── 鍵盤 ──
    const kb = part("keys", ffT("鍵盤"), "#ffe066", ffT("游標（觸控板、滑鼠或 Pencil）停在一個詞上，按一個鍵就標記它，不用打開卡片。網頁和影片字幕上都可以。"));
    const kSw = ffSwitch(prefs, "keys"); kSw.style.setProperty("--c", "#ffe066");
    row(kb, ffT("用鍵盤標記"), null, kSw);
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
    row(kb, ffT("認識"), ffT("標成認識：馬上不上色（只替不認識的詞上色開著的話），傳到 App 時變成熟悉"), keyBox("keyKnown"));
    row(kb, ffT("不熟＋收藏"), ffT("加到不熟，也收藏（連同那一句話）"), keyBox("keyNew"));
    tip(kb, "how", ffT("游標停在詞上按鍵，旁邊會跳出一個小提示說標了什麼。標的是卡片上第一個語言的那個詞。按「傳到 App」的時候一起傳過去。"));
    tip(kb, "warn", ffT("YouTube 自己用 K、J、L 和數字鍵控制影片，所以預設是 A 和 S。游標沒有停在詞上的時候，按鍵照網站原本的用法。"));

    // ── 網頁 ──
    const webPart = part("web", ffT("網頁"), v("--web"), ffT("網頁上的字本身（網頁查詞開著的時候）。"));
    if (!prefs.on) webPart.classList.add("dim");
    const wc = (k, o) => { const g = ffChoice(prefs, k, o); g.style.setProperty("--c", v("--web")); return g; };
    row(webPart, ffT("收藏的詞"), ffT("網頁上出現收藏過的詞時"), wc("ring", [[false, ffT("不標")], [true, ffT("彩虹框")]]));
    row(webPart, ffT("聲調顏色"), ffT("網頁上的中文字照聲調上色"), wc("tint", [[false, ffT("不上色")], ["saved", ffT("收藏的詞")], ["all", ffT("全部（華語）")]]));
    tip(webPart, "warn", ffT("「全部」會替整頁的字上色，很長的網頁可能會慢一點。"));

    // ── 影片字幕 ──
    const subPart = part("subs", ffT("影片字幕"), v("--subs"), ffT("在 YouTube 和 Viki 看影片時，字幕出現在旁邊（iPhone 在下面），說到哪一句就亮到哪一句。"));
    if (!prefs.subs) subPart.classList.add("dim");
    const sc = (k, o, f) => { const g = ffChoice(prefs, k, o, f); g.style.setProperty("--c", v("--subs")); return g; };
    row(subPart, ffT("位置"), ffT("旁邊往上捲，或下面一行往旁邊流（全螢幕時一定在下面）"), sc("subsFlow", [[false, ffT("旁邊")], [true, ffT("下面")]]));
    row(subPart, ffT("大小"), ffT("面板上的 A− A+ 也可以調"), sc("subsFont", FF_SIZES), true);
    row(subPart, ffT("查詞時影片暫停"), ffT("點字幕的詞時（卡片關掉後繼續）"), sc("subsPause", [[true, ffT("開")], [false, ffT("關")]]));
    row(subPart, ffT("影片上原本的字幕"), ffT("面板開著的時候"), sc("subsHideVideo", [[true, ffT("隱藏")], [false, ffT("顯示")]]));
    row(subPart, ffT("字幕的語言"), ffT("讀音、意思、聲調顏色和生詞用哪個語言的詞典。自動：跟著上面開著的那一個語言（瑞典語的話，看字幕本身的語言）"), sc("subsLang", [["auto", ffT("自動（跟查詞的語言）")], ["zh", ffT("華語")], ["tw", ffT("台語")], ["yue", ffT("粵語")], ["hak", ffT("客語")]]));
    row(subPart, ffT("簡體字幕"), ffT("簡體的字幕轉成繁體（照詞典的詞：头发 → 頭髮），認識的詞也照繁體認得"), sc("subsTrad", [[true, ffT("轉成繁體")], [false, ffT("照原樣")]]));
    row(subPart, ffT("第二種語言"), ffT("每一行下面用小小的灰色字顯示另一種語言（例如英文），影片有那個語言的字幕才會出現。在字幕面板上選。"), sc("subs2", [["", ffT("不顯示")], ["en", "English"], ["zh-hant", ffT("繁體中文")], ["zh-hans", ffT("簡體中文")], ["ja", "日本語"], ["ko", "한국어"]]));
    row(subPart, ffT("面板的底"), ffT("黑色；跟著底下的畫面：用底下大部分的顏色（太亮的會調暗）；沒有底：只看得到字幕一句一句的框、按鈕和詞卡"), sc("subsBg", [["dark", ffT("黑色")], ["tint", ffT("跟著底下的畫面")], ["clear", ffT("沒有底")]]));
    row(subPart, ffT("字幕在下面橫排時的詞卡"), ffT("畫面最上面一排一樣大小的詞卡：正在說的這一句標出來的詞"), sc("subsDefs", [[true, ffT("顯示")], [false, ffT("不顯示")]]));

    // (標出來的詞: which words of the subtitles get their reading, meaning and colour)
    subPart.appendChild(el("h3", ffT("標出來的詞"), "sub"));
    subPart.appendChild(el("p", ffT("字幕裡哪些詞上面標讀音、下面標意思、有聲調顏色（詞卡和「有生詞才停」也照這個）。"), "lead"));
    row(subPart, ffT("標哪些詞"), ffT("不認識：還沒在 App 標成熟悉的詞；不常用：不在最常用的那些詞裡面（不管認不認識）"), sc("subsMark", [["new", ffT("不認識的詞")], ["rare", ffT("不常用的詞")], ["both", ffT("不認識又不常用的詞")]], () => paintRare()));
    const rareRow = row(subPart, ffT("多不常用才標"), ffT("和 App 裡每個詞旁邊的常用度（五格）一樣：選的那一級以下的詞才標"), rareChoice(), true);
    // (each choice: the bars beside the words in the App, the level it starts at, and which words that is)
    function rareChoice() {
        const opts = [[1000, 4, ffT("常用和更少見的"), ffT("第 1001 個以後的詞")], [3000, 3, ffT("一般和更少見的"), ffT("第 3001 個以後的詞")],
                      [8000, 2, ffT("不常用和少見的"), ffT("第 8001 個以後的詞")], [20000, 1, ffT("只標少見的"), ffT("第 20001 個以後的詞")]];
        const g = el("div", null, "seg bars");
        g.style.setProperty("--c", v("--subs"));
        const draw = () => {
            g.replaceChildren();
            for (const [val, level, name, range] of opts) {
                const b = el("button", null, String(prefs.subsRare || 3000) === String(val) ? "on" : "");
                const sig = el("span", null, "sig");
                for (let i = 1; i <= 5; i++) {
                    const bar = el("i", null, i <= level ? "f" : "");
                    bar.style.height = (5 + i * 3) + "px";
                    sig.appendChild(bar);
                }
                b.appendChild(sig);
                b.appendChild(el("span", name, "nm"));
                b.appendChild(el("span", range, "rg"));
                b.addEventListener("click", () => { prefs.subsRare = val; ffSave(prefs); draw(); });
                g.appendChild(b);
            }
        };
        draw();
        return g;
    }
    function paintRare() { rareRow.classList.toggle("dim", (prefs.subsMark || "new") === "new"); }
    paintRare();
    row(subPart, ffT("上面標讀音"), ffT("注音或拼音（照華語的設定），也有聲調顏色"), sc("subsRd", [[true, ffT("開")], [false, ffT("關")]]));
    row(subPart, ffT("讀音的大小"), ffT("注音或拼音和字的大小比"), sc("subsRdSize", [[0.25, ffT("最小")], [0.32, ffT("很小")], [0.4, ffT("小一點")], [0.45, ffT("小")], [0.56, ffT("中")], [0.7, ffT("大")], [0.85, ffT("更大")], [1, ffT("和字一樣")]]));
    row(subPart, ffT("下面標意思"), prefs.en ? ffT("現在是英文（語言裡的「英文」開著）") : ffT("現在是中文（語言裡的「英文」打開就變英文）"), sc("subsGl", [[true, ffT("開")], [false, ffT("關")]]));
    row(subPart, ffT("英文字幕下面標中文"), ffT("英文的字幕：每個英文字下面標它的中文（照開著的語言：華語、台語、粵語或客語）"), sc("subsEnZh", [[true, ffT("開")], [false, ffT("關")]]));
    row(subPart, ffT("意思的大小"), ffT("下面的意思和字的大小比"), sc("subsGlSize", [[0.25, ffT("最小")], [0.32, ffT("很小")], [0.4, ffT("小一點")], [0.5, ffT("中")], [0.6, ffT("大")], [0.75, ffT("更大")]]));
    const onlySw = ffSwitch(prefs, "onlyNew");
    onlySw.style.setProperty("--c", v("--subs"));
    row(subPart, ffT("字幕的聲調顏色"), ffT("字幕裡的字和讀音用聲調顏色。和詞卡的「聲調顏色」分開設定"), sc("subsColours", [[true, ffT("開")], [false, ffT("關")]]));
    row(subPart, ffT("只替標出來的詞上色"), ffT("其他的詞不上聲調顏色（網頁上也是：只有不認識的詞有顏色）"), onlySw);
    const tools = el("div", null, "tools");
    for (const [b, t] of [[ffT("上一句"), ffT("回到上一句")], [ffT("重複"), ffT("一直重複這一句，練聽和跟讀")], [ffT("慢速"), ffT("放慢到 0.75 倍")],
        [ffT("一句一停"), ffT("每一句說完就暫停，按播放再說下一句（跟讀用）")], [ffT("下一句"), ffT("跳到下一句")], [ffT("讀音"), ffT("標出來的詞上面標讀音")], [ffT("生詞"), ffT("一個大視窗列出影片裡所有還不認識的詞：點你認識的，再按確定（或確定，其他都加到不熟）")], [ffT("意思"), ffT("標出來的詞下面標意思")], [ffT("懂 87%"), ffT("你認識這部影片多少的詞（要先從 App 傳認識的詞過來）")]]) {
        const x = el("div", null, "tool"); x.append(el("b", b), el("span", t)); tools.appendChild(x);
    }
    const tr = el("div", null, "row stack"); const tw = el("div", null, "what"); tw.append(el("b", ffT("面板上的學習工具")));
    tr.append(tw, tools); subPart.appendChild(tr);
    tip(subPart, "how", ffT("點每一行前面的時間會跳到那裡。用手指拖（或捲動）可以往前往後看，幾秒後會自己跟回影片。"));
    tip(subPart, "how", ffT("「不認識」是還沒在 App 裡標成熟悉的詞（用 A 標認識以後，讀音和意思就會拿掉）。還沒從 App 傳認識的詞過來時，每個詞都會標。"));
    tip(subPart, "good", ffT("在 YouTube 字幕語言可以選「自動翻譯」：影片沒有中文字幕時，會自己用自動翻譯成繁體中文。"));
    tip(subPart, "warn", ffT("iPhone 上影片全螢幕時看不到面板（全螢幕是 iOS 自己的播放器），要在網頁裡看。"));

    // ── 認識的詞 ──
    const kn = part("known", ffT("認識的詞"), v("--known"), ffT("從 App 傳過來的「熟悉」和「不熟」的詞：影片字幕裡沒學過的詞有虛線，不熟的詞有黃線，面板上顯示你懂多少。"));
    const k = d.known;
    const st = el("div", null, "stats");
    const count = o => Object.values(o || {}).reduce((a, x) => a + x.length, 0);
    const s1 = el("div"); s1.append(el("div", String(k ? count(k.k) : 0), "big"), el("small", ffT("認識的詞")));
    const s2 = el("div"); s2.append(el("div", String(k ? count(k.u) : 0), "big"), el("small", ffT("不熟的詞")));
    const s3 = el("div"); s3.append(el("div", k && k.at ? new Date(k.at).toLocaleDateString() : "—", "big"), el("small", ffT("上次傳過來")));
    st.append(s1, s2, s3);
    kn.appendChild(st);
    // 貼上: the words copied in the app (設定 → Safari 查詞 → 複製認識的詞)
    const pasteRow = el("div", null, "btns"); pasteRow.style.marginTop = "12px";
    const paste = el("button", ffT("貼上從 App 複製的詞"), "act main"); paste.style.setProperty("--c", v("--known"));
    const msg = el("p", null, "lead"); msg.style.margin = "8px 0 0";
    const take = async text => {
        try {
            if (!/^fangfang-known[:=]/.test((text || "").trim())) throw new Error("x");
            const o = await ffTakeKnown(text);
            const n = Object.values(o.k || {}).reduce((a, x) => a + x.length, 0), u = Object.values(o.u || {}).reduce((a, x) => a + x.length, 0);
            msg.textContent = ffT("收到了：認識的詞 ") + n + ffT(" 個、不熟的詞 ") + u + ffT(" 個。");
            setTimeout(() => location.reload(), 1200);
        } catch (e) { msg.textContent = ffT("剪貼簿裡不是從 App 複製的詞。先在 App 按「複製認識的詞」，再回來按「貼上」。"); }
    };
    paste.addEventListener("click", async () => {
        try { await take(await navigator.clipboard.readText()); }
        catch (e) {
            // (no access to the clipboard: a box to paste into by hand)
            const ta = el("textarea"); ta.placeholder = ffT("長按這裡，貼上"); ta.style.cssText = "width:100%;height:70px;margin-top:8px;border-radius:10px;background:#23242c;color:#eef0f6;border:1px solid #2e3039;padding:8px";
            ta.addEventListener("input", () => take(ta.value));
            if (!kn.querySelector("textarea")) pasteRow.after(ta);
            ta.focus();
        }
    });
    pasteRow.appendChild(paste);
    kn.append(pasteRow, msg);
    tip(kn, "how", ffT("在 App 的「設定 → Safari 查詞」按「複製認識的詞」，再回到這裡按「貼上從 App 複製的詞」。或者按「把認識的詞傳到 Safari 查詞」：它會在 Safari 打開 example.com，詞放在網址的 # 後面，不會傳到網路上（Safari 查詞要允許在 example.com 上，或允許所有網站）。"));
    tip(kn, "how", ffT("Android 的 Firefox：在 App 的「設定 → 匯出與匯入 → 瀏覽器查詞（Firefox）」按「把認識的詞傳到瀏覽器查詞」，或「複製認識的詞」再回到這裡貼上。"));
    tip(kn, "good", ffT("學了新詞以後再傳一次，懂的百分比就會更新。卡片上的「認識」按鈕也算：按了馬上不上色，傳到 App 的時候 App 也會把它標成熟悉。"));
    tip(kn, "warn", ffT("網頁上要上色，「網頁」的聲調顏色要選「全部（華語）」。")); 
    if (k) {
        const clr = el("button", ffT("清除"), "act");
        clr.addEventListener("click", async () => { await ffStore.set({ ffKnown: null }).catch(() => {}); clr.textContent = ffT("清除了"); });
        const r = el("div", null, "btns"); r.appendChild(clr); r.style.marginTop = "12px"; kn.appendChild(r);
    }

    // ── 傳到 App ──
    const sd = part("send", ffT("傳到 App"), v("--send"), ffT("卡片上按「加到不熟」「收藏」的詞先存在這裡，傳到 App 的時候連你存詞的那一句話一起傳。看影片字幕的時間也一起傳（App 的練習統計）。"));
    const q = d.queue;
    const mins = Object.values(d.watch).reduce((a, x) => a + x, 0);
    // (the buttons first, the words under them)
    if (q.length || mins >= 1) {
        const b = el("div", null, "btns");
        const send = el("button", ffT("傳到 App"), "act main");
        send.style.setProperty("--c", v("--send"));
        send.addEventListener("click", async () => {
            const url = await ffSend(q, d.watch);
            send.textContent = ffT("傳了");
            // (the words are kept in this link: if the app didn't open, tapping it opens it)
            const a = el("a", ffT("App 沒有打開？點這裡"));
            a.href = url;
            a.style.cssText = "margin-left:12px;color:inherit";
            send.after(a);
        });
        const clr = el("button", ffT("全部清掉"), "act");
        clr.addEventListener("click", async () => { await ffStore.set({ ffQueue: [] }).catch(() => {}); location.reload(); });
        b.append(send, clr);
        sd.appendChild(b);
    }
    if (mins >= 1) sd.appendChild(el("p", ffT("看影片字幕的時間：") + Math.round(mins) + ffT(" 分鐘"), "lead"));
    if (q.length) {
        // (by 影片詞組: the words of one video together, as the app will keep them)
        const by = new Map();
        for (const x of q) { const g = x.gn || ""; if (!by.has(g)) by.set(g, []); by.get(g).push(x); }
        for (const [g, xs] of by) {
            sd.appendChild(el("p", (g ? ffT("影片：") + g : ffT("其他")) + ffT("（") + xs.length + ffT("）"), "lead"));
            const w = el("div", null, "words");
            for (const x of xs) w.appendChild(el("span", x.h + (x.w === "saved" ? ffT("・收藏") : x.w === "known" ? ffT("・認識") : x.w === "group" ? ffT("・之前選的") : ""), x.w === "saved" ? "s" : ""));
            sd.appendChild(w);
        }
    } else sd.appendChild(el("p", ffT("還沒有選詞。"), "lead"));
    tip(sd, "warn", ffT("Safari 會先問要不要打開方方詞卡：按「打開」。App 沒有打開的話再按一次。"));
    tip(sd, "how", ffT("Android 的 Firefox：按「傳到 App」會打開 Android 的方方詞卡（Firefox 可能先問要不要打開）。沒有打開的話，按旁邊的「App 沒有打開？點這裡」。"));
})();

/// 設定 → 詞典: each dictionary, installed or not, and its 安裝 / 移除 (one at a time)
async function dictPart(sec) {
    const el = ffEl;
    const box = el("div", null, "dicts");
    sec.appendChild(box);
    // (the add-on without the converters, as Safari's: its dictionaries were made with the app, on the Mac)
    const can = await fetch(browser.runtime.getURL("install/common.js")).then(r => r.ok, () => false);
    if (!can) {
        sec.appendChild(el("p", ffT("這個查詞的詞典是安裝 App 的時候在 Mac 上做好放進來的，不用在這裡安裝。"), "lead"));
        return;
    }
    if (location.hash === "#dicts") setTimeout(() => sec.scrollIntoView(), 50);
    const HOSTS = ["https://raw.githubusercontent.com/*", "https://sutian.moe.edu.tw/*", "https://hakkadict.moe.edu.tw/*",
        "https://kaikki.org/*", "http://folkets-lexikon.csc.kth.se/*"];
    const got = new Map();          // (files downloaded on this visit: essay.txt and CC-CEDICT, used by more than one)
    let busy = false;
    const cards = [];
    let parts = {};
    const refresh = async () => {
        try { parts = await ffDB.parts(); } catch (e) { parts = {}; }
        for (const c of cards) c.paint();
    };

    for (const dict of FF_DICTS) {
        const c = el("div", null, "lang dict " + dict.id);
        const h = el("h3"); h.append(ffT(dict.name)); c.appendChild(h);
        const st = el("div", null, "st"); c.appendChild(st);
        const btns = el("div", null, "btns");
        const inst = el("button", null, "act main"), rm = el("button", ffT("移除"), "act");
        inst.style.setProperty("--c", "var(--c)");
        btns.append(inst, rm); c.appendChild(btns);
        const bar = el("div", null, "bar"), fill = el("i"); bar.appendChild(fill);
        const doing = el("div", null, "doing"), err = el("div", null, "err");
        bar.style.display = doing.style.display = "none";
        c.append(bar, doing, err);
        const ul = el("ul");
        for (const [name, lic, url] of dict.from) {
            const li = el("li");
            if (url) { const a = el("a", name); a.href = url; a.target = "_blank"; a.rel = "noopener"; li.appendChild(a); }
            else li.append(name);
            if (lic) li.append("（" + lic + "）");
            ul.appendChild(li);
        }
        c.appendChild(ul);
        box.appendChild(c);
        const card = {
            paint() {
                const p = parts[dict.id];
                const n = p && p.meta ? p.meta[dict.id] : 0;
                st.className = "st" + (p ? " ok" : "");
                st.textContent = p
                    ? ffT("已安裝・") + n.toLocaleString() + ffT(" 個詞・") + new Date(p.at || Date.now()).toLocaleDateString()
                    : ffT("沒有安裝・下載約 ") + dict.mb + " MB";
                // (made by an older version of the add-on: what's new comes with installing it again)
                const old = p && dict.ver && (p.ver || 0) < dict.ver;
                if (old) st.textContent += ffT("・舊版的資料，請按「重新安裝」");
                st.classList.toggle("old", !!old);
                inst.textContent = p ? ffT("重新安裝") : ffT("安裝");
                rm.style.display = p ? "" : "none";
                inst.disabled = rm.disabled = busy;
                c.classList.toggle("off", !p && !busy);
            },
            show(f, text) {
                bar.style.display = doing.style.display = "";
                fill.style.width = Math.round(f * 100) + "%";
                doing.textContent = text || "";
            },
            hide() { bar.style.display = doing.style.display = "none"; },
        };
        cards.push(card);

        inst.addEventListener("click", () => {
            if (busy) return;
            // (the sites the files come from; asked here, while the click still counts as yours)
            let asked = Promise.resolve();
            try { asked = browser.permissions.request({ origins: HOSTS }).catch(() => {}); } catch (e) {}
            busy = true; err.textContent = "";
            cards.forEach(x => x.paint());
            asked.then(() => install(dict, card)).catch(e => { err.textContent = String((e && e.message) || e); })
                .then(async () => { busy = false; card.hide(); await refresh(); });
        });
        rm.addEventListener("click", async () => {
            if (busy) return;
            busy = true; cards.forEach(x => x.paint());
            try {
                await ffDB.removeLang(dict.id);
                const left = await ffDB.parts();
                await ffDB.putMerged(Object.keys(left).length ? ffShards.merge(left) : {});
                await changed();
            } catch (e) { err.textContent = String((e && e.message) || e); }
            busy = false; await refresh();
        });
    }
    await refresh();

    async function changed() {
        await ffStore.set({ ffData: Date.now() }).catch(() => {});
        try { await browser.runtime.sendMessage({ op: "dataChanged" }); } catch (e) {}
    }

    /// a file, with its size so far; the copy on GitHub first, else from where it's published
    async function download(dict, s, report) {
        if (s.shared && got.has(s.file)) return got.get(s.file);
        const tryURL = async url => {
            const r = await fetch(url, { cache: "no-store" });
            if (!r.ok) throw new Error(r.status + " " + url);
            const total = Number(r.headers.get("content-length")) || 0;
            const reader = r.body.getReader();
            const chunks = [];
            let n = 0;
            for (;;) {
                const { done, value } = await reader.read();
                if (done) break;
                chunks.push(value); n += value.length;
                report(n, total);
            }
            let buf = await new Blob(chunks).arrayBuffer();
            // (a link on GitHub, expanded/tocfl.csv → tocfl-202307.csv: comes as the name of the file it points to)
            if (buf.byteLength < 300) {
                const t = new TextDecoder().decode(buf).trim();
                if (/^[A-Za-z0-9_./-]+\.(csv|txt|json)$/.test(t)) {
                    const next = new URL(t, url).href;
                    if (next !== url) return tryURL(next);
                }
            }
            return buf;
        };
        const m = ffMirrorURL(dict, s);
        let buf = null, why = "";
        if (m) { try { buf = await tryURL(m); } catch (e) { why = String(e.message || e); } }
        if (!buf) { try { buf = await tryURL(s.url); } catch (e) { why = String(e.message || e); } }
        if (!buf) throw new Error(ffT("下載不到 ") + s.file + "（" + why + "）");
        if (s.shared) got.set(s.file, buf);
        return buf;
    }

    async function install(dict, card) {
        const files = {};
        const list = dict.sources;
        for (let i = 0; i < list.length; i++) {
            const s = list[i];
            if (s.unless && files[s.unless]) continue;
            const mb = x => (x / 1048576).toFixed(1);
            try {
                files[s.file] = await download(dict, s, (n, total) =>
                    card.show(0.4 * (i + (total ? n / total : 0)) / list.length, ffT("下載 ") + s.file + "…" + mb(n) + (total ? " / " + mb(total) : "") + " MB"));
            } catch (e) {
                if (!s.optional) throw e;
            }
            card.show(0.4 * (i + 1) / list.length, "");
        }
        const bundled = {};
        for (const [arg, path] of Object.entries(dict.bundled || {})) {
            bundled[arg] = await fetch(browser.runtime.getURL(path)).then(r => r.ok ? r.text() : null, () => null);
            if (bundled[arg] === null) delete bundled[arg];
        }
        card.show(0.4, ffT("整理資料…"));
        await new Promise((ok, fail) => {
            const w = new Worker("install-worker.js");
            w.onmessage = ev => {
                const m = ev.data || {};
                if (m.op === "progress") card.show(0.4 + 0.6 * m.f, ffT(m.text));
                else if (m.op === "done") { w.terminate(); ok(); }
                else if (m.op === "error") { w.terminate(); fail(new Error(ffT("整理資料的時候出錯：") + m.text)); }
            };
            w.onerror = e => { w.terminate(); fail(new Error(ffT("整理資料的時候出錯：") + (e.message || ""))); };
            w.postMessage({ op: "install", dict, files, bundled });
        });
        await changed();
    }
}
