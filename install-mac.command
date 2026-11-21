#!/bin/bash
# 方方詞卡: the Windows program, on a Mac (the same program, made into a Mac app). Double-click this file (the first
# time: right-click → 打開), or in Terminal:
#   bash ~/Downloads/fangfang-cards-main/install-mac.command
# It gets what's needed to build it once (Java 21, Node.js for making the dictionaries, FFmpeg for the radio) into
# ~/Library/Application Support/FangfangCards, builds the program, and puts 方方詞卡（電腦版）.app in Applications.
# (The iPad app on the Mac is install.sh's; this one is the computer program, the same as on Windows. Both can be
# installed: they keep their things apart.)
cd "$(dirname "$0")" || exit 1
HERE="$(pwd -P)"
BASE="$HOME/Library/Application Support/FangfangCards"
LOG="$BASE/mac-build.log"
mkdir -p "$BASE"
ARCH=$(uname -m)                      # arm64 (Apple chip) or x86_64 (Intel)
fail() { echo "✗ $1"; echo; read -r -p "按 Enter 關閉…" _; exit 1; }
say_done() { echo; read -r -p "按 Enter 關閉…" _; }

[ -f "$HERE/windows/build.gradle.kts" ] || fail "找不到 windows 資料夾。請用完整的 fangfang-cards-main 資料夾。"
# (copies left by putting a new download over an older one: "Store 2.kt", the same code twice)
find "$HERE/windows" "$HERE/android/app/src" -type f \( -name "* [0-9].kt" -o -name "* copy.kt" -o -name "* ([0-9]).kt" \) -print -delete 2>/dev/null \
  | sed 's/^/（刪掉多出來的複本：/; s/$/）/'

# ---- Java 17–23 with jmods (the program takes a copy of Java along): one already here, else Java 21 of our own ----
java_ok() {   # $1 = a Java home
  [ -x "$1/bin/java" ] && [ -d "$1/jmods" ] || return 1
  local v
  v=$("$1/bin/java" -version 2>&1 | head -1 | sed -E 's/.*version "(1\.)?([0-9]+).*/\2/')
  [ "$v" -ge 17 ] 2>/dev/null && [ "$v" -le 23 ]
}
JH=""
for c in "$JAVA_HOME" "$(/usr/libexec/java_home -v 21 2>/dev/null)" "$(/usr/libexec/java_home -v 17 2>/dev/null)"; do
  if [ -n "$c" ] && java_ok "$c"; then JH="$c"; break; fi
done
if [ -z "$JH" ]; then
  OWN="$BASE/jdk21"
  JH=$(ls -d "$OWN"/*/Contents/Home 2>/dev/null | head -1)
  if [ -z "$JH" ] || ! java_ok "$JH"; then
    echo "下載 Java 21（Eclipse Temurin，只有第一次，大概 190 MB）…"
    JA="aarch64"; [ "$ARCH" = "x86_64" ] && JA="x64"
    rm -rf "$OWN"; mkdir -p "$OWN"
    curl -fL --progress-bar -o "$BASE/jdk.tar.gz" "https://api.adoptium.net/v3/binary/latest/21/ga/mac/$JA/jdk/hotspot/normal/eclipse" \
      || fail "下載不到 Java。請檢查網路，再執行一次。"
    tar -xzf "$BASE/jdk.tar.gz" -C "$OWN" || fail "Java 解壓縮失敗。"
    rm -f "$BASE/jdk.tar.gz"
    JH=$(ls -d "$OWN"/*/Contents/Home 2>/dev/null | head -1)
    java_ok "$JH" || fail "下載的 Java 不能用（${JH}）。"
  fi
fi
export JAVA_HOME="$JH"
echo "（用的 Java：${JAVA_HOME}）"

