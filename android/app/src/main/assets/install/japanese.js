// 日語: JMdict (English, JMdict_e_examp.gz) and KANJIDIC2 (kanjidic2.xml.gz) from the EDRDG (CC BY-SA 4.0) → ja.json.
// Downloaded and made on the device, like the other dictionaries (nothing of it is in the app or on GitHub).
//   buildJapanese({jmdict: JMdict_e_examp.gz, kanjidic: kanjidic2.xml.gz | null, out: ja.json})
//
// ja.json has the same shape as zh.json / yue.json / hak.json ("lang": "ja"), so 日語 uses the same pages:
//   head: {v, lang: "ja", nc: how many are study cards (the common words, first), c: the kanji cards, tags}
//   one entry a line: {k: "食べる\t日たべる", h, s: the reading in kana (one piece), d: [[meaning (English), []]…],
//     n: every meaning ("; "), w: word classes (中文), jp: JMdict's codes (for 活用), m: other spellings,
//     x = y: the group of 500 (common words), 0 the rest}
"use strict";

function jaText(s) {
    return decodeEntities(s.replace(/<[^>]+>/g, "")).trim();
}

/// the <!ENTITY code "meaning"> of the DOCTYPE
function jaEntities(head) {
    const m = new Map();
    for (const x of head.matchAll(/<!ENTITY\s+([\w.-]+)\s+"([^"]*)">/g)) m.set(x[1], x[2]);
    return m;
}

function jaRank(pris) {
    let nf = 0, common = false, some = false;
    for (const p of pris) {
        const m = /^nf(\d\d)$/.exec(p);
        if (m) nf = nf ? Math.min(nf, +m[1]) : +m[1];
        else if (/1$/.test(p)) common = true;
        else some = true;
    }
    if (nf && (common || nf <= 24)) return nf;
    if (common) return 49;
    if (nf || some) return 60;
    return 0;
}

const jaRes = new Map();
function jaAll(body, tag) {
    const out = [];
    let re = jaRes.get(tag);
    if (!re) { re = new RegExp("<" + tag + "(?:\\s[^>]*)?>([\\s\\S]*?)</" + tag + ">", "g"); jaRes.set(tag, re); }
    if (body.indexOf("<" + tag) < 0) return out;
    for (const m of body.matchAll(re)) out.push(m[1]);
    return out;
}
function jaCodes(body, tag) {
    const out = [];
    for (const v of jaAll(body, tag)) { const m = /&([\w.-]+);/.exec(v); if (m) out.push(m[1]); }
    return out;
}

function buildJmdict(xml, tags) {
    const start = xml.indexOf("<JMdict>");
    const ents = jaEntities(start > 0 ? xml.slice(0, start) : "");
    const used = new Set();
    const out = [];
    let p = start > 0 ? start : 0, n = 0;
    while (true) {
        const a = xml.indexOf("<entry>", p);
        if (a < 0) break;
        const b = xml.indexOf("</entry>", a);
        if (b < 0) break;
        const e = xml.slice(a + 7, b);
        p = b + 8;
        if (++n % 20000 === 0) host.progress(0.15 + 0.6 * (p / xml.length), "JMdict：" + n + " 個詞…");
        const idm = /<ent_seq>(\d+)<\/ent_seq>/.exec(e);
        const pris = [];
        const kanji = [];
        for (const k of jaAll(e, "k_ele")) {
            const inf = jaCodes(k, "ke_inf");
            // (not the rare, irregular, old or search-only spellings)
            if (inf.some(c => c === "sK" || c === "iK" || c === "oK" || c === "rK")) continue;
            const keb = jaAll(k, "keb")[0];
            if (!keb) continue;
            kanji.push(jaText(keb));
            if (kanji.length === 1) for (const x of jaAll(k, "ke_pri")) pris.push(x.trim());
        }
        const kana = [];
        for (const r of jaAll(e, "r_ele")) {
            const inf = jaCodes(r, "re_inf");
            if (inf.some(c => c === "sk" || c === "ik" || c === "ok")) continue;
            const reb = jaAll(r, "reb")[0];
            if (!reb) continue;
            kana.push(jaText(reb));
            if (kana.length === 1) for (const x of jaAll(r, "re_pri")) pris.push(x.trim());
        }
        if (!kana.length) continue;
        const senses = [];
        let pos = [];
        for (const s of jaAll(e, "sense")) {
            const ps = jaCodes(s, "pos");
            // (a sense without <pos> has the ones of the sense before it)
            if (ps.length) pos = ps;
            const gl = jaAll(s, "gloss").map(jaText).filter(x => x);
            if (!gl.length) continue;
            const misc = jaCodes(s, "misc").concat(jaCodes(s, "field"), jaCodes(s, "dial"));
            const info = jaAll(s, "s_inf").map(jaText).join("; ");
            for (const c of pos) used.add(c);
            for (const c of misc) used.add(c);
            // example sentences (JMdict_e_examp: Tatoeba's, CC BY 2.0 FR): the Japanese and the English, at most 3
            const ex = [];
            for (const x of jaAll(s, "example")) {
                const jp = /<ex_sent xml:lang="jpn">([\s\S]*?)<\/ex_sent>/.exec(x);
                const en = /<ex_sent xml:lang="eng">([\s\S]*?)<\/ex_sent>/.exec(x);
                if (jp && ex.length < 3) ex.push([jaText(jp[1]), en ? jaText(en[1]) : ""]);
            }
            senses.push([pos, gl, misc, info, ex]);
        }
        if (!senses.length) continue;
        out.push([idm ? +idm[1] : 0, kanji, kana, senses, jaRank(pris)]);
    }
    for (const c of used) if (ents.has(c)) tags[c] = ents.get(c);
    // the common ones first (by rank), then the rest in JMdict's order
    const key = r => (r ? r : 1000);
    out.sort((x, y) => key(x[4]) - key(y[4]) || x[0] - y[0]);
    return out;
}

