# Probe 6: validate the planned fix - disable the send thread first, then do a
# deterministic init loop (hardware.Start until InitState), ensure OpenRefresh
# is running, watch data arrive, and read the CPUID SDK's GPU fan APIs.
$ErrorActionPreference = 'Continue'
$dir = 'D:\Code\Xingcan-Xiaolan-Drive\official'
Set-Location $dir

[void][Reflection.Assembly]::LoadFrom("$dir\Newtonsoft.Json.dll")
$lib = [Reflection.Assembly]::LoadFrom("$dir\XKWLib.dll")
[void][Reflection.Assembly]::LoadFrom("$dir\HardwareHelp64.dll")

$tHelp = $lib.GetType('XKWLib.XKWLibHelp', $true)
$miStart = $tHelp.GetMethod('Start')
$help = [Activator]::CreateInstance($tHelp)
$ok = $miStart.Invoke($help, @('SystemTemperatureMonitoring'))
Write-Output ("Start -> " + $ok)

# 1) silence the vendor send thread immediately
$fiThread = $tHelp.GetField('thread_flag', [Reflection.BindingFlags]'NonPublic,Instance')
if ($fiThread) { $fiThread.SetValue($help, $false); Write-Output 'thread_flag=false (immediate)' }

# 2) deterministic init loop
$fiHw = $tHelp.GetField('hardware', [Reflection.BindingFlags]'NonPublic,Instance')
$hw = $fiHw.GetValue($help)
$ht = $hw.GetType()
$pi = $ht.GetProperty('InitState')
$miHwStart = $ht.GetMethod('Start')
$inited = $pi.GetValue($hw, $null)
$att = 0
while (-not $inited -and $att -lt 50) {
    $att++
    try { [void]$miHwStart.Invoke($hw, $null) } catch { Write-Output ("hwStart EX: " + $_.Exception.InnerException.Message) }
    $inited = $pi.GetValue($hw, $null)
    if (-not $inited) { Start-Sleep -Milliseconds 200 }
}
Write-Output ("InitState after loop = $inited (attempts=$att)")

# 3) ensure the 1s refresh thread is running
$fiAuto = $ht.GetField('_autoRefresh', [Reflection.BindingFlags]'NonPublic,Instance')
$miOpen = $ht.GetMethod('OpenRefresh')
$auto = $fiAuto.GetValue($hw)
Write-Output ("autoRefresh before = $auto")
if (-not $auto) { [void]$miOpen.Invoke($hw, @(1000)); Write-Output ("autoRefresh after OpenRefresh = " + $fiAuto.GetValue($hw)) }

# 4) watch data arrive
$rrd = $ht.GetMethod('ReadRunData')
$sd = $ht.GetProperty('SystemData').GetValue($hw, $null)
$sdt = $sd.GetType()
$gm = $null
foreach ($m in $sdt.GetMethods()) { if ($m.Name -eq 'GetSystemRunData' -and $m.GetParameters().Length -eq 1) { $gm = $m; break } }
$enumT = $gm.GetParameters()[0].ParameterType
function Sizes() {
    $out = @()
    foreach ($n in @('Cpu','Gpu','Ram','Fan','HHD')) {
        $ev = [Enum]::Parse($enumT, $n)
        $di = $gm.Invoke($sd, @($ev))
        if ($null -eq $di) { $out += "$n=null" } else { $out += ("$n=" + $di.GetType().GetProperty('Size').GetValue($di, $null)) }
    }
    return ($out -join ' ')
}
for ($i = 1; $i -le 12; $i++) {
    $r = $rrd.Invoke($hw, $null)
    Write-Output ("t=$i ReadRunData=$r " + (Sizes))
    Start-Sleep -Milliseconds 1000
}

# 5) GPU fan via the CPUID SDK
$fiSdk = $ht.GetField('_pSdk', [Reflection.BindingFlags]'NonPublic,Instance')
if ($fiSdk) {
    $sdk = $fiSdk.GetValue($hw)
    if ($null -ne $sdk) {
        $st = $sdk.GetType()
        foreach ($mn in @('GetDisplayAdapterFanSpeed','GetDisplayAdapterFanPWM')) {
            $mi = $st.GetMethod($mn)
            if (-not $mi) { Write-Output ("$mn -> not found"); continue }
            foreach ($idx in 0..2) {
                try { $v = $mi.Invoke($sdk, @($idx)); Write-Output ("$mn($idx) = $v") }
                catch { Write-Output ("$mn($idx) EX: " + $_.Exception.InnerException.Message) }
            }
        }
    } else { Write-Output '_pSdk is null' }
} else { Write-Output '_pSdk field not found' }

# also dump the GPU dict keys for reference
$ev = [Enum]::Parse($enumT, 'Gpu')
$di = $gm.Invoke($sd, @($ev))
if ($null -ne $di -and $di.GetType().GetProperty('Size').GetValue($di, $null) -gt 0) {
    foreach ($p in $di.GetType().GetProperties()) {
        if ($p.GetIndexParameters().Length -eq 1) {
            $it = $p.GetValue($di, @(0))
            if ($it) { Write-Output ("GPU item0: " + (($it.Keys | ForEach-Object { $_ + '=' + $it[$_] }) -join ' ')) }
            break
        }
    }
}
Write-Output "probe6 done"
