"""实机验证：唤醒序列(9包,全零填充+0x88/cmd 混淆) + SetColor 红绿交替。
官方服务需已停止。请盯着屏幕看红/绿是否出现。"""
import hid
import time

PATH = (
    b"\\\\?\\HID#VID_0145&PID_1001#7&2a30b4ea&0&0000#"
    b"{4d1e55b2-f16f-11cf-88cb-001111000030}"
)

h = hid.device()
h.open_path(PATH)
h.set_nonblocking(False)
print("opened", flush=True)


def send64(payload: bytes) -> int:
    return h.write(bytes([0]) + payload[:64].ljust(64, b"\x00"))


# 唤醒序列（Unicorn 仿真 0x2C70 得到的金标准）
cmd = 0x8000C00
n = 0
while cmd < 0x8003000:
    buf = bytearray(64)
    buf[0] ^= 0x88
    for i, b in enumerate(cmd.to_bytes(4, "little")):
        buf[4 + i] ^= b
    send64(bytes(buf))
    time.sleep(0.05)
    cmd += 0x400
    n += 1
print("wake packets:", n, flush=True)
time.sleep(0.5)

# SetColor 红/绿交替各 3 次
for rnd in range(3):
    r = send64(bytes([0x05, 0xFF, 0x00, 0x00, 0xFF]))
    print(f"RED write={r}", flush=True)
    time.sleep(2)
    g = send64(bytes([0x05, 0x00, 0xFF, 0x00, 0xFF]))
    print(f"GREEN write={g}", flush=True)
    time.sleep(2)

print("reply:", bytes(h.read(64, timeout_ms=500)).hex(" ") or "(none)")
h.close()
print("done")
