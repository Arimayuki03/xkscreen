"""对 XK003 屏做只读探测：打开 HID、读厂商/产品串、尝试阻塞读（3 秒超时）。
官方服务已停止，设备应空闲。不发送任何数据。"""
import hid
import time

PATH = (
    b"\\\\?\\HID#VID_0145&PID_1001#7&2a30b4ea&0&0000#"
    b"{4d1e55b2-f16f-11cf-88cb-001111000030}"
)

h = hid.device()
h.open_path(PATH)
print("opened:")
print("  manufacturer:", h.get_manufacturer_string())
print("  product     :", h.get_product_string())
print("  serial      :", h.get_serial_number_string())

h.set_nonblocking(False)
print("\n-- blocking read, 3s timeout --")
t0 = time.time()
data = h.read(64, timeout_ms=3000)
print(f"read {len(data)} bytes in {time.time()-t0:.1f}s:", bytes(data).hex(" ") if data else "(none)")

# 再试一次（有的设备需要先写才回包，这里只做两次被动读）
data = h.read(64, timeout_ms=3000)
print("second read:", bytes(data).hex(" ") if data else "(none)")

h.close()
print("done")
