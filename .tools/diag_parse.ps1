$f = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\xkw_driver_loop.ps1'
$bytes = [IO.File]::ReadAllBytes($f)
$gbk = [Text.Encoding]::GetEncoding(936).GetString($bytes)
$lines = $gbk -split "`n"
Write-Output '--- GBK-decoded lines 55..66 (0-based):'
foreach ($i in 55..66) {
    if ($i -lt $lines.Count) { Write-Output ("[$i] " + $lines[$i]) }
}
Write-Output ''
Write-Output '--- AST checks:'
$errs = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errs)
foreach ($name in '$timeFile', '$ringCpuFile', '$tSpec', '$tVal') {
    $found = $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.AssignmentStatementAst] -and $a.Left.Extent.Text -eq $name }, $true)
    Write-Output ($name + ' assignments in AST: ' + $found.Count + ' -> lines: ' + (($found | ForEach-Object { $_.Extent.StartLineNumber }) -join ','))
}
Write-Output '--- parse errors:'
if ($errs) { $errs | ForEach-Object { Write-Output ('  line ' + $_.Extent.StartLineNumber + ': ' + $_.Message) } } else { Write-Output '  (none)' }
