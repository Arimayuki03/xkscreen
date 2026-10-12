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
- **时钟完全可控** —— 跟随系统 / 偏移（快慢 N 分钟）/ 固定时间 / **秒表**（MM:SS）/ **倒计时**，带 开始 / 暂停 / 继续 / 重置 按钮。计时器发帧对齐到秒边界，屏幕跳秒干脆利落。
- **网页控制台** —— 驱动自带界面托管：浏览器直接打开 `http://127.0.0.1:8899/`，或用无边框桌面窗口（WebView2）。中英文可切换，改动即时上屏。
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
| 权限 | 管理员（CPUID SDK 需要驱动级硬件访问才能读取传感器） |
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
  "interval_ms": 500
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
| `gpu_load` / `gpu_temp` / `gpu_clock` / `gpu_fan` | GPU 对应项 | 风扇：rpm ÷100 |
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
| `timer` | 秒表正计时（MM:SS） |
| `timer_from:MM:SS` | 秒表从指定值起跑 |
| `timer_paused:MM:SS` | 秒表冻结显示 |
| `timer_down:MM:SS` | 倒计时，归零停住 |
| `timer_down_paused:MM:SS` | 倒计时冻结显示 |

## 🌐 本地 API

驱动同时托管界面和一个小型 JSON API，仅监听回环地址（`127.0.0.1:8899`）：

- `GET /` —— 网页控制台（`/_next/...` 下的静态资源同样 200）
- `GET /status` —— `{ ok, config, sensors, show }`（`show` = 时钟区当前实际显示内容）
- `POST /config` —— 校验并保存配置（schema 同 `config.json`）

## ⚠️ 已知限制

- **屏幕主题由固件固定** —— 布局、配色、标签、单位符号均不可更改（已穷尽验证，见[逆向笔记](docs/RE-NOTES.md)）。
- **每格仅 2 位数字** —— 数值截断到 0-99；大数值请用 `÷10` / `×10` 变体。
- **依赖厂商运行时组件** —— 需要本地安装原版软件提供 DLL，本仓库不包含也不分发这些文件。
- 个人爱好项目：`.tools/` 下部分辅助脚本含本机绝对路径，请按自己环境调整。

## 🙏 致谢与免责声明

本工具为互通性与学习目的的非官方社区项目，与星灿及任何屏幕厂商无关、未获其背书。仓库不包含任何厂商二进制文件；所有协议知识均来自对本地已安装软件为互通目的的逆向分析。使用风险自负。

## 📄 许可证

[MIT](LICENSE)
