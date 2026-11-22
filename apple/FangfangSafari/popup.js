// 方方詞卡 查詞: the small window from the extension's button in Safari's toolbar: the two switches, the words
// chosen to send to the app, and the way to the whole settings page (options.html).
(async () => {
    const d = await ffLoad();
    const { prefs } = d;
    const main = document.getElementById("main");
    const el = ffEl;
    if (!d.ready) main.appendChild(el("div", ffT("還沒有安裝詞典：按下面的「所有設定」，在「詞典」選一個語言安裝。"), "off"));

    // 1. 傳到 App first (no scrolling past the words to reach it)
    const q = d.queue, mins = Object.values(d.watch).reduce((a, x) => a + x, 0);
    let words = null;
    if (q.length || mins >= 1 || Object.keys(d.seen).length) {
        const s = el("div", null, "card");
        s.appendChild(el("div", (q.length ? ffT("選好 ") + q.length + ffT(" 個詞") : "") + (q.length && mins >= 1 ? ffT("・") : "") +
            (mins >= 1 ? ffT("看影片字幕 ") + Math.round(mins) + ffT(" 分鐘") : ""), "note"));
        const b = el("div", null, "btns");
        const send = el("button", ffT("傳到 App"), "act main");
        send.addEventListener("click", async () => {
            const url = await ffSend(q, d.watch, d.seen);
            s.replaceChildren(el("div", ffT("已經傳到方方詞卡。"), "note"));
            // (the words are kept in this link: if the app didn't open, tapping it opens it)
            const a = el("a", ffT("App 沒有打開？點這裡"), "act main");
            a.href = url;
            a.style.cssText = "display:block;text-align:center;text-decoration:none;margin-top:8px";
            s.appendChild(a);
            if (words) words.remove();
        });
        const clr = el("button", ffT("清掉"), "act");
        clr.addEventListener("click", async () => { await ffStore.set({ ffQueue: [] }).catch(() => {}); s.remove(); if (words) words.remove(); });
        b.append(send, clr);
        s.appendChild(b);
        main.appendChild(s);
    }

    // 2. the two switches
    const box = el("div", null, "card");
    const row = (title, sub, key, colour) => {
        const r = el("div", null, "row");
        const w = el("div"); w.append(el("b", title), el("small", sub));
        const sw = ffSwitch(prefs, key);
        sw.style.setProperty("--c", colour);
        r.append(w, sw);
        box.appendChild(r);
    };
    row(ffT("網頁查詞"), ffT("停在詞上跳出卡片"), "on", "#6eaaff");
    row(ffT("影片字幕"), ffT("YouTube、Viki 的字幕面板"), "subs", "#c39bff");
    {   // (介面語言)
        const r = el("div", null, "row");
        const w = el("div"); w.append(el("b", ffT("介面語言")), el("small", "中文 / English"));
        const g = el("div"); g.style.cssText = "display:flex;gap:4px";
        for (const [val, t] of [["zh", "中文"], ["en", "EN"]]) {
            const b = el("button", t, "act"); if ((prefs.uiLang || "zh") === val) b.style.borderColor = "#6eaaff";
            b.addEventListener("click", async () => { prefs.uiLang = val; await ffSave(prefs); location.reload(); });
            g.appendChild(b);
        }
        r.append(w, g); box.appendChild(r);
    }
    main.appendChild(box);

    // 3. 資料夾同步's 立刻同步 (Safari only: not in the Firefox version)
    if (await ffIsSafari()) {
        const sc = el("div", null, "card");
        sc.appendChild(el("div", ffT("資料夾同步：讀所有裝置的備份，再把這裡標的詞存回去。"), "note"));
        const { sb, said } = await ffSyncControls(d, "#ff8cc6", "note");
        sc.append(sb, said);
        main.appendChild(sc);
    }

    // 4. the whole settings page
    const all = el("button", ffT("所有設定"), "act wide");
    all.addEventListener("click", async () => {
        // (a tab of its own: the whole screen, also on an iPad, where the extension's own settings would be a small sheet)
        try { await browser.tabs.create({ url: browser.runtime.getURL("options.html") }); }
        catch (e) { try { await browser.runtime.openOptionsPage(); } catch (e2) { location.href = "options.html"; } }
        window.close();
    });
    main.appendChild(all);
    main.appendChild(el("div", ffT("語言、拼寫、卡片、字幕和認識的詞，都在「所有設定」。"), "note"));

    // 5. the words chosen, last (a long list doesn't push the buttons away)
    if (q.length) {
        words = el("div", null, "card");
        // (by 影片詞組: the words of one video together, as the app will keep them)
        const by = new Map();
        for (const x of q) { const g = x.gn || ""; if (!by.has(g)) by.set(g, []); by.get(g).push(x); }
        for (const [g, xs] of by) {
            words.appendChild(el("div", (g ? ffT("影片：") + g : ffT("其他")) + ffT("（") + xs.length + ffT("）：") + xs.map(x => x.h + (x.w === "saved" ? ffT("（收藏）") : x.w === "known" ? ffT("（認識）") : x.w === "group" ? ffT("（之前選的）") : "")).join(ffT("、")), "words"));
            // (each word's sentence, and under it the line in the second language)
            const seen = new Set();
            for (const x of xs) {
                const sx = (x.x || "").trim();
                if (!sx || seen.has(x.h + "|" + sx)) continue;
                seen.add(x.h + "|" + sx);
                const d2 = el("div", null, "words");
                d2.style.cssText = "margin-top:4px;opacity:0.9";
                d2.appendChild(el("b", x.h + "　"));
                d2.appendChild(document.createTextNode(sx));
                if (x.tr) { d2.appendChild(document.createElement("br")); const e = el("span", x.tr); e.style.opacity = "0.7"; d2.appendChild(e); }
                words.appendChild(d2);
            }
        }
        main.appendChild(words);
    }
})();
