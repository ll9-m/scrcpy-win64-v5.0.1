@echo off
chcp 936 >nul 2>&1
setlocal EnableExtensions
pushd "%~dp0" >nul 2>&1 || cd /d "%~dp0"
set "BIN=%~dp0bin"
set "ADB=%BIN%\adb.exe"
set "SCRCPY=%BIN%\scrcpy.exe"
set "SAVED=%~dp0config\phone.txt"
rem 图标和服务端按 exe 所在目录查找，这里显式指定，不依赖当前工作目录
set "SCRCPY_ICON_DIR=%BIN%"
set "SCRCPY_SERVER_PATH=%BIN%\scrcpy-server"
set "WAIT="
set "HINTED="
if /i "%~1"=="--wait" set "WAIT=1"

call :check_bin
if errorlevel 1 exit /b 1

:discover
set "SERIAL="
set "USB="
set "CONNECTED="
set "TARGET="
set "UNAUTH="
set "OFFLINE="

rem 跳过模拟器，否则它会被当成 USB 设备抢走这次投屏
for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices 2^>nul') do (
  if /i "%%b"=="device" (
    echo %%a | findstr /i /b /c:"emulator-" >nul || call :consider "%%a"
  )
  if /i "%%b"=="unauthorized" set "UNAUTH=1"
  if /i "%%b"=="offline" set "OFFLINE=1"
)

if defined SERIAL goto run

if defined USB (
  set "SERIAL=%USB%"
  goto run
)

rem phone.txt 可能为空、被记事本写成带 BOM、或有空行，只接受严格合法的 IPv4:端口
if exist "%SAVED%" for /f "usebackq delims=" %%t in ("%SAVED%") do (
  if not defined TARGET (
    echo %%t | findstr /r /c:"^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*:[0-9][0-9]*$" >nul && set "TARGET=%%t"
  )
)
if defined TARGET call :connect "%TARGET%"
if defined CONNECTED goto run

for /f "tokens=2,3" %%a in ('"%ADB%" mdns services 2^>nul') do if "%%a"=="_adb-tls-connect._tcp" (
  call :connect "%%b"
  if defined CONNECTED goto run
)

if defined WAIT (
  if defined UNAUTH if not defined HINTED (
    echo USB 调试未授权：解锁手机，点弹窗里的「允许」
    set "HINTED=1"
  )
  if defined OFFLINE if not defined HINTED (
    echo 设备离线：重新插拔 USB，或关掉再打开一次无线调试
    set "HINTED=1"
  )
  echo 等待手机中...
  ping -n 16 127.0.0.1 >nul
  goto discover
)

echo 没有找到手机，请检查：
echo 1. 手机和电脑在同一个 Wi-Fi
echo 2. 手机的「无线调试」已经打开
echo 3. 先运行一次「配对.bat」
if defined UNAUTH echo USB 调试未授权：解锁手机，点弹窗里的「允许」
if defined OFFLINE echo 设备离线：重新插拔 USB，或关掉再打开一次无线调试
echo 5 秒后退出。想一直等待，请用「等待投屏.bat」
ping -n 6 127.0.0.1 >nul
exit /b 1

:consider
rem 网络设备优先于 USB 设备，同类只取第一个
echo %~1 | findstr ":" >nul
if not errorlevel 1 (
  if not defined SERIAL set "SERIAL=%~1"
) else (
  if not defined USB set "USB=%~1"
)
exit /b 0

:connect
if "%~1"=="" exit /b 0
"%ADB%" connect "%~1" >nul 2>&1
for /f "skip=1 tokens=1,2" %%x in ('"%ADB%" devices 2^>nul') do (
  if /i "%%x"=="%~1" if /i "%%y"=="device" (
    set "SERIAL=%%x"
    set "CONNECTED=1"
  )
)
if defined CONNECTED call :remember "%~1"
exit /b 0

:remember
if not exist "%~dp0config" mkdir "%~dp0config" >nul 2>&1
>"%SAVED%" echo(%~1
exit /b 0

:check_bin
if exist "%SCRCPY%" goto check_adb
echo 错误：找不到 scrcpy.exe
echo   期望位置：%SCRCPY%
echo 请确认 bin 目录完整，或重新解压本程序包。
pause
exit /b 1
:check_adb
if exist "%ADB%" exit /b 0
where adb >nul 2>&1
if errorlevel 1 (
  echo 错误：找不到 %ADB%
  echo 系统 PATH 里也没有 adb，请重新解压本程序包。
  pause
  exit /b 1
)
set "ADB=adb"
echo 警告：bin\adb.exe 不存在，改用系统 PATH 里的 adb。
echo       版本不一致可能导致配对和发现异常。
exit /b 0

:run
if defined SERIAL (
  "%SCRCPY%" -s "%SERIAL%" --max-size=1280 --max-fps=60 --keep-active --always-on-top
) else (
  "%SCRCPY%" --max-size=1280 --max-fps=60 --keep-active --always-on-top
)
exit /b 0
