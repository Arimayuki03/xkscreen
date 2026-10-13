param([string]$Label = 'measure')
$map = @{}
Get-CimInstance Win32_Process | ForEach-Object { $map[[int]$_.ProcessId] = [int]$_.ParentProcessId }
function RootOf($p) {
    $cur = $p; $n = 0
    while ($cur -gt 0 -and $n -lt 10) {
        $par = 0; if ($map.ContainsKey($cur)) { $par = $map[$cur] }
        if ($par -eq 0) { break }
        $name = (Get-Process -Id $par -ErrorAction SilentlyContinue).ProcessName
        if ($name -eq 'XkScreen.Gui') { return $par }
        $cur = $par; $n++
    }
    return 0
}
$gui = @(Get-Process XkScreen.Gui -ErrorAction SilentlyContinue)
if ($gui.Count -eq 0) { Write-Output ("$Label : GUI not running (0 processes)"); exit }
$self = 0; foreach ($g in $gui) { $self += $g.WorkingSet64 }
$kids = 0; $kidsSum = 0
Get-Process msedgewebview2 -ErrorAction SilentlyContinue | ForEach-Object {
    if ((RootOf $_.Id) -eq $gui[0].Id) { $kids++; $kidsSum += $_.WorkingSet64 }
}
Write-Output ("$Label : GUI procs=" + $gui.Count + "  self=" + [Math]::Round($self / 1MB, 1) + " MB  webview2_children=" + $kids + "  children=" + [Math]::Round($kidsSum / 1MB, 1) + " MB  TOTAL=" + [Math]::Round(($self + $kidsSum) / 1MB, 1) + " MB")
