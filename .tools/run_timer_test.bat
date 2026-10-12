@echo off
title XkScreen Timer Test + Service Takeover
cd /d D:\Code\Xingcan-Xiaolan-Drive
set LOG=D:\Code\Xingcan-Xiaolan-Drive\.tools\timer_test_trace.log

echo ==== timer test / service takeover ==== > "%LOG%"
echo start: %DATE% %TIME% >> "%LOG%"

echo ============================================================
echo   C# SERVICE TAKEOVER + TIMER TEST
echo   P1 (~16s): frozen 45:30    (returns: is the clock area 2-digit-happy?)
echo   P2 (~25s): stopwatch 00:00 counting UP (MM:SS)
echo   P3 (~40s): countdown 00:30 counting DOWN to 00:00
echo   ==== WATCH THE MIDDLE CLOCK AREA ====
echo ============================================================
timeout /t 6 /nobreak >nul

echo [1/7] stopping PS driver... >> "%LOG%"
powershell -NoProfile -Command "$me=$PID; Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*xkw_driver_loop*' -and $_.ProcessId -ne $me } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Output ('killed pid ' + $_.ProcessId) }" >> "%LOG%" 2>&1
timeout /t 3 /nobreak >nul

echo [2/7] deploying service exe... >> "%LOG%"
copy /y "D:\Code\Xingcan-Xiaolan-Drive\product\XkScreen.Service\bin\Release\net48\XkScreen.Service.exe" "D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe" >> "%LOG%" 2>&1

echo [3/7] repointing autostart task to service... >> "%LOG%"
powershell -NoProfile -Command "$a = New-ScheduledTaskAction -Execute 'D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe'; $t = New-ScheduledTaskTrigger -AtStartup; $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest; Register-ScheduledTask -TaskName 'XKScreenDriver' -Action $a -Trigger $t -Principal $p -Force | Out-Null; Write-Output 'task repointed to XkScreen.Service.exe'" >> "%LOG%" 2>&1

echo [4/7] granting Users write on config dir... >> "%LOG%"
if not exist "%ProgramData%\XkScreen" mkdir "%ProgramData%\XkScreen" >> "%LOG%" 2>&1
icacls "%ProgramData%\XkScreen" /grant "*S-1-5-32-545:(OI)(CI)M" >> "%LOG%" 2>&1

echo [5/7] starting service... >> "%LOG%"
copy /y "D:\Code\Xingcan-Xiaolan-Drive\.tools\cfg_auto.json" "%ProgramData%\XkScreen\config.json" >> "%LOG%" 2>&1
start "XkScreenService" /min "D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe"
timeout /t 20 /nobreak >nul

echo [6/7] phases... >> "%LOG%"
echo phase P1: fixed 45:30 >> "%LOG%"
copy /y "D:\Code\Xingcan-Xiaolan-Drive\.tools\cfg_t_fixed.json" "%ProgramData%\XkScreen\config.json" >> "%LOG%" 2>&1
timeout /t 16 /nobreak >nul

echo phase P2: stopwatch up >> "%LOG%"
copy /y "D:\Code\Xingcan-Xiaolan-Drive\.tools\cfg_t_up.json" "%ProgramData%\XkScreen\config.json" >> "%LOG%" 2>&1
timeout /t 25 /nobreak >nul

echo phase P3: countdown 00:30 >> "%LOG%"
copy /y "D:\Code\Xingcan-Xiaolan-Drive\.tools\cfg_t_down.json" "%ProgramData%\XkScreen\config.json" >> "%LOG%" 2>&1
timeout /t 40 /nobreak >nul

echo phase P4: restore auto >> "%LOG%"
copy /y "D:\Code\Xingcan-Xiaolan-Drive\.tools\cfg_auto.json" "%ProgramData%\XkScreen\config.json" >> "%LOG%" 2>&1
timeout /t 5 /nobreak >nul

echo [7/7] done. service keeps running as the active driver. >> "%LOG%"
echo end: %DATE% %TIME% >> "%LOG%"
timeout /t 3 /nobreak >nul
