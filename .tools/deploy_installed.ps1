# Elevated: update the installed copy under C:\XkScreen from the repo build
# (the GUI must be closed first; the caller relaunches it afterwards).
$root = 'D:\Code\Xingcan-Xiaolan-Drive'
$app = 'C:\XkScreen'
$src = "$root\product\XkScreen.Gui\bin\Release\net8.0-windows"
$out = "$root\.tools\deploy_installed_result.txt"
"== deploy installed $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -Encoding utf8 $out

Get-Process 'XkScreen.Gui' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

foreach ($f in 'XkScreen.Gui.exe', 'XkScreen.Gui.dll', 'XkScreen.Gui.deps.json', 'XkScreen.Gui.runtimeconfig.json') {
    Copy-Item -Force (Join-Path $src $f) (Join-Path "$app\gui" $f)
}
Copy-Item -Force "$root\product\XkScreen.Service\bin\Release\net48\XkScreen.Service.exe" "$app\XkScreen.Service.exe"
robocopy "$root\product\frontend\out" "$app\gui\web" /MIR /NFL /NDL /NJH /NJS | Out-Null
"files copied: gui build $(Get-Item (Join-Path $src 'XkScreen.Gui.exe')).LastWriteTime" | Out-File -Append -Encoding utf8 $out
"done" | Out-File -Append -Encoding utf8 $out
