# 方方詞卡 查詞 for Firefox (on a computer, and on Android), made on Windows: the same add-on as Safari's, packed as
# one file, fangfang-firefox.xpi on the Desktop.
#
# Without any dictionary inside (the dictionaries' licenses don't allow sharing changed versions): it comes with the
# app's converters (apple\FangfangCards\Install\*.js, put in install\), and its settings page (詞典) downloads the
# dictionaries' original files and makes the lookup files in the browser. So it can be shared, and listed on
# addons.mozilla.org for everyone. Nothing else is needed (no Python, no android-install.bat).
#   Double-click build-firefox.bat, or in PowerShell:
#   powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\fangfang-cards-main\build-firefox.ps1"
#
# withdata: with the lookup files made from the data android-install.bat made on this computer inside it (needs Python 3);
# fangfang-firefox-private.xpi. Only for yourself (sign it "On your own", never listed).
#   build-firefox.bat withdata
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$Here = $PSScriptRoot
function Fail($msg) { Write-Host "✗ $msg"; exit 1 }
$With = ($args -contains "withdata")

$Code = Join-Path $Here "apple\FangfangSafari"
$Conv = Join-Path $Here "apple\FangfangCards\Install"
$Tool = Join-Path $Here "apple\tools\build_safari.py"
if (-not (Test-Path $Code) -or -not (Test-Path $Conv)) { Fail "找不到 apple\FangfangSafari 或 apple\FangfangCards\Install。請用完整的 fangfang-cards-main 資料夾。" }

$Tmp = Join-Path $env:TEMP ("fangfang-firefox-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
try {
    if ($With) {
        # the word data android-install.bat made: kept in %LOCALAPPDATA%\FangfangCards\data, and in the Android app's assets
        $Data = $null
        foreach ($d in @((Join-Path $env:LOCALAPPDATA "FangfangCards\data"), (Join-Path $Here "android\app\src\main\assets"))) {
            if ((Test-Path (Join-Path $d "dict.json")) -and (Test-Path (Join-Path $d "zh.json"))) { $Data = $d; break }
        }
        if (-not $Data) { Fail "還沒有詞典資料：先執行一次 android-install.bat（它會做出資料），再執行這個。" }
        # Python 3 (python.org): the launcher "py" first, then "python"
        $Py = $null; $PyArgs = @()
        if (Get-Command py -ErrorAction SilentlyContinue) {
            & py -3 --version *> $null
            if ($LASTEXITCODE -eq 0) { $Py = "py"; $PyArgs = @("-3") }
        }
        if (-not $Py -and (Get-Command python -ErrorAction SilentlyContinue)) {
            $v = (& python --version 2>&1) | Out-String
            if ($v -match "Python 3") { $Py = "python" }
        }
        if (-not $Py) { Fail "要用 Python 3。請從 https://www.python.org/downloads/ 安裝（勾選「Add python.exe to PATH」），再執行一次。" }
        $env:PYTHONUTF8 = "1"
        Write-Host "整理查詞的資料…（大概 1 分鐘）"
        & $Py @PyArgs $Tool $Data $Tmp
        if ($LASTEXITCODE -ne 0) { Fail "整理資料的時候出錯了。把上面的訊息傳給 Claude。" }
    }
    # the add-on's own files (not the Safari-only ones, not old data)
    Get-ChildItem $Code -File | Where-Object { $_.Extension -notin @(".swift", ".plist") -and $_.Name -notlike "d-*.json" } |
        ForEach-Object { Copy-Item $_.FullName (Join-Path $Tmp $_.Name) -Force }
    # the app's converters, for installing the dictionaries in the browser
    $Inst = Join-Path $Tmp "install"
    New-Item -ItemType Directory -Force -Path $Inst | Out-Null
    foreach ($f in @("common.js", "taigi.js", "mandarin.js", "cantonese.js", "hakka.js", "swedish.js", "twown.json")) {
        Copy-Item (Join-Path $Conv $f) (Join-Path $Inst $f) -Force
    }
    $Desk = [Environment]::GetFolderPath("Desktop")
    $Name = "fangfang-firefox"
    if ($With) { $Name = "fangfang-firefox-private" }
    $Out = Join-Path $Desk "$Name.xpi"
    Remove-Item $Out -Force -ErrorAction SilentlyContinue
    # (packed here, not with Compress-Archive: it writes folders as install\x.js, which Firefox refuses; the names
    # in an add-on have to use /)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Root = (Resolve-Path $Tmp).Path.TrimEnd("\")
    $Zip = [System.IO.Compression.ZipFile]::Open($Out, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        Get-ChildItem $Root -Recurse -File | ForEach-Object {
            $Rel = $_.FullName.Substring($Root.Length + 1).Replace("\", "/")
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Zip, $_.FullName, $Rel, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally {
        $Zip.Dispose()
    }
    $mb = [math]::Round((Get-Item $Out).Length / 1MB, 1)
    Write-Host "✓ $Out（$mb MB）"
    Write-Host ""
    if ($With) {
        Write-Host "這個版本裡面有詞典的資料：只能給你自己用。在 addons.mozilla.org/developers 上傳時一定要選「On your own」（不公開）。"
    } else {
        Write-Host "這個版本裡面沒有詞典，可以公開："
        Write-Host "1. 在 addons.mozilla.org/developers 登入。第一次按「Submit a New Add-on」；之後到「My Add-ons」打開方方詞卡 查詞，按「Upload New Version」（再按 Submit a New Add-on 會出現「Duplicate add-on ID」）。"
        Write-Host "2. 選「On this site」（公開上架），上傳這個檔案。問要不要附原始碼（source code）的時候選「No」：裡面的程式都沒有壓縮或產生過。"
        Write-Host "3. 審核通過以後，在 Firefox 的附加元件頁就找得到，大家都可以安裝；第一次打開會到設定頁的「詞典」選語言安裝。"
    }
} finally {
    Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
