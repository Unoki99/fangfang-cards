// 客語: 教育部《臺灣客語辭典》's six files (one per accent, "…腔詞條詞目文字.ods") → hak.json. The same as
// tools/build_hakka.py (see there for the file's shape); the dictionary's licence (CC BY-ND 3.0 TW) doesn't allow
// sharing changed versions, so each phone (or computer) makes its own copy from the original files.
//   buildHakka({src: dir with the .ods files, out: hak.json, essay: essay.txt or null, cedict: cedict_ts.u8 or null})
"use strict";

function buildHakka(a) {
    const ACCENTS = ["四縣", "海陸", "大埔", "饒平", "詔安", "南四縣"];
    const SUP = "⁰¹²³⁴⁵⁶⁷⁸⁹", SUB = "₀₁₂₃₄₅₆₇₈₉";

    // the files
    const files = new Map();
    for (const name0 of host.list(a.src)) {
        if (!name0.toLowerCase().endsWith(".ods")) continue;
        const n = name0.normalize("NFC");
        for (const i of [5, 0, 1, 2, 3, 4]) {
            if (n.includes(ACCENTS[i]) && !files.has(i)) { files.set(i, a.src + "/" + name0); break; }
        }
    }
    if (!files.has(0)) throw new Error("找不到四縣腔的檔案");

    // tones: value → [category, mark], per accent
    const TONE_DEFAULT = [
        [["24", [1, "ˊ"]], ["31", [2, "ˋ"]], ["55", [3, ""]], ["2", [4, "ˋ"]], ["11", [5, "ˇ"]], ["5", [8, ""]]],
        [["53", [1, "ˋ"]], ["24", [2, "ˊ"]], ["11", [3, "ˇ"]], ["5", [4, ""]], ["55", [5, ""]], ["33", [7, "+"]], ["2", [8, "ˋ"]]],
        [["33", [1, "+"]], ["35", [1, "ˊ"]], ["31", [2, "^"]], ["53", [3, "ˋ"]], ["21", [4, "^"]], ["113", [5, "ˇ"]], ["54", [8, "ˋ"]]],
        [["11", [1, "ˇ"]], ["53", [2, "ˋ"]], ["2", [4, "ˋ"]], ["55", [5, ""]], ["24", [7, "ˊ"]], ["5", [8, ""]]],
        [["11", [1, "ˇ"]], ["31", [2, "^"]], ["24", [4, "ˊ"]], ["53", [5, "ˋ"]], ["55", [7, ""]], ["43", [8, "ˋ"]]],
        [["24", [1, "ˊ"]], ["31", [2, "ˋ"]], ["55", [3, ""]], ["2", [4, "ˋ"]], ["11", [5, "ˇ"]], ["5", [8, ""]]],
    ];
    const IDX = /聲母索引\/[^/]+\/[^/]*\/[^/]*\/([^(\s]+)\((\d+)\/([^/]*)\/(\d+)\)/g;

    // syllables
    const SYL = /([a-z]+)(\d+)/g;
    const INITIALS = ["zh", "ch", "sh", "rh", "ng", "bb", "b", "p", "m", "f", "v", "d", "t", "n", "l", "g", "k", "h",
        "z", "c", "s", "j", "q", "x"];
    const ZY_INI = { b: "ㄅ", p: "ㄆ", m: "ㄇ", f: "ㄈ", v: "ㄪ", d: "ㄉ", t: "ㄊ", n: "ㄋ", l: "ㄌ", g: "ㄍ", k: "ㄎ", ng: "ㄫ",
        h: "ㄏ", j: "ㄐ", q: "ㄑ", x: "ㄒ", z: "ㄗ", c: "ㄘ", s: "ㄙ", zh: "ㄓ", ch: "ㄔ", sh: "ㄕ", rh: "ㄖ", bb: "ㆠ" };
    // (教育部「客語拼音方案」: ien = ㄧㄢ, the endings ng / b / d / g = ㄥ ㄅ ㄉ ㄍ: ong ㄛㄥ, ab ㄚㄅ, id ㄧㄉ)
    const ZY_FIN = [["ang", "ㄤ"], ["ai", "ㄞ"], ["au", "ㄠ"], ["an", "ㄢ"], ["ien", "ㄧㄢ"], ["ii", "ㆨ"], ["ee", "ㆤ"], ["oo", "ㆦ"],
        ["er", "ㄜ"], ["nn", "ⁿ"], ["ng", "ㄥ"], ["a", "ㄚ"], ["e", "ㄝ"], ["i", "ㄧ"], ["o", "ㄛ"], ["u", "ㄨ"], ["m", "ㄇ"],
        ["n", "ㄣ"], ["b", "ㄅ"], ["d", "ㄉ"], ["g", "ㄍ"]];
    const findall = (re, s) => { const out = []; re.lastIndex = 0; let m; while ((m = re.exec(s)) !== null) out.push(m.slice(1)); return out; };

    function zhuyin(letters) {
        let ini = INITIALS.find(i => letters.startsWith(i) && letters.length > i.length) || "";
        if (letters === "ng") return "ㄫ";
        if (letters === "m" || letters === "n") ini = "";
        let rest = letters.slice(ini.length);
        let out = ZY_INI[ini] || "";
        while (rest) {
            const f = ZY_FIN.find(([k]) => rest.startsWith(k));
            if (!f) return letters;
            out += f[1]; rest = rest.slice(f[0].length);
        }
        return out;
    }

    const toneTables = [];
    function encode(reading, acc, n) {
        let found = findall(SYL, reading.toLowerCase());
        if (n && found.length > n && found.length % n === 0) found = found.slice(0, n);
        return found.map(([letters, val]) => {
            const t = toneTables[acc].get(val);
            const cat = t ? t[0] : 0;
            return letters + SUP[cat] + SUB[acc];
        });
    }

    const clean = s => pyStrip((s || "").replace(/　/g, " "));
    const splitList = s => (s || "").split(/[\s　、，,]+/u).filter(w => w);
    function sensesOf(text) {
        const t = pyStrip((text || "").replace(/　/g, " "));
        if (!/(?:^|\s)(\p{Nd}+)\./u.test(t)) return t ? [[1, t]] : [];
        const parts = (" " + t).split(/(?:^|\s)(\p{Nd}+)\./u);
        const out = [];
        for (let i = 1; i < parts.length - 1; i += 2) {
            const s = pyStrip(parts[i + 1]);
            if (s) out.push([parseInt(parts[i].normalize("NFKC"), 10), s]);
        }
        return out;
    }
    function examplesOf(text) {
        const t = pyStrip((text || "").replace(/　/g, " "));
        if (!t) return [];
        const chunks = t.includes("例：") ? t.split("例：").map(c => pyStrip(c)).filter(c => c) : [t];
        const out = [];
        for (const c of chunks) {
            const m = /^(.*?)[(（]+(.*?)[)）]*$/u.exec(c);
            let h, z;
            if (m) { h = pyStrip(m[1]); z = pyStrip(pyStrip(m[2]), "（）() "); }
            else {
                const r = /(?<=[。！？])\s+/u.exec(c);
                if (r) { h = pyStrip(c.slice(0, r.index)); z = pyStrip(c.slice(r.index + r[0].length)); }
                else { h = pyStrip(c); z = ""; }
            }
            if (h) out.push([h, z]);
        }
        return out;
    }
    const POS = { 名: "名詞", 動: "動詞", 形: "形容詞", 副: "副詞", 諺: "諺語", 量: "量詞", 代: "代名詞",
        介: "介詞", 連: "連詞", 助: "助詞", 歎: "感嘆詞", 嘆: "感嘆詞", 數: "數詞", 綴: "詞綴" };

    const rowsOf = new Map();
    const accs = Array.from(files.keys()).sort((x, y) => x - y);
    accs.forEach((acc, ai) => {
        host.progress(0.05 + 0.6 * ai / accs.length, "讀" + ACCENTS[acc] + "腔…");
        const raw = readOdsRows(files.get(acc));
        const head = raw[0];
        const col = new Map(); head.forEach((name, i) => col.set(name, i));
        const get = (r, name) => { const i = col.get(name); return i !== undefined && i < r.length ? r[i] : ""; };
        const seen = new Map();
        for (const r of raw.slice(1)) {
            for (const [, num, mark, val] of findall(IDX, get(r, "詞目索引"))) {
                if (!seen.has(val)) seen.set(val, new Map());
                const key = parseInt(num, 10) + "\u0001" + pyStrip(mark);
                const c = seen.get(val); c.set(key, (c.get(key) || 0) + 1);
            }
        }
        const table = new Map(TONE_DEFAULT[acc]);
        for (const [val, c] of seen) {
            const [key, n] = mostCommon(c);
            if (n >= 3) { const [num, mark] = key.split("\u0001"); table.set(val, [parseInt(num, 10), mark]); }
        }
        toneTables[acc] = table;
        const rows = [];
        for (const r of raw.slice(1)) {
            const h = clean(get(r, "詞目"));
            const reading = clean(get(r, "音讀"));
            if (!h || !reading) continue;
            const main = reading.split(/\s*又(?:讀|音)/u)[0];
            const aid = findall(/hk(\d+)-/g, get(r, "對應音檔名稱"));
            rows.push({
                acc, h, read: main, id: aid.length ? aid[0][0] : null,
                senses: sensesOf(get(r, "釋義")), ex: examplesOf(get(r, "例句")),
                pos: splitList(get(r, "詞性")).map(p => POS[p] || p),
                syn: splitList(get(r, "相似詞")), ant: splitList(get(r, "相反詞")),
            });
        }
        rowsOf.set(acc, rows);
        host.log(ACCENTS[acc] + ": " + rows.length + " words");
    });
    for (let i = 0; i < 6; i++) if (!toneTables[i]) toneTables[i] = new Map(TONE_DEFAULT[i]);
    host.progress(0.7, "整理…");

    // the same word in the six accents
    const meaningChars = r => {
        const s = new Set(cps(r.senses.map(x => x[1]).join("")));
        for (const c of cps("，。、；：「」（）() ")) s.delete(c);
        return s;
    };
    const alike = (x, y) => {
        if (!x.size || !y.size) return 0;
        let inter = 0; for (const c of x) if (y.has(c)) inter++;
        return inter / (x.size + y.size - inter);
    };
    const byHead = new Map();
    for (const acc of accs) for (const r of rowsOf.get(acc)) { if (!byHead.has(r.h)) byHead.set(r.h, []); byHead.get(r.h).push(r); }
    const groups = [];
    for (const [, rs] of byHead) {
        const gs = [], byId = new Map();
        for (const r of rs) {
            if (r.id) {
                let g = byId.get(r.id);
                if (g === undefined || g.has(r.acc)) {
                    g = new Map(); gs.push(g);
                    if (!byId.has(r.id)) byId.set(r.id, g);
                }
                g.set(r.acc, r);
            }
        }
        const countAcc = acc => rs.filter(x => x.acc === acc).length;
        for (const r of rs) {
            if (r.id) continue;
            const mc = meaningChars(r);
            let best = null, score = 0.0;
            for (const g of gs) {
                if (g.has(r.acc)) continue;
                let s = Math.max(...Array.from(g.values()).map(x => alike(mc, meaningChars(x))));
                if (countAcc(r.acc) === 1 && Array.from(g.keys()).every(acc => countAcc(acc) <= 1)) s = Math.max(s, 0.5);
                if (s > score) { best = g; score = s; }
            }
            if (best !== null && score >= 0.35) best.set(r.acc, r);
            else { const g = new Map(); g.set(r.acc, r); gs.push(g); }
        }
        groups.push(...gs);
    }
    host.log(groups.length + " words in all");

    // how common (from a 華語 text: the closest there is)
    const freq = a.essay ? readEssay(a.essay) : new Map();
    const charFreq = new Map();
    for (const [w, n] of freq) if (cpLen(w) === 1) charFreq.set(w, (charFreq.get(w) || 0) + n);
    const heads = new Set();
    for (const rs of rowsOf.values()) for (const r of rs) heads.add(r.h);
    let maxw = 0; for (const h of heads) maxw = Math.max(maxw, cpLen(h));
    const exFreq = new Map();
    for (const rs of rowsOf.values()) for (const r of rs) for (const [x0] of r.ex) {
        const x = cps(x0);
        let i = 0;
        while (i < x.length) {
            let hit = false;
            for (let L = Math.min(maxw, x.length - i); L > 0; L--) {
                const w = x.slice(i, i + L).join("");
                if (heads.has(w)) { exFreq.set(w, (exFreq.get(w) || 0) + 1); i += L; hit = true; break; }
            }
            if (!hit) i += 1;
        }
    }
    const firstOf = g => g.has(0) ? g.get(0) : g.values().next().value;
    const homographs = new Map();
    for (const g of groups) { const h = firstOf(g).h; homographs.set(h, (homographs.get(h) || 0) + 1); }
    function score(g) {
        const h = firstOf(g).h;
        const e = (exFreq.get(h) || 0) / homographs.get(h);
        let f = (freq.get(h) || 0) / homographs.get(h);
        if (f === 0) {
            const cs = cps(h);
            f = (cs.length ? Math.min(...cs.map(c => charFreq.get(c) || 0)) : 0) / (40 * cs.length);
        }
        const rec = Array.from(g.values()).some(r => r.id) ? 1 : 0;
        return e * 1e6 + f * (1 + 0.15 * g.size) / 1e3 + rec;
    }

    // English (CC-CEDICT: the word written the same in 華語)
    const english = a.cedict ? readCedict(a.cedict) : new Map();

    function splitWords(ws) {
        const out = [];
        for (const w of ws) {
            if (heads.has(w) || cpLen(w) <= 4) { out.push(w); continue; }
            const c = cps(w);
            let parts = [], i = 0;
            while (i < c.length) {
                let hit = false;
                for (let L = Math.min(maxw, c.length - i); L > 1; L--) {
                    const x = c.slice(i, i + L).join("");
                    if (heads.has(x)) { parts.push(x); i += L; hit = true; break; }
                }
                if (!hit) { parts = null; break; }
            }
            out.push(...(parts ? parts : [w]));
        }
        return out.filter(w => !cps(w).some(c => c >= "" && c <= ""));
    }

    const GROUP = 500;
    const scored = groups.map(g => [g, -score(g)]);
    const ordered = scored.slice().sort((x, y) => x[1] - y[1]).map(x => x[0]);
    const lettersSeen = new Set();
    const entries = [], keys = new Set();
    ordered.forEach((g, n) => {
        const baseAcc = g.has(0) ? 0 : Math.min(...g.keys());
        const b = g.get(baseAcc);
        if (cps(b.h).some(c => (c >= "" && c <= "") || c === "□")) return;
        const syl = new Map();
        for (const [acc, r] of g) syl.set(acc, encode(r.read, acc, cps(r.h).filter(isHan).length));
        if (!syl.get(baseAcc).length) return;
        for (const ss of syl.values()) for (const s of ss) lettersSeen.add(s.slice(0, -2));
        const raw = findall(SYL, b.read.toLowerCase()).map(([l, v]) => l + v).slice(0, syl.get(baseAcc).length);
        let k = b.h + "\t客" + raw.join(" ");
        while (keys.has(k)) k += "＊";
        keys.add(k);
        const xs = b.ex, ss = b.senses;
        let d = ss.map(([num, text], i) => {
            const ex = i < xs.length && xs.length <= ss.length ? [xs[i]] : [];
            return [num, [text, ex.map(x => [x[0], x[1], ""])]];
        });
        if (xs.length > ss.length && d.length) d[0][1][1] = xs.map(x => [x[0], x[1], ""]);
        d = d.map((x, i) => [x, i]).sort((p, q) => p[0][0] - q[0][0] || p[1] - q[1]).map(x => x[0][1]);
        if (!d.length) return;
        const o = { k, h: b.h, s: syl.get(baseAcc).join(" ") };
        const v = [0, 1, 2, 3, 4, 5].map(acc => syl.has(acc) && syl.get(acc).length ? syl.get(acc).join(" ") : null);
        if (v.some(x => x && x !== o.s)) o.v = v;
        o.d = d;
        const en = english.get(b.h);
        if (en && (cpLen(b.h) > 1 || homographs.get(b.h) === 1)) o.n = unique(en).join("; ");
        const rsAll = Array.from(g.values());
        const pos = unique(rsAll.flatMap(r => r.pos));
        if (pos.length) o.w = pos;
        const syn = unique(rsAll.flatMap(r => splitWords(r.syn)).filter(w => w !== b.h));
        const ant = unique(rsAll.flatMap(r => splitWords(r.ant)).filter(w => w !== b.h));
        if (syn.length) o.j = syn.slice(0, 12);
        if (ant.length) o.f = ant.slice(0, 8);
        const other = Array.from(g).filter(([, r]) => r.h !== b.h);
        if (other.length) { o.o = {}; for (const [acc, r] of other) o.o[String(acc)] = r.h; }
        o.x = o.y = Math.floor(n / GROUP) + 1;
        entries.push(o);
    });

    // the characters: the one-character words, the most common first
    host.progress(0.9, "整理漢字…");
    const charEntries = new Map();
    for (const o of entries) if (cpLen(o.h) === 1 && isHan(o.h)) { if (!charEntries.has(o.h)) charEntries.set(o.h, []); charEntries.get(o.h).push(o); }
    const charUse = new Map();
    entries.forEach((o, n) => { for (const c of cps(o.h)) charUse.set(c, (charUse.get(c) || 0) + Math.max(1, Math.floor(100000 / (n + 50)))); });
    const first6000 = entries.slice(0, 6000);
    const appChars = Array.from(charEntries.keys()).map((ch, i) => [ch, i])
        .sort((x, y) => (charUse.get(y[0]) || 0) - (charUse.get(x[0]) || 0) || x[1] - y[1]).map(x => x[0])
        .map((ch, n) => {
            const rs = charEntries.get(ch).slice(0, 4).map(o => {
                const defs = o.d.slice(0, 4).map(m => ["", m[0]]);
                const words = first6000.filter(w => w.h.includes(ch) && w.h !== ch).map(w => w.h).slice(0, 12);
                if (words.length) defs.push(["", "例：" + words.join("，")]);
                return [o.s, o.s, defs, null, o.v === undefined ? null : o.v];
            });
            const lvl = n < GROUP * 7 ? Math.floor(n / GROUP) + 1 : 0;
            return { h: ch, m: rs, x: lvl, y: lvl };
        });

    const hz = {};
    for (const l of Array.from(lettersSeen).sort()) hz[l] = zhuyin(l);
    const ht = [];
    for (let acc = 0; acc < 6; acc++) {
        const marks = Array(9).fill("");
        for (const [, [cat, mark]] of toneTables[acc]) if (cat > 0 && cat < 9 && !marks[cat]) marks[cat] = mark;
        ht.push(marks);
    }
    const head = { v: 1, lang: "hak", nc: entries.length, c: appChars, ht, hz, acc: ACCENTS };
    host.writeText(a.out, dumps(head).slice(0, -1) + ',"e":[\n' + entries.map(dumps).join(",\n") + "\n]}");
    host.log("app file: " + entries.length + " words, " + appChars.length + " characters");
    return { words: entries.length, chars: appChars.length };
}
