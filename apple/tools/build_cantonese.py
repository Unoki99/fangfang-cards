# 粵語 (Cantonese) data -> FangfangCards/yue.json, from sources anyone can download:
#
#   python3 tools/build_cantonese.py SRC_DIR FangfangCards/yue.json [kaikki-chinese.jsonl|-]
#
# Everything in yue.json may be shared (CC BY-SA 4.0, see licenses/yue-data.txt), so it can be in the repository.
#
# SRC_DIR holds:
#   cedict_ts.u8          CC-CEDICT (CC BY-SA 4.0)                  the words and their English meanings
#   CC-CANTO.txt          CC-Canto (Pleco, CC BY-SA 3.0)            Cantonese words, with Jyutping and English
#   READINGS.txt          CC-Canto's Cantonese readings for CC-CEDICT (CC BY-SA 3.0)
#   jyut6ping3.words.dict.yaml, jyut6ping3.chars.dict.yaml, essay-cantonese.txt
#                         rime-cantonese (CC BY 4.0 / ODbL)          checked Jyutping, how common each word is
#   yyzd.txt              開放粵語字典 (kfcd/yyzd, CC BY 3.0)         characters: readings, meaning (in 中文), words
#                         (the Jyutping one: dist/tsv/繁體/粵語字典_(粵拼).txt)
# optional: Wiktionary's Chinese entries as extracted by kaikki.org (wiktextract, CC BY-SA 4.0):
#   https://kaikki.org/dictionary/Chinese/kaikki.org-dictionary-Chinese.jsonl
#   for Cantonese meanings, example sentences with translations and the Mandarin word with the same meaning.
#
# The output, one entry per word and reading:
#   {"h": 繁體, "s": 簡體 (if different), "j": "jyut6 ping3", "en": [English meanings], "yue": 1 if a Cantonese
#    word (not shared with standard written Chinese), "f": how common (higher = more), "src": which sources,
#    and from Wiktionary: "wk": [{"g": meaning, "p": word class, "l": labels, "x": [[粵語, jyutping, English]]}],
#    "au": a recording (Wikimedia Commons), "zh": [Mandarin words with the same meaning]}
# and "chars": {字: [[jyutping, 中文 meaning, words], ...]} with the usual reading first.
import json, os, re, sys, collections

SRC, OUT = sys.argv[1], sys.argv[2]
KAIKKI = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "-" else None
# (a 4th argument, zh.json, was used for the radicals: no longer, see below)
P = lambda n: os.path.join(SRC, n)

JP = re.compile(r"^[a-z]+[1-6]$")

def clean_jp(s):
    """'jat1 se1 se1' -> the same, or None when a syllable isn't Jyutping (letters, punctuation…)"""
    sy = s.lower().replace(",", " ").split()
    sy = [x for x in sy if x not in ("，", "·", "-")]
    return " ".join(sy) if sy and all(JP.match(x) for x in sy) else None

def senses(defs):
    """'/a/b/CL:個|个[ge4]/' -> ['a', 'b'] (measure words kept as their own line)"""
    out = []
    for d in defs.strip("/").split("/"):
        d = d.strip()
        if d and d not in out: out.append(d)
    return out

LINE = re.compile(r"^(\S+) (\S+) \[([^\]]*)\](?: \{([^}]*)\})? /(.*)/\s*$")

# ------------------------------------------------------------------ CC-CEDICT + its Cantonese readings
reading = {}            # (trad, simp, pinyin) -> jyutping
for line in open(P("READINGS.txt"), encoding="utf-8"):
    if line.startswith("#"): continue
    m = re.match(r"^(\S+) (\S+) \[([^\]]*)\] \{([^}]*)\}", line)
    if m:
        j = clean_jp(m.group(4))
        if j: reading[(m.group(1), m.group(2), m.group(3).replace(" ", "").lower())] = j

entries = collections.OrderedDict()     # (h, j) -> entry

def entry(h, s, j):
    k = (h, j)
    e = entries.get(k)
    if e is None:
        e = entries[k] = {"h": h, "s": s if s != h else None, "j": j, "en": [], "yue": 0, "src": []}
    return e

