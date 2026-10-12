# XkScreen v0.1.0

First public release of the open-source control suite for the Xingcan / XK003 chassis LCD.

## Highlights

- **Ring data mapping** — 19 live data sources or fixed values, assignable to each of the four 2-digit slots (CPU ring top/bottom, GPU ring top/bottom).
- **Clock control** — follow system / offset / fixed time / stopwatch (MM:SS) / countdown, with pause & resume; frames are aligned to the second boundary for crisp ticking.
- **Web console** — the .NET driver hosts the UI itself: open `http://127.0.0.1:8899/` in any browser, or use the frameless WebView2 desktop window. Full Chinese / English UI.
- **Lightweight** — compiled driver at ~30 MB resident working set (periodically trimmed); console costs nothing when closed; no Electron / Node.js runtime.
- **Local JSON API** — `GET /status`, `POST /config` for scripting and automation.
- **Persistent** — boot-time scheduled task (SYSTEM) keeps the screen alive at a configurable refresh rate.

## Requirements

- Windows 10/11 x64, administrator rights.
- The original **SystemTemperatureMonitoring** software installed (XkScreen reuses its `XKWLib.dll` / `TempComm.dll` / CPUID SDK components — not redistributed in this repository). Point XkScreen at that folder with `--official-dir`, `XKSCREEN_VENDOR_DIR`, or a local `vendor` folder.

## How to run

See the [README](README.md#-quick-start-from-source) for build instructions.
Runtime configuration lives in `C:\ProgramData\XkScreen\config.json` (hot-reloaded).

## Scope note

The screen's firmware theme is fixed (layout, colors, unit symbols). The programmable surface — the rings' numbers and the clock area — is fully covered by this release, as verified in the [reverse-engineering notes](RE-NOTES.md).
