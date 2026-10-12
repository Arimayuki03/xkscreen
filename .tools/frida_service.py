"""frida attach 到官方服务进程，hook WriteFile 截获它发给屏幕 HID 的真实报文流。
需要管理员运行（SYSTEM 进程 attach）。结果打印并保存 hid_service.bin。"""
import frida
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "hid_service.bin"

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
        if (hidHandles.has(this.h) && this.len > 0 && totalDumped < 1000000) {
            totalDumped += this.len;
            send({type: 'write', len: this.len}, this.buf.readByteArray(this.len));
        }
    }
});
"""

session = frida.attach(40324)
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
        print("[error]", str(message.get("description", ""))[:300], flush=True)


script.on("message", on_message)
script.load()
print("attached & hooks live, capturing 30s (service should be displaying)...", flush=True)
time.sleep(30)
session.detach()

blob = b"".join(chunks)
OUT.write_bytes(blob)
print("dumped:", len(blob), "bytes ->", OUT, flush=True)
