# data2.json (full MOE build) -> data.json used by the converter website, the Safari extension and 方方詞卡.
# Keeps the old field layout (words, syl, tl, pj, defs, pos, ex, reg, own, au, gl, freq) so existing code keeps
# working, and adds the new information (dialects, alternatives, synonyms, topics, variants, ...).
import json, sys, re, collections, math
from anchor import parse, code_to_zhuyin, code_to_haolo, code_to_tl, code_to_poj

D = json.load(open(sys.argv[1]))
ESSAY = sys.argv[2]                          # rime-essay essay.txt (how common each character is)
OUT = sys.argv[3]

def codes_only(rs):
    out = []
    for t in rs.split():
        c = t.lstrip("^")
        if parse(c): out.append(c)
        elif t.startswith("~"): return None        # contains a syllable we can't spell
    return " ".join(out)

def needs_tokens(rs):
    return any(not parse(t) for t in rs.split())   # ^ capitals, -- light tone, spaces, punctuation

# entries with the same characters and reading (e.g. a word and the same word as a surname or place name)
# become one entry: meanings, topics and readings are merged
groups = collections.OrderedDict()
for e in D["E"]:
    c = codes_only(e["r"]) if "r" in e else None
    k = e["h"] + "\t" + c if c else None
    if k is None: continue
    groups.setdefault(k, []).append(e)
merged_into = {}
# (the same syllables, one with 輕聲 and one without, are words of their own: 的 --ê and 的 ê (我的冊); the one with
# 輕聲 has "--" in its key, 的\t-- e5)
def has_dash(e): return "--" in e["r"].split()
parts = []
for k, es in groups.items():
    dash = [e for e in es if has_dash(e)]; plain = [e for e in es if not has_dash(e)]
    if dash and plain:
        for e in dash: e["_dash"] = True
        parts += [plain, dash]
    else: parts.append(es)
for es in parts:
    base = es[0]
    for o in es[1:]:
        merged_into[o["i"]] = base["i"]
        # a meaning's own place readings move along with it
        for si, v in o.get("sd", {}).items():
            base.setdefault("sd", {})[str(int(si) + len(base.get("m", [])))] = v
        if o.get("m"): base.setdefault("m", []).extend(o["m"])
        for c in o.get("c", []):
            if c not in base.setdefault("c", []): base["c"].append(c)
        if o["r"] != base["r"]: base.setdefault("a", []).append([o["r"], ""])
        for a in o.get("a", []): base.setdefault("a", []).append(a)
        for p_, r in o.get("d", {}).items(): base.setdefault("d", {}).setdefault(p_, r)
        for p_, xs in o.get("dd", {}).items(): base.setdefault("dd", {}).setdefault(p_, xs)
        for p_ in o.get("dx", []):
            if base["d"].get(p_) == o["d"].get(p_) and p_ not in base.setdefault("dx", []): base["dx"].append(p_)
        if "au" not in base and "au" in o: base["au"] = o["au"]
        for f in ("sy", "an", "v"):
            for x in o.get(f, []):
                if x not in base.setdefault(f, []): base[f].append(x)
        if o.get("g") and not base.get("g"): base["g"] = o["g"]
        o["_merged"] = True

