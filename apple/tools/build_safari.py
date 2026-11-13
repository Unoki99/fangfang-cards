#!/usr/bin/env python3
# Safari 查詞: the words the Safari pop-up looks up, put inside the Safari extension itself (FangfangSafari/d-*.json),
# so it works without the App Group (which an app installed with Sideloadly usually doesn't get). Made on your Mac
# from the app's data by install.sh, like the rest of the word data; not on GitHub (it's made from the MOE
# dictionaries).
#   python3 build_safari.py FangfangCards/ FangfangSafari/
#
# The readings are kept as they are in the data (注音 / 四川話拼音; 台語 syllable codes, and each place's), with
# tables to spell them: the pop-up writes them out in the spelling and 腔口 chosen in its own settings.
# Files by the word's first character (its code point modulo 256), so the pop-up only reads one small file.
import json, os, sys, unicodedata

SRC, OUT = sys.argv[1], sys.argv[2]
SHARDS, MAXLEN = 256, 12


def load(name):
    p = os.path.join(SRC, name)
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else None


def short(s, n=120):
    s = " ".join((s or "").split())
    return s[:n] + "…" if len(s) > n else s


# ── 注音 → 拼音 (the same as the app's Zhuyin.pinyin) ─────────────────────────────────────────────────────────────
INI = {"ㄅ": "b", "ㄆ": "p", "ㄇ": "m", "ㄈ": "f", "ㄉ": "d", "ㄊ": "t", "ㄋ": "n", "ㄌ": "l", "ㄍ": "g", "ㄎ": "k",
       "ㄏ": "h", "ㄐ": "j", "ㄑ": "q", "ㄒ": "x", "ㄓ": "zh", "ㄔ": "ch", "ㄕ": "sh", "ㄖ": "r", "ㄗ": "z", "ㄘ": "c", "ㄙ": "s"}
FIN = {"": "", "ㄚ": "a", "ㄛ": "o", "ㄜ": "e", "ㄝ": "ê", "ㄞ": "ai", "ㄟ": "ei", "ㄠ": "ao", "ㄡ": "ou",
       "ㄢ": "an", "ㄣ": "en", "ㄤ": "ang", "ㄥ": "eng", "ㄦ": "er",
       "ㄧ": "i", "ㄧㄚ": "ia", "ㄧㄛ": "io", "ㄧㄝ": "ie", "ㄧㄞ": "iai", "ㄧㄠ": "iao", "ㄧㄡ": "iu",
       "ㄧㄢ": "ian", "ㄧㄣ": "in", "ㄧㄤ": "iang", "ㄧㄥ": "ing",
       "ㄨ": "u", "ㄨㄚ": "ua", "ㄨㄛ": "uo", "ㄨㄞ": "uai", "ㄨㄟ": "ui", "ㄨㄢ": "uan", "ㄨㄣ": "un",
       "ㄨㄤ": "uang", "ㄨㄥ": "ong",
       "ㄩ": "ü", "ㄩㄝ": "üe", "ㄩㄢ": "üan", "ㄩㄣ": "ün", "ㄩㄥ": "iong"}
ALONE = {"i": "yi", "ia": "ya", "io": "yo", "ie": "ye", "iai": "yai", "iao": "yao", "iu": "you", "ian": "yan",
         "in": "yin", "iang": "yang", "ing": "ying", "u": "wu", "ua": "wa", "uo": "wo", "uai": "wai",
         "ui": "wei", "uan": "wan", "un": "wen", "uang": "wang", "ong": "weng", "ü": "yu", "üe": "yue",
         "üan": "yuan", "ün": "yun", "iong": "yong"}
MARKS = {"a": "āáǎà", "e": "ēéěè", "i": "īíǐì", "o": "ōóǒò", "u": "ūúǔù", "ü": "ǖǘǚǜ"}


def zy_tone(s):
    if s.startswith("˙") or s.endswith("˙"): return 0
    return {"ˊ": 2, "ˇ": 3, "ˋ": 4}.get(s[-1:], 1)


