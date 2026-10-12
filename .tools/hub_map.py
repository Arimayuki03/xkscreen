"""列出每个根集线器下的直接子设备，判断屏幕换哪个 USB 口能落到 USBPcap1 覆盖的 hub。
结果写 UTF-8 文件避免控制台编码崩溃。"""
import os
import subprocess

_TOOLS = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(_TOOLS, "hub_map.txt")

ps = r"""
$ErrorActionPreference = 'SilentlyContinue'
$out = New-Object System.Collections.Generic.List[string]
foreach ($hub in (Get-PnpDevice -PresentOnly | Where-Object {$_.InstanceId -match 'ROOT_HUB30'})) {
  $out.Add("HUB " + $hub.InstanceId)
  foreach ($dev in (Get-PnpDevice -PresentOnly)) {
    $p = (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_Parent').Data
    if ($p -eq $hub.InstanceId) { $out.Add("   child: " + $dev.InstanceId) }
  }
}
$out | Out-File -FilePath <LOGPATH> -Encoding utf8
""".replace("<LOGPATH>", OUT)

r = subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True)
print("ps rc:", r.returncode)
if os.path.exists(OUT):
    print(open(OUT, encoding="utf-8-sig").read())
