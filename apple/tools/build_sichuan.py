#!/usr/bin/env python3
# 華語 → 四川話: the 四川話 (成都) readings of the 華語 dictionary's words, from Wiktionary (kaikki.org, CC BY-SA),
# into a file of its own (FangfangCards/zh_sc.json). The dictionary (zh.json) isn't changed: the app shows these
# readings when 讀音 = 四川話, and the 普通話 reading for a word Wiktionary has no 四川話 reading for.
#   python3 build_sichuan.py zh.json OUT [kaikki.org-dictionary-Chinese.jsonl]
#   (without the Wiktionary file it's read straight from kaikki.org, without saving it)
#
# A Wiktionary page counts for a word only when it has the same 漢字 and its 普通話 reading (拼音, without the
# tones) is the word's: 行 xíng and 行 háng don't get each other's 四川話 reading. The readings are in 四川話拼音
# with the tone as a number: 1 陰平, 2 陽平, 3 上聲, 4 去聲 (the same four categories as 普通話's).
import collections, io, json, re, sys, unicodedata, urllib.request

ZH, OUT = sys.argv[1], sys.argv[2]
KAIKKI = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "-" else None
URL = "https://kaikki.org/dictionary/Chinese/kaikki.org-dictionary-Chinese.jsonl"

d = json.load(open(ZH, encoding="utf-8"))

# 注音 syllable → 拼音 (from the character readings: "ㄉㄧˊ" → "dí")
zy2py = {}
for c in d.get("c", []):
    for m in c.get("m", []):
        if len(m) > 1 and m[0] and m[1]: zy2py.setdefault(m[0], m[1])


def plain(s):
    """'zhòngjiǎng' / 'zhong4 jiang3' → 'zhongjiang' (no tones, ü → v, letters only)"""
    s = unicodedata.normalize("NFD", s.lower().replace("ü", "v"))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z]", "", s.replace("u:", "v"))


def toned(s):
    """'Zhòng jiǎng' → 'zhòngjiǎng' (with the tones, letters only)"""
    s = unicodedata.normalize("NFC", s.lower().replace("u:", "ü"))
    return "".join(c for c in s if c.isalpha())


def is_han(ch):
    return "㐀" <= ch <= "鿿" or "\U00020000" <= ch <= "\U0003ffff" or "豈" <= ch <= "﫿"


# the dictionary's words: 漢字 → [(key, 拼音 with the tones, without, number of syllables)]
words = {}
for e in d["e"]:
    h, k = e.get("h", ""), e.get("k", "")
    tw = (e.get("s") or "").split(" ")
    pys = []
    for z in tw:
        if z in ("-", "_", ""): continue
        p = zy2py.get(z) or zy2py.get(z.replace("˙", ""))
        if p is None: pys = None; break
        pys.append(p)
    if not pys: continue
    words.setdefault(h, []).append((k, toned("".join(pys)), plain("".join(pys)), len(tw), pys))
print(f"華語 words: {sum(len(v) for v in words.values())}", file=sys.stderr)

SUP = str.maketrans("⁰¹²³⁴⁵⁶⁷⁸⁹", "0123456789")
SYL = re.compile(r"^[a-z]+[1-5]$")


def sichuan(p):
    """'zhong⁴ jiang³' → ['zhong4', 'jiang3'] (None when it isn't syllables with a tone)"""
    p = p.translate(SUP).lower().replace("-", " ").strip()
    out = [s for s in p.split() if s]
    return out if out and all(SYL.match(s) for s in out) else None


def lines():
    if KAIKKI:
        return open(KAIKKI, encoding="utf-8-sig")
    print("reading Wiktionary from kaikki.org…", file=sys.stderr)
    return io.TextIOWrapper(urllib.request.urlopen(URL), encoding="utf-8")