def pinyin(s0):
    t = zy_tone(s0)
    s = "".join(c for c in s0 if c not in "ˊˇˋ˙")
    if not s: return ""
    er = len(s) > 1 and s.endswith("ㄦ")
    if er: s = s[:-1]
    ini = INI.get(s[0], "")
    rest = s[1:] if ini else s
    f = FIN.get(rest)
    if f is None: return s0
    if ini:
        if not f:
            if ini not in ("zh", "ch", "sh", "r", "z", "c", "s"): return s0
            f = "i"
        if ini in ("j", "q", "x"): f = f.replace("ü", "u")
        p = ini + f
    else:
        p = ALONE.get(f, f)
    if er: p += "r"
    if t not in (1, 2, 3, 4): return p
    v = next((i for i, c in enumerate(p) if c == "a"), None)
    if v is None: v = next((i for i, c in enumerate(p) if c in "eê"), None)
    if v is None and "ou" in p: v = p.index("o")
    if v is None:
        vs = [i for i, c in enumerate(p) if c in "iouü"]
        v = vs[-1] if vs else None
    if v is None: return p
    c = p[v]
    if c == "ê": m = "ê" + "̄́̌̀"[t - 1]
    else: m = MARKS[c][t - 1]
    return unicodedata.normalize("NFC", p[:v] + m + p[v + 1:])


shards = {l: [dict() for _ in range(SHARDS)] for l in ("zh", "tw", "yue", "hak")}


def add(lang, word, e, most=6):
    if not word or len(word) > MAXLEN: return
    d = shards[lang][ord(word[0]) % SHARDS]
    lst = d.setdefault(word, [])
    if len(lst) < most and not any(x["k"] == e["k"] for x in lst): lst.append(e)


# ── 華語 ───────────────────────────────────────────────────────────────────────────────────────────────────────
zy_py = {}
zh_count = 0
zh = load("zh.json")
if zh:
    sc = load("zh_sc.json") or {}
    sc_read = {}
    for kind, name in ((2, "p"), (1, "g"), (0, "s")):
        for k, v in (sc.get(name) or {}).items(): sc_read[k] = (v, kind)
    eqs = sc.get("q") or {}

    def zh_add(k, h, alt, tw, lu, scr, kind, spec, m, en, eq=None):
        global zh_count
        e = {"k": k, "t": tw}
        if lu: e["l"] = lu
        if scr: e["s"] = scr; e["q"] = kind
        if spec: e["p"] = spec
        if m: e["m"] = m
        if en: e["e"] = en
        if eq: e["eq"] = eq
        for s in tw.split(" ") + (lu or "").split(" "):
            if s and s not in ("-", "_") and s not in zy_py: zy_py[s] = pinyin(s)
        add("zh", h, e, 4)
        if alt and alt != h: add("zh", alt, e, 4)
        zh_count += 1

    for e in zh.get("e", []):
        k, h, tw = e.get("k"), e.get("h"), e.get("s")
        if not (k and h and tw): continue
        senses = [d[0] for d in e.get("d") or [] if d and d[0]]
        scr, kind = sc_read.get(k, (None, 0))
        if scr and len(scr.split(" ")) != len(tw.split(" ")): scr = None
        en = "; ".join([x.strip() for x in (e.get("n") or "").split(";") if x.strip()][:3])
        zh_add(k, h, e.get("a"), tw, e.get("l"), scr, kind, e.get("p") or 0, short("　".join(senses[:2])), en, eqs.get(h))
    # 四川話's own words (from Wiktionary)
    for w in sc.get("w") or []:
        h, s, z = w.get("h"), w.get("s"), w.get("z")
        if not (h and s and z) or len(s.split(" ")) != len(z.split(" ")): continue
        ms = w.get("m") or []
        m = ("四川話，意思同「" + "」、「".join(ms[:3]) + "」。") if ms else "四川話的詞。"
        zh_add(h + "\t" + z + "#川", h, None, z, None, s, w.get("k", 2), 3, m, "; ".join((w.get("e") or [])[:3]), ms)
print(f"華語 words: {zh_count}", file=sys.stderr)

