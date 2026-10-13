# Probe: enumerate the CPUID SDK's sensors to find whether a *live* voltage
# sensor exists (the vendor's "voltage" field reads the static "VID (max)").
$ErrorActionPreference = 'Continue'
$dir = 'C:\XkScreen\vendor'
Set-Location $dir
[void][Reflection.Assembly]::LoadFrom("$dir\Newtonsoft.Json.dll")
$lib = [Reflection.Assembly]::LoadFrom("$dir\XKWLib.dll")
[void][Reflection.Assembly]::LoadFrom("$dir\HardwareHelp64.dll")
$tHelp = $lib.GetType('XKWLib.XKWLibHelp', $true)
$help = [Activator]::CreateInstance($tHelp)
$ok = $tHelp.GetMethod('Start').Invoke($help, @('SystemTemperatureMonitoring'))
Write-Output ("Start -> " + $ok)
$fiThread = $tHelp.GetField('thread_flag', [Reflection.BindingFlags]'NonPublic,Instance')
if ($fiThread) { $fiThread.SetValue($help, $false) }
Start-Sleep -Seconds 2
$hw = $tHelp.GetField('hardware', [Reflection.BindingFlags]'NonPublic,Instance').GetValue($help)
$fiSdk = $hw.GetType().GetField('_pSdk', [Reflection.BindingFlags]'NonPublic,Instance')
$sdk = $fiSdk.GetValue($hw)
if ($null -eq $sdk) { Write-Output 'no _pSdk'; exit 1 }
$st = $sdk.GetType()
$miN = $st.GetMethod('GetNumberOfSensors')
$miI = $st.GetMethod('GetSensorInfos')
$miDevName = $st.GetMethod('GetDeviceName')
$miDevClass = $st.GetMethod('GetDeviceClass')
$miNumDev = $st.GetMethod('GetNumberOfDevices')

function Dump($label) {
    Write-Output ("==== " + $label + " ====")
    $nd = $miNumDev.Invoke($sdk, $null)
    for ($d = 0; $d -lt $nd; $d++) {
        $devName = $miDevName.Invoke($sdk, @($d))
        $devClass = $miDevClass.Invoke($sdk, @($d))
        foreach ($cls in 4096, 8192) {
            try { $ns = $miN.Invoke($sdk, @($d, $cls)) } catch { continue }
            if ($ns -le 0) { continue }
            for ($j = 0; $j -lt $ns; $j++) {
                $arr = @($d, $j, $cls, 0, "", 0, [float]0, [float]0, [float]0)
                try { $r = $miI.Invoke($sdk, $arr) } catch { continue }
                if (-not $r) { continue }
                $name = [string]$arr[4]
                $raw = $arr[5]
                $val = $arr[6]
                Write-Output ("  dev" + $d + "[" + $devName + "/" + $devClass + "] cls=" + $cls + " #" + $j + "  " + $name + "  value=" + [Math]::Round($val, 3) + " raw=" + $raw)
            }
        }
    }
}

Dump 'idle'
$jobs = 1..6 | ForEach-Object { Start-Job { $end=(Get-Date).AddSeconds(14); while ((Get-Date) -lt $end) { $x=0; 1..300000 | ForEach-Object { $x += $_ } } } }
Start-Sleep -Seconds 8
Dump 'under-load'
$jobs | Stop-Job -ErrorAction SilentlyContinue; $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
Write-Output "probe done"
