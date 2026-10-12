@echo off
title XkScreen Task Create Probe
set LOG=D:\Code\Xingcan-Xiaolan-Drive\.tools\task_probe_trace.log
echo ==== task create probe ==== > "%LOG%"
echo start: %DATE% %TIME% >> "%LOG%"

echo ==== probe 1: create calc task ==== >> "%LOG%"
schtasks /create /f /tn XKProbeCalc /tr "calc.exe" /sc onstart /ru SYSTEM /rl highest >> "%LOG%" 2>&1
echo probe1_errorlevel=%errorlevel% >> "%LOG%"

echo ==== probe 2: create service-exe task under temp name ==== >> "%LOG%"
schtasks /create /f /tn XKProbeSvc /tr "D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe" /sc onstart /ru SYSTEM /rl highest >> "%LOG%" 2>&1
echo probe2_errorlevel=%errorlevel% >> "%LOG%"

echo ==== probe 3: recreate real task, powershell-style tr like the original working one ==== >> "%LOG%"
schtasks /Create /TN "XKScreenDriver" /TR "D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe" /SC ONSTART /RU SYSTEM /RL HIGHEST /F >> "%LOG%" 2>&1
echo probe3_errorlevel=%errorlevel% >> "%LOG%"

echo ==== query all probes ==== >> "%LOG%"
schtasks /query /tn XKProbeCalc /v /fo list 2>&1 | findstr /c:"要运行的任务" >> "%LOG%"
schtasks /query /tn XKProbeSvc /v /fo list 2>&1 | findstr /c:"要运行的任务" >> "%LOG%"
schtasks /query /tn XKScreenDriver /v /fo list 2>&1 | findstr /c:"要运行的任务" >> "%LOG%"

echo ==== cleanup probes ==== >> "%LOG%"
schtasks /delete /tn XKProbeCalc /f >> "%LOG%" 2>&1
schtasks /delete /tn XKProbeSvc /f >> "%LOG%" 2>&1

echo done. >> "%LOG%"
echo end: %DATE% %TIME% >> "%LOG%"
timeout /t 3 /nobreak >nul
