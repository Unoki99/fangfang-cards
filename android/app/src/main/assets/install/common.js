// 方方詞卡: the dictionary converters' shared parts. These scripts run inside the app (JavaScriptCore, when you
// install a dictionary in 設定 → 詞典資料) and on a computer with node (tools/convert.js), the same code both ways.
// The app gives them `host`: readText(path), readLines(path, fn), unzipText(path, entry), xzText(path),
// writeText(path, text), list(dir), log(text), progress(fraction, text).
"use strict";

/** code points of a string (a 漢字 outside the BMP counts as one, as in Python) */
function cps(s) { return Array.from(s); }
function cpLen(s) { let n = 0; for (const _ of s) n++; return n; }

function isHan(ch) {
    const c = ch.codePointAt(0);
    return (c >= 0x3400 && c <= 0x9FFF) || (c >= 0x20000 && c <= 0x3FFFF) || (c >= 0xF900 && c <= 0xFAFF);
}

/** Python's str.strip() (whitespace) and str.strip(chars) */
function pyStrip(s, chars) {
    if (chars === undefined) return s.replace(/^[\s\u0085\u001c-\u001f]+|[\s\u0085\u001c-\u001f]+$/gu, "");
    const set = new Set(cps(chars));
    const a = cps(s);
    let i = 0, j = a.length;
    while (i < j && set.has(a[i])) i++;
    while (j > i && set.has(a[j - 1])) j--;
    return a.slice(i, j).join("");
}

/** a Counter's most_common(1): the biggest count, the first one counted among equals */
function mostCommon(m) {
    let best = null, n = -1;
    for (const [k, v] of m) if (v > n) { best = k; n = v; }
    return [best, n];
}

function decodeEntities(s) {
    if (s.indexOf("&") < 0) return s;
    return s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);/g, (m, e) => {
        if (e === "amp") return "&"; if (e === "lt") return "<"; if (e === "gt") return ">";
        if (e === "quot") return "\""; if (e === "apos") return "'";
        return String.fromCodePoint(e[1] === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10));
    });
}

/** an .ods sheet's rows (every sheet's, one after another), each a list of the cells' text; like ods reading in
 *  the Python tools: repeated columns at most 20 times, a repeated row once, empty rows left out */
