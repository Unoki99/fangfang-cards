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

# The dictionaries aren't in the app: it downloads and makes each language's dictionary itself (設定 → 詞典資料).
# The one data file put in is Wiktionary's English for the 台語 words (tw_en.json, CC BY-SA), which 台語's English
# search uses: the phone can't make it (it would need Wiktionary's whole 2.5 GB Chinese file), so it's made on this
# computer (once; kept in ~/FangfangCards/data, the same place the Apple version keeps its data).
ASSETS="$A/app/src/main/assets"
mkdir -p "$ASSETS"
APD="$HERE/apple/FangfangCards"
DATA="$HOME/FangfangCards/data"
mkdir -p "$DATA"
# (dictionaries put in the app by an older version: taken out)
for f in dict.json cards.json zh.json inputcodes.json yue.json hak.json ja.json shuowen.json zh_sc.json; do rm -f "$ASSETS/$f"; done
TWEN=""
for d in "$DATA" "$HOME/FangfangCards/FangfangCards" "$APD"; do
  if [ -f "$d/tw_en.json" ]; then TWEN="$d/tw_en.json"; break; fi
done
if [ -z "$TWEN" ]; then
  echo "建立台語詞的英文解釋…（第一次要下載台語詞典和維基詞典，幾分鐘）"
  for d in "$DATA" "$HOME/FangfangCards/FangfangCards"; do
    for f in dict.json cards.json; do [ ! -f "$APD/$f" ] && [ -f "$d/$f" ] && cp "$d/$f" "$APD/$f"; done
  done
  if [ ! -f "$APD/dict.json" ]; then bash "$HERE/apple/build-data.sh" || echo "（沒辦法建立台語詞典，先跳過）"; fi
  if [ -f "$APD/dict.json" ]; then bash "$HERE/apple/build-data.sh" twen || echo "（沒辦法建立台語詞的英文解釋，先跳過）"; fi
  for f in dict.json cards.json tw_en.json; do [ -f "$APD/$f" ] && mv -f "$APD/$f" "$DATA/$f"; done
  [ -f "$DATA/tw_en.json" ] && TWEN="$DATA/tw_en.json"
fi
if [ -n "$TWEN" ]; then
  cp "$TWEN" "$ASSETS/tw_en.json"
else
  rm -f "$ASSETS/tw_en.json"
  echo "（App 裡沒有台語詞的英文解釋：台語不能用英文查詞。）"
fi

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
