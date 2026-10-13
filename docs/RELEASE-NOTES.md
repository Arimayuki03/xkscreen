# Release Notes

## XkScreen v0.3.0 — Console layout redesign

### Changed

- **Console layout reordered around what you touch most.** The CPU and GPU ring cards now sit side by side at the top (they were buried at the bottom of the right column), followed by the clock, the screen-power card and the animations; the refresh-rate card — a set-once setting — moved to the very bottom. The controls area is now a **single scroll area** instead of two independently scrolling columns, so the whole page reads top to bottom.
- **The console opens at a size that fits.** It used to open at 1100×750 and needed scrolling for most of the page. It now opens at 1520×1360 DIPs when the screen allows (the whole page fits without scrolling), clamps to the working area otherwise, and centres itself there — computed from the monitor's own scale factor, so 125 %/150 %/200 % displays land in the right place instead of hanging off the screen (WPF's `CenterScreen` mis-centres at non-100 % scales).
- Screenshots and the usage guide were refreshed for the new order.

## XkScreen v0.2.9 — Console state restore & fresh screenshots

### Fixed

- **Upgrading no longer leaves two drivers fighting over the panel.** Installing over a machine where the previous driver was still running started a second service instance (the old one keeps 127.0.0.1:8899 and the USB device, and the new one used to log the bind failure and keep driving the screen anyway — two writers, one panel). The driver now treats the API port as its ownership token and exits instead of touching the device when it is already served, and the installer stops the previous service and console before replacing files.
- **Opening the console no longer switches your animation off.** The page adopted its initial state from a `/status` payload whose `config` block omitted the `effect*` fields, so the UI fell back to its local defaults (`off` / `120 ms` / `none`) and the 400 ms auto-apply wrote those defaults straight back to `config.json` — silently killing a running effect (and resetting its speed and auto-triggers) every time the console was opened. `/status` now returns the full effect block, and the console skips its write-back when it adopts the server's state, so loading the UI can never clobber server-side values. The frontend also falls back to the top-level `effect` fields, which keeps it correct against older drivers.

### Docs

- Refreshed both console screenshots (`docs/images/screenshot.png`, `docs/images/effects.png`) — they are now real captures of the desktop console window itself, one idle and one with the pipeline animation running.
- Branding consistency: the installer and the About dialog now spell the chassis line 星璨 (they had 星灿), and the disclaimer names 爱国者（aigo）instead of a misspelled vendor.

## XkScreen v0.2.8 — Live voltage & portability

### Changed

- **CPU voltage** now reports the **live per-core VID** (the requested voltage, the same value CPU-Z shows; the maximum across P-cores/E-cores) instead of the constant `VID (max)` spec value. Measured on the target machine: 1.13–1.21 V, moving with load. Fallback chain: per-core VID → measured motherboard `VCORE` rail → the vendor SDK's own value.
- **Portability hedges**, so other platforms keep reading correctly:
  - on **non-NVIDIA GPUs** the driver refreshes the vendor SDK's counters every 10 s (they drive the GPU load/clock there, and would otherwise be frozen without NVML);
  - every value now has a documented fallback chain (CPU load → OS metric, CPU clock → OS perf counter → nominal, disk → PDH → WMI, GPU → NVML → SDK, voltage → per-core VID → VCORE → SDK) — see the README's “Sources & portability” note.

### Notes

- The panel renders the clock’s **hour** without a leading zero (a value below 10 lights only one digit) — that is the firmware’s clock rendering, not the data: the frame XkScreen sends carries the exact value and the console preview shows `07:21`.

## XkScreen v0.2.7 — Clock, voltage and console fixes

### Fixed

- **CPU clock** was pinned at the nominal 3.5 GHz: on this platform `CallNtPowerInformation`'s `CurrentMhz` reports the nominal clock even at 4.8 GHz under load. It is now computed the way Task Manager computes its "Speed" — nominal × the OS `% Processor Performance` counter — and **verified live: 3.98–4.24 GHz idle → 4.67–4.83 GHz under full load**.
- **CPU voltage** showed the vendor's static `VID (max)` spec value (1.21 V, never moving). The driver now reads the **live `VCORE` sensor** (sensor class 4096, motherboard SIO through the vendor driver): 1.12 V measured on this machine.
- Console fixes:
  - the fixed-time hour/minute inputs now keep their leading zero (`09` instead of `9`) — numeric inputs are text-mode with a 2-digit pad, and the fixed-value slot inputs pad too;
  - the schedule time pickers no longer overflow their cell (explicit width + indicator styling);
  - the animation panel puts "区域 / 速度" on two separate, aligned rows instead of one wrapping line.

### Added

- `GET /sensors` — the complete vendor-SDK sensor inventory (device, class, name, value), so it is auditable which sensors exist and which are live. This is how the live `VCORE`, `+12V`, `+5V`, `+3.3V` rails were found.

