@echo off
rem Fangfang Cards on Windows: double-click this to make and install the Windows program (it runs install.ps1 windows).
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" windows
echo.
pause
