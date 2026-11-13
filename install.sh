#!/bin/bash
# 方方詞卡: installs the Apple version (iPhone / iPad / Mac) or makes the Android app, from one place.
#   bash ~/Downloads/fangfang-cards-main/install.sh            asks which one
#   bash ~/Downloads/fangfang-cards-main/install.sh apple      iPhone/iPad + Mac (same as apple/install.sh)
#   bash ~/Downloads/fangfang-cards-main/install.sh apple ios  only iPhone/iPad (anything after "apple" goes to apple/install.sh:
#                                                   ios, mac, ipad, catalyst, ipa)
#   bash ~/Downloads/fangfang-cards-main/install.sh android    the Android app (an APK on the Desktop; onto the phone if it's plugged in)
HERE="$(cd "$(dirname "$0")" && pwd)"
WHAT="$1"

if [ -z "$WHAT" ]; then
  echo "方方詞卡：要裝哪一個？"
  echo "  1) iPhone／iPad 和 Mac"
  echo "  2) 只有 iPhone／iPad"
  echo "  3) 只有 Mac"
  echo "  4) Android（做一個 APK 檔）"
  printf "打數字再按 Enter："
  read -r n
  case "$n" in
    1) WHAT=apple ;;
    2) WHAT=apple; set -- apple ios ;;
    3) WHAT=apple; set -- apple mac ;;
    4) WHAT=android ;;
    *) echo "沒有選，結束。"; exit 1 ;;
  esac
fi

case "$WHAT" in
  apple|ios|mac)
    # "install.sh ios" and the like also work
    [ "$WHAT" = "apple" ] && shift
    [ "$WHAT" != "apple" ] && set -- "$WHAT"
    exec bash "$HERE/apple/install.sh" "$@"
    ;;
  android) ;;
  *) echo "不知道「${WHAT}」是什麼。用 apple 或 android。"; exit 1 ;;
esac

# ---------- Android ----------
A="$HERE/android"
LOG="$HOME/Library/Logs/fangfang-android-build.log"
mkdir -p "$HOME/Library/Logs"

# the Android SDK and Java (both come with Android Studio)
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
if [ ! -d "$SDK" ]; then
  echo "✗ 找不到 Android SDK。請先安裝 Android Studio（https://developer.android.com/studio），"
  echo "  打開一次，讓它下載 SDK（照它的說明按下一步），再執行一次這個指令。"
  exit 1
