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
import json, os, re, sys, unicodedata

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


def shard_of(lang, word):
    # (瑞典語: by the first two letters, so the files of common first letters aren't big)
    if lang == "sv": return (ord(word[0]) * 31 + (ord(word[1]) if len(word) > 1 else 0)) % SHARDS
    return ord(word[0]) % SHARDS


def add(lang, word, e, most=6):
    if not word or (len(word) > MAXLEN and lang != "sv"): return
    d = shards[lang][shard_of(lang, word)]
    lst = d.setdefault(word, [])
    if len(lst) < most and not any(x["k"] == e["k"] for x in lst): lst.append(e)


# ── English → the Chinese languages' words (the pop-up looks up an English word too): "eat" → 吃 (華語), 食 (台語)…
EN = {}
EN_ORDER = [0]


def en_norm(t):
    t = re.sub(r"\([^)]*\)|\[[^\]]*\]", "", t).strip().lower()
    t = re.sub(r"^(to|a|an|the) ", "", t)
    return re.sub(r"[.!?…]+$", "", t).strip()


def en_add(lang, h, en):
    # each short meaning (3 words at most), the earlier ones of a word the better, and short words before long ones
    if not en or not h: return
    seen = set()
    for i, seg in enumerate(re.split(r"[;/]", en.lstrip("*"))[:6]):
        for part in seg.split(","):
            t = en_norm(part)
            if not t or t in seen or len(t) > 30 or len(t.split()) > 3 or not re.match(r"[a-z]", t): continue
            seen.add(t)
            EN_ORDER[0] += 1
            EN.setdefault(t, {}).setdefault(lang, []).append((i * 2 + (0 if len(h) <= 2 else 1), EN_ORDER[0], h))


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
        en_add("zh", h, e.get("n"))
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
        en_add("tw", h, tw_en.get(k))
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
        en_add(lang, h, e.get("n"))
        n += 1
    return n, d
yue_count, _ = zh_like("yue.json", "yue")
hak_count, hak = zh_like("hak.json", "hak")
if hak:
    meta["ht"] = hak.get("ht") or []
    meta["hz"] = hak.get("hz") or {}
    meta["hacc"] = hak.get("acc") or []
print(f"粵語 words: {yue_count}, 客語 words: {hak_count}", file=sys.stderr)

