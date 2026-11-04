@echo off
chcp 936 >nul 2>&1
pushd "%~dp0" >nul 2>&1 || cd /d "%~dp0"
start "scrcpy 等待手机" cmd /c call "%~dp0投屏.bat" --wait
exit /b 0