no_reading = 0
later = []
for line in open(P("cedict_ts.u8"), encoding="utf-8"):
    if line.startswith("#"): continue
    m = LINE.match(line.rstrip("\n"))
    if not m: continue
    h, s, py, _, defs = m.groups()
    j = reading.get((h, s, py.replace(" ", "").lower()))
    if not j:
        # no CC-Canto reading: rime-cantonese's, when it has the word (read below)
        later.append((h, s, defs)); continue
    e = entry(h, s, j)
    for d in senses(defs):
        if d not in e["en"]: e["en"].append(d)
    if "cedict" not in e["src"]: e["src"].append("cedict")

# ------------------------------------------------------------------ CC-Canto: Cantonese words (and meanings that differ)
canto = 0
for line in open(P("CC-CANTO.txt"), encoding="utf-8"):
    if line.startswith("#"): continue
    m = LINE.match(line.rstrip("\n"))
    if not m or not m.group(4): continue
    h, s, _, jy, defs = m.groups()
    j = clean_jp(jy)
    if not j: continue
    e = entry(h, s, j)
    new = [d for d in senses(defs) if d not in e["en"]]
    e["en"] = new + e["en"]             # the Cantonese meaning first
    if "cedict" not in e["src"]: e["yue"] = 1
    if "canto" not in e["src"]: e["src"].append("canto")
    canto += 1

# ------------------------------------------------------------------ rime-cantonese: checked readings, how common
freq = collections.Counter()
for line in open(P("essay-cantonese.txt"), encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) == 2 and p[1].isdigit(): freq[p[0]] = int(p[1])

rime_words = collections.defaultdict(list)       # word -> readings rime-cantonese gives it
def read_rime(name):
    body = False
    for line in open(P(name), encoding="utf-8"):
        if line.startswith("..."): body = True; continue
        if not body or line.startswith("#") or not line.strip(): continue
        p = line.rstrip("\n").split("\t")
        if len(p) < 2: continue
        j = clean_jp(p[1])
        if not j: continue
        w = 1.0
        if len(p) > 2 and p[2].endswith("%"):
            try: w = float(p[2][:-1]) / 100
            except ValueError: pass
        rime_words[p[0]].append((j, w))
read_rime("jyut6ping3.words.dict.yaml")
read_rime("jyut6ping3.chars.dict.yaml")

for h, s, defs in later:
    rs = rime_words.get(h)
    if not rs: no_reading += 1; continue
    e = entry(h, s, rs[0][0])
    for d in senses(defs):
        if d not in e["en"]: e["en"].append(d)
    if "cedict" not in e["src"]: e["src"].append("cedict")
    e["yue"] = 0

# a word with a CC-CEDICT reading that rime-cantonese spells differently (and has only one reading for):
# rime-cantonese is checked by hand and newer, so its reading is used
fixed = 0
for (h, j), e in list(entries.items()):
    rs = rime_words.get(h)
    if len(h) > 1 and rs and len({r for r, _ in rs}) == 1 and rs[0][0] != j and (h, rs[0][0]) not in entries:
        del entries[(h, j)]
        e["j"] = rs[0][0]
        entries[(h, e["j"])] = e
        fixed += 1

# Cantonese words that only rime-cantonese has (common ones: no meaning yet, Wiktionary may add one)
only_rime = 0
heads = {h for h, _ in entries}
for h, rs in rime_words.items():
    if len(h) < 2 or freq[h] < 200 or h in heads: continue
    e = entry(h, None, rs[0][0]); e["src"].append("rime"); e["yue"] = 1; only_rime += 1

# ------------------------------------------------------------------ Wiktionary (kaikki.org), optional
# Each word's own Cantonese meanings ("wk": [{"g": meaning, "p": word class, "l": labels, "x": [[粵語, jyutping,
# English]]}]), a recording when there is one ("au", from Wikimedia Commons), and from the dialect tables
# ("dialectal synonyms"), the Mandarin words with the same meaning ("zh").
wikt = wikt_ex = wikt_zh = wikt_au = 0
SUP = str.maketrans("⁰¹²³⁴⁵⁶⁷⁸⁹", "0123456789")
def jp_wikt(s):
    """'king¹ gai⁶⁻²' -> 'king1 gai2' (a changed tone: the one that's said); None if it isn't Jyutping"""
    s = (s or "").split(",")[0].split("/")[0].translate(SUP)
    s = re.sub(r"(\d)-(\d)", r"\2", s.replace("⁻", "-"))
    s = re.sub(r"[.,!?;:「」“”\"'()（），。！？；：…]", " ", s)
    return clean_jp(s)
