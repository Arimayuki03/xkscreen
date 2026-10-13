# Elevated: isolate why /TR pointing at our exe fails while other targets work.
$log = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\task_matrix_result.txt'
"== matrix $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -Encoding utf8 $log
function Say($m) { $m | Out-File -Append -Encoding utf8 $log; Write-Output $m }

Say "--- target file facts ---"
$exe = 'C:\XkScreen\XkScreen.Service.exe'
$fi = Get-Item $exe -ErrorAction SilentlyContinue
if ($fi) {
    Say ("exe size=" + $fi.Length + "  created=" + $fi.CreationTime + "  modified=" + $fi.LastWriteTime)
    $h = (Get-FileHash $exe -Algorithm SHA256).Hash
    Say ("exe sha256=" + $h)
    Say ("streams: " + ((Get-Item $exe -Stream * -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Stream) -join ','))
    $acl = Get-Acl $exe
    Say ("acl owner=" + $acl.Owner)
} else { Say "exe NOT FOUND" }
$repoHash = (Get-FileHash 'D:\Code\Xingcan-Xiaolan-Drive\product\XkScreen.Service\bin\Release\net48\XkScreen.Service.exe' -Algorithm SHA256).Hash
Say ("repo build sha256=" + $repoHash)

Say "--- matrix ---"
$bat = Join-Path $env:TEMP 'xk_m.bat'
$body = @'
@echo off
if not exist C:\XkTest mkdir C:\XkTest
copy /y "C:\XkScreen\XkScreen.Service.exe" "C:\XkTest\svc.exe" >nul
copy /y "C:\XkScreen\XkScreen.Service.exe" "C:\XkScreen\svc2.exe" >nul

echo [A] own exe, ONSTART
schtasks /Create /F /TN XKM1 /TR "C:\XkScreen\XkScreen.Service.exe" /SC ONSTART /RU SYSTEM /RL HIGHEST
echo     exit=%errorlevel%
schtasks /Delete /TN XKM1 /F >nul 2>&1

echo [B] copy in C:\XkTest, ONSTART
schtasks /Create /F /TN XKM2 /TR "C:\XkTest\svc.exe" /SC ONSTART /RU SYSTEM /RL HIGHEST
echo     exit=%errorlevel%
schtasks /Delete /TN XKM2 /F >nul 2>&1

echo [C] copy as svc2.exe same dir, ONSTART
schtasks /Create /F /TN XKM3 /TR "C:\XkScreen\svc2.exe" /SC ONSTART /RU SYSTEM /RL HIGHEST
echo     exit=%errorlevel%
schtasks /Delete /TN XKM3 /F >nul 2>&1

echo [D] watch.cmd with ONSTART
schtasks /Create /F /TN XKM4 /TR "C:\XkScreen\watch.cmd" /SC ONSTART /RU SYSTEM /RL HIGHEST
echo     exit=%errorlevel%
schtasks /Delete /TN XKM4 /F >nul 2>&1

echo [E] own exe, ONCE trigger
schtasks /Create /F /TN XKM5 /TR "C:\XkScreen\XkScreen.Service.exe" /SC ONCE /ST 23:59 /RU SYSTEM /RL HIGHEST
echo     exit=%errorlevel%
schtasks /Delete /TN XKM5 /F >nul 2>&1

echo [F] own exe, ONSTART, without /RL
schtasks /Create /F /TN XKM6 /TR "C:\XkScreen\XkScreen.Service.exe" /SC ONSTART /RU SYSTEM
echo     exit=%errorlevel%
schtasks /Delete /TN XKM6 /F >nul 2>&1
'@
Set-Content -Path $bat -Value $body -Encoding Ascii
$o = & cmd.exe /c $bat 2>&1
Say ($o -join "`n")

Say "--- start service manually (screen recovery) ---"
Start-Process -FilePath $exe -WindowStyle Minimized
Start-Sleep -Seconds 8
$svc = Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue
if ($svc) { Say "service pid=$($svc.Id) session=$($svc.SessionId)" } else { Say "SERVICE NOT RUNNING" }
Say "done"
