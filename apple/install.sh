#!/bin/bash
# 方方詞卡: builds the app and installs it on your iPhone / iPad and your Mac. No Xcode clicking needed.
#   bash ~/Downloads/fangfang-cards-main/install.sh          iPhone/iPad + Mac
#   bash ~/Downloads/fangfang-cards-main/install.sh ios      only iPhone/iPad
#   bash ~/Downloads/fangfang-cards-main/install.sh mac      only Mac (Apple chip: asks once, iPad app or Mac version; Intel: the Mac version)
#   bash ~/Downloads/fangfang-cards-main/install.sh ipad     only Mac, as the iPad app (Apple chip), and remember that
#   bash ~/Downloads/fangfang-cards-main/install.sh catalyst only Mac, as the Mac version, and remember that
#   bash ~/Downloads/fangfang-cards-main/install.sh ipa      an app file (FangfangCards.ipa on the Desktop) to install with Sideloadly
#   … nosafari (after any of the above, e.g. "install.sh ipa nosafari"): skips the Safari pop-up's words.
#   The app downloads and makes each language's dictionary itself (設定 → 詞典資料); the only data put in it is
#   Wiktionary's, which the app can't make on its own: 華語's 四川話 readings and 台語 words' English (zh_sc.json, tw_en.json).
#   The Safari pop-up (查詞) can't see what the app downloads (that would need an App Group, which an app installed
#   with Sideloadly usually doesn't get), so its words are built on this Mac and put inside the extension only
#   (the data is kept in ~/FangfangCards/data, never in the app; the first time takes a few minutes).
# Run it again any time (e.g. every 7 days for iPhone/iPad) to reinstall.
WHAT="${1:-all}"
SAFARI=1
for a in "$@"; do [ "$a" = "nosafari" ] && SAFARI=0; done
[ -n "$FANGFANG_NOSAFARI" ] && SAFARI=0
[ "$WHAT" = "safari" ] || [ "$WHAT" = "nosafari" ] && WHAT=all
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/FangfangCards"
DD="$HOME/Library/Developer/fangfangcards-build"
LOG="$HOME/Library/Logs/fangfangcards-build.log"
mkdir -p "$HOME/Library/Logs"

# copies of source files left by putting a new download over the old folder ("Store 2.swift"): the same code
# twice, which the build can't tell apart
find "$HERE/FangfangCards" "$HERE/FangfangWidget" -type f \( -name "* 2.swift" -o -name "* (1).swift" \) -print -delete 2>/dev/null | sed 's/^/（刪掉多出來的複本：/; s/$/）/'

# 1. keep the project in a fixed place: ~/FangfangCards
if [ "$HERE" != "$DEST" ]; then
  mkdir -p "$DEST"
  # keep word data that was already built there
  rsync -a --delete --exclude ".DS_Store" --exclude "xcuserdata" --exclude "project.xcworkspace" --exclude "/data" \
        --exclude "FangfangCards/dict.json" --exclude "FangfangCards/cards.json" --exclude "FangfangCards/zh.json" --exclude "FangfangCards/inputcodes.json" --exclude "FangfangCards/yue.json" --exclude "FangfangCards/hak.json" --exclude "FangfangCards/tw_en.json" --exclude "FangfangCards/zh_sc.json" --exclude "FangfangSafari/d-*.json" "$HERE/" "$DEST/"
  mkdir -p "$DEST/data"
  for f in dict.json cards.json zh.json inputcodes.json yue.json hak.json tw_en.json zh_sc.json; do
    [ -f "$HERE/FangfangCards/$f" ] && cp "$HERE/FangfangCards/$f" "$DEST/data/$f"
  done
fi
# (your own 台語 words, for building 台語 in the app too: 設定 → 詞典資料)
[ -f "$DEST/tools/own.json" ] && cp "$DEST/tools/own.json" "$DEST/FangfangCards/Install/twown.json" 2>/dev/null || true
echo "專案：$DEST/FangfangCards.xcodeproj"

