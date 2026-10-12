"""完整协议重放 V3：
1) 0x1260 握手包（65B HID report：[0]=report_id 0，[1]=1，[5..6]=rand16 大端，尾部双校验）
2) 0x2C70 唤醒序列（9 包）
3) 0x2D24 数据序列（180 包，Unicorn 仿真所得）
4) SetColor 红/绿交替
官方服务需停止。请盯屏幕。"""
import hid
import random
import time

PATH = (
    b"\\\\?\\HID#VID_0145&PID_1001#7&2a30b4ea&0&0000#"
    b"{4d1e55b2-f16f-11cf-88cb-001111000030}"
)

h = hid.device()
h.open_path(PATH)
h.set_nonblocking(False)
print("opened", flush=True)

# ---- 1) 握手包（0x1260 还原：65B 缓冲 = report_id + 64B，随机体 + 固定头 + 双校验） ----
buf = bytearray(65)
for i in range(65):
    buf[i] = random.randint(0, 255)
buf[0] = 0                    # report id
buf[1] = 1                    # 标志
buf[2] = buf[3] = buf[4] = 0
rand16 = random.randint(0, 0xFFFF)
buf[5] = (rand16 >> 8) & 0xFF
buf[6] = rand16 & 0xFF
buf[11] = 0
chk_xor = 0
chk_sum = 0
for i in range(1, 0x3C):      # 校验覆盖 [1..0x3B]
    v = (i * buf[i]) & 0xFF
    chk_xor ^= v
    chk_sum = (chk_sum + v) & 0xFF
buf[0x3F] = chk_xor
buf[0x40] = chk_sum
r = h.write(bytes(buf))       # 65B 含 report id
print("handshake write:", r, flush=True)
time.sleep(1)

# ---- 2) 唤醒序列 ----
cmd = 0x8000C00
while cmd < 0x8003000:
    b = bytearray(64)
    b[0] ^= 0x88
    for i, x in enumerate(cmd.to_bytes(4, "little")):
        b[4 + i] ^= x
    h.write(bytes([0]) + bytes(b))
    time.sleep(0.03)
    cmd += 0x400
print("wake done", flush=True)
time.sleep(0.5)

# ---- 3) 数据序列 180 包 ----
packets = []
with open(r"D:\Code\Xingcan-Xiaolan-Drive\.tools\all_packets.txt", encoding="utf-8") as f:
    for line in f:
        if line.startswith("pkt["):
            packets.append(bytes.fromhex(line.split(":", 1)[1].strip()))
for p in packets:
    h.write(bytes([0]) + p)
    time.sleep(0.01)
print("data sequence done:", len(packets), flush=True)
time.sleep(1)

# ---- 4) SetColor 红/绿 ----
for rnd in range(2):
    h.write(bytes([0]) + bytes([0x05, 0xFF, 0, 0, 0xFF]).ljust(64, b"\x00"))
    print("RED", flush=True)
    time.sleep(3)
    h.write(bytes([0]) + bytes([0x05, 0, 0xFF, 0, 0xFF]).ljust(64, b"\x00"))
    print("GREEN", flush=True)
    time.sleep(3)

h.close()
print("done")
