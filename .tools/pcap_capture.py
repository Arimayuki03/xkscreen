"""用已知拓扑直接抓包：不交互列设备树。
USBPcap1 覆盖一个根集线器；用 -A 抓该 hub 上全部设备，先抓 5 秒验证有无数据，
同时把抓包结果落到 pcap 文件。管理员运行（UAC 弹窗）。"""
import subprocess
import sys
import time

DUR = sys.argv[1] if len(sys.argv) > 1 else "10"
OUT = r"D:\Code\Xingcan-Xiaolan-Drive\.tools\cap_test.pcap"

cmd = (
    "Start-Process cmd -ArgumentList '/c',"
    f"'\"C:\\Program Files\\USBPcap\\USBPcapCMD.exe\" -d \\\\.\\USBPcap1 -A -o {OUT} --snaplen 256' "
    f"& timeout /t {DUR} /nobreak > nul & taskkill /f /im USBPcapCMD.exe "
    "> D:\\Code\\Xingcan-Xiaolan-Drive\\.tools\\pcap_run.txt 2>&1' "
    "-Verb RunAs -Wait"
)
r = subprocess.run(["powershell", "-NoProfile", "-Command", cmd], capture_output=True, text=True)
print("rc:", r.returncode, r.stderr[:200])
time.sleep(1)
import os
print("pcap size:", os.path.getsize(OUT) if os.path.exists(OUT) else "missing")
print(open(r"D:\Code\Xingcan-Xiaolan-Drive\.tools\pcap_run.txt").read()[:300] if os.path.exists(r"D:\Code\Xingcan-Xiaolan-Drive\.tools\pcap_run.txt") else "")
