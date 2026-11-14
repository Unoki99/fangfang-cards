#!/usr/bin/env python3
"""瑞典語 on the Mac (for the Safari pop-up; the app makes its own with FangfangCards/Install/swedish.js, the same
way): Folkets lexikon (KTH, CC BY-SA 2.5) → sv.json, with each word's morphemes, how common it is (FrequencyWords,
CC BY-SA 4.0) and the Chinese Wiktionary's Chinese meanings (kaikki.org, CC BY-SA) when they were downloaded.
    python3 build_swedish.py folkets_sv_en_public.xml sv_50k.txt|- kaikki.org-dictionary-瑞典語.jsonl|- sv.json [cedict_ts.u8|- [essay.txt]]
Kept the same as swedish.js (see there for what each part does)."""
import html
import json
import math
import re
import sys

SV_CLASS = {
    "nn": "名詞", "vb": "動詞", "jj": "形容詞", "ab": "副詞", "pn": "代名詞", "pp": "介詞", "kn": "連詞", "sn": "從屬連詞",
    "in": "感嘆詞", "rg": "數詞", "ro": "序數詞", "pm": "專有名詞", "abbrev": "縮寫", "prefix": "前綴", "suffix": "後綴",
    "hp": "疑問詞", "ie": "不定式標記", "ps": "物主代名詞", "article": "冠詞",
}
SV_SUFFIXES = sorted(["mässig", "aktig", "else", "skap", "ning", "ande", "ende", "ering", "itet",
                      "inna", "tion", "sion", "full", "het", "dom", "isk", "bar", "sam", "lös", "fri", "vis", "lig", "are", "eri", "ism",
                      "ist", "nad", "era", "ska", "ing", "ör", "ig"], key=lambda x: -len(x))
SV_PREFIXES = sorted(["miss", "sam", "sär", "van", "åter", "över", "under", "efter", "före", "fram", "till", "upp", "ut",
                      "in", "an", "av", "be", "bi", "er", "för", "ge", "mot", "med", "om", "o", "ur", "all", "icke", "anti", "super",
                      "mini", "multi", "inter", "ex", "re", "pre", "post", "sub", "trans"], key=lambda x: -len(x))
SV_LINKS = ["s", "e", "a", "u", "o"]
SV_VERBAL = ["ing", "ning", "are", "bar", "ande", "ende", "else", "nad", "eri", "ande"]
SV_VOWEL = re.compile(r"[aeiouyåäöé]")
# (Python's sort is stable like JavaScript's: equal lengths keep the list's order)


def decode(s):
    def one(t):
        return re.sub(r"&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);",
                      lambda m: {"amp": "&", "lt": "<", "gt": ">", "quot": '"', "apos": "'"}.get(m.group(1))
                      or chr(int(m.group(1)[2:], 16) if m.group(1)[1] == "x" else int(m.group(1)[1:])), t)
    return one(one(s)).strip()


def attrs(tag):
    return {m.group(1): decode(m.group(2)) for m in re.finditer(r'(\w+)="([^"]*)"', tag)}


NESTED = "example|idiom|definition|explanation|compound|derivation|related|variant"


