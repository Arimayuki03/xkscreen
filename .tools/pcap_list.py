"""以管理员运行 USBPcapCMD 列出设备树，输出到 .tools/pcap_list.txt。"""
import subprocess

cmd = (
    "Start-Process cmd -ArgumentList '/c',"
    "'\"C:\\Program Files\\USBPcap\\USBPcapCMD.exe\" > "
    "D:\\Code\\Xingcan-Xiaolan-Drive\\.tools\\pcap_list.txt 2>&1' "
    "-Verb RunAs -Wait"
)
r = subprocess.run(["powershell", "-NoProfile", "-Command", cmd], capture_output=True, text=True)
print("rc:", r.returncode, r.stderr[:200])