words, seen = [], set()
key_of = {}                                       # entry id -> key
defs_t, defs_m, pos, ex, reg, au, alt, dia, tok, sub, typ, cat, own, dex, dia2 = [], {}, {}, {}, {}, {}, {}, {}, {}, [], {}, {}, [], {}, {}
sdia = {}                                         # key -> {meaning number from 0: {place: codes}}
used = set()
collisions = 0
for e in D["E"]:
    if e.get("_merged"):
        continue
    if "r" not in e:
        key_of[e["i"]] = e["h"] + "\t"
        continue
    c = codes_only(e["r"])
    if not c:
        key_of[e["i"]] = e["h"] + "\t"
        continue
    # (the 輕聲 one of a pair: its "--" in its key)
    if e.get("_dash"): c = " ".join(t.lstrip("^") for t in e["r"].split() if t == "--" or parse(t.lstrip("^")))
    cc = " ".join(x for x in c.split() if x != "--")      # (its syllables)
    k = e["h"] + "\t" + c
    key_of[e["i"]] = k
    if k in seen:
        collisions += 1
        continue                                  # same characters + same reading: keep the first entry
    seen.add(k)
    words.append([e["h"], c])
    used.update(c.split())
    if needs_tokens(e["r"]): tok[k] = e["r"]
    if e.get("m"):
        lines = [m["t"] for m in e["m"]]
        text = lines[0] if len(lines) == 1 else "\n".join(f"{i + 1}. {t}" for i, t in enumerate(lines))
        defs_m[k] = len(defs_t); defs_t.append(text)
        if any(m["p"] for m in e["m"]): pos[k] = "|".join(m["p"] for m in e["m"])
        if any(m.get("x") for m in e["m"]):
            ex[k] = [m.get("x", []) for m in e["m"]]
            for m in e["m"]:
                for x in m.get("x", []):
                    used.update(re.findall(r"\{\^?([^}]+)\}", x[1]))
    if e.get("g"): reg[k] = e["g"]
    if "au" in e: au[k] = e["au"]
    if e.get("s"): sub.append(k)
    if e["t"] != 0: typ[k] = e["t"]
    if e["t"] == 5: own.append(k)
    if e.get("c"): cat[k] = e["c"]
    for a, label in e.get("a", []):
        ac = codes_only(a)
        if ac and ac != cc:
            alt.setdefault(k, []).append([ac, label] + ([a] if needs_tokens(a) else []))
            used.update(ac.split())
    for p, r in e.get("d", {}).items():
        rc = codes_only(r)
        if rc and rc != cc:
            dia.setdefault(k, {})[p] = rc
            used.update(rc.split())
            if p in e.get("dx", []): dex[k] = dex.get(k, "") + p     # MOE states it (not worked out by rule)
    for si, v in e.get("sd", {}).items():                        # a place's reading of one meaning (足 很: tsok)
        for p, r in v.items():
            rc = codes_only(r)
            if rc and rc != cc:
                sdia.setdefault(k, {}).setdefault(si, {})[p] = rc
                used.update(rc.split())
    for p, xs in e.get("dd", {}).items():                        # the place also says it these ways
        cs = [x for x in (codes_only(x) for x in xs) if x]
        if cs:
            dia2.setdefault(k, {})[p] = cs
            for x in cs: used.update(x.split())

for o, b_ in merged_into.items(): key_of[o] = key_of[b_]

# synonyms / antonyms (per meaning, plus whole-word links)
def links(field):
    out = {}
    for e in D["E"]:
        if e.get("_merged"): continue
        k = key_of.get(e["i"])
        if not k or k.endswith("\t") or k not in defs_m and field not in e and not any(field in m for m in e.get("m", [])):
            continue
        rec = {}
        for i, m in enumerate(e.get("m", [])):
            t = [key_of[x] for x in m.get(field, []) if x in key_of]
            if t: rec[str(i)] = t
        t = [key_of[x] for x in e.get(field, []) if x in key_of]
        if t: rec["e"] = t
        if rec and k not in out: out[k] = rec
    return out
sy, an = links("sy"), links("an")

# variant characters
var = collections.defaultdict(list)
for e in D["E"]:
    k = key_of.get(e["i"])
    if not k or k.endswith("\t"): continue
    for v in e.get("v", []):
        if k not in var[v]: var[v].append(k)

# 各地講法
cmp = []
for zh, items in D["cmp"]:
    row = []
    for p, han, r in items:
        rc = codes_only(r)
        row.append([p, han, rc or ""])
        if rc: used.update(rc.split())
    cmp.append([zh, row])

# names / surnames
def names(src):
    out = {}
    for ch, lst in src.items():
        row = []
        for r, t in lst:
            rc = codes_only(r)
            if rc:
                row.append([rc, t]); used.update(rc.split())
        if row: out[ch] = row
    return out
nm, sr = names(D["names"]), names(D["sur"])