def words_of(xml):
    out = []
    p = 0
    while True:
        a = xml.find("<word ", p)
        if a < 0:
            break
        ae = xml.find(">", a)
        b = xml.find("</word>", ae)
        if ae < 0 or b < 0:
            break
        at = attrs(xml[a:ae])
        body = xml[ae + 1:b]
        p = b + 7
        ex = []
        for m in re.finditer(r"<(example|idiom)\s+([^>]*?)(/?)>([\s\S]*?)(?:</\1>|$)", body):
            if m.group(3) == "/":
                v = attrs(m.group(2)).get("value")
                if v:
                    ex.append([v, ""])
                continue
            v = attrs(m.group(2)).get("value")
            t = re.search(r"<translation\s+([^>]*?)/?>", m.group(4))
            if v:
                ex.append([v, (attrs(t.group(1)).get("value") or "") if t else ""])
        d = ""
        dm = re.search(r"<definition\s+[^>]*?>\s*<translation\s+([^>]*?)/?>", body)
        if dm:
            d = attrs(dm.group(1)).get("value") or ""
        body = re.sub(r"<(" + NESTED + r")\b[^>]*?/>", "", body)
        body = re.sub(r"<(" + NESTED + r")\b[\s\S]*?</\1>", "", body)
        tr = [v for v in (attrs(m.group(1)).get("value") for m in re.finditer(r"<translation\s+([^>]*?)/?>", body)) if v]
        inf = [v for v in (attrs(m.group(1)).get("value") for m in re.finditer(r"<inflection\s+([^>]*?)/?>", body)) if v]
        syn = [v for v in (attrs(m.group(1)).get("value") for m in re.finditer(r"<synonym\s+([^>]*?)/?>", body)) if v]
        if not at.get("value"):
            continue
        out.append({"value": at["value"], "cls": at.get("class", ""), "tr": tr, "ex": ex, "inf": inf, "syn": syn, "def": d})
    return out


def morphemes(words):
    known, marks, verbs = set(), {}, set()
    for w in words:
        if w["cls"] in ("prefix", "suffix"):
            continue
        plain = w["value"].replace("|", "").lower()
        if len(plain) >= 2 and not re.search(r"[\s\-.,]", plain):
            known.add(plain)
        if w["cls"] == "vb":
            verbs.add(plain)
        if w["value"].find("|") > 0 and plain not in marks:
            marks[plain] = [x for x in w["value"].lower().split("|") if x]

    def is_word(x):
        return len(x) >= 2 and x in known

    def seg(w, depth):
        if depth > 5:
            return [[w, "r", w if is_word(w) else ""]]
        parts = marks.get(w)
        if parts and len(parts) > 1:
            out = []
            for i, p in enumerate(parts):
                last = i == len(parts) - 1
                if last and i > 0 and p in SV_SUFFIXES:
                    out.append([p, "s", ""])
                    continue
                if i == 0 and not last and p in SV_PREFIXES:
                    out.append([p, "p", ""])
                    continue
                out.extend(part(p, last, depth))
            return out
        return affixes(w, depth) or compound(w, depth) or [[w, "r", w if is_word(w) else ""]]

    def compound(w, depth):
        if depth > 5 or len(w) < 6:
            return None

        def fits(a, b):
            return (a >= 4 and b >= 4) or (min(a, b) >= 3 and max(a, b) >= 6)
        for i in range(len(w) - 3, 2, -1):
            left, right = w[:i], w[i:]
            if not is_word(right) or not SV_VOWEL.search(right) or not fits(len(left), len(right)):
                continue
            if is_word(left) and SV_VOWEL.search(left):
                return seg(left, depth + 1) + seg(right, depth + 1)
            l = left[-1]
            if len(left) > 3 and l in SV_LINKS:
                b = left[:-1]
                if is_word(b) and SV_VOWEL.search(b):
                    return seg(b, depth + 1) + [[l, "l", ""]] + seg(right, depth + 1)
        return None

    def part(p, last, depth):
        if is_word(p):
            return seg(p, depth + 1)
        if not last and len(p) > 3:
            for l in SV_LINKS:
                if not p.endswith(l):
                    continue
                b = p[:-1]
                if is_word(b):
                    return seg(b, depth + 1) + [[l, "l", ""]]
                for e in ("e", "a"):
                    if is_word(b + e):
                        return root(b, b + e, depth) + [[l, "l", ""]]
            if p.endswith("es") and len(p) > 4:
                b = p[:-2]
                for e in ("a", "e", ""):
                    if is_word(b + e):
                        return root(b, b + e, depth) + [["es", "l", ""]]
        for e in ("a", "e"):
            if is_word(p + e):
                return root(p, p + e, depth)
        return affixes(p, depth) or [[p, "r", ""]]

    def root(text, word, depth):
        s = seg(word, depth + 1)
        cut = len(word) - len(text)
        l = s[-1]
        if len(s) > 1 and l[1] == "e" and len(l[0]) == cut:
            return s[:-1]
        if len(s) > 1 and l[1] == "r" and len(l[0]) > cut:
            return s[:-1] + [[l[0][:len(l[0]) - cut], "r", l[2] or word]]
        return [[text, "r", word]]

    def affixes(w, depth):
        if depth > 5:
            return None
        for suf in SV_SUFFIXES:
            if not w.endswith(suf) or len(w) - len(suf) < 3:
                continue
            r = w[:-len(suf)]
            if not SV_VOWEL.search(r):
                continue
            if suf in SV_VERBAL and (r + "a") in verbs and r + "a" != w:
                return root(r, r + "a", depth) + [[suf, "s", ""]]
            if is_word(r) and r != w:
                return seg(r, depth + 1) + [[suf, "s", ""]]
            for e in ("a", "e"):
                if is_word(r + e) and r + e != w:
                    return root(r, r + e, depth) + [[suf, "s", ""]]
            if len(r) > 3 and r[-1] in SV_LINKS:
                b = r[:-1]
                if is_word(b):
                    return seg(b, depth + 1) + [[r[-1], "l", ""], [suf, "s", ""]]
                for e in ("e", "a"):
                    if is_word(b + e):
                        return root(b, b + e, depth) + [[r[-1], "l", ""], [suf, "s", ""]]
        for pre in SV_PREFIXES:
            if not w.startswith(pre):
                continue
            r = w[len(pre):]
            c = pre[-1]
            if len(r) >= 3 and r[0] != c and not re.match(r"[aeiouyåäö]", c):
                for e in ("", "a"):
                    if is_word(c + r + e):
                        return [[pre, "p", ""], [r, "r", c + r + e]]
            if len(r) >= 3 and SV_VOWEL.search(r) and is_word(r):
                return [[pre, "p", ""]] + seg(r, depth + 1)
        return None

    out = {}
    for w in words:
        plain = w["value"].replace("|", "")
        low = plain.lower()
        if (low + "\t" + w["cls"]) in out or re.search(r"[\s\-.,]", low) or w["cls"] in ("prefix", "suffix"):
            continue
        s = seg(low, 0)
        if w["cls"] == "vb" and len(low) >= 4 and low.endswith("a"):
            l = s[-1]
            if l[1] == "r" and len(l[0]) > 2 and l[0].endswith("a"):
                s = s[:-1] + [[l[0][:-1], "r", l[2] or low], ["a", "e", ""]]
        at = 0
        s2 = []
        for x in s:
            t = plain[at:at + len(x[0])]
            at += len(x[0])
            s2.append([t, x[1], x[2]])
        out[low + "\t" + w["cls"]] = s2 if len(s2) > 1 and at == len(plain) else None
    return out


