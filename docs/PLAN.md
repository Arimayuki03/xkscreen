# Xingcan Xiaolan Drive — 屏幕控制软件开发计划

> 目标：不依赖原厂"驱动"（实为 Windows 服务 + DLL），用自研软件控制 XK003 USB HID 硬件监视屏。
> 路线：路线 1 —— P/Invoke 调用 HWCX.dll 导出函数（详见 [RE-NOTES.md](RE-NOTES.md) 逆向证据）。
> 前提：原服务 `XKWHardwareServices` 已卸载；屏幕为标准 USB HID 设备，无需内核驱动。

## 架构总览

```
┌─────────────────────────────┐
│  我们的控制程序 (C# / .NET 8) │
│  ├─ 数据采集层  LibreHardwareMonitor (CPU/GPU/RAM/盘/风扇/网卡)
│  ├─ 控制层      HwcxClient — P/Invoke HWCX.dll 的 33 个导出函数
│  └─ UI/CLI      demo 控制台 → 以后可挂托盘/网页
└──────────┬──────────────────┘
           │ CreateFile(\\?\HID#...) + WriteFile (HWCX 内部完成)
           ▼
   XK003 USB HID 屏幕 (64 字节报告协议)
```

原厂链路（对照）：服务 `SystemTemperatureMonitoring.exe` → XKWLib.dll（UDP 127.0.0.1:7255）→ TempComm.dll/HWCX → HID。我们跳过前两层，直接用最底层。

## 阶段划分

### Phase 0 — 设备侦察（已完成 2026-10-12）
- [x] 屏幕设备确认：**`USB\VID_0145&PID_1001`**（HIDClass，Status OK，与 XKWLib IL 支持表吻合）
- [x] VID/PID 归属定论：XKWLib IL 中 `ldc.i4 0x1001; ldc.i4 0x145` 成对 → PID=0x1001, VID=0x0145
- [x] demo 工程就位（src/XkScreen，构建通过）

### Phase 1 — 通路验证（✅ 已完成，协议全解）
- [x] 设备确认：`USB\VID_0145&PID_1001`，HIDClass，Status OK
- [x] 调用约定修正：**禁止直接调 DeviceOpen**；入口为 CheckOnlineDevice → GetOnlineDeviceQty → Set*
- [x] **阻塞解决**：Inno 流内雕刻的 TempComm.dll 是坏构建（DllMain AV）；官方安装目录的 TempComm.dll（同尺寸同导出表但代码不同）加载正常
- [x] 实机验证：`CheckOnlineDevice→1`、`GetOnlineDeviceQty→1`、`SetColor(0, R/G/B/A)→1` 连续设置红/绿/蓝/紫成功
- [x] demo 改用 `official/TempComm.dll`（构建时复制为 HWCX.dll）
- [x] **协议金标准（frida 截获）**：见 RE-NOTES §7 —— 握手包 + 颜色包（FF 填充），500ms 周期
- [x] **点屏成功**：screen_on.py 常亮验证（橙/天蓝）

### Phase 1.5 — 最终方案（✅ 已上线，2026-10-12）
- **结论更正**：裸 HID 报文回放不可行（屏幕点亮依赖完整 XKWLib 流程）
- ✅ 最终驱动：`.tools/xkw_driver_loop.ps1` —— PowerShell 加载官方 XKWLib，调
  `XKWLibHelp.Start('SystemTemperatureMonitoring')`（内部完成设备注册/硬件采集/发送线程），
  循环 `SendDynamicDataNew()` 保活补帧
- ✅ **必须管理员/SYSTEM 权限**（CPUID SDK 读硬件依赖驱动访问；普通权限只有时间无 CPU/GPU）
- ✅ 开机自启：计划任务 `XKScreenDriver`（ONSTART / SYSTEM / HIGHEST）
- ✅ 官方服务已改手动启动（DEMAND_START），避免抢屏
- ✅ 实机验收：CPU 环（占用+温度）、时钟、GPU 环（占用+温度）与官方显示一致
- 屏幕显示布局为**固件主题固定**：仅 CPU 环 / 时钟 / GPU 环三区；协议还发送
  内存/网速/硬盘/风扇，但该主题不渲染（官方软件同样如此）

### Phase 1.6 — 能力边界实测（✅ 已完成 2026-10-13）
- [x] A 数值注入可行：两环数字完全可编程（77/88℃、44/55℃ 冻结，用户目视确认）
- [x] B SetColor 无效（该屏固件不响应 0x05 颜色命令）
- [x] C SetDisplayMode 无效（模式字节 1/2/3 无任何效果）
- [x] D 深挖（用户目视全无变化）：℃ 边界值 0/255 不隐藏符号；SetColorEx 变体无效；
      mode 0x80~0x83/4/5 无效；文字类导出全为空壳（官方+雕刻版一致）
- **能力边界定版**：可编程 = 两环数值 + 时间；布局/配色/文字/符号全部固件固定（详见 RE-NOTES §8）
- 工具：`.tools/run_experiment.bat [A|B|C|D]` 单项重跑

### Phase 1.7 — 环数据源映射 + 时钟控制（✅ 已完成 2026-10-13）
- 驱动 v3.1（`.tools/xkw_driver_loop.ps1`）支持 `ring_cpu.txt`/`ring_gpu.txt`：
  `auto` / `NN,MM`（固定数字）/ `SRC1,SRC2`（数据源，如 `mem_pct,cpu_temp`）
- 13 个数据源全部实机验证：cpu/gpu 的 load/temp/clock/watt/volt/fan、mem_pct、net_up/down、fan_rpm、hdd_load
- 验证证据：日志 `ring values gpu=[47,58]` 与系统实测内存 47.6% 精确吻合
- [x] **时钟控制**：`time.txt` = `auto` / `+N`/`-N`（分钟偏移）/ `HH:MM`（冻结）；
  E 轮目视确认（12:34 冻结 / 每分钟快进 / +1h 走动）+ 驱动自测 `ring values time=05:13`（+120）
