# 精确探测 XKWLib API（PS 5.1 兼容写法，不用 Join-String）。
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Set-Location 'D:\Code\Xingcan-Xiaolan-Drive\official'

$asm = [Reflection.Assembly]::LoadFrom((Resolve-Path 'XKWLib.dll'))

foreach ($tn in @('XKWLib.PIDVIDHelp', 'XKWLib.DllWrapper', 'XKWLib.XKWLibHelp')) {
    $t = $asm.GetType($tn)
    Write-Output ("=== " + $tn + " ===")
    foreach ($m in $t.GetMethods([Reflection.BindingFlags]'Public,NonPublic,Static,Instance,DeclaredOnly')) {
        $ps = @()
        foreach ($p in $m.GetParameters()) { $ps += ($p.ParameterType.Name + ' ' + $p.Name) }
        Write-Output ("  " + $m.ReturnType.Name + " " + $m.Name + "(" + ($ps -join ', ') + ") static=" + $m.IsStatic)
    }
    foreach ($c in $t.GetConstructors()) {
        $ps = @()
        foreach ($p in $c.GetParameters()) { $ps += ($p.ParameterType.Name + ' ' + $p.Name) }
        Write-Output ("  ctor(" + ($ps -join ', ') + ")")
    }
}
