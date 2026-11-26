# 維基詞典 (Wiktionary, as kaikki.org extracts it) for the tools that use its Chinese pages: build_tw_english.py
# (台語 words' English), build_sichuan.py (華語 words' 四川話 readings), build_cantonese.py (粵語 examples and 華語
# words). One page a line (JSON), from, in this order:
#   1. a file given: kaikki.org-dictionary-Chinese.jsonl as kaikki.org has it, or a .gz of it
#   2. this project's own copy, in common/ of its data repository on GitHub (unoki99/fangfang-data): the same pages with only what these tools read,
#      in pieces under 100 MB (wiktionary-zh-01.jsonl.gz, …, named in wiktionary-zh.txt). It's there so the app
#      still gets all this when kaikki.org's file is gone (it says it will be taken down)
#   3. kaikki.org's file, read straight from there (1.1 GB, not saved)
# With FANGFANG_WIKT_CACHE set (a file name), the copy downloaded in 2 is kept there, and read from there by the next
# tool of the same install, instead of downloading it again. FANGFANG_MIRROR: another place for that repository's files.
import gzip, io, os, sys, urllib.parse, urllib.request

MIRROR = os.environ.get("FANGFANG_MIRROR", "https://raw.githubusercontent.com/unoki99/fangfang-data/main").rstrip("/")
KAIKKI_URL = "https://kaikki.org/dictionary/Chinese/kaikki.org-dictionary-Chinese.jsonl"


def _text(raw):
    return io.TextIOWrapper(raw, encoding="utf-8-sig")


def _local(path):
    if path.endswith(".gz"):
        return _text(gzip.open(path, "rb"))
    return open(path, encoding="utf-8-sig")


def _get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "fangfang-cards"}), timeout=60)


def _mirror_parts():
    """the names of the copy's pieces, or None when it can't be reached"""
    try:
        with _get(MIRROR + "/common/wiktionary-zh.txt") as r:
            names = [x.strip() for x in r.read().decode("utf-8").splitlines() if x.strip() and not x.startswith("#")]
        return names or None
    except Exception:
        return None


def _download(names, dest):
    """the pieces, one after the other, into one .gz (gzip reads pieces put together as one)"""
    tmp = dest + ".part"
    with open(tmp, "wb") as out:
        for i, n in enumerate(names, 1):
            print(f"  維基詞典 {i}/{len(names)}…", file=sys.stderr)
            with _get(MIRROR + "/common/" + urllib.parse.quote(n)) as r:
                while True:
                    b = r.read(1 << 20)
                    if not b: break
                    out.write(b)
    os.replace(tmp, dest)


def _stream(names):
    for n in names:
        with _get(MIRROR + "/common/" + urllib.parse.quote(n)) as r:
            yield from _text(gzip.GzipFile(fileobj=r))


def lines(path=None):
    """every page, a line each (path: a file of them, or None / "-" for the copy, else kaikki.org)"""
    if path and path != "-":
        print(f"維基詞典 ← 這台電腦上的檔案（{path}）", file=sys.stderr)
        return _local(path)
    cache = os.environ.get("FANGFANG_WIKT_CACHE")
    if cache and os.path.exists(cache):
        print("維基詞典 ← 之前下載的副本（fangfang-data）", file=sys.stderr)
        return _local(cache)
    names = _mirror_parts()
    if names:
        print(f"維基詞典 ← fangfang-data（{MIRROR}/common/，{len(names)} 個檔案）", file=sys.stderr)
        if cache:
            try:
                _download(names, cache)
                return _local(cache)
            except Exception as e:
                print(f"（下載不完整：{e}）", file=sys.stderr)
        else:
            return _stream(names)
    print(f"維基詞典 ← kaikki.org（fangfang-data 沒有或下載不到：{KAIKKI_URL}）", file=sys.stderr)
    return _text(_get(KAIKKI_URL))
