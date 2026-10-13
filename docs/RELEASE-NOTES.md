# Release Notes

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
