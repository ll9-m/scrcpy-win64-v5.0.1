@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "ADB=%~dp0adb.exe"
set "SCRCPY=%~dp0scrcpy.exe"
if not exist "%ADB%" set "ADB=adb"
if not exist "%SCRCPY%" set "SCRCPY=scrcpy"
set "SAVED=%~dp0phone.txt"
set "WAIT="
set "HINTED="
if /i "%~1"=="--wait" set "WAIT=1"

:discover
set "SERIAL="
set "USB="
set "CONNECTED="
set "TARGET="
set "UNAUTH="
set "OFFLINE="

for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices 2^>nul') do (
  if /i "%%b"=="device" (
    echo %%a | findstr ":" >nul
    if not errorlevel 1 (
      set "SERIAL=%%a"
      goto run
    )
    if not defined USB set "USB=%%a"
  )
  if /i "%%b"=="unauthorized" set "UNAUTH=1"
  if /i "%%b"=="offline" set "OFFLINE=1"
)

if defined USB (
  set "SERIAL=%USB%"
  goto run
)

if exist "%SAVED%" set /p TARGET=<"%SAVED%"
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
"%ADB%" kill-server >nul 2>&1
exit /b 1

:connect
if "%~1"=="" exit /b 0
"%ADB%" connect %~1 >nul 2>&1
for /f "skip=1 tokens=1,2" %%x in ('"%ADB%" devices 2^>nul') do if "%%y"=="device" (
  set "SERIAL=%%x"
  set "CONNECTED=1"
  >"%SAVED%" echo %~1
)
exit /b 0

:run
if defined SERIAL (
  "%SCRCPY%" -s "%SERIAL%" --max-size=1280 --max-fps=60 --keep-active --always-on-top
) else (
  "%SCRCPY%" --max-size=1280 --max-fps=60 --keep-active --always-on-top
)
"%ADB%" kill-server >nul 2>&1
exit /b 0
