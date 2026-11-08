#!/usr/bin/env python3
# 客語 (Taiwanese Hakka) data -> FangfangCards/hak.json, from 教育部《臺灣客語辭典》's six files, one per accent
# (https://hakkadict.moe.edu.tw → 客語資源 → 客語資源下載, "…腔詞條詞目文字.ods"). The dictionary's licence
# (CC BY-ND 3.0 TW) doesn't allow sharing changed versions, so everyone builds their own copy, like dict.json.
#   python3 build_hakka.py DIR OUT [essay.txt|-] [cedict_ts.u8|-]
#     DIR: the six .ods files (四縣腔….ods, 海陸腔….ods, 大埔腔….ods, 饒平腔….ods, 詔安腔….ods, 南四縣腔….ods)
#     essay.txt (rime-essay): how common the words are (a 華語 text, the closest there is)
#     cedict_ts.u8 (CC-CEDICT): English meanings of the words written the same way in 華語
#
# The app's file has the same shape as zh.json / yue.json ("lang": "hak"). A syllable is written as its letters,
# the tone category as a superscript digit (1 陰平 2 上聲 3 (陰)去聲 4 陰入 5 陽平 7 陽去 8 陽入) and the accent
# as a subscript digit (0 四縣 1 海陸 2 大埔 3 饒平 4 詔安 5 南四縣): "bau¹₀". The head carries the tone marks of
# each accent ("ht") and the 注音 of each syllable's letters ("hz"), so the app only looks them up.
import collections, json, os, re, sys, unicodedata, zipfile
import xml.etree.ElementTree as ET

SRC, OUT = sys.argv[1], sys.argv[2]
ESSAY = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "-" else None
CEDICT = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] != "-" else None

ACCENTS = ["四縣", "海陸", "大埔", "饒平", "詔安", "南四縣"]
SUP = "⁰¹²³⁴⁵⁶⁷⁸⁹"
SUB = "₀₁₂₃₄₅₆₇₈₉"

# ------------------------------------------------------------------ reading the .ods files
NS_T = "{urn:oasis:names:tc:opendocument:xmlns:table:1.0}"
NS_X = "{urn:oasis:names:tc:opendocument:xmlns:text:1.0}"


def cell_text(c):
    paras = []
    for p in c.iter(NS_X + "p"):
        buf = []

        def walk(e):
            if e.text: buf.append(e.text)
            for ch in e:
                if ch.tag == NS_X + "s": buf.append(" " * int(ch.get(NS_X + "c", "1")))
                elif ch.tag == NS_X + "tab": buf.append("\t")
                elif ch.tag == NS_X + "line-break": buf.append("\n")
                else: walk(ch)
                if ch.tail: buf.append(ch.tail)
        walk(p)
        paras.append("".join(buf))
    return "\n".join(paras)


def read_ods(path):
    rows = []
    with zipfile.ZipFile(path).open("content.xml") as f:
        for ev, el in ET.iterparse(f, events=("end",)):
            if el.tag != NS_T + "table-row": continue
            row = []
            for c in el:
                if c.tag not in (NS_T + "table-cell", NS_T + "covered-table-cell"): continue
                n = int(c.get(NS_T + "number-columns-repeated", "1"))
                t = cell_text(c)
                row.extend([t] * min(n, 20))
            rep = int(el.get(NS_T + "number-rows-repeated", "1"))
            if any(x.strip() for x in row):
                for _ in range(min(rep, 1)): rows.append(row)
            el.clear()
    return rows


def find_files():
    out = {}
    for name in os.listdir(SRC):
        if not name.lower().endswith(".ods"): continue
        n = unicodedata.normalize("NFC", name)
        # (南四縣 first: its name has 四縣 in it)
        for i in (5, 0, 1, 2, 3, 4):
            if ACCENTS[i] in n and i not in out:
                out[i] = os.path.join(SRC, name); break
    return out


files = find_files()
if 0 not in files:
    sys.exit("找不到四縣腔的檔案（" + SRC + "）")
print("accents:", ", ".join(ACCENTS[i] for i in sorted(files)))

