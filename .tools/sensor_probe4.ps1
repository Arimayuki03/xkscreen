# Probe 4: call ReadSystemData() and then each individual WMI getter used by
# the init path, printing the exceptions the vendor code hides.
$ErrorActionPreference = 'Continue'
$dir = 'D:\Code\Xingcan-Xiaolan-Drive\official'
Set-Location $dir

[void][Reflection.Assembly]::LoadFrom("$dir\Newtonsoft.Json.dll")
$lib = [Reflection.Assembly]::LoadFrom("$dir\XKWLib.dll")
[void][Reflection.Assembly]::LoadFrom("$dir\HardwareHelp64.dll")

$tHelp = $lib.GetType('XKWLib.XKWLibHelp', $true)
$miStart = $tHelp.GetMethod('Start')
$help = [Activator]::CreateInstance($tHelp)
Write-Output "calling Start (init may hang here)..."
$ok = $miStart.Invoke($help, @('SystemTemperatureMonitoring'))
Write-Output ("Start -> " + $ok)
$fiThread = $tHelp.GetField('thread_flag', [Reflection.BindingFlags]'NonPublic,Instance')
if ($fiThread) { $fiThread.SetValue($help, $false) }
$fiHw = $tHelp.GetField('hardware', [Reflection.BindingFlags]'NonPublic,Instance')
$hw = $fiHw.GetValue($help)
$ht = $hw.GetType()

function Show-Ex($label, $e) {
    if ($null -eq $e) { return }
    $inner = $e
    $depth = 0
    while ($inner -ne $null -and $depth -lt 4) {
        Write-Output ("$label EX[" + $depth + "] " + $inner.GetType().Name + ": " + $inner.Message)
        $inner = $inner.InnerException
        $depth++
    }
}

$rsd = $ht.GetMethod('ReadSystemData')
try {
    $r = $rsd.Invoke($hw, $null)
    Write-Output ("ReadSystemData -> " + $r)
} catch {
    Show-Ex 'ReadSystemData' $_.Exception
    if ($_.Exception.InnerException) { Show-Ex 'ReadSystemData.inner' $_.Exception.InnerException }
}

foreach ($name in @('GetOperatingSystem','GetBaseBoard','GetCpuInfo','GetVideoController','GetPhysicalMemory','GetWin32_DiskDrive','GetDisplayManufacturer')) {
    $mi = $ht.GetMethod($name)
    if (-not $mi) { Write-Output ("$name -> not found"); continue }
    try {
        $r = $mi.Invoke($hw, $null)
        if ($null -eq $r) { Write-Output ("$name -> null") }
        else { Write-Output ("$name -> count=" + $r.Count) }
    } catch {
        Show-Ex $name $_.Exception
        if ($_.Exception.InnerException) { Show-Ex ($name + '.inner') $_.Exception.InnerException }
    }
}

$fSs = $ht.GetField('sharedSystem', [Reflection.BindingFlags]'NonPublic,Instance')
if ($fSs) {
    $ss = $fSs.GetValue($hw)
    if ($null -eq $ss) { Write-Output 'sharedSystem = null' }
    else {
        $sst = $ss.GetType()
        Write-Output ("sharedSystem: name=" + $sst.GetProperty('Name').GetValue($ss, $null) +
                      " CreateNew=" + $sst.GetProperty('CreateNew').GetValue($ss, $null))
        $d = $ss.Read()
        if ($null -eq $d) { Write-Output '  sharedSystem payload read -> null' }
        else { Write-Output ("  payload size=" + $d.Size + " tick=" + $d.GetType().GetProperty('tick').GetValue($d, $null)) }
    }
} else { Write-Output 'sharedSystem field not found' }
Write-Output "probe4 done"
