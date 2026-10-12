# 短程诊断：启动一次官方流程，让日志记录 CPUID SDK 初始化结果。
# 需要管理员运行（CPUID SDK 读 MSR 需要驱动访问权限）。
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$dir = 'D:\Code\Xingcan-Xiaolan-Drive\official'
Set-Location $dir
[Environment]::CurrentDirectory = $dir

[Reflection.Assembly]::LoadFrom((Resolve-Path 'XKWLib.dll')) | Out-Null
$help = New-Object XKWLib.XKWLibHelp
$s = $help.Start('SystemTemperatureMonitoring')
Write-Output "Start = $s"

Start-Sleep -Seconds 12

$logPath = Join-Path $dir 'log.txt'
if (Test-Path $logPath) {
    Write-Output "=== log.txt ==="
    Get-Content $logPath -Tail 30 -Encoding UTF8 | ForEach-Object { Write-Output $_ }
} else {
    Write-Output "no log at $logPath"
}
$help.Stop()
