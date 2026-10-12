@echo off
title XkScreen Restart + Verify
cd /d D:\Code\Xingcan-Xiaolan-Drive
call .tools\restart_service.bat
echo === frida watch: 240s with screen OFF (expect: few startup frames, then silence) ===
python .tools\frida_watch.py 240 > official\watch_dump2.log 2>&1
echo done - see official\watch_dump2.log
timeout /t 3 /nobreak >nul
