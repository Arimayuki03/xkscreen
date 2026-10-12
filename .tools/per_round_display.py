"""每轮独立子进程方式持续点屏：
每轮 spawn 一个 python 子进程（frida hook WriteFile），执行一次
CheckOnlineDevice（握手）+ SetColor（颜色包），结束后子进程退出释放所有句柄。
主脚本循环拉起子进程，实现 500ms 级持续显示。"""
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHILD = ROOT / "frida_child_once.py"

CHILD_SRC = """import ctypes, os, sys, time
dll = os.path.join(r"{dll}", "HWCX.dll")
h = ctypes.WinDLL(dll)
h.CheckOnlineDevice.restype = ctypes.c_int
h.SetColor.restype = ctypes.c_int
r = h.CheckOnlineDevice()
time.sleep(0.3)
c = h.SetColor(0, bytes([0xFF, 0x00, 0x00, 0xFF]))
print("ok", r, c, flush=True)
""".format(dll=str(ROOT / "src" / "XkScreen" / "bin" / "Release" / "net8.0"))

CHILD.write_text(CHILD_SRC, encoding="utf-8")

AGENT = r"""
let hidHandles = new Set();
const cwa = Module.getGlobalExportByName('CreateFileA');
Interceptor.attach(cwa, {
    onEnter: function (args) { this.path = args[0].readAnsiString(); },
    onLeave: function (retval) {
        if (this.path && this.path.toLowerCase().indexOf('hid#vid_0145') !== -1
                && retval.toInt32() !== -1) {
            hidHandles.add(retval.toInt32());
        }
    }
});
const wf = Module.getGlobalExportByName('WriteFile');
Interceptor.attach(wf, {
    onEnter: function (args) {
        this.h = args[0].toInt32();
        this.buf = args[1];
        this.len = args[2].toInt32();
    },
    onLeave: function (retval) {
        if (hidHandles.has(this.h) && this.len > 0) {
            send({type: 'write', len: this.len}, this.buf.readByteArray(this.len));
        }
    }
});
"""

COLOR = sys.argv[1] if len(sys.argv) > 1 else "FF0000"
CHILD_SRC = CHILD_SRC.replace("0xFF, 0x00, 0x00", ",".join(str(int(COLOR[i:i+2], 16)) for i in (0, 2, 4)))
CHILD.write_text(CHILD_SRC, encoding="utf-8")

import frida

rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 20
total = 0
for i in range(rounds):
    try:
        pid = frida.spawn([sys.executable, str(CHILD)])
        session = frida.attach(pid)
        script = session.create_script(AGENT)
        chunks = []
        script.on("message", lambda m, d, ch=chunks: ch.append(d) if m["type"] == "send" and d else None)
        script.load()
        frida.resume(pid)
        time.sleep(2.5)
        try:
            session.detach()
        except Exception:
            pass
        got = b"".join(chunks)
        total += len(got)
        print(f"round {i}: {len(got)} bytes", flush=True)
    except Exception as e:
        print(f"round {i} error:", str(e)[:120], flush=True)

print("total:", total, "bytes over", rounds, "rounds", flush=True)
