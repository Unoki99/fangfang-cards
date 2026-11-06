# 方方詞卡（Fangfang Cards）

台語和華語的詞卡、詞典和練習。這個資料夾裡有兩個版本：

- **apple/**：iPhone、iPad 和 Mac 版（Xcode 專案）
- **android/**：Android 版（Android Studio 專案）

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

**詞典資料**：教育部和中華文化總會的詞典授權不允許散布整理過的資料檔，所以這裡沒有那些檔案。第一次安裝的時候，`install.sh` 會在你自己的電腦上從原始的詞典檔案產生（要網路，幾分鐘；需要 Mac 內建的 Python 3）。Apple 版和 Android 版用同一份資料。資料來源和授權見 `apple/README.md` 的「資料來源與授權」。

## Windows（只有 Android 版）

iPhone／iPad／Mac 版只能在 Mac 上建置。在 Windows 上可以做 Android 版：

1. 安裝 Android Studio（https://developer.android.com/studio），打開一次讓它下載 SDK。
2. 第一次的話，安裝 Python 3（https://www.python.org/downloads/ ，安裝時勾選「Add python.exe to PATH」）：要用它從詞典的原始檔案產生詞典資料。（資料夾裡已經有詞典資料的話不需要。）
3. 在資料夾裡**雙擊 `install.bat`**。也可以在 PowerShell 輸入：

       powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\fangfang-cards-main\install.ps1"

做好的 APK 會放在桌面（FangfangCards.apk）；手機用 USB 接著並打開「USB 偵錯」的話，會直接裝上去。
（`install.sh` 是給 Mac 用的，Windows 的 PowerShell 沒有 bash，所以要用 `install.bat`／`install.ps1`。）

建置失敗的話，把終端機裡的錯誤訊息傳給 Claude。

---

Taiwanese and Mandarin word cards, dictionary and practice. `apple/` is the iPhone / iPad / Mac version,
`android/` the Android version. Run `bash install.sh` and pick one.
