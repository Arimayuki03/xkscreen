# Probe 10: time the vendor DLL calls (sampling + each getter) so we can see
# where the service's ~10% of one core actually goes.
$ErrorActionPreference = 'Continue'
$dir = 'C:\XkScreen\vendor'
Set-Location $dir

[void][Reflection.Assembly]::LoadFrom("$dir\Newtonsoft.Json.dll")
$lib = [Reflection.Assembly]::LoadFrom("$dir\XKWLib.dll")
[void][Reflection.Assembly]::LoadFrom("$dir\HardwareHelp64.dll")

$tHelp = $lib.GetType('XKWLib.XKWLibHelp', $true)
$miStart = $tHelp.GetMethod('Start')
$help = [Activator]::CreateInstance($tHelp)
$ok = $miStart.Invoke($help, @('SystemTemperatureMonitoring'))
Write-Output ("Start -> " + $ok)
$fiThread = $tHelp.GetField('thread_flag', [Reflection.BindingFlags]'NonPublic,Instance')
if ($fiThread) { $fiThread.SetValue($help, $false) }
Start-Sleep -Seconds 2   # let any in-flight vendor init finish (double Init2 = AV crash)
$fiHw = $tHelp.GetField('hardware', [Reflection.BindingFlags]'NonPublic,Instance')
$hw = $fiHw.GetValue($help)
$ht = $hw.GetType()

# wait for init
$pi = $ht.GetProperty('InitState')
$miHwStart = $ht.GetMethod('Start')
for ($i = 0; $i -lt 60 -and -not $pi.GetValue($hw, $null); $i++) { try { [void]$miHwStart.Invoke($hw, $null) } catch {}; Start-Sleep -Milliseconds 300 }
Write-Output ("InitState = " + $pi.GetValue($hw, $null))

function Time-It($label, $mi, $n) {
    if (-not $mi) { Write-Output "$label -> method not found"; return }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($k = 0; $k -lt $n; $k++) { try { [void]$mi.Invoke($hw, $null) } catch {} }
    $sw.Stop()
    Write-Output ("$label : " + [Math]::Round($sw.Elapsed.TotalMilliseconds / $n, 2) + " ms/call")
}

Time-It 'ReadRunData (full sampling pass)' ($ht.GetMethod('ReadRunData')) 10
Time-It 'GetCpuRunInfo' ($ht.GetMethod('GetCpuRunInfo')) 10
Time-It 'GetGpuRunInfo' ($ht.GetMethod('GetGpuRunInfo')) 10
Time-It 'GetRAMRunInfo' ($ht.GetMethod('GetRAMRunInfo')) 10
Time-It 'GetFanSpeed' ($ht.GetMethod('GetFanSpeed')) 10
Time-It 'GetNetwork' ($ht.GetMethod('GetNetwork')) 10
foreach ($n in 'GetWin32_DiskDrive') { $m = $ht.GetMethod($n); if ($m) { Time-It $n $m 10 } }

# Time the pure getters our service calls every cycle
$sd = $ht.GetProperty('SystemData').GetValue($hw, $null)
$gm = $null
foreach ($m in $sd.GetType().GetMethods()) { if ($m.Name -eq 'GetSystemRunData' -and $m.GetParameters().Length -eq 1) { $gm = $m; break } }
$enumT = $gm.GetParameters()[0].ParameterType
foreach ($n in 'Cpu','Gpu','Ram','Fan','HHD') {
    $ev = [Enum]::Parse($enumT, $n)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($k = 0; $k -lt 20; $k++) { try { [void]$gm.Invoke($sd, @($ev)) } catch {} }
    $sw.Stop()
    Write-Output ("GetSystemRunData($n) : " + [Math]::Round($sw.Elapsed.TotalMilliseconds / 20, 2) + " ms/call")
}
Write-Output "probe10 done"
