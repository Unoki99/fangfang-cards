#!/bin/bash
# 方方詞卡: builds the app's word data (FangfangCards/dict.json and cards.json) from the
# Ministry of Education's 臺灣台語常用詞辭典 file (kautian.ods). The data isn't stored in this
# repository: the dictionary's license (CC BY-ND 3.0 TW) doesn't allow sharing changed versions,
# so everyone builds their own copy from the original file.
#   bash build-data.sh                 (downloads kautian.ods from the MOE website)
#   bash build-data.sh ~/Downloads/kautian.ods
#   bash build-data.sh zh              (only the 華語 data, FangfangCards/zh.json)
#   bash build-data.sh ime             (only the input method codes, FangfangCards/inputcodes.json)
#   bash build-data.sh yue             (only the 粵語 data, FangfangCards/yue.json)
#   bash build-data.sh yue ~/Downloads/kaikki.org-dictionary-Chinese.jsonl   (with that Wiktionary file)
#   bash build-data.sh hak             (only the 客語 data, FangfangCards/hak.json)
#   bash build-data.sh twen            (only the 台語 words' English from Wiktionary, FangfangCards/tw_en.json)
#   bash build-data.sh sc              (only the 華語 words' 四川話 readings from Wiktionary, FangfangCards/zh_sc.json)
#   bash build-data.sh safari          (only the words inside the Safari extension, FangfangSafari/d-*.json)
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ODS="$1"
ONLY_ZH=""
[ "$ODS" = "zh" ] && { ONLY_ZH=1; ODS=""; }
# 輸入法拆碼: 倉頡 and 五筆 from Rime (LGPL-3.0); 無蝦米 only from your own table (tools/*.cin)
build_ime() {
  echo "下載倉頡、五筆碼表（Rime）…"
  curl -fsSL -o "$TMP/cj.yaml" "https://raw.githubusercontent.com/rime/rime-cangjie/master/cangjie5.base.dict.yaml"
  curl -fsSL -o "$TMP/cjx.yaml" "https://raw.githubusercontent.com/rime/rime-cangjie/master/cangjie5.extended.dict.yaml"
  curl -fsSL -o "$TMP/wb.yaml" "https://raw.githubusercontent.com/rime/rime-wubi/master/wubi86.dict.yaml"
  [ -f "$TMP/cedict_ts.u8" ] || curl -fsSL -o "$TMP/cedict_ts.u8" "https://raw.githubusercontent.com/cschiller/zhongwen/main/data/cedict_ts.u8" || true
  LIU=$(ls "$HERE"/tools/*.cin 2>/dev/null | head -1)
  /usr/bin/env python3 "$HERE/tools/build_inputcodes.py" "$TMP/cj.yaml" "$TMP/cjx.yaml" "$TMP/wb.yaml" "$HERE/FangfangCards/inputcodes.json" \
    "${LIU:--}" $([ -f "$TMP/cedict_ts.u8" ] && echo "$TMP/cedict_ts.u8") > /dev/null
}
if [ "$ODS" = "ime" ]; then build_ime; echo "✓ 完成：FangfangCards/inputcodes.json"; exit 0; fi
# 粵語: CC-CEDICT + CC-Canto (CC BY-SA), rime-cantonese (CC BY), 開放粵語字典 (CC BY), and Wiktionary's Chinese
# entries as extracted by kaikki.org (CC BY-SA): meanings, example sentences, the 華語 words, recordings
build_yue() {
  D="$TMP/yue"; mkdir -p "$D"
  G="https://raw.githubusercontent.com"
  echo "下載粵語資料（CC-CEDICT、CC-Canto、rime-cantonese、開放粵語字典）…"
  curl -fsSL -o "$D/cedict_ts.u8" "$G/cschiller/zhongwen/main/data/cedict_ts.u8"
  curl -fsSL -o "$D/CC-CANTO.txt" "$G/aaronhktan/jyut-dict/main/src/dictionaries/cedict/data/CC-CANTO.txt"
  curl -fsSL -o "$D/READINGS.txt" "$G/aaronhktan/jyut-dict/main/src/dictionaries/cedict/data/READINGS.txt"
  for f in jyut6ping3.words.dict.yaml jyut6ping3.chars.dict.yaml essay-cantonese.txt; do
    curl -fsSL -o "$D/$f" "$G/rime/rime-cantonese/main/$f"
  done
  curl -fsSL -o "$D/yyzd.txt" "$G/kfcd/yyzd/master/dist/tsv/%E7%B9%81%E9%AB%94/%E7%B2%B5%E8%AA%9E%E5%AD%97%E5%85%B8_%28%E7%B2%B5%E6%8B%BC%29.txt"
  # Wiktionary (kaikki.org): the file given, or one in Downloads / on the Desktop, or downloaded (large)
  K="${1:-}"
  for c in "$HOME/Downloads/kaikki.org-dictionary-Chinese.jsonl" "$HOME/Desktop/kaikki.org-dictionary-Chinese.jsonl"; do
    [ -z "$K" ] && [ -f "$c" ] && K="$c"
  done
  if [ -z "$K" ]; then
    echo "下載維基詞典的中文資料（kaikki.org，檔案很大，要等一下）…"
    if curl -fL --progress-bar -o "$D/kaikki.jsonl" "https://kaikki.org/dictionary/Chinese/kaikki.org-dictionary-Chinese.jsonl"; then
      K="$D/kaikki.jsonl"
    else
      echo "（下載不到維基詞典的資料，先不用：沒有例句和華語對照）"; K="-"
    fi
  fi
  echo "整理粵語資料中…（大概一兩分鐘）"
  /usr/bin/env python3 "$HERE/tools/build_cantonese.py" "$D" "$HERE/FangfangCards/yue.json" "$K"
  # (the same Wiktionary file: the 台語 words' English too)
  if [ "$K" != "-" ] && [ -f "$HERE/FangfangCards/dict.json" ]; then
    echo "整理台語詞的英文解釋（維基詞典）…"
    /usr/bin/env python3 "$HERE/tools/build_tw_english.py" "$HERE/FangfangCards/dict.json" "$HERE/FangfangCards/tw_en.json" "$K" || true
  fi
  # (and the 華語 words' 四川話 readings)
  if [ "$K" != "-" ] && [ -f "$HERE/FangfangCards/zh.json" ]; then
    echo "整理華語詞的四川話讀音（維基詞典）…"
    /usr/bin/env python3 "$HERE/tools/build_sichuan.py" "$HERE/FangfangCards/zh.json" "$HERE/FangfangCards/zh_sc.json" "$K" || true
  fi
}
# 台語: English for the 教育部 dictionary's words, from Wiktionary (a file of its own; dict.json isn't changed)
build_twen() {
  [ -f "$HERE/FangfangCards/dict.json" ] || { echo "✗ 先要有台語詞典資料（dict.json）。"; return 1; }
  K="${1:-}"
  for c in "$HOME/Downloads/kaikki.org-dictionary-Chinese.jsonl" "$HOME/Desktop/kaikki.org-dictionary-Chinese.jsonl"; do
    [ -z "$K" ] && [ -f "$c" ] && K="$c"
  done
  if [ -z "$K" ]; then echo "從 kaikki.org 讀維基詞典的中文資料（檔案很大，要等一陣子；不會存到電腦裡）…"; K="-"; fi
  echo "整理台語詞的英文解釋（維基詞典）…"
  /usr/bin/env python3 "$HERE/tools/build_tw_english.py" "$HERE/FangfangCards/dict.json" "$HERE/FangfangCards/tw_en.json" "$K"
}
if [ "$ODS" = "twen" ]; then build_twen "$2"; echo "✓ 完成：FangfangCards/tw_en.json"; exit 0; fi
# 華語 → 四川話: the 四川話 (成都) readings of the 華語 dictionary's words, from Wiktionary (a file of its own)
build_sc() {
  [ -f "$HERE/FangfangCards/zh.json" ] || { echo "✗ 先要有華語詞典資料（zh.json）。"; return 1; }
  K="${1:-}"
  for c in "$HOME/Downloads/kaikki.org-dictionary-Chinese.jsonl" "$HOME/Desktop/kaikki.org-dictionary-Chinese.jsonl"; do
    [ -z "$K" ] && [ -f "$c" ] && K="$c"
  done
  if [ -z "$K" ]; then echo "從 kaikki.org 讀維基詞典的中文資料（檔案很大，要等一陣子；不會存到電腦裡）…"; K="-"; fi
  echo "整理華語詞的四川話讀音（維基詞典）…"
  /usr/bin/env python3 "$HERE/tools/build_sichuan.py" "$HERE/FangfangCards/zh.json" "$HERE/FangfangCards/zh_sc.json" "$K"
}
if [ "$ODS" = "sc" ]; then build_sc "$2"; echo "✓ 完成：FangfangCards/zh_sc.json"; exit 0; fi
if [ "$ODS" = "safari" ]; then
  /usr/bin/env python3 "$HERE/tools/build_safari.py" "$HERE/FangfangCards/" "$HERE/FangfangSafari/" && echo "✓ 完成：FangfangSafari/d-*.json"
  exit 0
fi
if [ "$ODS" = "yue" ]; then build_yue "$2"; echo "✓ 完成：FangfangCards/yue.json"; exit 0; fi
# 客語: 教育部《臺灣客語辭典》, one file per accent (CC BY-ND 3.0 TW, like the 台語 dictionary: built here, not shared)
build_hak() {
  D="$TMP/hak"; mkdir -p "$D"
  echo "下載教育部《臺灣客語辭典》資料（四縣、海陸、大埔、饒平、詔安、南四縣）…"
  B="https://hakkadict.moe.edu.tw/static/resource/%E5%AE%A2%E8%AA%9E%E8%B3%87%E6%BA%90%E4%B8%8B%E8%BC%89/%E6%9C%AC%E8%BE%AD%E5%85%B8%E7%9A%84%E6%96%87%E5%AD%97"
  for a in 四縣 海陸 大埔 饒平 詔安 南四縣; do
    # (the file name, percent-encoded: …腔詞條詞目文字.ods)
    U=$(/usr/bin/env python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1] + "腔詞條詞目文字.ods"))' "$a")
    curl -fsSL -o "$D/${a}腔詞條詞目文字.ods" "$B/$U" || { [ "$a" = "四縣" ] && { echo "✗ 下載不到四縣腔的資料。"; return 1; }; echo "  （下載不到${a}腔，先跳過）"; }
  done
  [ -f "$TMP/essay.txt" ] || curl -fsSL -o "$TMP/essay.txt" "https://raw.githubusercontent.com/rime/rime-essay/master/essay.txt" || true
  [ -f "$TMP/cedict_ts.u8" ] || curl -fsSL -o "$TMP/cedict_ts.u8" "https://raw.githubusercontent.com/cschiller/zhongwen/main/data/cedict_ts.u8" || true
  echo "整理客語資料中…"
  /usr/bin/env python3 "$HERE/tools/build_hakka.py" "$D" "$HERE/FangfangCards/hak.json" \
    "$([ -f "$TMP/essay.txt" ] && echo "$TMP/essay.txt" || echo -)" "$([ -f "$TMP/cedict_ts.u8" ] && echo "$TMP/cedict_ts.u8" || echo -)" > /dev/null
}
if [ "$ODS" = "hak" ]; then build_hak; echo "✓ 完成：FangfangCards/hak.json"; exit 0; fi
if [ -n "$ONLY_ZH" ]; then :; elif [ -z "$ODS" ]; then
  ODS="$TMP/kautian.ods"
  echo "下載教育部《臺灣台語常用詞辭典》資料（kautian.ods）…"
  curl -fL --progress-bar -o "$ODS" "https://sutian.moe.edu.tw/media/senn/ods/kautian.ods"
fi
[ -n "$ONLY_ZH" ] || [ -f "$ODS" ] || { echo "✗ 找不到 $ODS"; exit 1; }
echo "下載 rime-essay 字頻表…"
curl -fsSL -o "$TMP/essay.txt" "https://raw.githubusercontent.com/rime/rime-essay/master/essay.txt"
cd "$HERE/tools"
if [ -z "$ONLY_ZH" ]; then
echo "整理資料中…（大概 1 分鐘）"
/usr/bin/env python3 ods2csv.py "$ODS" "$TMP/sheets.json" > /dev/null
/usr/bin/env python3 build_moe.py "$TMP/sheets.json" own.json "$TMP/data2.json" > /dev/null
/usr/bin/env python3 to_app_data.py "$TMP/data2.json" "$TMP/essay.txt" "$HERE/FangfangCards/dict.json" > /dev/null
/usr/bin/env python3 build_cards.py "$HERE/FangfangCards/dict.json" "$TMP/essay.txt" "$HERE/FangfangCards/cards.json" > /dev/null
fi
# 華語: 中華文化總會《兩岸常用詞典》 (CC BY-NC-ND), as prepared by the g0v 萌典 project
echo "下載《兩岸常用詞典》（萌典整理的資料）…"
curl -fL --progress-bar -o "$TMP/dict-csld.json" "https://raw.githubusercontent.com/g0v/moedict-data-csld/master/dict-csld.json"
echo "下載 CC-CEDICT（英文解釋）…"
curl -fsSL -o "$TMP/cedict_ts.u8" "https://raw.githubusercontent.com/cschiller/zhongwen/main/data/cedict_ts.u8" || rm -f "$TMP/cedict_ts.u8"
echo "下載 HSK 3.0 詞表…"
curl -fsSL -o "$TMP/hsk30.csv" "https://raw.githubusercontent.com/ivankra/hsk30/master/hsk30-expanded.csv" || rm -f "$TMP/hsk30.csv"
echo "下載 TOCFL 詞表…"
# (the list has moved before: try each place it has been)
# (a file there can be a link to another one, e.g. expanded/tocfl.csv → tocfl-202307.csv: GitHub then gives the
# name of the file it points to, which is followed)
for u in expanded/tocfl.csv tocfl.csv expanded/tbcl.csv tbcl.csv; do
  curl -fsSL -o "$TMP/tocfl.csv" "https://raw.githubusercontent.com/ivankra/tocfl/master/$u" || { rm -f "$TMP/tocfl.csv"; continue; }
  if [ "$(wc -c < "$TMP/tocfl.csv")" -lt 300 ] && grep -qE '^[A-Za-z0-9_./-]+\.csv$' "$TMP/tocfl.csv"; then
    T="$(tr -d '\r\n' < "$TMP/tocfl.csv")"; D="$(dirname "$u")"; [ "$D" = "." ] && D="" || D="$D/"
    curl -fsSL -o "$TMP/tocfl.csv" "https://raw.githubusercontent.com/ivankra/tocfl/master/$D$T" || { rm -f "$TMP/tocfl.csv"; continue; }
  fi
  break
done
[ -f "$TMP/tocfl.csv" ] || echo "  ⚠ 下載不到 TOCFL 詞表：華語的 TOCFL 只會有漢字卡，沒有詞的等級。"
echo "下載《重編國語辭典修訂本》（漢字卡的字義）和漢字表…"
curl -fL --progress-bar -o "$TMP/dict-revised.json.xz" "https://raw.githubusercontent.com/g0v/moedict-data/master/dict-revised.json.xz" || rm -f "$TMP/dict-revised.json.xz"
curl -fsSL -o "$TMP/hsk30-chars.csv" "https://raw.githubusercontent.com/ivankra/hsk30/master/hsk30-chars.csv" || rm -f "$TMP/hsk30-chars.csv"
curl -fsSL -o "$TMP/tbcl-chars.csv" "https://raw.githubusercontent.com/ivankra/tocfl/master/tbcl-chars.csv" || rm -f "$TMP/tbcl-chars.csv"
# what each character is made of (部首組合: finding a character by several radicals)
curl -fsSL -o "$TMP/ids.txt" "https://raw.githubusercontent.com/cjkvi/cjkvi-ids/master/ids.txt" || rm -f "$TMP/ids.txt"
echo "整理華語資料中…（大概一分鐘）"
/usr/bin/env python3 build_mandarin.py "$TMP/dict-csld.json" "$TMP/essay.txt" "$HERE/FangfangCards/zh.json" \
  "$([ -f "$TMP/cedict_ts.u8" ] && echo "$TMP/cedict_ts.u8" || echo -)" \
  "$([ -f "$TMP/hsk30.csv" ] && echo "$TMP/hsk30.csv" || echo -)" \
  "$([ -f "$TMP/tocfl.csv" ] && echo "$TMP/tocfl.csv" || echo -)" \
  "$([ -f "$TMP/dict-revised.json.xz" ] && echo "$TMP/dict-revised.json.xz" || echo -)" \
  "$([ -f "$TMP/hsk30-chars.csv" ] && echo "$TMP/hsk30-chars.csv" || echo -)" \
  "$([ -f "$TMP/tbcl-chars.csv" ] && echo "$TMP/tbcl-chars.csv" || echo -)" \
  "$([ -f "$TMP/ids.txt" ] && echo "$TMP/ids.txt" || echo -)" > /dev/null
build_ime
if [ -n "$ONLY_ZH" ]; then echo "✓ 完成：FangfangCards/zh.json、FangfangCards/inputcodes.json"; exit 0; fi
echo "✓ 完成：FangfangCards/dict.json、FangfangCards/cards.json、FangfangCards/zh.json"
