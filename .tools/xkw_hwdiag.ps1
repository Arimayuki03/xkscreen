# 诊断 CPUID 硬件采集状态：反射读取 XKWLibHelp 私有字段 hardware 的 InitState 与数据量。
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$dir = 'D:\Code\Xingcan-Xiaolan-Drive\official'
Set-Location $dir
[Environment]::CurrentDirectory = $dir

[Reflection.Assembly]::LoadFrom((Resolve-Path 'XKWLib.dll')) | Out-Null

$h = [Reflection.BindingFlags]'NonPublic,Instance,Public'
$help = New-Object XKWLib.XKWLibHelp
$s = $help.Start('SystemTemperatureMonitoring')
Write-Output "Start = $s"

Start-Sleep -Seconds 5

$t = $help.GetType()
$f = $t.GetField('hardware', $h)
$hw = $f.GetValue($help)
Write-Output ("hardware obj null? " + ($null -eq $hw))
if ($hw) {
    $initProp = $hw.GetType().GetProperty('InitState')
    if ($initProp) { Write-Output ("InitState = " + $initProp.GetValue($hw)) }
    $sd = $hw.GetType().GetProperty('SystemData').GetValue($hw)
    Write-Output ("SystemData null? " + ($null -eq $sd))
    if ($sd) {
        # GetSystemRunData() 无参版本取全部
        $m = $sd.GetType().GetMethod('GetSystemRunData', [Type[]]@())
        $all = $m.Invoke($sd, @())
        Write-Output ("GetSystemRunData() list null? " + ($null -eq $all))
        if ($all) { Write-Output ("all items count = " + $all.Count) }
        # 逐类型取样
        $asm = $hw.GetType().Assembly
        $dt = $asm.GetType('HardwareHelp.HardwareDataInfo+DataType')
        foreach ($name in @('Cpu', 'Gpu', 'Ram', 'Network', 'HHD', 'Fan')) {
            try {
                $v = [Enum]::Parse($dt, $name)
                $m2 = $sd.GetType().GetMethod('GetSystemRunData', [Type[]]@($dt))
                $r = $m2.Invoke($sd, @($v))
                $cnt = if ($null -eq $r) { 'null' } else { $r.Count }
                Write-Output ("  " + $name + " -> " + $cnt)
            } catch {
                Write-Output ("  " + $name + " EXC: " + $_.Exception.InnerException.Message)
            }
        }
    }
}
Start-Sleep -Seconds 3
$help.Stop()
Write-Output "diag done"