# ------------------------------------------------------------------ tones: value → (category, mark), per accent
# (from the dictionary's own index, "陰平(1/ˊ/24)"; these are what it says, for values the index doesn't list)
TONE_DEFAULT = [
    {"24": (1, "ˊ"), "31": (2, "ˋ"), "55": (3, ""), "2": (4, "ˋ"), "11": (5, "ˇ"), "5": (8, "")},
    {"53": (1, "ˋ"), "24": (2, "ˊ"), "11": (3, "ˇ"), "5": (4, ""), "55": (5, ""), "33": (7, "+"), "2": (8, "ˋ")},
    {"33": (1, "+"), "35": (1, "ˊ"), "31": (2, "^"), "53": (3, "ˋ"), "21": (4, "^"), "113": (5, "ˇ"), "54": (8, "ˋ")},
    {"11": (1, "ˇ"), "53": (2, "ˋ"), "2": (4, "ˋ"), "55": (5, ""), "24": (7, "ˊ"), "5": (8, "")},
    {"11": (1, "ˇ"), "31": (2, "^"), "24": (4, "ˊ"), "53": (5, "ˋ"), "55": (7, ""), "43": (8, "ˋ")},
    {"24": (1, "ˊ"), "31": (2, "ˋ"), "55": (3, ""), "2": (4, "ˋ"), "11": (5, "ˇ"), "5": (8, "")},
]
IDX = re.compile(r"聲母索引/[^/]+/[^/]*/[^/]*/([^(\s]+)\((\d+)/([^/]*)/(\d+)\)")

# ------------------------------------------------------------------ syllables
SYL = re.compile(r"([a-z]+)(\d+)")
INITIALS = ["zh", "ch", "sh", "rh", "ng", "bb", "b", "p", "m", "f", "v", "d", "t", "n", "l", "g", "k", "h",
            "z", "c", "s", "j", "q", "x"]
ZY_INI = {"b": "ㄅ", "p": "ㄆ", "m": "ㄇ", "f": "ㄈ", "v": "ㄪ", "d": "ㄉ", "t": "ㄊ", "n": "ㄋ", "l": "ㄌ", "g": "ㄍ",
          "k": "ㄎ", "ng": "ㄫ", "h": "ㄏ", "j": "ㄐ", "q": "ㄑ", "x": "ㄒ", "z": "ㄗ", "c": "ㄘ", "s": "ㄙ",
          "zh": "ㄓ", "ch": "ㄔ", "sh": "ㄕ", "rh": "ㄖ", "bb": "ㆠ"}
ZY_FIN = [("ang", "ㄤ"), ("ai", "ㄞ"), ("au", "ㄠ"), ("an", "ㄢ"), ("ii", "ㆨ"), ("ee", "ㆤ"), ("oo", "ㆦ"), ("er", "ㄜ"),
          ("nn", "ⁿ"), ("ng", "ㄫ"), ("a", "ㄚ"), ("e", "ㄝ"), ("i", "ㄧ"), ("o", "ㄛ"), ("u", "ㄨ"), ("m", "ㄇ"), ("n", "ㄣ"),
          ("b", "ㆴ"), ("d", "ㆵ"), ("g", "ㆶ")]


def zhuyin(letters):
    """客語拼音 letters (no tone) → 客語注音, by the rules of 臺灣客家語拼音方案"""
    ini = next((i for i in INITIALS if letters.startswith(i) and len(letters) > len(i)), "")
    if letters in ("m", "n", "ng"): ini = ""
    rest = letters[len(ini):]
    out = ZY_INI.get(ini, "")
    while rest:
        for k, v in ZY_FIN:
            if rest.startswith(k):
                out += v; rest = rest[len(k):]; break
        else:
            return letters
    return out


tone_tables = []          # per accent: value → (category, mark)
unknown_tones = collections.Counter()


def encode(reading, acc, n=0):
    """'bau24 i24' → ['bau¹₀', 'i¹₀'] (accent 0); [] when it can't be read. n: how many 漢字 (two readings written
    one after the other, 'ia24 ge55 lia24 ge55' for 這個: the first)"""
    out = []
    found = SYL.findall(reading.lower())
    if n and len(found) > n and len(found) % n == 0: found = found[:n]
    for letters, val in found:
        cat, _ = tone_tables[acc].get(val, (0, ""))
        if cat == 0: unknown_tones[(ACCENTS[acc], val)] += 1
        out.append(letters + SUP[cat] + SUB[acc])
    return out


# ------------------------------------------------------------------ the rows of each accent
def clean(s): return (s or "").replace("　", " ").strip()


def split_list(s):
    return [w for w in re.split(r"[\s　、，,]+", s or "") if w]


SENSE = re.compile(r"(?:^|\s)(\d+)\.")


