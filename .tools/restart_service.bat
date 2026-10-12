@echo off
title XkScreen Service Restart
cd /d D:\Code\Xingcan-Xiaolan-Drive
set LOG=D:\Code\Xingcan-Xiaolan-Drive\.tools\service_restart.log
echo ==== service restart ==== > "%LOG%"
echo start: %DATE% %TIME% >> "%LOG%"

echo [1/3] stopping service... >> "%LOG%"
powershell -NoProfile -Command "Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue | Stop-Process -Force; Write-Output 'stopped'" >> "%LOG%" 2>&1
timeout /t 2 /nobreak >nul

echo [2/3] deploying exe + web ui... >> "%LOG%"
copy /y "D:\Code\Xingcan-Xiaolan-Drive\product\XkScreen.Service\bin\Release\net48\XkScreen.Service.exe" "D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe" >> "%LOG%" 2>&1
if exist "D:\Code\Xingcan-Xiaolan-Drive\product\frontend\out" robocopy "D:\Code\Xingcan-Xiaolan-Drive\product\frontend\out" "D:\Code\Xingcan-Xiaolan-Drive\official\web" /MIR /NFL /NDL /NJH /NJS >> "%LOG%" 2>&1

echo [3/3] starting service... >> "%LOG%"
start "XkScreenService" /min "D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe"
timeout /t 15 /nobreak >nul
powershell -NoProfile -Command "$p = Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue; if ($p) { Write-Output ('running pid ' + $p.Id) } else { Write-Output 'NOT RUNNING' }" >> "%LOG%" 2>&1
echo done. >> "%LOG%"
echo end: %DATE% %TIME% >> "%LOG%"
timeout /t 3 /nobreak >nul
