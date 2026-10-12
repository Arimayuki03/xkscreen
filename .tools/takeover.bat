@echo off
echo === [1/5] start persistent driver ===
start "XKScreenDriver" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\Code\Xingcan-Xiaolan-Drive\.tools\xkw_driver_loop.ps1"
timeout /t 12 /nobreak >nul

echo === [2/5] kill leftover service processes ===
taskkill /F /IM SystemTemperatureMonitoring.exe >nul 2>&1

echo === [3/5] install boot task (SYSTEM, ONSTART) ===
schtasks /Create /TN "XKScreenDriver" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File D:\Code\Xingcan-Xiaolan-Drive\.tools\xkw_driver_loop.ps1" /SC ONSTART /RU SYSTEM /RL HIGHEST /F

echo === [4/5] official service start type -^> manual ===
sc config SystemTemperatureMonitoring start= demand

echo === [5/5] status ===
schtasks /Query /TN "XKScreenDriver" /FO LIST | findstr /i "TaskName Status Next"
echo --- driver log tail:
powershell -NoProfile -Command "if (Test-Path 'D:\Code\Xingcan-Xiaolan-Drive\official\driver_loop.log') { Get-Content 'D:\Code\Xingcan-Xiaolan-Drive\official\driver_loop.log' -Tail 6 } else { 'no log yet' }"
echo === done ===
