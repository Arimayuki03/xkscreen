# Elevated deploy + restart for the XkScreen service (needs admin: the SDK's
# CPUID driver can only be loaded elevated, and the running service has a
# high integrity level). Triggered via Start-Process -Verb RunAs.
$root = 'D:\Code\Xingcan-Xiaolan-Drive'
$out = "$root\.tools\deploy_elevated_result.txt"
"elevated deploy start $(Get-Date -Format 'HH:mm:ss')" | Out-File -Encoding ascii $out

Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

Copy-Item -Force "$root\product\XkScreen.Service\bin\Release\net48\XkScreen.Service.exe" "$root\official\XkScreen.Service.exe"
if (Test-Path "$root\product\frontend\out") {
    robocopy "$root\product\frontend\out" "$root\official\web" /MIR /NFL /NDL /NJH /NJS | Out-Null
}
"copied exe + web" | Out-File -Append -Encoding ascii $out

Start-Process -FilePath "$root\official\XkScreen.Service.exe" -WindowStyle Minimized
Start-Sleep -Seconds 8
$p = Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue
if ($p) { "service running pid=$($p.Id)" | Out-File -Append -Encoding ascii $out }
else { "SERVICE NOT RUNNING" | Out-File -Append -Encoding ascii $out }
"done $(Get-Date -Format 'HH:mm:ss')" | Out-File -Append -Encoding ascii $out