## XkScreen v0.2.6 — Branding, About & usage guide

### Added

- The target hardware is now stated explicitly everywhere: **the aigo 星璨小岚 (Xingcan Xiaolan) chassis LCD, model XK003** — README (both languages), the GitHub repository About, the console's about footer, and a new **关于 XkScreen** item in the tray menu (name, version, purpose, original-driver link, project link).
- README: the **official driver download address** — https://www.aigodiy.com/HuaqiHOMEAPP/index.aspx — in both the requirements table and the install section, plus a complete **usage guide**: install → open the console → ring mapping → six clock modes (incl. split) → screen power & daily schedule → animations → refresh rate → tray → autostart/watchdog → local API → troubleshooting.

## XkScreen v0.2.5 — Live metrics from native sources

### Changed

- **CPU load, CPU clock and the GPU utilisation/clock/temperature are now read from native, live sources** instead of the vendor SDK's cached counters:
  - `cpu_load` — `GetSystemTimes` deltas (the standard OS metric, the same one most monitoring tools show; Task Manager's "% Processor Utility" reads somewhat higher on boosting CPUs, and the two converge under sustained load);
  - `cpu_clock` — the highest current (effective) core clock via `CallNtPowerInformation`;
  - `gpu_load` / `gpu_clock` / `gpu_temp` — NVML, the same source nvidia-smi reads (measured **exactly equal** to nvidia-smi: 39.8 °C vs 39.8 °C).
- The vendor's `RefreshInformation()` call (needed by v0.2.4's fix) is gone again: it costs ~100 ms of CPU per call, and with native sources it is no longer needed. Sampling now takes **0.27 ms** (was 539 ms in v0.2.1).

### Verified

- Service CPU: **0.6 % of one core idle** (≈ 0.03 % in Task Manager) — the lowest yet.
- Ten-second parallel comparison against nvidia-smi and the Windows counters: GPU temperature identical, GPU load/clock tracking, CPU load tracking.

## XkScreen v0.2.4 — Data accuracy + console polish

### Fixed

- **Stale CPU load and clock.** After v0.2.2's slim sampling, `cpu_load` and `cpu_clock` could freeze at their last refreshed values (e.g. load nailed at 12 % while the machine was busy, clock stuck at 2.69 GHz). Root cause found by decompiling the vendor path: its `ReadRunData()` override calls `CPUIDSDK.RefreshInformation()` before sampling (that is what re-reads the SDK's frequency/load counters), while temperature and power are read live and kept moving — which is why only those two fields went stale. The driver now calls `RefreshInformation()` in every sampling pass. Verified under load: load 19 → 48 %, clock 26.9 → 52.9 (5.29 GHz boost), then back down after the load ended.
- Console layout: the split-clock source dropdowns truncated their labels ("CPU 温…"). Dropdown popups are now at least 250 px wide, the two split editors use the full row width, and the animation panel's "开屏时 / 倒计时结束" triggers are two separate aligned rows instead of one wrapping line.

### Data audit (2026-10-13)

Cross-checked every displayed value against independent sources (nvidia-smi, Windows performance counters, the OS memory counters): GPU temperature/load/fan, RAM %/used GB, CPU fan RPM, disk activity and the self-sampled network rates all agreed within their sampling windows. `cpu_load` / `cpu_clock` were the only stale fields — fixed above.

## XkScreen v0.2.3 — Tray memory stays trimmed

### Fixed

- The console only trimmed its working set at the moment it hid to the tray; afterwards Windows paged its used pages back in and the tray footprint crept from ≈ 7 MB towards ≈ 20 MB private. A periodic trim (every 3 minutes while hidden) now keeps it down: measured **3.9 MB private / 12.7 MB total** in the tray (after 8.4 MB / 35.7 MB immediately on hide).

### Notes

- If you see `msedgewebview2.exe` processes holding a few hundred MB in Task Manager, check the user-data folder in the command line: ours lives in `C:\XkScreen\gui\XkScreen.Gui.exe.WebView2` and only exists while the console window is open. The ones under `…\Packages\MicrosoftWindows.Client.CBS_…\EBWebView` belong to Windows itself (widgets/search/settings).
- Current resident cost with the console in the tray: service ≈ 12 MB + console ≈ 5 MB private working set.

## XkScreen v0.2.2 — 12× lower CPU

### Changed

