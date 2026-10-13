@echo off
title XkScreen Service Restart (elevated)
cd /d D:\Code\Xingcan-Xiaolan-Drive
set LOG=D:\Code\Xingcan-Xiaolan-Drive\.tools\service_restart.log
echo ==== service restart (elevated deploy) ==== > "%LOG%"
echo start: %DATE% %TIME% >> "%LOG%"

echo [1/3] building service... >> "%LOG%"
dotnet build "D:\Code\Xingcan-Xiaolan-Drive\product\XkScreen.Service\XkScreen.Service.csproj" -c Release -v q >> "%LOG%" 2>&1

echo [2/3] elevated deploy + restart (a UAC prompt will appear - approve it) >> "%LOG%"
powershell -NoProfile -Command "Start-Process -FilePath 'powershell' -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Code\Xingcan-Xiaolan-Drive\.tools\deploy_elevated.ps1'" >> "%LOG%" 2>&1

echo [3/3] result: >> "%LOG%"
type "D:\Code\Xingcan-Xiaolan-Drive\.tools\deploy_elevated_result.txt" >> "%LOG%" 2>&1
echo end: %DATE% %TIME% >> "%LOG%"
echo done - see .tools\service_restart.log
timeout /t 3 /nobreak >nul
