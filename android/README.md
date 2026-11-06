# 方方詞卡 — Android

The Android version of 方方詞卡: the same cards, dictionary, converter, practice modes, themes and widget as the
iPhone / iPad app, rewritten for Android (Kotlin + Jetpack Compose). Android 8.0 or newer.

## Build it (on the Mac)

1. Install **Android Studio** (free): https://developer.android.com/studio
2. Unzip `fangfang-android.zip`. In Android Studio: **Open** → choose the `fangfang-android` folder.
3. Wait for it to finish "Gradle sync" (the first time it downloads quite a lot; the bar at the bottom shows it).
   If it asks to install an Android SDK or to upgrade anything, say yes to installing the SDK, and **no** to
   upgrading the Android Gradle Plugin.
4. Make the APK: menu **Build → Build App Bundle(s) / APK(s) → Build APK(s)**. When it's done, click **locate**
   in the little message at the bottom right. The file is `app/build/outputs/apk/debug/app-debug.apk`.

If the build stops with errors, copy the red error lines from the **Build** window (bottom of the screen) and
send them to Claude to fix.

## Put it on an Android phone

**Send the APK** (easiest for a friend): send `app-debug.apk` to the phone (email, Google Drive, a chat app…).
On the phone, tap the file. Android asks to allow installing apps from that app (Chrome, Drive, Files…): allow it,
then tap **Install**. If Play Protect warns about an unknown app, choose **Install anyway**.

**Or straight from Android Studio**: on the phone, turn on Developer options (Settings → About phone → tap
"Build number" 7 times), then Settings → System → Developer options → USB debugging. Connect it with a cable,
pick the phone at the top of Android Studio and press the green ▶.

Updating later: build again and install the new APK over the old one — progress is kept.

## What's in it

- 新詞 (swipe cards, 主題), 不熟, 熟悉 (review + list), 詞典 (查詞, 各地讀音, 分類, 收藏, 自訂), 轉換
- tone colours (七聲 / 五聲, sandhi, 聲調光暈), 腔口, 皓羅 / 台羅 / 白話字
- 練習, 例句填空, 排句子, 看字排讀音, 聲調練習, stars, potion bars
- themes: 方方之夜, 女巫小屋, 星空, 苔蘚小窩, 雪夜 (主題動畫 can be turned off to save power); 選聲調顏色 (a colour for every tone)
- words swell when pressed; hold a finger on a sentence and slide to open the word under it
- 鬥拍字 read-aloud in 轉換, recordings kept for offline use
- automatic backup to a folder (same files as the iPhone app, so a shared Google Drive folder can sync both)
- 華語 mode (the 台・／華・ button at the top): 《兩岸常用詞典》 with 拼音／注音 and 臺灣／大陸 readings, tone colours,
  English / tone / `*` `?` search, tappable sentence words, cards from HSK 3.0 or TOCFL with level progress bars,
  a 華語 轉換, and CSV export of 收藏. 華語 is read aloud by the phone's own text-to-speech (if nothing plays,
  install a Chinese voice: Settings → System → Languages → Text-to-speech).
- 本週學習 (words for the week, practice, final test), 翻牌配對, saved meanings, copying a meaning in your own layout,
  選擇複製 with Discord styles, 倉頡／五筆 codes (設定 → 詞典), tappable headword characters
- home-screen widget 分類詞卡 (long-press the home screen → Widgets → 方方詞卡; long-press it again to change 分類)

- 部首查字 in both dictionaries: one radical, or 組合部首 (tap several radicals; the characters with all of them)
- several words at once (陰謀論 → 陰謀 + 論, or typed with spaces), with a rainbow button for each word in 台語
- 日語借詞, 單詞比較 (台語 and 華語), 台語 常用詞／常用字 groups of 500 in 新詞 and 學習進度
- 華語: 漢字卡 (《重編國語辭典修訂本》), 認識的漢字 (hold a character to switch it), 詞類 and 依詞類列出, 近／反,
  English meanings as a numbered list, English or 華語 as the main meaning on cards and lists, a copy layout of its own
- 練習範圍 (practise one level / group), practices carry on where you left them, 手寫練習 with a 楷體 shadow and a
  potion that shows how closely you traced it
- the widget can show only 不熟 words, the 不熟 words of either language, or a 華語 level
- both dictionaries load when the app starts; a backup import shows a potion bar

The 楷體 in 手寫練習 is 霞鶩文楷 TC (LXGW WenKai TC, SIL Open Font License 1.1, https://github.com/lxgw/LxgwWenkaiTC),
in `app/src/main/res/font`; its licence is in `licenses/LXGW-WenKai-TC-OFL.txt`. The 皓羅 font (`haolo.ttf`) is a
subset of DejaVu Sans; its licence is in `licenses/DejaVu-LICENSE.txt`.

Not in the Android version: Shortcuts actions, Liquid Glass.
