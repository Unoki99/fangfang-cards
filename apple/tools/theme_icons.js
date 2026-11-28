// Theme app icons: the same 方 and its ring of tone marks, in each theme's night
const fs = require("fs");
function rnd(seed) { let s = seed; return () => (s = (s * 16807) % 2147483647) / 2147483647; }
const marks = (o = 1) => `
<g stroke-linecap="round" stroke-width="36" filter="url(#mg)" opacity="${o}">
 <line x1="511" y1="122" x2="511" y2="212" stroke="#ff6a6a"/>
 <line x1="732" y1="226" x2="782" y2="310" stroke="#c39bff"/>
 <line x1="268" y1="222" x2="268" y2="312" stroke="#ff8ac8"/>
 <line x1="120" y1="512" x2="214" y2="512" stroke="#ffd95a"/>
 <line x1="222" y1="756" x2="314" y2="756" stroke="#4fd8c4"/>
 <line x1="538" y1="814" x2="486" y2="902" stroke="#6ad97a"/>
 <circle cx="857" cy="512" r="26" fill="#6aa8ff" stroke="none"/>
 <circle cx="756" cy="756" r="26" fill="#ffa24a" stroke="none"/>
</g>`;
const glyph = (fill, glow) => `
<text x="512" y="700" text-anchor="middle" font-family="Noto Sans CJK TC" font-weight="500" font-size="470" fill="${glow}" filter="url(#gl)" opacity=".9">方</text>
<text x="512" y="700" text-anchor="middle" font-family="Noto Sans CJK TC" font-weight="500" font-size="470" fill="${fill}">方</text>`;
const defs = (bgA, bgB, extra = "") => `<defs>
<radialGradient id="bg" cx="50%" cy="40%" r="75%"><stop offset="0" stop-color="${bgA}"/><stop offset="1" stop-color="${bgB}"/></radialGradient>
<filter id="gl" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="14"/></filter>
<filter id="mg" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur in="SourceGraphic" stdDeviation="5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
<filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="40"/></filter>
<filter id="tiny" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="3"/></filter>
${extra}</defs><rect width="1024" height="1024" fill="url(#bg)"/>`;
const stars = (n, seed, col = "#fff", max = 3.2) => { const r = rnd(seed); let s = ""; for (let i = 0; i < n; i++) { const x = r() * 1024, y = r() * 1024, rr = 0.8 + r() * max, o = 0.25 + r() * 0.6; s += `<circle cx="${x.toFixed(0)}" cy="${y.toFixed(0)}" r="${rr.toFixed(1)}" fill="${col}" opacity="${o.toFixed(2)}"/>`; } return s; };
const flower = (x, y, s, col, rot = 0) => { let p = `<g transform="translate(${x} ${y}) rotate(${rot}) scale(${s})">`; for (let i = 0; i < 5; i++) p += `<ellipse cx="0" cy="-15" rx="10" ry="15" fill="${col}" transform="rotate(${i * 72})"/>`; return p + `<circle r="5" fill="#ffe08a"/></g>`; };
const petal = (x, y, s, rot, col) => `<path d="M0,-12 C9,-6 9,8 0,13 C-9,8 -9,-6 0,-12Z" fill="${col}" transform="translate(${x} ${y}) rotate(${rot}) scale(${s})" opacity=".85"/>`;
const maple = (x, y, s, rot, col) => `<g transform="translate(${x} ${y}) rotate(${rot}) scale(${s})"><path d="M0,-40 L8,-22 L22,-30 L18,-10 L38,-12 L28,2 L40,12 L18,14 L22,30 L4,20 L2,40 L-2,40 L-4,20 L-22,30 L-18,14 L-40,12 L-28,2 L-38,-12 L-18,-10 L-22,-30 L-8,-22 Z" fill="${col}"/><line x1="0" y1="40" x2="0" y2="56" stroke="${col}" stroke-width="4" stroke-linecap="round"/></g>`;
const flake = (x, y, s, o = .85) => { let g = `<g transform="translate(${x} ${y}) scale(${s})" stroke="#eef6ff" stroke-width="3" stroke-linecap="round" opacity="${o}">`; for (let i = 0; i < 6; i++) g += `<g transform="rotate(${i * 60})"><line x1="0" y1="0" x2="0" y2="-20"/><line x1="0" y1="-12" x2="6" y2="-17"/><line x1="0" y1="-12" x2="-6" y2="-17"/></g>`; return g + `</g>`; };
const mushroom = (x, y, s, cap) => `<g transform="translate(${x} ${y}) scale(${s})"><path d="M-14,0 C-16,-30 -10,-46 0,-48 C10,-46 16,-30 14,0 Z" fill="#efe4cc"/><path d="M-62,-40 C-56,-92 56,-92 62,-40 C40,-34 -40,-34 -62,-40Z" fill="${cap}"/><circle cx="-28" cy="-62" r="8" fill="#fff4e6"/><circle cx="8" cy="-72" r="7" fill="#fff4e6"/><circle cx="34" cy="-52" r="6" fill="#fff4e6"/></g>`;