# ---- Node.js: the program makes the dictionaries with it (設定 → 詞典資料), the same converters as the apps' ----
if ! command -v node >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/node ] && [ ! -x /usr/local/bin/node ] \
   && ! ls "$BASE"/node/*/bin/node >/dev/null 2>&1; then
  echo "下載 Node.js（整理詞典用，只有第一次，大概 45 MB）…"
  NA="arm64"; [ "$ARCH" = "x86_64" ] && NA="x64"
  mkdir -p "$BASE/node"
  if curl -fL --progress-bar -o "$BASE/node.tar.gz" "https://nodejs.org/dist/v22.11.0/node-v22.11.0-darwin-$NA.tar.gz"; then
    tar -xzf "$BASE/node.tar.gz" -C "$BASE/node" && echo "✓ Node.js 好了。"
    rm -f "$BASE/node.tar.gz"
  else
    echo "（下載 Node.js 失敗：詞典要等下次執行這個檔案才能在程式裡安裝）"
  fi
fi

# ---- FFmpeg: the radio plays every kind of stream with it; without it mp3 and AAC stations still play ----
if ! command -v ffmpeg >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/ffmpeg ] && [ ! -x /usr/local/bin/ffmpeg ] \
   && [ ! -x "$BASE/ffmpeg/ffmpeg" ]; then
  echo "下載 FFmpeg（電台播各種格式用，只有第一次，大概 30 MB）…"
  FA="arm64"; [ "$ARCH" = "x86_64" ] && FA="x64"
  mkdir -p "$BASE/ffmpeg"
  if curl -fL --progress-bar -o "$BASE/ffmpeg/ffmpeg.gz" "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0/ffmpeg-darwin-$FA.gz"; then
    gunzip -f "$BASE/ffmpeg/ffmpeg.gz" && chmod +x "$BASE/ffmpeg/ffmpeg" && xattr -c "$BASE/ffmpeg/ffmpeg" 2>/dev/null
    [ -x "$BASE/ffmpeg/ffmpeg" ] && echo "✓ FFmpeg 好了。"
  else
    rm -f "$BASE/ffmpeg/ffmpeg.gz"
    echo "（沒有 FFmpeg：mp3 和 AAC 電台照樣能播，HLS 等其他格式可能播不了。下次執行會再試。）"
  fi
fi

# ---- 四川話 for 華語 (zh_sc.json, from Wiktionary): made from the 華語 dictionary once it's there (installed in the
# program, or made by install.sh); without Python 3 or the 華語 dictionary, next time ----
if [ ! -f "$BASE/data/zh_sc.json" ] && [ ! -f "$HOME/FangfangCards/data/zh_sc.json" ] && command -v python3 >/dev/null 2>&1; then
  ZJ=""
  for c in "$BASE/app/Dictionaries/zh.json" "$BASE/data/zh.json" "$HOME/FangfangCards/data/zh.json"; do [ -f "$c" ] && { ZJ="$c"; break; }; done
  if [ -n "$ZJ" ]; then
    echo "整理四川話的讀音（維基詞典，只有第一次，幾分鐘）…"
    mkdir -p "$BASE/data"
    SCT=$(mktemp -d)
    if (cd "$HERE/apple/tools" && FANGFANG_WIKT_CACHE="$SCT/wiktionary-zh.jsonl.gz" python3 build_sichuan.py "$ZJ" "$BASE/data/zh_sc.json" -) > "$SCT/py.log" 2>&1; then
      echo "✓ 四川話的讀音好了。"
    else
      rm -f "$BASE/data/zh_sc.json"; tail -5 "$SCT/py.log"; echo "（四川話的讀音沒做成：華語照常能用，下次執行會再試）"
    fi
    rm -rf "$SCT"
  else
    echo "（四川話：先在程式裡安裝華語的詞典，再執行一次這個檔案，就會有四川話的讀音）"
  fi
fi

# ---- build ----
# (built in a copy of the project here, not where it was downloaded: a folder on the Desktop or in Documents that
# iCloud keeps gives the files extra Finder information, and the Mac then won't sign the app: "codesign … exited with 1")
SRC="$BASE/src"
mkdir -p "$SRC"
rsync -a --delete --exclude ".gradle" --exclude "build" --exclude ".DS_Store" --exclude "local.properties" \
      "$HERE/android" "$HERE/windows" "$SRC/" || fail "沒辦法複製專案到 ${SRC}。"
xattr -cr "$SRC" 2>/dev/null
echo "建置 Mac 版…（第一次要下載不少東西，可能 5–10 分鐘）"
chmod +x "$SRC/android/gradlew" 2>/dev/null
ok=0
for try in 1 2 3; do
  (cd "$SRC/android" && ./gradlew -p "$SRC/windows" createDistributable --console=plain) > "$LOG" 2>&1 < /dev/null && { ok=1; break; }
  # (tried again only when a download timed out or the connection dropped)
  grep -q -E "timed out|Connection reset|Could not GET|Could not download|Read timed out" "$LOG" || break
  echo "（網路不穩，再試一次…）"; sleep $((try * 15))
done
BUILT=$(ls -d "$SRC"/windows/build/compose/binaries/main/app/*.app 2>/dev/null | head -1)
if [ "$ok" != 1 ] || [ -z "$BUILT" ]; then
  echo "✗ 建置失敗。把下面的錯誤訊息傳給 Claude（或直接傳這個檔案：${LOG}）："
  ERRS=$(grep -E "^e: " "$LOG" | sed -E 's#^e: file://.*/fangfang-cards-main/##; s#/app/src/main/java/com/unoki99/fangfang/#/…/#' | sort -u | head -80)
  if [ -n "$ERRS" ]; then echo "$ERRS"; else grep -E -A6 "What went wrong|error:|Could not" "$LOG" | head -60; fi
  # (jpackage's own reasons, when it was the one that failed)
  for f in "$SRC"/windows/build/compose/logs/createDistributable/*-err.txt; do [ -s "$f" ] && tail -15 "$f"; done
  say_done; exit 1
fi

# ---- into Applications (closed first, when it's open) ----
osascript -e 'tell application id "com.unoki99.fangfangcards.desktop" to quit' >/dev/null 2>&1
sleep 1
TARGET="/Applications"
[ -w "$TARGET" ] || { TARGET="$HOME/Applications"; mkdir -p "$TARGET"; }
APP="$TARGET/方方詞卡（電腦版）.app"
rm -rf "$APP"
cp -R "$BUILT" "$APP" || fail "沒辦法放進 ${TARGET}。"
# (made on this Mac, so nothing to allow; signed for this Mac only, which an Apple-chip Mac wants)
xattr -cr "$APP" 2>/dev/null
codesign --force --deep -s - "$APP" >/dev/null 2>&1
# fangfangcards:// links (the Firefox add-on's 傳到 App) open it
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1
echo "✓ 方方詞卡 Mac 版（電腦版）裝好了：$APP"
echo "  （進度和設定在 $BASE/app。詞典第一次打開時在程式裡選語言安裝；"
echo "   這台 Mac 用 install.sh 做過的詞典（~/FangfangCards/data）也會直接用。）"
open "$APP"
say_done
