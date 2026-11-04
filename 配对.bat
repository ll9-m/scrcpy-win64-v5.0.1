@echo off
chcp 936 >nul 2>&1
setlocal EnableExtensions
pushd "%~dp0" >nul 2>&1 || cd /d "%~dp0"
set "BIN=%~dp0bin"
set "ADB=%BIN%\adb.exe"
set "SAVED=%~dp0config\phone.txt"
set "SCRCPY_ICON_DIR=%BIN%"
set "SCRCPY_SERVER_PATH=%BIN%\scrcpy-server"

if exist "%ADB%" goto have_adb
where adb >nul 2>&1
if errorlevel 1 goto no_adb
set "ADB=adb"
:have_adb

if /i "%~1"=="--manual" goto manual

echo ============================================================
echo   scrcpy 无线配对
echo ============================================================
echo   1. 手机扫码配对      需要网络支持 mDNS 广播
echo   2. 手输 6 位配对码   任何网络都能用
echo.
set /p MODE=直接回车 = 扫码，输入 2 = 手输配对码： 
if /i "%MODE%"=="M" goto manual
if "%MODE%"=="2" goto manual
if not exist "%~dp0scripts\pair-qr.ps1" goto manual

echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\pair-qr.ps1"
if not errorlevel 1 goto qr_done
echo.
echo 扫码配对没有完成，现在改用 6 位配对码方式。
echo.

:manual
echo 手机操作：开发者选项 - 无线调试 - 使用配对码配对设备
echo 请填「配对」弹窗里的地址，不要填无线调试主界面的地址。
set /p PAIR=配对弹窗 IP:端口： 
set /p CODE=6 位配对码： 
if not defined PAIR goto pair_fail
if not defined CODE goto pair_fail
"%ADB%" pair %PAIR% %CODE%
if errorlevel 1 goto pair_fail

echo.
echo 配对成功，正在查找投屏用的连接端口...
ping -n 3 127.0.0.1 >nul
set "WIFI="
for /f "tokens=2,3" %%a in ('"%ADB%" mdns services 2^>nul') do if /i "%%a"=="_adb-tls-connect._tcp" (
  if not defined WIFI set "WIFI=%%b"
)

if defined WIFI (
  echo 找到：%WIFI%
  call :connect "%WIFI%"
  if defined CONNECTED goto connected
  echo 自动连接没有成功。
) else (
  echo 没能自动找到连接端口。
  echo 校园网通常会拦截 mDNS 广播，这一步需要手动填。
)

echo 请在「无线调试」主界面找到「IP 地址和端口」，填在下面。
echo 注意：这里要填主界面的端口，不是刚才配对弹窗里的端口。
set "WIFI="
set /p WIFI=主界面 IP:端口： 
if not defined WIFI goto connect_fail
call :connect "%WIFI%"
if not defined CONNECTED goto connect_fail

:connected
if not exist "%~dp0config" mkdir "%~dp0config" >nul 2>&1
>"%SAVED%" echo(%WIFI%
echo.
echo 已连接：%WIFI%
echo 地址已保存到 config\phone.txt
echo.
set /p START=现在开始投屏吗？[Y/N]： 
if /i "%START%"=="Y" call "%~dp0投屏.bat"
pause
exit /b 0

:qr_done
echo.
pause
exit /b 0

:no_adb
echo.
echo 错误：找不到 adb.exe
echo   期望位置：%ADB%
echo 请确认 bin 目录完整，或重新解压本程序包。
pause
exit /b 1

:pair_fail
echo.
echo 配对失败。请检查 6 位码，并保持配对弹窗不要关闭。
echo 如果提示 protocol fault，说明填成了主界面的端口。
echo 重新打开「使用配对码配对设备」，用弹窗里新出现的端口再试一次。
pause
exit /b 1

:connect_fail
echo.
echo 连接 %WIFI% 失败。
echo 1. 要填「无线调试」主界面上的 IP 和端口，不是配对端口
echo 2. 手机上弹出授权时要点「允许」，并保持手机解锁
echo 3. 手机和电脑必须在同一个 Wi-Fi，最好关掉 VPN
echo 4. 关掉再打开一次「无线调试」，重新配对
pause
exit /b 1

:connect
if "%~1"=="" exit /b 0
set "CONNECTED="
"%ADB%" connect "%~1"
for /f "skip=1 tokens=1,2" %%x in ('"%ADB%" devices 2^>nul') do (
  if /i "%%x"=="%~1" if /i "%%y"=="device" set "CONNECTED=1"
)
if defined CONNECTED (
  echo 连接成功。
) else (
  echo 还没连上。
  "%ADB%" devices
)
exit /b 0