# ── 瑞典語 (sv.json, Folkets lexikon): by the word and each of its forms, in small letters ─────────────────────────
shards["sv"] = [dict() for _ in range(SHARDS)]
sv_count = 0
sv = load("sv.json")
if sv:
    es = sv.get("e", [])
    # (the same as the app's ZhDict.svFix: -are / -ast(e) on an adjective or adverb is its comparative or superlative,
    # an ending, not -are of a person; a phrase (hitta på) is its words' morphemes with a space ("_:w") between them)
    by_plain = {}
    for i, e in enumerate(es):
        for w in [e.get("h", "")] + (e.get("m") or []):
            by_plain.setdefault(w.lower(), []).append(i)

    def describes(w):
        return any(set(es[i].get("w") or []) & {"形容詞", "副詞"} for i in by_plain.get(w.lower(), []))

    def parse(s):
        out = []
        for x in (s or "").split():
            p = x.split(":")
            if len(p) >= 2 and p[0]: out.append([" " if p[1] == "w" else p[0], p[1], p[2] if len(p) > 2 else ""])
        return out

    def code(m): return "_:w" if m[1] == "w" else m[0] + ":" + m[1] + (":" + m[2] if m[2] else "")

    def for_form(form, lemma, ms):
        low = form.lower()
        ms = ms or [[lemma, "r", ""]]
        def fits(lst):
            t = "".join(m[0] for m in lst).lower()
            return bool(lst) and low.startswith(t)
        use = list(ms)
        while use and use[-1][1] == "e": use.pop()
        if not fits(use) or low == lemma.lower(): use = list(ms)
        if not fits(use):
            t = "".join(m[0] for m in ms).lower()
            n = 0
            while n < len(t) and n < len(low) and t[n] == low[n]: n += 1
            cut, at = [], 0
            for m in ms:
                if at >= n: break
                take = min(len(m[0]), n - at)
                cut.append([m[0][:take], m[1], m[2]]); at += take
            use = cut
        out, at = [], 0
        for m in use:
            if at + len(m[0]) > len(form): break
            out.append([form[at:at + len(m[0])], m[1], m[2]]); at += len(m[0])
        if at < len(form): out.append([form[at:], "e", ""])
        return out

    def word_morphemes(w):
        idx = [i for i in by_plain.get(w.lower(), []) if " " not in es[i].get("h", "")]
        if not idx: return []
        e = next((es[i] for i in idx if es[i]["h"].lower() == w.lower()), es[idx[0]])
        ms = parse(e.get("s"))
        if e["h"].lower() == w.lower():
            if not ms or "".join(m[0] for m in ms).lower() != w.lower(): return [[w, "r", ""]]
        return for_form(w, e["h"], ms)

    for e in es:
        h = e.get("h", "")
        if " " in h: continue
        ms = parse(e.get("s"))
        noun = bool(set(e.get("w") or []) & {"名詞", "動詞"})
        if ms and len(ms) >= 2 and ms[-1][1] == "s" and ms[-1][0].lower() == "are" and not noun:
            stem = "".join(m[0] for m in ms[:-1])
            root = ms[-2][2] or ms[-2][0]
            if set(e.get("w") or []) & {"形容詞", "副詞"} or describes(stem) or describes(root):
                ms[-1][1] = "e"
                e["s"] = " ".join(code(m) for m in ms)
        elif not ms and not noun:
            for end in ("aste", "ast", "are"):
                if h.lower().endswith(end) and len(h) > len(end) + 1 and describes(h[:-len(end)]):
                    st = h[:-len(end)]
                    e["s"] = st + ":r:" + st.lower() + " " + h[-len(end):] + ":e"
                    break
    def headword(w): return any(es[i]["h"].lower() == w.lower() and " " not in es[i]["h"] for i in by_plain.get(w.lower(), []))
    # splits that make two words better: det|s|amma → det|samma (samma is a word), allt|ing → all|ting
    for e in es:
        ms = parse(e.get("s"))
        if len(ms) < 2: continue
        changed = False
        j = 0
        while j + 1 < len(ms):
            if ms[j][1] == "l" and ms[j][0].lower() == "s" and ms[j + 1][1] == "r" and j > 0 and len(ms[j + 1][0]) >= 3 and headword("s" + ms[j + 1][0]):
                t = ms[j][0] + ms[j + 1][0]
                ms[j + 1] = [t, "r", t.lower()]
                del ms[j]
                changed = True
                continue
            if ms[j][1] == "r" and ms[j + 1][1] == "s" and len(ms[j][0]) >= 4 and j + 2 == len(ms):
                x, sfx = ms[j][0], ms[j + 1][0]
                a, w2 = x[:-1], x[-1:] + sfx
                if len(a) >= 3 and len(w2) >= 4 and headword(a) and headword(w2):
                    ms[j] = [a, "r", a.lower()]
                    ms[j + 1] = [w2, "r", w2.lower()]
                    changed = True
            j += 1
        if changed: e["s"] = " ".join(code(m) for m in ms)
    # o- that isn't "not": only where the dictionary has the o-word both ways, ovan "above" and o|van "unaccustomed",
    # and in words made from the "above" one (ovan|på); olycka, olycklig, ovanlig keep their o-
    NEG = re.compile(r"\b(un|in|im|ir|il|non|dis|mis)\w|\bnot\b|\bwithout\b|\bno\b|\bbad|不|非|無|沒|未|失", re.I)
    def negated(e): return bool(NEG.search(" ".join([e.get("n") or ""] + (e.get("jp") or []))))
    def both_ways(w):
        hs = [es[i] for i in by_plain.get(w.lower(), []) if es[i]["h"].lower() == w.lower()]
        return any(not negated(x) for x in hs) and any(negated(x) for x in hs)
    for e in es:
        ms = parse(e.get("s"))
        if len(ms) < 2 or ms[0][1] != "p" or ms[0][0].lower() != "o" or ms[1][1] != "r": continue
        if not both_ways("o" + ms[1][0]) or negated(e): continue
        t = ms[0][0] + ms[1][0]
        ms[1] = [t, "r", t.lower()]
        del ms[0]
        e["s"] = " ".join(code(m) for m in ms)
    # -ning that's -ing on a verb ending in -n (var|ning → varn|ing: varna, not vara)
    def is_verb(w): return any("動詞" in (es[i].get("w") or []) and es[i]["h"].lower() == w.lower() for i in by_plain.get(w.lower(), []))
    for e in es:
        ms = parse(e.get("s"))
        changed = False
        for j in range(1, len(ms)):
            if ms[j][1] == "s" and ms[j][0].lower() == "ning" and ms[j - 1][1] == "r" and is_verb(ms[j - 1][0] + "na"):
                ms[j - 1] = [ms[j - 1][0] + "n", "r", (ms[j - 1][0] + "na").lower()]
                ms[j] = [ms[j][0][1:], "s", ""]
                changed = True
        if changed: e["s"] = " ".join(code(m) for m in ms)
    # verbs made of a short verb (omhänder|ta): its forms say so (omhändertog); the part before it and the short verb
    SHORT = [("ta", "tog"), ("dra", "drog"), ("ge", "gav"), ("be", "bad"), ("gå", "gick"), ("se", "såg"), ("få", "fick"),
             ("stå", "stod"), ("slå", "slog"), ("dö", "dog"), ("le", "log")]
    PREFIXES = sorted(["miss", "sam", "sär", "van", "åter", "över", "under", "efter", "före", "fram", "till", "upp", "ut",
                       "in", "an", "av", "be", "bi", "er", "för", "ge", "mot", "med", "om", "o", "ur", "all", "icke", "anti",
                       "super", "mini", "multi", "inter", "ex", "re", "pre", "post", "sub", "trans"], key=lambda x: -len(x))
    for e in es:
        h = e.get("h", "")
        if " " in h or "動詞" not in (e.get("w") or []): continue
        ms = parse(e.get("s"))
        if ms and ms[-1][1] != "e": continue
        low = h.lower()
        forms = [f.lower().replace("|", "") for f in e.get("m") or []]
        for v, past in SHORT:
            if not (low.endswith(v) and len(low) > len(v) + 1): continue
            front = h[:-len(v)]
            if front.lower() + past not in forms: continue
            pm = word_morphemes(front)
            if not pm:
                fl = front.lower()
                p = next((x for x in PREFIXES if fl.startswith(x) and len(fl) - len(x) >= 3 and by_plain.get(fl[len(x):])), None)
                pm = [[front[:len(p)], "p", ""], [front[len(p):], "r", ""]] if p else [[front, "r", ""]]
            e["s"] = " ".join(code(m) for m in pm + [[h[-len(v):], "r", v]])
            break
    for e in es:
        h = e.get("h", "")
        if " " in h and not parse(e.get("s")):
            out = []
            for j, w in enumerate(h.split(" ")):
                if j: out.append([" ", "w", ""])
                out += word_morphemes(w) or [[w, "r", ""]]
            e["s"] = " ".join(code(m) for m in out)

    by_word = {}
    for e in es:
        by_word.setdefault(e.get("h", "").lower(), []).append(e)

    def real(e): return [x for x in e.get("jp") or [] if not x.startswith("≈")]
    def guessed(e): return [x[1:] for x in e.get("jp") or [] if x.startswith("≈")]

    def sv_gloss(e):
        if real(e): return real(e)[0]
        if guessed(e): return "≈" + guessed(e)[0]
        return short((e.get("n") or "").split(";")[0].strip(), 30)

    for e in es:
        k, h = e.get("k"), e.get("h")
        if not (k and h): continue
        o = {"k": k, "s": e.get("s") or ""}
        if e.get("w"): o["w"] = e["w"][0]
        # (華語 guessed from the English: kept apart, the pop-up shows it when its 設定 says)
        if real(e): o["m"] = "、".join(real(e)[:4])
        elif guessed(e): o["q"] = "、".join(guessed(e)[:3])
        en = "; ".join([x.strip() for x in (e.get("n") or "").split(";") if x.strip()][:3])
        if en: o["e"] = short(en, 100)
        # (each root's meaning: the word it comes from)
        g = {}
        for i, m in enumerate((e.get("s") or "").split()):
            p = m.split(":")
            if len(p) >= 2 and p[1] == "r":
                lw = (p[2] if len(p) > 2 else p[0]).lower()
                # (each entry's first meaning: grund 膚淺／基礎, the adjective and the noun)
                gs = []
                for r in by_word.get(lw, []):
                    if r.get("k") == k: continue
                    t = sv_gloss(r)
                    if t and t not in gs: gs.append(t)
                if gs: g[str(i)] = "／".join(gs[:2])
        if g: o["g"] = g
        for w in [h] + (e.get("m") or []):
            w = w.lower()
            if w and len(w) <= 40: add("sv", w, o, 4)
        sv_count += 1