fi
# Java 17–23 (the build tools don't run on newer Java, e.g. Java 25): Android Studio's own Java first
java_major() { "$1/bin/java" -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/'; }
ok_java() { [ -x "$1/bin/java" ] || return 1; local m; m=$(java_major "$1"); [ -n "$m" ] && [ "$m" -ge 17 ] && [ "$m" -le 23 ]; }
PICK=""
for j in "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
         "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
         "/Applications/Android Studio Preview.app/Contents/jbr/Contents/Home" \
         "/Applications/Android Studio.app/Contents/jre/Contents/Home" \
         "${JAVA_HOME:-}" \
         "$(/usr/libexec/java_home -v 21 2>/dev/null)" "$(/usr/libexec/java_home -v 17 2>/dev/null)"; do
  if [ -n "$j" ] && ok_java "$j"; then PICK="$j"; break; fi
done
# none (new Android Studio comes with Java 25, too new for the build tools): a Java 21 of our own, downloaded
# once from Eclipse Adoptium (free) into ~/Library/Application Support/FangfangCards/jdk21
if [ -z "$PICK" ]; then
  OWN="$HOME/Library/Application Support/FangfangCards/jdk21"
  find_own() { for d in "$OWN"/*/Contents/Home; do ok_java "$d" && { echo "$d"; return; }; done; }
  PICK="$(find_own)"
  if [ -z "$PICK" ]; then
    echo "Android Studio 的 Java 太新了（建置工具要 17–23 版），下載一個 Java 21 給方方詞卡用（只有第一次，大概 200 MB）…"
    ARCH=$( [ "$(uname -m)" = "arm64" ] && echo aarch64 || echo x64 )
    TGZ="$(mktemp -d)/jdk21.tar.gz"
    if curl -fL --progress-bar -o "$TGZ" "https://api.adoptium.net/v3/binary/latest/21/ga/mac/$ARCH/jdk/hotspot/normal/eclipse"; then
      rm -rf "$OWN"; mkdir -p "$OWN"
      tar -xzf "$TGZ" -C "$OWN" && rm -f "$TGZ"
      PICK="$(find_own)"
    else
      echo "（下載 Java 失敗）"
    fi
  fi
fi
if [ -z "$PICK" ]; then
  echo "✗ 找不到可以用的 Java（要 17–23 版；這台 Mac 的 Java 太新或沒有）。"
  echo "  請安裝 Android Studio（https://developer.android.com/studio，它裡面有對的 Java），放在「應用程式」資料夾，再執行一次。"
  exit 1
fi
export JAVA_HOME="$PICK" ANDROID_HOME="$SDK"
echo "（用的 Java：${JAVA_HOME}）"
echo "sdk.dir=$SDK" > "$A/local.properties"

# The dictionaries are made on this computer and put into the app (making the big ones on the phone ran out of
# memory). Their licences don't allow sharing the made files, so only this computer's own build has them. They're
# kept in ~/FangfangCards/data (the same place the Apple version keeps its data), so they're made only once.
ASSETS="$A/app/src/main/assets"
mkdir -p "$ASSETS"
APD="$HERE/apple/FangfangCards"
DATA="$HOME/FangfangCards/data"
mkdir -p "$DATA"
BD="$HERE/apple/build-data.sh"
FILES="dict.json cards.json zh.json inputcodes.json yue.json hak.json tw_en.json ja.json shuowen.json"
# (made before, somewhere else: taken over)
for f in $FILES; do
  for d in "$HOME/FangfangCards/FangfangCards" "$APD"; do
    [ ! -f "$DATA/$f" ] && [ -f "$d/$f" ] && cp "$d/$f" "$DATA/$f"
  done
done
# (粵語 made by an older version: made again)
[ -f "$DATA/yue.json" ] && ! head -c 80 "$DATA/yue.json" | grep -q '"v":2' && rm -f "$DATA/yue.json"
# build-data.sh makes its files in apple/FangfangCards: each is moved into $DATA when it's made
made() { for f in "$@"; do [ -f "$APD/$f" ] && mv -f "$APD/$f" "$DATA/$f"; done; return 0; }
if [ ! -f "$DATA/dict.json" ] || [ ! -f "$DATA/cards.json" ]; then
  echo "建立台語詞典…"
  bash "$BD" && made dict.json cards.json || echo "（沒辦法建立台語詞典，先跳過）"
fi
if [ ! -f "$DATA/zh.json" ]; then echo "建立華語詞典…"; bash "$BD" zh && made zh.json || echo "（沒辦法建立華語詞典，先跳過）"; fi
if [ ! -f "$DATA/inputcodes.json" ]; then bash "$BD" ime && made inputcodes.json || echo "（沒辦法建立輸入法拆碼，先跳過）"; fi
if [ ! -f "$DATA/yue.json" ]; then echo "建立粵語詞典…"; bash "$BD" yue && made yue.json || echo "（沒辦法建立粵語詞典，先跳過）"; fi
if [ ! -f "$DATA/hak.json" ]; then echo "建立客語詞典…"; bash "$BD" hak && made hak.json || echo "（沒辦法建立客語詞典，先跳過）"; fi
if [ ! -f "$DATA/tw_en.json" ] && [ -f "$DATA/dict.json" ]; then
  echo "建立台語詞的英文解釋…（要讀維基詞典，幾分鐘）"
  cp "$DATA/dict.json" "$APD/dict.json"
  bash "$BD" twen && made tw_en.json || echo "（沒辦法建立台語詞的英文解釋，先跳過）"
  rm -f "$APD/dict.json"
fi
# 日語 (JMdict, KANJIDIC2) and 說文解字: the app's own converters (Install/*.js) run by Node.js on this computer
# (a Node.js of our own is downloaded once when there's none)
if [ ! -f "$DATA/ja.json" ] || [ ! -f "$DATA/shuowen.json" ]; then
  NODE="$(command -v node || true)"
  OWNNODE="$HOME/Library/Application Support/FangfangCards/node"
  [ -z "$NODE" ] && NODE="$(ls "$OWNNODE"/*/bin/node 2>/dev/null | head -1)"
  if [ -z "$NODE" ]; then
    echo "下載 Node.js（整理日語和說文解字的資料用，只有第一次，大概 40 MB）…"
    NARCH=$( [ "$(uname -m)" = "arm64" ] && echo arm64 || echo x64 )
    NT="$(mktemp -d)/node.tar.gz"
    if curl -fL --progress-bar -o "$NT" "https://nodejs.org/dist/v22.11.0/node-v22.11.0-darwin-$NARCH.tar.gz"; then
      rm -rf "$OWNNODE"; mkdir -p "$OWNNODE"
      tar -xzf "$NT" -C "$OWNNODE" && rm -f "$NT"
      NODE="$(ls "$OWNNODE"/*/bin/node 2>/dev/null | head -1)"
    fi
  fi
  if [ -z "$NODE" ]; then
    echo "（沒有 Node.js：日語和說文解字先不放進 App）"
  else
    JT="$(mktemp -d)"
    if [ ! -f "$DATA/ja.json" ]; then
      echo "下載日語資料（JMdict、KANJIDIC2）…"
      if curl -fL --progress-bar -o "$JT/JMdict_e_examp.gz" "http://ftp.edrdg.org/pub/Nihongo/JMdict_e_examp.gz"; then
        KD="$JT/kanjidic2.xml.gz"
        curl -fsSL -o "$KD" "http://ftp.edrdg.org/pub/Nihongo/kanjidic2.xml.gz" || KD="-"
        echo "整理日語資料中…（幾分鐘）"
        "$NODE" --max-old-space-size=6144 "$HERE/apple/tools/convert.js" japanese "$JT/JMdict_e_examp.gz" "$KD" "$DATA/ja.json" > "$JT/log" 2>&1 \
          || { tail -8 "$JT/log"; rm -f "$DATA/ja.json"; echo "（沒辦法建立日語資料，先跳過）"; }
      else
        echo "（下載不到日語資料，先跳過）"
      fi
    fi
    if [ ! -f "$DATA/shuowen.json" ]; then
      echo "下載《說文解字注》（cjkvi-dict）…"
      if curl -fsSL -o "$JT/swjz.xml" "https://raw.githubusercontent.com/cjkvi/cjkvi-dict/master/swjz.xml"; then
        "$NODE" --max-old-space-size=4096 "$HERE/apple/tools/convert.js" shuowen "$JT/swjz.xml" "$DATA/shuowen.json" > "$JT/log" 2>&1 \
          || { tail -8 "$JT/log"; rm -f "$DATA/shuowen.json"; echo "（沒辦法建立說文解字，先跳過）"; }
      else
        echo "（下載不到說文解字，先跳過）"
      fi
    fi
    rm -rf "$JT"
  fi
fi
# into the app (and what the Android version doesn't use out)
for f in $FILES; do
  if [ -f "$DATA/$f" ]; then cp "$DATA/$f" "$ASSETS/$f"; else rm -f "$ASSETS/$f"; fi
done
# 日語: made smaller for Android (all of JMdict doesn't fit in the memory Android gives an app)
if [ -f "$ASSETS/ja.json" ]; then
  [ -z "${NODE:-}" ] && NODE="$(command -v node || ls "$HOME/Library/Application Support/FangfangCards/node"/*/bin/node 2>/dev/null | head -1 || true)"
  if [ -n "${NODE:-}" ] && "$NODE" "$HERE/apple/tools/android_ja.js" "$ASSETS/ja.json" "$ASSETS/ja.small.json"; then
    mv -f "$ASSETS/ja.small.json" "$ASSETS/ja.json"
  else
    rm -f "$ASSETS/ja.json" "$ASSETS/ja.small.json"
    echo "（沒辦法把日語詞典變小：先不放進 Android App）"
  fi
fi
rm -f "$ASSETS/zh_sc.json" "$ASSETS/sv.json"
for f in dict.json cards.json zh.json; do
  [ -f "$ASSETS/$f" ] || { echo "✗ 詞典資料沒有建好（少了 $f）。把上面的訊息傳給 Claude。"; exit 1; }
done

# copies of source files left by putting a new download over the old folder ("Dict 2.kt"): the same code twice
find "$A/app/src" -type f \( -name "* 2.kt" -o -name "* - Copy.kt" -o -name "* (1).kt" \) -print -delete 2>/dev/null | sed 's/^/（刪掉多出來的複本：/; s/$/）/'
echo "建置 Android 版…（第一次要下載不少東西，可能 5–10 分鐘）"
(cd "$A" && bash ./gradlew assembleDebug --console=plain) > "$LOG" 2>&1 < /dev/null
APK="$A/app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APK" ] || ! grep -q "BUILD SUCCESSFUL" "$LOG"; then
  echo "✗ 建置失敗。把下面的錯誤訊息傳給 Claude："
  grep -E "^e: |error:|What went wrong" -A4 "${LOG}" | head -40
  echo "（完整紀錄：${LOG}）"
  exit 1
fi
OUT="$HOME/Desktop/FangfangCards.apk"
cp "$APK" "$OUT"
echo "✓ 建置完成：${OUT}"

# straight onto a phone that's plugged in with USB debugging on
ADB="$SDK/platform-tools/adb"
if [ -x "$ADB" ] && "$ADB" devices | awk 'NR>1 && $2=="device"' | grep -q .; then
  echo "安裝到接著的 Android 手機…"
  if "$ADB" install -r "$OUT" >> "$LOG" 2>&1; then echo "✓ 已安裝到手機"; else echo "（沒辦法直接安裝；把 APK 傳到手機上點它安裝就好）"; fi
else
  echo "把 FangfangCards.apk 傳到 Android 手機（email、Google Drive、聊天軟體…），在手機上點它安裝。"
  echo "（或是用 USB 線接上手機、打開「USB 偵錯」，再執行一次這個指令，就會直接裝上去。）"
fi
