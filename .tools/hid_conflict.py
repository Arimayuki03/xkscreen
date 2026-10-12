"""冲突实验：官方服务运行中（屏幕显示硬件信息）时，用 hidapi 强写纯色包。
- open 失败 → 设备被服务独占（另一个信息）
- open 成功但屏幕无变化 → 报文格式不对
- 屏幕闪纯色 → 格式对，只差持续刷新
写两次红色，每次间隔 2 秒，然后恢复读取一次应答。"""
import hid
import time

PATH = (
    b"\\\\?\\HID#VID_0145&PID_1001#7&2a30b4ea&0&0000#"
    b"{4d1e55b2-f16f-11cf-88cb-001111000030}"
)

h = hid.device()
try:
    h.open_path(PATH)
except OSError as e:
    print("OPEN FAILED:", e)
    raise SystemExit(1)

print("opened despite service running!")
h.set_nonblocking(False)

for i in range(2):
    buf = bytes([0]) + bytes([0x05, 0xFF, 0x00, 0x00, 0xFF]).ljust(64, b"\xFF")
    n = h.write(buf)
    print(f"write#{i}: {n} bytes")
    time.sleep(2)

print("reply:", bytes(h.read(64, timeout_ms=500)).hex(" ") or "(none)")
h.close()
print("done")
