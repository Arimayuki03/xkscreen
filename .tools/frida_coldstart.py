"""冷启动捕获：手动运行官方 SystemTemperatureMonitoring.exe（普通用户进程），
frida hook CreateFileA/WriteFile/ReadFile，录制从启动到点屏的完整 HID 报文流。
从当前工作目录（项目根）解析全部路径，无上级目录跳转。"""
import frida
import time
from pathlib import Path

ROOT = Path.cwd()
EXE = ROOT / "official" / "SystemTemperatureMonitoring.exe"
OUT = ROOT / "hid_cold.bin"
LOG = ROOT / "cold_progress.txt"

if OUT.exists():
    OUT.unlink()

AGENT = r"""
let hidHandles = new Set();

const cwa = Module.getGlobalExportByName('CreateFileA');
Interceptor.attach(cwa, {
    onEnter: function (args) { this.path = args[0].readAnsiString(); },
    onLeave: function (retval) {
        if (this.path && this.path.toLowerCase().indexOf('hid#vid_0145') !== -1
                && retval.toInt32() !== -1) {
            hidHandles.add(retval.toInt32());
            send({type: 'open', h: retval.toInt32()});
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

const rf = Module.getGlobalExportByName('ReadFile');
Interceptor.attach(rf, {
    onEnter: function (args) {
        this.h = args[0].toInt32();
        this.buf = args[1];
        this.len = args[2].toInt32();
    },
    onLeave: function (retval) {
        if (hidHandles.has(this.h) && this.len > 0) {
            send({type: 'read', len: this.len}, this.buf.readByteArray(this.len));
        }
    }
});
"""

pid = frida.spawn([str(EXE)], cwd=str(EXE.parent))
session = frida.attach(pid)
script = session.create_script(AGENT)

counts = {"w": 0, "r": 0, "open": 0}
fh = OUT.open("ab")
lf = LOG.open("w", encoding="utf-8")


def on_message(message, data):
    if message["type"] == "send":
        p = message["payload"]
        t = p.get("type")
        if t == "write" and data:
            counts["w"] += 1
            fh.write(b"W")
            fh.write(data)
            fh.flush()
        elif t == "read" and data:
            counts["r"] += 1
            fh.write(b"R")
            fh.write(data)
            fh.flush()
        else:
            counts["open"] += 1
            lf.write("open handle=" + str(p.get("h")) + "\n")
            lf.flush()
    elif message["type"] == "error":
        lf.write("[error] " + str(message.get("description", ""))[:200] + "\n")
        lf.flush()


script.on("message", on_message)
script.load()
frida.resume(pid)
print("spawned manual exe under frida, capturing 100s...", flush=True)

start = time.time()
while time.time() - start < 100:
    time.sleep(5)
    el = int(time.time() - start)
    size = OUT.stat().st_size if OUT.exists() else 0
    print(
        f"{el}s: writes={counts['w']} reads={counts['r']} opens={counts['open']} size={size}",
        flush=True,
    )

try:
    session.detach()
except Exception:
    pass
fh.close()
lf.close()
size = OUT.stat().st_size if OUT.exists() else 0
print(f"DONE total: writes={counts['w']} reads={counts['r']} size={size}")
