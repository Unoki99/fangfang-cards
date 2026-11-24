# Fangfang Cards（方方詞卡）

**English** · [中文](#方方詞卡fangfang-cards)

Word cards, a dictionary and practice for Taiwanese, Mandarin, Cantonese, Hakka and Japanese.

- **windows/**: the desktop version (Windows and Mac)
- **android/**: the Android version
- **apple/**: the iPhone / iPad version (can also be installed on a Mac)
- **Firefox extension**: look up words on web pages, YouTube lyrics. [Install from the add-ons site](https://addons.mozilla.org/en-US/firefox/addon/%E6%96%B9%E6%96%B9%E8%A9%9E%E5%8D%A1/)

## Install

On GitHub, click **Code → Download ZIP** and unzip it into Downloads (folder: `fangfang-cards-main`).

| Version | Platform | File / command |
|---|---|---|
| **Desktop** | Windows | Double-click `install-windows.bat` |
| **Desktop** | Mac | Terminal: `bash ~/Downloads/fangfang-cards-main/install-mac.command` |
| **Android** | Windows | Double-click `android-install.bat` |
| **Android** | Mac | Terminal: `bash ~/Downloads/fangfang-cards-main/install.sh android` |
| **iPhone / iPad** | Mac | Terminal: `bash ~/Downloads/fangfang-cards-main/install.sh apple ios` |
| **iPad version on a Mac** | Mac (Apple silicon) | Terminal: `bash ~/Downloads/fangfang-cards-main/install.sh apple mac` |
| **IPA (for sideloading)** | Mac | Terminal: `bash ~/Downloads/fangfang-cards-main/install.sh apple ipa` |
| **Firefox extension** | Windows, Mac, Android | [Add-ons page](https://addons.mozilla.org/en-US/firefox/addon/%E6%96%B9%E6%96%B9%E8%A9%9E%E5%8D%A1/) → Add to Firefox |

**Install first**

| Version | Windows | Mac |
|---|---|---|
| Desktop | [Python 3](https://www.python.org/downloads/) (tick "Add python.exe to PATH") | Nothing |
| Android | Python 3, [Android Studio](https://developer.android.com/studio) | Android Studio |
| iPhone / iPad | — | Xcode 26 or later, signed in with your Apple ID in Xcode → Settings → Accounts |

**Update**: run the same file or command again. (iPhone / iPad with a free Apple ID: once every 7 days.)

Terminal is in Applications → Utilities → Terminal. If the folder isn't in Downloads, change the path in the command, or drag the file into the Terminal window.

## Notes

### Desktop (Windows, Mac)

- The first build takes 5–10 minutes; Java and anything else it needs is downloaded automatically.
- Windows: installed to `%LOCALAPPDATA%\Programs\FangfangCards`, with 方方詞卡 in the Start menu and on the desktop.
- Mac: installed in Applications as **方方詞卡（電腦版）**. Run `install-mac.command` from Terminal (GitHub's ZIP doesn't keep the file executable, so double-clicking says you don't have permission).
- Dictionaries are installed inside the program, by language, the first time you open it.
- Progress: Windows `%LOCALAPPDATA%\FangfangCards\app`, Mac `~/Library/Application Support/FangfangCards/app`. Move it between devices with a backup file or a shared backup folder (Settings → Export and import).

### Android

- The APK ends up on the desktop (`FangfangCards.apk`): copy it to the phone and tap it to install. With the phone connected by USB and USB debugging on, it's installed directly.
- Open Android Studio once first so it downloads the SDK.
- More: `android/README.md`.

### iPhone / iPad (and the iPad version on a Mac)

- `install.sh apple` installs both iPhone / iPad and Mac; plain `install.sh` asks which one.
- Connect the iPhone / iPad to the Mac by USB (the first time, tap Trust on the device).
- More: `apple/README.md`.

### Dictionary data

The licences of the Ministry of Education's and the Chinese Language Society's dictionaries don't allow sharing processed versions, so they aren't in this repository. Copies of the original files are in [unoki99/fangfang-data](https://github.com/unoki99/fangfang-data), each under its own licence (see its README.md), **not covered by this project's MIT licence**. They are processed on your own computer when you install. Sources and licences: "資料來源與授權" in `apple/README.md`.

---

# 方方詞卡（Fangfang Cards）

[English](#fangfang-cards方方詞卡) · **中文**

台語、華語、粵語、客語、日語的詞卡、詞典和練習。

- **windows/**：電腦版（Windows 和 Mac）
- **android/**：Android 版
- **apple/**：iPhone、iPad 版（也可以裝在 Mac 上）
- **Firefox 擴充功能**：網頁查詞、YouTube 歌詞。[從附加元件網站安裝](https://addons.mozilla.org/en-US/firefox/addon/%E6%96%B9%E6%96%B9%E8%A9%9E%E5%8D%A1/)

## 安裝

在 GitHub 按 **Code → Download ZIP**，解壓縮到「下載項目」（資料夾：`fangfang-cards-main`）。

| 版本 | 平台 | 檔案／指令 |
|---|---|---|
| **電腦版** | Windows | 雙擊 `install-windows.bat` |
| **電腦版** | Mac | 終端機：`bash ~/Downloads/fangfang-cards-main/install-mac.command` |
| **Android** | Windows | 雙擊 `android-install.bat` |
| **Android** | Mac | 終端機：`bash ~/Downloads/fangfang-cards-main/install.sh android` |
| **iPhone／iPad** | Mac | 終端機：`bash ~/Downloads/fangfang-cards-main/install.sh apple ios` |
| **iPad 版裝在 Mac** | Mac（Apple 晶片） | 終端機：`bash ~/Downloads/fangfang-cards-main/install.sh apple mac` |
| **Firefox 擴充功能** | Windows、Mac、Android | [附加元件頁](https://addons.mozilla.org/en-US/firefox/addon/%E6%96%B9%E6%96%B9%E8%A9%9E%E5%8D%A1/) → Add to Firefox |

**要先裝的東西**

| 版本 | Windows | Mac |
|---|---|---|
| 電腦版 | [Python 3](https://www.python.org/downloads/)（勾選「Add python.exe to PATH」） | 不用 |
| Android | Python 3、[Android Studio](https://developer.android.com/studio) | Android Studio |
| iPhone／iPad | — | Xcode 26 以上，在 Xcode → Settings → Accounts 用 Apple ID 登入 |

**更新**：再執行一次同一個檔案或指令。（iPhone／iPad 用免費 Apple ID 的話，每 7 天一次。）

終端機在「應用程式 → 工具程式 → 終端機」。資料夾不在「下載項目」的話，把指令裡的路徑換掉，或把檔案拖進終端機視窗。

## 說明

### 電腦版（Windows、Mac）

- 第一次建置 5–10 分鐘；Java 等需要的東西會自己下載。
- Windows：裝在 `%LOCALAPPDATA%\Programs\FangfangCards`，開始功能表和桌面上有「方方詞卡」。
- Mac：裝在「應用程式」：**方方詞卡（電腦版）**。`install-mac.command` 要用終端機執行（GitHub 的 ZIP 不保留執行權限，雙擊會說「沒有適當的取用權限」）。
- 詞典在程式裡第一次打開時選語言安裝。
- 進度：Windows `%LOCALAPPDATA%\FangfangCards\app`，Mac `~/Library/Application Support/FangfangCards/app`。在裝置之間用備份檔或同一個備份資料夾（設定 → 匯出與匯入）。

### Android

- 做好的 APK 在桌面（`FangfangCards.apk`），傳到手機上點它安裝。手機用 USB 接著並打開「USB 偵錯」的話會直接裝上去。
- Android Studio 要先打開一次，讓它下載 SDK。
- 詳細：`android/README.md`。

### iPhone／iPad（和 Mac 上的 iPad 版）

- `install.sh apple` 一次裝 iPhone／iPad 和 Mac；只寫 `install.sh` 的話會問你要哪一個。
- iPhone／iPad 用 USB 接上 Mac（第一次在手機上按「信任」）。
- 詳細：`apple/README.md`。

### 詞典資料

教育部和中華文化總會的詞典授權不允許散布整理過的資料，所以這裡沒有那些檔案。原始檔案的副本在 [unoki99/fangfang-data](https://github.com/unoki99/fangfang-data)，各依自己的授權（見那裡的 README.md），**不在本專案的 MIT 授權範圍內**。安裝時在你的電腦上從原始檔案產生。資料來源和授權見 `apple/README.md` 的「資料來源與授權」。

### 查詞的附加元件給 Firefox（電腦和 Android）

**一般只要從 Firefox 的附加元件網站安裝就好：** https://addons.mozilla.org/en-US/firefox/addon/%E6%96%B9%E6%96%B9%E8%A9%9E%E5%8D%A1/ 。下面是自己做擴充功能檔案的方法（要改程式或在上架前先試的話）。

Safari 查詞（網頁查詞、影片字幕）也可以裝在 Firefox，包括 Android 手機上的 Firefox。不用先做詞典資料：

- **Windows**：在資料夾裡**雙擊 `build-firefox.bat`**（測試版：雙擊 `build-firefox-test.bat`）。
- **Mac**：在終端機執行 `bash ~/Desktop/fangfang-cards-main/apple/tools/build_firefox.sh`。

桌面會多一個 `fangfang-firefox.xpi`。**裡面沒有任何詞典**（詞典的授權不允許散布改過的版本）：裝好以後打開它的設定頁，在「詞典」選語言按「安裝」，它會下載詞典原本的檔案（先從 [fangfang-data](https://github.com/unoki99/fangfang-data)），在瀏覽器裡整理好。所以這個版本可以公開：在 addons.mozilla.org/developers 第一次按「Submit a New Add-on」，之後在「My Add-ons」打開它按「Upload New Version」，都選「On this site」，審核通過以後大家都能在 Firefox 的附加元件頁找到、安裝。（要先自己試的話：上傳時選「On your own」，下載簽好的檔案，在 Firefox 從檔案安裝；Android：設定 → 關於 Firefox → 連點標誌 5 次 → 回到設定 → 從檔案安裝附加元件。）

只給自己用、把做好的資料直接放進去的版本：`build-firefox.bat withdata`（Mac：`build_firefox.sh withdata`，要先照上面做出詞典資料），做出 `fangfang-firefox-private.xpi`。這個版本有改過的詞典資料，只能選「On your own」，不能公開。

