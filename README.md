# 方方詞卡（Fangfang Cards）

台語和華語（還有粵語、客語、日語）的詞卡、詞典和練習。

**方方詞卡有兩個部分：**

1. **App**（就是這個 GitHub 專案）：你自己在電腦上建置、安裝。有三個版本：
   - **apple/**：iPhone、iPad 和 Mac 版（Xcode 專案）
   - **android/**：Android 版（Android Studio 專案）
   - **windows/**：電腦版，Windows 用（跟 Android 版同一份程式碼，在電腦上當成一般的程式執行；也可以裝在 Mac 上：`install-mac.command`）
2. **Firefox 擴充功能「方方詞卡」**：在 Firefox 裡查網頁上的詞（台語、華語……），在不認識的詞上面加讀音和意思，在 YouTube 上跟著歌詞，並把詞傳到 App。直接從 Firefox 的附加元件網站安裝，不用建置：
   **https://addons.mozilla.org/en-US/firefox/addon/%E6%96%B9%E6%96%B9%E8%A9%9E%E5%8D%A1/**

兩個部分可以各自使用，一起用的話，擴充功能可以把詞和 YouTube 歌曲傳到 App 裡（電腦版和 Mac 上的 App）。

## 安裝：哪一個版本，用哪一個檔案

先在 GitHub 按 **Code → Download ZIP**，解壓縮到「下載項目」（資料夾叫 `fangfang-cards-main`）。然後照你的電腦和你要的版本：

| 要裝的版本 | 在 Mac 上 | 在 Windows 上 |
|---|---|---|
| **iPhone／iPad** | 終端機：`bash ~/Downloads/fangfang-cards-main/install.sh apple ios` | 不行（要 Mac 和 Xcode） |
| **Mac App**（跟 iPad 上的一樣，要 Apple 晶片） | 終端機：`bash ~/Downloads/fangfang-cards-main/install.sh apple mac` | 不行 |
| **iPhone／iPad 和 Mac App 一起** | 終端機：`bash ~/Downloads/fangfang-cards-main/install.sh apple` | 不行 |
| **電腦版-Windows/Mac**（YouTube 歌詞、浮動歌詞、電台、瑞典語、四川話） | 終端機：`bash ~/Downloads/fangfang-cards-main/install-mac.command`<br>（從 GitHub 下載的 ZIP 裡，這個檔案沒有「可以執行」的權限，雙擊會說「沒有適當的取用權限」：用終端機就沒問題） | 雙擊 `install-windows.bat` |
| **Android**（做一個 APK 檔） | 終端機：`bash ~/Downloads/fangfang-cards-main/install.sh android` | 雙擊 `android-install.bat` |
| **Firefox 擴充功能「方方詞卡」** | 在 Firefox 打開 [附加元件頁](https://addons.mozilla.org/en-US/firefox/addon/%E6%96%B9%E6%96%B9%E8%A9%9E%E5%8D%A1/)，按「Add to Firefox」（中文介面：「新增至 Firefox」） | 同左 |
| **要先裝的東西** | Apple 版：**Xcode 26 以上**（App Store），在 Xcode → Settings → Accounts 用 Apple ID 登入<br>Android：**Android Studio**<br>電腦版：不用（Java、Node.js、FFmpeg 第一次自己下載） | 全部：**Python 3**（安裝時勾選「Add python.exe to PATH」）<br>Android：**Android Studio**<br>電腦版：不用再裝別的（Java 第一次自己下載） |
| **更新** | 再執行一次同一個指令（免費 Apple ID 的 Apple 版：每 7 天一次） | 再雙擊一次同一個檔案 |

（終端機：「應用程式 → 工具程式 → 終端機」。資料夾不在「下載項目」的話，把指令裡的 `~/Downloads/fangfang-cards-main` 換成它所在的地方；也可以把檔案拖進終端機視窗。）

下面是每個版本的詳細說明。

### Mac：install.sh

只輸入 `bash ~/Downloads/fangfang-cards-main/install.sh`（後面不寫什麼）的話，它會問你要裝哪一個：

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

在 Windows 上可以做 **Windows 版**（裝在這台電腦上的程式）和 **Android 版**。iPhone／iPad／Mac 版只能在 Mac 上建置；Windows 版的程式在 Mac 上也可以裝（見下面「Mac 上的電腦版」）。

第一次的話，先安裝 Python 3（https://www.python.org/downloads/ ，安裝時勾選「Add python.exe to PATH」）：要用它從詞典的原始檔案產生詞典資料（只有第一次；之後留在 `%LOCALAPPDATA%\FangfangCards\data`）。

### Windows 版

在資料夾裡**雙擊 `install-windows.bat`**（不需要 Android Studio）。它會：

1. 在這台電腦上做好詞典資料（第一次要幾分鐘），
2. 建置 Windows 版（第一次要下載不少東西，5–10 分鐘；找不到合適的 Java 的話會自己下載一個 Java 21），
3. 裝到 `%LOCALAPPDATA%\Programs\FangfangCards`，開始功能表和桌面上會有「方方詞卡」，
4. 讓 Firefox 查詞的「傳到 App」可以打開它（`fangfangcards://` 連結）。

Windows 版和 Android 版用同一份程式碼（`android/app/src/main/java`），畫面、詞典、練習都一樣；`windows/` 裡只有 Windows 自己的部分（視窗、聲音、電台的播放、備份資料夾、檔案對話框）。Esc 鍵（或滑鼠的「上一頁」鍵）就是 Android 的「返回」。進度和設定在 `%LOCALAPPDATA%\FangfangCards\app`；要在手機和電腦之間帶進度，用備份檔（設定 → 匯出與匯入），或兩邊選同一個備份資料夾（例如 Google 雲端硬碟、OneDrive）。

### Mac 上的電腦版

Windows 版的程式也可以裝在 Mac 上（Apple 晶片或 Intel 都可以，不需要虛擬機器）：在終端機輸入 **`bash ~/Downloads/fangfang-cards-main/install-mac.command`**（雙擊這個檔案的話，Mac 會說「沒有適當的取用權限」：GitHub 的 ZIP 不會留下「可以執行」的權限。要雙擊也可以：先在終端機執行一次 `chmod +x ~/Downloads/fangfang-cards-main/install-mac.command`）。它會：

1. 第一次下載建置要用的 Java 21、整理詞典用的 Node.js、電台用的 FFmpeg（放在 `~/Library/Application Support/FangfangCards`），
2. 建置程式（第一次 5–10 分鐘），
3. 放到「應用程式」：**方方詞卡（電腦版）**，Firefox 查詞的「傳到 App」和「連到方方詞卡」一樣可以用。

跟 Windows 版一模一樣（YouTube 歌詞、浮動歌詞、歌詞對時…）。詞典第一次打開時在程式裡選語言安裝；這台 Mac 用 `install.sh` 做過的詞典（`~/FangfangCards/data`）也會直接用。進度和設定在 `~/Library/Application Support/FangfangCards/app`，備份檔叫 `方方詞卡-Mac-….json`。華語、粵語、日語的朗讀用 Mac 自己的語音（系統設定 → 輔助使用 → 朗讀內容 → 管理語音）。iPad 版（`install.sh`）和電腦版可以同時裝，兩個各自分開。

### Android 版

1. 安裝 Android Studio（https://developer.android.com/studio），打開一次讓它下載 SDK。
2. 在資料夾裡**雙擊 `android-install.bat`**。也可以在 PowerShell 輸入：

       powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\fangfang-cards-main\install.ps1"

做好的 APK 會放在桌面（FangfangCards.apk）；手機用 USB 接著並打開「USB 偵錯」的話，會直接裝上去。
（`install.sh` 是給 Mac 用的，Windows 的 PowerShell 沒有 bash，所以要用 `android-install.bat`／`install.ps1`。）

建置失敗的話，把終端機裡的錯誤訊息傳給 Claude。

### 查詞的附加元件給 Firefox（電腦和 Android）

**一般只要從 Firefox 的附加元件網站安裝就好：** https://addons.mozilla.org/en-US/firefox/addon/%E6%96%B9%E6%96%B9%E8%A9%9E%E5%8D%A1/ 。下面是自己做擴充功能檔案的方法（要改程式或在上架前先試的話）。

Safari 查詞（網頁查詞、影片字幕）也可以裝在 Firefox，包括 Android 手機上的 Firefox。不用先做詞典資料：

- **Windows**：在資料夾裡**雙擊 `build-firefox.bat`**（測試版：雙擊 `build-firefox-test.bat`）。
- **Mac**：在終端機執行 `bash ~/Desktop/fangfang-cards-main/apple/tools/build_firefox.sh`。

桌面會多一個 `fangfang-firefox.xpi`。**裡面沒有任何詞典**（詞典的授權不允許散布改過的版本）：裝好以後打開它的設定頁，在「詞典」選語言按「安裝」，它會下載詞典原本的檔案（先從 [fangfang-data](https://github.com/unoki99/fangfang-data)），在瀏覽器裡整理好。所以這個版本可以公開：在 addons.mozilla.org/developers 第一次按「Submit a New Add-on」，之後在「My Add-ons」打開它按「Upload New Version」，都選「On this site」，審核通過以後大家都能在 Firefox 的附加元件頁找到、安裝。（要先自己試的話：上傳時選「On your own」，下載簽好的檔案，在 Firefox 從檔案安裝；Android：設定 → 關於 Firefox → 連點標誌 5 次 → 回到設定 → 從檔案安裝附加元件。）

只給自己用、把做好的資料直接放進去的版本：`build-firefox.bat withdata`（Mac：`build_firefox.sh withdata`，要先照上面做出詞典資料），做出 `fangfang-firefox-private.xpi`。這個版本有改過的詞典資料，只能選「On your own」，不能公開。

---

Taiwanese and Mandarin word cards, dictionary and practice. `apple/` is the iPhone / iPad / Mac version,
`android/` the Android version. Run `bash install.sh` and pick one.
