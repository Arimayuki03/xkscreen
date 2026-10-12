# 完整官方流程驱动屏幕：SetCheckUsb → CheckOnlineDevice → DeviceOpen
# → XKWLibHelp.ReadConfig/Start → 循环 SendDynamicDataNew
# 在 official 目录下运行（TempComm.dll / cpuidsdk64.dll / config.ini 都在此）。
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$dir = 'D:\Code\Xingcan-Xiaolan-Drive\official'
Set-Location $dir
[Environment]::CurrentDirectory = $dir

[Reflection.Assembly]::LoadFrom((Resolve-Path 'XKWLib.dll')) | Out-Null
Write-Output "assembly loaded"

# 1) 注册屏幕 VID=0x0145 PID=0x1001（字节对编码，与已验证的调用一致）
[byte[]]$vidpid = 0x01, 0x45, 0x10, 0x01
try {
    $r = [XKWLib.DllWrapper]::SetCheckUsb($vidpid, 2, 20)
    Write-Output "SetCheckUsb = $r"
} catch { Write-Output "SetCheckUsb EXC: $($_.Exception.Message)" }

# 2) 枚举并打开设备
try {
    [XKWLib.DllWrapper]::CheckOnlineDevice()
    Write-Output "CheckOnlineDevice ok, err=$([XKWLib.DllWrapper]::GetErrorCode())"
} catch { Write-Output "CheckOnlineDevice EXC: $($_.Exception.Message)" }

try {
    $o = [XKWLib.DllWrapper]::DeviceOpen(0)
    Write-Output "DeviceOpen(0) = $o"
} catch { Write-Output "DeviceOpen EXC: $($_.Exception.Message)" }

# 3) XKWLibHelp：读配置 + Start
$help = New-Object XKWLib.XKWLibHelp
try { $help.ReadConfig(); Write-Output "ReadConfig ok" } catch { Write-Output "ReadConfig EXC: $($_.Exception.Message)" }
try { $s = $help.Start('SystemTemperatureMonitoring'); Write-Output "Start = $s" } catch { Write-Output "Start EXC: $($_.Exception.Message)" }

# 4) 持续推送动态数据（CPU/时间/GPU）——官方服务就是这么驱动的
Write-Output ">>> dynamic data loop starts, WATCH THE SCREEN <<<"
$t0 = Get-Date
$i = 0
while (((Get-Date) - $t0).TotalSeconds -lt 240) {
    try {
        $help.SendDynamicDataNew()
    } catch {
        try { $help.SendDynamicData() } catch { }
    }
    $i++
    if ($i % 20 -eq 0) {
        Write-Output ("loop i=$i err=$([XKWLib.DllWrapper]::GetErrorCode())")
    }
    Start-Sleep -Milliseconds 300
}
Write-Output "loop done: $i"