FORM_OF = re.compile(r"(的|之)(複數|单数|單數|定指|不定指|定式|不定式|屬格|所有格|過去|过去|現在|现在|命令|分詞|分词|比較級|比较级|最高級|最高级|被動|被动|中性|陰性|陽性|通性|變格|变格|變位|变位|形式)|^(複數|复数|單數|单数)(形式)?$")
POS = {"noun": "nn", "verb": "vb", "adj": "jj", "adv": "ab", "pron": "pn", "prep": "pp", "conj": "kn", "intj": "in", "num": "rg"}


def chinese(path):
    out = {}
    if not path:
        return out
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n").rstrip("\r")
            if len(line) < 10 or '"sv"' not in line:
                continue
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if e.get("lang_code") != "sv" or not e.get("word") or not e.get("senses"):
                continue
            gl = []
            for s in e["senses"]:
                if s.get("form_of") or "form-of" in (s.get("tags") or []):
                    continue
                for g in s.get("glosses") or []:
                    t = str(g).strip()
                    if not t or FORM_OF.search(t) or re.search(r"[a-zA-ZåäöÅÄÖ]{3}", re.sub(r"[（(][^）)]*[）)]", "", t)):
                        continue
                    if t not in gl:
                        gl.append(t)
            if not gl:
                continue
            w, c = e["word"].lower(), POS.get(e.get("pos"), "")
            m = out.setdefault(w, {})
            seen = []
            for x in (m.get(c) or []) + gl:
                if x not in seen:
                    seen.append(x)
            m[c] = seen[:6]
    return out


