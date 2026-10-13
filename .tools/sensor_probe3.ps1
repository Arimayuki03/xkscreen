# Probe 3: dump the type hierarchy and private fields of the vendor hardware
# object, plus the null-ness of sharedRunData. Read-only.
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
$t = $hw.GetType()
while ($t -ne $null) {
    Write-Output ("TYPE " + $t.FullName)
    $flds = $t.GetFields([Reflection.BindingFlags]'NonPublic,Instance,Public')
    foreach ($f in $flds) {
        $v = ''
        try {
            $val = $f.GetValue($hw)
            if ($null -eq $val) { $v = '<null>' } else { $v = $val.ToString() }
        } catch { $v = '<err>' }
        Write-Output ("   " + $f.FieldType.Name + " " + $f.Name + " = " + $v)
    }
    $t = $t.BaseType
}
$pi = $hw.GetType().GetProperty('InitState')
if ($pi) { Write-Output ("InitState = " + $pi.GetValue($hw, $null)) }
Write-Output "probe3 done"
