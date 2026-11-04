@echo off
chcp 936 >nul 2>&1
setlocal EnableExtensions
pushd "%~dp0" >nul 2>&1 || cd /d "%~dp0"
set "BIN=%~dp0bin"
set "ADB=%BIN%\adb.exe"
set "DEVDIR=%~dp0config\devices"
set "SCRCPY_ICON_DIR=%BIN%"
set "SCRCPY_SERVER_PATH=%BIN%\scrcpy-server"

if exist "%ADB%" goto have_adb
where adb >nul 2>&1
if errorlevel 1 goto no_adb
set "ADB=adb"
:have_adb

if not exist "%DEVDIR%" mkdir "%DEVDIR%" >nul 2>&1

echo ============================================================
echo   scrcpy 投屏设置
echo ============================================================
echo 正在查找已连接的手机...
call :collect

if not defined SER1 goto no_device
if defined SER2 goto choose
set "SERIAL=%SER1%"
goto picked

:choose
echo.
echo 发现多台设备，请选择要配置的一台：
echo   1. %SER1%
if defined SER2 echo   2. %SER2%
if defined SER3 echo   3. %SER3%
if defined SER4 echo   4. %SER4%
echo.
set /p PICK=输入序号后回车： 
if "%PICK%"=="2" set "SERIAL=%SER2%"
if "%PICK%"=="3" set "SERIAL=%SER3%"
if "%PICK%"=="4" set "SERIAL=%SER4%"
if not defined SERIAL set "SERIAL=%SER1%"

:picked
call :identify
call :defaults
if exist "%SETFILE%" call "%SETFILE%"

:menu
if not defined NOCLS cls
set "T_SCREEN=关"
if "%OPT_SCREEN_OFF%"=="1" set "T_SCREEN=开"
set "T_CLIP=开"
if "%OPT_CLIPBOARD%"=="0" set "T_CLIP=关"
set "T_DISPLAY=关"
if not "%OPT_NEW_DISPLAY%"=="" set "T_DISPLAY=%OPT_NEW_DISPLAY%"
set "T_SIZE=%OPT_MAX_SIZE%"
if "%OPT_MAX_SIZE%"=="" set "T_SIZE=不限制"
set "T_FPS=%OPT_MAX_FPS%"
if "%OPT_MAX_FPS%"=="" set "T_FPS=不限制"
set "T_BITRATE=%OPT_BITRATE%"
if "%OPT_BITRATE%"=="" set "T_BITRATE=默认"
set "T_WINDOW=普通"
if "%OPT_WINDOW%"=="1" set "T_WINDOW=置顶"
if "%OPT_WINDOW%"=="2" set "T_WINDOW=全屏"
if "%OPT_WINDOW%"=="3" set "T_WINDOW=无边框"
set "T_KEEP=关"
if "%OPT_KEEP_ACTIVE%"=="1" set "T_KEEP=开"
set "T_APP=未设置"
if not "%OPT_START_APP%"=="" set "T_APP=%OPT_START_APP%"

echo ============================================================
echo   scrcpy 投屏设置
echo ============================================================
echo 设备：%DEV_NAME%     当前连接：%SERIAL%
echo 设置按手机序列号保存，换 IP 也不会丢
echo.
echo   1. 关屏投屏        %T_SCREEN%
echo   2. 虚拟副屏        %T_DISPLAY%
echo   3. 剪贴板同步      %T_CLIP%
echo   4. 分辨率上限      %T_SIZE%
echo   5. 帧率上限        %T_FPS%
echo   6. 视频码率        %T_BITRATE%
echo   7. 窗口形态        %T_WINDOW%
echo   8. 保持亮屏        %T_KEEP%
echo   9. 副屏启动应用    %T_APP%
echo.
echo   0. 保存并退出      Q. 不保存退出
echo.
set /p CH=输入序号： 

if "%CH%"=="1" goto toggle_screen
if "%CH%"=="2" goto cycle_display
if "%CH%"=="3" goto toggle_clip
if "%CH%"=="4" goto cycle_size
if "%CH%"=="5" goto cycle_fps
if "%CH%"=="6" goto cycle_bitrate
if "%CH%"=="7" goto cycle_window
if "%CH%"=="8" goto toggle_keep
if "%CH%"=="9" goto set_app
if "%CH%"=="0" goto save
if /i "%CH%"=="Q" goto quit
if not defined CH goto no_input
set "EMPTY=0"
goto menu

:set_app
echo.
echo 副屏是新建的一块空屏，上面没有任何界面，必须指定启动哪个应用才不会黑屏。
echo 可以填包名（如 com.android.settings），也可以填关键字（如 ?bilibili），带 ? 会模糊匹配。
echo 直接回车 = 不自动启动。
set "APPIN="
set /p APPIN=应用： 
set "OPT_START_APP=%APPIN%"
goto menu

:toggle_screen
if "%OPT_SCREEN_OFF%"=="1" (
  set "OPT_SCREEN_OFF=0"
) else (
  set "OPT_SCREEN_OFF=1"
)
goto menu

:cycle_display
if "%OPT_NEW_DISPLAY%"=="" (
  set "OPT_NEW_DISPLAY=1920x1080/420"
  goto menu
)
if "%OPT_NEW_DISPLAY%"=="1920x1080/420" (
  set "OPT_NEW_DISPLAY=1280x720/240"
  goto menu
)
if "%OPT_NEW_DISPLAY%"=="1280x720/240" (
  set "OPT_NEW_DISPLAY=1920x1200/320"
  goto menu
)
set "OPT_NEW_DISPLAY="
goto menu

:toggle_clip
if "%OPT_CLIPBOARD%"=="1" (
  set "OPT_CLIPBOARD=0"
) else (
  set "OPT_CLIPBOARD=1"
)
goto menu

