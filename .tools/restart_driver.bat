@echo off
title XKScreen Driver Restart
powershell -NoProfile -Command "$me=$PID; Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*xkw_driver_loop*' -and $_.ProcessId -ne $me } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Output ('killed pid ' + $_.ProcessId) }"
timeout /t 3 /nobreak >nul
start "XKScreenDriver" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\Code\Xingcan-Xiaolan-Drive\.tools\xkw_driver_loop.ps1"
echo driver restarted.
timeout /t 3 /nobreak >nul