VARIETIES = {"Mandarin", "Hokkien", "Teochew", "Wu", "Shanghainese", "Hakka", "Min-Nan", "Min-Dong", "Min-Bei",
             "Taiwanese-Hokkien", "Xiang", "Gan", "Jin", "Puxian-Min", "Hainanese", "Leizhou-Min", "Changsha",
             "Dungan", "Sichuanese", "Taishanese", "Pinghua", "Classical-Chinese", "Literary-Chinese"}
LABEL_SKIP = {"Cantonese", "Guangzhou", "Hong-Kong", "Hong Kong", "Macau", "Hong-Kong-Cantonese"} | VARIETIES
zh_of = collections.defaultdict(collections.Counter)    # Cantonese word -> Mandarin words (dialect tables)
if KAIKKI:
    for line in open(KAIKKI, encoding="utf-8-sig"):
        try: w = json.loads(line)
        except ValueError: continue
        if w.get("lang_code") != "zh": continue
        h = w.get("word", "")
        if not h or h.isascii(): continue
        # --- the dialect tables: each starts again at the "formal" (書面語) row. The Mandarin words: Taiwan's
        # spoken ones count most, the written ones a little (Beijing's 兒 words are left out)
        tables, cur, last_formal = [], None, False
        for x in w.get("synonyms", []):
            t = set(x.get("tags") or []) | set(x.get("raw_tags") or [])
            formal = "Written-vernacular-Chinese" in t
            if formal and not last_formal: cur = {"m": collections.Counter(), "c": []}; tables.append(cur)
            last_formal = formal
            if cur is None or not x.get("word"): continue
            places = {a for a in t if a[:1].isupper() and " " not in a.replace("Hong Kong", "")}
            if formal: cur["m"][x["word"]] += 1
            elif any("Mandarin" in a for a in t) and "Taiwan" in places:
                cur["m"][x["word"]] += 3
            elif "Cantonese" in t and places & {"Guangzhou", "Hong Kong"} and places <= {"Cantonese", "Guangzhou", "Hong Kong", "Macau"}:
                if x["word"] not in cur["c"]: cur["c"].append(x["word"])
        for tb in tables:
            # (a long list of Cantonese words is a list of slang or euphemisms (死, …): not equivalents)
            if len(tb["c"]) > 5: continue
            for c in tb["c"]:
                # a single character is in many tables for one of its meanings: only its own page's
                if len(c) == 1 and c != h and len(tb["c"]) > 1: continue
                for m, n in tb["m"].items():
                    if m != c: zh_of[c][m] += n
        # --- the word's own Cantonese reading
        j = None; au = None
        for s in w.get("sounds", []):
            t = set(s.get("tags") or [])
            if "Cantonese" in t and "Jyutping" in t and "Guangzhou" in t:
                if not j and s.get("zh_pron"): j = jp_wikt(s["zh_pron"])
                if not au and s.get("mp3_url"): au = s["mp3_url"]
        if not j or len(j.split()) != len(h): continue
        senses_out = []
        for s in w.get("senses", []):
            t = set(s.get("tags") or [])
            other = t & VARIETIES
            if other and "Cantonese" not in t: continue           # Mandarin only, Hokkien only…
            g = (s.get("glosses") or [""])[-1].strip()
            if not g or "form-of" in t or "alt-of" in t: continue
            ex = []
            for x in s.get("examples", []):
                xt = set(x.get("tags") or [])
                if "Jyutping" not in xt or "Simplified-Chinese" in xt: continue
                text, rom = x.get("text", ""), jp_wikt(x.get("roman", "")) and x.get("roman", "").translate(SUP)
                en = x.get("english") or x.get("translation") or ""
                if text and rom and en and len(text) <= 40 and len(ex) < 3:
                    rom = re.sub(r"(\d)⁻(\d)", r"\2", rom).replace("⁻", "")
                    ex.append([text, rom, en])
            labels = sorted(a for a in t - LABEL_SKIP if a[0].islower() and a not in ("form-of", "alt-of"))
            sv = {"g": g, "p": w.get("pos", "")}
            if labels: sv["l"] = labels
            if ex: sv["x"] = ex; wikt_ex += len(ex)
            senses_out.append(sv)
        if not senses_out: continue
        e = entries.get((h, j))
        if e is None:
            e = entry(h, None, j)
            if any("Cantonese" in (s.get("tags") or []) for s in w.get("senses", [])): e["yue"] = 1
        e.setdefault("wk", [])
        for sv in senses_out:
            if not any(o["g"] == sv["g"] for o in e["wk"]): e["wk"].append(sv)
        if au and "au" not in e: e["au"] = au; wikt_au += 1
        if "wikt" not in e["src"]: e["src"].append("wikt"); wikt += 1
    # the Mandarin words go on the main entry of each Cantonese word
    for (h, j), e in entries.items():
        if h in zh_of: e["zh"] = [m for m, _ in zh_of[h].most_common(3)]; wikt_zh += 1
    # a word Wiktionary gives a meaning for: the reading it uses is the usual one

