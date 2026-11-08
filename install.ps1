# 方方詞卡 on Windows: makes the Android app (an APK on the Desktop; onto the phone if it's plugged in).
#   Double-click install.bat, or in PowerShell:
#   powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\fangfang-cards-main\install.ps1"
# (The iPhone / iPad / Mac version can only be built on a Mac: use install.sh there.)
param([string]$What = "android")

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"          # (downloads are much faster without the progress bar)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Here = $PSScriptRoot
if ($What -ne "android") {
    Write-Host "iPhone／iPad／Mac 版只能在 Mac 上建置（在 Mac 的終端機執行 install.sh）。在 Windows 上可以做 Android 版。"
    exit 1
}
$A = Join-Path $Here "android"
$LogDir = Join-Path $env:LOCALAPPDATA "FangfangCards"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir "android-build.log"

function Fail($msg) { Write-Host "✗ $msg"; exit 1 }

# ---- the Android SDK (comes with Android Studio) ----
$Sdk = $env:ANDROID_HOME
if (-not $Sdk) { $Sdk = $env:ANDROID_SDK_ROOT }
if (-not $Sdk) { $Sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
if (-not (Test-Path $Sdk)) {
    Fail "找不到 Android SDK。請先安裝 Android Studio（https://developer.android.com/studio），打開一次，讓它下載 SDK（照它的說明按下一步），再執行一次。"
}

# ---- Java 17–23 (the build tools don't run on newer Java): Android Studio's own Java (its "jbr" folder) first ----
# the version from the "release" file next to it (JAVA_VERSION="21.0.5"), or else by asking java.exe
function Get-JavaMajor($jh) {
    $rel = Join-Path $jh "release"
    if (Test-Path $rel) {
        $t = Get-Content $rel -Raw -ErrorAction SilentlyContinue
        if ($t -match 'JAVA_VERSION="(1\.)?(\d+)') { return [int]$Matches[2] }
    }
    $exe = Join-Path $jh "bin\java.exe"
    if (-not (Test-Path $exe)) { return 0 }
    $line = (& $exe -version 2>&1 | ForEach-Object { "$_" }) -join " "
    if ($line -match 'version "(1\.)?(\d+)') { return [int]$Matches[2] }
    return 0
}
# where Android Studio can be: what Windows knows about it, the usual folders, and any "Android Studio*" folder
$studios = @()
foreach ($k in @("HKLM:\SOFTWARE\Android Studio", "HKCU:\SOFTWARE\Android Studio", "HKLM:\SOFTWARE\WOW6432Node\Android Studio")) {
    $p = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).Path
    if ($p) { $studios += $p }
}
foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:ProgramFiles "Android"), (Join-Path $env:LOCALAPPDATA "Programs"),
                    (Join-Path $env:LOCALAPPDATA "Programs\Android"), "C:\Android", "D:\Program Files\Android", "D:\Android")) {
    if ($root -and (Test-Path $root)) {
        $studios += (Get-ChildItem -Path $root -Directory -Filter "Android Studio*" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }
}
# (a shortcut in the Start menu points at it too)
foreach ($sm in @((Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"), (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"))) {
    if (-not (Test-Path $sm)) { continue }
    foreach ($lnk in (Get-ChildItem -Path $sm -Recurse -Filter "Android Studio*.lnk" -ErrorAction SilentlyContinue)) {
        try {
            $target = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk.FullName).TargetPath
            if ($target) { $studios += (Split-Path (Split-Path $target -Parent) -Parent) }
        } catch {}
    }
}
$candidates = @()
foreach ($s in ($studios | Select-Object -Unique)) { $candidates += (Join-Path $s "jbr"); $candidates += (Join-Path $s "jre") }
$tb = Join-Path $env:LOCALAPPDATA "JetBrains\Toolbox\apps"
if (Test-Path $tb) { $candidates += (Get-ChildItem -Path $tb -Recurse -Directory -Filter jbr -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
if ($env:JAVA_HOME) { $candidates += $env:JAVA_HOME }
foreach ($jroot in @((Join-Path $env:ProgramFiles "Java"), (Join-Path $env:ProgramFiles "Eclipse Adoptium"), (Join-Path $env:ProgramFiles "Microsoft"))) {
    if (Test-Path $jroot) { $candidates += (Get-ChildItem -Path $jroot -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
}
$Java = $null
$seen = @()
foreach ($c in ($candidates | Select-Object -Unique)) {
    if ($c -and (Test-Path (Join-Path $c "bin\java.exe"))) {
        $m = Get-JavaMajor $c
        $seen += "  $c（Java $m）"
        if ($m -ge 17 -and $m -le 23) { $Java = $c; break }
    }
}
# none (new Android Studio comes with Java 25, too new for the build tools): a Java 21 of our own, downloaded once
# from Eclipse Adoptium (free) into %LOCALAPPDATA%\FangfangCards\jdk21
if (-not $Java) {
    $Own = Join-Path $LogDir "jdk21"
    $have = Get-ChildItem -Path $Own -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName "bin\java.exe") } | Select-Object -First 1
    if (-not $have) {
        Write-Host "Android Studio 的 Java 太新了（建置工具要 17–23 版），下載一個 Java 21 給方方詞卡用（只有第一次，大概 200 MB）…"
        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x64" }
        $zip = Join-Path $env:TEMP "fangfang-jdk21.zip"
        try {
            Invoke-WebRequest -Uri "https://api.adoptium.net/v3/binary/latest/21/ga/windows/$arch/jdk/hotspot/normal/eclipse" -OutFile $zip -UseBasicParsing -ErrorAction Stop
            Remove-Item -Recurse -Force $Own -ErrorAction SilentlyContinue
            Expand-Archive -Path $zip -DestinationPath $Own -Force
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
        } catch { Write-Host "（下載 Java 失敗：$($_.Exception.Message)）" }
        $have = Get-ChildItem -Path $Own -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName "bin\java.exe") } | Select-Object -First 1
    }
    if ($have) { $Java = $have.FullName }
}
if (-not $Java) {
    Write-Host "✗ 找不到可以用的 Java（要 17–23 版）。"
    if ($seen) { Write-Host "  找到的（版本不對）："; $seen | ForEach-Object { Write-Host $_ } }
    else { Write-Host "  找不到 Android Studio 裡面的 Java。Android Studio 裝在哪裡？（例如 C:\Program Files\Android\Android Studio）" }
    Write-Host "  可以自己指定：在 PowerShell 先輸入  `$env:JAVA_HOME = `"C:\...\Android Studio\jbr`"  再執行 install.ps1。"
    Write-Host "  把這些訊息傳給 Claude 也可以。"
    exit 1
}
$env:JAVA_HOME = $Java
$env:ANDROID_HOME = $Sdk
Write-Host "（用的 Java：$Java）"
# (forward slashes: Gradle reads them fine, and no escaping is needed)
[IO.File]::WriteAllText((Join-Path $A "local.properties"), "sdk.dir=" + ($Sdk -replace '\\', '/') + "`n")

# ---- the word data, made on this computer from the dictionaries' own files ----
# (their licences don't allow sharing the made files; the Apple and Android versions use the same files)
$Assets = Join-Path $A "app\src\main\assets"
New-Item -ItemType Directory -Force -Path $Assets | Out-Null
$need = @("dict.json", "cards.json", "zh.json") | Where-Object { -not (Test-Path (Join-Path $Assets $_)) }
if ($need) {
    $Apd = Join-Path $Here "apple\FangfangCards"
    $Tools = Join-Path $Here "apple\tools"
    if (-not (Test-Path $Tools)) { Fail "找不到 apple\tools（建立詞典資料要用）。請用完整的 fangfang-cards-main 資料夾。" }

    # Python 3 (python.org): the launcher "py" first, then "python" (not the Microsoft Store shortcut)
    $Py = $null; $PyArgs = @()
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3 --version *> $null
        if ($LASTEXITCODE -eq 0) { $Py = "py"; $PyArgs = @("-3") }
    }
    if (-not $Py -and (Get-Command python -ErrorAction SilentlyContinue)) {
        $v = (& python --version 2>&1) | Out-String
        if ($v -match "Python 3") { $Py = "python" }
    }
    if (-not $Py) {
        Fail "建立詞典資料要用 Python 3。請從 https://www.python.org/downloads/ 安裝（安裝時勾選「Add python.exe to PATH」），再執行一次。"
    }
    $env:PYTHONUTF8 = "1"        # (the scripts read and write UTF-8)

    $Tmp = Join-Path $env:TEMP ("fangfang-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
    function Get-File($url, $name, [switch]$Optional) {
        $dest = Join-Path $Tmp $name
        try { Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop; return $dest }
        catch {
            if ($Optional) { return "-" }
            Fail "下載失敗：$url（$($_.Exception.Message)）"
        }
    }
    $PyLog = Join-Path $Tmp "py.log"
    function Run-Py([string[]]$scriptArgs) {
        & $Py @PyArgs @scriptArgs *> $PyLog
        if ($LASTEXITCODE -ne 0) {
            Get-Content $PyLog -Tail 15 | Write-Host
            Fail "整理資料的時候出錯了（$($scriptArgs[0])）。把上面的訊息傳給 Claude。"
        }
    }
    $raw = "https://raw.githubusercontent.com"
    Push-Location $Tools
    if (-not (Test-Path (Join-Path $Apd "dict.json")) -or -not (Test-Path (Join-Path $Apd "cards.json"))) {
        Write-Host "下載教育部《臺灣台語常用詞辭典》資料（kautian.ods）…"
        $ods = Get-File "https://sutian.moe.edu.tw/media/senn/ods/kautian.ods" "kautian.ods"
        Write-Host "下載 rime-essay 字頻表…"
        $essay = Get-File "$raw/rime/rime-essay/master/essay.txt" "essay.txt"
        Write-Host "整理資料中…（大概 1 分鐘）"
        Run-Py @("ods2csv.py", $ods, (Join-Path $Tmp "sheets.json"))
        Run-Py @("build_moe.py", (Join-Path $Tmp "sheets.json"), "own.json", (Join-Path $Tmp "data2.json"))
        Run-Py @("to_app_data.py", (Join-Path $Tmp "data2.json"), $essay, (Join-Path $Apd "dict.json"))
        Run-Py @("build_cards.py", (Join-Path $Apd "dict.json"), $essay, (Join-Path $Apd "cards.json"))
    }
    if (-not (Test-Path (Join-Path $Apd "zh.json"))) {
        if (-not (Test-Path (Join-Path $Tmp "essay.txt"))) { Get-File "$raw/rime/rime-essay/master/essay.txt" "essay.txt" | Out-Null }
        Write-Host "下載《兩岸常用詞典》、CC-CEDICT、HSK／TOCFL 詞表、《重編國語辭典修訂本》…"
        $csld = Get-File "$raw/g0v/moedict-data-csld/master/dict-csld.json" "dict-csld.json"
        $ced = Get-File "$raw/cschiller/zhongwen/main/data/cedict_ts.u8" "cedict_ts.u8" -Optional
        $hsk = Get-File "$raw/ivankra/hsk30/master/hsk30-expanded.csv" "hsk30.csv" -Optional
        $toc = Get-File "$raw/ivankra/tocfl/master/expanded/tocfl.csv" "tocfl.csv" -Optional
        $rev = Get-File "$raw/g0v/moedict-data/master/dict-revised.json.xz" "dict-revised.json.xz" -Optional
        $hch = Get-File "$raw/ivankra/hsk30/master/hsk30-chars.csv" "hsk30-chars.csv" -Optional
        $tch = Get-File "$raw/ivankra/tocfl/master/tbcl-chars.csv" "tbcl-chars.csv" -Optional
        $ids = Get-File "$raw/cjkvi/cjkvi-ids/master/ids.txt" "ids.txt" -Optional
        Write-Host "整理華語資料中…（大概一分鐘）"
        Run-Py @("build_mandarin.py", $csld, (Join-Path $Tmp "essay.txt"), (Join-Path $Apd "zh.json"), $ced, $hsk, $toc, $rev, $hch, $tch, $ids)
    }
    if (-not (Test-Path (Join-Path $Apd "inputcodes.json"))) {
        Write-Host "下載倉頡、五筆碼表（Rime）…"
        $cj = Get-File "$raw/rime/rime-cangjie/master/cangjie5.base.dict.yaml" "cj.yaml" -Optional
        $cjx = Get-File "$raw/rime/rime-cangjie/master/cangjie5.extended.dict.yaml" "cjx.yaml" -Optional
        $wb = Get-File "$raw/rime/rime-wubi/master/wubi86.dict.yaml" "wb.yaml" -Optional
        $ced2 = if (Test-Path (Join-Path $Tmp "cedict_ts.u8")) { Join-Path $Tmp "cedict_ts.u8" } else { Get-File "$raw/cschiller/zhongwen/main/data/cedict_ts.u8" "cedict_ts.u8" -Optional }
        $liu = Get-ChildItem -Path $Tools -Filter *.cin -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cj -ne "-" -and $cjx -ne "-" -and $wb -ne "-") {
            $icArgs = @("build_inputcodes.py", $cj, $cjx, $wb, (Join-Path $Apd "inputcodes.json"), $(if ($liu) { $liu.FullName } else { "-" }))
            if ($ced2 -ne "-") { $icArgs += $ced2 }
            & $Py @PyArgs @icArgs *> $null
            if ($LASTEXITCODE -ne 0) { Write-Host "（沒辦法建立輸入法拆碼，先跳過）" }
        } else { Write-Host "（沒辦法下載輸入法碼表，先跳過）" }
    }
    Pop-Location
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
    foreach ($f in @("dict.json", "cards.json", "zh.json", "inputcodes.json")) {
        $src = Join-Path $Apd $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $Assets $f) -Force }
    }
    foreach ($f in @("dict.json", "cards.json", "zh.json")) {
        if (-not (Test-Path (Join-Path $Assets $f))) { Fail "詞典資料沒有建好（少了 $f）。" }
    }
}
# 粵語 (yue.json: in the project when it's on GitHub, or made on a Mac with build-data.sh yue)
$yue = Join-Path $Apd "yue.json"
if ((Test-Path $yue) -and -not (Test-Path (Join-Path $Assets "yue.json"))) { Copy-Item $yue (Join-Path $Assets "yue.json") -Force }