# 華語 glossary, from the dictionary itself:
#  1) the short 華語 equivalent at the start of each meaning ("數目。" -> 數目)
#  2) word-level examples: 台語 word / its 華語 translation ("一睏仔" -> 一下子, marked ~)
HAN = re.compile(r"^[\u3400-\u9fff\uf900-\ufaff\U00020000-\U0003134f]+$")
def terms_of(text):
    out = []
    for t in re.split(r"[、，,；;]", text):
        t = t.strip().strip("「」『』（）()")
        if 1 <= len(t) <= 6 and HAN.match(t): out.append(t)
    return out
# 方言詞: the words only some places say for a meaning (詞彙比較) and the dictionary has no entry for (柑仔得, 金門,
# for 番茄): words of their own, marked with the places that say them (loc), each meaning pointing to the words most
# places say (看「臭柿仔」、「柑仔蜜」; lstd)
loc, lstd = {}, {}
PLACES_SHORT = [x[:2] for x in D["places"]]
hans = {w[0] for w in words}
first_key = {}
for h, c in words:
    k = h + "\t" + c
    if h not in first_key and k in defs_m: first_key[h] = k
# (which of the dictionary's entries a row's word is. A word of one character only when its reading or its
# meaning says so: 呼牛快跑's 喝 há is not 喝 huah "大聲喊叫", and 哈 ha̍h not 哈 ha "笑聲". Its own readings are
# MOE's, its 又音 and its places' (語音差異), not the ones 詞彙比較 itself gave; tones and the places' vowels
# (ɵ, ə, ɨ) aside. Longer words are the same word whatever the reading: 茶葉 tê-hiɵ̍h.)
own_r = collections.defaultdict(set)              # key -> its readings
own_t = collections.defaultdict(list)             # key -> its meanings
sound = set()                                     # (sound words, 哈 ha "笑聲": the tone tells them apart too)
for e in D["E"]:
    k = key_of.get(e["i"])
    if not k or k.endswith("\t") or k not in defs_m: continue
    for x in [e.get("r", "")] + [a[0] for a in e.get("a", [])] + \
             [f for pl, fs in e.get("sf", {}).items() if pl not in e.get("vx", []) for f in fs]:
        c = codes_only(x)
        if c: own_r[k].add(c)
    own_t[k] += [m.get("t", "") for m in e.get("m", [])]
    if any(m.get("p") in ("擬聲詞", "嘆詞") for m in e.get("m", [])): sound.add(k)
def loose(c, tone=False):
    return " ".join(re.sub(r"\d", ("C" if s[-1:] in "48" else "O") if tone else "", s)
                    .replace("ɵ", "ø").replace("ə", "e").replace("ɨ", "i") for s in c.split())
keys_of = collections.defaultdict(list)
for h, c in words:
    if h + "\t" + c in defs_m: keys_of[h].append(h + "\t" + c)
def entry_of(h, rcs, zh, key_in):
    if h in key_in: return key_in[h]
    for k in keys_of[h]:
        t = k in sound
        if any(loose(x, t) in {loose(r, t) for r in rcs} for x in own_r[k]): return k
    if len(h) > 1: return first_key.get(h)
    for k in keys_of[h]:
        if any(zh in [w.strip("「」『』（）() ") for w in re.split(r"[、，,；;。：:]", t)] for t in own_t[k]): return k
    return None
