# 纯反射方式调用 XKWLib.PIDVIDHelp 与 XKWLibHelp。
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Set-Location 'D:\Code\Xingcan-Xiaolan-Drive\official'

$asm = [Reflection.Assembly]::LoadFrom((Resolve-Path 'XKWLib.dll'))
$t = $asm.GetType('XKWLib.PIDVIDHelp')
Write-Output ("PIDVIDHelp methods:")
$t.GetMethods([Reflection.BindingFlags]'Public,Static,Instance,DeclaredOnly') | ForEach-Object {
    Write-Output ("  " + $_.Name + " static=" + $_.IsStatic + " args=" + ($_.GetParameters() | ForEach-Object { $_.ParameterType.Name } | Join-String -Separator ','))
}

# 尝试静态调用
$m = $t.GetMethod('SetCheckUsb')
if ($m -and $m.IsStatic) {
    foreach ($f in @('vid_0145&pid_1001', 'VID_0145&PID_1001', '0x0145,0x1001', '0145,1001', '145,1001')) {
        try {
            $r = $m.Invoke($null, @($f))
            Write-Output ("static SetCheckUsb('" + $f + "') = " + $r)
            if ($r) { break }
        } catch {
            Write-Output ("static SetCheckUsb('" + $f + "') EXC: " + $_.Exception.InnerException.Message)
        }
    }
} elseif ($m) {
    $inst = [Activator]::CreateInstance($t, $true)
    foreach ($f in @('vid_0145&pid_1001', 'VID_0145&PID_1001', '0x0145,0x1001', '0145,1001', '145,1001')) {
        try {
            $r = $m.Invoke($inst, @($f))
            Write-Output ("inst SetCheckUsb('" + $f + "') = " + $r)
            if ($r) { break }
        } catch {
            Write-Output ("inst SetCheckUsb('" + $f + "') EXC: " + $_.Exception.InnerException.Message)
        }
    }
} else {
    Write-Output "method not found"
}
