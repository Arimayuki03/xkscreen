# XkScreen watchdog (runs hourly as SYSTEM via the XKScreenDriverWatch task).
# - restarts the driver if the service process is gone (crash recovery)
# - restarts it after ~48h uptime: schtasks-created tasks carry a default 72h
#   execution-time limit which would otherwise kill the screen every 3 days
$ErrorActionPreference = 'Continue'
$task = 'XKScreenDriver'
$st = Join-Path $env:SystemRoot 'System32\schtasks.exe'

$svc = Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue
$needRestart = $false
$reason = ''

if (-not $svc) {
    $needRestart = $true
    $reason = 'service not running'
} else {
    $up = (Get-Date) - $svc.StartTime
    if ($up.TotalHours -ge 48) {
        $needRestart = $true
        $reason = "uptime " + [Math]::Round($up.TotalHours, 1) + "h"
    }
}

if ($needRestart) {
    Write-Output ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " restart: " + $reason)
    if ($svc) { Stop-Process -Id $svc.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    & $st /End /TN $task | Out-Null
    Start-Sleep -Seconds 1
    & $st /Run /TN $task | Out-Null
    Write-Output ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " restarted")
}