const T = {};
T.night = { name: "方方之夜", svg: defs("#323236", "#161618") + marks() + glyph("#f2f2f2", "#ffffff") };
T.witch = { name: "女巫小屋", svg: defs("#3d2a19", "#110c08",
  `<radialGradient id="flame" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#ffd27a" stop-opacity=".55"/><stop offset="1" stop-color="#ffb347" stop-opacity="0"/></radialGradient>`)
  + stars(40, 7, "#ffe9b8", 2)
  + `<circle cx="150" cy="880" r="210" fill="url(#flame)"/>`
  + `<g transform="translate(905 118)"><circle r="58" fill="#f6e6b8" filter="url(#tiny)" opacity=".35"/><path d="M14,-52 A54,54 0 1,0 14,52 A42,42 0 1,1 14,-52Z" fill="#f6e6b8"/></g>`
  + `<g transform="translate(118 950)"><rect x="-22" y="-120" width="44" height="120" rx="8" fill="#efe1c2"/><path d="M-22,-110 q10,18 0,34" stroke="#d8c7a2" stroke-width="5" fill="none"/><line x1="0" y1="-120" x2="0" y2="-134" stroke="#3a2a1c" stroke-width="4"/><path d="M0,-176 C14,-156 12,-140 0,-134 C-12,-140 -14,-156 0,-176Z" fill="#ffc861"/><path d="M0,-162 C6,-152 5,-144 0,-140 C-5,-144 -6,-152 0,-162Z" fill="#fff3c4"/></g>`
  + marks() + glyph("#f4ead5", "#ffb347") };
T.space = { name: "星空", svg: defs("#1b2152", "#04050c")
  + `<ellipse cx="820" cy="210" rx="260" ry="150" fill="#7a5cff" opacity=".22" filter="url(#soft)"/><ellipse cx="190" cy="830" rx="240" ry="140" fill="#2f8f86" opacity=".18" filter="url(#soft)"/>`
  + stars(150, 3, "#ffffff", 2.6)
  + `<g transform="translate(880 900)"><circle r="46" fill="#c9a43a"/><circle r="46" fill="url(#bg)" opacity=".25"/><ellipse rx="88" ry="20" fill="none" stroke="#ffe9a8" stroke-width="7" transform="rotate(-20)" opacity=".85"/></g>`
  + marks() + glyph("#eef1ff", "#8fb0ff") };
T.goblin = { name: "苔蘚小窩", svg: defs("#2c2e19", "#0d0e08")
  + stars(30, 11, "#d9f28a", 2.4)
  + `<path d="M0,1024 L0,930 C80,880 150,915 220,895 C300,872 360,925 450,910 C560,892 620,935 720,915 C820,895 900,930 1024,900 L1024,1024Z" fill="#3e5a1f"/>`
  + `<path d="M0,1024 L0,965 C110,940 200,975 320,955 C460,935 560,980 700,960 C840,942 930,975 1024,955 L1024,1024Z" fill="#577a2a"/>`
  + `<ellipse cx="610" cy="975" rx="34" ry="20" fill="#8c8673"/><ellipse cx="660" cy="985" rx="22" ry="14" fill="#a39d88"/>`
  + mushroom(150, 940, 1.25, "#c8432f") + mushroom(880, 960, 0.8, "#d9822b")
  + marks() + glyph("#eee8d2", "#cfe39a") };
