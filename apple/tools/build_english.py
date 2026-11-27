#!/usr/bin/env python3
"""英語 on the Mac (for the Safari pop-up; the app makes its own with FangfangCards/Install/english.js, the same
data): ECDICT (MIT) → en.json, with CMUdict's American readings (BSD), Folkets lexikon the other way round for the
Swedish words and example sentences (CC BY-SA 2.5), FrequencyWords for the Swedish words' order (CC BY-SA 4.0) and
CC-CEDICT's pairs for the Chinese in 正體 (CC BY-SA).
Kept the same as english.js (see there for what each part does).

  build_english.py ecdict.csv cmudict.dict|- folkets.xml|- sv_50k.txt|- cedict_ts.u8|- out/en.json
"""
import csv, html, json, re, sys

csv.field_size_limit(1 << 30)

EN_CLASS = {
    "n": "名詞", "v": "動詞", "vt": "動詞", "vi": "動詞", "a": "形容詞", "adj": "形容詞", "s": "形容詞", "ad": "副詞",
    "adv": "副詞", "r": "副詞", "prep": "介詞", "conj": "連詞", "pron": "代名詞", "int": "感嘆詞", "interj": "感嘆詞",
    "num": "數詞", "art": "冠詞", "aux": "助動詞", "abbr": "縮寫", "pref": "前綴", "suf": "後綴",
}
EN_SHOWN = {"a": "adj", "s": "adj", "r": "adv", "ad": "adv", "int": "interj"}
EN_EXAMS = [("zk", 1), ("gk", 2), ("cet4", 3), ("cet6", 4), ("ky", 5), ("toefl", 6), ("ielts", 6), ("gre", 7)]
ARPA = {
    "AA": "ɑ", "AE": "æ", "AH": "ʌ", "AO": "ɔ", "AW": "aʊ", "AY": "aɪ", "EH": "ɛ", "ER": "ɝ", "EY": "eɪ", "IH": "ɪ",
    "IY": "i", "OW": "oʊ", "OY": "ɔɪ", "UH": "ʊ", "UW": "u", "B": "b", "CH": "tʃ", "D": "d", "DH": "ð", "F": "f",
    "G": "ɡ", "HH": "h", "JH": "dʒ", "K": "k", "L": "l", "M": "m", "N": "n", "NG": "ŋ", "P": "p", "R": "ɹ", "S": "s",
    "SH": "ʃ", "T": "t", "TH": "θ", "V": "v", "W": "w", "Y": "j", "Z": "z", "ZH": "ʒ",
}
ONSET2 = re.compile(r"^(s[ptkmnlw]|[pbtdkɡfθʃ][ɹlw]|[ptkbdɡmnfvθszʃh]j)$")


def unique(xs):
    out = []
    for x in xs:
        if x not in out: out.append(x)
    return out


def ipa_uk(p):
    if not p: return ""
    return re.sub(r"\s+", "", p.replace("ә", "ə").replace("'", "ˈ").replace(",", "ˌ").replace(":", "ː")).strip()


def ipa_us(phones):
    toks = []
    for p in phones.split():
        m = re.match(r"^([A-Z]+)([012])?$", p)
        if not m or m.group(1) not in ARPA: continue
        t = ARPA[m.group(1)]
        if m.group(2) == "0" and m.group(1) == "AH": t = "ə"
        if m.group(2) == "0" and m.group(1) == "ER": t = "ɚ"
        toks.append({"t": t, "v": m.group(2) is not None, "s": m.group(2)})
    vowels = sum(1 for x in toks if x["v"])
    out = ""
    i = 0
    while i < len(toks):
        out += toks[i]["t"]
        nx = toks[i + 1:]
        vi = next((j for j, x in enumerate(nx) if x["v"]), -1)
        if vi < 0 or nx[vi]["s"] not in ("1", "2") or vowels < 2 or not any(x["v"] for x in toks[:i + 1]):
            i += 1
            continue
        run = [x["t"] for x in nx[:vi]]
        take = len(run) if len(run) <= 1 else (2 if ONSET2.match("".join(run[-2:])) else 1)
        mark = "ˈ" if nx[vi]["s"] == "1" else "ˌ"
        out += "".join(run[:len(run) - take]) + mark + "".join(run[len(run) - take:]) + nx[vi]["t"]
        i += vi + 2
    if vowels >= 2:
        fv = next((j for j, x in enumerate(toks) if x["v"]), -1)
        if fv >= 0 and toks[fv]["s"] in ("1", "2"): out = ("ˈ" if toks[fv]["s"] == "1" else "ˌ") + out
    return out


