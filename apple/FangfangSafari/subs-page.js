// 方方詞卡 查詞 → 影片字幕, the part that runs in the page itself (YouTube, Viki): it sees the subtitles the video
// player downloads and hands a copy to the extension, which shows them in its subtitle panel. On YouTube it also
// lists the video's subtitle languages and, when asked, has the player load the one wanted.
// (It reads nothing else and sends nothing anywhere: window.postMessage stays inside the page.)
(() => {
    // (only in the page's own world: in the extension's world the page's downloads can't be seen)
    if (typeof browser !== "undefined" && browser.runtime && browser.runtime.id) return;
    if (window.__ffSubsPage) return;
    window.__ffSubsPage = true;

    const post = (kind, url, text) => { try { window.postMessage({ __ffSubs: 1, kind, url, text }, "*"); } catch (e) {} };
    const looks = url => /timedtext|\.vtt\b|\.srt\b|subtitle|caption/i.test(url || "");

    // a copy of each subtitle file the player downloads
    const fetch0 = window.fetch;
    if (fetch0) window.fetch = function (...a) {
        const p = fetch0.apply(this, a);
        try {
            const url = (a[0] && a[0].url) || String(a[0]);
            if (looks(url)) p.then(r => r.clone().text()).then(t => post("file", url, t)).catch(() => {});
        } catch (e) {}
        return p;
    };
    const open0 = XMLHttpRequest.prototype.open, send0 = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function (m, url, ...rest) {
        try { this.__ffUrl = String(url); } catch (e) {}
        return open0.call(this, m, url, ...rest);
    };
    XMLHttpRequest.prototype.send = function (...a) {
        if (this.__ffUrl && looks(this.__ffUrl)) this.addEventListener("load", () => {
            try {
                if (this.responseType === "" || this.responseType === "text") post("file", this.__ffUrl, this.responseText);
                else if (this.responseType === "json") post("file", this.__ffUrl, JSON.stringify(this.response));
                else if (this.responseType === "arraybuffer") post("file", this.__ffUrl, new TextDecoder().decode(this.response));
            } catch (e) {}
        });
        return send0.apply(this, a);
    };

    // YouTube: the video's subtitle languages; the player loading one of them
    const player = () => document.getElementById("movie_player") || document.querySelector(".html5-video-player");
    function tracks() {
        const p = player();
        let pr = null;
        try { pr = p && p.getPlayerResponse ? p.getPlayerResponse() : null; } catch (e) {}
        pr = pr || window.ytInitialPlayerResponse;
        const list = (pr && pr.captions && pr.captions.playerCaptionsTracklistRenderer &&
            pr.captions.playerCaptionsTracklistRenderer.captionTracks) || [];
        const vid = pr && pr.videoDetails && pr.videoDetails.videoId;
        post("tracks", location.href, JSON.stringify({ vid, tracks: list.map(t => ({
            lang: t.languageCode, kind: t.kind || "", url: t.baseUrl,
            name: (t.name && (t.name.simpleText || (t.name.runs && t.name.runs.map(r => r.text).join("")))) || t.languageCode,
        })) }));
    }
    function use(lang) {
        const p = player();
        if (!p) return;
        try { if (p.loadModule) p.loadModule("captions"); } catch (e) {}
        try { p.setOption("captions", "track", { languageCode: lang }); } catch (e) {}
    }
    window.addEventListener("message", e => {
        const d = e.data;
        if (!d || e.source !== window) return;
        if (d.__ffSubsAsk === "tracks") tracks();
        else if (d.__ffSubsAsk === "use" && d.lang) use(d.lang);
    });
    post("hello", location.href, "");
})();
