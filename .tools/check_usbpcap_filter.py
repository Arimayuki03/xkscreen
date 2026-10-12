"""检查 USBPcap filter 是否挂载：枚举注册表里所有 UpperFilters 含 USBPcap 的类。"""
import winreg


def walk(path, depth=0):
    if depth > 4:
        return
    try:
        key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, path)
    except OSError:
        return
    try:
        i = 0
        while True:
            sub = winreg.EnumKey(key, i)
            i += 1
            child = path + "\\" + sub
            try:
                k = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, child)
                filters, t = winreg.QueryValueEx(k, "UpperFilters")
                if any("USBPcap" in str(f) for f in filters if isinstance(f, str)):
                    print("HIT:", child, filters)
                winreg.CloseKey(k)
            except (OSError, FileNotFoundError):
                pass
            walk(child, depth + 1)
    except OSError:
        pass
    finally:
        winreg.CloseKey(key)


print("scanning UpperFilters for USBPcap...")
walk(r"SYSTEM\CurrentControlSet\Enum")
walk(r"SYSTEM\CurrentControlSet\Control\Class")
print("scan done")