# 四川話's own words (not in the 華語 dictionary): pages with meanings marked Sichuanese, and the words the
# dialect tables give for 成都 (聊天's table: 成都 擺龍門陣)
JUNK = re.compile(r"^(alternative form of|variant of|obsolete form of|synonym of|a surname|used in |only used in|short for|abbreviation of)", re.I)
own_pages = {}      # word → (四川話 readings, [English], [English of the meanings marked Sichuanese])
table_words = collections.defaultdict(list)     # 四川話 word → the 華語 words whose table gives it for 成都

def glosses(sense):
    if sense.get("form_of") or sense.get("alt_of"): return None
    gl = [re.sub(r"\s+", " ", g).strip() for g in sense.get("glosses") or [] if g]
    gl = [g for g in gl if g and not JUNK.search(g)]
    return gl[-1] if gl else None

out = {}
pages = 0
for line in lines():
    if "Chengdu" not in line and "Sichuanese" not in line: continue
    try: w = json.loads(line)
    except ValueError: continue
    if w.get("lang_code") != "zh": continue
    han = w.get("word", "")
    nh = sum(1 for ch in han if is_han(ch))
    if nh == 0 or nh != len(han): continue
    # the dialect tables: what 成都 says, and the 華語 words of the same table (the "formal" ones at its top). A page
    # can have several tables, one after the other (一: "one", "to die" …): a new one starts at its formal words
    formal, prev_formal = [], False
    for x in w.get("synonyms", []):
        t = set(x.get("tags") or []) | set(x.get("raw_tags") or [])
        xw = (x.get("word") or "").strip()
        is_formal = "Written-vernacular-Chinese" in t or "formal" in t
        if is_formal:
            if not prev_formal: formal = []
            if xw: formal.append(xw)
        prev_formal = is_formal
        if "Chengdu" in t and "Simplified-Chinese" not in t and xw and all(is_han(c) for c in xw) and xw not in formal:
            for m in formal:
                if m != xw and m not in table_words[xw]: table_words[xw].append(m)
    if han not in words:
        # a page of a word the 華語 dictionary doesn't have: kept, in case it's one of 四川話's own
        rs = []
        for s in w.get("sounds", []):
            t = set(s.get("tags") or []) | set(s.get("raw_tags") or [])
            if "Pinyin" in t and ("Chengdu" in t or "Sichuanese" in t):
                for alt in re.split(r"[,/;]", s.get("zh_pron") or ""):
                    r = sichuan(alt)
                    if r and len(r) == nh and r not in rs: rs.append(r)
        en, own = [], []
        for s in w.get("senses", []):
            g = glosses(s)
            if not g: continue
            t = set(s.get("tags") or []) | set(s.get("raw_tags") or [])
            if "Sichuanese" in t and g not in own: own.append(g)
            if g not in en: en.append(g)
        if rs or own:
            o = own_pages.setdefault(han, ([], [], []))
            for r in rs:
                if r not in o[0]: o[0].append(r)
            for g in en:
                if g not in o[1]: o[1].append(g)
            for g in own:
                if g not in o[2]: o[2].append(g)
    cands = words.get(han)
    if not cands: continue
    # the 四川話 readings and the 普通話 ones, in order (a page with two readings gives both, in the same order:
    # 間 jiān / jiàn, 四川話 jian1 / jian4)
    scs, mand = [], []
    for s in w.get("sounds", []):
        t = set(s.get("tags") or []) | set(s.get("raw_tags") or [])
        if "Pinyin" not in t: continue
        p = s.get("zh_pron") or ""
        if "Chengdu" in t or "Sichuanese" in t:
            for alt in re.split(r"[,/;]", p):
                r = sichuan(alt)
                if r and len(r) == nh and r not in scs: scs.append(r)
        elif "Mandarin" in t and t & {"Standard-Chinese", "Standard"} or t == {"Mandarin", "Pinyin"}:
            for alt in re.split(r"[,/;]", p):
                if toned(alt) and toned(alt) not in mand: mand.append(toned(alt))
    if not scs: continue

    def sc_for(pys):
        """the 四川話 reading that goes with a 普通話 reading: the one most like it (the same letters, the same tone),
        or the first. A 輕聲 reading (˙ㄉㄜ) gets one only when the page has just the one"""
        if len(scs) == 1: return scs[0]
        def score(sc):
            n = 0
            for a, b in zip(pys, sc):
                t = next((i + 1 for i, m in enumerate("\u0304\u0301\u030c\u0300") if m in unicodedata.normalize("NFD", a)), 0)
                la = plain(a).replace("zh", "z").replace("ch", "c").replace("sh", "s")
                lb = re.sub(r"\d", "", b)
                if la == lb or la.rstrip("g") == lb.rstrip("g"): n += 2
                if t == int(b[-1]): n += 1
            return n
        return max(scs, key=score)
    hit = False
    for k, py, bare, n, pys in cands:
        if n != nh or k in out: continue
        # the page's 普通話 reading is the word's: with the tones, or without them when none has them the same
        # (or the page gives none and there's only the one word)
        if py in mand:
            if not all(re.search("[\u0304\u0301\u030c\u0300]", unicodedata.normalize("NFD", x)) for x in pys) and len(cands) > 1:
                continue        # (a 輕聲 reading of a character that has others: 底 ˙ㄉㄜ isn't 底 di3)
            out[k] = " ".join(sc_for(pys)); hit = True
        elif not any(c[1] in mand for c in cands) and bare in {plain(m) for m in mand} and len(cands) == 1:
            out[k] = " ".join(scs[0]); hit = True
        elif not mand and len(cands) == 1:
            out[k] = " ".join(scs[0]); hit = True
    if hit: pages += 1