:cycle_size
if "%OPT_MAX_SIZE%"=="1280" (
  set "OPT_MAX_SIZE=1920"
  goto menu
)
if "%OPT_MAX_SIZE%"=="1920" (
  set "OPT_MAX_SIZE=1024"
  goto menu
)
if "%OPT_MAX_SIZE%"=="1024" (
  set "OPT_MAX_SIZE="
  goto menu
)
set "OPT_MAX_SIZE=1280"
goto menu

:cycle_fps
if "%OPT_MAX_FPS%"=="60" (
  set "OPT_MAX_FPS=30"
  goto menu
)
if "%OPT_MAX_FPS%"=="30" (
  set "OPT_MAX_FPS=90"
  goto menu
)
if "%OPT_MAX_FPS%"=="90" (
  set "OPT_MAX_FPS="
  goto menu
)
set "OPT_MAX_FPS=60"
goto menu

:cycle_bitrate
if "%OPT_BITRATE%"=="8M" (
  set "OPT_BITRATE=16M"
  goto menu
)
if "%OPT_BITRATE%"=="16M" (
  set "OPT_BITRATE=32M"
  goto menu
)
if "%OPT_BITRATE%"=="32M" (
  set "OPT_BITRATE=4M"
  goto menu
)
set "OPT_BITRATE=8M"
goto menu

:cycle_window
if "%OPT_WINDOW%"=="1" (
  set "OPT_WINDOW=2"
  goto menu
)
if "%OPT_WINDOW%"=="2" (
  set "OPT_WINDOW=3"
  goto menu
)
if "%OPT_WINDOW%"=="3" (
  set "OPT_WINDOW=4"
  goto menu
)
set "OPT_WINDOW=1"
goto menu

:toggle_keep
if "%OPT_KEEP_ACTIVE%"=="1" (
  set "OPT_KEEP_ACTIVE=0"
) else (
  set "OPT_KEEP_ACTIVE=1"
)
goto menu

:save
(
echo rem 本文件由 设置.bat 生成，每台手机一份，按序列号命名
echo rem 可手动修改，但必须保持 GBK 编码，否则中文会乱码
echo set "DEV_NAME=%DEV_NAME%"
echo set "DEV_ADDR=%SERIAL%"
echo set "OPT_SCREEN_OFF=%OPT_SCREEN_OFF%"
echo set "OPT_NEW_DISPLAY=%OPT_NEW_DISPLAY%"
echo set "OPT_CLIPBOARD=%OPT_CLIPBOARD%"
echo set "OPT_MAX_SIZE=%OPT_MAX_SIZE%"
echo set "OPT_MAX_FPS=%OPT_MAX_FPS%"
echo set "OPT_BITRATE=%OPT_BITRATE%"
echo set "OPT_WINDOW=%OPT_WINDOW%"
echo set "OPT_KEEP_ACTIVE=%OPT_KEEP_ACTIVE%"
echo set "OPT_START_APP=%OPT_START_APP%"
) > "%SETFILE%"
echo.
echo 已保存：%SETFILE%
echo.
set /p GO=现在按这套设置投屏吗？[Y/N]： 
if /i "%GO%"=="Y" call "%~dp0投屏.bat"
exit /b 0

:no_input
rem 连续回车或输入流已到末尾时不要空转
set /a EMPTY+=1
if %EMPTY% GEQ 5 goto quit
goto menu

:quit
echo.
echo 已放弃本次修改。
pause
exit /b 0

:no_device
echo.
echo 没有找到已连接的手机。
echo 请先运行「配对.bat」完成配对，再回来设置。
pause
exit /b 1

:no_adb
echo.
echo 错误：找不到 adb.exe
echo   期望位置：%ADB%
echo 请确认 bin 目录完整，或重新解压本程序包。
pause
exit /b 1

:collect
set "SER1="
set "SER2="
set "SER3="
set "SER4="
for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices 2^>nul ^<nul') do (
  if /i "%%b"=="device" (
    echo %%a | findstr /i /b /c:"emulator-" >nul || call :add "%%a"
  )
)
exit /b 0

:add
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

:identify
rem 这里不能用 for /f 捕获 adb 输出：带引号的 exe 路径再加 -s "地址"
rem 会被 cmd 拆坏引号导致取不到值，改成先写临时文件再读。
set "DEV_SERIAL="
set "DEV_NAME="
set "TMPF=%TEMP%\scrcpy_id.txt"
"%ADB%" -s "%SERIAL%" exec-out getprop ro.serialno > "%TMPF%" 2>nul
if exist "%TMPF%" set /p DEV_SERIAL=<"%TMPF%"
if not defined DEV_SERIAL set "DEV_SERIAL=unknown"
echo %DEV_SERIAL%| findstr /r /c:"^[A-Za-z0-9_-][A-Za-z0-9_-]*$" >nul
if errorlevel 1 set "DEV_SERIAL=unknown"
"%ADB%" -s "%SERIAL%" exec-out getprop ro.product.model > "%TMPF%" 2>nul
if exist "%TMPF%" set /p DEV_NAME=<"%TMPF%"
if not defined DEV_NAME set "DEV_NAME=未知设备"
del "%TMPF%" >nul 2>&1
set "SETFILE=%DEVDIR%\%DEV_SERIAL%.bat"
exit /b 0

:defaults
set "OPT_SCREEN_OFF=0"
set "OPT_NEW_DISPLAY="
set "OPT_CLIPBOARD=1"
set "OPT_MAX_SIZE=1280"
set "OPT_MAX_FPS=60"
set "OPT_BITRATE=8M"
set "OPT_WINDOW=1"
set "OPT_KEEP_ACTIVE=1"
set "OPT_START_APP="
exit /b 0
