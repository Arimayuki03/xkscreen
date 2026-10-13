param(
    [Parameter(Mandatory = $true)][string]$ProcessName,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$WaitMs = 1500
)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class XkW32 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
[void][XkW32]::SetProcessDPIAware()
Start-Sleep -Milliseconds $WaitMs
$p = Get-Process -Name ($ProcessName + "*") -ErrorAction SilentlyContinue |
     Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
if (-not $p) { throw "no '$ProcessName*' process with a visible window" }
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { throw "$ProcessName has no main window handle" }
$t = New-Object System.Text.StringBuilder 256
[void][XkW32]::GetWindowText($h, $t, 256)
$r = New-Object XkW32+RECT
[void][XkW32]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap($w, $hh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [XkW32]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc); $g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("captured " + $w + "x" + $hh + " '$($t.ToString())' ok=$ok -> $Out")
