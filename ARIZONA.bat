@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Arizona_Main_Donor_Launcher_BANNED_IS_MAIN_FIXED.ps1"
endlocal