function readOdsRows(path) {
    const xml = host.unzipText(path, "content.xml");
    const rows = [];
    const re = /<(\/?)([A-Za-z][\w.-]*:[\w.-]+|[A-Za-z][\w.-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>|([^<]+)/g;
    let row = null, cell = null, cellRep = 1, para = null, inP = 0, rowRep = 1;
    const attrRe = {};
    const attr = (a, name) => {
        if (a.indexOf(name) < 0) return null;
        const re2 = attrRe[name] || (attrRe[name] = new RegExp(name + "=\"([^\"]*)\""));
        const m = re2.exec(a); return m ? m[1] : null;
    };
    let m;
    while ((m = re.exec(xml)) !== null) {
        if (m[5] !== undefined) { if (inP > 0 && para !== null) para.push(decodeEntities(m[5])); continue; }
        const close = m[1] === "/", tag = m[2], a = m[3], self = m[4] === "/";
        if (tag === "table:table-row") {
            if (!close) { row = []; rowRep = parseInt(attr(a, "table:number-rows-repeated") || "1", 10); if (self) { row = null; } }
            else if (row) { if (row.some(x => pyStrip(x) !== "")) rows.push(row); row = null; }
        } else if (tag === "table:table-cell" || tag === "table:covered-table-cell") {
            if (!row) continue;
            if (!close) {
                cellRep = parseInt(attr(a, "table:number-columns-repeated") || "1", 10);
                if (self) { for (let i = 0; i < Math.min(cellRep, 20); i++) row.push(""); cell = null; }
                else cell = [];
            } else if (cell) {
                const t = cell.join("\n");
                for (let i = 0; i < Math.min(cellRep, 20); i++) row.push(t);
                cell = null;
            }
        } else if (tag === "text:p") {
            if (!cell) continue;
            if (!close) { if (self) cell.push(""); else { if (inP === 0) para = []; inP++; } }
            else { inP--; if (inP === 0) { cell.push(para.join("")); para = null; } }
        } else if (inP > 0 && para !== null) {
            if (tag === "text:s") para.push(" ".repeat(parseInt(attr(a, "text:c") || "1", 10)));
            else if (tag === "text:tab") para.push("\t");
            else if (tag === "text:line-break") para.push("\n");
        }
    }
    return rows;
}

/** CC-CEDICT: 正體 → [English, …] (the same choices as the Python tools) */
function readCedict(path, alsoSimp) {
    const english = new Map();
    const re = /^(\S+) (\S+) \[([^\]]*)\] \/(.*)\/\s*$/;
    host.readLines(path, line => {
        if (line.startsWith("#")) return;
        const m = re.exec(line);
        if (!m) return;
        const trad = m[1], gl = m[4];
        const gs = gl.split("/").filter(g => g && !g.startsWith("CL:") && !/^(variant of|old variant of|see )/.test(g));
        if (gs.length) { if (!english.has(trad)) english.set(trad, []); english.get(trad).push(...gs); }
    });
    return english;
}

/** rime-essay: word → how often (summed) */
function readEssay(path) {
    const freq = new Map();
    host.readLines(path, line => {
        const p = line.split("\t");
        if (p.length >= 2 && /^\p{Nd}+$/u.test(p[1])) freq.set(p[0], (freq.get(p[0]) || 0) + parseInt(p[1].normalize("NFKC"), 10));
    });
    return freq;
}

/** a list without repeats, in the order first seen */
function unique(xs) { return Array.from(new Set(xs)); }

/** Python's json.dumps(o, ensure_ascii=False, separators=(",", ":")) for the converters' data */
function dumps(o) { return JSON.stringify(o); }

/** every sheet of an .ods file by name, each a list of rows (as tools/ods2csv.py: a cell's paragraphs, or its
 *  value when it has none; repeated columns at most 200 times; empty cells at a row's end left off; a repeated
 *  row at most 1000 times; empty rows left out) */
function readOdsSheets(path) {
    const xml = host.unzipText(path, "content.xml");
    const sheets = {};
    const re = /<(\/?)([A-Za-z][\w.-]*:[\w.-]+|[A-Za-z][\w.-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>|([^<]+)/g;
    const attrRe = {};
    const attr = (a, name) => {
        if (a.indexOf(name) < 0) return null;
        const re2 = attrRe[name] || (attrRe[name] = new RegExp("(?:^|\\s)" + name + "=\"([^\"]*)\""));
        const m = re2.exec(a); return m ? decodeEntities(m[1]) : null;
    };
    let rows = null, row = null, rowRep = 1, cell = null, cellRep = 1, cellVal = null, para = null, inP = 0;
    const endCell = () => {
        const t = cell.length ? cell.join("\n") : (cellVal || "");
        for (let i = 0; i < Math.min(cellRep, 200); i++) row.push(t);
        cell = null;
    };
    const endRow = () => {
        while (row.length && row[row.length - 1] === "") row.pop();
        if (row.length) for (let i = 0; i < Math.min(rowRep, 1000); i++) rows.push(row);
        row = null;
    };
    let m;
    while ((m = re.exec(xml)) !== null) {
        if (m[5] !== undefined) { if (inP > 0 && para !== null) para.push(decodeEntities(m[5])); continue; }
        const close = m[1] === "/", tag = m[2], a = m[3], self = m[4] === "/";
        if (tag === "table:table") {
            if (!close) { rows = []; sheets[attr(a, "table:name")] = rows; }
            else rows = null;
        } else if (tag === "table:table-row") {
            if (!close) { row = []; rowRep = parseInt(attr(a, "table:number-rows-repeated") || "1", 10); if (self) endRow(); }
            else if (row) endRow();
        } else if (tag === "table:table-cell" || tag === "table:covered-table-cell") {
            if (!row) continue;
            if (!close) {
                cellRep = parseInt(attr(a, "table:number-columns-repeated") || "1", 10);
                cellVal = attr(a, "office:value") || attr(a, "office:date-value") || attr(a, "office:string-value");
                cell = [];
                if (self) endCell();
            } else if (cell) endCell();
        } else if (tag === "text:p") {
            if (!cell) continue;
            if (!close) { if (self) cell.push(""); else { if (inP === 0) para = []; inP++; } }
            else { inP--; if (inP === 0) { cell.push(para.join("")); para = null; } }
        } else if (inP > 0 && para !== null) {
            if (tag === "text:s") para.push(" ".repeat(parseInt(attr(a, "text:c") || "1", 10)));
            else if (tag === "text:tab") para.push("\t");
            else if (tag === "text:line-break") para.push("\n");
        }
    }
    return sheets;
}
