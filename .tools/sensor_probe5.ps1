# Probe 5: replicate the service's startup order 1:1, then observe the
# ReadRunData state machine once per second and print every intermediate
# value the vendor code keeps private.
$ErrorActionPreference = 'Continue'
$dir = 'D:\Code\Xingcan-Xiaolan-Drive\official'
Set-Location $dir

[void][Reflection.Assembly]::LoadFrom("$dir\Newtonsoft.Json.dll")
$lib = [Reflection.Assembly]::LoadFrom("$dir\XKWLib.dll")
[void][Reflection.Assembly]::LoadFrom("$dir\HardwareHelp64.dll")
try { [void][Reflection.Assembly]::LoadFrom("$dir\TempComm.dll") } catch { }

$tHelp = $lib.GetType('XKWLib.XKWLibHelp', $true)
$miStart = $tHelp.GetMethod('Start')
$help = [Activator]::CreateInstance($tHelp)
$ok = $miStart.Invoke($help, @('SystemTemperatureMonitoring'))
Write-Output ("Start -> " + $ok)

$fiDelay = $tHelp.GetField('usb_send_delay', [Reflection.BindingFlags]'NonPublic,Instance')
if ($fiDelay) { $fiDelay.SetValue($help, 120000) }
$fiThread = $tHelp.GetField('thread_flag', [Reflection.BindingFlags]'NonPublic,Instance')
if ($fiThread) { $fiThread.SetValue($help, $false) }

$fiHw = $tHelp.GetField('hardware', [Reflection.BindingFlags]'NonPublic,Instance')
$hw = $fiHw.GetValue($help)
$ht = $hw.GetType()

function Get-Field($obj, $name) {
    $t = $obj.GetType()
    while ($t -ne $null) {
        $f = $t.GetField($name, [Reflection.BindingFlags]'NonPublic,Instance,Public')
        if ($f) { return $f.GetValue($obj) }
        $t = $t.BaseType
    }
    return $null
}
function Get-PField($obj, $name) {
    $t = $obj.GetType()
    while ($t -ne $null) {
        $f = $t.GetField($name, [Reflection.BindingFlags]'NonPublic,Instance,Public')
        if ($f) { return $f }
        $t = $t.BaseType
    }
    return $null
}

$pi = $ht.GetProperty('InitState')
Write-Output ("InitState = " + $pi.GetValue($hw, $null))
$rrd = $ht.GetMethod('ReadRunData')
$rsd = $ht.GetMethod('ReadSystemData')
$sd = $ht.GetProperty('SystemData').GetValue($hw, $null)
$sdt = $sd.GetType()
$gm = $null
foreach ($m in $sdt.GetMethods()) { if ($m.Name -eq 'GetSystemRunData' -and $m.GetParameters().Length -eq 1) { $gm = $m; break } }
$enumT = $gm.GetParameters()[0].ParameterType

for ($i = 1; $i -le 20; $i++) {
    $line = "t=$i "
    $ss = Get-Field $hw 'sharedSystem'
    $sr = Get-Field $hw 'sharedRunData'
    $line += ("sharedSystem=" + $(if ($null -eq $ss) { 'null' } else { 'ok' }) + " ")
    $line += ("sharedRunData=" + $(if ($null -eq $sr) { 'null' } else { 'ok' }) + " ")
    if ($null -ne $sr) {
        $srt = $sr.GetType()
        $cn = $srt.GetProperty('CreateNew').GetValue($sr, $null)
        $d = $sr.Read()
        if ($null -eq $d) { $line += "RunData.read=null " }
        else {
            $tick = $d.GetType().GetProperty('tick').GetValue($d, $null)
            $str = $d.GetType().GetMethod('GetString').Invoke($d, $null)
            $len = if ($null -ne $str) { $str.Length } else { -1 }
            $line += ("CreateNew=$cn age=" + ([Environment]::TickCount - $tick) + " len=$len ")
        }
    }
    try { $r = $rrd.Invoke($hw, $null); $line += "ReadRunData=$r " }
    catch { $line += ("ReadRunData=EX(" + $_.Exception.InnerException.GetType().Name + ") ") }
    foreach ($n in @('Cpu','Gpu','Fan')) {
        $ev = [Enum]::Parse($enumT, $n)
        $di = $gm.Invoke($sd, @($ev))
        if ($null -eq $di) { $line += "$n=null " } else { $line += ("$n=" + $di.GetType().GetProperty('Size').GetValue($di, $null) + " ") }
    }
    $ar = Get-Field $hw '_autoRefresh'
    $tr = Get-Field $hw '_threadRefresh'
    $line += ("autoRefresh=$ar thread=" + $(if ($null -eq $tr) { 'null' } else { 'ok' }))
    Write-Output $line
    Start-Sleep -Milliseconds 1000
}
Write-Output "probe5 done"
