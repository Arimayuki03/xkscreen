# Elevated: full task-scheduler diagnosis + bring the screen back by starting
# the service directly (autostart task to be fixed based on findings).
$log = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\diag_task_result.txt'
"== diag $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -Encoding utf8 $log
function Say($m) { $m | Out-File -Append -Encoding utf8 $log; Write-Output $m }

Say "--- scheduler service ---"
$s = Get-Service Schedule
Say "Schedule: $($s.Status) / $($s.StartType)"
Say "--- disk C: free ---"
$d = Get-PSDrive C
Say ("C: free = " + [Math]::Round($d.Free / 1GB, 2) + " GB")
Say "--- leftover task files ---"
Get-ChildItem 'C:\Windows\System32\Tasks' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'XKScreen|XKSTest' } |
    ForEach-Object { Say ("file: " + $_.Name + "  " + $_.LastWriteTime) }
Say "--- system log: TaskScheduler errors (last 40 min) ---"
try {
    Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddMinutes(-40)} -ErrorAction Stop |
        Where-Object { $_.ProviderName -match 'TaskScheduler' -or $_.Message -match '任务计划' } |
        Select-Object -First 12 |
        ForEach-Object { Say ("$($_.TimeCreated.ToString('HH:mm:ss')) [$($_.ProviderName)/$($_.Id)] $(($_.Message -replace "`r?`n", ' ').Substring(0, [Math]::Min(220, $_.Message.Length)))") }
} catch { Say "system log: $($_.Exception.Message)" }
Say "--- TaskScheduler operational log state ---"
try {
    $lg = Get-WinEvent -ListLog 'Microsoft-Windows-TaskScheduler/Operational' -ErrorAction Stop
    Say "enabled=$($lg.IsEnabled) records=$($lg.RecordCount)"
} catch { Say "operational log: $($_.Exception.Message)" }

Say "--- start service directly (screen recovery) ---"
try {
    Start-Process -FilePath 'C:\Program Files\XkScreen\XkScreen.Service.exe' -WindowStyle Minimized
    Start-Sleep -Seconds 10
    $svc = Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue
    if ($svc) { Say "service pid=$($svc.Id) session=$($svc.SessionId)" } else { Say "SERVICE NOT RUNNING" }
} catch { Say "start exc: $($_.Exception.Message)" }
Say "done"
