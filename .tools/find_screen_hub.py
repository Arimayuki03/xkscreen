"""查屏幕挂在哪个根集线器下（父设备链），决定用 USBPcap1 还是 USBPcap2 抓包。
输出重定向到 UTF-8 文件避免控制台编码问题。"""
import subprocess

ps = r"""
$screen = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_0145' }
foreach ($dev in $screen) {
  Write-Output ("DEV: " + $dev.InstanceId)
  $parent = (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_Parent').Data
  Write-Output ("PARENT: " + $parent)
  $gp = (Get-PnpDeviceProperty -InstanceId $parent -KeyName 'DEVPKEY_Device_Parent').Data
  Write-Output ("GRANDPARENT: " + $gp)
}
"""
r = subprocess.run(
    ["powershell", "-NoProfile", "-Command", ps],
    capture_output=True,
)
text = r.stdout.decode("utf-8", "replace") or r.stderr.decode("utf-8", "replace")
print(text)
