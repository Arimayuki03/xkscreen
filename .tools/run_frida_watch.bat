@echo off
title XkScreen Frida Watch
cd /d D:\Code\Xingcan-Xiaolan-Drive
echo watching service HID traffic for 80 seconds...
python .tools\frida_watch.py 80 > official\watch_dump.log 2>&1
echo done - see official\watch_dump.log
timeout /t 3 /nobreak >nul
