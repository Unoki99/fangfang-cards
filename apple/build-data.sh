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
}
if [ "$ODS" = "yue" ]; then build_yue "$2"; echo "✓ 完成：FangfangCards/yue.json"; exit 0; fi
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
for u in expanded/tocfl.csv tocfl.csv expanded/tbcl.csv tbcl.csv; do
  curl -fsSL -o "$TMP/tocfl.csv" "https://raw.githubusercontent.com/ivankra/tocfl/master/$u" && break || rm -f "$TMP/tocfl.csv"
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
