"""交互模式重装 USBPcap（会弹 UAC 和安装界面，用户点确认即可）。"""
import subprocess
import os

cmd = (
    "Start-Process -FilePath 'D:\\Code\\Xingcan-Xiaolan-Drive\\.tools\\USBPcapSetup.exe' "
    "-Verb RunAs -Wait"
)
r = subprocess.run(["powershell", "-NoProfile", "-Command", cmd], capture_output=True, text=True)
print("rc:", r.returncode, r.stderr[:200])
print("exe present:", os.path.exists(r"C:\Program Files\USBPcap\USBPcapCMD.exe"))
