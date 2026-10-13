# Elevated: verify the watchdog self-heals a dead driver.
$log = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\watch_test_result.txt'
"== watch test $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -Encoding utf8 $log
function Say($m) { $m | Out-File -Append -Encoding utf8 $log; Write-Output $m }

$st = Join-Path $env:SystemRoot 'System32\schtasks.exe'
Remove-Item 'C:\XkScreen\watch.log' -ErrorAction SilentlyContinue

Say "--- kill the running service ---"
Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue | ForEach-Object {
    Say "killing pid $($_.Id) (session $($_.SessionId))"
    Stop-Process -Id $_.Id -Force
}
Start-Sleep -Seconds 3
Say "service present after kill: $((Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue) -ne $null)"

Say "--- run the watchdog task ---"
& $st /Run /TN XKScreenDriverWatch | Out-File -Append -Encoding utf8 $log
Start-Sleep -Seconds 25
$svc = Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue
if ($svc) { Say "service back: pid=$($svc.Id) session=$($svc.SessionId)" } else { Say "SERVICE STILL DOWN" }

Say "--- watch.log ---"
if (Test-Path 'C:\XkScreen\watch.log') { Get-Content 'C:\XkScreen\watch.log' | ForEach-Object { Say $_ } }
else { Say "(no watch.log)" }
Say "done"
