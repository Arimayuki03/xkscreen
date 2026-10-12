"""探测 USBPcap 控制设备节点是否存在（\\\\.\\USBPcap1..6）。"""
import ctypes

k32 = ctypes.windll.kernel32
found = []
for i in range(1, 7):
    path = "\\\\.\\USBPcap{}".format(i)
    h = k32.CreateFileW(path, 0x80000000, 0, None, 3, 0, None)  # GENERIC_READ, OPEN_EXISTING
    if h not in (-1, 0xFFFFFFFFFFFFFFFF):
        print(path, "EXISTS")
        k32.CloseHandle(h)
        found.append(i)
    else:
        print(path, "err", k32.GetLastError())

print("found:", found)
