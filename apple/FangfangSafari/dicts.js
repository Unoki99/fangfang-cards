// 方方詞卡 查詞: the dictionaries the add-on can install by itself (設定 → 詞典), the same ones and the same original
// files as the app's 設定 → 詞典資料 (FangfangCards/DictInstall.swift). The dictionaries' licenses don't allow
// sharing changed versions, so the add-on has none inside it: it downloads the original, unchanged files (first
// from the copies in this project's GitHub repository, fangfang-sources/, else from where they're published), the
// app's own converters (install/*.js, copied from FangfangCards/Install when the add-on is built) make the app's
// data from them, and shards.js the lookup files, all in the browser (install-worker.js), kept in its storage.
"use strict";

var FF_DICTS = (() => {
    const g = "https://raw.githubusercontent.com/";
    const essay = { file: "essay.txt", url: g + "rime/rime-essay/master/essay.txt", arg: "essay", shared: true };
    const cedict = { file: "cedict_ts.u8", url: g + "cschiller/zhongwen/main/data/cedict_ts.u8", arg: "cedict", shared: true };
    const hakBase = "https://hakkadict.moe.edu.tw/static/resource/客語資源下載/本辭典的文字/";
    const jd = g + "aaronhktan/jyut-dict/main/src/dictionaries/cedict/data/";
    const rc = g + "rime/rime-cantonese/main/";
    return [
        {
            id: "zh", name: "華語", script: "mandarin", fn: "buildMandarin", outs: ["zh"], mb: 75,
            sources: [{ file: "dict-csld.json", url: g + "g0v/moedict-data-csld/master/dict-csld.json", arg: "csld" },
                Object.assign({}, essay), Object.assign({}, cedict, { optional: true }),
                { file: "hsk30.csv", url: g + "ivankra/hsk30/master/hsk30-expanded.csv", arg: "hsk", optional: true },
                { file: "tocfl.csv", url: g + "ivankra/tocfl/master/expanded/tocfl.csv", arg: "tocfl", optional: true, noMirror: true }],
            from: [["中華文化總會《兩岸常用詞典》", "CC BY-NC-ND 3.0 TW", "https://github.com/g0v/moedict-data-csld"],
                ["CC-CEDICT", "CC BY-SA 4.0", "https://cc-cedict.org/wiki/"],
                ["rime-essay", "LGPL-3.0", "https://github.com/rime/rime-essay"],
                ["HSK 3.0 詞表（ivankra/hsk30）", "MIT", "https://github.com/ivankra/hsk30"],
                ["TOCFL 詞表（ivankra/tocfl）", "", "https://github.com/ivankra/tocfl"]],
        },
        {
            // (ver: the version of the data the converter makes; an older one installed is offered again)
            id: "tw", name: "台語", script: "taigi", fn: "buildTaigi", outs: ["dict", "cards"], mb: 11, ver: 5,
            sources: [{ file: "kautian.ods", url: "https://sutian.moe.edu.tw/media/senn/ods/kautian.ods", arg: "ods" },
                Object.assign({}, essay)],
            bundled: { own: "install/twown.json" },
            from: [["教育部《臺灣台語常用詞辭典》", "CC BY-ND 3.0 TW", "https://sutian.moe.edu.tw/"],
                ["rime-essay", "LGPL-3.0", "https://github.com/rime/rime-essay"],
                ["音節編碼：rime-taigi-tps（YuRen-tw，經作者同意）", "", "https://github.com/YuRen-tw/rime-taigi-tps"],
                ["自補詞條：Unoki99", "", ""]],
        },
        {
            id: "yue", name: "粵語", script: "cantonese", fn: "buildCantonese", outs: ["yue"], mb: 25,
            sources: [Object.assign({}, cedict),
                { file: "CC-CANTO.txt", url: jd + "CC-CANTO.txt", arg: "canto" },
                { file: "READINGS.txt", url: jd + "READINGS.txt", arg: "readings" },
                { file: "jyut6ping3.words.dict.yaml", url: rc + "jyut6ping3.words.dict.yaml", arg: "words" },
                { file: "jyut6ping3.chars.dict.yaml", url: rc + "jyut6ping3.chars.dict.yaml", arg: "chars" },
                { file: "essay-cantonese.txt", url: rc + "essay-cantonese.txt", arg: "essay" },
                { file: "yyzd.txt", url: g + "kfcd/yyzd/master/dist/tsv/%E7%B9%81%E9%AB%94/%E7%B2%B5%E8%AA%9E%E5%AD%97%E5%85%B8_%28%E7%B2%B5%E6%8B%BC%29.txt", arg: "yyzd" }],
            from: [["CC-CEDICT", "CC BY-SA 4.0", "https://cc-cedict.org/wiki/"],
                ["CC-Canto", "CC BY-SA", "https://cantonese.org/"],
                ["rime-cantonese", "CC BY 4.0", "https://github.com/rime/rime-cantonese"],
                ["開放粵語字典", "CC BY 3.0", "https://github.com/kfcd/yyzd"]],
        },
        {
            id: "hak", name: "客語", script: "hakka", fn: "buildHakka", outs: ["hak"], mb: 33,
            sources: [...["四縣", "海陸", "大埔", "饒平", "詔安", "南四縣"].map(a => ({ file: a + "腔詞條詞目文字.ods", url: hakBase + a + "腔詞條詞目文字.ods", optional: a !== "四縣" })),
                Object.assign({}, essay, { optional: true }), Object.assign({}, cedict, { optional: true })],
            from: [["教育部《臺灣客語辭典》", "CC BY-ND 3.0 TW", "https://hakkadict.moe.edu.tw/"],
                ["rime-essay", "LGPL-3.0", "https://github.com/rime/rime-essay"],
                ["CC-CEDICT", "CC BY-SA 4.0", "https://cc-cedict.org/wiki/"]],
        },
        {
            id: "sv", name: "瑞典語", script: "swedish", fn: "buildSwedish", outs: ["sv"], mb: 95,
            sources: [{ file: "folkets.xml", url: g + "antonlisq/convert-dict/main/folkets_sv_en_public.xml", arg: "folkets2", optional: true },
                { file: "folkets_kth.xml", url: "http://folkets-lexikon.csc.kth.se/folkets/folkets_sv_en_public.xml", arg: "folkets", optional: true, unless: "folkets.xml", noMirror: true },
                { file: "sv_50k.txt", url: g + "hermitdave/FrequencyWords/master/content/2018/sv/sv_50k.txt", arg: "freq", optional: true },
                Object.assign({}, cedict, { optional: true }), Object.assign({}, essay, { optional: true }),
                { file: "zhwikt-sv.jsonl", url: "https://kaikki.org/zhwiktionary/%E7%91%9E%E5%85%B8%E8%AA%9E/kaikki.org-dictionary-%E7%91%9E%E5%85%B8%E8%AA%9E.jsonl", arg: "zhwikt", optional: true }],
            from: [["Folkets lexikon（KTH）", "CC BY-SA 2.5", "http://folkets-lexikon.csc.kth.se/folkets/"],
                ["FrequencyWords", "CC BY-SA 4.0", "https://github.com/hermitdave/FrequencyWords"],
                ["維基詞典的中文解釋（kaikki.org）", "CC BY-SA 4.0", "https://kaikki.org/"],
                ["CC-CEDICT", "CC BY-SA 4.0", "https://cc-cedict.org/wiki/"]],
        },
    ];
})();
/// the copies of the original files, unchanged, in this project's GitHub repository (one folder per dictionary, and
/// common/ for the files more than one uses)
const FF_MIRROR = "https://raw.githubusercontent.com/unoki99/fangfang-cards/main/fangfang-sources/";
function ffMirrorURL(dict, s) {
    return s.noMirror ? null : FF_MIRROR + (s.shared ? "common" : dict.id) + "/" + encodeURIComponent(s.file);
}
/// the app's data a language's lookup files are made from (the converters' outputs, and what shards.js reads)
const FF_DATA_OF = { zh: ["zh"], tw: ["dict", "cards"], yue: ["yue"], hak: ["hak"], sv: ["sv"] };
