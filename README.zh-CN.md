<div align="center">
  <img src="docs/images/icon.png" width="96" alt="XkScreen 图标"/>
  <h1>XkScreen</h1>
  <p><b>星灿 / XK003 机箱小屏的开源控制套件</b><br/>
  把<i>任意</i>传感器数据放进小屏的 CPU/GPU 圆环和时钟区 —— 配一个现代化的网页控制台。</p>
</div>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6?logo=windows11&logoColor=white"/>
  <img alt=".NET Framework" src="https://img.shields.io/badge/.NET%20Framework-4.8-512BD4?logo=dotnet&logoColor=white"/>
  <img alt="Next.js" src="https://img.shields.io/badge/Next.js-16-000000?logo=nextdotjs&logoColor=white"/>
  <img alt="WebView2" src="https://img.shields.io/badge/UI-WebView2-0A84FF?logo=microsoftedge&logoColor=white"/>
  <img alt="License" src="https://img.shields.io/github/license/Arimayuki03/xkscreen"/>
  <img alt="Release" src="https://img.shields.io/github/v/release/Arimayuki03/xkscreen"/>
  <img alt="Stars" src="https://img.shields.io/github/stars/Arimayuki03/xkscreen"/>
</p>

<p align="center"><a href="README.md">English</a> | <b>简体中文</b></p>

![控制台界面截图](docs/images/screenshot.png)

## ✨ 功能特性

- **圆环显示任意数据** —— 四个数字位（CPU 环上/下格、GPU 环上/下格）可映射到 **19 种实时数据源**：CPU/GPU 占用、温度、频率、功耗、电压、风扇转速、内存占用、网速、硬盘活动 —— 或固定数值。
- **时钟完全可控** —— 跟随系统 / 偏移（快慢 N 分钟）/ 固定时间 / **分格定制**（时钟区左右两组 2 位数字分别映射任意数据源或固定值，如 `split:cpu_temp,mem_pct` 显示 `44:47`，冒号由固件固定）/ **秒表**（MM:SS）/ **倒计时**，带 开始 / 暂停 / 继续 / 重置 按钮。计时器发帧对齐到秒边界，屏幕跳秒干脆利落。
- **屏幕开关与定时** —— 一键关屏/开屏，或设置每日熄屏时段（如 23:30 关、07:00 开，支持跨午夜）。关屏时暂停全部发帧（面板无掉电保持，即变黑、驱动也随之空闲），恢复时自动重新握手点亮。
- **网页控制台** —— 驱动自带界面托管：浏览器直接打开 `http://127.0.0.1:8899/`，或用带**托盘图标**的无边框桌面窗口（WebView2）——鼠标悬停即可看到 CPU/GPU/内存实时数据，托盘菜单可开关屏、打开网页界面，并选择"关闭窗口收进托盘"还是"直接退出"。中英文可切换，改动即时上屏。
- **轻量设计** —— 编译版 .NET 驱动常驻内存 **约 30 MB**（工作集，定期修剪）；控制台关闭时零占用；无 Electron、无 Node 运行时。
- **配置即代码** —— 单一 `config.json` + 本地 HTTP API（`/status`、`/config`），方便脚本与自动化。
- **开机自启** —— 计划任务（SYSTEM）常驻，按你设置的刷新频率（300ms – 2s）保持屏幕长亮。

## 🔧 实现原理

屏幕是一台 USB HID 设备（`VID_0145 / PID_1001`）。它的固件主题是**固定的**：布局（双圆环+时钟）、配色、`%` / `℃` 符号都由设备绘制、不可更改。经过系统性实测（见 [逆向笔记](docs/RE-NOTES.md)），**真正可编程**的只有两处：

1. **数字**：每个圆环区有两个 2 位数字格（0-99），可以显示你喂给它的任何数据；
2. **时钟区**：一块 MM:SS 风格的显示，可以驱动为真实时间、偏移或你自己的计时器。

XkScreen 通过厂商安装的组件驱动设备，并重新实现了帧管线：每周期单帧发送、逐格数据覆盖、秒边界自适应调度。

