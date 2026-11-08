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
$Apd = Join-Path $Here "apple\FangfangCards"
# the data made once is kept in %LOCALAPPDATA%\FangfangCards\data, so a new download of the project, put over the
# old one, doesn't have to make it again
$Keep = Join-Path $env:LOCALAPPDATA "FangfangCards\data"
New-Item -ItemType Directory -Force -Path $Keep | Out-Null
# (粵語 data made by an older version: made again)
foreach ($y in @((Join-Path $Keep "yue.json"), (Join-Path $Assets "yue.json"), (Join-Path $Apd "yue.json"))) {
    if (Test-Path $y) {
        $fs = [IO.File]::OpenRead($y); $buf = New-Object byte[] 80; $n = $fs.Read($buf, 0, 80); $fs.Close()
        if (-not ([Text.Encoding]::UTF8.GetString($buf, 0, $n)).Contains('"v":2')) { Remove-Item $y -Force }
    }
}
foreach ($f in @("dict.json", "cards.json", "zh.json", "inputcodes.json", "yue.json", "hak.json", "tw_en.json")) {
    $k = Join-Path $Keep $f
    if ((Test-Path $k) -and -not (Test-Path (Join-Path $Assets $f))) { Copy-Item $k (Join-Path $Assets $f) -Force }
}
# (what's made already isn't made again: the files in the app's assets count too)
New-Item -ItemType Directory -Force -Path $Apd | Out-Null
foreach ($f in @("dict.json", "cards.json", "zh.json", "inputcodes.json")) {
    $as = Join-Path $Assets $f
    if ((Test-Path $as) -and -not (Test-Path (Join-Path $Apd $f))) { Copy-Item $as (Join-Path $Apd $f) -Force }
}
# (粵語 already in the project, when it's on GitHub)
$yue = Join-Path $Apd "yue.json"
if ((Test-Path $yue) -and -not (Test-Path (Join-Path $Assets "yue.json"))) { Copy-Item $yue (Join-Path $Assets "yue.json") -Force }
# (客語 and the 台語 words' English too: each step below only makes what isn't there)
$need = @("dict.json", "cards.json", "zh.json", "yue.json", "hak.json", "tw_en.json") | Where-Object { -not (Test-Path (Join-Path $Assets $_)) }
if ($need) {
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
        # (the TOCFL list has moved before: try each place it has been)
        $toc = "-"
        foreach ($u in @("expanded/tocfl.csv", "tocfl.csv", "expanded/tbcl.csv", "tbcl.csv")) {
            $toc = Get-File "$raw/ivankra/tocfl/master/$u" "tocfl.csv" -Optional
            if ($toc -eq "-") { continue }
            # (a link to another file, e.g. expanded/tocfl.csv -> tocfl-202307.csv: GitHub gives the name it points to)
            $txt = (Get-Content $toc -Raw -Encoding UTF8).Trim()
            if ((Get-Item $toc).Length -lt 300 -and $txt -match '^[A-Za-z0-9_./-]+\.csv$') {
                $dir = Split-Path $u -Parent
                $to = if ($dir) { "$dir/$txt".Replace('\', '/') } else { $txt }
                $toc = Get-File "$raw/ivankra/tocfl/master/$to" "tocfl.csv" -Optional
                if ($toc -eq "-") { continue }
            }
            break
        }
        if ($toc -eq "-") { Write-Host "  ⚠ 下載不到 TOCFL 詞表：華語的 TOCFL 只會有漢字卡，沒有詞的等級。" }
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
    # 粵語: CC-CEDICT + CC-Canto, rime-cantonese, 開放粵語字典, and Wiktionary (kaikki.org) when its file is in
    # Downloads or on the Desktop
    if (-not (Test-Path (Join-Path $Apd "yue.json")) -and -not (Test-Path (Join-Path $Assets "yue.json"))) {
        Write-Host "下載粵語資料（CC-CEDICT、CC-Canto、rime-cantonese、開放粵語字典）…"
        $ok = $true
        foreach ($pair in @(
            @("$raw/cschiller/zhongwen/main/data/cedict_ts.u8", "cedict_ts.u8"),
            @("$raw/aaronhktan/jyut-dict/main/src/dictionaries/cedict/data/CC-CANTO.txt", "CC-CANTO.txt"),
            @("$raw/aaronhktan/jyut-dict/main/src/dictionaries/cedict/data/READINGS.txt", "READINGS.txt"),
            @("$raw/rime/rime-cantonese/main/jyut6ping3.words.dict.yaml", "jyut6ping3.words.dict.yaml"),
            @("$raw/rime/rime-cantonese/main/jyut6ping3.chars.dict.yaml", "jyut6ping3.chars.dict.yaml"),
            @("$raw/rime/rime-cantonese/main/essay-cantonese.txt", "essay-cantonese.txt"),
            @("$raw/kfcd/yyzd/master/dist/tsv/%E7%B9%81%E9%AB%94/%E7%B2%B5%E8%AA%9E%E5%AD%97%E5%85%B8_%28%E7%B2%B5%E6%8B%BC%29.txt", "yyzd.txt"))) {
            $got = Get-File $pair[0] $pair[1] -Optional
            if ($got -eq "-") { $ok = $false }
        }
        $kk = "-"
        foreach ($c in @((Join-Path $env:USERPROFILE "Downloads\kaikki.org-dictionary-Chinese.jsonl"), (Join-Path $env:USERPROFILE "Desktop\kaikki.org-dictionary-Chinese.jsonl"))) {
            if ($kk -eq "-" -and (Test-Path $c)) { $kk = $c }
        }
        if ($kk -eq "-") { Write-Host "（找不到維基詞典的檔案 kaikki.org-dictionary-Chinese.jsonl：粵語先不用它，沒有例句和華語對照）" }
        if ($ok) {
            Write-Host "整理粵語資料中…（有維基詞典的話要幾分鐘）"
            & $Py @PyArgs "build_cantonese.py" $Tmp (Join-Path $Apd "yue.json") $kk *> $PyLog
            if ($LASTEXITCODE -ne 0) { Get-Content $PyLog -Tail 8 | Write-Host; Write-Host "（沒辦法建立粵語資料，先跳過）" }
        } else { Write-Host "（下載不到粵語資料，先跳過：App 裡的粵語會打不開）" }
    }
    # 客語: 教育部《臺灣客語辭典》, one file per accent (CC BY-ND 3.0 TW: made here, not shared)
    if (-not (Test-Path (Join-Path $Apd "hak.json")) -and -not (Test-Path (Join-Path $Assets "hak.json"))) {
        Write-Host "下載教育部《臺灣客語辭典》資料（四縣、海陸、大埔、饒平、詔安、南四縣）…"
        $HakDir = Join-Path $Tmp "hak"
        New-Item -ItemType Directory -Force -Path $HakDir | Out-Null
        $hb = "https://hakkadict.moe.edu.tw/static/resource/%E5%AE%A2%E8%AA%9E%E8%B3%87%E6%BA%90%E4%B8%8B%E8%BC%89/%E6%9C%AC%E8%BE%AD%E5%85%B8%E7%9A%84%E6%96%87%E5%AD%97"
        $hakOk = $true
        foreach ($acc in @("四縣", "海陸", "大埔", "饒平", "詔安", "南四縣")) {
            $name = $acc + "腔詞條詞目文字.ods"
            try { Invoke-WebRequest -Uri ("$hb/" + [uri]::EscapeDataString($name)) -OutFile (Join-Path $HakDir $name) -UseBasicParsing -ErrorAction Stop }
            catch { if ($acc -eq "四縣") { $hakOk = $false }; Write-Host "  （下載不到$($acc)腔，先跳過）" }
        }
        if ($hakOk) {
            $es = if (Test-Path (Join-Path $Tmp "essay.txt")) { Join-Path $Tmp "essay.txt" } else { Get-File "$raw/rime/rime-essay/master/essay.txt" "essay.txt" -Optional }
            $ce = if (Test-Path (Join-Path $Tmp "cedict_ts.u8")) { Join-Path $Tmp "cedict_ts.u8" } else { Get-File "$raw/cschiller/zhongwen/main/data/cedict_ts.u8" "cedict_ts.u8" -Optional }
            Write-Host "整理客語資料中…"
            & $Py @PyArgs "build_hakka.py" $HakDir (Join-Path $Apd "hak.json") $es $ce *> $PyLog
            if ($LASTEXITCODE -ne 0) { Get-Content $PyLog -Tail 8 | Write-Host; Write-Host "（沒辦法建立客語資料，先跳過）" }
        } else { Write-Host "（下載不到客語資料，先跳過：App 裡的客語會打不開）" }
    }
    # 台語 words' English: Wiktionary (kaikki.org), the file in Downloads / on the Desktop, or read straight from kaikki.org
    $dj = Join-Path $Apd "dict.json"
    if (-not (Test-Path $dj)) { $dj = Join-Path $Assets "dict.json" }
    if ((Test-Path $dj) -and -not (Test-Path (Join-Path $Apd "tw_en.json")) -and -not (Test-Path (Join-Path $Assets "tw_en.json"))) {
        $kk = "-"
        foreach ($c in @((Join-Path $env:USERPROFILE "Downloads\kaikki.org-dictionary-Chinese.jsonl"), (Join-Path $env:USERPROFILE "Desktop\kaikki.org-dictionary-Chinese.jsonl"))) {
            if ($kk -eq "-" -and (Test-Path $c)) { $kk = $c }
        }
        if ($kk -eq "-") { Write-Host "從 kaikki.org 讀維基詞典的中文資料（檔案很大，要等一陣子；不會存到電腦裡）…" }
        Write-Host "整理台語詞的英文解釋（維基詞典）…"
        & $Py @PyArgs "build_tw_english.py" $dj (Join-Path $Apd "tw_en.json") $kk *> $PyLog
        if ($LASTEXITCODE -ne 0) { Get-Content $PyLog -Tail 8 | Write-Host; Write-Host "（沒辦法建立台語詞的英文解釋，先跳過）" }
    }
    Pop-Location
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
    foreach ($f in @("dict.json", "cards.json", "zh.json", "inputcodes.json", "yue.json", "hak.json", "tw_en.json")) {
        $src = Join-Path $Apd $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $Assets $f) -Force }
    }
    foreach ($f in @("dict.json", "cards.json", "zh.json")) {
        if (-not (Test-Path (Join-Path $Assets $f))) { Fail "詞典資料沒有建好（少了 $f）。" }
    }
}
# keep what was made (for the next time)
foreach ($f in @("dict.json", "cards.json", "zh.json", "inputcodes.json", "yue.json", "hak.json", "tw_en.json")) {
    $src = Join-Path $Assets $f
    if ((Test-Path $src) -and -not (Test-Path (Join-Path $Keep $f))) { Copy-Item $src (Join-Path $Keep $f) -Force }
}

# copies of source files left by putting a new download over the old folder ("Dict 2.kt", "Dict - Copy.kt",
# "Dict (1).kt"): the same code twice, which the build can't tell apart
Get-ChildItem -Path (Join-Path $A "app\src") -Recurse -File -Include "* 2.kt", "* - Copy.kt", "* (1).kt", "* - Kopia.kt" -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host "（刪掉多出來的複本：$($_.Name)）"; Remove-Item $_.FullName -Force }

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