T.winter = { name: "雪夜", svg: defs("#2a3a50", "#0a0f17")
  + stars(60, 5, "#ffffff", 3.4)
  + flake(140, 150, 1.6) + flake(900, 140, 1.2, .7) + flake(80, 640, 1.0, .6) + flake(940, 640, 1.4, .8) + flake(660, 120, 0.9, .5)
  + `<path d="M0,1024 L0,900 C120,860 230,905 360,885 C500,862 600,915 740,895 C870,876 950,905 1024,885 L1024,1024Z" fill="#dfe9f5"/>`
  + `<path d="M0,1024 L0,955 C150,930 280,965 440,948 C600,930 760,970 1024,945 L1024,1024Z" fill="#f4f8fd"/>`
  + marks() + glyph("#eef5ff", "#9cc8ff") };
T.sakura = { name: "夜櫻", svg: defs("#3b2130", "#130b0f")
  + stars(40, 9, "#ffd3e6", 2)
  + `<path d="M-20,90 C120,120 210,170 300,140 C360,120 400,70 470,60" stroke="#4a2c22" stroke-width="22" fill="none" stroke-linecap="round"/>`
  + flower(120, 100, 2.2, "#ffc3d9", 10) + flower(300, 140, 1.8, "#ffd6e5", 30) + flower(420, 68, 1.5, "#ffb3cf", 5) + flower(40, 160, 1.4, "#ffd6e5", 20)
  + petal(860, 300, 2, 30, "#ffb8d2") + petal(930, 560, 1.6, -40, "#ffd0e2") + petal(820, 860, 2.2, 70, "#ffb8d2") + petal(380, 930, 1.5, -20, "#ffd0e2") + petal(110, 400, 1.4, 50, "#ffb8d2") + petal(640, 960, 1.3, 10, "#ffc6dc")
  + marks() + glyph("#fdeff4", "#ff9fcb") };
T.momiji = { name: "紅葉狩", svg: defs("#3b1f12", "#110906")
  + stars(25, 13, "#ffd9a8", 2)
  + maple(130, 130, 1.5, -20, "#d2552b") + maple(900, 180, 1.1, 25, "#e8922e") + maple(905, 880, 1.6, 40, "#c8402a") + maple(130, 900, 1.2, -35, "#f0b23a") + maple(640, 930, 0.9, 10, "#d2552b") + maple(90, 620, 0.8, 15, "#e8922e")
  + marks() + glyph("#f9ece2", "#ff9a5c") };

const order = ["night", "witch", "space", "goblin", "winter", "sakura", "momiji"];
const icon = k => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">${T[k].svg.replace(/id="(\w+)"/g, `id="${k}-$1"`).replace(/url\(#(\w+)\)/g, `url(#${k}-$1)`)}</svg>`;
for (const k of order) fs.writeFileSync(`icon-${k}.svg`, icon(k));
const sheet = `<html><body style="margin:0;background:#0f0d0c;font-family:'Noto Sans CJK TC';color:#e8ddd6">
<div style="padding:40px 40px 20px;font-size:30px;font-weight:600">方方詞卡 · theme icons</div>
<div style="display:grid;grid-template-columns:repeat(4,240px);gap:40px 44px;padding:10px 40px 50px">
${order.map(k => `<div style="text-align:center"><div style="width:240px;height:240px;border-radius:54px;overflow:hidden;box-shadow:0 10px 30px rgba(0,0,0,.6)">${icon(k).replace('width="1024" height="1024"', 'width="240" height="240"')}</div><div style="margin-top:14px;font-size:22px">${T[k].name}</div></div>`).join("")}
</div></body></html>`;
fs.writeFileSync("sheet.html", sheet);