# (the text rime-cantonese counted is from the internet, where some words are often typed with a stand-in
# character: 我地 for 我哋, 左 for 咗, 既 for 嘅)
STAND_IN = str.maketrans({"哋": "地", "咗": "左", "嘅": "既", "嚟": "黎", "喺": "係", "噉": "咁"})
for e in entries.values():
    h = e["h"]
    e["f"] = max(freq.get(h, 0), freq.get(h.translate(STAND_IN), 0) if len(h) > 1 else 0)
    # the stand-ins themselves are counted far too often (左 is mostly 咗 there)
    if h in ("左", "既", "黎"): e["f"] //= 20
    # a Cantonese word rime-cantonese has but the text doesn't count (佢哋, 你哋): from its characters
    if e["f"] == 0 and len(h) > 1 and h in rime_words and all(freq.get(c, 0) for c in h):
        e["f"] = min(freq[c] for c in h) // 50

# ------------------------------------------------------------------ characters (開放粵語字典)
chars = collections.OrderedDict()
for line in open(P("yyzd.txt"), encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) < 3: continue
    ch, j = p[0], clean_jp(p[2])
    if not j or len(ch) != 1: continue
    chars.setdefault(ch, []).append([j, p[4] if len(p) > 4 else "", p[3] if len(p) > 3 else ""])
# the usual reading first: rime-cantonese's weight (no weight = the usual reading; "5%" = a rarer one), then how
# often the reading is used in words (weighted by how common the words are)
use = collections.Counter()
for e in entries.values():
    if len(e["h"]) > 1 and len(e["h"]) == len(e["j"].split()):
        for c, r in zip(e["h"], e["j"].split()):
            use[(c, r)] += 1 + e["f"]
weight = {}
for ch, rs in rime_words.items():
    if len(ch) == 1:
        for r, w in rs: weight[(ch, r)] = max(weight.get((ch, r), 0), w)
def char_score(ch, r):
    return (weight.get((ch, r), 0), use[(ch, r)])
for ch, rs in list(chars.items()):
    # (the same reading listed twice: one line, the meanings and words together)
    merged = collections.OrderedDict()
    for j, m, w in rs:
        if j in merged:
            a = merged[j]
            if m and m not in a[1]: a[1] = (a[1] + "；" if a[1] else "") + m
            if w and w not in a[2]: a[2] = (a[2] + "，" if a[2] else "") + w
        else: merged[j] = [j, m, w]
    chars[ch] = sorted(merged.values(), key=lambda r: char_score(ch, r[0]), reverse=True)

# a character as a word of its own, with only CC-CEDICT's rarer reading (嘅 ge2) while the usual one (ge3) has
# no entry: the meaning is the usual reading's
for (h, j), e in list(entries.items()):
    if len(h) != 1 or e["src"] != ["cedict"] or weight.get((h, j), 1) >= 1: continue
    main = [r for (c, r), w in weight.items() if c == h and w >= 1]
    if len(main) == 1 and (h, main[0]) not in entries:
        del entries[(h, j)]; e["j"] = main[0]; entries[(h, main[0])] = e
# characters yyzd doesn't have, with a reading from rime-cantonese
for ch, rs in rime_words.items():
    if len(ch) == 1 and ch not in chars and freq.get(ch, 0) > 0:
        best = sorted(rs, key=lambda r: char_score(ch, r[0]), reverse=True)
        chars[ch] = [[r, "", ""] for r, _ in best[:3]]

# a word with more than one reading: the usual one first, the others marked "alt"
byh = collections.defaultdict(list)
for e in entries.values(): byh[e["h"]].append(e)
def rank(e):
    h, j = e["h"], e["j"]
    if len(h) == 1:
        order = [r[0] for r in chars.get(h, [])]
        return (order.index(j) if j in order else 99) - (3 if e.get("wk") else 0)
    rs = [r for r, _ in rime_words.get(h, [])]
    return (rs.index(j) if j in rs else 50) - (0.5 if e.get("yue") else 0) - (0.2 if "canto" in e["src"] else 0) - (2 if e.get("wk") else 0)
