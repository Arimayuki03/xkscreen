"""回放真实报文流：从 hid_dump.bin（frida 截获的 TempComm 真实输出）解析出全部
写包（W 标记 + 65B），按约 15 包/秒的速率连续回放。官方服务需停止。"""
import time
from pathlib import Path

import hid

ROOT = Path.cwd()
DUMP = ROOT / "hid_dump.bin"

data = DUMP.read_bytes()
packets = []
i = 0
while i < len(data):
    marker = data[i : i + 1]
    if marker == b"W":
        # 试 65 字节载荷；确认下一位置是标记
        if i + 66 <= len(data) and data[i + 66 : i + 67] in (b"W", b"R"):
            packets.append(data[i + 1 : i + 66])
            i += 66
        else:
            # 变长载荷：找下一个标记位置
            j = i + 1
            while j < len(data) and data[j : j + 1] not in (b"W", b"R"):
                j += 1
            packets.append(data[i + 1 : j])
            i = j
    elif marker == b"R":
        if i + 66 <= len(data) and data[i + 66 : i + 67] in (b"W", b"R"):
            i += 66
        else:
            j = i + 1
            while j < len(data) and data[j : j + 1] not in (b"W", b"R"):
                j += 1
            i = j
    else:
        i += 1

print("parsed write packets:", len(packets), flush=True)
lengths = {}
for p in packets:
    lengths[len(p)] = lengths.get(len(p), 0) + 1
print("length distribution:", lengths, flush=True)

devs = [d for d in hid.enumerate() if d["vendor_id"] == 0x0145]
if not devs:
    print("screen not found")
    raise SystemExit(1)
h = hid.device()
h.open_path(devs[0]["path"])
h.set_nonblocking(True)
print("opened, replaying at ~15 pkt/s for 60s...", flush=True)

t0 = time.time()
n = 0
try:
    while time.time() - t0 < 60:
        p = packets[n % len(packets)]
        h.write(p)
        n += 1
        # 排空输入报告
        for _ in range(4):
            r = h.read(65, timeout_ms=1)
            if not r:
                break
        time.sleep(0.066)
        if n % 150 == 0:
            print(f"{(time.time()-t0):.0f}s: sent {n}", flush=True)
except KeyboardInterrupt:
    pass
h.close()
print(f"done, sent {n} packets", flush=True)
