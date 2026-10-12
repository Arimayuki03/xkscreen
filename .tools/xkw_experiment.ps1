# Three-in-one screen experiment (admin required):
#   A: feed custom values into the CPU/GPU ring globals and flush via SetDeviceTime
#   B: SetColor ring color test (red / green / blue)
#   C: SetDisplayMode test (modes 1,2,3 with normal 4s gaps), then restore mode 0
# -Only A|B|C reruns a single test; default ALL runs everything.
# run_experiment.bat stops the resident driver first and restarts it afterwards.
param([string]$Only = 'ALL')
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$dir = 'D:\Code\Xingcan-Xiaolan-Drive\official'
Set-Location $dir
[Environment]::CurrentDirectory = $dir
$log = Join-Path $dir 'experiment.log'
if (Test-Path $log) { Move-Item -Force $log (Join-Path $dir 'experiment_prev.log') }

function L([string]$m) {
  $s = ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $m)
  Add-Content -Path $log -Value $s -Encoding UTF8
  Write-Host $s
}

L '=== experiment start ==='
[Reflection.Assembly]::LoadFrom((Resolve-Path 'XKWLib.dll')) | Out-Null
L 'XKWLib loaded'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class TempCommX {
    [DllImport("TempComm.dll")]
    public static extern int SetColor(int idx, byte[] rgba);
    [DllImport("TempComm.dll")]
    public static extern int SetDisplayMode(int a, int b);
    [DllImport("TempComm.dll")]
    public static extern int SetColorEx(int idx, byte[] rgba, byte extra);
}
"@
L 'TempCommX bindings added (SetColor, SetDisplayMode)'

$help = New-Object XKWLib.XKWLibHelp
$ok = $false
for ($i = 1; $i -le 15; $i++) {
  try { $ok = $help.Start('SystemTemperatureMonitoring') } catch { $ok = $false; L ('Start exception: ' + $_.Exception.Message) }
  L ("Start attempt $i = $ok")
  if ($ok) { break }
  Start-Sleep -Seconds 3
}
if (-not $ok) { L 'ABORT: XKWLibHelp.Start failed'; exit 1 }

$f = $help.GetType().GetField('usb_send_delay', [Reflection.BindingFlags]'NonPublic,Instance')
if ($f) { $f.SetValue($help, 120000); L 'helper send_delay -> 120s (auto re-sender paused)' } else { L 'WARN: usb_send_delay field not found' }

function NowBytes {
  $n = Get-Date
  $t = New-Object byte[] 9
  $t[0] = [byte][math]::Floor($n.Year / 100)
  $t[1] = [byte]($n.Year % 100)
  $t[2] = [byte]$n.Month
  $t[3] = [byte]$n.Day
  $t[4] = [byte][int]$n.DayOfWeek
  $t[5] = [byte]$n.Hour
  $t[6] = [byte]$n.Minute
  $t[7] = [byte]$n.Second
  $t[8] = [byte][math]::Floor($n.Millisecond / 10)
  return ,$t
}

function TimeBytes([datetime]$d) {
  $t = New-Object byte[] 9
  $t[0] = [byte][math]::Floor($d.Year / 100)
  $t[1] = [byte]($d.Year % 100)
  $t[2] = [byte]$d.Month
  $t[3] = [byte]$d.Day
  $t[4] = [byte][int]$d.DayOfWeek
  $t[5] = [byte]$d.Hour
  $t[6] = [byte]$d.Minute
  $t[7] = [byte]$d.Second
  $t[8] = [byte][math]::Floor($d.Millisecond / 10)
  return ,$t
}

function KeepAliveReal([int]$seconds) {
  $end = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $end) {
    try { $help.SendDynamicDataNew() | Out-Null } catch {}
    Start-Sleep -Milliseconds 300
  }
}

L '--- baseline 8s (live data) ---'
KeepAliveReal 8

if ($Only -eq 'ALL' -or $Only -eq 'A') {
L '--- TEST A: frozen custom values 25s (CPU 77%/88C, GPU 44%/55C) ---'
$cpu = New-Object byte[] 8
$cpu[0] = 77; $cpu[1] = 88; $cpu[2] = 0x24; $cpu[3] = 0x13
$gpu = New-Object byte[] 8
$gpu[0] = 44; $gpu[1] = 55; $gpu[2] = 0xC4; $gpu[3] = 0x09
$end = (Get-Date).AddSeconds(25)
while ((Get-Date) -lt $end) {
  try {
    [XKWLib.DllWrapper]::SetCpuDynamicInfo($cpu, $cpu.Length) | Out-Null
    [XKWLib.DllWrapper]::SetGpuDynamicInfo($gpu, $gpu.Length) | Out-Null
    [XKWLib.DllWrapper]::SetDeviceTime((NowBytes), 9) | Out-Null
  } catch {}
  Start-Sleep -Milliseconds 300
}
L 'TEST A done'

L '--- back to live 8s ---'
KeepAliveReal 8
}

if ($Only -eq 'ALL' -or $Only -eq 'B') {
L '--- TEST B: SetColor red/green/blue 8s each ---'
foreach ($pair in 'RED=255,0,0,255', 'GREEN=0,255,0,255', 'BLUE=0,0,255,255') {
  $kv = $pair -split '='
  $v = $kv[1] -split ','
  $b = New-Object byte[] 4
  $b[0] = [byte][int]$v[0]; $b[1] = [byte][int]$v[1]; $b[2] = [byte][int]$v[2]; $b[3] = [byte][int]$v[3]
  try { $r = [TempCommX]::SetColor(0, $b) } catch { $r = 'EX:' + $_.Exception.Message }
  L ('SetColor ' + $kv[0] + ' ret=' + $r)
  KeepAliveReal 8
}
L 'TEST B done'
}