- [x] 驱动暂停 XKWLib 内部发送线程（独占每帧，消除覆盖数据被真实帧抢帧）
- [x] 修复 GBK 吞行 bug：中文注释在 PS5.1 无 BOM UTF-8 下吞掉下一行（`$timeFile` 赋值失效）→ 驱动脚本改纯 ASCII
- [x] D 轮深挖已完成（2026-10-13）：℃ 符号不可隐藏、SetColorEx 无效、mode 变体无效 → 边界定版

### Phase 2 — 参数结构逆向（静态 + 抓包，2-3 天）
**目的**：搞清每个 Set* 函数的入参布局。x64 调用约定：RCX/RDX/R8/R9。

已知（反汇编确认）：
- `SetColor(int deviceIndex, byte* rgba)`：64 字节缓冲 `[0]=0x05`(命令号)，`[1]=R [2]=G [3]=B [4]=A`
- `SetDisplayMode(int idx, int mode)`：mode=0 时内部 `or dl,0x80` → 存全局；非 0 原样存
- 多值函数如 `SetCpuDynamicInfo(char* p)`：按 `[p+1]*256+[p+2]`、`[p]` 等拆包写多个 16 位全局（见 RE-NOTES 0x1AA0）
- 帧率：枚举函数里对每设备写 `0x5DC`（1500ms）两个超时字段

待逆向（每个约 30-60 分钟，capstone 反汇编 + 对照抓包）：
- [ ] `SetCpuName/SetGpuName/SetMemName/SetDiskName/SetMbName/SetDisplayName` — 猜测 `(idx, char* text)`
- [ ] `SetCpuDynamicInfo/SetGpuDynamicInfo/...` — 结构体字段（温度/频率/负载/电压/功耗）
- [ ] `SetFanRPM/SetWaterFanRPM/SetOtherFanRPM/SetGpuFanRPM/SetNetSpeed`
- [ ] `SetDeviceTime/SetOsInfo/GetNameAndVersion`
- [ ] `SetColorEx` 与 `SetColor` 的差异

方法：优先静态（capstone 脚本批量反汇编导出函数 + 参数寄存器跟踪）；不确定的字段用"抓包对照"——原装软件已卸载，可临时装回跑一次 USBPcap 抓 HID 流量，或直接用我们的 demo 逐字段改值看屏幕变化（黑盒二分，屏幕本身就是显示器，反馈最直观）。

**产出**：更新 RE-NOTES.md 的函数签名表；形成 `HwcxClient` 全量签名。

### Phase 3 — 封装库 + 完整 Demo（2 天）
- [ ] `HwcxClient`（SafeHandle 管理 DeviceOpen/Close，互斥保护——HWCX 内部已有 CreateMutexA）
- [ ] 主题类 `ScreenTheme`：CPU/GPU/RAM/DISK 页面渲染（调 SetXxxName + SetXxxDynamicInfo）
- [ ] CLI demo：`xkscreen set-color FF8800`、`xkscreen set-cpu 65C 4.2GHz 30%`、`xkscreen mode 1`
- [ ] 异常恢复：设备拔插监听（WM_DEVICECHANGE 或轮询 CheckOnlineDevice）

**验收**：屏幕稳定显示我们发送的颜色/文本/数据 ≥1 小时无断连。

### Phase 4 — 数据采集 + 常驻（2-3 天）
- [ ] 集成 LibreHardwareMonitor（NuGet `LibreHardwareMonitorLib`）替代 cpuidsdk：CPU 温度/电压/功耗、GPU、风扇、内存、磁盘、网速
- [ ] 刷新循环 1500ms（对齐 HWCX 默认超时 0x5DC）
- [ ] 开机自启（计划任务/服务，二选一）；崩溃自动重启
- [ ] 配置文件：主题、刷新率、日志开关

### Phase 5（可选）— 协议级重写
用 hidapi 直接收发 64 字节报告，摆脱 HWCX.dll 依赖（跨平台、可控性最强）。以 Phase 2 抓包得到的命令表为准：已知 `0x05=颜色`。仅当需要 HWCX 没有的能力时再做。

## 风险与备忘

| 风险 | 缓解 |
|---|---|
| HWCX 有 15 设备上限循环（`cmp edi,0xF`）与 0x288 字节/设备结构，多屏场景未知 | 单屏不受影响 |
| HWCX 雕刻版 LoadLibrary 崩（DllMain 阶段，疑 TempComm 依赖） | 官方目录文件 diff/替换（Phase 1 阻塞项）|
| HWCX 内部线程 + 事件 + 重试（"-------retry!!!!-------"），线程安全边界未知 | 所有调用走我们自己的串行队列 |
| 原服务卸载但驱动过滤残留可能截获 HID | 设备管理器确认无残留服务；必要时 `pnputil` 清理 |
| TempComm.dll 未完整解出（Inno 6.4 新格式 50MB 块） | 重装官方软件后从安装目录直接取 DLL |

## 关键证据索引（详见 RE-NOTES.md）

- 屏幕：`USB\VID_0145&PID_1001`（实机确认）；型号串 `XK003`（HWCX .rdata）
- 通信端口：UDP 7255（XKWLib 层）；HWCX：HID + SetupAPI，64 字节报文，`[0]=0x05`=颜色命令
- 服务名：`XKWHardwareServices`；产品 `RM-Hardware`、`LK Digital Display`、`ZALMAN-CTM/TDM`
- 调用禁令：`DeviceOpen` 不可无参调用；入口应为 `CheckOnlineDevice`