# ── 台語 ───────────────────────────────────────────────────────────────────────────────────────────────────────
tw_count = 0
d = load("dict.json")
meta = {"v": 1, "shards": SHARDS, "max": MAXLEN, "py": zy_py}
if d:
    en_file = load("tw_en.json") or {}
    tw_en = en_file.get("e") or {}
    gl = {k: [t.lstrip("~") for t in v.split("|") if t.lstrip("~")] for k, v in d.get("gl", [])}
    defs = d.get("defs") or {}
    dm, dt = defs.get("m") or {}, defs.get("t") or []
    dia = d.get("dia") or {}
    tok = d.get("tok") or {}            # (a word's tokens: "--" before a light tone, "_" between its parts)

    def tw_entry(k, via=None):
        codes = k.split("\t", 1)[1]
        e = {"k": k, "c": codes}
        if k in dia: e["d"] = dia[k]
        if k in tok: e["o"] = tok[k]
        m = "、".join(gl[k]) if gl.get(k) else (short(dt[dm[k]].split("\n")[0]) if k in dm and dm[k] < len(dt) else "")
        if m: e["m"] = m
        en = tw_en.get(k)
        if en: e["e"] = "; ".join(en.lstrip("*").split("; ")[:3])
        if via: e["v"] = via
        return e

    keys = []
    for h, codes in d.get("words", []):
        k = h + "\t" + codes
        if k not in dm and k not in gl: continue
        add("tw", h, tw_entry(k)); keys.append(k); tw_count += 1
    # (華語 → 台語: the 台語 words for a 華語 word, the more common first (cards.json's order); for a word 台語
    # writes the same way too (its own entry first), one or two more words with that meaning)
    heads = {k.split("\t", 1)[0] for k in keys}        # (the words that have an entry of their own)
    cards = load("cards.json") or {}
    rank = {c["k"]: i for i, c in enumerate(cards.get("cards", []))}
    by_term = {}
    for k in keys:
        for t in gl.get(k, []):
            if not (t in heads and k.split("\t", 1)[0] == t): by_term.setdefault(t, []).append(k)
    for t, ks in by_term.items():
        ks = sorted(ks, key=lambda k: rank.get(k, 10 ** 6))
        for k in ks[:2 if t in heads else 4]: add("tw", t, tw_entry(k, via=t), 6)
    meta["syl"] = d.get("syl") or {}
    meta["tl"] = {c: v[0] for c, v in (d.get("tl") or {}).items()}
    meta["pj"] = d.get("pj") or {}
    meta["places"] = d.get("places") or []
print(f"台語 words: {tw_count}", file=sys.stderr)

# ── 粵語 and 客語 ───────────────────────────────────────────────────────────────────────────────────────────────
def zh_like(name, lang):
    d = load(name)
    if not d: return 0, d
    n = 0
    for e in d.get("e", []):
        k, h, s = e.get("k"), e.get("h"), e.get("s")
        if not (k and h and s): continue
        senses = [x[0] for x in e.get("d") or [] if x and x[0]]
        o = {"k": k, "s": s}
        if e.get("v"): o["a"] = e["v"]          # (客語: each accent's reading)
        m = short("　".join(senses[:2]))
        if m: o["m"] = m
        en = "; ".join([x.strip() for x in (e.get("n") or "").split(";") if x.strip()][:3])
        if en and lang != "yue": o["e"] = en
        add(lang, h, o, 4)
        n += 1
    return n, d
yue_count, _ = zh_like("yue.json", "yue")
hak_count, hak = zh_like("hak.json", "hak")
if hak:
    meta["ht"] = hak.get("ht") or []
    meta["hz"] = hak.get("hz") or {}
    meta["hacc"] = hak.get("acc") or []
print(f"粵語 words: {yue_count}, 客語 words: {hak_count}", file=sys.stderr)

# ── written ────────────────────────────────────────────────────────────────────────────────────────────────────
os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT):
    if f.startswith("d-") and f.endswith(".json"): os.remove(os.path.join(OUT, f))
for lang in ("zh", "tw", "yue", "hak"):
    for i, sh in enumerate(shards[lang]):
        if sh:
            with open(os.path.join(OUT, f"d-{lang}-{i:03d}.json"), "w", encoding="utf-8") as f:
                json.dump(sh, f, ensure_ascii=False, separators=(",", ":"))
meta["zh"] = zh_count
meta["tw"] = tw_count
meta["yue"] = yue_count
meta["hak"] = hak_count
with open(os.path.join(OUT, "d-meta.json"), "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False, separators=(",", ":"))
print(f"Safari 查詞: {zh_count + tw_count} words → {OUT}", file=sys.stderr)
