# Elevated diagnostic 2: dump the task definition, last run result, the service
# log in the new location, and recent task-scheduler events.
$out = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\task_test2_result.txt'
"== task diag2 $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -Encoding utf8 $out
$st = Join-Path $env:SystemRoot 'System32\schtasks.exe'

function Run-ST($label, $argList) {
    $o = Join-Path $env:TEMP 'st2_o.txt'
    $e = Join-Path $env:TEMP 'st2_e.txt'
    $p = Start-Process -FilePath $st -ArgumentList $argList -Wait -PassThru -NoNewWindow `
         -RedirectStandardOutput $o -RedirectStandardError $e
    "--- $label (exit=$($p.ExitCode)) ---" | Out-File -Append -Encoding utf8 $out
    (Get-Content $o -ErrorAction SilentlyContinue) | Out-File -Append -Encoding utf8 $out
    (Get-Content $e -ErrorAction SilentlyContinue) | Out-File -Append -Encoding utf8 $out
}

Run-ST 'verbose-query' @('/Query', '/TN', 'XKScreenDriver', '/V', '/FO', 'LIST')
Run-ST 'xml' @('/Query', '/TN', 'XKScreenDriver', '/XML')

"--- service log in install dir ---" | Out-File -Append -Encoding utf8 $out
if (Test-Path 'C:\Program Files\XkScreen\xkscreen_service.log') {
    Get-Content 'C:\Program Files\XkScreen\xkscreen_service.log' -Tail 20 | Out-File -Append -Encoding utf8 $out
} else { "no service log" | Out-File -Append -Encoding utf8 $out }

"--- task scheduler events (last 8) ---" | Out-File -Append -Encoding utf8 $out
try {
    Get-WinEvent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -MaxEvents 8 -ErrorAction Stop |
        ForEach-Object { "$($_.TimeCreated) [$($_.Id)] $($_.Message -replace "`r?`n", ' ')" } |
        Out-File -Append -Encoding utf8 $out
} catch { "event log read failed: $($_.Exception.Message)" | Out-File -Append -Encoding utf8 $out }
"done" | Out-File -Append -Encoding utf8 $out
