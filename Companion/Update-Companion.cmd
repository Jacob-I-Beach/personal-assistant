@echo off
powershell.exe -NoProfile -File "%~dp0scripts\install-update.ps1"
if errorlevel 1 echo The update needs attention. The previous package and saved data were preserved.
pause
