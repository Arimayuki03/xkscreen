# Elevated recovery: recreate the driver task with the proven schtasks /TR form,
# start it, dump the resulting task XML (to check the 72h limit) and test
# whether the CIM registration path works at all on this machine.
$log = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\recover_result.txt'
"== recover $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -Encoding utf8 $log
function Say($m) { $m | Out-File -Append -Encoding utf8 $log; Write-Output $m }

# 1) proven /TR form via a temporary batch file (no PS quoting involved)
$bat = Join-Path $env:TEMP 'xk_task.bat'
$batBody = @"
@echo off
schtasks /Create /F /TN XKScreenDriver /TR "\"C:\Program Files\XkScreen\XkScreen.Service.exe\"" /SC ONSTART /RU SYSTEM /RL HIGHEST
echo create exit=%errorlevel%
schtasks /Run /TN XKScreenDriver
echo run exit=%errorlevel%
"@
Set-Content -Path $bat -Value $batBody -Encoding Ascii
$o = & cmd.exe /c $bat 2>&1
Say "bat output: $o"

Start-Sleep -Seconds 12
$svc = Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue
if ($svc) { Say "service pid=$($svc.Id) session=$($svc.SessionId)" } else { Say "SERVICE NOT RUNNING" }

# 2) task XML of the created task (check ExecutionTimeLimit / battery settings)
$xmlOut = Join-Path $env:TEMP 'xk_cur.xml'
& schtasks /Query /TN XKScreenDriver /XML > $xmlOut 2>&1
Say "--- current task XML ---"
(Get-Content $xmlOut -ErrorAction SilentlyContinue) | Where-Object { $_ -match 'ExecutionTimeLimit|DisallowStart|StopIfGoing|Command|UserId|RunLevel|MultipleInstances' } |
    ForEach-Object { Say $_.Trim() }

# 3) does the CIM path work for a plain task at all?
try {
    Register-ScheduledTask -TaskName 'XKSTest5' -Action (New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit') `
        -Trigger (New-ScheduledTaskTrigger -AtStartup) -Force -ErrorAction Stop | Out-Null
    Say "CIM plain task: OK"
    Unregister-ScheduledTask -TaskName 'XKSTest5' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
} catch { Say "CIM plain task: FAIL - $($_.Exception.Message)" }

Say "done"
