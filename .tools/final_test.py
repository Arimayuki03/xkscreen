"""决定性测试：SetCheckUsb(必须先调) → CheckOnlineDevice → 等线程握手 → SetColor 循环。
官方服务保持停止。进程存活 100 秒。"""
import ctypes
import time
import os
import shutil

base = r"D:\Code\Xingcan-Xiaolan-Drive\src\XkScreen\bin\Release\net8.0"
shutil.copy(
    r"D:\Code\Xingcan-Xiaolan-Drive\official\TempComm.dll",
    os.path.join(base, "HWCX.dll"),
)
h = ctypes.WinDLL(os.path.join(base, "HWCX.dll"))
h.SetCheckUsb.restype = ctypes.c_int
h.CheckOnlineDevice.restype = ctypes.c_int
h.GetOnlineDeviceQty.restype = ctypes.c_int
h.SetColor.restype = ctypes.c_int

# SetCheckUsb(字节对数组, n, cap) — 字节对为 VID 编码: [0x01,0x45]=0x0145, [0x10,0x01]=0x1001
vidpid = bytes([0x01, 0x45, 0x10, 0x01])
for n in (1, 2):
    r = h.SetCheckUsb(vidpid, n, 20)
    print(f"SetCheckUsb(n={n}) = {r}", flush=True)
    online = h.CheckOnlineDevice()
    qty = h.GetOnlineDeviceQty()
    print(f"  online={online} qty={qty}", flush=True)
    if qty >= 1:
        break

print("等 15s 让工作线程打开设备+握手...", flush=True)
time.sleep(15)

colors = ([0xFF, 0, 0, 0xFF], [0, 0xFF, 0, 0xFF], [0, 0, 0xFF, 0xFF], [0xFF, 0xFF, 0, 0xFF])
names = ("RED", "GREEN", "BLUE", "YELLOW")
t0 = time.time()
i = 0
while time.time() - t0 < 80:
    rc = h.SetColor(0, bytes(colors[i % 4]))
    print(f"{time.time()-t0:5.1f}s SetColor {names[i%4]} -> {rc}", flush=True)
    time.sleep(15)
    i += 1
print("DONE (alive 100s)")
