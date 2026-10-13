# Elevated bisect: find which task definition ingredient breaks registration.
$log = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\task_bisect_result.txt'
"== bisect $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -Encoding utf8 $log
function Say($m) { $m | Out-File -Append -Encoding utf8 $log; Write-Output $m }

$exe = 'C:\Program Files\XkScreen\XkScreen.Service.exe'

function Try-Reg($name, $useSettings, $limitZero) {
    try {
        $a = New-ScheduledTaskAction -Execute $exe
        $t = New-ScheduledTaskTrigger -AtStartup
        $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        if ($useSettings) {
            if ($limitZero) {
                $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                     -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
            } else {
                $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                     -MultipleInstances IgnoreNew -StartWhenAvailable
            }
            Register-ScheduledTask -TaskName $name -Action $a -Trigger $t -Principal $p -Settings $s -Force -ErrorAction Stop | Out-Null
        } else {
            Register-ScheduledTask -TaskName $name -Action $a -Trigger $t -Principal $p -Force -ErrorAction Stop | Out-Null
        }
        Say "$name : OK"
        return $true
    } catch {
        Say "$name : FAIL - $($_.Exception.Message)"
        return $false
    }
}

Try-Reg 'XKSTest1' $false $false | Out-Null
Try-Reg 'XKSTest2' $true  $false | Out-Null
Try-Reg 'XKSTest3' $true  $true  | Out-Null
Try-Reg 'XKSTest4' $true  $false | Out-Null

"--- scheduler events (last 10) ---" | Out-File -Append -Encoding utf8 $log
try {
    Get-WinEvent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -MaxEvents 10 -ErrorAction Stop |
        ForEach-Object { "$($_.TimeCreated.ToString('HH:mm:ss')) [$($_.Id)] $(($_.Message -replace "`r?`n", ' ').Substring(0, [Math]::Min(180, $_.Message.Length)))" } |
        Out-File -Append -Encoding utf8 $log
} catch { "no events: $($_.Exception.Message)" | Out-File -Append -Encoding utf8 $log }

"--- cleanup ---" | Out-File -Append -Encoding utf8 $log
foreach ($n in 'XKSTest1','XKSTest2','XKSTest3','XKSTest4') {
    try { Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction Stop; Say "$n removed" }
    catch { Say "$n remove: $($_.Exception.Message)" }
}
Say "done"
