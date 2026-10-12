import ctypes, os, time
dll = os.path.join(r"D:\Code\Xingcan-Xiaolan-Drive\src\XkScreen\bin\Release\net8.0", "HWCX.dll")
h = ctypes.WinDLL(dll)
h.CheckOnlineDevice.restype = ctypes.c_int
h.GetOnlineDeviceQty.restype = ctypes.c_int
h.DeviceClose.restype = ctypes.c_int
h.SetCheckUsb.restype = ctypes.c_int
h.SetColor.restype = ctypes.c_int
time.sleep(2)
h.SetCheckUsb(bytes([0x01, 0x45, 0x10, 0x01]), 2, 20)
for i in range(40):
    h.DeviceClose()
    r = h.CheckOnlineDevice()
    c = h.SetColor(0, bytes([0xFF, 0x00, 0x00, 0xFF]))
    if i % 5 == 0:
        print("round", i, "chk:", r, "color:", c, flush=True)
    time.sleep(0.3)
print("child done", flush=True)
