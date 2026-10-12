"""读取正在运行的官方服务进程里 TempComm.dll 的关键全局变量：
- 0x1DDE4 (SetCheckUsb 写的匹配表, 0x28 字节 x 若干)
- 0x18904 (设备数量)
- 0x1AB40 (设备表, 0x288 x 15)
- 0x1AAE0..0x1AB00 (Set* 写的全局区)
"""
import ctypes
import ctypes.wintypes as wt
import os
import sys

# 提权运行时输出重定向到文件
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mem_dump.txt")
_log = open(OUT, "w", encoding="utf-8", buffering=1)


class Tee:
    def __init__(self, *streams):
        self.streams = streams

    def write(self, s):
        for st in self.streams:
            st.write(s)
            st.flush()

    def flush(self):
        for st in self.streams:
            st.flush()


sys.stdout = Tee(sys.__stdout__, _log)

PROCESS_VM_READ = 0x0010
PROCESS_QUERY_INFORMATION = 0x0400

ps = ctypes.windll.psapi
k32 = ctypes.windll.kernel32

# 找服务 PID
import subprocess
r = subprocess.run(
    ["powershell", "-NoProfile", "-Command",
     "(Get-Process SystemTemperatureMonitoring).Id"],
    capture_output=True, text=True,
)
pid = int(r.stdout.strip().splitlines()[0])
print("service PID:", pid)

h = k32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, False, pid)
print("OpenProcess handle:", h)
if not h:
    print("OpenProcess failed err=", k32.GetLastError())
    sys.exit(1)

# 找 TempComm.dll 模块基址
hps = k32.CreateToolhelp32Snapshot(0x8 | 0x2, pid)  # TH32CS_SNAPMODULE
class MODULEENTRY32(ctypes.Structure):
    _fields_ = [
        ("dwSize", wt.DWORD), ("th32ModuleID", wt.DWORD), ("th32ProcessID", wt.DWORD),
        ("GlblcntUsage", wt.DWORD), ("ProccntUsage", wt.DWORD), ("modBaseAddr", ctypes.POINTER(ctypes.c_byte)),
        ("modBaseSize", wt.DWORD), ("szModule", ctypes.c_char * 256), ("szExePath", ctypes.c_char * 260),
    ]
me = MODULEENTRY32()
me.dwSize = ctypes.sizeof(MODULEENTRY32)
base = None
if k32.Module32First(hps, ctypes.byref(me)):
    while True:
        name = me.szModule.decode(errors="ignore").lower()
        if name == "tempcomm.dll":
            base = ctypes.cast(me.modBaseAddr, ctypes.c_void_p).value
            print(f"TempComm.dll base = {hex(base)} size={hex(me.modBaseSize)}")
            break
        if not k32.Module32Next(hps, ctypes.byref(me)):
            break
assert base, "TempComm.dll not found in service process"


def read_mem(rva, size):
    buf = ctypes.create_string_buffer(size)
    got = ctypes.c_size_t()
    ok = k32.ReadProcessMemory(h, ctypes.c_void_p(base + rva), buf, size, ctypes.byref(got))
    if not ok:
        return None
    return buf.raw[: got.value]


print("\n== SetCheckUsb 表 @0x1DDE4 ==")
blob = read_mem(0x1DDE4, 0x28 * 12)
for i in range(0, len(blob), 0x28):
    chunk = blob[i : i + 0x28]
    if any(chunk):
        print(f"  entry[{i//0x28}]: {chunk.hex(' ')}")

print("\n== 设备数量 @0x18904 ==")
print("  ", read_mem(0x18904, 4).hex(" "))

print("\n== 设备表 @0x1AB40 (前 3 项, 每项 0x288) ==")
for idx in range(3):
    blob = read_mem(0x1AB40 + idx * 0x288, 0x60)
    if any(blob):
        print(f"  dev[{idx}] head 0x60: {blob.hex(' ')}")

print("\n== Set* 全局区 @0x1AAE0 (0x30 字节) ==")
blob = read_mem(0x1AAE0, 0x30)
print("  ", blob.hex(" "))

k32.CloseHandle(h)
print("\ndone")