# the other words: each character's 四川話 reading from the words that have one (a word of its own first, then the
# words it's in), the way the 台語 dictionary's readings are guessed for a place. A word gets a guessed reading only
# when every character of it has one
by_zy = {}       # (字, 注音) → Counter of 四川話 syllables
for e in d["e"]:
    k = e.get("k", "")
    if k not in out: continue
    h = [ch for ch in e.get("h", "")]
    tw = (e.get("s") or "").split(" ")
    sc = out[k].split(" ")
    if len(h) != len(tw) or len(tw) != len(sc): continue
    single = len(h) == 1
    for ch, z, x in zip(h, tw, sc):
        if z in ("-", "_"): continue
        c = by_zy.setdefault((ch, z), collections.Counter())
        c[x] += 1000 if single else 1        # (the character's own word decides)

def bare_zy(z): return z.replace("˙", "").rstrip("ˊˇˋ")
by_bare = {}
for (ch, z), c in by_zy.items():
    by_bare.setdefault((ch, bare_zy(z)), collections.Counter()).update(c)

def guess_syl(ch, z):
    """a character's 四川話 syllable for this 注音: where it's read that way somewhere; a 輕聲 syllable: the one of
    the same letters (謝謝 ˙ㄒㄧㄝ → xie4). (Not a reading with another tone or other letters: 還 ㄒㄩㄢˊ isn't hai2)"""
    c = by_zy.get((ch, z))
    if not c and z.startswith("˙"): c = by_bare.get((ch, bare_zy(z)))
    return c.most_common(1)[0][0] if c else None

# ── predicting: the regular sound changes from 普通話 to 四川話, learned from the characters that have a reading ──
# (zh ch sh → z c s, n/l → n, -ing/-eng → -in/-en, a zero initial before a e o → ng-, …; and the tones: 1 2 3 4 stay,
# but the old 入聲 characters (that ended in -p -t -k) are 2 in 成都. 普通話 lost those endings; 粵語 kept them, so
# a character read with -p/-t/-k in the 粵語 data (yue.json next to zh.json) counts as one)
import os
ru_of = {}
yp = os.path.join(os.path.dirname(os.path.abspath(ZH)), "yue.json")
if os.path.exists(yp):
    for c in json.load(open(yp, encoding="utf-8")).get("c", []):
        js = [m[1] for m in c.get("m", []) if len(m) > 1 and isinstance(m[1], str) and m[1]]
        if not js: continue
        checked = [bool(re.search(r"[ptk]\d$", j)) for j in js]
        ru_of[c["h"]] = True if all(checked) else (False if not any(checked) else None)
