# Release Notes

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