def senses_of(text):
    """'2.語頭…　3.表疑問…　1.敬詞…' → [(number, text)] in the order written"""
    t = (text or "").replace("　", " ").strip()
    if not SENSE.search(t): return [(1, t)] if t else []
    parts = SENSE.split(" " + t)
    out = []
    for i in range(1, len(parts) - 1, 2):
        s = parts[i + 1].strip()
        if s: out.append((int(parts[i]), s))
    return out


def examples_of(text):
    """'例：客語。(華語。)' (several) → [(客語, 華語)]"""
    t = (text or "").replace("　", " ").strip()
    if not t: return []
    chunks = [c.strip() for c in t.split("例：") if c.strip()] if "例：" in t else [t]
    out = []
    for c in chunks:
        m = re.match(r"^(.*?)[(（]+(.*?)[)）]*$", c)
        if m:
            h, z = m.group(1).strip(), m.group(2).strip().strip("（）() ")
        else:
            # "客語。 華語。" (a space between, no brackets)
            p = re.split(r"(?<=[。！？])\s+", c, maxsplit=1)
            h, z = p[0].strip(), (p[1].strip() if len(p) > 1 else "")
        if h: out.append((h, z))
    return out


POS = {"名": "名詞", "動": "動詞", "形": "形容詞", "副": "副詞", "諺": "諺語", "量": "量詞", "代": "代名詞",
       "介": "介詞", "連": "連詞", "助": "助詞", "歎": "感嘆詞", "嘆": "感嘆詞", "數": "數詞", "綴": "詞綴"}

rows_of = {}
for acc in sorted(files):
    raw = read_ods(files[acc])
    head = raw[0]
    col = {name: i for i, name in enumerate(head)}

    def get(r, name):
        i = col.get(name)
        return r[i] if i is not None and i < len(r) else ""
    # tones from the index
    seen = collections.defaultdict(collections.Counter)
    for r in raw[1:]:
        for name, num, mark, val in IDX.findall(get(r, "詞目索引")):
            seen[val][(int(num), mark.strip())] += 1
    table = dict(TONE_DEFAULT[acc])
    for val, c in seen.items():
        (num, mark), n = c.most_common(1)[0]
        if n >= 3: table[val] = (num, mark)
    tone_tables.append(None)
    while len(tone_tables) <= acc: tone_tables.append(None)
    tone_tables[acc] = table
    rows = []
    for r in raw[1:]:
        h = clean(get(r, "詞目"))
        reading = clean(get(r, "音讀"))
        if not h or not reading: continue
        main = re.split(r"\s*又(?:讀|音)", reading)[0]
        aid = re.findall(r"hk(\d+)-", get(r, "對應音檔名稱"))
        rows.append({
            "acc": acc, "h": h, "read": main, "id": aid[0] if aid else None,
            "senses": senses_of(get(r, "釋義")), "ex": examples_of(get(r, "例句")),
            "pos": [POS.get(p, p) for p in split_list(get(r, "詞性"))],
            "syn": split_list(get(r, "相似詞")), "ant": split_list(get(r, "相反詞")),
            "cat": [c.split("/")[1] for c in get(r, "詞目索引").split() if c.startswith("詞目分類索引/")],
        })
    rows_of[acc] = rows
    print(f"{ACCENTS[acc]}: {len(rows)} words")
tone_tables = [t or TONE_DEFAULT[i] for i, t in enumerate(tone_tables + [None] * (6 - len(tone_tables)))]

# ------------------------------------------------------------------ the same word in the six accents
# Words with the same recording number are the same entry; the rest go by 漢字 and how alike the meanings are.
def meaning_chars(r):
    return set("".join(s for _, s in r["senses"])) - set("，。、；：「」（）() ")


def alike(a, b):
    if not a or not b: return 0
    return len(a & b) / len(a | b)


by_head = collections.defaultdict(list)
for acc in sorted(rows_of):
    for r in rows_of[acc]: by_head[r["h"]].append(r)