# ---- build ----
Write-Host "建置 Android 版…（第一次要下載不少東西，可能 5–10 分鐘）"
Push-Location $A
& .\gradlew.bat assembleDebug --console=plain *> $Log
Pop-Location
$Apk = Join-Path $A "app\build\outputs\apk\debug\app-debug.apk"
$ok = (Test-Path $Apk) -and (Select-String -Path $Log -Pattern "BUILD SUCCESSFUL" -Quiet)
if (-not $ok) {
    Write-Host "✗ 建置失敗。把下面的錯誤訊息傳給 Claude："
    Select-String -Path $Log -Pattern "^e: |error:|What went wrong" -Context 0, 4 | Select-Object -First 30 | ForEach-Object { $_.ToString() }
    Write-Host "（完整紀錄：$Log）"
    exit 1
}
$Desk = [Environment]::GetFolderPath("Desktop")
if (-not $Desk) { $Desk = Join-Path $HOME "Desktop" }
$Out = Join-Path $Desk "FangfangCards.apk"
Copy-Item $Apk $Out -Force
Write-Host "✓ 建置完成：$Out"

# ---- straight onto a phone that's plugged in with USB debugging on ----
$Adb = Join-Path $Sdk "platform-tools\adb.exe"
$phone = $false
if (Test-Path $Adb) { $phone = [bool](& $Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" }) }
if ($phone) {
    Write-Host "安裝到接著的 Android 手機…"
    & $Adb install -r $Out *>> $Log
    if ($LASTEXITCODE -eq 0) { Write-Host "✓ 已安裝到手機" } else { Write-Host "（沒辦法直接安裝；把 APK 傳到手機上點它安裝就好）" }
} else {
    Write-Host "把 FangfangCards.apk 傳到 Android 手機（email、Google Drive、聊天軟體…），在手機上點它安裝。"
    Write-Host "（或是用 USB 線接上手機、打開「USB 偵錯」，再執行一次，就會直接裝上去。）"
}