for h, es in byh.items():
    if len(es) > 1:
        es.sort(key=rank)
        for e in es[1:]:
            e["alt"] = 1
            e.pop("zh", None)

# the 華語 word CC-CEDICT / CC-Canto give in a meaning ("Mandarin equivalent: 沒有|没有[mei2 you3]")
MEQ = re.compile(r"Mandarin equivalent:?\s*([^\s|\[\]();,]+)")
for e in entries.values():
    if e.get("alt"): continue
    for g in e["en"]:
        for m in MEQ.findall(g):
            if m != e["h"]:
                e.setdefault("zh", [])
                if m not in e["zh"]: e["zh"].append(m)

out = [e for e in entries.values() if e["en"] or e.get("wk") or e["f"] >= 200]
out.sort(key=lambda e: (-e["f"], e.get("alt", 0)))
for e in out:
    if e["s"] is None: del e["s"]
    for k in ("wk", "zh"):
        if k in e and not e[k]: del e[k]
    if not e["yue"]: del e["yue"]
# ------------------------------------------------------------------ the app's file (the same shape as zh.json)
# Each entry: "k" 漢字\t粵jyutping (the key, so 粵語 words are told apart from 華語 and 台語 ones), "h", "s"
# (Jyutping, one syllable per 漢字), "a" (簡體), "d" [[meaning, [[例句, English, reading word by word]]]],
# "n" (English, ; between), "x"/"y" (the 常用詞 group: 1 = the 500 most common…), "m" (華語 words),
# "u" (a recording). The characters ("c") the same as zh.json's, their readings as [耶魯, 粵拼, [["", meaning]]].
GROUP = 500
CARDS = 12000
heads_all = {e["h"] for e in out}
maxw = 6
def is_han(ch): return "㐀" <= ch <= "鿿" or "\U00020000" <= ch <= "\U0003ffff" or "豈" <= ch <= "﫿"
TOK = re.compile(r"[a-z]+[1-6]")

def code_of(text, rom):
    """the reading of a sentence word by word: '冇乜|偈|好|傾' style pieces, 'mou5 mat1|gai2|…' ('' for punctuation)"""
    toks = TOK.findall(rom.lower())
    hans = [c for c in text if is_han(c)]
    if len(toks) != len(hans): return ""
    parts, i, k = [], 0, 0
    while i < len(text):
        c = text[i]
        if not is_han(c): parts.append(""); i += 1; continue
        L = 1
        for n in range(min(maxw, len(text) - i), 1, -1):
            w = text[i:i + n]
            if all(is_han(x) for x in w) and w in heads_all: L = n; break
        parts.append(" ".join(toks[k:k + L])); k += L; i += L
    return "|".join(parts)

def gloss_ok(g): return not g.startswith("CL:") and not re.match(r"^(variant of|old variant of|see )", g)

YALE_TONE = {"1": "̄", "2": "́", "3": "", "4": "̀", "5": "́", "6": ""}

def app_entry(e):
    j = e["j"]
    o = {"k": e["h"] + "\t粵" + j, "h": e["h"], "s": j}
    if e.get("s") and e["s"] != e["h"]: o["a"] = e["s"]
    d = []
    for sv in e.get("wk", []):
        g = sv["g"]
        if sv.get("l"): g = "(" + ", ".join(sv["l"]) + ") " + g
        xs = [[x[0], x[2], code_of(x[0], x[1])] for x in sv.get("x", [])]
        d.append([g, xs])
    en = [g for g in e["en"] if gloss_ok(g)]
    if not d: d = [[g, []] for g in en[:8]]
    o["d"] = d
    if en: o["n"] = "; ".join(en)
    if e.get("zh"): o["m"] = e["zh"]
    if e.get("au"): o["u"] = e["au"]
    return o

cards_order = [e for e in out if not e.get("alt") and e["f"] > 0 and (e.get("wk") or [g for g in e["en"] if gloss_ok(g)])
               and all(is_han(c) for c in e["h"])][:CARDS]
carded = {id(e) for e in cards_order}
rest = [e for e in out if id(e) not in carded]
app_entries = []
for n, e in enumerate(cards_order):
    o = app_entry(e); o["x"] = o["y"] = n // GROUP + 1; app_entries.append(o)
