@echo off
chcp 936 >nul 2>&1
setlocal EnableExtensions
pushd "%~dp0" >nul 2>&1 || cd /d "%~dp0"
set "BIN=%~dp0bin"
set "ADB=%BIN%\adb.exe"
set "SCRCPY=%BIN%\scrcpy.exe"
set "SAVED=%~dp0config\phone.txt"
set "DEVDIR=%~dp0config\devices"
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
set "CONNECTED="
set "TARGET="
set "UNAUTH="
set "OFFLINE="
set "SER1="
set "SER2="
set "SER3="
set "SER4="

rem 跳过模拟器，否则它会被当成真机抢走这次投屏
for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices 2^>nul ^<nul') do (
  if /i "%%b"=="device" (
    echo %%a | findstr /i /b /c:"emulator-" >nul || call :collect "%%a"
  )
  if /i "%%b"=="unauthorized" set "UNAUTH=1"
  if /i "%%b"=="offline" set "OFFLINE=1"
)

if not defined SER1 goto try_saved
if not defined SER2 (
  set "SERIAL=%SER1%"
  goto run
)
rem 多台设备同时在线：等待模式不打断流程，直接取第一台
if defined WAIT (
  set "SERIAL=%SER1%"
  goto run
)
call :choose
if defined SERIAL goto run

:try_saved
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

:collect
rem 同一台手机可能同时以 IP 和 mDNS 实例名出现，只保留 IP 那种
echo %~1 | findstr /i "_adb-tls-" >nul
if not errorlevel 1 exit /b 0
if not defined SER1 (
  set "SER1=%~1"
  exit /b 0
)
if not defined SER2 (
  set "SER2=%~1"
  exit /b 0
)
if not defined SER3 (
  set "SER3=%~1"
  exit /b 0
)
set "SER4=%~1"
exit /b 0

:choose
echo.
echo 发现多台设备，请选择用来投屏的一台：
echo   1. %SER1%
if defined SER2 echo   2. %SER2%
if defined SER3 echo   3. %SER3%
if defined SER4 echo   4. %SER4%
echo.
set /p PICK=输入序号后回车（直接回车用第 1 台）： 
if "%PICK%"=="2" set "SERIAL=%SER2%"
if "%PICK%"=="3" set "SERIAL=%SER3%"
if "%PICK%"=="4" set "SERIAL=%SER4%"
if not defined SERIAL set "SERIAL=%SER1%"
exit /b 0

:connect
if "%~1"=="" exit /b 0
"%ADB%" connect "%~1" >nul 2>&1
for /f "skip=1 tokens=1,2" %%x in ('"%ADB%" devices 2^>nul ^<nul') do (
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

:apply_settings
rem 设置按手机序列号保存，换 IP 或换 Wi-Fi 都不会丢。
rem 不能用 for /f 捕获 adb 输出：带引号的 exe 路径再加 -s "地址"
rem 会被 cmd 拆坏引号，所以先写临时文件再读。
set "DEV_SERIAL="
set "TMPF=%TEMP%\scrcpy_id.txt"
"%ADB%" -s "%SERIAL%" exec-out getprop ro.serialno > "%TMPF%" 2>nul
if exist "%TMPF%" set /p DEV_SERIAL=<"%TMPF%"
del "%TMPF%" >nul 2>&1
if not defined DEV_SERIAL set "DEV_SERIAL=unknown"
echo %DEV_SERIAL%| findstr /r /c:"^[A-Za-z0-9_-][A-Za-z0-9_-]*$" >nul
if errorlevel 1 set "DEV_SERIAL=unknown"

set "OPT_SCREEN_OFF=0"
set "OPT_NEW_DISPLAY="
set "OPT_CLIPBOARD=1"
set "OPT_MAX_SIZE=1280"
set "OPT_MAX_FPS=60"
set "OPT_BITRATE=8M"
set "OPT_WINDOW=1"
set "OPT_KEEP_ACTIVE=1"
set "SETFILE=%DEVDIR%\%DEV_SERIAL%.bat"
if exist "%SETFILE%" call "%SETFILE%"

set "ARGS="
if "%OPT_SCREEN_OFF%"=="1" set "ARGS=%ARGS% --turn-screen-off"
if "%OPT_CLIPBOARD%"=="0" set "ARGS=%ARGS% --no-clipboard-autosync"
if not "%OPT_MAX_SIZE%"=="" set "ARGS=%ARGS% --max-size=%OPT_MAX_SIZE%"
if not "%OPT_MAX_FPS%"=="" set "ARGS=%ARGS% --max-fps=%OPT_MAX_FPS%"
if not "%OPT_BITRATE%"=="" set "ARGS=%ARGS% --video-bit-rate=%OPT_BITRATE%"
if "%OPT_KEEP_ACTIVE%"=="1" set "ARGS=%ARGS% --keep-active"
if not "%OPT_NEW_DISPLAY%"=="" set "ARGS=%ARGS% --new-display=%OPT_NEW_DISPLAY%"
if "%OPT_WINDOW%"=="1" set "ARGS=%ARGS% --always-on-top"
if "%OPT_WINDOW%"=="2" set "ARGS=%ARGS% --fullscreen"
if "%OPT_WINDOW%"=="3" set "ARGS=%ARGS% --window-borderless"
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
call :apply_settings
if defined SERIAL (
  "%SCRCPY%" -s "%SERIAL%"%ARGS%
) else (
  "%SCRCPY%"%ARGS%
)
exit /b 0
