import subprocess
import os

cmd = (
    "Start-Process -FilePath 'D:\\Code\\Xingcan-Xiaolan-Drive\\.tools\\USBPcapSetup.exe' "
    "-ArgumentList '/S' -Verb RunAs -Wait"
)
r = subprocess.run(["powershell", "-NoProfile", "-Command", cmd], capture_output=True, text=True)
print("rc:", r.returncode, r.stderr[:200])
print("installed:", os.path.exists(r"C:\Program Files\USBPcap\USBPcap.exe"))
