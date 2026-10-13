# Probe 2: inspect the vendor run-data shared memory state (tick / CreateNew /
# payload) and step ReadRunData() twice to expose the takeover state machine.
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
$fiThread = $tHelp.GetField('thread_flag', [Reflection.BindingFlags]'NonPublic,Instance')
if ($fiThread) { $fiThread.SetValue($help, $false) }
$fiHw = $tHelp.GetField('hardware', [Reflection.BindingFlags]'NonPublic,Instance')
$hw = $fiHw.GetValue($help)
$ht = $hw.GetType()

function Get-PrivateField($obj, $name) {
    $t = $obj.GetType()
    while ($t -ne $null) {
        $f = $t.GetField($name, [Reflection.BindingFlags]'NonPublic,Instance')
        if ($f) { return $f }
        $t = $t.BaseType
    }
    return $null
}

$fSrd = Get-PrivateField $hw 'sharedRunData'
$fDelay = Get-PrivateField $hw '_delay'
$srd = if ($fSrd) { $fSrd.GetValue($hw) } else { $null }
$delay = if ($fDelay) { $fDelay.GetValue($hw) } else { -1 }
Write-Output ("_delay = " + $delay + " ; TickCount now = " + [Environment]::TickCount)
if (-not $srd) { Write-Output 'sharedRunData field not found'; exit 1 }
$srt = $srd.GetType()
Write-Output ("SharedMemory: name=" + $srt.GetProperty('Name').GetValue($srd, $null) +
              " CreateNew=" + $srt.GetProperty('CreateNew').GetValue($srd, $null) +
              " lastWriteTime=" + $srt.GetProperty('lastWriteTime').GetValue($srd, $null))

function Show-Shared($label) {
    try {
        $d = $srd.Read()
    } catch {
        Write-Output ("$label Read() EX: " + $_.Exception.Message); return
    }
    if ($null -eq $d) { Write-Output ("$label Read() -> null"); return }
    $dt = $d.GetType()
    $tick = $dt.GetProperty('tick').GetValue($d, $null)
    $str = $dt.GetMethod('GetString').Invoke($d, $null)
    $len = if ($null -ne $str) { $str.Length } else { -1 }
    Write-Output ("$label tick=$tick age_ms=" + ([Environment]::TickCount - $tick) + " payload_len=$len")
    if ($len -gt 0) { Write-Output ("   head: " + $str.Substring(0, [Math]::Min(200, $len))) }
}

Show-Shared 'before:'

$rrd = $ht.GetMethod('ReadRunData')
$r1 = $rrd.Invoke($hw, $null)
Write-Output ("ReadRunData#1 -> " + $r1)
Show-Shared 'after1:'

$sd = $ht.GetProperty('SystemData').GetValue($hw, $null)
$sdt = $sd.GetType()
$gm = $null
foreach ($m in $sdt.GetMethods()) { if ($m.Name -eq 'GetSystemRunData' -and $m.GetParameters().Length -eq 1) { $gm = $m; break } }
$enumT = $gm.GetParameters()[0].ParameterType
foreach ($n in @('Cpu','Gpu','Network','Ram','HHD','Fan')) {
    $ev = [Enum]::Parse($enumT, $n)
    $di = $gm.Invoke($sd, @($ev))
    if ($null -eq $di) { Write-Output ("  SystemData[$n] -> null") }
    else { Write-Output ("  SystemData[$n] -> Size=" + $di.GetType().GetProperty('Size').GetValue($di, $null)) }
}

$r2 = $rrd.Invoke($hw, $null)
Write-Output ("ReadRunData#2 -> " + $r2)
Show-Shared 'after2:'
foreach ($n in @('Cpu','Gpu','Network','Ram','HHD','Fan')) {
    $ev = [Enum]::Parse($enumT, $n)
    $di = $gm.Invoke($sd, @($ev))
    if ($null -eq $di) { Write-Output ("  SystemData[$n] -> null") }
    else { Write-Output ("  SystemData[$n] -> Size=" + $di.GetType().GetProperty('Size').GetValue($di, $null)) }
}
Write-Output ("CreateNew now = " + $srt.GetProperty('CreateNew').GetValue($srd, $null))
Write-Output "probe2 done"