## 📦 环境要求

| | |
|---|---|
| 系统 | Windows 10 / 11 x64 |
| 厂商软件 | 必须已安装原版 **SystemTemperatureMonitoring**（星灿屏幕工具）—— XkScreen 复用其 `XKWLib.dll` / `TempComm.dll` / `HardwareHelp64.dll` / CPUID SDK 组件完成设备链路与硬件遥测。**这些文件不随本仓库分发。** |
| 权限 | 管理员（CPUID SDK 需要驱动级硬件访问才能读取传感器；非管理员启动将没有传感器数据，控制台会显示警示横幅） |
| 构建工具 | .NET SDK 8+、Node.js 20+（仅前端构建需要） |

可通过 `--official-dir <路径>`、环境变量 `XKSCREEN_VENDOR_DIR`，或程序旁放置 `vendor` 文件夹来指向已安装的厂商组件目录。

## 🚀 快速开始（源码构建）

```powershell
# 1. 前端（Next.js 静态导出）
cd product\frontend
npm install
npm run build

# 2. 驱动服务 + 控制台
cd ..\XkScreen.Service ; dotnet build -c Release
cd ..\XkScreen.Gui     ; dotnet build -c Release

# 3. 以管理员运行驱动，然后打开 http://127.0.0.1:8899/
product\XkScreen.Service\bin\Release\net48\XkScreen.Service.exe --official-dir "D:\path\to\official"
```

桌面控制台（`XkScreen.Gui.exe`）优先加载驱动托管的界面，驱动未运行时自动回退内置副本。

## ⚙️ 配置

全部配置位于 `C:\ProgramData\XkScreen\config.json`（热加载，修改约 0.4 秒内上屏）：

```json
{
  "cpu": ["cpu_load", "cpu_temp"],
  "gpu": ["mem_pct", "net_down_x10"],
  "time": "auto",
  "interval_ms": 500,
  "screen": "on",
  "schedule": { "off": "23:30", "on": "07:00" }
}
```

### 数据源（每格最多 2 位数字，0-99）

| 标识 | 含义 | 换算 |
|---|---|---|
| `auto` | 该环的真实数据（厂商链路） | — |
| `cpu_load` / `cpu_temp` | CPU 占用 % / 封装温度 | 原值 |
| `cpu_clock` | CPU 频率 | GHz ×10（`52` = 5.2 GHz） |
| `cpu_watt` / `cpu_watt10` | CPU 封装功耗 | W（≤99）/ W ÷10（`15` = 150 W） |
| `cpu_volt` | CPU 电压 | V ×10（`12` = 1.2 V） |
| `gpu_load` / `gpu_temp` / `gpu_clock` | GPU 对应项 | 频率：GHz ×10 |
| `gpu_fan` | GPU 风扇负载 | % 0-99（NVIDIA NVML；`0` = 零风扇停转状态） |
| `mem_pct` / `mem_used_gb` | 内存占用 % / 已用 GB | 原值 |
| `net_down` / `net_up` | 网络 下载 / 上传 | MB/s |
| `net_down_x10` / `net_up_x10` | 同上，×10 分辨率 | `12` = 1.2 MB/s |
| `fan_rpm` | CPU 风扇 | rpm ÷100（`9` = 900 转） |
| `hdd_load` | 硬盘活动 % | 原值 |
| 数字，如 `50` | 固定值 | 原样显示 |

### 时钟模式

| 取值 | 含义 |
|---|---|
| `auto` | 跟随系统时间 |
| `+90` / `-30` | 快 / 慢 N 分钟 |
| `HH:MM` | 固定显示某时间（小时位可 0-99） |
| `split:L,R` | 时钟区左右两组 2 位数字分别映射：每侧可为任意数据源标识或固定数字（如 `split:cpu_temp,mem_pct` 显示 `44:47`） |
| `timer` | 秒表正计时（MM:SS） |
| `timer_from:MM:SS` | 秒表从指定值起跑 |
| `timer_paused:MM:SS` | 秒表冻结显示 |
| `timer_down:MM:SS` | 倒计时，归零停住 |
| `timer_down_paused:MM:SS` | 倒计时冻结显示 |

