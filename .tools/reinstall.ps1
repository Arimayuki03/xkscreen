# Elevated: uninstall the old (Program Files) build, install the new C:\XkScreen
# build, then verify tasks + service.
$log = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\reinstall_result.txt'
"== reinstall $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -Encoding utf8 $log
function Say($m) { $m | Out-File -Append -Encoding utf8 $log; Write-Output $m }

Say "--- stop running instances ---"
& taskkill /IM XkScreen.Gui.exe /F 2>&1 | Out-File -Append -Encoding utf8 $log
& taskkill /IM XkScreen.Service.exe /F 2>&1 | Out-File -Append -Encoding utf8 $log
Start-Sleep -Seconds 2

Say "--- uninstall old build ---"
$u = 'C:\Program Files\XkScreen\unins000.exe'
if (Test-Path $u) {
    $p = Start-Process -FilePath $u -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
    Say "uninstaller exit=$($p.ExitCode)"
} else { Say "old uninstaller not found" }
Start-Sleep -Seconds 3
Say "old dir exists: $(Test-Path 'C:\Program Files\XkScreen')"

Say "--- install new build ---"
$ip = Start-Process -FilePath 'D:\Code\Xingcan-Xiaolan-Drive\dist\XkScreen-Setup-0.2.0.exe' `
      -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/LOG=D:\Code\Xingcan-Xiaolan-Drive\dist\install2.log' -Wait -PassThru
Say "installer exit=$($ip.ExitCode)"
Say "new exe exists: $(Test-Path 'C:\XkScreen\XkScreen.Service.exe')"
Say "vendor dlls: $((Get-ChildItem 'C:\XkScreen\vendor' -Filter *.dll -ErrorAction SilentlyContinue).Count)"

Say "--- tasks ---"
$st = Join-Path $env:SystemRoot 'System32\schtasks.exe'
function Q($name) {
    $o = Join-Path $env:TEMP 'rq.txt'
    & $st /Query /TN $name /V /FO LIST > $o 2>&1
    (Get-Content $o -ErrorAction SilentlyContinue) |
        Where-Object { $_ -match '任务名|要运行的任务|上次结果|作为用户运行|计划类型' } |
        ForEach-Object { Say ("$name : " + $_.Trim()) }
}
Q 'XKScreenDriver'
Q 'XKScreenDriverWatch'

Say "--- service ---"
Start-Sleep -Seconds 12
$svc = Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue
if ($svc) { Say "service pid=$($svc.Id) session=$($svc.SessionId) path=$($svc.Path)" } else { Say "SERVICE NOT RUNNING" }
Say "done"
