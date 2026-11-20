@echo off
rem Fangfang Cards on Windows: double-click this to make the Android app (it runs install.ps1).
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
