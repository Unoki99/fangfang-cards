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

### Playing together over the internet (一起玩, 詞龍)

On iPhone / iPad, people in the same place can play without any setup: choose 附近的人 (same Wi-Fi, or Bluetooth on). To play with someone somewhere else, or between iPhone, Android and computers, the apps connect through a small relay server. **One person sets it up once**, on their own free Cloudflare account; everyone else only pastes its address.

1. Make a free account at [dash.cloudflare.com/sign-up](https://dash.cloudflare.com/sign-up) (no credit card).
2. Install [Node.js](https://nodejs.org) (the LTS version) on a Mac or Windows computer.
3. Upload the relay:
   - **Mac**: in Terminal, run `bash ~/Downloads/fangfang-cards-main/relay/deploy-relay.command`. It logs in to Cloudflare (a browser page opens: press **Allow**), uploads the relay, and copies its address.
   - **Windows, or by hand**: open a terminal in the `relay` folder and run `npx wrangler login`, then `npx wrangler deploy`.
   - The first time, it may ask for a workers.dev name: type a short English name (e.g. your own) and press Enter.
4. At the end it shows an address like `https://fangfang-relay.yourname.workers.dev`. You can also find it at dash.cloudflare.com → Compute (Workers) → fangfang-relay.
5. In the app: **Settings → Cards & practice → 一起玩 → 連線伺服器**, paste the address (and set the name others see). Send the same address to everyone you play with; they paste it in the same place.
6. To play: open 一起玩 or 詞龍, choose **透過網路**. One person presses **開一個新房間** and tells the others the room code (e.g. KX7P-2MQA); they type it and press **進房間**.

The relay stays online by itself: no computer needs to be on. It's free on Cloudflare's free plan (a game uses a tiny part of the daily allowance; if it were ever used up, it would just stop until the next day, never charge you). Messages are encrypted in the app with a key made from the room code, so the relay only passes on data it can't read, and it stores nothing. More: `relay/README.md`.

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

### 透過網路一起玩（一起玩、詞龍）

iPhone／iPad 在同一個地方的話不用設定：選「附近的人」（同一個 Wi-Fi，或打開藍牙）。要和在別的地方的人玩，或是 iPhone、Android、電腦一起玩，App 透過一個小小的連線伺服器連線。**只要一個人放一次**，放在自己的免費 Cloudflare 帳號上；其他人只要貼上網址。

1. 在 [dash.cloudflare.com/sign-up](https://dash.cloudflare.com/sign-up) 申請免費帳號（不用信用卡）。
2. 在 Mac 或 Windows 電腦上安裝 [Node.js](https://nodejs.org)（LTS 版）。
3. 把連線伺服器放上去：
   - **Mac**：在終端機執行 `bash ~/Downloads/fangfang-cards-main/relay/deploy-relay.command`。它會登入 Cloudflare（瀏覽器打開一個頁面：按 **Allow**）、上傳，最後把網址複製好。
   - **Windows，或自己打指令**：在 `relay` 資料夾打開終端機，執行 `npx wrangler login`，再執行 `npx wrangler deploy`。
   - 第一次可能會問 workers.dev 的名字：打一個短短的英文名字（例如你的名字），按 Enter。
4. 最後會顯示網址，像 `https://fangfang-relay.你的名字.workers.dev`。也可以在 dash.cloudflare.com → Compute (Workers) → fangfang-relay 找到。
5. App 裡：**設定 → 卡片與練習 → 一起玩 → 連線伺服器**，貼上網址（也可以設別人看到的名字）。把同一個網址傳給一起玩的人，他們貼在同一個地方。
6. 開始玩：打開「一起玩」或「詞龍」，選 **透過網路**。一個人按 **開一個新房間**，把房間代碼（例如 KX7P-2MQA）告訴其他人；他們打代碼，按 **進房間**。

連線伺服器放上去以後自己一直開著，不用開著哪一台電腦。用 Cloudflare 的免費方案就夠了（一場遊戲只用到每天額度的一點點；萬一用完了，只是當天不能用，第二天再恢復，不會收費）。訊息在 App 裡用房間代碼算出來的金鑰加密，伺服器只轉送看不懂的資料，什麼都不存。詳細：`relay/README.md`。

### 詞典資料

教育部和中華文化總會的詞典授權不允許散布整理過的資料，所以這裡沒有那些檔案。原始檔案的副本在 [unoki99/fangfang-data](https://github.com/unoki99/fangfang-data)，各依自己的授權（見那裡的 README.md），**不在本專案的 MIT 授權範圍內**。安裝時在你的電腦上從原始檔案產生。資料來源和授權見 `apple/README.md` 的「資料來源與授權」。

### 查詞的附加元件給 Firefox（電腦和 Android）

**一般只要從 Firefox 的附加元件網站安裝就好：** https://addons.mozilla.org/en-US/firefox/addon/%E6%96%B9%E6%96%B9%E8%A9%9E%E5%8D%A1/ 。下面是自己做擴充功能檔案的方法（要改程式或在上架前先試的話）。

Safari 查詞（網頁查詞、影片字幕）也可以裝在 Firefox，包括 Android 手機上的 Firefox。不用先做詞典資料：

- **Windows**：在資料夾裡**雙擊 `build-firefox.bat`**（測試版：雙擊 `build-firefox-test.bat`）。
- **Mac**：在終端機執行 `bash ~/Desktop/fangfang-cards-main/apple/tools/build_firefox.sh`。

桌面會多一個 `fangfang-firefox.xpi`。**裡面沒有任何詞典**（詞典的授權不允許散布改過的版本）：裝好以後打開它的設定頁，在「詞典」選語言按「安裝」，它會下載詞典原本的檔案（先從 [fangfang-data](https://github.com/unoki99/fangfang-data)），在瀏覽器裡整理好。所以這個版本可以公開：在 addons.mozilla.org/developers 第一次按「Submit a New Add-on」，之後在「My Add-ons」打開它按「Upload New Version」，都選「On this site」，審核通過以後大家都能在 Firefox 的附加元件頁找到、安裝。（要先自己試的話：上傳時選「On your own」，下載簽好的檔案，在 Firefox 從檔案安裝；Android：設定 → 關於 Firefox → 連點標誌 5 次 → 回到設定 → 從檔案安裝附加元件。）

只給自己用、把做好的資料直接放進去的版本：`build-firefox.bat withdata`（Mac：`build_firefox.sh withdata`，要先照上面做出詞典資料），做出 `fangfang-firefox-private.xpi`。這個版本有改過的詞典資料，只能選「On your own」，不能公開。

