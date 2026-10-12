@echo off
title XkScreen Autostart Repair
cd /d D:\Code\Xingcan-Xiaolan-Drive

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator elevation...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

set LOG=D:\Code\Xingcan-Xiaolan-Drive\.tools\autostart_fix.log
echo ==== autostart repair ==== > "%LOG%"
echo start: %DATE% %TIME% >> "%LOG%"

echo.
echo   Repairing autostart task XKScreenDriver ...
echo.

echo [1/3] create via schtasks ... >> "%LOG%"
schtasks /Create /TN "XKScreenDriver" /TR "D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe" /SC ONSTART /RU SYSTEM /RL HIGHEST /F >> "%LOG%" 2>&1
echo step1_errorlevel=%errorlevel% >> "%LOG%"

powershell -NoProfile -Command "if (Get-ScheduledTask -TaskName XKScreenDriver -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if %errorlevel%==0 goto done

echo [2/3] create via Register-ScheduledTask (ServiceAccount) ... >> "%LOG%"
powershell -NoProfile -Command "$a = New-ScheduledTaskAction -Execute 'D:\Code\Xingcan-Xiaolan-Drive\official\XkScreen.Service.exe'; $t = New-ScheduledTaskTrigger -AtStartup; $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest; Register-ScheduledTask -TaskName 'XKScreenDriver' -Action $a -Trigger $t -Principal $p -Force | Out-Null" >> "%LOG%" 2>&1

powershell -NoProfile -Command "if (Get-ScheduledTask -TaskName XKScreenDriver -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if %errorlevel%==0 goto done

echo [2b] create via XML import ... >> "%LOG%"
powershell -NoProfile -Command "$c = Get-Content -Raw 'D:\Code\Xingcan-Xiaolan-Drive\.tools\task_template.xml'; [IO.File]::WriteAllText('D:\Code\Xingcan-Xiaolan-Drive\.tools\task_u16.xml', $c, [Text.Encoding]::Unicode)" >> "%LOG%" 2>&1
schtasks /Create /TN "XKScreenDriver" /XML "D:\Code\Xingcan-Xiaolan-Drive\.tools\task_u16.xml" /F >> "%LOG%" 2>&1
echo step2b_errorlevel=%errorlevel% >> "%LOG%"

:done
echo [3/3] final state: >> "%LOG%"
powershell -NoProfile -Command "$t = Get-ScheduledTask -TaskName XKScreenDriver -ErrorAction SilentlyContinue; if ($t) { Write-Output ('RESULT OK: ' + $t.Actions[0].Execute) } else { Write-Output 'RESULT FAIL: task still missing' }" >> "%LOG%" 2>&1
type "%LOG%"

echo.
echo   If you see "RESULT OK", autostart is repaired.
echo   This window closes in 15 seconds.
timeout /t 15 /nobreak >nul
