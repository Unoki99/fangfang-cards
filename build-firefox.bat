@echo off
rem Fangfang Cards: double-click this to make the Firefox add-on (it runs build-firefox.ps1; "build-firefox.bat withdata": with your own data, for yourself only).
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-firefox.ps1" %*
echo.
pause
