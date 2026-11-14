#!/usr/bin/env python3
# 台語: English meanings for the 教育部 dictionary's words, from Wiktionary (kaikki.org, CC BY-SA), into a file of
# its own (FangfangCards/tw_en.json). The dictionary's own data (dict.json) isn't changed: the app only adds the
# English to a word's page and an English section to the search.
#   python3 build_tw_english.py dict.json OUT [kaikki.org-dictionary-Chinese.jsonl]
#   (without the Wiktionary file it's read straight from kaikki.org, without saving it)
#
# A Wiktionary page counts for a word only when it has the same 漢字 and gives a Hokkien reading (Tâi-lô) that is
# the dictionary's reading without the tones: 行 kiânn and 行 hâng don't get each other's English. The meanings
# Wiktionary marks as Hokkien come first; meanings marked as another variety's (Cantonese, Mandarin…) are left out.
import io, json, re, sys, unicodedata, urllib.request

DICT, OUT = sys.argv[1], sys.argv[2]
KAIKKI = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "-" else None
URL = "https://kaikki.org/dictionary/Chinese/kaikki.org-dictionary-Chinese.jsonl"

d = json.load(open(DICT, encoding="utf-8"))
tl = d["tl"]                 # syllable code → [Tâi-lô, Tâi-lô with a number]


def bare(s):
    """'tsia̍h-pn̄g' / 'tsiah8 png7' → 'tsiahpng' (no tones, no hyphens, no spaces)"""
    s = unicodedata.normalize("NFD", s.lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.replace("ⁿ", "nn").replace("o͘", "oo")
    return re.sub(r"[^a-z]", "", s)


def code_bare(codes):
    out = []
    for c in codes.split(" "):
        t = tl.get(c)
        if not t: return None
        out.append(bare(t[1] if len(t) > 1 else t[0]))
    return "".join(out)


# the dictionary's words: 漢字 → [(key, readings without tones)]
words = {}
for han, codes in d["words"]:
    k = han + "\t" + codes
    b = code_bare(codes)
    if b is None: continue
    rs = {b}
    for a in d.get("alt", {}).get(k, []):
        ab = code_bare(a[0]) if a and a[0] else None
        if ab: rs.add(ab)
    words.setdefault(han, []).append((k, rs))
print(f"台語 words: {sum(len(v) for v in words.values())}", file=sys.stderr)

OTHER = {"Cantonese", "Mandarin", "Beijing", "Hakka", "Wu", "Shanghainese", "Teochew", "Min-Dong", "Eastern-Min",
         "Gan", "Xiang", "Jin", "Sichuanese", "Taishanese", "Puxian-Min", "Northern-Min", "Dungan", "Hainanese",
         "Leizhou-Min", "Guangzhou-Cantonese", "Hong-Kong-Cantonese", "Taiwanese-Mandarin", "Singapore-Mandarin",
         "Mainland-China", "Malaysian-Mandarin", "Jianghuai-Mandarin", "Southwestern-Mandarin", "Northeastern-Mandarin"}
HOKKIEN = {"Hokkien", "Taiwanese-Hokkien", "Xiamen", "Quanzhou", "Zhangzhou", "Philippine-Hokkien", "Singapore-Hokkien",
           "Penang-Hokkien", "Min-Nan", "Southern-Min"}


# meanings that say nothing about the 台語 word: surnames, places, transcription, other forms
JUNK = re.compile(r"^(alternative form of|variant of|obsolete form of|synonym of|a surname|used in (transcription|place names|personal names)|"
                  r"only used in|short for|abbreviation of|\(historical\)|.*\(an? (town|county|district|village|township|city|prefecture|subdistrict)\b)",
                  re.I)


def clean(g):
    g = re.sub(r"\s*\(Classifier:[^)]*\)", "", g)
    g = re.sub(r"\s+", " ", g).strip()
    return g


def lines():
    if KAIKKI:
        return open(KAIKKI, encoding="utf-8-sig")
    print("reading Wiktionary from kaikki.org…", file=sys.stderr)
    return io.TextIOWrapper(urllib.request.urlopen(URL), encoding="utf-8")


english = {}                  # key → (Hokkien glosses, other glosses)
pages = 0
for line in lines():
    if '"zh"' not in line[:400] and '"lang_code": "zh"' not in line: continue
    try: w = json.loads(line)
    except ValueError: continue
    if w.get("lang_code") != "zh": continue
    han = w.get("word", "")
    cands = words.get(han)
    if not cands: continue
    # the page's Hokkien readings (Tâi-lô), without tones
    reads = set()
    for s in w.get("sounds", []):
        t = set(s.get("tags") or []) | set(s.get("raw_tags") or [])
        if not (t & {"Hokkien", "Min-Nan"}) or "Teochew" in t or "Leizhou" in t: continue
        if not (t & {"Tai-lo", "Tâi-lô"}): continue
        for p in re.split(r"[/,;]", s.get("zh_pron") or ""):
            b = bare(p)
            if b: reads.add(b)
    if not reads: continue
    hok, gen = [], []
    for s in w.get("senses", []):
        t = set(s.get("tags") or []) | set(s.get("raw_tags") or [])
        if s.get("form_of") or s.get("alt_of"): continue
        gl = [clean(g) for g in s.get("glosses") or [] if g]
        # (and the xiangqi pieces: 馬 "knight, horse: 🩪 (sometimes only on the black side)")
        gl = [g for g in gl if g and not JUNK.search(g) and not re.search("[\U0001FA60-\U0001FA6F]|on the (red|black) side", g)]
        if not gl: continue
        g = gl[-1] if len(gl) > 1 else gl[0]
        if t & HOKKIEN: hok.append(g)
        elif t & OTHER: continue
        else: gen.append(g)
    if not hok and not gen: continue
    hit = False
    for k, rs in cands:
        if rs & reads:
            h0, g0 = english.setdefault(k, ([], []))
            for g in hok:
                if g not in h0: h0.append(g)
            for g in gen:
                if g not in g0: g0.append(g)
            hit = True
    if hit: pages += 1

out = {}
nh = 0
for k, (h, g) in english.items():
    gs = (h + [x for x in g if x not in h])[:6]
    if not gs: continue
    if h: nh += 1
    # (a leading "*" marks a word with meanings Wiktionary says are Hokkien's own: they come first in the search)
    out[k] = ("*" if h else "") + "; ".join(x.replace(";", ",") for x in gs)
with open(OUT, "w", encoding="utf-8") as f:
    json.dump({"v": 1, "e": out}, f, ensure_ascii=False, separators=(",", ":"))
print(f"English for {len(out)} 台語 words ({nh} with Hokkien meanings), from {pages} Wiktionary pages", file=sys.stderr)