def read_cmu(path):
    out = {}
    if not path: return out
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if not line or line.startswith(";;;"): continue
            sp = line.find(" ")
            if sp < 0: continue
            w = line[:sp]
            if "(" in w: continue
            ph = re.sub(r"#.*$", "", line[sp + 1:])
            if w not in out: out[w] = ipa_us(ph)
    return out


def traditional(path):
    words, votes, kept = {}, {}, {}
    if path:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if not line or line[0] == "#": continue
                m = re.match(r"^(\S+) (\S+) \[", line)
                if not m: continue
                t, s = m.group(1), m.group(2)
                if len(t) != len(s): continue
                if t != s and 1 < len(t) <= 4 and s not in words: words[s] = t
                for a, b in zip(t, s):
                    if a == b: kept[b] = kept.get(b, 0) + 1; continue
                    v = votes.setdefault(b, {})
                    v[a] = v.get(a, 0) + 1
    chars = {}
    for s, v in votes.items():
        best = max(v, key=v.get)
        if v[best] > kept.get(s, 0): chars[s] = best

    def conv(text):
        out, i = "", 0
        while i < len(text):
            for ln in range(min(4, len(text) - i), 1, -1):
                w = words.get(text[i:i + ln])
                if w: out += w; i += ln; break
            else:
                out += chars.get(text[i], text[i]); i += 1
        return out
    return conv


def attrs(t):
    return {m.group(1): html.unescape(html.unescape(m.group(2))).strip() for m in re.finditer(r'(\w+)="([^"]*)"', t)}


def read_folkets(path):
    sv, ex = {}, {}
    if not path: return sv, ex
    xml = open(path, encoding="utf-8", errors="replace").read()
    p, order = 0, 0
    strip1 = re.compile(r"<(example|idiom|definition|explanation|compound|derivation|related|variant)\b[^>]*?/>")
    strip2 = re.compile(r"<(example|idiom|definition|explanation|compound|derivation|related|variant)\b[\s\S]*?</\1>")
    while True:
        a = xml.find("<word ", p)
        if a < 0: break
        ae = xml.find(">", a)
        b = xml.find("</word>", ae)
        if ae < 0 or b < 0: break
        at = attrs(xml[a:ae])
        body = xml[ae + 1:b]
        p = b + 7
        order += 1
        word = (at.get("value") or "").replace("|", "")
        if not word or at.get("class") in ("prefix", "suffix"): continue
        for m in re.finditer(r"<example\s+([^>]*?)>([\s\S]*?)</example>", body):
            v = attrs(m.group(1)).get("value")
            t = re.search(r"<translation\s+([^>]*?)/?>", m.group(2))
            en = attrs(t.group(1)).get("value", "") if t else ""
            if not v or not en: continue
            for w in unique(re.findall(r"[a-z']+", en.lower())):
                lst = ex.setdefault(w, [])
                if len(lst) < 40 and not any(x[0] == en for x in lst): lst.append([en, v])
        body = strip2.sub("", strip1.sub("", body))
        for m in re.finditer(r"<translation\s+([^>]*?)/?>", body):
            t = re.sub(r"\([^)]*\)", "", (attrs(m.group(1)).get("value") or "").lower()).strip()
            if at.get("class") == "vb": t = re.sub(r"^to ", "", t)
            t = re.sub(r"^(a|an|the) ", "", t).strip()
            if not t or len(t) > 30: continue
            lst = sv.setdefault(t, [])
            if not any(x[0] == word for x in lst): lst.append([word, order])
    return sv, ex


def lines(s):
    out = []
    for l0 in s.split("\\n"):
        l = l0.strip()
        if not l: continue
        m = re.match(r"^([a-z]+)\.?\s+(.*)$", l)
        if m and m.group(1) in EN_CLASS:
            out.append({"c": EN_SHOWN.get(m.group(1), m.group(1)), "cls": m.group(1), "t": m.group(2).strip()})
        elif out and re.match(r"^[a-z(]", l):
            out[-1]["t"] += " " + l
        else:
            out.append({"c": "", "cls": "", "t": l})
    return [x for x in out if not re.match(r"^([a-z]\.\s*)*See\s", x["t"])]