- **The driver now samples the hardware itself instead of letting the vendor DLL do a full pass.** The vendor's all-in-one `ReadRunData` also runs a network getter (WMI performance counters) and a disk getter (WMI `Win32_DiskDrive`) — together tens of milliseconds of CPU per pass — even though XkScreen computes network rates from adapter counters and only needs disk activity. The driver now calls just the four cheap getters it uses (CPU / GPU / RAM / fan, ≈1 ms each) and publishes them itself; disk activity comes from a PDH counter (`PhysicalDisk\% Disk Time`).
- Sampling cadence is also ours now (the vendor's 1 Hz refresh thread is stopped): 1 s normally, 5 s while the screen is dark.
- Minor: config file is re-parsed only when it changes; the official CPU/GPU frames go out ≈1×/s (the SDK refreshes at that rate anyway) while the time frame still flows every cycle; network adapter list is cached for 30 s.

**Measured on the target machine** (20 logical cores, `Get-Counter` on `\Process(XkScreen.Service)\% Processor Time`):

| Scenario | Before | After |
|---|---|---|
| Idle, screen on | 10.79 % of one core (≈ 0.54 % in Task Manager) | **0.90 %** (≈ 0.045 %) |
| Console open (2 s /status polling) | ≈ 13 % | **1.71 %** |
| Screen off (night schedule) | 3.28 % | **0.92 %** |

### Added

- `GET /perf` — a tiny self-check endpoint returning the measured cost of one sampling pass and of the per-cycle read/frame building (`sample_ms`, `getSensors_ms`, `buildCpu_ms`, …).

## XkScreen v0.2.1 — Tray memory fix

### Fixed

- **Closing the console to the tray now frees its memory.** Previously the window was only hidden, so the WebView2 browser/renderer process tree kept idling in the background (~450 MB). The console now disposes the WebView2 and trims its working set when hidden to the tray, and rebuilds the UI when you reopen it: **≈ 35 MB while in the tray** (versus ≈ 490 MB with the window open), and nothing at all after exiting. Measured: open 488 MB → tray 35 MB → reopened 406 MB.

### Added

- The console is single-instance: launching it again (e.g. from the desktop icon while it sits in the tray) brings the existing window back instead of starting a second copy.

## XkScreen v0.2.0 — One-click installer

### Added

- **One-click installer** (`XkScreen-Setup-0.2.0.exe`, Inno Setup, Chinese wizard): detects an installed copy of the original software and copies the vendor components it needs, installs the driver + web console + desktop console to `C:\XkScreen`, registers boot autostart and start-menu/desktop shortcuts, and starts the driver before the wizard closes. An uninstaller (Start menu → 卸载 XkScreen) removes everything; your `config.json` is kept.
- **Hourly watchdog task** — restarts the driver if the process ever dies, and proactively every 48 h. (Tasks created via `schtasks` inherit a default 72 h execution-time limit that would otherwise blank the screen every 3 days; the watchdog resets it.)
- The installer sets the original service `SystemTemperatureMonitoring` to **manual start** (it auto-started by default and would fight XkScreen for the USB screen) and restores auto-start when XkScreen is uninstalled.
- `installer/` in the repository: the Inno script supports a public build (vendor-free; components are copied from the user's own original install at install time) and a personal build with the vendor DLLs embedded (`iscc /DEmbedVendor=1 /DVendorDir=<official>`).

### Notes

- Install path is deliberately **space-free** (`C:\XkScreen`): on this Windows build the Task Scheduler returns `E_FAIL` for task targets containing spaces, and it also refuses unsigned `.exe` targets — the driver task therefore runs `service_host.cmd`, which hosts the service in the foreground.
- The packaged service includes the v0.1.4 animation engine and the GPU-fan / sensor-init work from v0.1.3.

## XkScreen v0.1.4 — Screen animations

### Added

- **Animation engine** — the panel only accepts digit values (colors and brightness are firmware-fixed), so every effect is a scripted value sequence over the six display cells (rings CPU/GPU top/bottom + the clock's two 2-digit groups), layered on top of the real data at 60-1000 ms per tick:
  - Persistent modes: **pipeline** (`scroll`, a digit conveyor), **marquee** (`chase`, an `88` racing through the cells like an RGB chase), **digital rain**, **wave**, **counter** and **glitch** — each with a target (`clock` / `rings` / `all`) and speed.
  - One-shots (console buttons or `POST /effect`): **Steins;Gate divergence-meter scramble** (digits flicker, then lock onto the real values one by one), **boot scan** (all-`88` flash → odometer ramp → settle) and **glitch burst**.
  - Automatic triggers: play a one-shot on screen-on or when a countdown reaches `00:00`.
- New config keys: `effect`, `effect_target`, `effect_speed_ms`, `effect_on_screen_on`, `effect_on_timer_end`; new API `POST /effect`; `/status` now reports the effect state; the console has a bilingual **Animations** panel.

### Notes

- Verified live: the effect tick drives the loop at ~125 ms per frame (≈ 8 fps) while sensor reads slow down to the SDK's 1 Hz refresh; every mode's digit sequence was checked against its design (pipeline `11:23 → 23:45 → 78:90`, marquee `08:88 ↔ 88:52`, counter `09:23 → 09:62 → 10:01`, …).

## XkScreen v0.1.3 — GPU fan & sensor init hardening

### Added

- **GPU fan reading** — the GPU run-data on this platform carries no fan value, the CPUID SDK's adapter-fan API returns `-1` and NVML's RPM API is unsupported, so the driver now reads the **NVIDIA NVML fan percentage** (`nvml.dll`, ships with the display driver). Verified live against `nvidia-smi` (40 % == 40 %); `0` when the zero-fan idle state has the fans physically stopped. The console label is now `GPU fan (%)`.
- `/status` now reports `sensors_active` — `false` when the driver runs without sensor access; the console shows a warning banner so all-zero readings are never mistaken for real data.

### Fixed

- **Sensors could come up completely empty after a restart.** Root cause: the vendor SDK initializes its hardware *lazily inside its send thread's retry loop*, and the previous fix for the screen-relight bug (`thread_flag = false`) killed that retry loop together with the sender — whether sensors worked came down to a millisecond race. The driver now performs a deterministic init itself (stop the send thread → retry `hardware.Start()` until `InitState` → re-arm the SDK's `OpenRefresh` thread → verify the data pipeline before serving).
- Sensor init needs the CPUID kernel driver, which can only be loaded elevated (`Driver error 5`); the driver now logs this clearly, and the restart helper script deploys and restarts elevated (one UAC prompt).

## XkScreen v0.1.2 — Split clock & tray

### Added

- **Split clock mode** — drive the clock area's two 2-digit groups independently: `time: "split:L,R"` maps each side to any data source or a fixed value (the colon is firmware-drawn). E.g. `split:cpu_temp,mem_pct` shows `44:47`. The web console gets a dedicated split mode with two source pickers and live value badges.
- **Tray icon** for the desktop console — hover shows live CPU / GPU / RAM and the screen state; the menu toggles the screen, opens the web UI, and lets you choose close-to-tray or plain exit (persisted in `%ProgramData%\XkScreen\gui.json`).

### Fixed

- **Screen relighting after power off** — the panel used to light up again every few seconds while switched off. Root cause: the vendor DLL's internal keep-alive thread re-sent a real-data frame every `usb_send_delay` behind the driver's back. The driver now disables that thread via reflection (`thread_flag = false`), and a re-arm call that threw `NullReferenceException` on resume was removed. Verified with a 240-second Frida watch on the USB writes: **0 packets, 0 device opens** while off.

## XkScreen v0.1.1 — Screen power & schedule

### Added

- **Screen power control** — turn the panel off/on manually. Frames pause while off (the panel goes dark) and resume with a fresh device handshake.
- **Daily on/off schedule** — e.g. dark from 23:30 to 07:00, midnight wrap supported. Effective off = manual switch OR inside the window.
- **Screen panel** in the web console with a live state badge (English / 中文).
- `/status` now reports the effective screen state.

### Fixed / improved

- Timer frames align to displayed-second boundaries (crisp MM:SS ticking).
- Driver trims its working set (≈28 MB resident) and the desktop console renders without the GPU process.

## XkScreen v0.1.0

First public release of the open-source control suite for the Xingcan / XK003 chassis LCD.

### Highlights

- **Ring data mapping** — 19 live data sources or fixed values, assignable to each of the four 2-digit slots (CPU ring top/bottom, GPU ring top/bottom).
- **Clock control** — follow system / offset / fixed time / stopwatch (MM:SS) / countdown, with pause & resume; frames are aligned to the second boundary for crisp ticking.
- **Web console** — the .NET driver hosts the UI itself: open `http://127.0.0.1:8899/` in any browser, or use the frameless WebView2 desktop window. Full Chinese / English UI.
- **Lightweight** — compiled driver at ~30 MB resident working set (periodically trimmed); console costs nothing when closed; no Electron / Node.js runtime.
- **Local JSON API** — `GET /status`, `POST /config` for scripting and automation.
- **Persistent** — boot-time scheduled task (SYSTEM) keeps the screen alive at a configurable refresh rate.

### Requirements

- Windows 10/11 x64, administrator rights.
- The original **SystemTemperatureMonitoring** software installed (XkScreen reuses its `XKWLib.dll` / `TempComm.dll` / CPUID SDK components — not redistributed in this repository). Point XkScreen at that folder with `--official-dir`, `XKSCREEN_VENDOR_DIR`, or a local `vendor` folder.

### How to run

See the [README](../README.md#-quick-start-from-source) for build instructions.
Runtime configuration lives in `C:\ProgramData\XkScreen\config.json` (hot-reloaded).

### Scope note

The screen's firmware theme is fixed (layout, colors, unit symbols). The programmable surface — the rings' numbers and the clock area — is fully covered by this release, as verified in the [reverse-engineering notes](RE-NOTES.md).