groups = []          # each: {acc: row}
for h, rs in by_head.items():
    gs = []
    by_id = {}
    for r in rs:
        if r["id"]:
            g = by_id.get(r["id"])
            if g is None or r["acc"] in g:
                g = {}; gs.append(g)
                by_id.setdefault(r["id"], g)
            g[r["acc"]] = r
    for r in rs:
        if r["id"]: continue
        mc = meaning_chars(r)
        best, score = None, 0.0
        for g in gs:
            if r["acc"] in g: continue
            s = max(alike(mc, meaning_chars(x)) for x in g.values())
            # (the only one of this 漢字 in each accent: the same word)
            if len([x for x in rs if x["acc"] == r["acc"]]) == 1 and all(len([x for x in rs if x["acc"] == a]) <= 1 for a in g):
                s = max(s, 0.5)
            if s > score: best, score = g, s
        if best is not None and score >= 0.35: best[r["acc"]] = r
        else: gs.append({r["acc"]: r})
    groups.extend(gs)
print(f"{len(groups)} words in all")

# ------------------------------------------------------------------ how common (from a 華語 text: the closest there is)
freq = collections.Counter()
if ESSAY:
    for line in open(ESSAY, encoding="utf-8"):
        p = line.rstrip("\n").split("\t")
        if len(p) >= 2 and p[1].isdigit(): freq[p[0]] += int(p[1])
char_freq = collections.Counter()
for w, n in freq.items():
    if len(w) == 1: char_freq[w] += n


# how often each word is in the dictionary's own example sentences (Hakka text: the best sign of what's common),
# the longest words first
heads = {r["h"] for rs in rows_of.values() for r in rs}
maxw = max(len(h) for h in heads)
ex_freq = collections.Counter()
for rs in rows_of.values():
    for r in rs:
        for x, _ in r["ex"]:
            i = 0
            while i < len(x):
                for L in range(min(maxw, len(x) - i), 0, -1):
                    if x[i:i + L] in heads:
                        ex_freq[x[i:i + L]] += 1; i += L; break
                else: i += 1
homographs = collections.Counter((g.get(0) or next(iter(g.values())))["h"] for g in groups)


def score(g):
    base = g.get(0) or next(iter(g.values()))
    h = base["h"]
    # (a word written the same as others: its share)
    e = ex_freq.get(h, 0) / homographs[h]
    f = freq.get(h, 0) / homographs[h]
    # words the 華語 text doesn't have: their rarest character, much less (Hakka words are often written with
    # characters 華語 rarely uses)
    if f == 0: f = min((char_freq.get(c, 0) for c in h), default=0) / (40 * len(h))
    # in more accents, with a recording: a little more common
    return e * 1e6 + f * (1 + 0.15 * len(g)) / 1e3 + (1 if any(r["id"] for r in g.values()) else 0)


# ------------------------------------------------------------------ English (CC-CEDICT: the word written the same in 華語)
english = {}
if CEDICT:
    for line in open(CEDICT, encoding="utf-8"):
        if line.startswith("#"): continue
        m = re.match(r"^(\S+) (\S+) \[([^\]]*)\] /(.*)/\s*$", line)
        if not m: continue
        trad, gl = m.group(1), m.group(4)
        gs = [g for g in gl.split("/") if g and not g.startswith("CL:") and not re.match(r"^(variant of|old variant of|see )", g)]
        if gs: english.setdefault(trad, []).extend(gs)

# ------------------------------------------------------------------ the app's file
def is_han(ch): return "㐀" <= ch <= "鿿" or "\U00020000" <= ch <= "\U0003ffff" or "豈" <= ch <= "﫿"


def split_words(ws):
    """synonyms written one after another without a space ('包山包海掖蔴掖米弛崗打陣'): the dictionary's words in it"""
    out = []
    for w in ws:
        if w in heads or len(w) <= 4: out.append(w); continue
        parts, i = [], 0
        while i < len(w):
            for L in range(min(maxw, len(w) - i), 1, -1):
                if w[i:i + L] in heads: parts.append(w[i:i + L]); i += L; break
            else: parts = None; break
        out.extend(parts if parts else [w])
    return [w for w in out if not any("\ue000" <= c <= "\uf8ff" for c in w)]


