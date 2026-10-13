# Elevated diagnostic: reproduce the task registration the installer performs,
# capture schtasks output/exit codes, then create + run the task.
$out = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\task_test_result.txt'
$exe = 'C:\Program Files\XkScreen\XkScreen.Service.exe'
"== task test $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -Encoding utf8 $out
"exe exists: $(Test-Path $exe)" | Out-File -Append -Encoding utf8 $out

$st = Join-Path $env:SystemRoot 'System32\schtasks.exe'

function Run-ST($label, $argList) {
    $o = Join-Path $env:TEMP 'st_o.txt'
    $e = Join-Path $env:TEMP 'st_e.txt'
    $p = Start-Process -FilePath $st -ArgumentList $argList -Wait -PassThru -NoNewWindow `
         -RedirectStandardOutput $o -RedirectStandardError $e
    "$label exit=$($p.ExitCode)" | Out-File -Append -Encoding utf8 $out
    (Get-Content $o -ErrorAction SilentlyContinue) | Out-File -Append -Encoding utf8 $out
    (Get-Content $e -ErrorAction SilentlyContinue) | Out-File -Append -Encoding utf8 $out
}

Run-ST 'delete-old' @('/Delete', '/TN', 'XKScreenDriver', '/F')
Run-ST 'create' @('/Create', '/F', '/TN', 'XKScreenDriver', '/TR', ('"' + $exe + '"'),
                  '/SC', 'ONSTART', '/RU', 'SYSTEM', '/RL', 'HIGHEST')
Run-ST 'query' @('/Query', '/TN', 'XKScreenDriver', '/FO', 'LIST')
Run-ST 'run' @('/Run', '/TN', 'XKScreenDriver')

Start-Sleep -Seconds 10
$svc = Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue
if ($svc) { "service running pid=$($svc.Id) session=$($svc.SessionId)" | Out-File -Append -Encoding utf8 $out }
else { "SERVICE NOT RUNNING" | Out-File -Append -Encoding utf8 $out }
"done" | Out-File -Append -Encoding utf8 $out
