@echo off
chcp 936 >nul 2>&1
setlocal EnableExtensions
pushd "%~dp0" >nul 2>&1 || cd /d "%~dp0"

if not exist "%~dp0lib\shortcut.ps1" (
  echo 错误：找不到 tools\lib\shortcut.ps1，请确认目录完整。
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\shortcut.ps1"
if errorlevel 1 (
  echo.
  echo 创建失败，请把上面的报错发出来。
) else (
  echo.
  echo 桌面上应该已经出现「投屏」图标，双击即可打开菜单。
)
echo.
pause
exit /b 0
