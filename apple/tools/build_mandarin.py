# 兩岸常用詞典 (中華文化總會, via g0v/moedict-data-csld: dict-csld.json) -> FangfangCards/zh.json,
# the 華語 deck: every entry in the same card format as cards.json, the most common words first.
#
#   python3 tools/build_mandarin.py dict-csld.json essay.txt FangfangCards/zh.json
#
# The dictionary's own 注音 is kept as it is (臺灣 reading, and the 大陸 reading where it differs);
# 漢語拼音 is spelled from it by rule. Example sentences get readings by splitting them into the
# dictionary's words. Meanings and sentences are copied as they are.
import json, os, re, sys, collections

SRC, ESSAY, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
# optional: CC-CEDICT (cedict_ts.u8, CC BY-SA 4.0) for English meanings, so words can be looked up in English
CEDICT = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] != "-" else None
# optional: the HSK 3.0 word list (ivankra/hsk30: hsk30-expanded.csv, MIT): those words are the 華語 cards
HSK = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] != "-" else None
# optional: the TOCFL word list (ivankra/tocfl: expanded/tocfl.csv)
TOCFL = sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] != "-" else None
# optional: 教育部《重編國語辭典修訂本》 (CC BY-ND 3.0 TW, g0v/moedict-data: dict-revised.json(.xz)) for the
# character cards' meanings, and the HSK 3.0 / TOCFL (TBCL) character lists for their levels
MOE = sys.argv[7] if len(sys.argv) > 7 and sys.argv[7] != "-" else None
HSKCH = sys.argv[8] if len(sys.argv) > 8 and sys.argv[8] != "-" else None
TBCLCH = sys.argv[9] if len(sys.argv) > 9 and sys.argv[9] != "-" else None
# cjkvi-ids ids.txt (what each character is made of): for finding a character by several radicals at once
IDS = sys.argv[10] if len(sys.argv) > 10 and sys.argv[10] != "-" else None
D = json.load(open(SRC))

# ------------------------------------------------------------------ 注音 -> 拼音
INIT = dict(zip("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ",
                "b p m f d t n l g k h j q x zh ch sh r z c s".split()))
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
MARKS = {"a": "āáǎà", "e": "ēéěè", "i": "īíǐì", "o": "ōóǒò", "u": "ūúǔù", "ü": "ǖǘǚǜ", "ê": "ê̄ếê̌ề"}
TONE_CH = {"ˊ": 2, "ˇ": 3, "ˋ": 4}

def zy_parse(s):
    """one 注音 syllable -> (pinyin with tone mark, tone 0-4) or None"""
    t = 1
    if s.startswith("˙"): t, s = 0, s[1:]
    if s.endswith("˙"): t, s = 0, s[:-1]
    if s and s[-1] in TONE_CH: t, s = TONE_CH[s[-1]], s[:-1]
    if not s: return None
    er = s.endswith("ㄦ") and len(s) > 1
    if er: s = s[:-1]
    ini = INIT.get(s[0], "")
    rest = s[1:] if ini else s
    if rest not in FIN: return None
    f = FIN[rest]
    if ini:
        if f == "" and ini in ("zh", "ch", "sh", "r", "z", "c", "s"): f = "i"
        elif f == "": return None
        if ini in ("j", "q", "x"): f = f.replace("ü", "u")
        p = ini + f
    else:
        p = ALONE.get(f, f)
    if er: p += "r"
    # tone mark
    if t in (1, 2, 3, 4):
        v = None
        if "a" in p: v = p.index("a")
        elif "e" in p and "ê" not in p: v = p.index("e")
        elif "ê" in p: v = p.index("ê")
        elif "ou" in p: v = p.index("o")
        else:
            for i in range(len(p) - 1, -1, -1):
                if p[i] in "iouü": v = i; break
        if v is not None:
            ch = p[v]
            p = p[:v] + MARKS[ch][t - 1] + p[v + 1:]
    return p, t

def is_han(ch):
    o = ord(ch)
    return 0x3400 <= o <= 0x9fff or 0x20000 <= o <= 0x3ffff or 0xf900 <= o <= 0xfaff

def clean_zy(s):
    return re.sub(r"[臺陸]⃟", "", s).replace("", "").strip()

def syllables(zy, title):
    """the 注音 of a word, one per 漢字 of the title: [(zy, py, tone)]; 兒 after an -ㄦ syllable shares it"""
    parts = [x for x in re.split(r"[　\s，,－\-﹐｜]+", clean_zy(zy)) if x]
    hs = [c for c in title if is_han(c)]
    out = []
    i = 0
    for p in parts:
        r = zy_parse(p)
        if r is None: return None
        out.append((p, r[0], r[1]))
        i += 1
        if p.rstrip("ˊˇˋ˙").endswith("ㄦ") and len(p.rstrip("ˊˇˋ˙").lstrip("˙")) > 1:
            # 點兒 -> one syllable for two 漢字
            if len(out) < len(hs) and hs[len(out)] == "兒":
                out.append(("", "", r[1]))
    if len(out) != len(hs): return None
    return out

