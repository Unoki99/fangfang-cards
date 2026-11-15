#!/bin/bash
# 方方詞卡 查詞 for Firefox (on a computer, and on Android): the same add-on as Safari's, packed as one file,
# ~/Desktop/fangfang-firefox.xpi.
#
# Without any dictionary inside (the dictionaries' licenses don't allow sharing changed versions): it comes with
# the app's converters (FangfangCards/Install/*.js, put in install/), and its settings page (詞典) downloads the
# dictionaries' original files and makes the lookup files in the browser. So it can be shared, and listed on
# addons.mozilla.org for everyone.
#   bash tools/build_firefox.sh
#
# withdata: with the lookup files install.sh made on this Mac (d-*.json) inside it, nothing to install in Firefox;
# ~/Desktop/fangfang-firefox-private.xpi. Only for yourself (sign it "On your own", never listed): it has the
# dictionaries' data, made changed, inside it.
#   bash tools/build_firefox.sh withdata
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CODE="$HERE/FangfangSafari"
CONV="$HERE/FangfangCards/Install"
WITH=""
[ "$1" = "withdata" ] && WITH=1
DATA=""
if [ -n "$WITH" ]; then
  for d in "$HOME/FangfangCards/FangfangSafari" "$CODE"; do
    if [ -f "$d/d-meta.json" ]; then DATA="$d"; break; fi
  done
  if [ -z "$DATA" ]; then
    echo "還沒有查詞的資料：先執行一次 bash install.sh（不要加 nosafari）或 bash build-data.sh，再執行這個。"
    exit 1
  fi
fi
OUT="$HOME/Desktop/fangfang-firefox.xpi"
[ -n "$WITH" ] && OUT="$HOME/Desktop/fangfang-firefox-private.xpi"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# the add-on's own files (not the Safari-only ones, not data)
for f in "$CODE"/*; do
  case "$f" in *.swift|*.plist|*/d-*.json) continue;; esac
  [ -f "$f" ] && cp "$f" "$TMP/"
done
# the app's converters, for installing the dictionaries in the browser
mkdir -p "$TMP/install"
for f in common taigi mandarin cantonese hakka swedish; do cp "$CONV/$f.js" "$TMP/install/"; done
cp "$CONV/twown.json" "$TMP/install/"
[ -n "$WITH" ] && cp "$DATA"/d-*.json "$TMP/"
rm -f "$OUT"
(cd "$TMP" && zip -qr -X "$OUT" .)
echo "✓ $OUT（$(du -h "$OUT" | cut -f1)）"
echo
if [ -n "$WITH" ]; then
  echo "這個版本裡面有詞典的資料：只能給你自己用。在 addons.mozilla.org/developers 上傳時一定要選「On your own」（不公開）。"
else
  echo "這個版本裡面沒有詞典，可以公開："
  echo "1. 在 addons.mozilla.org/developers 登入。第一次按「Submit a New Add-on」；之後到「My Add-ons」打開方方詞卡 查詞，按「Upload New Version」（再按 Submit a New Add-on 會出現「Duplicate add-on ID」）。"
  echo "2. 選「On this site」（公開上架），上傳這個檔案。問要不要附原始碼（source code）的時候選「No」：裡面的程式都沒有壓縮或產生過。"
  echo "3. 審核通過以後，在 Firefox 的附加元件頁就找得到，大家都可以安裝；第一次打開會到設定頁的「詞典」選語言安裝。"
fi
