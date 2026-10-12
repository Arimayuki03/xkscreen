import ctypes, os

p = os.path.join(r"D:\Code\Xingcan-Xiaolan-Drive\src\XkScreen\bin\Release\net8.0", "HWCX.dll")
print("path:", p, flush=True)

print("LoadLibraryW only (no GetProcAddress)...", flush=True)
h = ctypes.WinDLL(p)
print("loaded, module handle =", hex(h._handle), flush=True)

# 不调用任何导出，只测加载。若这里崩 => DllMain 初始化崩溃；否则逐个函数测。
addr = ctypes.windll.kernel32.GetProcAddress(h._handle, b"GetOnlineDeviceQty")
print("GetOnlineDeviceQty proc =", hex(addr), flush=True)
