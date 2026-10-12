@echo off
title XkScreen Task Repoint Fix
set LOG=D:\Code\Xingcan-Xiaolan-Drive\.tools\task_fix_trace.log
echo ==== task repoint fix ==== > "%LOG%"
echo start: %DATE% %TIME% >> "%LOG%"

echo ==== BEFORE ==== >> "%LOG%"
schtasks /query /tn XKScreenDriver /v /fo list >> "%LOG%" 2>&1

echo ==== REPOINT via schtasks ==== >> "%LOG%"
schtasks /create /f /tn XKScreenDriver /tr "D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe" /sc onstart /ru SYSTEM /rl highest >> "%LOG%" 2>&1

echo ==== AFTER ==== >> "%LOG%"
schtasks /query /tn XKScreenDriver /v /fo list >> "%LOG%" 2>&1

echo ==== config dir ACL ==== >> "%LOG%"
icacls "%ProgramData%\XkScreen" >> "%LOG%" 2>&1

echo done. >> "%LOG%"
echo end: %DATE% %TIME% >> "%LOG%"
timeout /t 3 /nobreak >nul
