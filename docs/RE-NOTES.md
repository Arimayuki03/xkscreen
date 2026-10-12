# 逆向证据笔记 — SystemTemperatureMonitoring V2.8

> 所有结论区分【观察】（反汇编/字符串直接证据）与【推断】（标注置信度）。
> 目标安装包 SHA-256: `ed71359a60e526e4c1f0b5ac36a37b3262f70022930e335a04cbc0e855aee661`

## 1. 安装包

- Inno Setup 6.4.0.1 固实安装包，PE32 x86 引导（观察）
- innoextract 1.9 不支持 6.4 数据格式；我们自写解包：
  - `zlb\x1a` @ 安装器偏移 0xCE400 → 标准 LZMA1（props 0x5D, dict 8MB）→ 59,092,032 字节数据流 `.tools/inno_hdr.bin`
  - 数据流内嵌 19 个 PE 文件，已雕刻至 `extracted/`（含 4 个误报，真实组件 15 个）
  - 约 50MB 高熵块（0x2EC38–0x300095A）为 Inno 6.4 新增逐文件压缩记录，未解开【已知缺口】

## 2. 组件清单（extracted/，原名 = PE 资源 FileDescription）

| 文件 | 架构 | 身份 |
|---|---|---|
| pe_030e1670.bin | x64 | SystemTemperatureMonitoring.exe — .NET 服务主程序（服务名 `XKWHardwareServices`）|
| pe_030e4470.bin | x64 | XKWLib.dll — .NET 通信库 |
| pe_030e9e70.bin | x64 | **HWCX** — 原生 HID 控制库（本项目核心目标）|
| pe_03004760.bin | x64 | HardwareHelp64.dll — 封装层 |
| pe_03101870 / pe_03457758 | x86/x64 | cpuidsdk.dll (CPUID SDK 1.3.4.7) |
| pe_00000000.bin | x86 | BoxStub.exe (Microsoft，Inno 组件) |
| pe_0301f560 / pe_030cd270 | x86 | Newtonsoft.Json 13.0.3 / System.Net.Http |
| 其余 8 个 | x86/x64 | 辅助 EXE/DLL（卸载辅助等，未深查）|

注：雕刻文件名 `pe_XXXXXXXX.bin` 为数据流内偏移；`TempComm.dll` 存在但本体在被加密的 50MB 块内，仅见到其导出表字符串与 HWCX 完全一致（同源）。

## 3. 通信链路（观察：.NET 用户字符串 + 导出表）

```
SystemTemperatureMonitoring.exe (.NET 服务, OnStart 启动线程)
   │  写注册表 HKLM\SYSTEM\CurrentControlSet\Services\XKWHardwareServices
   ▼
XKWLib.dll
   · UdpClient / UdpCommand / UdpUtil / IsUdp / localPort / defaultPort
   · 端口常量 7255 在 IL 中出现 5 次（观察，推断为默认 UDP 端口，置信度高）
   · config.ini 键: fefresh_delay, send_delay, IsLog, LogPath, IsUdp, localPort, rundata, staticdata
   · 发送内容字符串: "CPU 信息发送成功", "GPU 信息发送成功", "RAM...", "DISK...",
     "风扇信息发送成功,转速:{0}", "设置CPU温度:{0}", "设置GPU温度:{0}"
   · 协议串: "cmdNo:{0} cmd:{1} data:{2}", "{0}|{1}", "name:=", "CPUID"
   · 兼容机型串: ZALMAN-CTM / ZALMAN-TDM / SLAYERCPULiveTemperature / RM-Hardware /
     LK Digital Display / GTX / RTX / NVIDIA
   ▼
TempComm.dll / HWCX (导出表一致)
   ▼
USB HID 设备 (型号串 "XK003", HWCX .rdata)
```

UDP 用途【推断】：XKWLib 同时监听本机回环，供第三方（或 GUI）注入数据；核心数据可能直接函数调用不走 UDP。对自研软件不重要——我们直接调 HWCX。

## 4. HWCX 深度分析（pe_030e9e70.bin，imagebase 0x180000000）

### 4.1 导入（观察）
`HID.dll`: HidD_GetAttributes, HidD_GetHidGuid
`SETUPAPI.dll`: SetupDiGetClassDevsA, SetupDiEnumDeviceInterfaces, SetupDiGetDeviceInterfaceDetailA, SetupDiDestroyDeviceInfoList
`KERNEL32.dll`: CreateFileA, ReadFile, WriteFile, GetOverlappedResult, CancelIo, CreateEventA, CreateMutexA...
→ **纯用户态 HID 设备通信，无 .sys 内核驱动**（观察）