def tl_of(rc): return "-".join(code_to_tl(c) for c in rc.split())
add, order = {}, []
for zh, row in cmp:
    by_han, key_in, by_key = {}, {}, {}
    for p, han, rc in row:
        if not rc: continue
        by_han.setdefault(han, set()).add(p)
        k = han + "\t" + rc
        if k in defs_m and han not in key_in: key_in[han] = k
        by_key.setdefault(k, set()).add(p)
    cand = sorted(((h, ps) for h, ps in by_han.items() if h in hans), key=lambda x: -len(x[1]))   # (stable)
    std = []
    for h, _ in cand:
        k = entry_of(h, {rc for _, hh, rc in row if hh == h and rc}, zh, key_in)
        if k and k not in std: std.append(k)
        if len(std) == 3: break
    news = [k for k in by_key
            if not (k.split("\t")[0] in hans or not HAN.match(k.split("\t")[0]) or len(k.split("\t")[0]) != len(k.split("\t")[1].split()))]
    for k in news:
        ps = by_key[k]
        if k not in add: add[k] = {"places": set(), "groups": []}; order.append(k)
        w = add[k]
        w["places"].update(ps)
        if not any(g[0] == zh for g in w["groups"]):
            # (no usual word for it: what each place says, 臺北 喝 há, 臺南 嘵叱叱, and the others' 方言詞 as 近義)
            say = []
            if not std:
                by_w = collections.OrderedDict()           # word -> {reading: places}
                for p, hh, rc in row:
                    if rc and hh != k.split("\t")[0]: by_w.setdefault(hh, collections.OrderedDict()).setdefault(rc, set()).add(p)
                for hh, rs in by_w.items():
                    pl = set().union(*rs.values())
                    top = sorted(rs, key=lambda r: -len(rs[r]))[:3]       # (stable)
                    say.append(hh + " " + "/".join(tl_of(r) for r in top) + ("…" if len(rs) > 3 else "") +
                               "（" + ("各地" if len(pl) == len(PLACES_SHORT) else "、".join(PLACES_SHORT[x] for x in sorted(pl))) + "）")
            w["groups"].append([zh, std, say, [x for x in news if x != k] if not std else []])
# (one 方言詞 said differently in different places, 天遮: one entry, its reading the one most places say, the
# others as those places' readings)
by_h = collections.OrderedDict()
for k in order: by_h.setdefault(k.split("\t")[0], []).append(k)
order2 = []
for han, ks in by_h.items():
    main = max(ks, key=lambda x: len(add[x]["places"]))      # (the first among equals)
    order2.append(main)
    w = add[main]
    for k in ks:
        if k == main: continue
        o, rc = add[k], k.split("\t")[1]
        for p in sorted(o["places"]):
            if p in w["places"]:
                xs = dia2.setdefault(main, {}).setdefault(str(p), [])
                if rc not in xs: xs.append(rc)
            else:
                dia.setdefault(main, {})[str(p)] = rc
                dex[main] = dex.get(main, "") + str(p)
        used.update(rc.split())
        w["places"].update(o["places"])
        for g in o["groups"]:
            if not any(x[0] == g[0] for x in w["groups"]): w["groups"].append(g)
order = order2
main_of = {k: max(ks, key=lambda x: len(add[x]["places"])) for ks in by_h.values() for k in ks}
TYPE_LOCAL = D["types"].index("方言詞")
for k in order:
    w = add[k]
    han, rc = k.split("\t")
    lines, stds, sibs = [], [], []
    for zh, std, say, sib in w["groups"]:
        # (the meaning first: the usual words' meaning with its 華語 in it (妻子), else that 華語; then the usual
        # words to see: 看「某」…)
        ls = [re.sub(r"^\d+\.\s*", "", l) for x in std if x in defs_m for l in defs_t[defs_m[x]].split("\n")]
        ls = [l for l in ls if l and "看「" not in l]
        sd = next((l for l in ls if zh in l), ls[0] if ls else zh + "。")
        t = (sd + "看" + "、".join("「" + x.split("\t")[0] + "」" for x in std) + "。") if std else \
            "華語：" + zh + "。" + ("各地講法：" + "、".join(say) + "。" if say else "")
        if t in lines: continue
        lines.append(t); stds.append(std)
        sibs.append([] if std else list(dict.fromkeys(main_of[x] for x in sib if main_of[x] != k)))
    words.append([han, rc]); seen.add(k)
    used.update(rc.split())
    defs_m[k] = len(defs_t)
    defs_t.append(lines[0] if len(lines) == 1 else "\n".join(f"{i + 1}. {t}" for i, t in enumerate(lines)))
    typ[k] = TYPE_LOCAL
    loc[k] = sorted(w["places"])
    allk = []
    for st in stds:
        for x in st:
            if x not in allk: allk.append(x)
    rec = {str(i): st or sb for i, (st, sb) in enumerate(zip(stds, sibs)) if st or sb}
    if rec: sy[k] = rec
    if allk:
        lstd[k] = allk
        # (and the other way: the usual word lists it as a 近義 of its own, with the places that say it)
        for x in allk:
            back = sy.setdefault(x, {}).setdefault("e", [])
            if k not in back: back.append(k)

