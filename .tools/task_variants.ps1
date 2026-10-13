# Elevated: isolate why task creation fails - plain path vs spaced path vs 8.3 short path.
$log = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\task_variants_result.txt'
"== variants $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -Encoding utf8 $log
function Say($m) { $m | Out-File -Append -Encoding utf8 $log; Write-Output $m }

$bat = Join-Path $env:TEMP 'xk_var.bat'
$body = @'
@echo off
echo [1] plain path, no quotes
schtasks /Create /F /TN XKV1 /TR "C:\Windows\System32\cmd.exe" /SC ONSTART /RU SYSTEM /RL HIGHEST
echo    exit=%errorlevel%
schtasks /Delete /TN XKV1 /F >nul 2>&1

echo [2] spaced path, escaped quotes
schtasks /Create /F /TN XKV2 /TR "\"C:\Program Files\XkScreen\XkScreen.Service.exe\"" /SC ONSTART /RU SYSTEM /RL HIGHEST
echo    exit=%errorlevel%
schtasks /Delete /TN XKV2 /F >nul 2>&1

echo [3] spaced path, 8.3 short name
for %%I in ("C:\Program Files\XkScreen\XkScreen.Service.exe") do echo    short=%%~sI
schtasks /Create /F /TN XKV3 /TR "C:\PROGRA~1\XkScreen\XkScreen.Service.exe" /SC ONSTART /RU SYSTEM /RL HIGHEST
echo    exit=%errorlevel%
schtasks /Delete /TN XKV3 /F >nul 2>&1

echo [4] spaced path, no inner quotes (control)
schtasks /Create /F /TN XKV4 /TR "C:\Program Files\XkScreen\XkScreen.Service.exe" /SC ONSTART /RU SYSTEM /RL HIGHEST
echo    exit=%errorlevel%
schtasks /Query /TN XKV4 /XML 2>nul | findstr /C:"<Command>" /C:"<Arguments>"
schtasks /Delete /TN XKV4 /F >nul 2>&1
'@
Set-Content -Path $bat -Value $body -Encoding Ascii
$o = & cmd.exe /c $bat 2>&1
Say ($o -join "`n")
Say "done"
