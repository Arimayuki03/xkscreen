@echo off
title XkScreen Task Repoint Fix 2
set LOG=D:\Code\Xingcan-Xiaolan-Drive\.tools\task_fix2_trace.log
echo ==== task repoint fix 2 ==== > "%LOG%"
echo start: %DATE% %TIME% >> "%LOG%"

echo ==== attempt C2: Register-ScheduledTask with LogonType ServiceAccount ==== >> "%LOG%"
powershell -NoProfile -Command "$a = New-ScheduledTaskAction -Execute 'D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe'; $t = New-ScheduledTaskTrigger -AtStartup; $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest; Register-ScheduledTask -TaskName 'XKScreenDriver' -Action $a -Trigger $t -Principal $p -Force | Out-Null; Write-Output 'C2 executed'" >> "%LOG%" 2>&1

schtasks /query /tn XKScreenDriver /v /fo list | findstr /c:"XkScreen.Service" >nul
if %errorlevel%==0 goto verify_ok

echo ==== C2 did not take effect, attempt A: schtasks delete + create ==== >> "%LOG%"
schtasks /delete /tn XKScreenDriver /f >> "%LOG%" 2>&1
schtasks /create /tn XKScreenDriver /tr "D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe" /sc onstart /ru SYSTEM /rl highest >> "%LOG%" 2>&1
echo A_errorlevel=%errorlevel% >> "%LOG%"

:verify_ok
echo ==== final task state ==== >> "%LOG%"
schtasks /query /tn XKScreenDriver /v /fo list >> "%LOG%" 2>&1
echo done. >> "%LOG%"
echo end: %DATE% %TIME% >> "%LOG%"
timeout /t 3 /nobreak >nul