def main(ecdict, cmu_path, folkets, svfreq, cedict, out_path):
    arg = lambda p: None if p in ("-", "") else p
    cmu = read_cmu(arg(cmu_path))
    print(f"CMUdict: {len(cmu)} words", file=sys.stderr)
    folk_sv, folk_ex = read_folkets(arg(folkets))
    print(f"Folkets lexikon (the other way round): {len(folk_sv)} English words", file=sys.stderr)
    sv_rank = {}
    if arg(svfreq):
        with open(svfreq, encoding="utf-8") as f:
            for line in f:
                w = line.split(" ")[0]
                if w and w not in sv_rank: sv_rank[w] = len(sv_rank) + 1
    trad = traditional(arg(cedict))
    entries = []
    with open(ecdict, encoding="utf-8", newline="") as f:
        for r in csv.DictReader(f):
            w = r.get("word") or ""
            if not re.match(r"^[A-Za-z][A-Za-z' -]*$", w) or not r.get("translation"): continue
            frq = int(r.get("frq") or 0) if (r.get("frq") or "0").isdigit() else 0
            bnc = int(r.get("bnc") or 0) if (r.get("bnc") or "0").isdigit() else 0
            tags = r["tag"].split(" ") if r.get("tag") else []
            if not ((0 < frq <= 60000) or (0 < bnc <= 60000) or r.get("collins") or r.get("oxford") == "1" or tags): continue
            if re.match(r"^\[(人名|地名|姓氏)\]", r["translation"]) and not (0 < frq <= 20000): continue
            entries.append((r, w, frq, bnc, tags))
    print(f"ECDICT: {len(entries)} words", file=sys.stderr)
    out, keys = [], set()
    for r, w, frq, bnc, tags in entries:
        k = w + "\t英"
        while k in keys: k += "＊"
        keys.add(k)
        low = w.lower()
        en = [x for x in lines(r.get("definition") or "") if x["t"] and not x["t"].startswith("See ")]
        zh = [x for x in lines(r["translation"]) if x["t"] and not x["t"].startswith("[网络]")
              and not re.search(r"的(过去式|过去分词|现在分词|复数|第三人称单数|比较级|最高级)", x["t"])]
        cls = unique([EN_CLASS[x["cls"]] for x in en + zh if x["cls"] in EN_CLASS])
        svw = [x[0].lower()[:max(3, len(x[0]) - 2)] for x in folk_sv.get(low, [])]
        exs = [x for x in folk_ex.get(low, []) if not (frq and frq <= 3000) or any(t in x[1].lower() for t in svw)]
        d = ([[(x["c"] + ". " if x["c"] else "") + x["t"], exs[:4] if i == 0 else []] for i, x in enumerate(en[:8])]
             if en else [["", exs[:4]]])
        o = {"k": k, "h": w, "s": (ipa_uk(r.get("phonetic")) or "-") + " " + (cmu.get(low) or "-"), "d": d,
             "n": "; ".join(x["t"] for x in en)}
        if cls: o["w"] = cls
        jp = [(x["c"] + ". " if x["c"] else "") + re.sub(r",\s*", "、", trad(x["t"])) for x in zh][:8]
        if jp: o["jp"] = jp
        forms = []
        for part in (r.get("exchange") or "").split("/"):
            m = re.match(r"^([pdi3srt]):(.+)$", part)
            if m and m.group(2) != w and m.group(2) not in forms: forms.append(m.group(2))
        if forms: o["m"] = forms
        sw = [x[0] for x in sorted(folk_sv.get(low, []), key=lambda x: sv_rank.get(x[0].lower(), 1e6 + x[1]))]
        if sw: o["sw"] = unique(sw)[:6]
        col = int(r["collins"]) if (r.get("collins") or "").isdigit() else 0
        if col: o["x"] = 6 - col
        exam = 0
        for t, l in EN_EXAMS:
            if t in tags and (not exam or l < exam): exam = l
        if exam: o["y"] = exam
        if r.get("oxford") == "1": o["o"] = 1
        o["_r"] = frq or bnc or 0
        out.append(o)
    ranked = sorted([e for e in out if 0 < e["_r"] <= 30000], key=lambda e: e["_r"])
    rest = sorted([e for e in out if not (0 < e["_r"] <= 30000)], key=lambda e: (e.get("x") or 9, e.get("y") or 9))
    for i, e in enumerate(ranked): e["g"] = i // 500 + 1
    for e in ranked + rest:
        if e["_r"]: e["r"] = e["_r"]
        del e["_r"]
    head = {"v": 1, "lang": "en", "nc": len(ranked), "c": [], "tags": {}}
    dump = lambda x: json.dumps(x, ensure_ascii=False, separators=(",", ":"))
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(dump(head)[:-1] + ',"e":[\n' + ",\n".join(dump(e) for e in ranked + rest) + "\n]}")
    print(f"en.json: {len(ranked) + len(rest)} entries, {len(ranked)} common", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) != 7:
        print(__doc__, file=sys.stderr); sys.exit(1)
    main(*sys.argv[1:])
