@echo off
setlocal EnableExtensions
pushd "%~dp0" >nul 2>&1 || cd /d "%~dp0"
set "BIN=%~dp0bin"
set "ADB=%BIN%\adb.exe"
if not exist "%ADB%" set "ADB=adb"
set "SAVED=%~dp0config\phone.txt"
set "SCRCPY_ICON_DIR=%BIN%"
set "SCRCPY_SERVER_PATH=%BIN%\scrcpy-server"

echo On phone: Developer options - Wireless debugging - Pair device with pairing code
echo Use the IP:port shown INSIDE the pairing dialog, NOT the main Wireless debugging screen.
set /p PAIR=Pairing dialog IP:port: 
set /p CODE=6-digit pairing code: 
if not defined PAIR goto pair_fail
if not defined CODE goto pair_fail
"%ADB%" pair %PAIR% %CODE%
if errorlevel 1 goto pair_fail

echo.
echo Paired successfully. Looking for the wireless debugging port...
ping -n 3 127.0.0.1 >nul
set "WIFI="
for /f "tokens=2,3" %%a in ('"%ADB%" mdns services 2^>nul') do if /i "%%a"=="_adb-tls-connect._tcp" (
  if not defined WIFI set "WIFI=%%b"
)

if defined WIFI (
  echo Found: %WIFI%
  call :connect "%WIFI%"
  if defined CONNECTED goto connected
  echo Automatic connection failed.
) else (
  echo Could not find the connection port automatically.
)

echo On the main Wireless debugging screen, find "IP address and port".
echo Enter that IP:port here ^(NOT the pairing dialog port^):
set "WIFI="
set /p WIFI=Main screen IP:port: 
if not defined WIFI goto connect_fail
call :connect "%WIFI%"
if not defined CONNECTED goto connect_fail

:connected
>"%SAVED%" echo %WIFI%
echo.
echo Connected: %WIFI%
echo Saved to phone.txt.
echo.
set /p START=Start mirroring now? [Y/N]: 
if /i "%START%"=="Y" call "%~dp0mirror.bat"
pause
exit /b 0

:pair_fail
echo.
echo Pairing failed. Check the 6-digit code and keep the pairing dialog open.
echo If you see "protocol fault", you used the main screen port.
echo Reopen "Pair device with pairing code" and use the NEW port from that dialog.
pause
exit /b 1

:connect_fail
echo.
echo Could not connect to %WIFI%.
echo 1. Use the IP:port from the Wireless debugging main screen, not the pairing port.
echo 2. Unlock the phone and tap Allow when asked.
echo 3. Keep phone and PC on the same Wi-Fi, and disable VPN.
echo 4. Toggle Wireless debugging off/on, then pair again.
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
  echo Connection ready.
) else (
  echo Connection not ready yet.
  "%ADB%" devices
)
exit /b 0
