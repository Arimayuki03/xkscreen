"""用计划任务以最高权限运行抓包 bat：
1. 创建任务 XkPcap（只运行一次，最高权限）
2. 触发运行；由调用方控制时长后 taskkill USBPcapCMD 结束抓包
用法: python pcap_run.py <capture_seconds>"""
import os
import subprocess
import sys
import time

_TOOLS = os.path.dirname(os.path.abspath(__file__))
DUR = sys.argv[1] if len(sys.argv) > 1 else "10"
BAT = os.path.join(_TOOLS, "cap_run.bat")
PCAP = os.path.join(_TOOLS, "cap_test.pcap")

# 清理旧任务与旧 pcap
subprocess.run(["schtasks", "/Delete", "/TN", "XkPcap", "/F"], capture_output=True)
if os.path.exists(PCAP):
    os.remove(PCAP)

# 创建 + 运行（schtasks 参数用 / 前缀，Git Bash 下会被转义，故用 mshta 风格的 // 不行，走 python 直接调）
r = subprocess.run(
    ["schtasks", "/Create", "/TN", "XkPcap", "/TR", BAT, "/SC", "ONCE", "/RL", "HIGHEST", "/F"],
    capture_output=True,
)
r2 = subprocess.run(["schtasks", "/Run", "/TN", "XkPcap"], capture_output=True)
print("create:", r.returncode, "| run:", r2.returncode)

# 等 USBPcapCMD 起来
time.sleep(3)
print("running for", DUR, "s ...")
time.sleep(int(DUR))

# 结束抓包（USBPcapCMD 收到 kill 后会把缓冲写盘）
subprocess.run(["taskkill", "/F", "/IM", "USBPcapCMD.exe"], capture_output=True)
time.sleep(2)
print("pcap size:", os.path.getsize(PCAP) if os.path.exists(PCAP) else "missing")
