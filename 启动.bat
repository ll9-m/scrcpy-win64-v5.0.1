@echo off
chcp 936 >nul 2>&1
setlocal EnableExtensions
pushd "%~dp0" >nul 2>&1 || cd /d "%~dp0"
title scrcpy 无线投屏

rem 允许直接指定要执行的动作：启动.bat pair / mirror / wait / settings
if /i "%~1"=="pair" goto do_pair
if /i "%~1"=="mirror" goto do_mirror
if /i "%~1"=="wait" goto do_wait
if /i "%~1"=="settings" goto do_settings

:menu
cls
echo ============================================================
echo   scrcpy 无线投屏
echo ============================================================
echo.
echo   1. 配对手机        第一次使用，或手机换了 Wi-Fi
echo   2. 投屏            已经配对过，直接投
echo   3. 等待投屏        先开脚本，再开手机的无线调试
echo   4. 投屏设置        关屏 / 副屏 / 画质 / 窗口
echo.
echo   0. 退出
echo.
set /p CH=请输入序号： 

if "%CH%"=="1" goto do_pair
if "%CH%"=="2" goto do_mirror
if "%CH%"=="3" goto do_wait
if "%CH%"=="4" goto do_settings
if "%CH%"=="0" goto bye
if not defined CH goto no_input
set "EMPTY=0"
goto menu

:no_input
rem 连续回车或输入流已到末尾时不要空转
set /a EMPTY+=1
if %EMPTY% GEQ 5 goto bye
goto menu

:do_pair
cls
call "%~dp0配对.bat"
echo.
pause
goto menu

:do_mirror
cls
call "%~dp0投屏.bat"
echo.
pause
goto menu

:do_wait
cls
call "%~dp0等待投屏.bat"
echo.
echo 已在新窗口开始等待手机，本窗口可以关掉。
pause
goto menu

:do_settings
cls
call "%~dp0设置.bat"
echo.
pause
goto menu

:bye
exit /b 0
