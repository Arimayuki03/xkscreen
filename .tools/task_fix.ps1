# Elevated: replace the (broken) XKScreenDriver task with an XML-defined one
# and start the driver service from the installed location.
$out = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\task_fix_result.txt'
"== task fix $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -Encoding utf8 $out
$st = Join-Path $env:SystemRoot 'System32\schtasks.exe'
$xml = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\xkscreen_task.xml'

function Run-ST($label, $argList) {
    $o = Join-Path $env:TEMP 'stf_o.txt'
    $e = Join-Path $env:TEMP 'stf_e.txt'
    $p = Start-Process -FilePath $st -ArgumentList $argList -Wait -PassThru -NoNewWindow `
         -RedirectStandardOutput $o -RedirectStandardError $e
    "--- $label (exit=$($p.ExitCode)) ---" | Out-File -Append -Encoding utf8 $out
    (Get-Content $o -ErrorAction SilentlyContinue) | Out-File -Append -Encoding utf8 $out
    (Get-Content $e -ErrorAction SilentlyContinue) | Out-File -Append -Encoding utf8 $out
}

Run-ST 'delete'  @('/Delete', '/TN', 'XKScreenDriver', '/F')
Run-ST 'create'  @('/Create', '/F', '/TN', 'XKScreenDriver', '/XML', $xml)
Run-ST 'run'     @('/Run', '/TN', 'XKScreenDriver')

Start-Sleep -Seconds 12
$svc = Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue
if ($svc) { "service running pid=$($svc.Id) session=$($svc.SessionId) path=$($svc.Path)" | Out-File -Append -Encoding utf8 $out }
else { "SERVICE NOT RUNNING" | Out-File -Append -Encoding utf8 $out }
"done" | Out-File -Append -Encoding utf8 $out
