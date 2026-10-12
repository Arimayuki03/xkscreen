"""确认两个根集线器的 UpperFilters —— 判断 USBPcap filter 是否只挂了其中一个。"""
import winreg

for name, path in (
    ("hub1(1416EA97)", r"SYSTEM\CurrentControlSet\Enum\USB\ROOT_HUB30\5&1416EA97&0&0"),
    ("hub2(2FD48294)", r"SYSTEM\CurrentControlSet\Enum\USB\ROOT_HUB30\4&2FD48294&0&0"),
):
    try:
        k = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, path)
        try:
            v, _ = winreg.QueryValueEx(k, "UpperFilters")
            print(name, "UpperFilters:", v)
        except FileNotFoundError:
            print(name, "UpperFilters: NONE")
        winreg.CloseKey(k)
    except OSError as e:
        print(name, "ERR", e)
