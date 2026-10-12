"""实机验证 V2：唤醒序列(9包) + 完整数据序列(180包,Unicorn 仿真所得)。
按 TempComm 0x3494 的真实调用顺序：0x2C70 唤醒 → 0x2D24 数据序列。
发送节奏对齐反汇编：每包立即发，序列完成后进入 500ms 周期。"""
import hid
import time

PATH = (
    b"\\\\?\\HID#VID_0145&PID_1001#7&2a30b4ea&0&0000#"
    b"{4d1e55b2-f16f-11cf-88cb-001111000030}"
)

# 从 all_packets.txt 读取仿真所得的 180 个报文
packets = []
with open(r"D:\Code\Xingcan-Xiaolan-Drive\.tools\all_packets.txt", encoding="utf-8") as f:
    for line in f:
        if line.startswith("pkt["):
            packets.append(bytes.fromhex(line.split(":", 1)[1].strip()))
print("loaded packets:", len(packets))

h = hid.device()
h.open_path(PATH)
h.set_nonblocking(False)
print("opened", flush=True)


def send64(payload: bytes) -> int:
    return h.write(bytes([0]) + payload[:64].ljust(64, b"\x00"))


# 唤醒序列（0x2C70 仿真所得）
wake = []
cmd = 0x8000C00
while cmd < 0x8003000:
    buf = bytearray(64)
    buf[0] ^= 0x88
    for i, b in enumerate(cmd.to_bytes(4, "little")):
        buf[4 + i] ^= b
    wake.append(bytes(buf))
    cmd += 0x400

print("sending wake x", len(wake), flush=True)
for w in wake:
    send64(w)
    time.sleep(0.03)

print("sending data sequence x", len(packets), flush=True)
for p in packets:
    send64(p)
    time.sleep(0.01)

# 数据序列里应含 SetColor 效果;追加三轮红绿确认
print("done - watch the screen", flush=True)
h.close()
