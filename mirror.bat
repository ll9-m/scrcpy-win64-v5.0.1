@echo off
setlocal EnableExtensions
pushd "%~dp0" >nul 2>&1 || cd /d "%~dp0"
set "BIN=%~dp0bin"
set "ADB=%BIN%\adb.exe"
set "SCRCPY=%BIN%\scrcpy.exe"
set "SAVED=%~dp0config\phone.txt"
rem Keep icon and server lookup independent of the working directory.
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

rem Emulator instances (emulator-5554) are skipped: otherwise they are treated
rem as a USB device and steal the session from the real phone.
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

rem phone.txt may be missing, empty, or polluted by a BOM / stray blank lines.
rem Only accept a line that is exactly IPv4:port.
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
    echo USB debugging is unauthorized. Unlock the phone and tap "Allow".
    set "HINTED=1"
  )
  if defined OFFLINE if not defined HINTED (
    echo Device is offline. Reconnect USB or toggle wireless debugging.
    set "HINTED=1"
  )
  echo Waiting for phone...
  ping -n 16 127.0.0.1 >nul
  goto discover
)

echo No phone found. Check:
echo 1. Phone and PC are on the same Wi-Fi
echo 2. Wireless debugging is enabled on the phone
echo 3. Run pair.bat first
if defined UNAUTH echo USB debugging is unauthorized. Unlock the phone and tap "Allow".
if defined OFFLINE echo Device is offline. Reconnect USB or toggle wireless debugging.
echo Exiting in 5 seconds. Use mirror-wait.bat to keep waiting.
ping -n 6 127.0.0.1 >nul
exit /b 1

:consider
rem Network devices win over USB devices; keep the first one seen in each class.
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
echo ERROR: scrcpy.exe not found at:
echo   %SCRCPY%
echo The bin folder is incomplete. Re-extract the package.
exit /b 1
:check_adb
if exist "%ADB%" exit /b 0
where adb >nul 2>&1
if errorlevel 1 (
  echo ERROR: adb.exe not found at:
  echo   %ADB%
  echo and no adb was found in PATH. Re-extract the package.
  exit /b 1
)
set "ADB=adb"
echo WARNING: using adb from PATH instead of the bundled one.
echo          A version mismatch may break pairing and device discovery.
exit /b 0

:run
if defined SERIAL (
  "%SCRCPY%" -s "%SERIAL%" --max-size=1280 --max-fps=60 --keep-active --always-on-top
) else (
  "%SCRCPY%" --max-size=1280 --max-fps=60 --keep-active --always-on-top
)
exit /b 0
