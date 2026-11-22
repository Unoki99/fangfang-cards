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
    // (the settings as tiles side by side, the ones that go together in one grid; a tile: its name, a line about it,
    // and its controls: a switch goes next to the name, a [label, control] pair gets a small label)
    const grid = parent => { const g = el("div", null, "grid"); parent.appendChild(g); return g; };
    const tile = (g, title, sub, controls, wide) => {
        const t = el("div", null, "tile" + (wide ? " wide" : ""));
        const head = el("div", null, "head");
        const w = el("div", null, "what");
        w.appendChild(el("b", title));
        if (sub) w.appendChild(el("small", sub));
        head.appendChild(w);
        let list = Array.isArray(controls) ? controls : (controls ? [controls] : []);
        if (list.length && list[0] && list[0].classList && list[0].classList.contains("switch")) { head.appendChild(list[0]); list = list.slice(1); }
        t.appendChild(head);
        for (const c of list) {
            if (Array.isArray(c)) { t.appendChild(el("label", c[0], "mini")); t.appendChild(c[1]); }
            else t.appendChild(c);
        }
        g.appendChild(t);
        return t;
    };
    const group = (parent, title, lead) => {
        parent.appendChild(el("h3", title, "sub"));
        if (lead) parent.appendChild(el("p", lead, "lead"));
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

    // (the parts that work only with 網頁查詞 or 影片字幕 on: dimmed while it's off)
    const needWeb = [], needSubs = [];
    const paintNeeds = () => {
        for (const x of needWeb) x.classList.toggle("dim", !prefs.on);
        for (const x of needSubs) x.classList.toggle("dim", !prefs.subs);
    };
    const choice = (k, o, colour, f) => { const g = ffChoice(prefs, k, o, f); g.style.setProperty("--c", colour); return g; };
    const onOff = [[true, ffT("開")], [false, ffT("關")]];

    // ── 開關 ──
    const sw = part("switches", ffT("開關"), v("--web"), ffT("兩個功能各有自己的開關：只看影片字幕的話，網頁上停在詞上不會跳出卡片。"));
    const legend = el("div", null, "legend");
    for (const [t, c] of [[ffT("怎麼用"), "--tip"], [ffT("小技巧"), "--good"], [ffT("注意"), "--warn"]]) {
        const s = el("span"); const i = el("i"); i.style.setProperty("--t", v(c)); s.append(i, t); legend.appendChild(s);
    }
    sw.appendChild(legend);
    {   // (the page's own heading, in the language chosen)
        const h = document.querySelector("header h1"), p = document.querySelector("header p");
        if (h) h.textContent = ffT(h.textContent); if (p) p.textContent = ffT(p.textContent);
        document.title = ffT(document.title);
    }
    const swG = grid(sw);
    const webSw = ffSwitch(prefs, "on", () => paintNeeds());
    webSw.style.setProperty("--c", v("--web"));
    tile(swG, ffT("網頁查詞"), ffT("游標或 Apple Pencil 停在一個詞上，就跳出那個詞的卡片"), webSw);
    const subSw = ffSwitch(prefs, "subs", () => { subPart.classList.toggle("dim", !prefs.subs); paintNeeds(); });
    subSw.style.setProperty("--c", v("--subs"));
    tile(swG, ffT("影片字幕"), ffT("YouTube、Viki：影片的字幕在旁邊的面板捲動，點一下字幕裡的詞查詞（停在上面不會跳出來）"), subSw);
    // (介面語言: the add-on's own words in 中文 or English)
    tile(swG, ffT("介面語言"), "中文 / English", choice("uiLang", [["zh", "中文"], ["en", "English"]], v("--web"), () => location.reload()));
    tip(sw, "how", ffT("iPad 用 Apple Pencil 懸停在字上面（不要碰到螢幕），Mac 用觸控板或滑鼠的游標停在字上。沒有懸停的 iPad 和 iPhone：用手指選取一個詞。"));

    // ── 詞典 ──
    dictPart(part("dicts", ffT("詞典"), "#7fd1b9", ffT("查詞要用的詞典。詞典的授權不允許散布改過的版本，所以查詞裡面沒有附詞典：按「安裝」會下載詞典原本的檔案（先從方方詞卡在 GitHub 上的原檔副本，沒有的話從原本發布的地方），在這個瀏覽器裡整理好，存在瀏覽器裡。只會下載詞典的檔案，不會傳出任何東西。")));

    // ── 語言 ──
    const lg = part("languages", ffT("語言"), v("--tw"), ffT("查詞用哪一個語言（一次一個：打開一個，其他的會自己關掉），和它們的讀音、拼寫。顏色和 App 裡每個語言的顏色一樣。"));
    const langs = el("div", null, "langs");
    lg.appendChild(langs);
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
    // (English: the meanings in English, and English words looked up in Chinese, on the page and in the subtitles)
    group(lg, ffT("英文"), ffT("英文的解釋，和從英文查中文。"));
    const enG = grid(lg);
    tile(enG, ffT("英文解釋"), ffT("卡片和字幕下面的意思用英文"), choice("en", [[false, ffT("不顯示")], [true, ffT("顯示")]], v("--tw")));
    tile(enG, ffT("英文查中文"), ffT("游標停在英文字上，找中文的詞"), choice("en2zh", onOff, v("--tw")));
    needSubs.push(tile(enG, ffT("英文字幕下面標中文"), ffT("英文的字幕：每個英文字下面標它的中文（照開著的語言：華語、台語、粵語或客語）"), choice("subsEnZh", onOff, v("--tw"))));

    // ── 聲調顏色 ──
    const cl = part("colours", ffT("聲調顏色和標記"), "#4fd8c4", ffT("字照聲調上色（和 App 選的顏色一樣）。卡片、字幕和網頁各有自己的開關。"));
    const clG = grid(cl);
    const cc = "#4fd8c4";
    tile(clG, ffT("卡片"), ffT("跳出來的卡片裡的字和讀音"), choice("colours", onOff, cc));
    needSubs.push(tile(clG, ffT("字幕"), ffT("字幕面板裡的字和讀音"), choice("subsColours", onOff, cc)));
    needWeb.push(tile(clG, ffT("網頁上的字"), ffT("網頁上的中文字照聲調上色"), choice("tint", [[false, ffT("不上色")], ["saved", ffT("收藏的詞")], ["all", ffT("全部（華語）")]], cc)));
    needWeb.push(tile(clG, ffT("網頁上不認識的詞"), ffT("像字幕一樣：不認識的詞上面標讀音、下面標意思，字照聲調上色（哪些詞照「字幕 → 標哪些詞」）"),
        choice("pageAnno", [[false, ffT("不標")], ["both", ffT("讀音和意思")], ["rd", ffT("只有讀音")], ["gl", ffT("只有意思")]], cc)));
    const onlySw = ffSwitch(prefs, "onlyNew");
    onlySw.style.setProperty("--c", cc);
    tile(clG, ffT("只替標出來的詞上色"), ffT("其他的詞不上聲調顏色（網頁上也是：只有不認識的詞有顏色）"), onlySw);
    needWeb.push(tile(clG, ffT("收藏的詞"), ffT("網頁上出現收藏過的詞時"), choice("ring", [[false, ffT("不標")], [true, ffT("彩虹框")]], cc)));
    tip(cl, "warn", ffT("「全部」會替整頁的字上色，很長的網頁可能會慢一點。"));

    // ── 卡片 ──
    const cd = part("card", ffT("卡片"), v("--card"), ffT("跳出來的卡片長什麼樣子。"));
    const cdG = grid(cd);
    tile(cdG, ffT("字的大小"), null, choice("font", FF_SIZES, v("--card")), true);
    tile(cdG, ffT("位置"), ffT("卡片出現在哪裡"), choice("pos", [["word", ffT("詞的旁邊")], ["tl", ffT("左上角")], ["tr", ffT("右上角")], ["bl", ffT("左下角")], ["br", ffT("右下角")]], v("--card")));
    const reset = el("button", ffT("大小還原"), "act");
    reset.addEventListener("click", () => { prefs.w = 0; prefs.h = 0; ffSave(prefs); reset.textContent = ffT("還原了"); });
    const resetRow = el("div", null, "btns"); resetRow.appendChild(reset);
    tile(cdG, ffT("卡片大小"), ffT("拖拉卡片右下角可以改大小"), resetRow);

    // ── 鍵盤 ──
    const kb = part("keys", ffT("鍵盤"), "#ffe066", ffT("游標（觸控板、滑鼠或 Pencil）停在一個詞上，按一個鍵就標記它，不用打開卡片。網頁和影片字幕上都可以。"));
    const kbG = grid(kb);
    const kSw = ffSwitch(prefs, "keys"); kSw.style.setProperty("--c", "#ffe066");
    tile(kbG, ffT("用鍵盤標記"), null, kSw);
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
    tile(kbG, ffT("認識"), ffT("標成認識：馬上不上色（只替不認識的詞上色開著的話），傳到 App 時變成熟悉"), keyBox("keyKnown"));
    tile(kbG, ffT("不熟＋收藏"), ffT("加到不熟，也收藏（連同那一句話）"), keyBox("keyNew"));
    tip(kb, "how", ffT("游標停在詞上按鍵，旁邊會跳出一個小提示說標了什麼。標的是卡片上第一個語言的那個詞。按「傳到 App」的時候一起傳過去。"));
    tip(kb, "warn", ffT("YouTube 自己用 K、J、L 和數字鍵控制影片，所以預設是 A 和 S。游標沒有停在詞上的時候，按鍵照網站原本的用法。"));

    // ── 影片字幕 ──
    const subPart = part("subs", ffT("影片字幕"), v("--subs"), ffT("在 YouTube 和 Viki 看影片時，字幕出現在旁邊（iPhone 在下面），說到哪一句就亮到哪一句。"));
    if (!prefs.subs) subPart.classList.add("dim");
    const sc = (k, o, f) => choice(k, o, v("--subs"), f);
    // (the panel: where, how big, how it looks)
    group(subPart, ffT("面板"));
    const pG = grid(subPart);
    tile(pG, ffT("位置"), ffT("旁邊往上捲，或下面一行往旁邊流（全螢幕時一定在下面）"), sc("subsFlow", [[false, ffT("旁邊")], [true, ffT("下面")]]));
    tile(pG, ffT("大小"), ffT("面板上的 A− A+ 也可以調"), sc("subsFont", FF_SIZES));
    tile(pG, ffT("面板的底"), ffT("黑色；跟著底下的畫面：用底下大部分的顏色（太亮的會調暗）；沒有底：只看得到字幕一句一句的框、按鈕和詞卡"), sc("subsBg", [["dark", ffT("黑色")], ["tint", ffT("跟著底下的畫面")], ["clear", ffT("沒有底")]]));
    tile(pG, ffT("影片上原本的字幕"), ffT("面板開著的時候"), sc("subsHideVideo", [[true, ffT("隱藏")], [false, ffT("顯示")]]));
    tile(pG, ffT("查詞時影片暫停"), ffT("點字幕的詞時（卡片關掉後繼續）"), sc("subsPause", onOff));
    tile(pG, ffT("字幕在下面橫排時的詞卡"), ffT("畫面最上面一排一樣大小的詞卡：正在說的這一句標出來的詞"), sc("subsDefs", [[true, ffT("顯示")], [false, ffT("不顯示")]]));
    // (which subtitles: their language, the script, a second language under them)
    group(subPart, ffT("字幕的語言"));
    const lG = grid(subPart);
    tile(lG, ffT("字幕的語言"), ffT("讀音、意思、聲調顏色和生詞用哪個語言的詞典。自動：跟著上面開著的那一個語言（瑞典語的話，看字幕本身的語言）"), sc("subsLang", [["auto", ffT("自動（跟查詞的語言）")], ["zh", ffT("華語")], ["tw", ffT("台語")], ["yue", ffT("粵語")], ["hak", ffT("客語")]]));
    tile(lG, ffT("簡體字幕"), ffT("簡體的字幕轉成繁體（照詞典的詞：头发 → 頭髮），認識的詞也照繁體認得"), sc("subsTrad", [[true, ffT("轉成繁體")], [false, ffT("照原樣")]]));
    tile(lG, ffT("第二種語言"), ffT("每一行下面用小小的灰色字顯示另一種語言（例如英文），影片有那個語言的字幕才會出現。在字幕面板上選。"), sc("subs2", [["", ffT("不顯示")], ["en", "English"], ["zh-hant", ffT("繁體中文")], ["zh-hans", ffT("簡體中文")], ["ja", "日本語"], ["ko", "한국어"]]));

    // (標出來的詞: which words of the subtitles get their reading, meaning and colour)
    group(subPart, ffT("標出來的詞"), ffT("字幕裡哪些詞上面標讀音、下面標意思、有聲調顏色（詞卡和「有生詞才停」也照這個）。"));
    const mG = grid(subPart);
    tile(mG, ffT("標哪些詞"), ffT("不認識：還沒在 App 標成熟悉的詞；不常用：不在最常用的那些詞裡面（不管認不認識）"), sc("subsMark", [["new", ffT("不認識的詞")], ["rare", ffT("不常用的詞")], ["both", ffT("不認識又不常用的詞")]], () => paintRare()), true);
    const rareRow = tile(mG, ffT("多不常用才標"), ffT("和 App 裡每個詞旁邊的常用度（五格）一樣：選的那一級以下的詞才標"), rareChoice(), true);
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
    // (the reading over them and the meaning under them: each with its size)
    tile(mG, ffT("上面標讀音"), ffT("注音或拼音（照華語的設定），也有聲調顏色"), [sc("subsRd", onOff),
        [ffT("讀音的大小"), sc("subsRdSize", [[0.25, ffT("最小")], [0.32, ffT("很小")], [0.4, ffT("小一點")], [0.45, ffT("小")], [0.56, ffT("中")], [0.7, ffT("大")], [0.85, ffT("更大")], [1, ffT("和字一樣")]])]]);
    tile(mG, ffT("下面標意思"), prefs.en ? ffT("現在是英文（語言裡的「英文」開著）") : ffT("現在是中文（語言裡的「英文」打開就變英文）"), [sc("subsGl", onOff),
        [ffT("意思的大小"), sc("subsGlSize", [[0.25, ffT("最小")], [0.32, ffT("很小")], [0.4, ffT("小一點")], [0.5, ffT("中")], [0.6, ffT("大")], [0.75, ffT("更大")]])]]);
    subPart.appendChild(el("p", ffT("字幕的聲調顏色在上面的「聲調顏色和標記」。"), "lead"));

    group(subPart, ffT("面板上的學習工具"));
    const tools = el("div", null, "tools");
    for (const [b, t] of [[ffT("上一句"), ffT("回到上一句")], [ffT("重複"), ffT("一直重複這一句，練聽和跟讀")], [ffT("慢速"), ffT("放慢到 0.75 倍")],
        [ffT("一句一停"), ffT("每一句說完就暫停，按播放再說下一句（跟讀用）")], [ffT("下一句"), ffT("跳到下一句")], [ffT("讀音"), ffT("標出來的詞上面標讀音")], [ffT("生詞"), ffT("一個大視窗列出影片裡所有還不認識的詞：點你認識的，再按確定（或確定，其他都加到不熟）")], [ffT("意思"), ffT("標出來的詞下面標意思")], [ffT("懂 87%"), ffT("你認識這部影片多少的詞（要先從 App 傳認識的詞過來）")]]) {
        const x = el("div", null, "tool"); x.append(el("b", b), el("span", t)); tools.appendChild(x);
    }
    subPart.appendChild(tools);
    tip(subPart, "how", ffT("點每一行前面的時間會跳到那裡。用手指拖（或捲動）可以往前往後看，幾秒後會自己跟回影片。"));
    tip(subPart, "how", ffT("「不認識」是還沒在 App 裡標成熟悉的詞（用 A 標認識以後，讀音和意思就會拿掉）。還沒從 App 傳認識的詞過來時，每個詞都會標。"));
    tip(subPart, "good", ffT("在 YouTube 字幕語言可以選「自動翻譯」：影片沒有中文字幕時，會自己用自動翻譯成繁體中文。"));
    tip(subPart, "warn", ffT("iPhone 上影片全螢幕時看不到面板（全螢幕是 iOS 自己的播放器），要在網頁裡看。"));
    paintNeeds();

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

    // HSK／TOCFL 懂多少: each level of the word list, how many of its words are 認識 and 不熟 (from the app's words,
    // and the ones marked 認識 here)
    // (installed here, or, in Safari, made with the app on the Mac and inside the add-on)
    let lv = await ffDB.get("d-levels.json").catch(() => null);
    if (!lv) lv = await fetch(browser.runtime.getURL("d-levels.json")).then(r => r.ok ? r.json() : null, () => null).catch(() => null);
    const fromMac = !(await fetch(browser.runtime.getURL("install/common.js")).then(r => r.ok, () => false));
    kn.appendChild(el("h3", ffT("HSK／TOCFL 懂多少"), "sub"));
    if (!lv) {
        kn.appendChild(el("p", fromMac ? ffT("要在 Mac 上重新執行一次安裝（install.sh），查詞裡才會有每一級的詞。")
            : ffT("要先安裝（或重新安裝）「詞典」裡的華語，才看得到每一級的詞。"), "lead"));
    } else {
        const local = (await ffStore.get(["ffKnownLocal"]).catch(() => ({}))).ffKnownLocal || [];
        const knownZh = new Set([...((k && k.k && k.k.zh) || []), ...local.filter(x => !/^[a-z]+:/.test(x) || x.startsWith("zh:")).map(x => x.replace(/^zh:/, ""))]);
        const learnZh = new Set((k && k.u && k.u.zh) || []);
        const box = el("div");
        if (prefs.levelList !== "y") prefs.levelList = "x";
        const listSw = ffChoice(prefs, "levelList", [["x", "HSK 3.0"], ["y", "TOCFL"]], () => draw());
        kn.append(listSw, box);
        const names = { x: l => l >= 7 ? "HSK 7–9" : "HSK " + l,
            y: l => "TOCFL " + (["", "準備一級", "準備二級", "入門級", "基礎級", "進階級", "高階級", "流利級"][l] || l) };
        const draw = () => {
            box.replaceChildren();
            const which = prefs.levelList === "y" ? "y" : "x";
            const by = new Map();
            for (const [h, l0] of Object.entries(lv[which] || {})) {
                const l = which === "x" ? Math.min(l0, 7) : l0;
                if (!by.has(l)) by.set(l, [0, 0, 0]);
                const c = by.get(l);
                c[0]++;
                if (knownZh.has(h)) c[1]++; else if (learnZh.has(h)) c[2]++;
            }
            const g = el("div", null, "grid");
            let all = [0, 0, 0];
            for (const l of [...by.keys()].sort((a, b) => a - b)) {
                const [n, kk, uu] = by.get(l);
                all = [all[0] + n, all[1] + kk, all[2] + uu];
                const t = el("div", null, "tile");
                const hd = el("div", null, "head");
                const w = el("div", null, "what");
                w.append(el("b", ffT(names[which](l))), el("small", n + ffT(" 個詞")));
                hd.append(w, el("b", Math.round(100 * kk / Math.max(1, n)) + "%"));
                const bar = el("div"); bar.style.cssText = "display:flex;height:10px;border-radius:5px;overflow:hidden;background:#2e3039";
                const a = el("div"); a.style.cssText = "background:var(--known);width:" + (100 * kk / Math.max(1, n)) + "%";
                const b = el("div"); b.style.cssText = "background:#e8c547;opacity:.75;width:" + (100 * uu / Math.max(1, n)) + "%";
                bar.append(a, b);
                t.append(hd, bar, el("small", ffT("認識 ") + kk + ffT("　不熟 ") + uu + ffT("　還沒學 ") + (n - kk - uu)));
                g.appendChild(t);
            }
            box.append(el("p", ffT("全部：認識 ") + all[1] + " / " + all[0] + "（" + Math.round(100 * all[1] / Math.max(1, all[0])) + "%）", "lead"), g);
        };
        draw();
    }
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
    if (q.length || mins >= 1 || Object.keys(d.seen).length) {
        const b = el("div", null, "btns");
        const send = el("button", ffT("傳到 App"), "act main");
        send.style.setProperty("--c", v("--send"));
        send.addEventListener("click", async () => {
            const url = await ffSend(q, d.watch, d.seen);
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
            // (the sentences that go with them: the line, and under it the line in the second language)
            const seen = new Set();
            for (const x of xs) {
                const sx = (x.x || "").trim();
                if (!sx || seen.has(x.h + "|" + sx)) continue;
                seen.add(x.h + "|" + sx);
                const p = el("p", null, "lead");
                p.style.cssText = "margin:6px 0 0;font-size:13px";
                p.appendChild(el("b", x.h + "　"));
                p.appendChild(document.createTextNode(sx));
                if (x.tr) { p.appendChild(document.createElement("br")); const e = el("span", x.tr); e.style.opacity = "0.7"; p.appendChild(e); }
                sd.appendChild(p);
            }
        }
    } else sd.appendChild(el("p", ffT("還沒有選詞。"), "lead"));
    tip(sd, "warn", ffT("Safari 會先問要不要打開方方詞卡：按「打開」。App 沒有打開的話再按一次。"));
    tip(sd, "how", ffT("Android 的 Firefox：按「傳到 App」會打開 Android 的方方詞卡（Firefox 可能先問要不要打開）。沒有打開的話，按旁邊的「App 沒有打開？點這裡」。"));

    // ── 連到方方詞卡（Windows）: YouTube songs' lyrics in the program (Firefox only: not in Safari) ──
    if (!(await ffIsSafari())) {
        const pc = part("pc", ffT("連到方方詞卡（Windows）"), "#ff9f5a",
            ffT("在 YouTube 或 YouTube Music 放歌的時候，Windows 版方方詞卡的「歌詞」會跟著歌走：查詞、讀音，從 App 裡跳到別的地方、暫停、重複一句。"));
        const pcG = grid(pc);
        const ORIGINS = { origins: ["http://127.0.0.1/*"] };
        const pcSw = el("button", null, "switch");
        pcSw.setAttribute("role", "switch");
        pcSw.style.setProperty("--c", "#ff9f5a");
        const status = el("p", "", "lead");
        const paint = () => { pcSw.classList.toggle("on", !!prefs.pcLink); pcSw.setAttribute("aria-checked", prefs.pcLink ? "true" : "false"); };
        // (Firefox asks once for the permission, only to 127.0.0.1: asked right in the tap, as Firefox wants it)
        pcSw.addEventListener("click", () => {
            if (prefs.pcLink) {
                prefs.pcLink = false; ffSave(prefs); paint(); check();
                browser.permissions.remove(ORIGINS).catch(() => {});
                return;
            }
            browser.permissions.request(ORIGINS).then(ok => {
                if (!ok) { status.textContent = ffT("沒有允許：查詞不能連到這台電腦上的方方詞卡。"); return; }
                prefs.pcLink = true; ffSave(prefs); paint(); check();
            }, () => { status.textContent = ffT("沒有允許：查詞不能連到這台電腦上的方方詞卡。"); });
        });
        paint();
        tile(pcG, ffT("連到方方詞卡（Windows）"), ffT("只傳給這台電腦上的方方詞卡（127.0.0.1），不會傳到網路上"), pcSw);
        pc.appendChild(status);
        // (whether the program answers: checked every few seconds while this page is open)
        const check = () => {
            if (!prefs.pcLink) { status.textContent = ffT("關著。"); return; }
            browser.runtime.sendMessage({ op: "pcNow", now: { ping: true } }).then(r => {
                status.textContent = r && r.ok ? ffT("連上了：方方詞卡開著。在 YouTube 放一首歌，打開方方詞卡的「電台 → YouTube 歌詞」。")
                    : ffT("找不到方方詞卡：在這台電腦上打開 Windows 版的方方詞卡（開著的時候才連得上）。");
            }, () => { status.textContent = ffT("找不到方方詞卡。"); });
        };
        check();
        setInterval(check, 4000);
        tip(pc, "how", ffT("打開開關的時候 Firefox 會問可不可以連到 127.0.0.1（這台電腦自己）：按「允許」。查詞只傳正在放的歌是哪一首、放到哪裡，給這台電腦上的方方詞卡；方方詞卡只回傳你在它那裡按的（跳到哪裡、暫停、播放、速度）。"));
        tip(pc, "good", ffT("歌單用 YouTube 自己的：一首放完接下一首，方方詞卡的歌詞也會自己換。"));
    }

    // ── 資料夾同步 (Safari only: not in the Firefox version) ──
    if (await ffIsSafari()) {
        const fo = part("folder", ffT("資料夾同步"), v("--send"),
            ffT("和 App 用同一個備份資料夾（iCloud Drive、OneDrive、Google 雲端硬碟…）：讀所有裝置的備份，你在每個裝置認識和不熟的詞這裡都會用；這裡選的詞也可以存一個檔案到那個資料夾，App 同步的時候會讀進去。"));
        const { safari, direct, sb, fb, said } = await ffSyncControls(d, v("--send"), "lead");
        fo.append(sb, fb, said);
        if (d.known && d.known.from === "folder" && d.known.at) {
            fo.appendChild(el("p", ffT("上次讀資料夾：") + new Date(d.known.at).toLocaleString(), "lead"));
        }
        tip(fo, "how", ffIOS ? ffT("按「立刻同步」，在「檔案」打開 App 的備份資料夾，按「選擇」→「全選」→「打開」：查詞把所有裝置的詞合起來（每個詞以最後改的為準）。再按「存回資料夾」→「儲存到檔案」→ 選同一個資料夾 →「儲存」，問的時候按「取代」。")
            : safari ? ffT("按「立刻同步」，選 App 的備份資料夾裡所有的方方詞卡檔案：查詞把所有裝置的詞合起來（每個詞以最後改的為準），再下載自己的檔案（方方詞卡-查詞-Safari-….json）。")
            : direct ? ffT("「立刻同步」第一次會問要用哪個資料夾：選 App 的備份資料夾，按「允許」讓它讀寫。之後按一下就會讀所有裝置的備份，再把這裡選的詞存進去。")
            : ffT("「立刻同步」會先讀資料夾（選 App 的備份資料夾），再存這裡選的詞（瀏覽器問存在哪裡的時候選同一個資料夾）。"));
        if (safari && !ffIOS) tip(fo, "good", ffT("讓下載的檔案直接進備份資料夾：Safari 設定 → 一般 → 檔案下載位置 → 選 App 的備份資料夾。App 同步的時候會讀它，同一個查詞存了好幾個的話只留最新的。"));
        tip(fo, "how", ffT("按「讀資料夾」，選 App 的備份資料夾（App 的 設定 → 備份 裡選的那一個），瀏覽器會問可不可以讀：按「上傳」或「允許」（檔案不會離開你的電腦）。"));
        tip(fo, "good", ffT("要讓「存到資料夾」直接存在那個資料夾：在瀏覽器的設定把下載改成「每次都問要存在哪裡」，存的時候選那個資料夾。之後存一樣的檔名就會蓋過舊的。"));
        tip(fo, "warn", ffT("存的檔案有在這裡標過的所有詞（傳到 App 以後也還在），每個詞記著是什麼時候標的，所以每個裝置同步的時候都以最後改的為準。"));
    }
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
