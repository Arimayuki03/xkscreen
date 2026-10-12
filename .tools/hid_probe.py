"""枚举全部 HID 设备，定位 XK003 屏（VID 0x0145 / PID 0x1001）并尝试读其能力。只读探测，不写。"""
import hid

for dev in hid.enumerate():
    if dev["vendor_id"] == 0x0145 or "XK" in str(dev.get("product_string", "")):
        print("== candidate ==")
        for k, v in dev.items():
            print(f"  {k}: {v!r}")

print("\n-- all HID devices --")
for dev in hid.enumerate():
    print(
        hex(dev["vendor_id"]),
        hex(dev["product_id"]),
        dev.get("usage_page"),
        hex(dev.get("usage") or 0),
        dev.get("path", b"")[:60],
    )
