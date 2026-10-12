"""直接 hidapi 向 XK003 屏发 SetColor 报文（绕过 TempComm）。
官方服务运行时会占用设备 —— 先确认服务已停再跑。"""
import hid
import time

PATH = (
    b"\\\\?\\HID#VID_0145&PID_1001#7&2a30b4ea&0&0000#"
    b"{4d1e55b2-f16f-11cf-88cb-001111000030}"
)

h = hid.device()
h.open_path(PATH)
h.set_nonblocking(False)
print("opened")


def send64(payload: bytes):
    buf = bytes([0]) + payload[:64].ljust(64, b"\xFF")  # report id 0 前缀
    return h.write(buf)


def wake():
    """照 0x2C70 的唤醒序列: cmd 从 0x8000C00 步进 0x400 到 0x8003000。
    64B 缓冲先 memset 0xFF, [0] xor 0x88, [4..8] xor cmd。编码方式按 0x2C70 的 xor 语义猜测。"""
    cmd = 0x8000C00
    while cmd < 0x8003000:
        buf = bytearray(b"\xFF" * 64)
        buf[0] ^= 0x88
        # cmd dword 与 [rsp+0x24] xor → 大端/小端两种都试过才能确定；先小端
        dword = cmd.to_bytes(4, "little")
        for i in range(4):
            buf[4 + i] ^= dword[i]
        h.write(bytes([0]) + bytes(buf))
        cmd += 0x400
    print("wake sequence sent")


# 1) 明文 SetColor: [0]=0x05 [1..4]=R G B A
print("v1 plain red:", send64(bytes([0x05, 0xFF, 0x00, 0x00, 0xFF])))
time.sleep(3)
print("reply:", bytes(h.read(64, timeout_ms=500)).hex(" "))

# 2) not(cmd) 变体: 0x34c2 的 not [rsp+0x30]
print("v2 not-cmd red:", send64(bytes([0xFA, 0xFF, 0x00, 0x00, 0xFF])))
time.sleep(3)

# 3) 唤醒序列后再次 SetColor
wake()
time.sleep(1)
print("v3 after wake, plain red:", send64(bytes([0x05, 0xFF, 0x00, 0x00, 0xFF])))
time.sleep(3)
print("reply:", bytes(h.read(64, timeout_ms=500)).hex(" "))

h.close()
print("done")