### 4.2 导出表（33 个，RVA 精确）

```
CheckOnlineDevice      0x17D4   DeviceOpen            0x1A44
DeviceClose            0x92B8   GetErrorCode          0x7CDC
GetNameAndVersion      0x21F8   GetOnlineDeviceQty    0x1A14
SetCheckUsb            0x1690   SetColor              0x20E8
SetColorEx             0x2170   SetCpuDynamicInfo     0x1AA0
SetCpuName             0x1BE4   SetCpuVoltage         0x1A58
SetCpuWatt             0x1A7C   SetDeviceTime         0x1DF4
SetDiskDynamicInfo     0x1BEC   SetDiskName           0x1BE4
SetDisplayMode         0x1B98   SetDisplayName        0x1BE4
SetFanRPM              0x1AF8   SetGpuDynamicInfo     0x1B18
SetGpuFanRPM           0x1B08   SetGpuName            0x1BE4
SetGpuVoltage          0x1B50   SetGpuWatt            0x1B74
SetMbDynamicInfo       0x1BE4   SetMbName             0x1BE4
SetMemDynamicInfo      0x1BAC   SetMemName            0x1BE4
SetNetSpeed            0x1C08   SetOsInfo             0x1BE4
SetOtherFanRPM         0x1AE8   SetWaterFanRPM        0x1AD8
```
（多个 Set*Name/SetOsInfo 共享同一转发体 0x1BE4，内部按名字分发或共享参数布局）

### 4.3 关键函数反汇编（capstone，观察）

**DeviceOpen @0x1A44**：仅 `call 0x2621; ret 1`。0x2621 内部：`CreateEvent`+`CreateMutex`、按路径 `CreateFileA` 读写句柄（+0x40000080 权限）存入设备结构 +0x118/+0x120/+0x128。

**设备枚举器 @0x1C2F**（参数 idx）：
- 设备结构 0x288 字节/个，最多 15 个（`cmp edi,0xF`）
- 每设备初始两个 1500ms 字段：`[+0x210]=0x5DC, [+0x20C]=0x5DC`
- 关键比对：`mov edx,[dev+0x21C]; cmp edx,0x3E3; je ...` — 0x3E3=995。来自 HID attributes 填充【推断：PID 或 VID 之一，运行时写入，静态图为 0，Phase 0 实测定论】
- 枚举循环尾部 `jmp 0x2D4A` 进入一段混淆/虚拟化代码（xor 0x34/0xAA/0x11 等常量参与报文混淆与校验）

**SetColor @0x20E8**（观察，完整）：
```
mov edi, ecx            ; arg1 = 设备索引
mov rbx, rdx            ; arg2 = 指向 RGBA 的指针
call 0x2512             ; 取互斥锁
lea rcx,[rsp+0x20]; mov edx,0xFF; mov r8d,0x40; call memset   ; 64B 清 0xFF? (edx=0xFF 值)
mov al,[rbx]   → [rsp+0x21]   ; R
mov al,[rbx+1] → [rsp+0x22]   ; G
byte [rsp+0x20] = 5           ; 报文[0]=命令号 0x05
mov al,[rbx+2] → [rsp+0x23]   ; B
mov al,[rbx+3] → [rsp+0x24]   ; A
call 0x327F                    ; 加密+发送+等待应答
```
→ HID 输出/特征报告 64 字节，`[0]=0x05` 为"设置颜色"命令号，[1..4]=RGBA。HWCX 会等待设备应答并重试（日志串 `-------retry!!!!-------E:%d, %d, C:%u`）。

**SetDisplayMode @0x1B98**（观察）：`(int idx?) ecx, edx=mode`；`mode==0 → or dl,0x80`，结果存全局字节。即 mode 位图，0x80 位有特殊含义【推断：横竖屏或亮度位】。

