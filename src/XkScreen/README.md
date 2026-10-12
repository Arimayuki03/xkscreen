# XK003 屏幕控制 Demo — Phase 1

> 通路验证：P/Invoke `HWCX.dll` → `CheckOnlineDevice`（枚举+填设备表）→ `GetOnlineDeviceQty` → `SetColor`。
> HWCX.dll 为 x64 原生库，必须以 x64 运行。**禁止直接调用 DeviceOpen**（RE-NOTES §5.3）。

## 文件

- `HWCX.dll` — 从 `extracted/pe_030e9e70.bin` 复制改名而来（构建事件自动完成）
- `Program.cs` — 最小验证程序（含 30s 看门狗与 config.ini 日志开关）
- `.csproj` — .NET 8, x64, AllowUnsafeBlocks

## 运行

```powershell
dotnet run -c Release -- FF8800
```

## 预期输出（成功）

```
[1/3] CheckOnlineDevice（枚举并填设备表）... 1
[2/3] GetOnlineDeviceQty... 1
[3/3] SetColor #FF8800 (device 0)... 1
DONE
```

## 排错

| 现象 | 处置 |
|---|---|
| `DllNotFoundException` | 32/64 位不匹配（必须 x64）或缺 VC++ 运行库（`vc_redist.x64`）|
| LoadLibrary 即崩（segfault） | **当前已知阻塞**：DllMain 初始化阶段 AV，疑缺 TempComm.dll 同目录依赖 → 按 PLAN.md Phase 1 用官方安装目录文件 diff/替换 |
| `CheckOnlineDevice` 卡住 | 30s 看门狗会提示；确认屏幕在线（`HID\VID_0145&PID_1001`）|
| `SetColor` 返回 0 | 查 `debug.txt`（HWCX 自带日志）与 `GetErrorCode()` |