print(f"入聲 (from 粵語): {sum(1 for v in ru_of.values() if v)} characters" if ru_of else "（沒有粵語資料：入聲的字的聲調會比較常錯）", file=sys.stderr)

INITS = sorted(["zh", "ch", "sh", "ng", "nh", "ny", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x",
                "z", "c", "s", "r", "y", "w", "v"], key=len, reverse=True)
def split_syl(s):
    for i in INITS:
        if s.startswith(i) and len(s) > len(i): return i, s[len(i):]
    return "", s
def init_class(i):
    return "retro" if i in ("zh", "ch", "sh", "r") else "pal" if i in ("j", "q", "x") else "lab" if i in ("b", "p", "m", "f") \
        else "zero" if i in ("", "y", "w") else "other"
def py_tone(p):
    n = unicodedata.normalize("NFD", p)
    for t, m in enumerate("̄́̌̀"):
        if m in n: return t + 1
    return 0

# the 注音 readings of each character (a 輕聲 syllable takes the tone of the character's reading with the same letters)
char_zys = {}
for c in d.get("c", []):
    char_zys[c["h"]] = [m[0] for m in c.get("m", []) if m and m[0]]
def citation(ch, z):
    if not z.startswith("˙"): return z
    b = bare_zy(z)
    for o in char_zys.get(ch, []):
        if not o.startswith("˙") and bare_zy(o) == b: return o
    return None

# the training data: each (字, 注音) with a reading → (普通話 initial, final, tone, 入聲?, 四川話 syllable)
train = []
for (ch, z), c in by_zy.items():
    if z.startswith("˙"): continue
    p = zy2py.get(z)
    if not p: continue
    sc = c.most_common(1)[0][0]
    mi, mf = split_syl(plain(p))
    train.append((ch, plain(p), mi, mf, py_tone(p), ru_of.get(ch), sc, p))

class Model:
    def __init__(self, rows):
        C = lambda: collections.defaultdict(collections.Counter)
        self.whole, self.ini, self.ini0, self.fin, self.fin1, self.fin0, self.tone, self.tone0 = C(), C(), C(), C(), C(), C(), C(), C()
        for ch, pl, mi, mf, mt, ru, sc, _ in rows:
            letters, st = sc[:-1], sc[-1]
            si, sf = split_syl(letters)
            self.whole[(pl, ru)][letters] += 1
            self.whole[(pl, "*")][letters] += 1
            self.ini[(mi, mf[:1])][si] += 1
            self.ini0[mi][si] += 1
            self.fin[(mf, ru, init_class(mi))][sf] += 1
            self.fin1[(mf, init_class(mi))][sf] += 1
            self.fin0[mf][sf] += 1
            self.tone[(mt, ru)][st] += 1
            self.tone0[mt][st] += 1
    @staticmethod
    def best(*cs, least=1):
        for c in cs:
            if c and sum(c.values()) >= least: return c.most_common(1)[0][0]
        return None
    def predict(self, p, ru):
        pl = plain(p); mi, mf = split_syl(pl); mt = py_tone(p)
        letters = self.best(self.whole.get((pl, ru)), self.whole.get((pl, "*")), least=2)
        if letters is None:
            si = self.best(self.ini.get((mi, mf[:1])), self.ini0.get(mi))
            sf = self.best(self.fin.get((mf, ru, init_class(mi))), self.fin1.get((mf, init_class(mi))), self.fin0.get(mf))
            if si is None: si = mi
            if sf is None: sf = mf
            letters = si + sf
        t = self.best(self.tone.get((mt, ru)), self.tone0.get(mt))
        if t is None: t = str(mt or 1)
        return letters + t

