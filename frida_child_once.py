import ctypes, os, sys, time
dll = os.path.join(r"D:\Code\Xingcan-Xiaolan-Drive\src\XkScreen\bin\Release\net8.0", "HWCX.dll")
h = ctypes.WinDLL(dll)
h.CheckOnlineDevice.restype = ctypes.c_int
h.SetColor.restype = ctypes.c_int
r = h.CheckOnlineDevice()
time.sleep(0.3)
c = h.SetColor(0, bytes([255,0,0, 0xFF]))
print("ok", r, c, flush=True)
