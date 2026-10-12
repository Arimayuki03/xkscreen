
import ctypes, ctypes.wintypes as wt, sys, subprocess
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mem_dump.txt")
log = open(OUT, "w", buffering=1)
def p(*a):
    s = " ".join(str(x) for x in a)
    log.write(s + "\n")
    try: print(s)
    except: pass

TOKEN_ADJUST_PRIVILEGES=0x20; TOKEN_QUERY=0x8; SE_DEBUG="SeDebugPrivilege"
k32=ctypes.windll.kernel32; adv=ctypes.windll.advapi32
h=ctypes.c_void_p(); r_ok=adv.OpenProcessToken(k32.GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES|TOKEN_QUERY, ctypes.byref(h)); print("OpenProcessToken:", r_ok, "handle:", h.value)
class LUID(ctypes.Structure): _fields_=[("LowPart",wt.DWORD),("HighPart",wt.LONG)]
class LUID_AND_ATTR(ctypes.Structure): _fields_=[("Luid",LUID),("Attributes",wt.DWORD)]
class TP(ctypes.Structure): _fields_=[("PrivilegeCount",wt.DWORD),("Privileges",LUID_AND_ATTR*1)]
luid=LUID(); adv.LookupPrivilegeValueW(None, SE_DEBUG, ctypes.byref(luid))
tp=TP(); tp.Privileges[0].Luid=luid; tp.Privileges[0].Attributes=2
adv.AdjustTokenPrivileges(h, False, ctypes.byref(tp), 0, None, None)
p("AdjustTokenPrivileges ret:", adv.AdjustTokenPrivileges(h, False, ctypes.byref(tp), 0, None, None), "err:", k32.GetLastError())

p("argv:", sys.argv); pid=int(sys.argv[1])
PROCESS_VM_READ=0x10; PROCESS_QUERY_INFORMATION=0x400; PROCESS_QUERY_LIMITED=0x1000
ph=k32.OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION, False, pid)
p("OpenProcess:", hex(ph or 0), "err:", k32.GetLastError())
if not ph: sys.exit(1)

# 模块基址
import ctypes.wintypes as w
k32.CreateToolhelp32Snapshot.restype=w.HANDLE
snap=k32.CreateToolhelp32Snapshot(0x8|0x2, pid)
class ME(ctypes.Structure):
    _fields_=[("dwSize",w.DWORD),("a",w.DWORD),("pid",w.DWORD),("g",w.DWORD),("p",w.DWORD),
              ("base",ctypes.c_void_p),("size",w.DWORD),("name",ctypes.c_char*256),("path",ctypes.c_char*260)]
me=ME(); me.dwSize=ctypes.sizeof(ME); base=None
ok=k32.Module32First(snap, ctypes.byref(me))
while ok:
    if me.name.decode(errors='ignore').lower()=='tempcomm.dll':
        base=me.base; p("TempComm base:", hex(base)); break
    ok=k32.Module32Next(snap, ctypes.byref(me))
p("base found:", bool(base))
if base:
    def rd(rva,n):
        buf=ctypes.create_string_buffer(n); got=ctypes.c_size_t()
        ok=k32.ReadProcessMemory(ph, ctypes.c_void_p(base+rva), buf, n, ctypes.byref(got))
        return buf.raw[:got.value] if ok else None
    p("== SetCheckUsb table @0x1DDE4 ==")
    blob=rd(0x1DDE4, 0x28*12) or b""
    for i in range(0,len(blob),0x28):
        c=blob[i:i+0x28]
        if any(c): p(f"  entry[{i//0x28}]:", c.hex(' '))
    p("== count @0x18904 ==", (rd(0x18904,4) or b'').hex(' '))
    p("== devtable @0x1AB40 ==")
    for idx in range(4):
        b=rd(0x1AB40+idx*0x288, 0x60) or b""
        if any(b): p(f"  dev[{idx}]:", b.hex(' '))
    p("== Set* globals @0x1AAE0 ==", (rd(0x1AAE0,0x30) or b'').hex(' '))
