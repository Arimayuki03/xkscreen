# Attach to the running XkScreen.Service process and print every 65-byte HID
# report it writes, plus any (re)open of the screen's device path. Used to
# diagnose what is still talking to the display while frames are paused.
#
# The script only prints to stdout - the caller redirects to a log file, e.g.:
#   run_frida_watch.bat   ->   python frida_watch.py 80 > watch_dump.log
#
# Output lines:  "<ms> HH:MM:SS.mmm w <first 8 bytes hex>"  /  "open <path>"

import sys
import time

import frida

SECONDS = int(sys.argv[1]) if len(sys.argv) > 1 else 80

target = None
for p in frida.get_local_device().enumerate_processes():
    if p.name.lower() == "xkscreen.service.exe":
        target = p
        break
if target is None:
    print("service process not found")
    sys.exit(1)

print("attaching to %s (pid %d), watching %ds" % (target.name, target.pid, SECONDS))
session = frida.attach(target.pid)

script = session.create_script("""
var k32 = Module.load("kernel32.dll");
var t0 = Date.now();

var CreateFileA = k32.getExportByName("CreateFileA");
Interceptor.attach(CreateFileA, {
  onEnter: function (args) {
    try { this.p = args[0].readAnsiString() || ""; } catch (e) { this.p = ""; }
  },
  onLeave: function (ret) {
    if (this.p && this.p.indexOf("vid_0145") >= 0) {
      send({ k: "open", t: Date.now() - t0, p: this.p.substring(0, 80) });
    }
  }
});

var WriteFile = k32.getExportByName("WriteFile");
Interceptor.attach(WriteFile, {
  onEnter: function (args) {
    try {
      var n = args[2].toInt32();
      if (n === 65) {
        var b = new Uint8Array(args[1].readByteArray(8));
        send({ k: "w", t: Date.now() - t0, b: Array.prototype.slice.call(b) });
      }
    } catch (e) { }
  }
});
""")

stats = {"packets": 0, "opens": 0}


def on_message(msg, data):
    if msg.get("type") != "send":
        return
    p = msg["payload"]
    hh = time.strftime("%H:%M:%S", time.localtime())
    if p["k"] == "w":
        stats["packets"] += 1
        print("%7d %s.%03d w %s" % (p["t"], hh, p["t"] % 1000,
              " ".join("%02x" % x for x in p["b"])), flush=True)
    else:
        stats["opens"] += 1
        print("%7d %s open %s" % (p["t"], hh, p["p"]), flush=True)


script.on("message", on_message)
script.load()
time.sleep(SECONDS)
print("done: %d packets, %d opens" % (stats["packets"], stats["opens"]), flush=True)