### 屏幕电源

| 取值 | 含义 |
|---|---|
| `"screen": "on"` | 屏幕活动（默认） |
| `"screen": "off"` | 暂停全部发帧 —— 面板熄灭 |
| `"schedule": {"off": "HH:MM", "on": "HH:MM"}` | 可选每日熄屏窗口（自动处理跨午夜）。生效关屏 = 手动关 **或** 处于窗口内 |

## 🌐 本地 API

驱动同时托管界面和一个小型 JSON API，仅监听回环地址（`127.0.0.1:8899`）：

- `GET /` —— 网页控制台（`/_next/...` 下的静态资源同样 200）
- `GET /status` —— `{ ok, config, sensors, show, screen, sensors_active }`（`show` = 时钟区当前实际显示内容，`screen` = 生效的电源状态，`sensors_active` = 服务无传感器权限时为 false）
- `POST /config` —— 校验并保存配置（schema 同 `config.json`）

## ⚠️ 已知限制

- **屏幕主题由固件固定** —— 布局、配色、标签、单位符号均不可更改（已穷尽验证，见[逆向笔记](docs/RE-NOTES.md)）。
- **每格仅 2 位数字** —— 数值截断到 0-99；大数值请用 `÷10` / `×10` 变体。
- **依赖厂商运行时组件** —— 需要本地安装原版软件提供 DLL，本仓库不包含也不分发这些文件。
- 个人爱好项目：`.tools/` 下部分辅助脚本含本机绝对路径，请按自己环境调整。

## 🙏 致谢

特别感谢以下项目与工具——它们让这项工作成为可能：

- **[REA（Reverse Engineering Assistant 逆向工程助手）](https://github.com/morluto/rea)**（作者 [@morluto](https://github.com/morluto)）—— 本项目协议分析、反汇编、反编译与差分实验背后的逆向工程助手。其"证据优先"的结构化工具链，深刻影响了屏幕能力边界的测绘方式（见[逆向笔记](docs/RE-NOTES.md)）。
- [ILSpy / ilspycmd](https://github.com/icsharpcode/ILSpy) —— 对厂商库（`XKWLib.dll`、`HardwareHelp64.dll`）的 .NET 反编译，还原出完整数据流。
- [Capstone](https://github.com/capstone-engine/capstone) 与 [pefile](https://github.com/erocarrera/pefile) —— `TempComm.dll` 的原生反汇编与 PE 解析。
- [Frida](https://frida.re/) —— 运行时 Hook，捕获到真实的 HID 报文协议（最终帧设计的"金标准"记录）。
- [Unicorn Engine](https://www.unicorn-engine.org/) —— 用于验证组包函数的模拟执行。
- [USBPcap](https://desowin.org/usbpcap/) 与 [innoextract](https://constexpr.org/innoextract/) —— 早期的抓包/解包尝试，塑造了最终的方法论。
- [hidapi](https://github.com/libusb/hidapi) —— 直连 HID 实验。
- [Pillow](https://python-pillow.org/) —— 程序化生成应用图标。
- 本产品所依赖的技术栈：**.NET Framework**、**WPF**、**Microsoft Edge WebView2**（控制台）与 **Next.js / React / Tailwind CSS**（网页界面）。
- 原版厂商软件的组件（XKWLib / TempComm / CPUID SDK）—— 运行时复用于设备链路与硬件遥测，是本项目赖以实现的互通参照物。

本项目在 **ZCode** 编码智能体的协助下开发完成。

## ⚖️ 免责声明

本工具为互通性与学习目的的非官方社区项目，与星灿及任何屏幕厂商无关、未获其背书。仓库不包含任何厂商二进制文件；所有协议知识均来自对本地已安装软件为互通目的的逆向分析。使用风险自负。

## 📄 许可证

[MIT](LICENSE)
