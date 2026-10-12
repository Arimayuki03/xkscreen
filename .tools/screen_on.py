"""XK003 屏幕常亮控制：持续显示指定颜色。
协议（frida 截获金标准）：
  握手包 65B: [0]=0 [1]=1 [2..4]=0 [5..6]=rand16大端 [7..0x3D]=随机 [0x3E]=xor校验 [0x3F]=sum校验
  颜色包 65B: [0]=0 [1]=05 [2]=R [3]=G [4]=B [5..0x40]=FF填充
  节奏: 握手→颜色，每 500ms 一轮（对齐官方服务）

用法: python screen_on.py FF8800   （颜色为 RRGGBB hex，缺省蓝色）
Ctrl+C 停止。"""
import hid
import random
import sys
import time

PATH = (
    b"\\\\?\\HID#VID_0145&PID_1001#7&2a30b4ea&0&0000#"
    b"{4d1e55b2-f16f-11cf-88cb-001111000030}"
)


def handshake() -> bytes:
    buf = bytearray(65)
    for i in range(1, 65):
        buf[i] = random.randint(0, 255)
    buf[0] = 0
    buf[1] = 1
    buf[2] = buf[3] = buf[4] = 0
    r16 = random.randint(0, 0xFFFF)
    buf[5] = (r16 >> 8) & 0xFF
    buf[6] = r16 & 0xFF
    buf[11] = 0
    cx = 0
    cs = 0
    for i in range(1, 0x3C):
        v = (i * buf[i]) & 0xFF
        cx ^= v
        cs = (cs + v) & 0xFF
    buf[0x3E] = cx
    buf[0x3F] = cs
    return bytes(buf)


def color_packet(r: int, g: int, b: int) -> bytes:
    return bytes([0, 0x05, r, g, b]) + b"\xFF" * 60


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "0000FF"
    r = int(arg[0:2], 16)
    g = int(arg[2:4], 16)
    b = int(arg[4:6], 16)
    print(f"屏幕常亮: #{arg} (R={r} G={g} B={b})  Ctrl+C 停止")

    devs = [d for d in hid.enumerate() if d["vendor_id"] == 0x0145]
    if not devs:
        print("未找到屏幕 (VID_0145&PID_1001)")
        return 1
    h = hid.device()
    h.open_path(devs[0]["path"])
    h.set_nonblocking(False)
    print("device opened")

    pkt = color_packet(r, g, b)
    try:
        while True:
            h.write(bytes(handshake()))
            h.write(bytes([0]) + pkt)
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        h.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