**单值 setter 群 @0x1A58-0x1B41**（观察，全部写 16 位全局，供枚举器组包时引用）：
- 0x1A58 (SetCpuVoltage): `val = p[1]*256 + p[2]` → 全局 0x1AAE8
- 0x1A7C (SetCpuWatt):   `val = p[1]*256 + p[2]` → 0x1AAEA
- 0x1AA0 (SetCpuDynamicInfo): `g[0x1AAE0]=p[1]`, `g[0x1AAE2]=p[3]*256+p[2]`, `g[0x1AAE4]=p[0]`
- 0x1AD8 (SetWaterFanRPM): `g[0x1AAEC]=cx`
- 0x1AE8 (SetOtherFanRPM): `g[0x1AAEE]=cx`
- 0x1AF8 (SetFanRPM): `g[0x1AAF6]=cx`（0x1AAE4+0x12 推算）
- 0x1B50/0x1B74 (GpuVoltage/Watt): 同 CPU 模式 → 0x1AAxx
- 0x1B98 前的 0x1BAC/0x1BEC 为多字节 setter（结构体展开）
- 参数指针 p 指向的字节串即"迷你结构"：`[0]=类型/槽位, [1]=高字节, [2]=低字节`【推断，具体语义待抓包】

**发送器 @0x327F**：报文先与 0xAA/0x11、0x34 及计数值做 xor 校验（观察），随后 WriteFile 到 HID 句柄；等待应答逐字节校验非 0。

### 4.4 日志与配置（观察）
- `GetPrivateProfileStringA` + 节名 `config`、`debug`；文件 `config.ini`、`debug.txt`（相对 exe 目录）
- 日志格式：`[%02d:%02d:%02d] `、`Send info fail = E:%d, %d, C:%d`、`SetTime = %u`、`SetColor`
- XKWLib 键名 `IsLog` 开日志【推断】

## 5. 实机验证结果（2026-10-12）

### 5.1 设备确认（观察，Get-PnpDevice）
- 屏幕在本机枚举为 **`USB\VID_0145&PID_1001`**（两个接口：USB 输入设备 + HID-compliant device，Status OK）
- VID/PID 与 XKWLib.dll IL 中的支持设备表完全吻合（`ldc.i4 0x1001; ldc.i4 0x145` 成对出现）：
  - (PID=0x1001, VID=0x0145)、(0x12B7, 0x0145)、(0x1005, 0x0145)、(0x1001, 0x2C65)、(0x1000, 0x2C65)
  - (0x3ED1/0x4B8F/0x3A7F/0x3ED2/0x3ED6, 0x1C57)
- HWCX 内 `cmp edx,0x3E3`【已降级为无关紧要：0x3E3 不在支持表内，疑为内部类型码，不再是 VID/PID】

### 5.2 雕刻版 vs 官方版 TempComm（已解决，2026-10-12）
- 流内雕刻版（`pe_030e9e70.bin`）与官方安装的 `TempComm.dll`（96,768B）**大小相同、导出表相同（32 项）、CheckSum/时间戳相同，但代码字节不同**（1,294 个差异区、4,082 字节）——同源工程两次构建
- 雕刻版 `LoadLibrary` 即 AV（DllMain 阶段）；**官方版独立加载正常**，`GetOnlineDeviceQty()` 返回 0
- 处置：demo 改用官方 `official/TempComm.dll`（重命名 HWCX.dll 加载）。**Inno 流内那份是不可用构建，弃用**
- 附带：官方安装目录实测只装 6 个文件（exe/XKWLib/TempComm/HardwareHelp64/cpuidsdk×2/Newtonsoft.Json/System.Net.Http），**无 .sys**——确认无内核组件参与屏幕控制

### 5.4 官方服务实测（观察）
- 服务名实际为 **`SystemTemperatureMonitoring`**（非 XKWHardwareServices——后者是 .NET 代码里的安装器字符串），自动启动，PID 存在
- `log.txt` 记录延迟启动逻辑（等待约 30 秒后"开始启动"）
- config.ini 实际值：`fefresh_delay=500, send_delay=500, IsLog=False, localPort=8890, IsUdp=True`——**UDP 端口运行时为 8890，非代码默认 7255**
- 官方服务运行时，demo `SetColor` 仍返回成功（两者未抢句柄失败，但颜色归属无法视觉判定）；严谨验证前应先停官方服务

### 5.3 调用约定修正（观察，重要）
- `DeviceOpen`(0x1A44) 不是无参函数：它转发到 0x2621 `(rcx=设备结构, edx=槽位)`，**无参调用必崩**。公开的"枚举+填表"入口是 `CheckOnlineDevice`(0x17D4)（含互斥等待 → 0x1C28 枚举准备 → SetupDi 流程 → 写设备表）
- `GetOnlineDeviceQty`(0x1A14) 是纯设备表(基址 0x1AB40，步长 0x288)扫描，无副作用
- `SetColor(idx, rgba)`：报文 64B、`[0]=0x05`、`[1..4]=R,G,B,A`，缓冲 memset 0xFF（非 0），发送前取内部互斥