# 合音: a word some places say in fewer syllables (佗位: 宜蘭, 臺南, 新竹… tuē, tueh) is an entry of its own too,
# marked with those places and pointing to the word it's the 合音 of
cont = collections.OrderedDict()
raw_tok = {}                                       # (漢字, codes) -> the reading as written (with "--")
for _, row in D["cmp"]:
    for p, han, rs in row:
        c = codes_only(rs) if rs else None
        if c: raw_tok.setdefault((han, c), rs)
def ps_all(han, rs):
    return {p for _, row in cmp for p, h, r in row if h == han and r == rs}
for zh, row in cmp:
    for p, han, rs in row:
        rc = codes_only(rs) if rs else None
        if not rc or not HAN.match(han) or han not in first_key: continue
        if len(rc.split()) >= len(han): continue
        main = first_key[han]
        # (MOE gives it already, for everyone, 下昏 合音唸作 i̋ng: not a word of some places)
        if any(a[0] == rc and len(a) > 1 and a[1] == "合" for a in alt.get(main, [])) and len(ps_all(han, rs)) >= 10: continue
        k = han + "\t" + rc
        if k in seen and k not in cont: continue
        cont.setdefault(k, set()).add(p)
        raw = raw_tok.get((han, rc))
        if raw and needs_tokens(raw): tok[k] = raw                     # (硩落去 te--loih: its light tone)
for k, ps in cont.items():
    han, rc = k.split("\t")
    main = first_key[han]
    words.append([han, rc]); seen.add(k)
    used.update(rc.split())
    defs_m[k] = len(defs_t)
    defs_t.append("「" + han + "」的合音。看「" + han + "」。")
    typ[k] = TYPE_LOCAL
    loc[k] = sorted(ps)
    lstd[k] = [main]
    sy[k] = {"0": [main]}
    back = sy.setdefault(main, {}).setdefault("e", [])
    if k not in back: back.append(k)
print("合音 entries:", len(cont), file=sys.stderr)

G = collections.defaultdict(dict)
for e in D["E"]:
    if e.get("_merged") or e["i"] not in key_of: continue
    k = key_of[e["i"]]
    if k.endswith("\t") or k not in seen: continue
    for m in e.get("m", []):
        g = m["t"].split("。")[0]
        if len(g) <= 12:
            for t in terms_of(g): G[k].setdefault(t, 1)
        for x in m.get("x", []):
            w, zh = x[0], x[2]
            if HAN.match(w) and len(w) <= 5 and len(zh) <= 6 and HAN.match(zh):
                xk = w + "\t" + " ".join(re.findall(r"\{\^?([^}]+)\}", x[1]))
                if xk in seen: G[xk].setdefault(zh, 2)
gl = {k: "|".join(t if s_ == 1 else "~" + t for t, s_ in v.items()) for k, v in G.items()}
# + the 華語 words of 詞彙比較
for zh, row in cmp:
    for p, han, rc in row:
        k = han + "\t" + rc
        if k in seen:
            terms = gl.get(k, "").split("|") if gl.get(k) else []
            if zh not in [t.lstrip("~") for t in terms]: terms.append(zh)
            gl[k] = "|".join(terms)

for c in sorted(used):
    try:
        parse(c) and code_to_haolo(c)
    except Exception: print("BAD CODE", repr(c))
