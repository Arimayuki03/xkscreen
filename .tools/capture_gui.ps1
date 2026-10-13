param(
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Width = 1520,
    [int]$Height = 1120,
    [int]$X = 60,
    [int]$Y = 40
)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class XkWin32 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
[void][XkWin32]::SetProcessDPIAware()
$p = Get-Process XkScreen.Gui -ErrorAction Stop
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { throw "XkScreen.Gui has no main window handle" }
$t = New-Object System.Text.StringBuilder 256
[void][XkWin32]::GetWindowText($h, $t, 256)
[void][XkWin32]::ShowWindow($h, 9)              # SW_RESTORE
[void][XkWin32]::MoveWindow($h, $X, $Y, $Width, $Height, $true)
Start-Sleep -Milliseconds 1800
$r = New-Object XkWin32+RECT
[void][XkWin32]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
# PrintWindow(PW_RENDERFULLCONTENT) renders the window's own content into the
# bitmap regardless of z-order, so a background window can be captured without
# fighting SetForegroundWindow.
$bmp = New-Object System.Drawing.Bitmap($w, $hh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [XkWin32]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()
# Blank-frame guard: an all-identical frame means the render failed.
$a1 = $bmp.GetPixel(5, 5).ToArgb()
$a2 = $bmp.GetPixel([int]($w / 2), [int]($hh / 2)).ToArgb()
$a3 = $bmp.GetPixel($w - 5, $hh - 5).ToArgb()
$a4 = $bmp.GetPixel(5, $hh - 5).ToArgb()
$a5 = $bmp.GetPixel($w - 5, 5).ToArgb()
$distinct = (@($a1, $a2, $a3, $a4, $a5) | Sort-Object -Unique).Count
if (-not $ok -or $distinct -le 1) {
  $bmp.Dispose()
  throw ("PrintWindow failed (ok=" + $ok + ", distinctColors=" + $distinct + ")")
}
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("captured " + $w + "x" + $hh + " title='" + $t.ToString() + "' distinct=" + $distinct + " -> " + $Out)