def unique(xs):
    out = []
    for x in xs:
        if x not in out:
            out.append(x)
    return out


def english_index(path):
    out = {}
    if not path:
        return out
    with open(path, encoding="utf-8") as f:
        for line in f.read().split("\n"):
            line = re.sub(r"\r$", "", line)
            if not line or line[0] == "#":
                continue
            m = re.match(r"^(\S+) (\S+) \[[^\]]*\] /(.*)/$", line)
            if not m:
                continue
            trad = m.group(1)
            if re.search(r"[A-Za-z0-9]", trad) or len(trad) > 4:
                continue
            for i, d0 in enumerate(m.group(3).split("/")):
                if i > 2:
                    continue
                d = re.sub(r"\([^)]*\)", "", d0).strip().lower()
                narrow = 5 if "(" in d0 else 0
                if not d or re.match(r"(surname|variant of|old variant|see |used in|abbr|cl:|erhua|japanese|taiwan pr|also pr|classifier)", d):
                    continue
                for piece in re.split(r";\s*", d):
                    t = piece.strip()
                    if not t:
                        continue
                    key = "v:" + t[3:] if t.startswith("to ") else "n:" + t
                    lst = out.setdefault(key, [])
                    if not any(x[0] == trad for x in lst):
                        lst.append([trad, i * 3 + narrow + abs(len(trad) - 2)])
    return out


def essay_counts(path):
    out = {}
    if not path:
        return out
    with open(path, encoding="utf-8") as f:
        for l in f.read().split("\n"):
            p = re.sub(r"\r$", "", l).split("\t")
            if len(p) == 2:
                try:
                    out[p[0]] = int(p[1])
                except ValueError:
                    out[p[0]] = 0
    return out


def guess_chinese(idx, cls, terms, freq):
    got = []
    for t0 in [y for x in terms for y in re.split(r",\s*", x)][:2]:
        t = re.sub(r"^(to|a|an|the) ", "", re.sub(r"\([^)]*\)", "", t0).strip().lower())
        if not t:
            continue
        lst = idx.get(("v:" if cls == "vb" else "n:") + t, [])
        if freq:
            lst = [x for x in lst if freq.get(x[0], 0) >= 1000]
        lst = sorted(lst, key=lambda x: x[1] - 4 * math.log10(freq.get(x[0], 0) + 1))
        for w, _ in lst[:2]:
            if w not in got:
                got.append(w)
    return got[:3]


def chinese_english(path, freq):
    out = {}
    if not path or not freq:
        return out
    with open(path, encoding="utf-8") as f:
        for line in f.read().split("\n"):
            line = re.sub(r"\r$", "", line)
            if not line or line[0] == "#":
                continue
            m = re.match(r"^(\S+) (\S+) \[[^\]]*\] /(.*)/$", line)
            if not m or freq.get(m.group(1), 0) < 300:
                continue
            en = []
            for d0 in m.group(3).split("/"):
                d = re.sub(r"\([^)]*\)", "", d0).strip()
                if not d or re.match(r"(surname|variant of|old variant|see |used in|abbr|cl:|erhua|japanese|taiwan pr|also pr|classifier)", d, re.I):
                    continue
                for p in re.split(r";\s*", d):
                    t = p.strip()
                    if t and t not in en:
                        en.append(t)
            if not en:
                continue
            for w in (m.group(1), m.group(2)):
                have = out[w].split("; ") if w in out else []
                for t in en:
                    if len(have) < 4 and t not in have:
                        have.append(t)
                out[w] = "; ".join(have)
    return out


