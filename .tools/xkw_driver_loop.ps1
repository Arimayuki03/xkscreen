# XK003 screen resident driver (our software) - v3.1
# Features: ring data-source mapping + clock control + per-frame driving.
# Chain: load official XKWLib -> XKWLibHelp.Start('SystemTemperatureMonitoring')
#   -> SetCheckUsb registers VID_0145/PID_1001 + CPUIDHardware.Start + OpenRefresh(1000)
#   -> TempComm Set* -> USB HID frames.
# This process keeps the screen alive and drives every frame itself; the XKWLib
# internal auto-sender is paused after Start so overrides are not interleaved.
# Requires admin/SYSTEM (CPUID SDK needs driver access, otherwise CPU/GPU data is empty).
# IMPORTANT: keep this file ASCII-only. PowerShell 5.1 reads a no-BOM UTF-8 script
# as ANSI/GBK; some non-ASCII comment bytes swallow the following newline and turn
# the next code line into a comment (this once silently killed the time.txt read).
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$dir = 'D:\Code\Xingcan-Xiaolan-Drive\official'
Set-Location $dir
[Environment]::CurrentDirectory = $dir

$log = Join-Path $dir 'driver_loop.log'
function Write-DriverLog([string]$msg) {
    try {
        Add-Content -Path $log -Value ("{0}`t{1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8
    } catch { }
}

Write-DriverLog 'driver start (v3.1: ring mapping + clock control)'
[Reflection.Assembly]::LoadFrom((Resolve-Path 'XKWLib.dll')) | Out-Null

$help = New-Object XKWLib.XKWLibHelp
$ok = $false
for ($attempt = 1; $attempt -le 30; $attempt++) {
    try {
        if ($help.Start('SystemTemperatureMonitoring')) { $ok = $true; break }
    } catch { Write-DriverLog ("Start exc: " + $_.Exception.Message) }
    Write-DriverLog ("Start attempt $attempt/30 failed, retry in 10s")
    Start-Sleep -Seconds 10
}
if (-not $ok) {
    Write-DriverLog 'Start failed x30, exit 1'
    exit 1
}
Write-DriverLog 'Start ok'

# Pause the XKWLib internal auto-sender: this loop drives each frame itself (300ms),
# avoiding the internal thread periodically sending real data (flicker on overrides).
$fDelay = $help.GetType().GetField('usb_send_delay', [Reflection.BindingFlags]'NonPublic,Instance')
if ($fDelay) { $fDelay.SetValue($help, 120000); Write-DriverLog 'helper send_delay -> 120s (paused)' }
else { Write-DriverLog 'WARN: usb_send_delay not found, helper may interleave frames' }

# ---- Ring config files: official\ring_cpu.txt / ring_gpu.txt ----
#   content auto      = real data (official behavior; no override when the file is auto)
#   content NN,MM     = fixed numbers (0-255), e.g. 33,22
#   content SRC1,SRC2 = data-source mapping; sources (case-insensitive).
#   Every slot is a byte clamped to 0-99 (the screen shows at most 2 digits):
#     cpu_load(%)  cpu_temp(C)  cpu_clock(GHz*10)  cpu_watt(W)  cpu_volt(V*10)
#     gpu_load(%)  gpu_temp(C)  gpu_clock(GHz*10)  gpu_fan(rpm/100)
#     mem_pct(%)   mem_used_gb(GB)  net_down(MB/s)  net_up(MB/s)
#     fan_rpm(rpm/100)  hdd_load(%)
#   example: GPU ring shows memory% + download MB/s -> mem_pct,net_down
$ringCpuFile = Join-Path $dir 'ring_cpu.txt'
$ringGpuFile = Join-Path $dir 'ring_gpu.txt'
$lastRingState = ''
$lastResolved = ''

# ---- Clock config (optional): official\time.txt ----
#   content auto    = follow system time (default)
#   content +N / -N = shifted from system time by N minutes (still ticking; +90 = 90 min ahead)
#   content HH:MM   = freeze the clock at that time
$timeFile = Join-Path $dir 'time.txt'

function Read-RingSpec([string]$path) {
    try {
        if (-not (Test-Path $path)) { return $null }
        $t = (Get-Content -Path $path -Raw -ErrorAction Stop).Trim()
        if ($t -eq '' -or $t.ToLower() -eq 'auto') { return $null }
        $v = $t -split ','
        if ($v.Count -lt 2) { return $null }
        return @($v[0].Trim(), $v[1].Trim())
    } catch { return $null }
}

function Read-TimeSpec([string]$path) {
    try {
        if (-not (Test-Path $path)) { return $null }
        $t = (Get-Content -Path $path -Raw -ErrorAction Stop).Trim()
        if ($t -eq '' -or $t.ToLower() -eq 'auto') { return $null }
        return $t
    } catch { return $null }
}

function Resolve-Time([string]$spec) {
    if (-not $spec) { return $null }
    try {
        if ($spec -match '^[+-][0-9]+$') {
            return (Get-Date).AddMinutes([int]$spec)
        }
        if ($spec -match '^([0-9]{1,2}):([0-9]{2})$') {
            $h = [int]$Matches[1]
            $m = [int]$Matches[2]
            if ($h -le 23 -and $m -le 59) {
                $now = Get-Date
                return (Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour $h -Minute $m -Second 0 -Millisecond 0)
            }
        }
    } catch { }
    return $null
}

# ---- Hardware sensor access (reflection into XKWLib hardware.SystemData) ----
$script:hwField = $null
$script:sysDataProp = $null
$script:sysData = $null
$script:runDataMethod = $null
$script:enumMap = @{}
try {
    $script:hwField = $help.GetType().GetField('hardware', [Reflection.BindingFlags]'NonPublic,Instance')
    if ($script:hwField) {
        $hw = $script:hwField.GetValue($help)
        if ($hw) {
            $script:sysDataProp = $hw.GetType().GetProperty('SystemData')
            if ($script:sysDataProp) {
                $script:sysData = $script:sysDataProp.GetValue($hw)
                if ($script:sysData) {
                    $script:runDataMethod = $script:sysData.GetType().GetMethods() | Where-Object { $_.Name -eq 'GetSystemRunData' -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
                    if ($script:runDataMethod) {
                        $et = $script:runDataMethod.GetParameters()[0].ParameterType
                        foreach ($nm in 'Cpu', 'Gpu', 'Network', 'Ram', 'HHD', 'Fan') {
                            try { $script:enumMap[$nm] = [Enum]::Parse($et, $nm) } catch { }
                        }
                    }
                }
            }
        }
    }
    Write-DriverLog ("sensor access init: method=" + [bool]$script:runDataMethod + " enums=" + $script:enumMap.Count)
} catch { Write-DriverLog ("sensor access init exc: " + $_.Exception.Message) }

function To-Dbl($v) {
    $d = 0.0
    try { [void][double]::TryParse([string]$v, [ref]$d) } catch { }
    return $d
}

function Get-RunData([string]$key) {
    if (-not $script:runDataMethod -or -not $script:enumMap.ContainsKey($key)) { return $null }
    try {
        $r = $script:runDataMethod.Invoke($script:sysData, @($script:enumMap[$key]))
        if ($null -eq $r) { return $null }
        # DataItem is IEnumerable: a plain return would be unwrapped into an array
        # by PowerShell, losing .Size and the indexer; wrap with unary comma.
        return ,$r
    } catch { return $null }
}

function Get-Sensors {
    $s = @{}
    $g = Get-RunData 'Gpu'
    if ($g -and $g.Size -gt 0) {
        try {
            $d = $null
            if ($g.Size -gt 1) {
                for ($i = 0; $i -lt $g.Size; $i++) {
                    $n = [string]$g[$i]['name']
                    if ($n -match 'GTX|RTX|NVIDIA') { $d = $g[$i]; break }
                }
                if (-not $d) {
                    for ($i = 0; $i -lt $g.Size; $i++) {
                        if ($g[$i].ContainsKey('clock') -and $g[$i].ContainsKey('temperature')) { $d = $g[$i]; break }
                    }
                }
            }
            if (-not $d) { $d = $g[0] }
            if ($d.ContainsKey('load')) { $s['gpu_load'] = (To-Dbl $d['load']) }
            if ($d.ContainsKey('temperature')) { $s['gpu_temp'] = (To-Dbl $d['temperature']) }
            if ($d.ContainsKey('clock')) { $s['gpu_clock'] = (To-Dbl $d['clock']) / 100.0 }
            if ($d.ContainsKey('fan')) { $s['gpu_fan'] = (To-Dbl $d['fan']) / 100.0 }
        } catch { }
    }
    $c = Get-RunData 'Cpu'
    if ($c -and $c.Size -gt 0) {
        try {
            $loadSum = 0.0
            $loadN = 0
            $tMax = 0.0
            $clkMax = 0.0
            foreach ($d in $c) {
                $nm = ''
                try { $nm = [string]$d['name'] } catch { }
                if ($nm -eq 'packge') {
                    # the package item also carries load/temperature/clock; only
                    # additionally extract watt/voltage here, do NOT skip it
                    if ($d.ContainsKey('powers')) { $s['cpu_watt'] = (To-Dbl $d['powers']) }
                    if ($d.ContainsKey('voltage')) { $s['cpu_volt'] = (To-Dbl $d['voltage']) * 10.0 }
                }
                if ($d.ContainsKey('load')) { $loadSum += (To-Dbl $d['load']); $loadN++ }
                if ($d.ContainsKey('temperature')) { $tv = (To-Dbl $d['temperature']); if ($tv -gt $tMax) { $tMax = $tv } }
                if ($d.ContainsKey('clock')) { $tv = (To-Dbl $d['clock']); if ($tv -gt $clkMax) { $clkMax = $tv } }
            }
            if ($loadN -gt 0) { $s['cpu_load'] = $loadSum / $loadN }
            $s['cpu_temp'] = $tMax
            $s['cpu_clock'] = $clkMax / 100.0
        } catch { }
    }
    $n = Get-RunData 'Network'
    if ($n -and $n.Size -gt 0) {
        try {
            $rx = 0.0
            $tx = 0.0
            foreach ($d in $n) {
                if ($d.ContainsKey('ReceivedPerSec')) { $v = (To-Dbl $d['ReceivedPerSec']); if ($v -gt $rx) { $rx = $v } }
                if ($d.ContainsKey('SentPerSec')) { $v = (To-Dbl $d['SentPerSec']); if ($v -gt $tx) { $tx = $v } }
            }
            $s['net_down'] = $rx / 1048576.0
            $s['net_up'] = $tx / 1048576.0
        } catch { }
    }
    $r = Get-RunData 'Ram'
    if ($r -and $r.Size -gt 0) {
        try {
            $d = $r[0]
            $used = 0.0
            $avail = 0.0
            if ($d.ContainsKey('Memory Used') -and $d.ContainsKey('Memory Available')) {
                $used = (To-Dbl $d['Memory Used'])
                $avail = (To-Dbl $d['Memory Available'])
            } elseif ($d.ContainsKey('Used Memory') -and $d.ContainsKey('Available Memory')) {
                $used = (To-Dbl $d['Used Memory'])
                $avail = (To-Dbl $d['Available Memory'])
            }
            if (($used + $avail) -gt 0) { $s['mem_pct'] = $used / ($used + $avail) * 100.0 }
            if ($used -gt 0) { $s['mem_used_gb'] = $used }
        } catch { }
    }
    $f = Get-RunData 'Fan'
    if ($f -and $f.Size -gt 0) {
        try { $s['fan_rpm'] = (To-Dbl $f[0]['speed']) / 100.0 } catch { }
    }
    $h = Get-RunData 'HHD'
    if ($h -and $h.Size -gt 0) {
        try { $s['hdd_load'] = (To-Dbl $h[0]['load']) } catch { }
    }
    return $s
}

function Resolve-Slot([string]$tok, $sensors) {
    if ($tok -match '^[0-9]+$') {
        $v = [int]$tok
        if ($v -gt 99) { $v = 99 }
        return [byte]$v
    }
    $k = $tok.ToLower()
    if ($sensors -and $sensors.ContainsKey($k)) {
        $v = [math]::Round([double]$sensors[$k])
        if ($v -lt 0) { $v = 0 }
        if ($v -gt 99) { $v = 99 }
        return [byte]$v
    }
    return [byte]0
}

function Send-TimeFlush {
    param([datetime]$d = (Get-Date))
    $n = $d
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
    [XKWLib.DllWrapper]::SetDeviceTime($t, 9) | Out-Null
}

# Keep-alive + per-frame overrides
$i = 0
$snapshotDone = $false
while ($true) {
    try { $help.SendDynamicDataNew() } catch { }
    $rc = Read-RingSpec $ringCpuFile
    $rg = Read-RingSpec $ringGpuFile
    $tSpec = Read-TimeSpec $timeFile
    $tVal = Resolve-Time $tSpec
    $anyCustom = [bool]($rc -or $rg -or $tVal)
    $lastResolved = ''
    if ($anyCustom) {
        try {
            $needSensors = $false
            if ($rc -and (($rc[0] -notmatch '^[0-9]+$') -or ($rc[1] -notmatch '^[0-9]+$'))) { $needSensors = $true }
            if ($rg -and (($rg[0] -notmatch '^[0-9]+$') -or ($rg[1] -notmatch '^[0-9]+$'))) { $needSensors = $true }
            $sensors = $null
            if ($needSensors) { $sensors = Get-Sensors }
            if ($rc) {
                $b = New-Object byte[] 8
                $b[0] = Resolve-Slot $rc[0] $sensors
                $b[1] = Resolve-Slot $rc[1] $sensors
                $b[2] = 0x24; $b[3] = 0x13
                [XKWLib.DllWrapper]::SetCpuDynamicInfo($b, [uint32]8) | Out-Null
                $lastResolved = ('cpu=[' + $b[0] + ',' + $b[1] + ']')
            }
            if ($rg) {
                $b = New-Object byte[] 8
                $b[0] = Resolve-Slot $rg[0] $sensors
                $b[1] = Resolve-Slot $rg[1] $sensors
                $b[2] = 0x24; $b[3] = 0x13
                [XKWLib.DllWrapper]::SetGpuDynamicInfo($b, [uint32]8) | Out-Null
                $lastResolved = ($lastResolved + ' gpu=[' + $b[0] + ',' + $b[1] + ']')
            }
            if ($tVal) {
                Send-TimeFlush $tVal
                $lastResolved = ($lastResolved + ' time=' + $tVal.ToString('HH:mm'))
            } else {
                Send-TimeFlush
            }
        } catch { }
    }
    $state = 'cpu:' + $(if ($rc) { ($rc -join '/') } else { 'auto' }) + ' gpu:' + $(if ($rg) { ($rg -join '/') } else { 'auto' }) + ' time:' + $(if ($tVal) { $tSpec } else { 'auto' })
    if ($state -ne $lastRingState) {
        Write-DriverLog ("state -> " + $state)
        $lastRingState = $state
    }
    $i++
    if (-not $snapshotDone -and ($i % 30 -eq 0)) {
        try {
            $snap = Get-Sensors
            $parts = @()
            foreach ($k in ($snap.Keys | Sort-Object)) { $parts += ($k + '=' + [math]::Round([double]$snap[$k], 1)) }
            if ($parts.Count -gt 0) {
                Write-DriverLog ('sensor snapshot: ' + ($parts -join ' '))
                $snapshotDone = $true
            }
        } catch { }
    }
    if ($anyCustom -and $lastResolved -and ($i % 30 -eq 0)) {
        Write-DriverLog ('ring values ' + $lastResolved)
    }
    if ($i % 150 -eq 0) {
        $err = 0
        try { $err = [XKWLib.DllWrapper]::GetErrorCode() } catch { }
        Write-DriverLog ("alive i=$i err=$err")
    }
    Start-Sleep -Milliseconds 300
}