function buildKanjidic(xml) {
    const out = {};
    let p = 0, n = 0;
    while (true) {
        const a = xml.indexOf("<character>", p);
        if (a < 0) break;
        const b = xml.indexOf("</character>", a);
        if (b < 0) break;
        const c = xml.slice(a + 11, b);
        p = b + 12;
        const lit = jaAll(c, "literal")[0];
        if (!lit) continue;
        const num = t => { const v = jaAll(c, t)[0]; return v ? +v : 0; };
        const meanings = [], on = [], kun = [];
        for (const m of c.matchAll(/<meaning(\s[^>]*)?>([^<]*)<\/meaning>/g)) if (!m[1]) meanings.push(decodeEntities(m[2]));
        for (const m of c.matchAll(/<reading r_type="ja_(on|kun)"[^>]*>([^<]*)<\/reading>/g)) (m[1] === "on" ? on : kun).push(m[2]);
        out[jaText(lit)] = [meanings, on, kun, num("grade"), num("stroke_count"), num("freq"), num("jlpt")];
        n++;
    }
    host.log("KANJIDIC2: " + n + " characters");
    return out;
}

/// a reading in morae, one each ("たべる" → た べ る; "きょう" → きょ う; "がっこう" → が っ こ う; "コーヒー" → コー ヒー)
function jaMorae(r) {
    const out = [];
    for (const c of r) {
        if (out.length && "ゃゅょぁぃぅぇぉゎャュョァィゥェォヮー".includes(c)) out[out.length - 1] += c;
        else out.push(c);
    }
    return out;
}

// JMdict's word classes, in the app's words (the same as JaTags in the app)
const JA_POS = {
    "n": "名詞", "v1": "一段動詞", "v1-s": "一段動詞", "v5u": "五段動詞", "v5k": "五段動詞", "v5k-s": "五段動詞", "v5g": "五段動詞",
    "v5s": "五段動詞", "v5t": "五段動詞", "v5n": "五段動詞", "v5b": "五段動詞", "v5m": "五段動詞", "v5r": "五段動詞", "v5r-i": "五段動詞",
    "v5aru": "五段動詞", "v5u-s": "五段動詞", "vk": "カ變動詞", "vs": "する名詞", "vs-i": "サ變動詞", "vs-s": "サ變動詞",
    "vt": "他動詞", "vi": "自動詞", "adj-i": "い形容詞", "adj-ix": "い形容詞", "adj-na": "な形容詞", "adj-no": "の形容詞",
    "adv": "副詞", "adv-to": "副詞", "prt": "助詞", "conj": "連接詞", "int": "感嘆詞", "pn": "代名詞", "ctr": "量詞",
    "exp": "片語", "pref": "接頭詞", "suf": "接尾詞", "aux-v": "助動詞", "aux-adj": "助動詞", "aux": "助動詞", "num": "數詞", "cop": "繫詞",
    "adj-pn": "連體詞", "adj-f": "連體詞", "n-suf": "接尾詞", "n-pref": "接頭詞", "n-adv": "副詞", "n-t": "名詞", "pn-adj": "連體詞",
};
const JA_MISC = { "uk": "通常寫假名", "pol": "禮貌", "hon": "尊敬", "hum": "謙讓", "col": "口語", "sl": "俗語", "abbr": "縮寫",
    "arch": "古語", "obs": "舊說法", "vulg": "粗俗", "fam": "親密", "male": "男性用語", "fem": "女性用語", "on-mim": "擬聲擬態",
    "id": "慣用語", "yoji": "四字熟語", "proverb": "諺語", "derog": "貶義", "joc": "玩笑" };

