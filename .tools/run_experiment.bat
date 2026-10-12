@echo off
title XKScreen Experiments
cd /d D:\Code\Xingcan-Xiaolan-Drive

if "%1"=="" (set ONLY=ALL) else (set ONLY=%1)

echo ============================================================
echo   SCREEN EXPERIMENT  (ONLY=%ONLY%)
echo   A: frozen values  CPU 77pct/88C  GPU 44pct/55C   ~25s
echo   B: ring colors    RED - GREEN - BLUE, 8s each     ~24s
echo   C: display modes  1 / 2 / 3, 8s each + 4s normal  ~36s
echo   D: deep-dig       0/255 temp, ColorEx x0..3, mode 0x80..0x83,4,5
echo   E: clock          12:34 fixed 10s, fast clock 30s, +1h hold 70s
echo   ==== WATCH THE SCREEN NOW ====
echo ============================================================
timeout /t 8 /nobreak >nul

echo [1/4] stopping resident driver...
powershell -NoProfile -Command "$me=$PID; Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*xkw_driver_loop*' -and $_.ProcessId -ne $me } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Output ('killed pid ' + $_.ProcessId) }"
timeout /t 3 /nobreak >nul

echo [2/4] running experiment (watch the screen)...
powershell -NoProfile -ExecutionPolicy Bypass -File D:\Code\Xingcan-Xiaolan-Drive\.tools\xkw_experiment.ps1 -Only %ONLY%

echo [3/4] restarting resident driver...
start "XKScreenDriver" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\Code\Xingcan-Xiaolan-Drive\.tools\xkw_driver_loop.ps1"

echo [4/4] done, screen returns to normal shortly.
timeout /t 5 /nobreak >nul