print(f"瑞典語 words: {sv_count}", file=sys.stderr)

# ── written ────────────────────────────────────────────────────────────────────────────────────────────────────
os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT):
    if f.startswith("d-") and f.endswith(".json"): os.remove(os.path.join(OUT, f))
for lang in ("zh", "tw", "yue", "hak", "sv"):
    for i, sh in enumerate(shards[lang]):
        if sh:
            with open(os.path.join(OUT, f"d-{lang}-{i:03d}.json"), "w", encoding="utf-8") as f:
                json.dump(sh, f, ensure_ascii=False, separators=(",", ":"))
# (English: by the word's first two letters, like 瑞典語's; each language's 3 best words)
en_sh = [dict() for _ in range(SHARDS)]
for t, by in EN.items():
    o = {}
    for lang, lst in by.items():
        hs = []
        for _, _, h in sorted(lst):
            if h not in hs: hs.append(h)
            if len(hs) >= 3: break
        o[lang] = hs
    en_sh[shard_of("sv", t)][t] = o
for i, sh in enumerate(en_sh):
    if sh:
        with open(os.path.join(OUT, f"d-en-{i:03d}.json"), "w", encoding="utf-8") as f:
            json.dump(sh, f, ensure_ascii=False, separators=(",", ":"))
meta["en"] = len(EN)
meta["zh"] = zh_count
meta["tw"] = tw_count
meta["yue"] = yue_count
meta["hak"] = hak_count
meta["sv"] = sv_count
with open(os.path.join(OUT, "d-meta.json"), "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False, separators=(",", ":"))
print(f"Safari 查詞: {zh_count + tw_count} words → {OUT}", file=sys.stderr)
