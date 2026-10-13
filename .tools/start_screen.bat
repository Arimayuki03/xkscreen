@echo off
title XkScreen Start
cd /d D:\Code\Xingcan-Xiaolan-Drive

set SVC=D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe
set GUI=D:\Code\Xingcan-Xiaolan-Drive\product\XkScreen.Gui\bin\Release\net8.0-windows\XkScreen.Gui.exe
set FIND=%SystemRoot%\System32\find.exe
set SLEEP=ping -n 5 127.0.0.1

tasklist /fi "imagename eq XkScreen.Service.exe" 2>nul | "%FIND%" /i "XkScreen.Service.exe" >nul
if not errorlevel 1 (
  echo [1/2] driver already running, skipping.
  goto gui
)
echo [1/2] starting driver - PLEASE APPROVE THE UAC PROMPT (admin is required
echo       for the CPUID hardware driver that reads the sensors)...
powershell -NoProfile -Command "Start-Process -FilePath '%SVC%' -Verb RunAs"
%SLEEP% >nul

:gui
tasklist /fi "imagename eq XkScreen.Gui.exe" 2>nul | "%FIND%" /i "XkScreen.Gui.exe" >nul
if not errorlevel 1 (
  echo [2/2] console already running, skipping.
  goto end
)
echo [2/2] starting desktop console...
start "" "%GUI%"

:end
echo.
echo done. web console: http://127.0.0.1:8899/
%SLEEP% >nul