## 6. 结论（更新）

1. 无内核驱动，控制屏幕 = 65 字节 HID 报文（TempComm 用户态封装）
2. VID=0x0145 / PID=0x1001 已实机确认
3. Phase 1 已打通；最终协议见 §7（frida 截获金标准）
4. Inno 流内的 TempComm 是坏构建，正式开发一律用官方安装目录版本
5. 屏幕无掉电保持，需 ~500ms 周期重发（握手+颜色）

## 7. 最终可用方案（2026-10-12 实机验证 ✅）

### 7.0 重要更正：裸报文回放【不可行】

此前尝试用 frida 截获的"握手包+颜色包"直接 hidapi 回放，**实测无法点亮屏幕**（多轮重放、官方节奏重放、纯色注入均无效）。
结论：屏幕点亮依赖 XKWLib 完整流程（设备注册 → 打开 → 内部线程握手/组包周期发送），
单独回放抽样报文不足以驱动屏幕。原第 7 节协议分析保留作参考，但**不作为控制方案**。

### 7.1 最终方案：调用官方 XKWLib 完整链路（PowerShell 驱动）

```
PowerShell (管理员/SYSTEM)
  → LoadFrom XKWLib.dll
  → XKWLib.DllWrapper.SetCheckUsb(vidpidBytes, 2, 20)   # 注册 VID_0145/PID_1001
  → New-Object XKWLib.XKWLibHelp
  → .Start('SystemTemperatureMonitoring')               # 内部完成：
        PIDVIDHelp.SetCheckUsb → CPUIDHardware.Start()（读 CPU/GPU 数据）
        → OpenRefresh(1000) → 启动内部发送线程
  → 循环 .SendDynamicDataNew()（300ms）作为保底补帧
```

关键点：
- **必须管理员权限**：CPUID SDK（cpuidsdk64.dll + uiomap 驱动）读硬件需要管理员；非管理员能点亮但
  **只有时间、无 CPU/GPU 数据**（实测现象，已定位）
- `SendDynamicDataNew()` 每轮发送：时间、GPU 动态信息（占用/温度/频率）、GPU 风扇、
  CPU 动态信息（占用/温度/频率）、CPU 功耗/电压、网速、内存、硬盘、风扇
- 屏幕固件主题只渲染：**上圆环 CPU（占用%+温度℃）、中间时钟、下圆环 GPU（占用%+温度℃）**
  ——与官方软件显示完全一致（用户实机对照确认）；内存/网速/硬盘/风扇数据被发送但该主题不渲染

### 7.2 部署（常驻 + 开机自启）

- 驱动脚本：`.tools/xkw_driver_loop.ps1`（Start + 保活循环，30 次重试，日志 `official/driver_loop.log`）
- 开机自启：计划任务 `XKScreenDriver`（ONSTART，SYSTEM，RL HIGHEST，隐藏窗口）
- 官方服务 `SystemTemperatureMonitoring` 已改 **DEMAND_START（手动）**，避免与我们的驱动抢屏
- 停用我们的驱动：`schtasks /End /TN XKScreenDriver` + 杀 xkw_driver_loop 进程
- 恢复官方驱动：`sc config SystemTemperatureMonitoring start= auto` 并重启服务

### 7.3 截图证据（2026-10-12 23:0x）

实机照片确认：CPU 环 13%/49℃、时钟 22:51、GPU 环 2%/45℃——与官方软件显示一致。

### 7.4 方法论记录

抓包驱动(USBPcap)与纯静态逆向均受阻后，最终突破口是【反射调用官方 .NET 库 XKWLib】：
ilspycmd 反编译 XKWLib/HardwareHelp64 得到完整数据流（SendDynamicDataNew → DllWrapper.Set*），
PowerShell 5.1（.NET Framework）直接加载 net45 程序集驱动屏幕成功。

## 8. 能力边界实测（2026-10-13，A ✅ / B ❌ / C ❌）

三合一实验（停我们的驱动 → 实验进程接管屏幕 → 自动恢复驱动），
脚本：`.tools/run_experiment.bat [A|B|C]`（单项可重跑）+ `.tools/xkw_experiment.ps1`，
日志：`official/experiment_run1.log`、`experiment_run2.log`。用户目视确认为准。

- **A 数值注入 ✅ 可行**：每 300ms 循环 `SetCpuDynamicInfo/SetGpuDynamicInfo(自定义 8 字节) + SetDeviceTime(作 flusher)`
  实测两个环冻结于注入值（CPU 77%/88℃、GPU 44%/55℃）。**环内数字完全可编程**