# how good it is: each tenth character predicted from the other nine tenths
if train:
    ok = ok_l = ok_t = n = 0
    for f in range(10):
        m = Model([r for i, r in enumerate(train) if i % 10 != f])
        for ch, pl, mi, mf, mt, ru, sc, p in train[f::10]:
            guess = m.predict(p, ru)
            n += 1; ok += guess == sc; ok_l += guess[:-1] == sc[:-1]; ok_t += guess[-1] == sc[-1]
    print(f"預測的準確度（拿已知的字測試，{n} 個）：完全對 {ok * 100 // max(n, 1)}%，聲母韻母對 {ok_l * 100 // max(n, 1)}%，聲調對 {ok_t * 100 // max(n, 1)}%", file=sys.stderr)
model = Model(train)

def predict_syl(ch, z):
    z0 = citation(ch, z)
    if not z0: return None
    p = zy2py.get(z0)
    return model.predict(p, ru_of.get(ch)) if p and train else None

guessed, predicted = {}, {}
for e in d["e"]:
    k = e.get("k", "")
    if k in out: continue
    h = [ch for ch in e.get("h", "")]
    tw = (e.get("s") or "").split(" ")
    if not h or len(h) != len(tw) or any(z in ("-", "_", "") for z in tw): continue
    sy = [guess_syl(ch, z) for ch, z in zip(h, tw)]
    if all(sy): guessed[k] = " ".join(sy); continue
    # a character no word has a reading for: predicted from the sound changes
    sy = [x or predict_syl(ch, z) for x, ch, z in zip(sy, h, tw)]
    if all(sy): predicted[k] = " ".join(sy)

# 四川話's own words: a word from a 成都 dialect table, or a page with meanings marked Sichuanese, that the 華語
# dictionary doesn't have. Each: 漢字, its 四川話 reading and where that's from (0 Wiktionary, 1 guessed, 2 predicted),
# a 普通話 reading to show with 國語 / 普通話 (each character's usual one), the English, the 華語 words for it
new_words = []
for h in sorted(set(table_words) | {h for h, o in own_pages.items() if o[2]}):
    if h in words: continue
    zs = []
    for ch in h:
        zys = char_zys.get(ch)
        if not zys: zs = None; break
        zs.append(next((z for z in zys if not z.startswith("˙")), zys[0]))
    if not zs: continue
    o = own_pages.get(h, ([], [], []))
    if o[0]: sc, kind = o[0][0], 0
    else:
        sy = [guess_syl(ch, z) for ch, z in zip(h, zs)]
        kind = 1 if all(sy) else 2
        sy = [x or predict_syl(ch, z) for x, ch, z in zip(sy, h, zs)]
        if not all(sy): continue
        sc = sy
    en = (o[2] or o[1])[:6]
    mw = [m for m in table_words.get(h, []) if m in words][:6]
    if not en and not mw: continue
    new_words.append({"h": h, "s": " ".join(sc), "k": kind, "z": " ".join(zs), "e": en, "m": mw})

# and the 華語 dictionary's words that a 成都 dialect table gives (擺龍門陣 for 聊天): their 華語 words too
# (words of two characters or more: a single character in a table is often a measure word or one of many meanings:
# 去 "to die")
known_eq = {h: [m for m in ms if m in words][:6] for h, ms in table_words.items() if h in words and len(h) >= 2}
known_eq = {h: ms for h, ms in known_eq.items() if ms}

with open(OUT, "w", encoding="utf-8") as f:
    # s: from Wiktionary; g: guessed from how the characters are read in other words; p: (also) predicted;
    # w: 四川話's own words; q: words of the dictionary that 成都 says, with the 華語 words for them
    json.dump({"v": 4, "s": out, "g": guessed, "p": predicted, "w": new_words, "q": known_eq}, f, ensure_ascii=False, separators=(",", ":"))
print(f"四川話 readings for {len(out)} 華語 words, from {pages} Wiktionary pages; guessed from the characters for "
      f"{len(guessed)} more; predicted from the sound changes for {len(predicted)}; "
      f"{len(new_words)} words of 四川話's own", file=sys.stderr)
