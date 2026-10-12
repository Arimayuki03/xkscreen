"""重放官方真实报文（frida dump 原字节）：握手包+颜色包交替，验证协议。"""
import hid
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
d = (ROOT / "hid_dump.bin").read_bytes()
pkts = [d[i : i + 65] for i in range(0, len(d) - 64, 65)]
handshake_pkt = pkts[0]
color_red = next(p for p in pkts if p[1] == 0x05)

devs = [dev for dev in hid.enumerate() if dev["vendor_id"] == 0x0145]
h = hid.device()
h.open_path(devs[0]["path"])
h.set_nonblocking(False)
print("opened", flush=True)

for rnd in range(4):
    h.write(bytes(handshake_pkt))
    time.sleep(0.05)
    h.write(bytes(color_red))
    print(f"round {rnd}: handshake+RED", flush=True)
    time.sleep(2)

h.close()
print("done")
