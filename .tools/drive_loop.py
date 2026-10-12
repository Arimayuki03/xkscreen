"""持续驱动测试：单进程保持设备句柄不关，循环调用官方 TempComm 的
CheckOnlineDevice + SetColor，形成 ~15 包/秒的连续流，持续 90 秒。
原理：官方服务运行时就是这么持续驱动的（手柄常开 + 密流），此前所有测试
要么句柄频繁开关、要么节奏过稀。"""
import ctypes
import os
import time

ROOT = os.getcwd()
DLL = os.path.join(ROOT, "src", "XkScreen", "bin", "Release", "net8.0", "HWCX.dll")

h = ctypes.WinDLL(DLL)
h.CheckOnlineDevice.restype = ctypes.c_int
h.GetOnlineDeviceQty.restype = ctypes.c_int
h.DeviceClose.restype = ctypes.c_int
h.SetCheckUsb.restype = ctypes.c_int
h.SetColor.restype = ctypes.c_int

# 注册屏幕 VID/PID（字节对编码: 01 45 = 0x0145, 10 01 = 0x1001）
h.SetCheckUsb(bytes([0x01, 0x45, 0x10, 0x01]), 2, 20)

# 先打开一次（保持句柄）
r0 = h.CheckOnlineDevice()
print("open:", r0, "qty:", h.GetOnlineDeviceQty(), flush=True)

RED = bytes([0xFF, 0x00, 0x00, 0xFF])
t0 = time.time()
i = 0
while time.time() - t0 < 90:
    # 不调 DeviceClose — 保持设备打开，持续补帧
    h.CheckOnlineDevice()
    h.SetColor(0, RED)
    i += 1
    time.sleep(0.07)
    if i % 150 == 0:
        print(f"{time.time()-t0:.0f}s: rounds={i}", flush=True)

print("done rounds:", i, flush=True)
