# Sensor probe: loads the vendor chain the same way the service does, then
# calls Refresh() / each individual sampler directly and prints what each one
# returns or throws (ReadRunData swallows exceptions internally, so this is
# the only way to see the real failure).
# Read-only diagnostic; disables the DLL's own send thread immediately.
$ErrorActionPreference = 'Continue'
$dir = 'D:\Code\Xingcan-Xiaolan-Drive\official'
Set-Location $dir

[void][Reflection.Assembly]::LoadFrom("$dir\Newtonsoft.Json.dll")
$lib = [Reflection.Assembly]::LoadFrom("$dir\XKWLib.dll")
[void][Reflection.Assembly]::LoadFrom("$dir\HardwareHelp64.dll")
[void][Reflection.Assembly]::LoadFrom("$dir\TempComm.dll")

$tHelp = $lib.GetType('XKWLib.XKWLibHelp', $true)
$miStart = $tHelp.GetMethod('Start')
$help = [Activator]::CreateInstance($tHelp)
Write-Output "calling Start..."
try {
  $ok = $miStart.Invoke($help, @('SystemTemperatureMonitoring'))
  Write-Output ("Start -> " + $ok)
} catch {
  $e = $_.Exception
  Write-Output ("Start -> EX " + $e.GetType().Name + ": " + $e.Message)
  if ($e.InnerException) { Write-Output ("   inner: " + $e.InnerException.GetType().Name + ": " + $e.InnerException.Message) }
  exit 1
}

# disable the internal send thread right away (no frames from this probe)
$fiThread = $tHelp.GetField('thread_flag', [Reflection.BindingFlags]'NonPublic,Instance')
if ($fiThread) { $fiThread.SetValue($help, $false); Write-Output 'thread_flag=false' }

$fiHw = $tHelp.GetField('hardware', [Reflection.BindingFlags]'NonPublic,Instance')
$hw = $fiHw.GetValue($help)
$ht = $hw.GetType()
Write-Output ("hardware type: " + $ht.FullName)

$sd = $ht.GetProperty('SystemData').GetValue($hw, $null)

function Invoke-Probe($name) {
  $mi = $ht.GetMethod($name)
  if (-not $mi) { Write-Output ("$name -> method not found"); return }
  try {
    $r = $mi.Invoke($hw, $null)
    if ($null -eq $r) { Write-Output ("$name -> null") }
    else {
      $c = $r.Count
      Write-Output ("$name -> count=$c")
      if ($c -gt 0 -and ($name -eq 'GetFanSpeed' -or $name -eq 'GetGpuRunInfo')) {
        foreach ($it in $r) {
          $kv = ($it.Keys | ForEach-Object { $_ + '=' + $it[$_] }) -join ' '
          Write-Output ("   item: " + $kv)
        }
      }
    }
  } catch {
    $e = $_.Exception
    Write-Output ("$name -> EX " + $e.GetType().Name + ": " + $e.Message)
    if ($e.InnerException) { Write-Output ("   inner: " + $e.InnerException.GetType().Name + ": " + $e.InnerException.Message) }
  }
}

Start-Sleep -Milliseconds 1500
Invoke-Probe 'ReadRunData'
Invoke-Probe 'Refresh'
Invoke-Probe 'GetCpuRunInfo'
Invoke-Probe 'GetGpuRunInfo'
Invoke-Probe 'GetRAMRunInfo'
Invoke-Probe 'GetFanSpeed'
Invoke-Probe 'GetNetwork'

$sdt = $sd.GetType()
$gm = $null
foreach ($m in $sdt.GetMethods()) {
  if ($m.Name -eq 'GetSystemRunData' -and $m.GetParameters().Length -eq 1) { $gm = $m; break }
}
if ($gm) {
  $enumT = $gm.GetParameters()[0].ParameterType
  foreach ($n in @('Cpu','Gpu','Network','Ram','HHD','Fan')) {
    try {
      $ev = [Enum]::Parse($enumT, $n)
      $di = $gm.Invoke($sd, @($ev))
      if ($null -eq $di) { Write-Output ("SystemData[$n] -> null"); continue }
      $sz = $di.GetType().GetProperty('Size').GetValue($di, $null)
      Write-Output ("SystemData[$n] -> Size=$sz")
      if ($sz -gt 0) {
        foreach ($p in $di.GetType().GetProperties()) {
          if ($p.GetIndexParameters().Length -eq 1) {
            $it = $p.GetValue($di, @(0))
            if ($it) {
              $kv = ($it.Keys | ForEach-Object { $_ + '=' + $it[$_] }) -join ' '
              Write-Output ("   item0: " + $kv)
            }
            break
          }
        }
      }
    } catch {
      $e = $_.Exception
      Write-Output ("SystemData[$n] -> EX " + $e.Message)
      if ($e.InnerException) { Write-Output ("   inner: " + $e.InnerException.Message) }
    }
  }
} else {
  Write-Output "SystemData.GetSystemRunData(1-arg) not found"
}
Write-Output "probe done"
