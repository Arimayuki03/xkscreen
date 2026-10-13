# Probe 9: check NVIDIA NVML (ships with the driver) for GPU fan readings.
$ErrorActionPreference = 'Continue'
$code = @"
using System;
using System.Runtime.InteropServices;
public static class NvmlProbe {
  [DllImport("nvml.dll")] public static extern int nvmlInit_v2();
  [DllImport("nvml.dll")] public static extern int nvmlShutdown();
  [DllImport("nvml.dll")] public static extern int nvmlDeviceGetHandleByIndex_v2(uint index, out IntPtr dev);
  [DllImport("nvml.dll")] public static extern int nvmlDeviceGetFanSpeed(IntPtr dev, out uint speed);
  [DllImport("nvml.dll", EntryPoint="nvmlDeviceGetFanSpeedRPM")] public static extern int nvmlDeviceGetFanSpeedRPM(IntPtr dev, out uint speed);
  [DllImport("nvml.dll", EntryPoint="nvmlDeviceGetNumFans")] public static extern int nvmlDeviceGetNumFans(IntPtr dev, out uint num);
  [DllImport("nvml.dll", EntryPoint="nvmlDeviceGetTemperature")] public static extern int nvmlDeviceGetTemperature(IntPtr dev, uint sensor, out uint temp);
}
"@
Add-Type -TypeDefinition $code
try {
    $r = [NvmlProbe]::nvmlInit_v2()
    Write-Output ("nvmlInit_v2 -> $r")
    $dev = [IntPtr]::Zero
    $r = [NvmlProbe]::nvmlDeviceGetHandleByIndex_v2(0, [ref]$dev)
    Write-Output ("handle(0) -> $r dev=$dev")
    if ($r -eq 0) {
        $pct = 0
        $r = [NvmlProbe]::nvmlDeviceGetFanSpeed($dev, [ref]$pct)
        Write-Output ("FanSpeed(%) -> rc=$r value=$pct")
        try {
            $rpm = 0
            $r = [NvmlProbe]::nvmlDeviceGetFanSpeedRPM($dev, [ref]$rpm)
            Write-Output ("FanSpeedRPM -> rc=$r value=$rpm")
        } catch { Write-Output ("FanSpeedRPM EX: " + $_.Exception.Message) }
        try {
            $n = 0
            $r = [NvmlProbe]::nvmlDeviceGetNumFans($dev, [ref]$n)
            Write-Output ("NumFans -> rc=$r value=$n")
        } catch { Write-Output ("NumFans EX: " + $_.Exception.Message) }
        $t = 0
        $r = [NvmlProbe]::nvmlDeviceGetTemperature($dev, 0, [ref]$t)
        Write-Output ("Temp -> rc=$r value=$t")
    }
    [void][NvmlProbe]::nvmlShutdown()
} catch {
    Write-Output ("EX: " + $_.Exception.GetType().Name + " / " + $_.Exception.Message)
}
Write-Output "probe9 done"
