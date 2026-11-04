@echo off
pushd "%~dp0" >nul 2>&1 || cd /d "%~dp0"
start "scrcpy" cmd /c call "%~dp0mirror.bat" --wait
exit /b 0