# 聲調顏色 can write a syllable in the tone it's said in after tone sandhi (通行 5→7, 8→4; 泉 5→3, 8→3;
# checked syllables ending in h lose the h: 4→2, 8→3), so those spellings are needed too
def sandhi_codes(c):
    p = parse(c)
    if not p: return []
    ini, nas, vow, fin, t = p
    stop = bool(vow) and bool(fin)
    base = c[:-1]
    if t in (4, 8):
        targets = ([2] if t == 4 else [3]) if not stop else ([8] if t == 4 else [4, 3])
    else:
        targets = {1: [7], 2: [1, 5], 3: [2], 5: [7, 3], 6: [3], 7: [3]}.get(t, [])
    # before 仔: 2, 3 → 1; 1, 5, 6, 7, 8 and 4 ending in h → 7; 4 ending in p/t/k → 8
    targets = targets + ({2: [1], 3: [1], 1: [7], 5: [7], 6: [7], 7: [7], 8: [7]}.get(t, []) if t != 4 else ([8] if stop else [7]))
    return [base + str(n) for n in targets]
for c in list(used):
    for n in sandhi_codes(c):
        try:
            if parse(n) and code_to_haolo(n) and code_to_tl(n) and code_to_poj(n) and code_to_zhuyin(n): used.add(n)
        except Exception: pass
syl = {c: [code_to_zhuyin(c), code_to_haolo(c)] for c in sorted(used) if parse(c)}
tl = {}
for c in syl:
    m = code_to_tl(c)
    num = re.sub(r"[̀-ͯ]", "", __import__("unicodedata").normalize("NFD", m)) + c[-1]
    tl[c] = [m, num]
pj = {c: code_to_poj(c) for c in syl}

# reading in context: for characters with several readings, how often each reading appears in the
# dictionary's example sentences, and next to which characters (helps the converter pick the reading)
HANC = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\U00020000-\U0003134f\u3007]")
single = collections.defaultdict(set)
for h, c in words:
    if len(h) == 1: single[h].add(" ".join(x for x in c.split() if x != "--"))
amb = {h for h, cs in single.items() if len(cs) > 1}
cu, cl, cr = collections.Counter(), collections.Counter(), collections.Counter()
for senses in ex.values():
    for xs in senses:
        for x in xs:
            hs = HANC.findall(x[0]); cs = re.findall(r"\{\^?([^}]+)\}", x[1])
            if len(hs) != len(cs): continue
            for i, (h, c) in enumerate(zip(hs, cs)):
                if h not in amb or c not in single[h]: continue
                cu[h + "\t" + c] += 1
                if i > 0: cl[hs[i - 1] + "\t" + h + "\t" + c] += 1
                if i + 1 < len(hs): cr[h + "\t" + c + "\t" + hs[i + 1]] += 1
ctx = {"u": dict(cu), "l": dict(cl), "r": dict(cr)}

# how common each character is: ln(count) in rime-essay
counts = collections.Counter()
for line in open(ESSAY, encoding="utf-8"):
    p_ = line.rstrip("\n").split("\t")
    if len(p_) >= 2 and len(p_[0]) == 1 and p_[1].isdigit(): counts[p_[0]] += int(p_[1])
chars = {ch for h, _ in words for ch in h}
freq = {ch: round(math.log(counts[ch]), 1) for ch in sorted(chars) if counts[ch] > 0}

out = {
    "v": 8, "words": words, "syl": syl, "tl": tl, "pj": pj,
    "defs": {"t": defs_t, "m": defs_m}, "pos": pos, "ex": ex, "reg": reg, "own": own, "au": au,
    "gl": [[k, v] for k, v in gl.items()], "freq": freq, "dex": dex, "ctx": ctx, "dia2": dia2, "sdia": sdia,
    "places": D["places"], "g1": D["g1"], "types": D["types"], "cats": D["cats"],
    "alt": alt, "dia": dia, "tok": tok, "sub": sub, "typ": typ, "cat": cat,
    "sy": sy, "an": an, "var": var, "cmp": cmp, "names": nm, "sur": sr, "loc": loc, "lstd": lstd,
}
json.dump(out, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
print("words", len(words), "collisions", collisions, "syllables", len(syl))
print("defs", len(defs_t), "examples", sum(len(x) for v in ex.values() for x in v), "audio", len(au))
print("alt", len(alt), "dialect", len(dia), "tokens", len(tok), "sub", len(sub), "syn", len(sy), "ant", len(an))
print("variants", len(var), "cmp", len(cmp), "names", len(nm), "surnames", len(sr), "gl", len(gl), "cat", len(cat))