if ($Only -eq 'ALL' -or $Only -eq 'C') {
L '--- TEST C: SetDisplayMode 1/2/3 (8s each, 4s normal between) ---'
foreach ($m in @(1, 2, 3)) {
  try { $r = [TempCommX]::SetDisplayMode(1, $m) } catch { $r = 'EX:' + $_.Exception.Message }
  L ("SetDisplayMode(1,$m) ret=$r")
  KeepAliveReal 8
  try { [TempCommX]::SetDisplayMode(1, 0) | Out-Null } catch {}
  L 'mode restored to 0'
  KeepAliveReal 4
}
L 'TEST C done'
}

if ($Only -eq 'ALL' -or $Only -eq 'D') {
L '--- TEST D1: ring temp slot values 0 / 255 (does the unit symbol change?) ---'
foreach ($tv in 0, 255) {
  $end = (Get-Date).AddSeconds(9)
  while ((Get-Date) -lt $end) {
    try {
      $b = New-Object byte[] 8
      $b[0] = 50; $b[1] = [byte]$tv; $b[2] = 0x24; $b[3] = 0x13
      [XKWLib.DllWrapper]::SetGpuDynamicInfo($b, [uint32]8) | Out-Null
      [XKWLib.DllWrapper]::SetCpuDynamicInfo($b, [uint32]8) | Out-Null
      Send-TimeFlush
    } catch { }
    Start-Sleep -Milliseconds 300
  }
  L ('D1: both rings set to 50,' + $tv + ' for 9s')
}
L 'D1 done'
KeepAliveReal 5

L '--- TEST D2: SetColorEx extra byte 0..3 (red), watch for ANY color change ---'
foreach ($x in 0, 1, 2, 3) {
  try {
    $b = New-Object byte[] 4
    $b[0] = 0xFF; $b[1] = 0x00; $b[2] = 0x00; $b[3] = 0xFF
    $r = [TempCommX]::SetColorEx(0, $b, [byte]$x)
  } catch { $r = 'EX:' + $_.Exception.Message }
  L ('SetColorEx(0, RED, ' + $x + ') ret=' + $r)
  KeepAliveReal 7
}
L 'D2 done'

L '--- TEST D3: display mode byte variants 0x80..0x83, then 4 and 5 ---'
foreach ($m in 0, 1, 2, 3) {
  try { $r = [TempCommX]::SetDisplayMode(0, $m) } catch { $r = 'EX:' + $_.Exception.Message }
  L ('SetDisplayMode(0,' + $m + ') -> byte 0x' + ('{0:X2}' -f (0x80 -bor $m)) + ' ret=' + $r)
  KeepAliveReal 7
  try { [TempCommX]::SetDisplayMode(1, 0) | Out-Null } catch { }
  L 'mode restored to 0'
  KeepAliveReal 3
}
foreach ($m in 4, 5) {
  try { $r = [TempCommX]::SetDisplayMode(1, $m) } catch { $r = 'EX:' + $_.Exception.Message }
  L ('SetDisplayMode(1,' + $m + ') ret=' + $r)
  KeepAliveReal 7
  try { [TempCommX]::SetDisplayMode(1, 0) | Out-Null } catch { }
  L 'mode restored to 0'
  KeepAliveReal 3
}
L 'D3 done'
}

if ($Only -eq 'ALL' -or $Only -eq 'E') {
L '--- TEST E: clock control (screen shows HH:MM only) ---'
$today = Get-Date
$fixed = Get-Date -Year $today.Year -Month $today.Month -Day $today.Day -Hour 12 -Minute 34 -Second 0 -Millisecond 0
$end = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $end) {
  try { [XKWLib.DllWrapper]::SetDeviceTime((TimeBytes $fixed), 9) | Out-Null } catch { }
  Start-Sleep -Milliseconds 300
}
L 'E1 done: fixed 12:34 for 10s'

# E2: fast clock - start 04:00, +1 minute per second (minute visibly jumps)
$fastBase = Get-Date -Year $today.Year -Month $today.Month -Day $today.Day -Hour 4 -Minute 0 -Second 0 -Millisecond 0
$t0 = Get-Date
$end = $t0.AddSeconds(30)
while ((Get-Date) -lt $end) {
  $mins = [int]((Get-Date) - $t0).TotalSeconds
  try { [XKWLib.DllWrapper]::SetDeviceTime((TimeBytes ($fastBase.AddMinutes($mins))), 9) | Out-Null } catch { }
  Start-Sleep -Milliseconds 300
}
L 'E2 done: fast clock 04:00 +1min/s for 30s'

# E3: steady now+1h for 70s (minute advances naturally at least once)
$end = (Get-Date).AddSeconds(70)
while ((Get-Date) -lt $end) {
  try { [XKWLib.DllWrapper]::SetDeviceTime((TimeBytes ((Get-Date).AddHours(1))), 9) | Out-Null } catch { }
  Start-Sleep -Milliseconds 300
}
L 'E3 done: now+1h steady for 70s'

L '--- back to real time 6s ---'
KeepAliveReal 6
L 'TEST E done'
}
L '=== experiment done ==='
