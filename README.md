# 方方詞卡（Fangfang Cards）

台語和華語的詞卡、詞典和練習。這個資料夾裡有三個版本：

- **apple/**：iPhone、iPad 和 Mac 版（Xcode 專案）
- **android/**：Android 版（Android Studio 專案）
- **windows/**：Windows 版（用的是 Android 版同一份程式碼，在 Windows 上當成一般的程式執行）

## 安裝

打開「終端機」（Terminal），輸入下面這一行，按 Enter（資料夾在「下載項目」的話）：

    bash ~/Downloads/fangfang-cards-main/install.sh

它會問你要裝哪一個：

1. iPhone／iPad 和 Mac
2. 只有 iPhone／iPad
3. 只有 Mac
4. Android（做一個 APK 檔）

也可以直接寫：`install.sh apple`、`install.sh apple ios`、`install.sh apple mac`、`install.sh android`。

**Apple 版**需要 Xcode 26 以上（App Store 免費下載），並在 Xcode → Settings → Accounts 用 Apple ID 登入。
iPhone／iPad 要用 USB 接上 Mac（第一次要在手機上按「信任」）。用免費的 Apple ID 安裝的話，每 7 天再執行一次就好，詞卡進度都會留著。
詳細說明在 `apple/README.md`。

**Android 版**需要 Android Studio（免費：https://developer.android.com/studio），放在「應用程式」資料夾，打開一次讓它下載 SDK（它裡面也有建置要用的 Java）。
做好的 APK 會放在桌面（FangfangCards.apk），傳到手機上點它安裝；手機用 USB 接著並打開「USB 偵錯」的話，會直接裝上去。
詳細說明在 `android/README.md`。

**詞典資料**：教育部和中華文化總會的詞典授權不允許散布整理過的資料檔，所以這裡沒有那些檔案。詞典**原始檔案的副本**在另一個儲存庫 [unoki99/fangfang-data](https://github.com/unoki99/fangfang-data)（App 和安裝程式先從那裡下載，下載不到才去原本的網站），每個檔案依照它自己的授權（見那裡的 README.md），**不在本專案的 MIT 授權範圍內**。第一次安裝的時候，`install.sh` 會在你自己的電腦上從原始的詞典檔案產生（要網路，幾分鐘；需要 Mac 內建的 Python 3）。Apple 版和 Android 版用同一份資料。Android 版的詞典（台語、華語、粵語、客語、日語、說文解字）都在電腦上做好、放進 App 裡（在手機上做大的詞典會記憶體不足）；日語和說文解字用 Node.js 做，沒有的話安裝程式會自己下載一個（只有第一次）。資料來源和授權見 `apple/README.md` 的「資料來源與授權」。

## Windows

在 Windows 上可以做 **Windows 版**（裝在這台電腦上的程式）和 **Android 版**。iPhone／iPad／Mac 版只能在 Mac 上建置。

第一次的話，先安裝 Python 3（https://www.python.org/downloads/ ，安裝時勾選「Add python.exe to PATH」）：要用它從詞典的原始檔案產生詞典資料（只有第一次；之後留在 `%LOCALAPPDATA%\FangfangCards\data`）。

### Windows 版

在資料夾裡**雙擊 `install-windows.bat`**（不需要 Android Studio）。它會：

1. 在這台電腦上做好詞典資料（第一次要幾分鐘），
2. 建置 Windows 版（第一次要下載不少東西，5–10 分鐘；找不到合適的 Java 的話會自己下載一個 Java 21），
3. 裝到 `%LOCALAPPDATA%\Programs\FangfangCards`，開始功能表和桌面上會有「方方詞卡」，
4. 讓 Firefox 查詞的「傳到 App」可以打開它（`fangfangcards://` 連結）。

Windows 版和 Android 版用同一份程式碼（`android/app/src/main/java`），畫面、詞典、練習都一樣；`windows/` 裡只有 Windows 自己的部分（視窗、聲音、電台的播放、備份資料夾、檔案對話框）。Esc 鍵（或滑鼠的「上一頁」鍵）就是 Android 的「返回」。進度和設定在 `%LOCALAPPDATA%\FangfangCards\app`；要在手機和電腦之間帶進度，用備份檔（設定 → 匯出與匯入），或兩邊選同一個備份資料夾（例如 Google 雲端硬碟、OneDrive）。

### Android 版

1. 安裝 Android Studio（https://developer.android.com/studio），打開一次讓它下載 SDK。
2. 在資料夾裡**雙擊 `android-install.bat`**。也可以在 PowerShell 輸入：

       powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\fangfang-cards-main\install.ps1"

做好的 APK 會放在桌面（FangfangCards.apk）；手機用 USB 接著並打開「USB 偵錯」的話，會直接裝上去。
（`install.sh` 是給 Mac 用的，Windows 的 PowerShell 沒有 bash，所以要用 `android-install.bat`／`install.ps1`。）

建置失敗的話，把終端機裡的錯誤訊息傳給 Claude。

### 查詞的附加元件給 Firefox（電腦和 Android）

Safari 查詞（網頁查詞、影片字幕）也可以裝在 Firefox，包括 Android 手機上的 Firefox。Firefox 的版本是另外一個檔案（`fangfang-firefox.zip`），不在這個儲存庫裡；也可以在 Firefox 的附加元件頁找「方方詞卡 查詞」安裝。

**裡面沒有任何詞典**（詞典的授權不允許散布改過的版本）：裝好以後打開它的設定頁，在「詞典」選語言按「安裝」，它會下載詞典原本的檔案（先從 [fangfang-data](https://github.com/unoki99/fangfang-data)），在瀏覽器裡整理好。所以這個版本可以公開：在 addons.mozilla.org/developers 第一次按「Submit a New Add-on」，之後在「My Add-ons」打開它按「Upload New Version」，都選「On this site」，審核通過以後大家都能在 Firefox 的附加元件頁找到、安裝。（要先自己試的話：Firefox 網址列打 about:debugging → 這個 Firefox → 載入暫時的附加元件 → 選這個檔案；或上傳時選「On your own」，下載簽好的檔案，在 Firefox 從檔案安裝；Android：設定 → 關於 Firefox → 連點標誌 5 次 → 回到設定 → 從檔案安裝附加元件。）

---

Taiwanese and Mandarin word cards, dictionary and practice. `apple/` is the iPhone / iPad / Mac version,
`android/` the Android version. Run `bash install.sh` and pick one.
