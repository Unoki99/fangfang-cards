# Input method codes for the characters in the dictionaries -> FangfangCards/inputcodes.json
#   python3 build_inputcodes.py cangjie5.base.dict.yaml cangjie5.extended.dict.yaml wubi86.dict.yaml OUT.json [boshiamy.cin|-] [cedict_ts.u8]
#
# 倉頡 (5th edition) and 五筆 (86): the Rime tables (rime/rime-cangjie, rime/rime-wubi, LGPL-3.0).
# 無蝦米 is not free: its table is only used when you give your own copy (a .cin file, e.g. liu.cin / boshiamy.cin).
# Output: {"c": {字: "倉頡碼"}, "w": {字: "五筆碼"}, "l": {字: "無蝦米碼"}}; several codes are joined by " ".
import sys, re, json, collections

CJ_BASE, CJ_EXT, WUBI, OUT = sys.argv[1:5]
LIU = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] != "-" else None
CEDICT = sys.argv[6] if len(sys.argv) > 6 else None

def rime_table(path):
    """text -> codes, from a Rime .dict.yaml (after the "..." line)"""
    out = collections.OrderedDict()
    body = False
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not body:
            body = line.strip() == "..."
            continue
        if not line or line.startswith("#"): continue
        p = line.split("\t")
        if len(p) < 2 or len(p[0]) != 1: continue
        out.setdefault(p[0], [])
        if p[1] not in out[p[0]]: out[p[0]].append(p[1])
    return out

cj = rime_table(CJ_BASE)
for ch, cs in rime_table(CJ_EXT).items(): cj.setdefault(ch, cs)

# 五筆: a character's full code is its longest one (好: vb, vbg -> vbg)
wb_all = rime_table(WUBI)
wb = {ch: sorted(cs, key=lambda c: (-len(c), c))[:1] for ch, cs in wb_all.items()}
# a traditional character the 五筆 table doesn't have: the code of its simplified form (CC-CEDICT)
if CEDICT:
    for line in open(CEDICT, encoding="utf-8"):
        if line.startswith("#"): continue
        p = line.split(" ", 2)
        if len(p) >= 2 and len(p[0]) == 1 and len(p[1]) == 1 and p[0] not in wb and p[1] in wb:
            wb[p[0]] = wb[p[1]]

liu = {}
if LIU:
    body = False
    for line in open(LIU, encoding="utf-8", errors="ignore"):
        s = line.strip()
        if s.startswith("%chardef"):
            body = "begin" in s
            continue
        if not body or not s or s.startswith("#"): continue
        p = s.split()
        if len(p) >= 2 and len(p[1]) == 1:
            liu.setdefault(p[1], [])
            if p[0] not in liu[p[1]]: liu[p[1]].append(p[0])
    # the shortest code first (that's the one you type)
    liu = {ch: sorted(cs, key=lambda c: (len(c), c))[:2] for ch, cs in liu.items()}

out = {"c": {ch: " ".join(cs[:2]) for ch, cs in cj.items()},
       "w": {ch: " ".join(cs) for ch, cs in wb.items()}}
if liu: out["l"] = {ch: " ".join(cs) for ch, cs in liu.items()}
json.dump(out, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
print("倉頡", len(out["c"]), "五筆", len(out["w"]), "無蝦米", len(out.get("l", {})))
