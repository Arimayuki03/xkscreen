"""USBPcap1 长抓 25 秒：官方服务每 500ms 发包，若 USBPcap1 覆盖其总线则 pcap 应有记录。"""
import os
import subprocess
import threading
import time

EXE = os.path.join("C:" + os.sep, "Program Files", "USBPcap", "USBPcapCMD.exe")
PCAP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cap_test.pcap")
if os.path.exists(PCAP):
    os.remove(PCAP)

DEV = "\\" * 2 + "." + "\\" + "USBPcap1"


def capture():
    try:
        subprocess.run(
            [EXE, "-d", DEV, "-A", "-o", PCAP, "--snaplen", "256"],
            timeout=25,
            capture_output=True,
        )
    except subprocess.TimeoutExpired:
        pass


t = threading.Thread(target=capture, daemon=True)
t.start()
print("capturing 25s (service is running, expect its 500ms packets)...")
time.sleep(26)
size = os.path.getsize(PCAP) if os.path.exists(PCAP) else 0
print("pcap size:", size)
