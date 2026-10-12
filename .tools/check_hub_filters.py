"""检查两个根集线器和 USB 类的 UpperFilters 注册表值。"""
import os
import winreg

SEP = chr(92)
for hub in (
    r"SYSTEM\CurrentControlSet\Enum\USB\ROOT_HUB30\5&1416EA97&0&0",
    r"SYSTEM\CurrentControlSet\Enum\USB\ROOT_HUB30\4&2FD48294&0&0",
):
    try:
        k = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, hub)
        leaf = hub.split(SEP)[-1]
        try:
            v, _ = winreg.QueryValueEx(k, "UpperFilters")
            print(leaf, "UpperFilters:", v)
        except FileNotFoundError:
            print(leaf, "no UpperFilters")
        winreg.CloseKey(k)
    except OSError as e:
        print("ERR", e)

k = winreg.OpenKey(
    winreg.HKEY_LOCAL_MACHINE,
    r"SYSTEM\CurrentControlSet\Control\Class\{36fc9e60-c465-11cf-8056-444553540000}",
)
print("class USB UpperFilters:", winreg.QueryValueEx(k, "UpperFilters")[0])
