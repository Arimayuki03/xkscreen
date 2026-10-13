@echo off
rem XkScreen task registration - runs elevated (from the installer) or manually.
rem Creates the boot task (SYSTEM, highest) and the hourly watchdog task, then
rem starts the driver. Progress is appended to setup_tasks.log next to this file.
setlocal
set "APP=%~dp0"
set "LOG=%APP%setup_tasks.log"
set "SVC=%APP%XkScreen.Service.exe"
echo ==== setup_tasks %DATE% %TIME% ==== >> "%LOG%"

schtasks /Create /F /TN XKScreenDriver /TR "%APP%service_host.cmd" /SC ONSTART /RU SYSTEM /RL HIGHEST >> "%LOG%" 2>&1
echo   driver-task create exit=%errorlevel% >> "%LOG%"

schtasks /Create /F /TN XKScreenDriverWatch /TR "%APP%watch.cmd" /SC HOURLY /RU SYSTEM /RL HIGHEST >> "%LOG%" 2>&1
echo   watch-task create exit=%errorlevel% >> "%LOG%"

schtasks /Run /TN XKScreenDriver >> "%LOG%" 2>&1
echo   driver-task run exit=%errorlevel% >> "%LOG%"
echo done. >> "%LOG%"
endlocal
