@echo off
chcp 936 >nul 2>&1
setlocal EnableExtensions
pushd "%~dp0" >nul 2>&1 || cd /d "%~dp0"

if not exist "%~dp0lib\pack.ps1" (
  echo 错误：找不到 tools\lib\pack.ps1，请确认目录完整。
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\pack.ps1"
if errorlevel 1 (
  echo.
  echo 打包失败，请把上面的报错发出来。
  pause
  exit /b 1
)

echo.
echo 产物在 dist 目录里，可以直接发给别人。
pause
exit /b 0