for e in rest:
    o = app_entry(e)
    if o["d"]: app_entries.append(o)

# the characters, the most common first (as a word of its own in the text, or in words)
char_use = collections.Counter()
for e in out:
    for c in e["h"]: char_use[c] += e["f"]
# (the radicals and strokes for 部首查字 aren't put in: they're the 華語 data's (CC BY-ND, GPL), so yue.json can be
# shared under CC BY-SA. The app reads them from zh.json when it has it.)
zh_chars = {}
radicals = rx = None
word_of = {}
for e in out:
    if len(e["h"]) == 1 and not e.get("alt"): word_of[e["h"]] = e

def yale(s):
    """one Jyutping syllable in Yale with tone marks: goi1 → gōi, m4 → m̀h, sik6 → sihk"""
    m = re.match(r"^([a-z]+)([1-6])$", s)
    if not m: return s
    b, t = m.groups()
    ini = ""
    for i0 in ("gw", "kw", "ng", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "w", "z", "c", "s", "j"):
        if b.startswith(i0) and len(b) > len(i0): ini = i0; break
    fin = b[len(ini):]
    ini = {"z": "j", "c": "ch", "j": "y"}.get(ini, ini)
    if ini == "y" and fin.startswith("yu"): ini = ""
    fin = {"aa": "a"}.get(fin, fin)
    fin = re.sub(r"^eo|^oe", "eu", fin)
    if ini == "" and not fin: fin = b
    syl = ini + fin
    if fin in ("m", "ng") and not ini: v = 0
    else:
        v = next((i for i, ch in enumerate(syl) if ch in "aeiou"), None)
        if v is None: v = len(ini)
    out_s = syl[:v + 1] + YALE_TONE[t] + syl[v + 1:]
    if t in "456":
        # the h after the vowels (before the final consonant)
        k = v + 1 + len(YALE_TONE[t])
        while k < len(out_s) and (out_s[k] in "aeiouy" or out_s[k] in "̀́̄"): k += 1
        if fin in ("m", "ng") and not ini: k = len(out_s)
        out_s = out_s[:k] + "h" + out_s[k:]
    return out_s

app_chars = []
ranked = sorted(chars.keys(), key=lambda c: -char_use[c])
for n, ch in enumerate(ranked):
    rs = []
    for j, meaning, words in chars[ch][:4]:
        defs = []
        if meaning: defs.append(["", meaning])
        if words: defs.append(["", "例：" + "，".join(words.split("，")[:12])])
        if not defs:
            w = word_of.get(ch)
            if w and w["j"] == j:
                g = (w.get("wk") or [{}])[0].get("g") or next((x for x in w["en"] if gloss_ok(x)), "")
                if g: defs.append(["", g])
        rs.append([yale(j), j, defs])
    if not any(r[2] for r in rs) and char_use[ch] == 0: continue
    lvl = n // GROUP + 1 if n < GROUP * 7 else 0
    c = {"h": ch, "m": rs, "x": lvl, "y": lvl}
    z = zh_chars.get(ch)
    if z:
        if "b" in z: c["b"] = z["b"]
        if "n" in z: c["n"] = z["n"]
    app_chars.append(c)

head = {"v": 1, "lang": "yue", "nc": len(cards_order), "c": app_chars}
if radicals: head["r"] = radicals
if rx: head["rx"] = rx
with open(OUT, "w", encoding="utf-8") as f:
    f.write(json.dumps(head, ensure_ascii=False, separators=(",", ":"))[:-1] + ',"e":[\n')
    f.write(",\n".join(json.dumps(o, ensure_ascii=False, separators=(",", ":")) for o in app_entries))
    f.write("\n]}")
print(f"app file: {len(app_entries)} words, {len(cards_order)} of them cards, {len(app_chars)} characters")

print(f"{len(out)} words ({sum(1 for e in out if e.get('yue'))} Cantonese words, "
      f"{sum(1 for e in out if e['f'] > 0)} found in the Cantonese text), {len(chars)} characters")
print(f"CC-CEDICT words without a Cantonese reading (left out): {no_reading}; CC-Canto lines: {canto}; "
      f"readings set by rime-cantonese: {fixed}; words only rime-cantonese has: {only_rime}")
if KAIKKI: print(f"Wiktionary: {wikt} words with meanings, {wikt_ex} examples, {wikt_au} recordings, {wikt_zh} words with a Mandarin equivalent")