# Xcode new enough? (the project needs Xcode 26, which needs macOS Sequoia 15.6 or later)
XV=$(xcodebuild -version 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
if [ -z "$XV" ]; then
  echo "✗ 找不到 Xcode。請從 App Store 安裝 Xcode，打開一次，再執行這個指令。"; exit 1
elif [ "$XV" -lt 26 ]; then
  echo "✗ 這台 Mac 的 Xcode 是 $(xcodebuild -version | head -1)，太舊了：方方詞卡需要 Xcode 26 以上。"
  echo "  Xcode 26 需要 macOS Sequoia 15.6 以上（這台是 macOS $(sw_vers -productVersion)）。"
  echo "  請先更新 macOS 和 Xcode；如果這台 Mac 不能更新，請用另一台較新的 Mac 安裝。"
  exit 1
fi

# 2. no dictionary data in the app: the app downloads and makes each language's dictionary itself. Data built on
# this Mac before is kept in ~/FangfangCards/data (for the Safari pop-up), never inside the app.
DATA="dict.json cards.json zh.json inputcodes.json yue.json hak.json tw_en.json zh_sc.json ja.json shuowen.json sv.json"
mkdir -p "$DEST/data/safari"
for f in $DATA; do [ -f "$DEST/FangfangCards/$f" ] && mv -f "$DEST/FangfangCards/$f" "$DEST/data/$f"; done
if [ "$SAFARI" = "1" ]; then
  # Safari 查詞: the extension needs the words inside it, so they're built here (build-data.sh works in
  # FangfangCards/: the data is put there for that, then taken out again)
  for f in $DATA; do [ -f "$DEST/data/$f" ] && cp "$DEST/data/$f" "$DEST/FangfangCards/$f"; done
  for f in "$DEST"/data/safari/d-*.json; do [ -f "$f" ] && mv -f "$f" "$DEST/FangfangSafari/"; done
  if [ ! -f "$DEST/FangfangCards/dict.json" ] || [ ! -f "$DEST/FangfangCards/cards.json" ]; then
    bash "$DEST/build-data.sh" || { echo "✗ 沒辦法建立詞典資料。"; exit 1; }
  fi
  # 華語 data (《兩岸常用詞典》)
  if [ ! -f "$DEST/FangfangCards/zh.json" ]; then
    bash "$DEST/build-data.sh" zh || { echo "✗ 沒辦法建立華語資料。"; exit 1; }
  fi
  # 粵語 data (CC-Canto, CC-CEDICT, Wiktionary…); made again when it was made by an older version
  Y="$DEST/FangfangCards/yue.json"
  if [ -f "$Y" ] && ! head -c 80 "$Y" | grep -q '"v":2'; then echo "（粵語資料是舊版做的，重新建立）"; rm -f "$Y"; fi
  if [ ! -f "$DEST/FangfangCards/yue.json" ]; then
    bash "$DEST/build-data.sh" yue || echo "（沒辦法建立粵語資料，先跳過：App 裡的粵語會打不開）"
  fi
  # 客語 data (教育部《臺灣客語辭典》)
  if [ ! -f "$DEST/FangfangCards/hak.json" ]; then
    bash "$DEST/build-data.sh" hak || echo "（沒辦法建立客語資料，先跳過：App 裡的客語會打不開）"
  fi
  # 台語 words' English (Wiktionary)
  if [ ! -f "$DEST/FangfangCards/tw_en.json" ]; then
    bash "$DEST/build-data.sh" twen || echo "（沒辦法建立台語詞的英文解釋，先跳過）"
  fi
  # 華語 words' 四川話 readings (Wiktionary); made again when it was made by an older version (without the guessed and
  # predicted ones)
  SC="$DEST/FangfangCards/zh_sc.json"
  if [ -f "$SC" ] && ! head -c 40 "$SC" | grep -q '"v":4'; then rm -f "$SC"; fi
  if [ ! -f "$DEST/FangfangCards/zh_sc.json" ]; then
    bash "$DEST/build-data.sh" sc || echo "（沒辦法建立四川話讀音，先跳過）"
  fi
  # 瑞典語 data (Folkets lexikon), for the Safari pop-up's Swedish words; made again when it was made by an older
  # version (without the 華語 guessed from the English)
  SV="$DEST/FangfangCards/sv.json"
  if [ -f "$SV" ] && ! head -c 40 "$SV" | grep -q '"v":3'; then rm -f "$SV"; fi
  if [ ! -f "$DEST/FangfangCards/sv.json" ]; then
    bash "$DEST/build-data.sh" sv || echo "（沒辦法建立瑞典語資料，先跳過：Safari 查詞不會查瑞典語）"
  fi
  if [ ! -f "$DEST/FangfangCards/inputcodes.json" ]; then
    bash "$DEST/build-data.sh" ime || echo "（沒辦法建立輸入法拆碼，先跳過）"
  fi
  # Safari 查詞: the words, put inside the Safari extension (made again when the word data is newer)
  SM="$DEST/FangfangSafari/d-meta.json"
  NEED_SAFARI=0
  [ -f "$SM" ] || NEED_SAFARI=1
  for f in dict.json zh.json zh_sc.json tw_en.json sv.json; do
    [ -f "$DEST/FangfangCards/$f" ] && [ "$DEST/FangfangCards/$f" -nt "$SM" ] && NEED_SAFARI=1
  done
  [ "$DEST/tools/build_safari.py" -nt "$SM" ] && NEED_SAFARI=1
  if [ "$NEED_SAFARI" = "1" ]; then
    echo "準備 Safari 查詞的資料…"
    /usr/bin/env python3 "$DEST/tools/build_safari.py" "$DEST/FangfangCards/" "$DEST/FangfangSafari/" || echo "（沒辦法準備 Safari 查詞的資料，先跳過）"
  fi
  for f in $DATA; do [ -f "$DEST/FangfangCards/$f" ] && mv -f "$DEST/FangfangCards/$f" "$DEST/data/$f"; done
else
  # (the Safari pop-up's words from an earlier install: kept aside, not in the app)
  for f in "$DEST"/FangfangSafari/d-*.json; do [ -f "$f" ] && mv -f "$f" "$DEST/data/safari/"; done
  echo "（跳過 Safari 查詞的資料：Safari 查詞不會跳出卡片。要的話執行 install.sh 時不要加 nosafari。）"
fi
# The Wiktionary data (CC BY-SA) put in the app: 華語's 四川話 readings (zh_sc.json) and 台語 words' English, which
# 台語's English search uses (tw_en.json). The app can't make them itself (it would need Wiktionary's whole 2.5 GB
# Chinese file), so the copies made on this Mac go in; every other dictionary is downloaded and made by the app.
for f in zh_sc tw_en; do
  if [ -f "$DEST/data/$f.json" ]; then
    cp "$DEST/data/$f.json" "$DEST/FangfangCards/$f.json"
  else
    echo "（還沒有 $f.json（維基詞典的資料：四川話讀音、台語詞的英文）：執行 install.sh 時不要加 nosafari，就會在這台 Mac 上建立。）"
  fi
done

# (FANGFANG_OFFLINE_SOURCES=a folder: the dictionaries' original files go inside the app, for a device that can't
# download them; the app then makes each dictionary from them. Taken out again when this script ends.)
OFF="$DEST/FangfangCards/OfflineSources.bundle"
rm -rf "$OFF"
if [ -n "$FANGFANG_OFFLINE_SOURCES" ] && [ -d "$FANGFANG_OFFLINE_SOURCES" ]; then
  mkdir -p "$OFF" && cp "$FANGFANG_OFFLINE_SOURCES"/* "$OFF"/
  trap 'rm -rf "$OFF"' EXIT
  echo "（詞典的原始檔案放進 App：$(du -sh "$OFF" | cut -f1)）"
fi

# Xcode's iOS part (a separate download in new Xcode versions): say how to get it if it's missing
ensure_ios_platform() {
  if ! xcodebuild -showdestinations -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards 2>&1 < /dev/null | grep -q "is not installed"; then return 0; fi
  echo "✗ Xcode 還沒有 iOS 的元件。請打開 Xcode → Settings → Components，下載 iOS，再執行一次這個指令。"
  exit 1
}

# (defined before anything that builds, so every way of building can stop on an error)
fail() {
  echo "✗ 建置失敗。把下面的錯誤訊息傳給 Claude："
  grep -E "error:|error -|Signing|provision" "$LOG" | sort -u | head -25
  echo "（完整紀錄：${LOG}）"
  exit 1
}

# "install.sh ipa": an app file (.ipa) for someone whose Mac can't build the app; they install it on their
# iPhone/iPad with Sideloadly and their own Apple ID (Sideloadly signs it, so it's built unsigned here)
if [ "$WHAT" = "ipa" ]; then
  ensure_ios_platform
  echo "建置 App 檔（.ipa）…"
  IDD="$DD-ipa"
  # (no app from an earlier build left over: if this build fails, there's no old app to pack by mistake)
  rm -rf "$IDD/Build/Products"
  xcodebuild -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards -configuration Release \
     -destination "generic/platform=iOS" -derivedDataPath "$IDD" \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
     build > "$LOG" 2>&1 < /dev/null || fail
  APP=$(ls -d "$IDD"/Build/Products/Release-iphoneos/*.app | grep -v -i widget | head -1)
  PKG=$(mktemp -d)
  mkdir -p "$PKG/Payload"
  cp -R "$APP" "$PKG/Payload/"
  OUT="$HOME/Desktop/FangfangCards.ipa"
  rm -f "$OUT"
  (cd "$PKG" && zip -qry "$OUT" Payload)
  rm -rf "$PKG"
  echo "✓ App 檔：$OUT"
  echo "  傳給對方，對方用 Sideloadly 安裝到 iPhone／iPad（見 README「用 Sideloadly 安裝」）。"
  exit 0
fi

# 3. Apple developer team (only needed when the project doesn't have one, e.g. downloaded from GitHub)
TEAMARG=()
IDARG=()
if grep -q 'DEVELOPMENT_TEAM = "";' "$DEST/FangfangCards.xcodeproj/project.pbxproj"; then
  TEAM="${FANGFANG_TEAM:-$(cat "$HOME/.fangfang-team" 2>/dev/null)}"
  if [ -z "$TEAM" ]; then
    TEAM=$(defaults read com.apple.dt.Xcode 2>/dev/null | grep -oE 'teamID = "?[A-Z0-9]{10}' | head -1 | grep -oE '[A-Z0-9]{10}$')
  fi
  if [ -z "$TEAM" ]; then
    echo "✗ 找不到你的 Apple 開發者團隊。請先打開 Xcode → Settings → Accounts，用 Apple ID 登入，再執行一次。"
    exit 1
  fi
  echo "$TEAM" > "$HOME/.fangfang-team"
  # an app ID of your own: each Apple ID can only use IDs no one else has registered
  FFID="${FANGFANG_ID:-com.fangfangcards.$(echo "$TEAM" | tr 'A-Z' 'a-z')}"
  TEAMARG=(DEVELOPMENT_TEAM="$TEAM" FF_ID="$FFID")
  IDARG=(FF_ID="$FFID")
  # also write it into the project copy, so opening it in Xcode uses the same team and ID
  sed -i '' -e "s/FF_ID = com.unoki99.fangfangcards;/FF_ID = $FFID;/" \
            -e "s/DEVELOPMENT_TEAM = \"\";/DEVELOPMENT_TEAM = $TEAM;/" "$DEST/FangfangCards.xcodeproj/project.pbxproj"
fi


# Build with signing. If the App Group (the widget's shared folder) isn't registered for your Apple ID
# yet, build again without it: the app works normally, only the 分類詞卡 widget has no words.
NOGROUP=()
build_signed() {
  xcodebuild "$@" "${NOGROUP[@]}" build > "$LOG" 2>&1 < /dev/null && return 0
  if [ ${#NOGROUP[@]} -eq 0 ] && grep -q "application-groups" "$LOG"; then
    echo "（你的 Apple ID 還沒註冊這個 App 的 App Group，先不用它建置：App 都正常，只是「分類詞卡」小工具會沒有詞。"
    echo "  想用小工具：在 Xcode 打開 ~/FangfangCards/FangfangCards.xcodeproj，上方選你的 iPhone 按 ▶ 一次，"
    echo "  Xcode 會自動註冊；之後再執行這個指令就好。）"
    NOGROUP=(CODE_SIGN_ENTITLEMENTS="")
    xcodebuild "$@" "${NOGROUP[@]}" build > "$LOG" 2>&1 < /dev/null && return 0
  fi
  return 1
}

# 4. iPhone / iPad (fresh 7-day signature)
if [ "$WHAT" = "all" ] || [ "$WHAT" = "ios" ]; then
  ensure_ios_platform
  echo "建置 iPhone／iPad 版…（第一次大概 1–2 分鐘）"
  build_signed -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards -configuration Debug \
     -destination "generic/platform=iOS" -derivedDataPath "$DD" -allowProvisioningUpdates "${TEAMARG[@]}" || fail
  APP=$(ls -d "$DD"/Build/Products/Debug-iphoneos/*.app | head -1)
  echo "✓ 建置完成"
  JSON=$(mktemp)
  xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 < /dev/null
  IDS=$(/usr/bin/python3 - "$JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for dev in d.get("result", {}).get("devices", []):
    hw = dev.get("hardwareProperties", {}); cp = dev.get("connectionProperties", {})
    if hw.get("platform") == "iOS" and cp.get("pairingState") == "paired" and cp.get("tunnelState") != "unavailable":
        print(dev["identifier"] + "\t" + dev.get("deviceProperties", {}).get("name", "?"))
PY
)
  rm -f "$JSON"
  if [ -z "$IDS" ]; then
    echo "✗ 找不到 iPhone／iPad。請解鎖、接上傳輸線或連同一個 Wi-Fi，再執行一次。"
  else
    while IFS=$'\t' read -r ID NAME; do
      if xcrun devicectl device install app --device "$ID" "$APP" >/dev/null 2>&1 < /dev/null; then
        echo "✓ 已安裝到 $NAME"
      else
        echo "✗ 安裝到 $NAME 失敗（手機要解鎖）"
      fi
    done <<< "$IDS"
  fi
fi

# 5. Mac. On a Mac with an Apple chip: the iPad app itself (exactly the same app as on the iPad; it runs
#    smoother than the Mac version). On an Intel Mac, or with "install.sh catalyst": the Mac version.
# Apple chip: you choose (asked once, remembered in ~/.fangfang-mac-kind; "install.sh ipad" or
# "install.sh catalyst" choose again). Intel: always the Mac version (iPad apps don't run there).
MACKIND="catalyst"
if [ "$(uname -m)" = "arm64" ] || [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then
  KINDFILE="$HOME/.fangfang-mac-kind"
  if [ "$WHAT" = "catalyst" ] || [ "$WHAT" = "ipad" ]; then
    MACKIND="$WHAT"; echo "$MACKIND" > "$KINDFILE"
  elif [ -f "$KINDFILE" ]; then
    MACKIND=$(cat "$KINDFILE")
  elif [ "$WHAT" = "all" ] || [ "$WHAT" = "mac" ]; then
    echo ""
    echo "這台 Mac 是 Apple 晶片，Mac 上要裝哪一種？"
    echo "  1) iPad 版（建議）：跟 iPad 上的一模一樣，比較順，聲調光暈也比較漂亮；7 天後要重新執行這個指令。"
    echo "  2) Mac 版：有側邊欄、可以用選單列；不會過期，但滑鼠移過去放大字的時候比較不順。"
    if [ -t 0 ]; then read -r -p "請輸入 1 或 2（直接按 Enter = 1）：" ANS; else ANS=1; fi
    if [ "$ANS" = "2" ]; then MACKIND="catalyst"; else MACKIND="ipad"; fi
    echo "$MACKIND" > "$KINDFILE"
    echo "（記住了。之後想換：install.sh ipad 或 install.sh catalyst）"
  else
    MACKIND="ipad"
  fi
  [ "$MACKIND" = "ipad" ] || MACKIND="catalyst"
elif [ "$WHAT" = "ipad" ]; then
  echo "✗ 這台 Mac 是 Intel 晶片，不能執行 iPad App，改裝 Mac 版。"
fi
if [ "$WHAT" = "all" ] || [ "$WHAT" = "mac" ] || [ "$WHAT" = "catalyst" ] || [ "$WHAT" = "ipad" ]; then
  TARGET="/Applications"
  [ -w "$TARGET" ] || { TARGET="$HOME/Applications"; mkdir -p "$TARGET"; }
  if [ "$MACKIND" = "ipad" ]; then
    ensure_ios_platform
    echo "建置 Mac 版（iPad App）…"
    MDD="$DD-ipadmac"
    # the project is set up for the Mac version; for this build, switch it to "iPad app on the Mac"
    # (in the copy in ~/FangfangCards; put back right after)
    PBX="$DEST/FangfangCards.xcodeproj/project.pbxproj"
    cp "$PBX" "$PBX.fangfang-bak"
    sed -i '' -e 's/SUPPORTS_MACCATALYST = YES;/SUPPORTS_MACCATALYST = NO;/' \
              -e 's/SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;/SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES;/' "$PBX"
    restore() { mv -f "$PBX.fangfang-bak" "$PBX"; }
    # this Mac as an "iPad app" destination
    xcodebuild -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards -showdestinations > "$LOG" 2>&1 < /dev/null
    LINE=$(sed '/Ineligible/,$d' "$LOG" | grep "Designed for" | grep "id:" | head -1)
    DID=$(echo "$LINE" | grep -oE 'id:[^,} ]+' | head -1 | cut -d: -f2)
    # (the variant name "Designed for [iPad,iPhone]" has a comma xcodebuild can't read, so: this Mac's id +
    #  arm64; with the Mac version switched off above, that is the iPad-app destination)
    if [ -n "$DID" ]; then DESTSPEC="platform=macOS,arch=arm64,id=$DID"
    else DESTSPEC="platform=macOS,arch=arm64,variant=Designed for iPad"; fi
    SHOWD=$(grep -E "platform:macOS" "$LOG" | head -5)
    build_signed -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards -configuration Debug \
         -destination "$DESTSPEC" -derivedDataPath "$MDD" \
         -allowProvisioningUpdates -allowProvisioningDeviceRegistration "${TEAMARG[@]}" \
         || { restore; echo "（可以用的目的地：）"; echo "$SHOWD"; fail; }
    restore
    IPAPP=$(ls -d "$MDD"/Build/Products/Debug-iphoneos/*.app | grep -v -i widget | head -1)
    NAME=$(basename "$IPAPP")
    pkill -f "方方詞卡.app" 2>/dev/null
    # an iPad app on the Mac lives inside a wrapper: 方方詞卡.app/Wrapper/<app>.app (+ WrappedBundle link).
    # Keep the wrapper and only swap the app inside it, and take off any "downloaded from the internet"
    # marks, so the Mac hopefully remembers that you allowed it to open.
    if [ ! -L "$TARGET/方方詞卡.app/WrappedBundle" ]; then rm -rf "$TARGET/方方詞卡.app"; fi
    mkdir -p "$TARGET/方方詞卡.app/Wrapper"
    rm -rf "$TARGET/方方詞卡.app/Wrapper/$NAME"
    cp -R "$IPAPP" "$TARGET/方方詞卡.app/Wrapper/$NAME"
    ln -sfn "Wrapper/$NAME" "$TARGET/方方詞卡.app/WrappedBundle"
    xattr -cr "$TARGET/方方詞卡.app" 2>/dev/null
    echo "✓ Mac 版（iPad App）已安裝到 $TARGET/方方詞卡.app"
    echo "  跟 iPhone／iPad 一樣，免費 Apple ID 的話 7 天後再執行一次這個指令。"
  else
    echo "建置 Mac 版…"
    xcodebuild -project "$DEST/FangfangCards.xcodeproj" -scheme FangfangCards -configuration Release \
       -destination "generic/platform=macOS,variant=Mac Catalyst" -derivedDataPath "$DD" \
       CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" "${IDARG[@]}" \
       build > "$LOG" 2>&1 < /dev/null || fail
    MACAPP=$(ls -d "$DD"/Build/Products/Release-maccatalyst/*.app | head -1)
    pkill -x "$(basename "$MACAPP" .app)" 2>/dev/null
    rm -rf "$TARGET/方方詞卡.app"
    cp -R "$MACAPP" "$TARGET/方方詞卡.app"
    echo "✓ Mac 版已安裝到 $TARGET/方方詞卡.app"
  fi
fi
echo "完成！免費 Apple ID：7 天後再執行一次這個指令就好。"
