# Probe 7: single-threaded call into the CPUID SDK native init to read the
# exact error code (the vendor maps it to "Driver error N" etc.).
$ErrorActionPreference = 'Continue'
$dir = 'D:\Code\Xingcan-Xiaolan-Drive\official'
Set-Location $dir
$asm = [Reflection.Assembly]::LoadFrom("$dir\HardwareHelp64.dll")
$t = $asm.GetType('HardwareHelp.CPUIDSDK', $true)
Write-Output ("type = " + $t.FullName)
$sdk = [Activator]::CreateInstance($t)
$miCi = $t.GetMethod('CreateInstance')
$ci = $miCi.Invoke($sdk, $null)
Write-Output ("CreateInstance -> $ci")
if ($ci) {
    $mi = $t.GetMethod('Init2')
    $argv = @([uint32]2147483647, 0, 0)
    try {
        $r = $mi.Invoke($sdk, $argv)
        Write-Output ("Init2 -> $r errorcode=" + $argv[1] + " ext=" + $argv[2])
    } catch {
        Write-Output ("Init2 EX: " + $_.Exception.GetType().Name + " / " + $_.Exception.Message)
        if ($_.Exception.InnerException) { Write-Output ("  inner: " + $_.Exception.InnerException.GetType().Name + " / " + $_.Exception.InnerException.Message) }
    }
    $miV = $t.GetMethod('GetDllVersion')
    if ($miV) { $v = @(0); try { [void]$miV.Invoke($sdk, $v); Write-Output ("DllVersion = " + $v[0]) } catch { Write-Output ("GetDllVersion EX: " + $_.Exception.Message) } }
    foreach ($mn in @('GetDisplayAdapterFanSpeed','GetDisplayAdapterFanPWM')) {
        $m2 = $t.GetMethod($mn)
        if ($m2) { foreach ($i in 0,1) { try { Write-Output ("$mn($i) = " + $m2.Invoke($sdk, @($i))) } catch { Write-Output ("$mn($i) EX: " + $_.Exception.Message) } } }
    }
    try { [void]$t.GetMethod('Close').Invoke($sdk, $null) } catch { }
}
Write-Output "probe7 done"