GROUP = 500
ordered = sorted(groups, key=lambda g: -score(g))
letters_seen = set()
entries, keys = [], set()
for n, g in enumerate(ordered):
    base_acc = 0 if 0 in g else min(g)
    b = g[base_acc]
    # (characters the dictionary has in its own font only, or not at all: they can't be shown)
    if any("\ue000" <= c <= "\uf8ff" or c == "□" for c in b["h"]): continue
    syl = {a: encode(r["read"], a, sum(1 for c in r["h"] if is_han(c))) for a, r in g.items()}
    if not syl[base_acc]: continue
    for ss in syl.values():
        for s in ss: letters_seen.add(s[:-2])
    # the key: 漢字, then the 四縣 (or first) reading as the dictionary writes it ("包山塞海\t客bau24 san24 sed2 hoi31")
    raw = [l + v for l, v in SYL.findall(b["read"].lower())][:len(syl[base_acc])]
    k = b["h"] + "\t客" + " ".join(raw)
    while k in keys: k += "＊"
    keys.add(k)
    # meanings in number order, each with its examples (the examples are written in the order of the meanings)
    xs = b["ex"]
    ss = b["senses"]
    d = []
    for i, (num, text) in enumerate(ss):
        ex = [xs[i]] if i < len(xs) and len(xs) <= len(ss) else []
        d.append((num, [text, [[x[0], x[1], ""] for x in ex]]))
    if len(xs) > len(ss) and d:
        d[0][1][1] = [[x[0], x[1], ""] for x in xs]
    d = [x[1] for x in sorted(d, key=lambda x: x[0])]
    if not d: continue
    o = {"k": k, "h": b["h"], "s": " ".join(syl[base_acc])}
    v = [" ".join(syl[a]) if a in syl and syl[a] else None for a in range(6)]
    if any(x and x != o["s"] for x in v): o["v"] = v
    o["d"] = d
    # (a character with several readings / meanings in Hakka: 華語's English would be for some other one)
    if english.get(b["h"]) and (len(b["h"]) > 1 or homographs[b["h"]] == 1): o["n"] = "; ".join(dict.fromkeys(english[b["h"]]))
    pos = list(dict.fromkeys(p for r in g.values() for p in r["pos"]))
    if pos: o["w"] = pos
    syn = list(dict.fromkeys(w for r in g.values() for w in split_words(r["syn"]) if w != b["h"]))
    ant = list(dict.fromkeys(w for r in g.values() for w in split_words(r["ant"]) if w != b["h"]))
    if syn: o["j"] = syn[:12]
    if ant: o["f"] = ant[:8]
    # the accents that say it another way (the same entry, another word): shown as that accent's word
    other = {a: r["h"] for a, r in g.items() if r["h"] != b["h"]}
    if other: o["o"] = {str(a): w for a, w in other.items()}
    o["x"] = o["y"] = n // GROUP + 1
    entries.append(o)

# the characters: the one-character words, the most common first
char_entries = collections.defaultdict(list)
for o in entries:
    if len(o["h"]) == 1 and is_han(o["h"]): char_entries[o["h"]].append(o)
char_use = collections.Counter()
for n, o in enumerate(entries):
    for c in o["h"]: char_use[c] += max(1, 100000 // (n + 50))
app_chars = []
for n, ch in enumerate(sorted(char_entries, key=lambda c: -char_use[c])):
    rs = []
    for o in char_entries[ch][:4]:
        s = o["s"]
        defs = [["", m[0]] for m in o["d"][:4]]
        words = [w["h"] for w in entries[:6000] if ch in w["h"] and w["h"] != ch][:12]
        if words: defs.append(["", "例：" + "，".join(words)])
        rs.append([s, s, defs, None, o.get("v")])
    lvl = n // GROUP + 1 if n < GROUP * 7 else 0
    app_chars.append({"h": ch, "m": rs, "x": lvl, "y": lvl})

hz = {l: zhuyin(l) for l in sorted(letters_seen)}
bad = [l for l, z in hz.items() if z == l]
ht = []
for a in range(6):
    marks = [""] * 9
    for val, (cat, mark) in tone_tables[a].items():
        if 0 < cat < 9 and not marks[cat]: marks[cat] = mark
    ht.append(marks)

head = {"v": 1, "lang": "hak", "nc": len(entries), "c": app_chars, "ht": ht, "hz": hz, "acc": ACCENTS}
with open(OUT, "w", encoding="utf-8") as f:
    f.write(json.dumps(head, ensure_ascii=False, separators=(",", ":"))[:-1] + ',"e":[\n')
    f.write(",\n".join(json.dumps(o, ensure_ascii=False, separators=(",", ":")) for o in entries))
    f.write("\n]}")
print(f"app file: {len(entries)} words, {len(app_chars)} characters, {sum(1 for o in entries if 'n' in o)} with English")
if bad: print("no 注音 for:", " ".join(bad[:40]), file=sys.stderr)
if unknown_tones: print("tones not known:", dict(unknown_tones.most_common(10)), file=sys.stderr)