- **B SetColor ❌ 无效**：红/绿/蓝各 8 秒，调用全部 ret=1 但屏幕颜色无任何变化。
  与 frida 证据一致：官方显示流从不含 0x05 颜色包（只有我们手动调用才会发出）。该屏固件不响应颜色命令
- **C SetDisplayMode ❌ 无效**：模式字节 1/2/3 各 8 秒（中间恢复 0），屏幕布局无任何变化。
  该字节虽随 SetDeviceTime 包持续下发，此屏固件不使用

**结论 —— 屏幕可编程范围**：

| 维度 | 可控制性 |
|---|---|
| 两个环的数字（每环：负载%位 + 温度℃位） | ✅ 完全自定义 |
| 时钟 | ✅ 随 SetDeviceTime 下发（可偏移） |
| 布局（CPU环/时钟/GPU环 三区） | ❌ 固件固定 |
| 配色（彩虹渐变） | ❌ 固件固定，无颜色命令 |
| 其他页面/文本 | ❌ 未发现入口（无响应） |

**落地实现**：常驻驱动内置环数据覆盖 —— `official/ring_cpu.txt` / `ring_gpu.txt`，
驱动每 300ms 周期读取并覆盖对应环；任何脚本写这两个文件即可向屏幕推送数字（文件持久 → 重启后仍生效）。

文件内容三种形式（两槽以逗号分隔）：
1. `auto` —— 真实数据（官方行为；整个文件仅 auto 时不做覆盖）
2. `NN,MM` —— 固定数字（0-255），如 `33,22`
3. `SRC1,SRC2` —— 数据源映射，可用源（2026-10-13 实机验证全部可用）：

| 源 | 含义 | 换算（**每格最多 2 位数字 → 一律截断到 0-99**） |
|---|---|---|
| cpu_load / cpu_temp | CPU 平均占用% / 最高核心温度℃ | 原值 |
| cpu_clock | CPU 最高核心频率 | GHz×10（52=5.2GHz） |
| cpu_watt | 封装功耗 W | 原值（截 99） |
| cpu_watt10 | 封装功耗 W | **÷10（15=150W，>99W 用这个）** |
| cpu_volt | 电压 V | ×10（12=1.2V） |
| gpu_load / gpu_temp / gpu_clock | GPU 同理 | 同上 |
| gpu_fan / fan_rpm | GPU 风扇 / CPU 风扇转速 | ÷100（21=2100RPM）；风扇扫描所有项取非零 |
| mem_pct / mem_used_gb | 内存占用% / 已用 GB | 原值（实测对照 47.6≈47）/ 原值（SDK 字段已是 GB） |
| net_down / net_up | 网络 下载/上传 | **自研高精度采样**：全网卡字节差 ÷ 0.5s 窗口 ÷1048576（MB/s），比 SDK 的 1s 平均更准更跟手 |
| net_down_x10 / net_up_x10 | 网络 下载/上传 | ×10（12=1.2MB/s，轻负载用这两个） |
| hdd_load | 硬盘活动 % | 原值 |

数据来源：反射 `hardware.SystemData.GetSystemRunData(DataType.X)`（CPU/GPU/Ram/Network/Fan/HHD），
键名 `load/temperature/clock/fan`、`ReceivedPerSec/SentPerSec`、`Memory Used/Available`、`speed`、`powers/voltage`。

**时钟控制**（2026-10-13 实机验证：E 轮实验目视确认 + 驱动自测）：
`official/time.txt` 内容 `auto`（默认，跟随系统）/ `+N` `-N`（与系统时间偏移 N 分钟，正常走动）/
`HH:MM`（固定冻结）。驱动每周期用该时间重发 SetDeviceTime 帧（覆盖 XKWLib 的真实时间帧）。
实验证据：12:34 冻结 ✅、04:00 每分钟快进（+1min/s）✅、+1h 正常走动（整点进位）✅；
驱动自测日志 `ring values time=05:13`（+120，真实 03:13）。

**计时器（2026-10-13，C# 服务已实现）**：config.json `time` 字段新增：
`timer`（秒表正计时）/ `timer_down:MM:SS`（倒计时到 00:00 保持）+ `HH:MM` 放宽到小时位 0-99。
实现原理：把"分钟"填到时间帧的 hour 槽、"秒"填到 minute 槽 → 屏幕 4 个数字位呈现 MM:SS。
服务日志证据：P1 `show=45:30`、P2 `show=00:00→00:25`、P3 `show=00:30→00:00`（目视确认待补）。

