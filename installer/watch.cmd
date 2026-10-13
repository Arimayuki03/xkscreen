@echo off
rem XkScreen watchdog - runs hourly as SYSTEM (XKScreenDriverWatch task).
rem Restarts the driver when it died, and proactively after long uptime so the
rem driver task's default 72h execution-time limit never kills the screen.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watch.ps1" >> "%~dp0watch.log" 2>&1
