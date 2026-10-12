"""周期写色测试（60 秒，请求用户全程盯屏）。
官方服务保持运行。我们以 300ms 周期交替发送 红色/黑色 纯色包，共 60 秒。
若屏幕出现明显闪烁或整屏变红/变黑 → 报文格式正确。
若画面纹丝不动 → 报文不被屏幕识别。"""
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
    return h.write(bytes([0]) + payload[:64].ljust(64, b"\xFF"))


def wake():
    """照 TempComm 0x2C70 语义: cmd 0x8000C00 步进 0x400 至 0x8003000,
    buf 全 0xFF, [0]^=0x88, [4:8]^=cmd(小端)。"""
    cmd = 0x8000C00
    while cmd < 0x8003000:
        buf = bytearray(b"\xFF" * 64)
        buf[0] ^= 0x88
        for i, b in enumerate(cmd.to_bytes(4, "little")):
            buf[4 + i] ^= b
        send64(bytes(buf))
        cmd += 0x400


wake()
print("wake done", flush=True)

red = bytes([0x05, 0xFF, 0x00, 0x00, 0xFF])
black = bytes([0x05, 0x00, 0x00, 0x00, 0xFF])
print(">>> 60 秒红/黑交替开始，请盯屏幕 <<<", flush=True)
t0 = time.time()
i = 0
while time.time() - t0 < 60:
    send64(red if i % 2 == 0 else black)
    time.sleep(0.3)
    i += 1
print(f"sent {i} packets, done", flush=True)
h.close()