def main(folkets, freq, zhwikt, out_path, cedict=None, essay=None):
    xml = open(folkets, encoding="utf-8").read()
    words = words_of(xml)
    print("Folkets lexikon:", len(words), "words", file=sys.stderr)
    morph = morphemes(words)
    rank = {}
    if freq:
        i = 0
        for l in open(freq, encoding="utf-8").read().split("\n"):
            w = l.rstrip("\r").split(" ")[0]
            if w and w not in rank:
                i += 1
                rank[w] = i
    zh = chinese(zhwikt)
    en_zh = english_index(cedict)
    ess = essay_counts(essay) if en_zh else {}
    groups, order = {}, []
    for w in words:
        if w["cls"] in ("prefix", "suffix"):
            continue
        h = w["value"].replace("|", "")
        i = h + "\t" + w["cls"]
        if i not in groups:
            groups[i] = []
            order.append(i)
        groups[i].append(w)
    entries, keys = [], set()
    for i in order:
        ws = groups[i]
        h = ws[0]["value"].replace("|", "")
        cls = ws[0]["cls"]
        low = h.lower()
        k = h + "\t瑞" + cls
        while k in keys:
            k += "＊"
        keys.add(k)
        d, al = [], []
        for w in ws:
            if not w["tr"] and not w["def"]:
                continue
            t = "; ".join(w["tr"]) or w["def"]
            if w["def"] and w["tr"]:
                t += " (" + w["def"] + ")"
            d.append([t, w["ex"][:4]])
            for x in w["tr"]:
                if x not in al:
                    al.append(x)
        if not d:
            continue
        inf = [x for x in unique([f for w in ws for f in w["inf"]]) if x != h and x not in al]
        ms = morph.get(low + "\t" + cls)
        o = {"k": k, "h": h, "s": " ".join(x[0] + ":" + x[1] + (":" + x[2] if x[2] and x[2] != low else "") for x in ms) if ms else "",
             "d": d, "n": "; ".join(al)}
        if cls in SV_CLASS:
            o["w"] = [SV_CLASS[cls]]
        if inf:
            o["m"] = inf[:12]
        syn = [x for x in unique([s for w in ws for s in w["syn"]]) if x != h]
        if syn:
            o["j"] = syn[:8]
        z = zh.get(low)
        if z:
            c = z.get(cls) or z.get("") or (list(z.values())[0] if len(z) == 1 else None)
            if c:
                o["jp"] = c
        if "jp" not in o and en_zh:
            g = guess_chinese(en_zh, cls, al, ess)
            if g:
                o["jp"] = ["≈" + x for x in g]
        r = rank.get(low, 0)
        for f in inf:
            x = rank.get(f.lower())
            if x and (not r or x < r):
                r = x
        o["_r"] = r
        entries.append(o)
    ranked = sorted([e for e in entries if 0 < e["_r"] <= 30000], key=lambda e: e["_r"])
    rest = [e for e in entries if not (0 < e["_r"] <= 30000)]
    for n, e in enumerate(ranked):
        e["y"] = n // 500 + 1
        e["x"] = e["y"]
    outs = []
    for e in ranked + rest:
        del e["_r"]
        outs.append(e)
    head = {"v": 3, "lang": "sv", "nc": len(ranked), "c": [], "tags": {}}
    ce = chinese_english(cedict, ess)
    if ce:
        head["ce"] = ce
    dump = lambda o: json.dumps(o, ensure_ascii=False, separators=(",", ":"))
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(dump(head)[:-1] + ',"e":[\n' + ",\n".join(dump(e) for e in outs) + "\n]}")
    print("sv.json:", len(outs), "entries,", len(ranked), "common", file=sys.stderr)


if __name__ == "__main__":
    opt = lambda x: x if x and x != "-" else None
    main(sys.argv[1], opt(sys.argv[2]), opt(sys.argv[3]), sys.argv[4], opt(sys.argv[5]) if len(sys.argv) > 5 else None,
         opt(sys.argv[6]) if len(sys.argv) > 6 else None)
