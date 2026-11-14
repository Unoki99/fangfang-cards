// 方方詞卡 查詞: the small window from the extension's button in Safari's toolbar: the two switches, the words
// chosen to send to the app, and the way to the whole settings page (options.html).
(async () => {
    const d = await ffLoad();
    const { prefs } = d;
    const main = document.getElementById("main");
    const el = ffEl;
    if (!d.ready) main.appendChild(el("div", "查詞的資料不在延伸功能裡：在 Mac 上執行一次 install.sh（不要加 nosafari），再安裝一次 App。", "off"));

    // 1. 傳到 App first (no scrolling past the words to reach it)
    const q = d.queue, mins = Object.values(d.watch).reduce((a, x) => a + x, 0);
    let words = null;
    if (q.length || mins >= 1) {
        const s = el("div", null, "card");
        s.appendChild(el("div", (q.length ? "選好 " + q.length + " 個詞" : "") + (q.length && mins >= 1 ? "・" : "") +
            (mins >= 1 ? "看影片字幕 " + Math.round(mins) + " 分鐘" : ""), "note"));
        const b = el("div", null, "btns");
        const send = el("button", "傳到 App", "act main");
        send.addEventListener("click", async () => {
            await ffSend(q, d.watch);
            s.replaceChildren(el("div", "已經傳到方方詞卡。如果 App 沒有打開，請再按一次。", "note"));
            if (words) words.remove();
        });
        const clr = el("button", "清掉", "act");
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
    row("網頁查詞", "停在詞上跳出卡片", "on", "#6eaaff");
    row("影片字幕", "YouTube、Viki 的字幕面板", "subs", "#c39bff");
    main.appendChild(box);

    // 3. the whole settings page
    const all = el("button", "所有設定", "act wide");
    all.addEventListener("click", async () => {
        // (a tab of its own: the whole screen, also on an iPad, where the extension's own settings would be a small sheet)
        try { await browser.tabs.create({ url: browser.runtime.getURL("options.html") }); }
        catch (e) { try { await browser.runtime.openOptionsPage(); } catch (e2) { location.href = "options.html"; } }
        window.close();
    });
    main.appendChild(all);
    main.appendChild(el("div", "語言、拼寫、卡片、字幕和認識的詞，都在「所有設定」。", "note"));

    // 4. the words chosen, last (a long list doesn't push the buttons away)
    if (q.length) {
        words = el("div", null, "card");
        words.appendChild(el("div", "選好的詞（" + q.length + "）：" + q.map(x => x.h + (x.w === "saved" ? "（收藏）" : x.w === "known" ? "（認識）" : "")).join("、"), "words"));
        main.appendChild(words);
    }
})();