**踩坑记录 1**：PowerShell 函数返回 `IEnumerable` 对象（如 DataItem）时会被自动展开成数组、
丢失 `Size`/索引器 → 读传感器永远为空。必须 `return ,$r` 用一元逗号包装。
**踩坑记录 2**：CPU 数据里 `packge`（封装）条目**同时含** load/temperature/clock（官方从所有条目读取），
不能跳过它，否则温度/频率为 0。
**踩坑记录 3**：实验编排 bat 若含中文，cmd 解析会因 UTF-8/chcp 字节错位把命令行拆坏
（表现为 `'n-Drive' 不是内部或外部命令`），导致启动命令被跳过 —— 编排类 .bat 一律保持纯 ASCII。
**踩坑记录 4（最阴险）**：PowerShell 5.1 读取**无 BOM 的 UTF-8 脚本**时按 ANSI/GBK 解码，
某些中文注释的字节序列会**吞掉行尾换行**，把下一行代码并入注释（实测 `$timeFile` 赋值行被
上一行中文注释吞掉 → 时间功能静默失效、无任何报错，脚本语法检查还通过）。
诊断方法：`Parser::ParseFile` 后用 AST 统计目标赋值语句数量；或按 GBK 解码逐行对比。
**结论：.ps1/.bat 脚本一律纯 ASCII（已在驱动 v3.1 全量整改）。**
**踩坑记录 5（产品代码，C#）**：`JavaScriptSerializer.Deserialize<Dictionary<string,object>>`（泛型重载）
把 JSON 数组转成 **`ArrayList`**（而 `DeserializeObject` 转成 `object[]`），`as object[]` 静默失败
→ 配置永远回退默认值（现象与"配置没生效"完全一样）。修复：用 `IList` 接收（两种类型都兼容）。
**踩坑记录 6（测试脚本）**：cmd 批处理里 `->` 的 `>` 会被当成**重定向符**（横幅文字被写进了
垃圾文件、拖累下一行）；且 `echo {...} > file` 写 JSON 受逗号/引号解析怪癖影响不可靠 ——
配置类文件一律用"预置 JSON 文件 + copy"的方式下发。
**踩坑记录 7（Windows 任务计划）**：重指向计划任务时 `schtasks /create` 与 `Register-ScheduledTask`
同时报"未指定的错误"/0x80004005 —— 属**瞬时故障**（约 25 分钟后同一条命令一次成功）；但当时
"先删旧、再建新"的流程已把旧任务删掉，造成开机自启短暂缺失。经验：修改任务用"先建新的、
验证成功、再处理旧的"，并备好三重兜底脚本 `.tools/fix_autostart.bat`
（schtasks 经典 / Register+ServiceAccount / XML 导入）。管理员创建的任务 ACL 仅授予
管理员与 SYSTEM —— 非提权查询报"拒绝访问/找不到"属正常现象。

### 8.1 D 轮深挖（2026-10-13，用户目视：全部无变化）

- **D1 温度位边界值 0 / 255**：环上数字正常显示，但 **℃ 符号仍固定渲染**（无条件显示，无法隐藏）
- **D2 SetColorEx**（0x05 命令 + 第 6 字节 extra=0..3，红色）：**无任何颜色效果**（全部 ret=1）
- **D3 显示模式字节变体** 0x80/0x81/0x82/0x83/4/5：**无任何布局效果**（全部 ret=1）
- **名称/文字通道**：全部 8 个文字类导出（SetCpuName/SetGpuName/SetMemName/SetDiskName/SetMbName/
  SetDisplayName/SetOsInfo/SetMbDynamicInfo）在**两份构建**（官方 + 安装包雕刻版）中均为空壳
  （`mov eax,1; ret`），官方软件亦从不调用 → 屏幕上的 CPU/GPU 等文字为固件主题固定
- 日志：`official/experiment_run3_D.log`（D 轮），`experiment_run1/2.log`（A/B/C 轮）

**最终能力边界（定版）**：可编程 = **两环数字（完全自定义）+ 时间**；
其余（布局 / 配色 / 显示模式 / 文字标签 / 单位符号）全部为屏幕固件固定。
唯一未探索项："命令号盲扫"（0x00-0xFF 逐个试探）——概率低且存在把屏幕切进未知状态的风险，暂不执行。



