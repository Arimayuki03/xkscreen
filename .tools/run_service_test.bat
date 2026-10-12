@echo off
title XkScreen Service Swap Test
cd /d D:\Code\Xingcan-Xiaolan-Drive
set LOG=D:\Code\Xingcan-Xiaolan-Drive\.tools\service_test_trace.log

echo ==== service swap test run ==== > "%LOG%"
echo start time: %DATE% %TIME% >> "%LOG%"

echo ============================================================
echo   C# SERVICE SWAP TEST (PS driver stops, C# service runs ~80s)
echo   Phase 1 (~30s): default config - screen shows live data
echo   Phase 2 (~50s): custom config  - GPU ring = mem pct + CPU temp
echo   ==== WATCH THE SCREEN ====
echo ============================================================
timeout /t 6 /nobreak >nul

echo [1/6] stopping PS driver... >> "%LOG%"
powershell -NoProfile -Command "$me=$PID; Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*xkw_driver_loop*' -and $_.ProcessId -ne $me } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Output ('killed pid ' + $_.ProcessId) }" >> "%LOG%" 2>&1
timeout /t 3 /nobreak >nul

echo [2/6] deploying service exe... >> "%LOG%"
copy /y "D:\Code\Xingcan-Xiaolan-Drive\product\XkScreen.Service\bin\Release\net48\XkScreen.Service.exe" "D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe" >> "%LOG%" 2>&1

echo [3/6] writing default config... >> "%LOG%"
if not exist "%ProgramData%\XkScreen" mkdir "%ProgramData%\XkScreen" >> "%LOG%" 2>&1
copy /y "D:\Code\Xingcan-Xiaolan-Drive\.tools\cfg_auto.json" "%ProgramData%\XkScreen\config.json" >> "%LOG%" 2>&1
echo config after step3 copy: >> "%LOG%"
type "%ProgramData%\XkScreen\config.json" >> "%LOG%" 2>&1

echo [4/6] starting C# service... >> "%LOG%"
start "XkScreenService" /min "D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe"
timeout /t 45 /nobreak >nul

echo [5/6] switching config to gpu demo... >> "%LOG%"
copy /y "D:\Code\Xingcan-Xiaolan-Drive\.tools\cfg_gpu_demo.json" "%ProgramData%\XkScreen\config.json" >> "%LOG%" 2>&1
echo config after step5 copy: >> "%LOG%"
type "%ProgramData%\XkScreen\config.json" >> "%LOG%" 2>&1
timeout /t 50 /nobreak >nul

echo [6/6] stopping service, restarting PS driver... >> "%LOG%"
powershell -NoProfile -Command "Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue | Stop-Process -Force" >> "%LOG%" 2>&1
copy /y "D:\Code\Xingcan-Xiaolan-Drive\.tools\cfg_auto.json" "%ProgramData%\XkScreen\config.json" >> "%LOG%" 2>&1
timeout /t 2 /nobreak >nul
start "XKScreenDriver" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\Code\Xingcan-Xiaolan-Drive\.tools\xkw_driver_loop.ps1"
echo done. >> "%LOG%"
echo end time: %DATE% %TIME% >> "%LOG%"
timeout /t 3 /nobreak >nul
