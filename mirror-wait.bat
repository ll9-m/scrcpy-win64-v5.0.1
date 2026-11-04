@echo off
cd /d "%~dp0"
start "scrcpy" cmd /c "mirror.bat --wait"
exit /b 0
