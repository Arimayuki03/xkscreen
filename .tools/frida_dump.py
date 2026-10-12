"""Frida 方案：spawn 子进程加载 TempComm，hook WriteFile 截获 HID 字节流。
所有文件经 pathlib 在项目根下解析。"""
import frida
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "hid_dump.bin"
CHILD = ROOT / "frida_child.py"
DLLDIR = ROOT / "src" / "XkScreen" / "bin" / "Release" / "net8.0"

AGENT = r"""
let hidHandles = new Set();
let totalDumped = 0;
let wfCount = 0;

function isHidPath(p) {
    try {
        return p && p.indexOf && p.toLowerCase().indexOf('hid#vid_0145') !== -1;
    } catch (e) { return false; }
}

const cw = Module.getGlobalExportByName('CreateFileW');
Interceptor.attach(cw, {
    onEnter: function (args) {
        this.path = args[0].readUtf16String();
    },
    onLeave: function (retval) {
        if (this.path && isHidPath(this.path) && retval.toInt32() !== -1) {
            hidHandles.add(retval.toInt32());
            send({type: 'open', path: this.path});
        }
    }
});

const cwa = Module.getGlobalExportByName('CreateFileA');
Interceptor.attach(cwa, {
    onEnter: function (args) {
        this.path = args[0].readAnsiString();
    },
    onLeave: function (retval) {
        if (this.path && isHidPath(this.path.toLowerCase()) && retval.toInt32() !== -1) {
            hidHandles.add(retval.toInt32());
            send({type: 'open-a', path: this.path});
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
        if (hidHandles.has(this.h)) {
            send({type: 'read', len: this.len}, this.buf.readByteArray(16));
        }
    }
});

const wf = Module.getGlobalExportByName('WriteFile');
Interceptor.attach(wf, {
    onEnter: function (args) {
        this.h = args[0].toInt32();
        this.buf = args[1];
        this.len = args[2].toInt32();
        wfCount++;
        if (wfCount <= 5) send({type: 'dbg-wf', h: this.h, len: this.len});
    },
    onLeave: function (retval) {
        try {
            if (hidHandles.has(this.h) && this.len > 0 && totalDumped < 200000) {
                const data = this.buf.readByteArray(this.len);
                totalDumped += this.len;
                send({type: 'write', len: this.len, handle: this.h}, data);
            }
        } catch (e) {
            send({type: 'wf-err', msg: String(e)});
        }
    }
});
"""

CHILD_SRC = f"""import ctypes, os, time
dll = os.path.join(r"{DLLDIR}", "HWCX.dll")
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
"""

CHILD.write_text(CHILD_SRC, encoding="utf-8")

argv = [sys.executable, str(CHILD)]
pid = frida.spawn(argv)
session = frida.attach(pid)
script = session.create_script(AGENT)

chunks = []


def on_message(message, data):
    if message["type"] == "send":
        payload = message["payload"]
        if payload.get("type") == "write" and data:
            chunks.append(data)
        elif payload.get("type") == "read" and data:
            print("[reply]", data.hex(" ")[:60], flush=True)
        else:
            print("[agent]", payload, flush=True)
    elif message["type"] == "error":
        print("[error]", str(message.get("description", ""))[:300], flush=True)


script.on("message", on_message)
script.load()
frida.resume(pid)
print("resumed, capturing 60s...", flush=True)
time.sleep(60)
try:
    session.detach()
except Exception:
    pass

OUT.write_bytes(b"".join(chunks))
print("dumped:", OUT.stat().st_size, "bytes ->", OUT, flush=True)