def join_py(sy):
    """syllables -> one word: chīfàn, Xī'ān (an apostrophe before a / o / e)"""
    s = ""
    for p in sy:
        if not p: continue
        if s and p[0] in "aāáǎàoōóǒòeēéěèê": s += "'"
        s += p
    return s

# ------------------------------------------------------------------ frequency
freq = collections.Counter()
for line in open(ESSAY, encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 2 and p[1].isdigit(): freq[p[0]] = max(freq[p[0]], int(p[1]))

# ------------------------------------------------------------------ entries
def clean_def(t):
    t = re.sub(r"<[^>]+>", "", t).replace("臺⃝", "〔臺灣〕").replace("陸⃝", "〔大陸〕")
    return t.strip()

entries = []
seen_keys = collections.Counter()
for e in D:
    title = e["title"]
    for h in e["heteronyms"]:
        zyparts = h["bopomofo"].split("<br>")
        tw = clean_zy(zyparts[0])
        lu = None
        for x in zyparts[1:]:
            if x.startswith("陸⃝"): lu = clean_zy(x[2:])
        spec = h.get("specific_to", "") + ("臺⃟" if "臺⃟" in h["bopomofo"] else "") + ("陸⃟" if "陸⃟" in h["bopomofo"] else "")
        sp = 1 if "臺" in spec else (2 if "陸" in spec else 0)
        syl_tw = syllables(tw, title)
        syl_lu = syllables(lu, title) if lu else None
        if syl_tw is None: continue
        # meanings: a heading like 「嘆詞：」 goes in front of its (1) (2) …
        defs = []
        head = ""
        for x in h["definitions"]:
            t = clean_def(x["def"])
            exs = []
            for ex in x.get("example", []):
                for q in re.findall(r"「(.*?)」", ex):
                    src = ""
                    m = re.search(r"（([^（）]*)）$", q)
                    if m: src, q = m.group(1), q[:m.start()]
                    q = q.strip()
                    if q: exs.append((q, src))
            if t.endswith("：") and not exs:
                head = t; continue
            if head and re.match(r"^\(\d+\)", t): t = head + t
            else: head = ""
            # everyday sentences before quotations from old books
            exs.sort(key=lambda q: 1 if "‧" in q[1] or "•" in q[1] or "《" in q[1] or "〈" in q[1] else 0)
            defs.append((t, exs))
        if not defs: continue
        k = title + "\t" + " ".join(s[0] for s in syl_tw if s[0])
        seen_keys[k] += 1
        if seen_keys[k] > 1: k += "#" + str(seen_keys[k])
        entries.append(dict(k=k, h=title, tw=syl_tw, lu=syl_lu, sp=sp, alt=h.get("alt"), defs=defs))

print("entries", len(entries))

# ------------------------------------------------------------------ splitting sentences into words
words = collections.defaultdict(list)          # 漢字 -> entries (in dictionary order: the usual reading first)
for en in entries: words[en["h"]].append(en)
MAXLEN = max(len(w) for w in words)

# one character on its own in a sentence: the reading it usually has there
ALONE_READING = {"的": "˙ㄉㄜ", "了": "˙ㄌㄜ", "著": "˙ㄓㄜ", "得": "˙ㄉㄜ", "們": "˙ㄇㄣ", "麼": "˙ㄇㄜ", "嗎": "˙ㄇㄚ",
                 "呢": "˙ㄋㄜ", "吧": "˙ㄅㄚ", "啊": "˙ㄚ", "都": "ㄉㄡ", "還": "ㄏㄞˊ", "個": "ㄍㄜˋ", "沒": "ㄇㄟˊ",
                 "給": "ㄍㄟˇ", "那": "ㄋㄚˋ", "哪": "ㄋㄚˇ", "誰": "ㄕㄟˊ", "會": "ㄏㄨㄟˋ", "要": "ㄧㄠˋ", "說": "ㄕㄨㄛ",
                 "為": "ㄨㄟˋ", "中": "ㄓㄨㄥ", "好": "ㄏㄠˇ", "看": "ㄎㄢˋ", "只": "ㄓˇ", "長": "ㄔㄤˊ", "重": "ㄓㄨㄥˋ",
                 "地": "ㄉㄧˋ", "大": "ㄉㄚˋ", "和": "ㄏㄜˊ", "把": "ㄅㄚˇ", "少": "ㄕㄠˇ", "種": "ㄓㄨㄥˇ", "行": "ㄒㄧㄥˊ"}

def reading_of(han):
    """(tw syllables, lu syllables) for a word: the most common reading"""
    ens = words.get(han)
    if not ens: return None
    if len(ens) > 1:
        want = ALONE_READING.get(han)
        for en in ens:
            if want and en["tw"][0][0] == want: return en["tw"], en["lu"]
        # otherwise the reading with the most meanings
        en = max(ens, key=lambda en: len(en["defs"]))
    else:
        en = ens[0]
    return en["tw"], en["lu"]

def segment(text, own=None):
    """the sentence as [han, twpy, twzy, lupy, luzy, tones] pieces; `own` = (title, tw, lu) is always read
    the way its own entry says"""
    n = len(text)
    best = [None] * (n + 1)          # (pieces, score)
    best[0] = (0, 0)
    back = [None] * (n + 1)
    for i in range(n):
        if best[i] is None: continue
        cnt, sc = best[i]
        ch = text[i]
        cands = []
        if not is_han(ch):
            cands.append((i + 1, None))
        else:
            for L in range(min(MAXLEN, n - i), 0, -1):
                w = text[i:i + L]
                if (own and w == own[0]) or w in words:
                    cands.append((i + L, w))
            if not cands: cands.append((i + 1, "?"))
        for j, w in cands:
            # fewer pieces is better; then more common words
            ns = (cnt + 1, sc - (freq.get(w, 0) if w and w != "?" else 0))
            if best[j] is None or ns < best[j]:
                best[j] = ns; back[j] = (i, w)
    pieces = []
    j = n
    while j > 0:
        i, w = back[j]
        pieces.append((text[i:j], w))
        j = i
    pieces.reverse()
    out = []
    for seg, w in pieces:
        if w is None or w == "?":
            out.append([seg, "", "", "", "", "", "", ""]); continue
        if own and w == own[0]: tw, lu = own[1], own[2]
        else: tw, lu = reading_of(w)
        twpy = [s[1] for s in tw]; twzy = [s[0] for s in tw]; tones = "".join(str(s[2]) for s in tw)
        if lu:
            lupy = join_py([s[1] for s in lu]); luzy = " ".join(s[0] for s in lu if s[0])
        else: lupy = luzy = ""
        out.append([seg, join_py(twpy), " ".join(z for z in twzy if z), lupy, luzy, tones,
                    zy_str(tw), zy_str(lu) if lu and [s[0] for s in lu] != [s[0] for s in tw] else ""])
    # 一 / 不 on their own change tone before another syllable (the dictionary writes words this way too)
    NUM = set("〇零一二三四五六七八九十百千萬億兩第")
    for idx, p in enumerate(out):
        if p[0] not in ("一", "不") or not p[5]: continue
        nxt = next((q for q in out[idx + 1:] if q[5]), None)
        if nxt is None or out[idx + 1][5] == "": continue
        prev = out[idx - 1][0] if idx > 0 else ""
        if p[0] == "一" and (prev[-1:] in NUM or nxt[0][:1] in NUM): continue
        t = nxt[5][0]
        if p[0] == "不":
            if t == "4": p[1], p[2], p[5], p[6] = "bú", "ㄅㄨˊ", "2", "ㄅㄨˊ"
        else:
            if t == "4": p[1], p[2], p[5], p[6] = "yí", "ㄧˊ", "2", "ㄧˊ"
            elif t in "123": p[1], p[2], p[5], p[6] = "yì", "ㄧˋ", "4", "ㄧˋ"
        # a word that ends in 不 (從不, 絕不…: CC-CEDICT writes bù) before a 4th tone: bú
    for idx, p in enumerate(out):
        if len(p[0]) < 2 or not p[0].endswith("不") or not p[5].endswith("4"): continue
        nxt = out[idx + 1] if idx + 1 < len(out) else None
        if not nxt or not nxt[5] or nxt[5][0] != "4": continue
        if not p[1].endswith("bù"): continue
        p[1] = p[1][:-2] + "bú"
        p[5] = p[5][:-1] + "2"
        for k in (2, 6):
            if p[k].endswith("ㄅㄨˋ"): p[k] = p[k][:-3] + "ㄅㄨˊ"
        if p[3].endswith("bù"): p[3] = p[3][:-2] + "bú"
        for k in (4, 7):
            if p[k].endswith("ㄅㄨˋ"): p[k] = p[k][:-3] + "ㄅㄨˊ"
    return out

def pieces_text(pcs, i):
    """the reading of a sentence: 1 = 拼音 (words with spaces), 2 = 注音"""
    out = ""
    prev = False
    for p in pcs:
        if p[5]:
            if prev: out += " "
            out += p[i]; prev = True
        else:
            out += p[0]; prev = False
    return out.strip()

# ------------------------------------------------------------------ output
# Compact, the app spells 拼音 and works out the tones from the 注音:
#   entry: {"k", "h", "s": 臺灣 注音 (syllables with spaces; "-" = 兒 sharing the syllable before),
#           "l": 大陸 注音 where it differs, "p": 1 臺灣特有 / 2 大陸特有, "a": 簡化字,
#           "d": [[meaning, [[sentence, source, reading], …]], …]}
#   reading of a sentence: its words joined by "|"; a word = its 注音 syllables with spaces,
#   "臺灣/大陸" when the two differ; "" = one character with no reading (punctuation, numbers…)
def lu_differs(en):
    return en["lu"] is not None and [s[0] for s in en["lu"]] != [s[0] for s in en["tw"]]

def is_reference(en):
    return all(re.match(r"^(參見|見|同|「.*」的(異體字|簡化字|俗字|本字))", t) or t in ("姓。",) for t, _ in en["defs"])

def zy_str(syl):
    return " ".join(s[0] if s[0] else "-" for s in syl)

def per_char(text, zys):
    """one item per character: its syllable, "-" (兒 sharing the one before) or "_" (not a 漢字)"""
    sy = zys.split(" ")
    out, i = [], 0
    for ch in text:
        if is_han(ch) and i < len(sy): out.append(sy[i]); i += 1
        else: out.append("_")
    return " ".join(out)

def piece_code(p):
    if not p[5]: return ""
    return per_char(p[0], p[6]) + ("/" + per_char(p[0], p[7]) if p[7] else "")

# ------------------------------------------------------------------ English (CC-CEDICT)
ced = collections.defaultdict(list)          # traditional -> [(toneless pinyin, toned pinyin, glosses)]
ced_read = {}                                  # traditional -> (numbered syllables, Taiwan's numbered syllables or None)
if CEDICT:
    for line in open(CEDICT, encoding="utf-8"):
        if line.startswith("#"): continue
        m = re.match(r"^(\S+) (\S+) \[([^\]]*)\] /(.*)/\s*$", line)
        if not m: continue
        trad, _, py, defs = m.groups()
        sy = py.lower().replace("u:", "v").split()
        toned = "".join(sy).replace("5", "")
        plain = re.sub(r"\d", "", toned)
        gl = []
        for d in defs.split("/"):
            d = d.strip()
            if not d or d.startswith(("CL:", "variant of", "old variant of", "see ", "surname ", "also written", "abbr. for", "Taiwan pr.", "used in ")): continue
            d = re.sub(r"\s*\([^()]*\b(?:Tw|PRC|lit\.|fig\.)\b[^()]*\)", "", d) if len(d) > 60 else d
            if len(d) > 90: d = d[:88].rstrip() + "…"
            gl.append(d)
        if gl: ced[trad].append((plain, toned, gl))
        # readings, for words 兩岸 doesn't have: (syllables, Taiwan's syllables if CC-CEDICT notes them)
        twm = re.search(r"Taiwan pr\. \[([^\]]+)\]", defs)
        ced_read.setdefault(trad, (sy, twm.group(1).lower().replace("u:", "v").split() if twm else None))

def numbered(syl):
    out = []
    for s in syl:
        if not s[1]: continue
        p = s[1]
        import unicodedata
        base = "".join(c for c in unicodedata.normalize("NFD", p) if not unicodedata.combining(c)).replace("ü", "v").lower()
        out.append(base + (str(s[2]) if s[2] in (1, 2, 3, 4) else ""))
    return "".join(out)

def english(en):
    cands = ced.get(en["h"])
    if not cands: return ""
    want = {numbered(en["tw"])} | ({numbered(en["lu"])} if en["lu"] else set())
    exact = [g for p, t, g in cands if t in want]
    if not exact:
        plain = {re.sub(r"\d", "", w) for w in want}
        exact = [g for p, t, g in cands if p in plain]
    # CC-CEDICT has only one reading: it's that one when the dictionary has only one too (睡覺 shuìjué, the
    # literary 「剛睡醒」, must not get "to sleep")
    if not exact and len(cands) == 1 and len(words.get(en["h"], [])) <= 1: exact = [cands[0][2]]
    gl = []
    for g in exact:
        for d in g:
            if d not in gl: gl.append(d)
    return "; ".join(gl[:8])

# ------------------------------------------------------------------ word lists: HSK 3.0 and TOCFL
import unicodedata
def letters_tones(py):
    """拼音 with marks -> (letters, tones of the marked syllables in order): bàba -> ("baba", "4")"""
    tones, out = "", ""
    for ch in unicodedata.normalize("NFD", py.lower()):
        if ch == "\u0304": tones += "1"
        elif ch == "\u0301": tones += "2"
        elif ch == "\u030c": tones += "3"
        elif ch == "\u0300": tones += "4"
        elif ch == "\u0308": out += "v"[:0]          # ü: the dots aren't a tone
        elif ch.isalpha(): out += ch
    return out.replace("u\u0308", "v"), tones

def entry_lt(syl):
    return letters_tones(" ".join(s[1] for s in syl if s[1]).replace(" ", ""))

import csv
by_trad = collections.defaultdict(list)
for i, en in enumerate(entries): by_trad[en["h"]].append(i)
added = {}                                     # 漢字 -> index of an entry added for a word list

# 拼音 (numbered, CC-CEDICT) -> 注音, using every syllable the dictionary has
py2zy = {}
for en in entries:
    for z, p, t in en["tw"] + (en["lu"] or []):
        if not z: continue
        b = z.strip("˙ˊˇˋ")
        plain = unicodedata.normalize("NFD", zy_parse(b)[0])
        plain = "".join(c for c in plain if not unicodedata.combining(c) or c == "\u0308").replace("u\u0308", "v").replace("ü", "v")
        py2zy.setdefault(plain, b)

def ced_zhuyin(sy):
    """["de2", "dao4"] -> [(注音, 拼音, tone)] or None"""
    out = []
    for s in sy:
        if s == "r5" and out and out[-1][0]:
            # 兒化: the ㄦ joins the syllable before (點兒 ㄉㄧㄚˇㄦ); 兒 has no syllable of its own
            z0 = out[-1][0]
            lead = "˙" if z0.startswith("˙") else ""
            b0 = z0.strip("˙ˊˇˋ")
            mark = z0[-1] if z0[-1] in "ˊˇˋ" else ""
            z = lead + b0 + "ㄦ" + mark
            pr = zy_parse(z)
            if pr is None: return None
            out[-1] = (z, pr[0], pr[1])
            out.append(("", "", pr[1]))
            continue
        m = re.match(r"^([a-zv]+)([1-5])$", s)
        if not m: return None
        b = py2zy.get(m.group(1))
        if not b: return None
        t = int(m.group(2))
        z = "˙" + b if t == 5 else b + {1: "", 2: "ˊ", 3: "ˇ", 4: "ˋ"}[t]
        pr = zy_parse(z)
        if pr is None: return None
        out.append((z, pr[0], pr[1]))
    return out

# 詞類 of the list words (the lists give them; the dictionaries don't), in the 台語 dictionary's names
POS_NAMES = {"N": "名詞", "V": "動詞", "Vi": "動詞", "Vst": "動詞", "Vp": "動詞", "Vpt": "動詞",
             "Adj": "形容詞", "Vs": "形容詞", "Vs-attr": "形容詞", "Vs-pred": "形容詞",
             "V-sep": "離合詞", "Vp-sep": "離合詞", "Vs-sep": "離合詞",
             "Adv": "副詞", "M": "量詞", "Conj": "連詞", "conj": "連詞", "Pron": "代詞", "Pr": "代詞",
             "Prep": "介詞", "Num": "數詞", "Aux": "助動詞", "Vaux": "助動詞", "Ptc": "助詞", "Intj": "嘆詞",
             "Phonetic": "擬聲詞", "Det": "限定詞", "Suffix": "後綴", "Prefix": "前綴", "Name": "專有名詞"}
pos_of = collections.defaultdict(list)

def add_pos(i, pos):
    for p in (pos or "").split("/"):
        n = POS_NAMES.get(p.strip())
        if n and n not in pos_of[i]: pos_of[i].append(n)

def apply_list(rows):
    """[(traditional variants, simplified, 拼音, level)] -> {entry index: level}; words the dictionary doesn't
    have (打電話, 好吃, 北京…) are added, read by splitting them into the dictionary's words, with the English
    meaning from CC-CEDICT, and marked as not from the dictionary"""
    level_of, missing = {}, []
    for trads, simp, py, lvl, pos in rows:
        want = letters_tones(py)
        found = None
        for trad in trads:
            cands = by_trad.get(trad, [])
            if not cands: continue
            exact = [i for i in cands if entry_lt(entries[i]["tw"]) == want or (entries[i]["lu"] and entry_lt(entries[i]["lu"]) == want)]
            loose = [i for i in cands if entry_lt(entries[i]["tw"])[0] == want[0]]
            pick = exact or loose or sorted(cands, key=lambda i: -len(entries[i]["defs"]))
            found = pick[0]
            break
        if found is None and trads and trads[0] in added: found = added[trads[0]]
        if found is not None:
            if found not in level_of or level_of[found] > lvl: level_of[found] = lvl
            add_pos(found, pos)
        else:
            missing.append((trads, simp, lvl, pos))
    for trads, simp, lvl, pos in missing:
        trad = trads[0] if trads else ""
        if not trad: continue
        if trad in added:
            i = added[trad]
            if i not in level_of or level_of[i] > lvl: level_of[i] = lvl
            add_pos(i, pos)
            continue
        nh = sum(1 for c in trad if is_han(c))
        pcs = segment(trad)
        # the reading: CC-CEDICT's (its Taiwan reading when it notes one), else the dictionary's words put together
        tw, lu = None, None
        if trad in ced_read:
            sy, twsy = ced_read[trad]
            main = ced_zhuyin(sy)
            tws = ced_zhuyin(twsy) if twsy else None
            if main and len(main) == nh:
                tw = tws if tws and len(tws) == nh else main
                if tws and len(tws) == nh and [x[0] for x in tws] != [x[0] for x in main]: lu = main
        if tw is None:
            if any(not p[5] for p in pcs if any(is_han(c) for c in p[0])): continue
            tw = []
            for p in pcs:
                if not p[5]: continue
                for z in p[6].split(" "):
                    if z == "-": tw.append(("", "", tw[-1][2] if tw else 1)); continue
                    pr = zy_parse(z)
                    tw.append((z, pr[0], pr[1]))
        if len(tw) != nh: continue
        g = english({"h": trad, "tw": tw, "lu": lu})
        parts = "＋".join(p[0] for p in pcs if p[5])
        t = ("（英）" + g) if g else ("由「" + parts + "」組成。")
        entries.append(dict(k=trad + "\t" + " ".join(s[0] for s in tw if s[0]), h=trad, tw=tw, lu=lu, sp=0,
                            alt=simp if simp and simp != trad else None, defs=[(t, [])], extra=True))
        added[trad] = len(entries) - 1
        level_of[len(entries) - 1] = lvl
        add_pos(len(entries) - 1, pos)
        # the sentences can use it as a word too (教育得到了重視: 得到, not 得 + 到)
        words[trad].append(entries[-1])
    return level_of

hsk_of, tocfl_of = {}, {}
if HSK:
    rows = []
    for row in csv.DictReader(open(HSK, encoding="utf-8")):
        lvl = 7 if row["Level"].startswith("7") else int(row["Level"])
        rows.append(([t.strip() for t in row["Traditional"].split("|") if t.strip()], row["Simplified"].split("|")[0], row["Pinyin"], lvl, row.get("POS", "")))
    hsk_of = apply_list(rows)
    print("hsk words", len(hsk_of), collections.Counter(hsk_of.values()))
# the TOCFL word list (ivankra/tocfl: expanded/tocfl.csv): 準備一級 … 流利級 = levels 1–7
TOCFL_LEVELS = {"L0-1": 1, "L0-2": 2, "L1": 3, "L2": 4, "L3": 5, "L4": 6, "L5": 7}
if TOCFL:
    rows = []
    for row in csv.DictReader(open(TOCFL, encoding="utf-8")):
        idv = row["ID"]
        lvl = TOCFL_LEVELS.get(idv[:4]) or TOCFL_LEVELS.get(idv[:2])
        if not lvl: continue
        rows.append(([row["Traditional"].strip()], row["Simplified"], row["Pinyin"], lvl, row.get("POS", "")))
    tocfl_of = apply_list(rows)
    print("tocfl words", len(tocfl_of), collections.Counter(tocfl_of.values()))

# 近義詞 / 反義詞 from 教育部《重編國語辭典修訂本》 (the 兩岸 dictionary has none): word + reading -> lists
moe_all = []
if MOE:
    import lzma
    _raw = lzma.open(MOE, "rt", encoding="utf-8").read() if MOE.endswith(".xz") else open(MOE, encoding="utf-8").read()
    moe_all = json.loads(_raw)
syn_of, ant_of = {}, {}
for e in moe_all:
    t = e.get("title", "")
    for h in e.get("heteronyms", []):
        zy = re.sub(r"[（(].*?[）)]", "", h.get("bopomofo", "")).strip()
        sy, an = [], []
        for d in h.get("definitions", []):
            for w in (d.get("synonyms") or "").split(","):
                w = w.strip()
                if w and w != t and w not in sy: sy.append(w)
            for w in (d.get("antonyms") or "").split(","):
                w = w.strip()
                if w and w != t and w not in an: an.append(w)
        if sy: syn_of[(t, zy)] = sy; syn_of.setdefault((t, None), sy)
        if an: ant_of[(t, zy)] = an; ant_of.setdefault((t, None), an)
print("近義", len(syn_of), "反義", len(ant_of))

out_entries = []
for idx, en in enumerate(entries):
    tw = en["tw"]
    own = (en["h"], tw, en["lu"] if lu_differs(en) else None)
    ds = []
    for t, exs in en["defs"]:
        xs = []
        for q, src in exs:
            pcs = segment(q, own)
            xs.append([q, src, "|".join(piece_code(p) for p in pcs)])
        ds.append([t, xs])
    c = {"k": en["k"], "h": en["h"], "s": zy_str(tw), "d": ds}
    if lu_differs(en): c["l"] = zy_str(en["lu"])
    if en["sp"]: c["p"] = en["sp"]
    if en["alt"]: c["a"] = en["alt"]
    g = english(en)
    if g: c["n"] = g
    if idx in hsk_of: c["x"] = hsk_of[idx]
    if idx in tocfl_of: c["y"] = tocfl_of[idx]
    if en.get("extra"): c["q"] = 1
    if pos_of.get(idx): c["w"] = pos_of[idx]
    zs = zy_str(tw).replace("-", "").strip()
    sy = syn_of.get((en["h"], zs)) or syn_of.get((en["h"], None))
    an = ant_of.get((en["h"], zs)) or ant_of.get((en["h"], None))
    if sy: c["j"] = sy[:8]
    if an: c["f"] = an[:8]
    c["_f"] = freq.get(en["h"], 0)
    c["_ref"] = is_reference(en)
    out_entries.append(c)

# the most common words first; words that are only references (參見…, 姓) and words the frequency list doesn't
# know aren't study cards (they're still in the dictionary)
for i, c in enumerate(out_entries): c["_i"] = i
out_entries.sort(key=lambda c: (c["_ref"] or c["_f"] == 0, -c["_f"], c["_i"]))
nc = sum(1 for c in out_entries if not (c["_ref"] or c["_f"] == 0))
for c in out_entries:
    del c["_f"], c["_ref"], c["_i"]

# ------------------------------------------------------------------ 漢字 cards
# every character of the character lists (HSK 3.0 / TOCFL), then the more common other characters, with their
# meanings from 教育部《重編國語辭典修訂本》 (copied as they are; the literary quotations are left out)
chars_out = []
if MOE:
    import lzma
    raw = lzma.open(MOE, "rt", encoding="utf-8").read() if MOE.endswith(".xz") else open(MOE, encoding="utf-8").read()
    moe = {}
    for e in json.loads(raw):
        t = e.get("title", "")
        if len(t) == 1 and is_han(t): moe[t] = e
    def lvl_of(path, col_char, col_lvl):
        out = {}
        if not path: return out
        for row in csv.DictReader(open(path, encoding="utf-8")):
            ch = row[col_char].split("/")[0].strip()
            try: l = int(str(row[col_lvl]).split("-")[0])
            except ValueError: continue
            if len(ch) == 1 and (ch not in out or out[ch] > l): out[ch] = l
        return out
    hsk_ch = {c: min(l, 7) for c, l in lvl_of(HSKCH, "Traditional", "Level").items()}
    tbcl_ch = lvl_of(TBCLCH, "Traditional", "Level")
    # how common a character is: the frequency of the words it's in
    cfreq = collections.Counter()
    for w, f in freq.items():
        for ch in w:
            if is_han(ch): cfreq[ch] += f
    def moe_readings(e):
        """[(注音, 拼音, [(詞類, meaning with its examples)])] of a character, 異體字-only ones left out"""
        out = []
        for h in e.get("heteronyms", []):
            zy = re.sub(r"[（(].*?[）)]", "", h.get("bopomofo", "")).strip()
            label = re.findall(r"[（(](.*?)[）)]", h.get("bopomofo", ""))
            py = re.sub(r"[（(].*?[）)]", "", h.get("pinyin", "")).strip()
            ds = []
            for d in h.get("definitions", []):
                t = re.sub(r"<[^>]+>", "", d.get("def", "")).strip()
                if not t: continue
                ex = "".join(re.sub(r"<[^>]+>", "", x).strip() for x in d.get("example", []))
                ds.append([d.get("type", ""), (t + ex) if ex else t])
            if not ds or not zy or " " in zy: continue
            out.append([zy, py, ds] + ([label[0]] if label else []))
        return out
    def real(rs):
        return any(not re.fullmatch(r"「.」的異體字。", d[1]) for r in rs for d in r[2])
    listed = set(hsk_ch) | set(tbcl_ch)
    picked = []
    for ch in sorted(listed, key=lambda c: -cfreq.get(c, 0)):
        if ch in moe and real(moe_readings(moe[ch])): picked.append(ch)
    # more characters: the common ones the lists don't have (in the 兩岸 dictionary too, so they can be looked up)
    MORE = 3000
    more = [ch for ch, f in cfreq.most_common() if ch not in listed and ch in moe and ch in words
            and real(moe_readings(moe[ch]))][:MORE]
    # how each character is read in the words it's in, each word counted by how common it is (撣 is ㄉㄢˇ in
    # 撣子, 雞毛撣子…, so that's its usual reading, not the ㄕㄢˋ the dictionary happens to list first)
    usage = collections.defaultdict(collections.Counter)
    for w, ens in words.items():
        if len(w) < 2 or not ens: continue
        tw = ens[0]["tw"]
        if len(tw) != len(w): continue
        f = freq.get(w, 0) + 1
        for i, ch in enumerate(w):
            # (a light tone in a word, like 子 in 桌子, isn't the character's own reading)
            if is_han(ch) and tw[i][0] and not tw[i][0].startswith("˙"): usage[ch][tw[i][0]] += f
    for ch in picked + more:
        rs = moe_readings(moe[ch])
        # the usual reading first: the one it has on its own (的, 了…), else the one the words with it use most,
        # else the 兩岸 dictionary's; then the others, the more used first, 又音 / 讀音 / 語音 last
        u = usage.get(ch, collections.Counter())
        main = reading_of(ch)
        mz = main[0][0][0] if main and main[0] else (rs[0][0] if rs else None)
        if ch in ALONE_READING and any(r[0] == ALONE_READING[ch] for r in rs):
            mz = ALONE_READING[ch]
        elif rs and not (mz or "").startswith("˙"):
            # (a particle's light tone, like 啦 or 嘛, stays first)
            best = max(rs, key=lambda r: (u.get(r[0], 0), -(len(r) > 3)))[0]
            # the words with it clearly use another reading (at least twice as much)
            if u.get(best, 0) > 0 and u.get(mz, 0) * 2 < u[best]: mz = best
        order = {id(r): i for i, r in enumerate(rs)}
        rs.sort(key=lambda r: (0 if r[0] == mz else 1, -u.get(r[0], 0), len(r) > 3, order[id(r)]))
        c = {"h": ch, "m": rs}
        if ch in hsk_ch: c["x"] = hsk_ch[ch]
        if ch in tbcl_ch: c["y"] = tbcl_ch[ch]
        e = moe[ch]
        if e.get("radical"): c["b"] = e["radical"].strip()
        if e.get("stroke_count"): c["n"] = e["stroke_count"]
        chars_out.append(c)
    print("characters", len(chars_out), "listed", len(picked), "more", len(more))

# 部首 lookup: every character with its radical and the strokes besides the radical (the 兩岸 dictionary's,
# then 《重編國語辭典修訂本》's); the radicals with their own strokes
rad_of = {}
for e in list(D) + moe_all:
    t = e.get("title", "")
    if len(t) != 1 or not is_han(t) or t in rad_of: continue
    r, n = e.get("radical"), e.get("non_radical_stroke_count")
    if r and n is not None: rad_of[t] = (r.strip(), int(n), int(e.get("stroke_count") or 0))
rad_strokes = {}
for t, (r, n, total) in rad_of.items():
    if t == r and n == 0 and total: rad_strokes[r] = total
cf = collections.Counter()
for w, f in freq.items():
    for ch in w:
        if is_han(ch): cf[ch] += f
rads = sorted({r for r, _, _ in rad_of.values()}, key=lambda r: (rad_strokes.get(r, 99), -cf.get(r, 0)))
rad_list = [[r, rad_strokes.get(r, 0)] for r in rads]
chars_by_rad = collections.defaultdict(list)
for t, (r, n, _) in rad_of.items(): chars_by_rad[r].append((n, -cf.get(t, 0), t))
rad_chars = {r: "".join(t for _, _, t in sorted(v)) for r, v in chars_by_rad.items()}
rad_res = {r: [n for n, _, _ in sorted(v)] for r, v in chars_by_rad.items()}
print("radicals", len(rad_list), "characters", len(rad_of))

# 部首組合: for each radical, every character that has it anywhere inside (from what the characters are made of),
# so the app can find a character by tapping several radicals (氵 + 每 → 海). The forms radicals take inside
# characters (氵 亻 扌 艹 ⻌ 钅 …) count as the radical.
rad_in = {}
if IDS and os.path.exists(IDS):
    RADSET = set(rads)
    VARIANT = {
        "亻": "人", "𠆢": "人", "刂": "刀", "⺈": "刀", "㔾": "卩", "氵": "水", "氺": "水", "扌": "手", "龵": "手",
        "忄": "心", "㣺": "心", "犭": "犬", "礻": "示", "衤": "衣", "糹": "糸", "纟": "糸", "訁": "言", "讠": "言",
        "釒": "金", "钅": "金", "飠": "食", "饣": "食", "艹": "艸", "䒑": "艸", "⺾": "艸", "⺿": "艸", "辶": "辵", "⻌": "辵",
        "⻍": "辵", "灬": "火", "爫": "爪", "罒": "网", "⺲": "网", "罓": "网", "王": "玉", "𤣩": "玉", "⺼": "肉",
        "攵": "攴", "歺": "歹", "牜": "牛", "⺧": "牛", "耂": "老", "覀": "襾", "西": "襾", "镸": "長", "长": "長",
        "𧾷": "足", "⻊": "足", "彑": "彐", "⺕": "彐", "丬": "爿", "𦍌": "羊", "⺶": "羊", "⺷": "羊", "𥫗": "竹",
        "⺮": "竹", "尣": "尢", "旡": "无", "⺊": "卜", "⺍": "小", "⺌": "小", "门": "門", "贝": "貝", "车": "車",
        "见": "見", "鱼": "魚", "鸟": "鳥", "马": "馬", "页": "頁", "风": "風", "韦": "韋", "齿": "齒", "龙": "龍",
        "龟": "龜", "麦": "麥", "黄": "黃", "齐": "齊", "卤": "鹵", "黾": "黽", "飞": "飛", "⻗": "青", "戸": "戶", "户": "戶", "母": "毋", "⺟": "毋",
    }
    ids = {}
    tag = re.compile(r"\[[A-Z]*\]")
    for line in open(IDS, encoding="utf-8"):
        if line.startswith("#") or "\t" not in line: continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3: continue
        ch, alts = parts[1], parts[2:]
        best = next((a for a in alts if "T" in (re.search(r"\[([A-Z]*)\]", a) or [None, ""])[1]), alts[0])
        ids[ch] = tag.sub("", best)
    memo = {}
    def comps(c, depth=0):
        if c in memo: return memo[c]
        out_ = {c}
        d = ids.get(c)
        if d and d != c and depth < 12:
            for x in re.findall(r"&[^;]+;|.", d):
                if x in "⿰⿱⿲⿳⿴⿵⿶⿷⿸⿹⿺⿻〾": continue
                out_ |= comps(x, depth + 1)
        memo[c] = out_
        return out_
    by_rad = collections.defaultdict(list)
    for t, (r, n, total) in rad_of.items():
        rs = {r}
        d = ids.get(t, "")
        for x in comps(t):
            if x == "阝":
                rs.add(r if r in ("阜", "邑") else ("阜" if d.startswith("⿰阝") else "邑"))
            elif x == "月" and r == "肉":
                rs.add("肉")
            elif x in RADSET:
                rs.add(x)
            elif x in VARIANT:
                rs.add(VARIANT[x])
        for x in rs:
            if x in RADSET: by_rad[x].append((total or 99, -cf.get(t, 0), t))
    rad_in = {r: "".join(t for _, _, t in sorted(v)) for r, v in by_rad.items()}
    print("radical combinations: characters per radical", sum(len(v) for v in rad_in.values()) // max(len(rad_in), 1))

out = {"v": 1, "nc": nc, "e": out_entries}
# "r": [[radical, its strokes, characters (fewest other strokes first, then the most common), [their other strokes]]]
out["r"] = [[r, n, rad_chars[r], rad_res[r]] for r, n in rad_list]
# "rx": {radical: every character with it anywhere inside, fewest strokes first}
if rad_in: out["rx"] = rad_in
if chars_out: out["c"] = chars_out
# the entries last, one per line: the app reads them in parts at the same time (on all the cores), which is
# much faster than reading the whole file in one go. Still one ordinary JSON file.
es = out.pop("e")
head = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
with open(OUT, "w") as f:
    f.write(head[:-1] + ',"e":[\n')
    f.write(",\n".join(json.dumps(c, ensure_ascii=False, separators=(",", ":")) for c in es))
    f.write("\n]}")
print("cards", nc, "of", len(out_entries))