function buildJapanese(a) {
    host.progress(0.05, "解開 JMdict…");
    const xml = host.gunzipText(a.jmdict);
    const tags = {};
    const raw = buildJmdict(xml, tags);
    host.log("JMdict: " + raw.length + " entries");
    const GROUP = 500;
    const keys = new Set();
    const entries = [];
    let nc = 0;
    for (const [id, kanji, kana, senses, rank] of raw) {
        const h = kanji.length ? kanji[0] : kana[0];
        const reading = kana[0];
        let k = h + "\t日" + reading;
        while (keys.has(k)) k += "＊";
        keys.add(k);
        const common = rank > 0 && rank < 60;
        const d = senses.map(s => {
            let t = s[1].join("; ");
            if (s[3]) t += " (" + s[3] + ")";
            return [t, s[4] || []];
        });
        const codes = unique(senses.flatMap(s => s[0]));
        const misc = unique(senses.flatMap(s => s[2]));
        const o = { k, h, s: jaMorae(reading).join(" "), d, n: senses.flatMap(s => s[1]).join("; ") };
        const w = unique(codes.map(c => JA_POS[c]).filter(x => x).concat(misc.map(c => JA_MISC[c]).filter(x => x)));
        if (w.length) o.w = w;
        if (codes.length || misc.length) o.jp = codes.concat(misc.map(c => "*" + c));
        const more = kanji.slice(1).concat(kanji.length ? kana.slice(1) : kana.slice(1));
        if (more.length) o.m = more.slice(0, 8);
        if (common) { o.x = o.y = Math.floor(nc / GROUP) + 1; nc++; }
        entries.push(o);
    }
    let chars = [];
    if (a.kanjidic) {
        host.progress(0.8, "解開 KANJIDIC2…");
        const kx = host.gunzipText(a.kanjidic);
        if (kx) chars = kanjiCards(buildKanjidic(kx), entries.slice(0, Math.min(nc, 8000)), GROUP);
    }
    host.progress(0.95, "寫入…");
    const head = { v: 1, lang: "ja", nc, c: chars, tags };
    host.writeText(a.out, dumps(head).slice(0, -1) + ',"e":[\n' + entries.map(dumps).join(",\n") + "\n]}");
    return { entries: entries.length, cards: nc, kanji: chars.length };
}

/// the kanji as character cards: the readings (音讀 in katakana, 訓讀 in hiragana: た（べる）), the meanings, a few
/// common words with it; the most common first (KANJIDIC's newspaper frequency, then the school grade)
function kanjiCards(k, common, GROUP) {
    const list = Object.keys(k).filter(c => k[c][5] > 0 || (k[c][3] > 0 && k[c][3] <= 8));
    const order = c => (k[c][5] > 0 ? k[c][5] : 3000 + (k[c][3] || 9) * 100 + k[c][4]);
    list.sort((x, y) => order(x) - order(y));
    return list.map((ch, n) => {
        const [meanings, on, kun, grade, strokes] = k[ch];
        const kunShown = kun.map(r => { const p = r.split("."); return p.length > 1 ? p[0] + "（" + p.slice(1).join("") + "）" : r; });
        const reading = on.concat(kunShown).join("、");
        const defs = meanings.slice(0, 6).map(m => ["", m]);
        const words = common.filter(w => w.h.includes(ch) && w.h !== ch).slice(0, 10).map(w => w.h + "（" + w.s + "）");
        if (words.length) defs.push(["", "例：" + words.join("，")]);
        const lvl = n < GROUP * 7 ? Math.floor(n / GROUP) + 1 : 0;
        const o = { h: ch, m: [[reading, reading, defs, null]], x: lvl, y: lvl };
        if (strokes) o.n = strokes;
        if (grade) o.g = grade;
        return o;
    });
}
