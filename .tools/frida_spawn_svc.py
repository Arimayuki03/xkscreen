"""frida spawn 官方服务 exe：在服务进程启动前 hook WriteFile/CreateFileA，
截获包括上电初始化在内的完整报文流。
需要管理员（frida spawn SYSTEM 服务由 frida 自己拉起为子进程）。
输出: hid_init.bin（全部字节流）+ 控制台统计。"""
import frida
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "hid_init.bin"
SVC = ROOT / "official" / "SystemTemperatureMonitoring.exe"

AGENT = r"""
let hidHandles = new Set();
let totalDumped = 0;

const cwa = Module.getGlobalExportByName('CreateFileA');
Interceptor.attach(cwa, {
    onEnter: function (args) { this.path = args[0].readAnsiString(); },
    onLeave: function (retval) {
        if (this.path && this.path.toLowerCase().indexOf('hid#vid_0145') !== -1
                && retval.toInt32() !== -1) {
            hidHandles.add(retval.toInt32());
            send({type: 'open'});
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
        if (hidHandles.has(this.h) && this.len > 0 && totalDumped < 2000000) {
            totalDumped += this.len;
            send({type: 'write', len: this.len}, this.buf.readByteArray(this.len));
        }
    }
});
"""

pid = frida.spawn([str(SVC)])
print("spawned pid:", pid, flush=True)
device = frida.get_local_device()
session = device.attach(pid)
print("session:", type(session).__name__, flush=True)
script = session.create_script(AGENT)

chunks = []


def on_message(message, data):
    if message["type"] == "send":
        payload = message["payload"]
        if payload.get("type") == "write" and data:
            chunks.append(data)
        else:
            print("[agent]", payload, flush=True)
    elif message["type"] == "error":
        print("[error]", str(message.get("description", ""))[:200], flush=True)


script.on("message", on_message)
script.load()
frida.resume(pid)
print("spawned service, capturing 45s (covers 30s delay + startup)...", flush=True)
time.sleep(45)
try:
    session.detach()
except Exception:
    pass

blob = b"".join(chunks)
OUT.write_bytes(blob)
print("dumped:", len(blob), "bytes ->", OUT, flush=True)
