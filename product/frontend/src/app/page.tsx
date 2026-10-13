"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import { createPortal } from "react-dom";

const API = "http://127.0.0.1:8899";

type Lang = "zh" | "en";

type Config = {
  cpu: string[];
  gpu: string[];
  time: string;
  interval_ms: number;
  screen: "on" | "off";
  schEnabled: boolean;
  schOff: string;
  schOn: string;
  splitL: string;
  splitR: string;
};

const DEFAULT_CONFIG: Config = {
  cpu: ["auto", "auto"],
  gpu: ["auto", "auto"],
  time: "auto",
  interval_ms: 500,
  screen: "on",
  schEnabled: false,
  schOff: "23:30",
  schOn: "07:00",
  splitL: "cpu_temp",
  splitR: "mem_pct",
};

/** Map the UI state onto the driver's config schema. */
function toApi(c: Config) {
  return {
    cpu: c.cpu,
    gpu: c.gpu,
    time: c.time,
    interval_ms: c.interval_ms,
    screen: c.screen,
    ...(c.schEnabled ? { schedule: { off: c.schOff, on: c.schOn } } : {}),
  };
}

const SOURCES: { key: string; zh: string; en: string }[] = [
  { key: "auto", zh: "自动（真实数据）", en: "Auto (real data)" },
  { key: "cpu_load", zh: "CPU 占用 %", en: "CPU usage %" },
  { key: "cpu_temp", zh: "CPU 温度 ℃", en: "CPU temp ℃" },
  { key: "cpu_clock", zh: "CPU 频率（52 = 5.2GHz）", en: "CPU clock (52 = 5.2GHz)" },
  { key: "cpu_watt", zh: "CPU 功耗 W（≤99）", en: "CPU power W (≤99)" },
  { key: "cpu_watt10", zh: "CPU 功耗 ÷10（15 = 150W）", en: "CPU power ÷10 (15 = 150W)" },
  { key: "cpu_volt", zh: "CPU 电压（12 = 1.2V）", en: "CPU voltage (12 = 1.2V)" },
  { key: "gpu_load", zh: "GPU 占用 %", en: "GPU usage %" },
  { key: "gpu_temp", zh: "GPU 温度 ℃", en: "GPU temp ℃" },
  { key: "gpu_clock", zh: "GPU 频率（15 = 1.5GHz）", en: "GPU clock (15 = 1.5GHz)" },
  { key: "gpu_fan", zh: "GPU 风扇（%）", en: "GPU fan (%)" },
  { key: "mem_pct", zh: "内存占用 %", en: "RAM usage %" },
  { key: "mem_used_gb", zh: "内存已用 GB", en: "RAM used GB" },
  { key: "net_down", zh: "下载速度 MB/s", en: "Download MB/s" },
  { key: "net_down_x10", zh: "下载 ×10（12 = 1.2MB/s）", en: "Download ×10 (12 = 1.2MB/s)" },
  { key: "net_up", zh: "上传速度 MB/s", en: "Upload MB/s" },
  { key: "net_up_x10", zh: "上传 ×10（12 = 1.2MB/s）", en: "Upload ×10 (12 = 1.2MB/s)" },
  { key: "fan_rpm", zh: "CPU 风扇（9 = 900转）", en: "CPU fan (9 = 900rpm)" },
  { key: "hdd_load", zh: "硬盘活动 %", en: "Disk activity %" },
];

const UI = {
  zh: {
    title: "XkScreen 屏幕控制台",
    openInBrowser: "浏览器打开：http://127.0.0.1:8899/",
    connecting: "正在连接驱动服务…",
    connectedHint: "已连接，改动自动生效",
    applying: "应用中…",
    applied: "已应用 ✓",
    applyFailed: "应用失败：",
    offline: "无法连接驱动服务（127.0.0.1:8899）",
    applyOffline: "应用失败：无法连接服务",
    connected: "驱动服务已连接",
    disconnected: "未连接",
    sensorsInactive:
      "传感器未激活：请以管理员身份运行驱动（或使用计划任务启动），当前读数不可信",
    previewHint: "屏幕实际显示内容 · 每格最多 2 位数字",
    refreshRate: "刷新频率",
    timesPerSec: "次/秒",
    clock: "时钟",
    modeAuto: "跟随系统",
    modeOffset: "偏移",
    modeFixed: "固定时间",
    modeTimer: "秒表",
    modeTimerDown: "倒计时",
    vsSystem: "比系统时间",
    minutesPosAhead: "分钟（正 = 快）",
    showFixed: "固定显示",
    hourUpTo99: "（小时位可到 99）",
    timerHint: "切换到秒表即从 00:00 开始计时；重新选择本项可归零重启",
    btnStart: "开始",
    btnResume: "继续",
    btnPause: "暂停",
    btnReset: "重置",
    duration: "时长",
    min: "分",
    sec: "秒",
    cdHint: "秒，归零后停住",
    cpuRing: "CPU 环",
    gpuRing: "GPU 环",
    topBottom: "上格 / 下格",
    top: "上格",
    bottom: "下格",
    fixedValue: "固定值…",
    screenPanel: "屏幕",
    powerLabel: "电源",
    screenOn: "开启",
    screenOff: "关闭",
    effOn: "当前点亮",
    effOff: "当前已关闭",
    scheduleLabel: "定时开关",
    schedEnable: "启用",
    schedDisable: "停用",
    schedOffLabel: "关闭时间",
    schedOnLabel: "开启时间",
    modeSplit: "分格定制",
    splitLeft: "左两位",
    splitRight: "右两位",
    splitHint: "冒号由固件固定显示；左右两组 2 位数字可分别映射任意数据源或固定值",
  },
  en: {
    title: "XkScreen Console",
    openInBrowser: "Open in browser: http://127.0.0.1:8899/",
    connecting: "Connecting to driver service…",
    connectedHint: "Connected — changes apply instantly",
    applying: "Applying…",
    applied: "Applied ✓",
    applyFailed: "Apply failed: ",
    offline: "Cannot reach the driver service (127.0.0.1:8899)",
    applyOffline: "Apply failed: cannot reach the service",
    connected: "Driver service connected",
    disconnected: "Disconnected",
    sensorsInactive:
      "Sensors inactive: run the driver elevated (or via the scheduled task) — readings are not live",
    previewHint: "What the screen is showing · 2 digits per slot max",
    refreshRate: "Refresh rate",
    timesPerSec: "/s",
    clock: "Clock",
    modeAuto: "Follow system",
    modeOffset: "Offset",
    modeFixed: "Fixed time",
    modeTimer: "Stopwatch",
    modeTimerDown: "Countdown",
    vsSystem: "vs system time",
    minutesPosAhead: "minutes (positive = ahead)",
    showFixed: "Show fixed",
    hourUpTo99: "(hour up to 99)",
    timerHint:
      "Selecting Stopwatch starts from 00:00; re-select it to reset to zero",
    btnStart: "Start",
    btnResume: "Resume",
    btnPause: "Pause",
    btnReset: "Reset",
    duration: "Duration",
    min: "min",
    sec: "sec",
    cdHint: "sec, stops at zero",
    cpuRing: "CPU ring",
    gpuRing: "GPU ring",
    topBottom: "top / bottom",
    top: "Top",
    bottom: "Bottom",
    fixedValue: "Fixed value…",
    screenPanel: "Screen",
    powerLabel: "Power",
    screenOn: "On",
    screenOff: "Off",
    effOn: "Lights on",
    effOff: "Display off",
    scheduleLabel: "Daily schedule",
    schedEnable: "Enable",
    schedDisable: "Disable",
    schedOffLabel: "Off at",
    schedOnLabel: "On at",
    modeSplit: "Custom split",
    splitLeft: "Left 2 digits",
    splitRight: "Right 2 digits",
    splitHint:
      "The colon is firmware-drawn; each 2-digit group maps to any data source or a fixed value",
  },
} as const;

type UIKey = keyof (typeof UI)["zh"];

const INTERVALS = [300, 500, 800, 1000, 1500, 2000];

type ClockMode = "auto" | "offset" | "fixed" | "split" | "timer" | "timer_down";

function modeOf(spec: string): ClockMode {
  if (!spec || spec === "auto") return "auto";
  if (spec.startsWith("split:")) return "split";
  if (spec.startsWith("timer_down")) return "timer_down";
  if (spec.startsWith("timer")) return "timer";
  if (/^[+-]\d+$/.test(spec)) return "offset";
  return "fixed";
}

const showToSec = (s: string): number => {
  const m = s.match(/^(\d{1,2}):(\d{2})$/);
  return m ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : 0;
};
const fmt = (sec: number): string => {
  const v = Math.max(0, Math.min(99 * 60 + 59, Math.floor(sec)));
  return String(Math.floor(v / 60)).padStart(2, "0") + ":" + String(v % 60).padStart(2, "0");
};

const mmssOf = (v: string): number => {
  const m = v.match(/^(\d{1,2}):(\d{2})$/);
  return m ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : 0;
};

type TimerAnchor = { spec: string; at: number };

const elapsedOf = (a: TimerAnchor, spec: string, now: number): number =>
  a.spec === spec ? Math.max(0, (now - a.at) / 1000) : 0;

/** Instant local display for timer specs (does not wait for the server round-trip). */
const displayOf = (spec: string, a: TimerAnchor, now: number): string => {
  const el = elapsedOf(a, spec, now);
  let m: RegExpMatchArray | null = spec.match(/^timer_from:(\d{1,2}:\d{2})$/);
  if (m) return fmt(mmssOf(m[1]) + el);
  m = spec.match(/^timer_paused:(\d{1,2}:\d{2})$/);
  if (m) return m[1];
  m = spec.match(/^timer_down_paused:(\d{1,2}:\d{2})$/);
  if (m) return m[1];
  if (spec === "timer") return fmt(el);
  m = spec.match(/^timer_down:(\d{1,2}:\d{2})$/);
  if (m) return fmt(mmssOf(m[1]) - el);
  return "--:--";
};

function clamp99(n: number): number {
  return Math.max(0, Math.min(99, Math.round(n)));
}

/** Live value of one token (fixed number or data-source name) for slot badges. */
function resolveLive(tok: string, sensors: Record<string, number>): number {
  if (/^\d+$/.test(tok)) return clamp99(parseInt(tok, 10));
  const v = sensors[tok];
  return v === undefined ? 0 : clamp99(v);
}

function ringPreview(
  pair: string[],
  ring: "cpu" | "gpu",
  sensors: Record<string, number>
): [number, number] {
  const def0 = ring === "cpu" ? "cpu_load" : "gpu_load";
  const def1 = ring === "cpu" ? "cpu_temp" : "gpu_temp";
  const resolve = (tok: string, def: string): number => {
    const t = !tok || tok === "auto" ? def : tok;
    if (/^\d+$/.test(t)) return clamp99(parseInt(t, 10));
    const v = sensors[t];
    return v === undefined ? 0 : clamp99(v);
  };
  return [resolve(pair[0], def0), resolve(pair[1], def1)];
}

/* ---------------- UI building blocks ---------------- */

function Gauge({
  label,
  a,
  b,
  ring,
}: {
  label: string;
  a: number;
  b: number;
  ring: "cpu" | "gpu";
}) {
  const R = 52;
  const C = 2 * Math.PI * R;
  const frac = Math.max(0, Math.min(99, a)) / 99;
  const arc = ring === "cpu" ? "#fbbf24" : "#38bdf8";
  const txt = ring === "cpu" ? "text-amber-300" : "text-sky-300";
  return (
    <div className="flex flex-col items-center gap-1">
      <span className="text-[10px] tracking-[0.35em] text-slate-500">{label}</span>
      <div className="relative h-36 w-36">
        <svg viewBox="0 0 128 128" className="h-full w-full -rotate-90">
          <circle cx="64" cy="64" r={R} fill="none" stroke="#1e293b" strokeWidth="9" />
          <circle
            cx="64"
            cy="64"
            r={R}
            fill="none"
            stroke={arc}
            strokeWidth="9"
            strokeLinecap="round"
            strokeDasharray={C * frac + " " + C}
            style={{ transition: "stroke-dasharray 0.3s" }}
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center font-mono leading-tight">
          <span className={"text-3xl tabular-nums " + txt}>
            {a}
            <span className="ml-0.5 text-sm text-slate-500">%</span>
          </span>
          <span className={"text-2xl tabular-nums " + txt}>
            {b}
            <span className="ml-0.5 text-sm text-slate-500">℃</span>
          </span>
        </div>
      </div>
    </div>
  );
}

function Panel({
  title,
  right,
  children,
}: {
  title: string;
  right?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="rounded-2xl border border-slate-800/80 bg-[#0f141c] p-4">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="text-sm font-medium tracking-wide text-slate-300">{title}</h2>
        {right}
      </div>
      {children}
    </section>
  );
}

function Segmented<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T;
  options: { v: T; label: string }[];
  onChange: (v: T) => void;
}) {
  return (
    <div className="inline-flex flex-wrap gap-1 rounded-xl border border-slate-800 bg-slate-950/50 p-1">
      {options.map((o) => (
        <button
          key={o.v}
          type="button"
          onClick={() => onChange(o.v)}
          className={
            "rounded-lg px-3 py-1.5 text-sm transition-colors " +
            (o.v === value
              ? "border border-sky-500/40 bg-sky-500/15 text-sky-300"
              : "border border-transparent text-slate-400 hover:bg-slate-800/60 hover:text-slate-200")
          }
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

const inputCls =
  "rounded-lg border border-slate-700 bg-slate-900/80 px-2.5 py-1.5 text-sm text-slate-100 outline-none transition-colors focus:border-sky-500";

function NumInput({
  value,
  min,
  max,
  onChange,
  width = "w-20",
}: {
  value: number;
  min: number;
  max: number;
  onChange: (n: number) => void;
  width?: string;
}) {
  return (
    <input
      type="number"
      className={inputCls + " text-center tabular-nums " + width}
      value={value}
      min={min}
      max={max}
      onChange={(e) => {
        const n = parseInt(e.target.value, 10);
        if (!isNaN(n)) onChange(Math.max(min, Math.min(max, n)));
      }}
    />
  );
}

const btnBase =
  "rounded-lg border px-3 py-1.5 text-sm transition-colors disabled:cursor-not-allowed disabled:opacity-40";
const btnPrimary = btnBase + " border-sky-500/40 bg-sky-500/15 text-sky-300 hover:bg-sky-500/25";
const btnGhost = btnBase + " border-slate-700 text-slate-300 hover:bg-slate-800/60";

/** Custom dark dropdown. The popup is rendered in a body-level portal with fixed
 *  positioning, so it can never be clipped or occluded by scroll containers or
 *  neighbouring panels; it stays locked to the trigger width, has a slim styled
 *  scrollbar and flips upward when there is not enough room below. */
function Dropdown({
  value,
  options,
  onChange,
}: {
  value: string;
  options: { v: string; label: string }[];
  onChange: (v: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const [pos, setPos] = useState<{
    left: number;
    width: number;
    top: number;
    bottom: number;
    up: boolean;
    maxH: number;
  } | null>(null);
  const rootRef = useRef<HTMLDivElement | null>(null);
  const listRef = useRef<HTMLDivElement | null>(null);

  const current = options.find((o) => o.v === value) || options[0];

  const updatePos = () => {
    const el = rootRef.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    const below = window.innerHeight - r.bottom;
    const up = below < 300 && r.top > below;
    const space = (up ? r.top : below) - 12;
    setPos({
      left: Math.max(8, Math.min(r.left, window.innerWidth - r.width - 8)),
      width: r.width,
      top: r.bottom + 4,
      bottom: window.innerHeight - r.top + 4,
      up,
      maxH: Math.max(120, Math.min(288, space)),
    });
  };

  const toggle = () => {
    if (!open) {
      const idx = options.findIndex((o) => o.v === value);
      setActive(idx < 0 ? 0 : idx);
      updatePos();
    }
    setOpen((o) => !o);
  };

  const pick = (v: string) => {
    onChange(v);
    setOpen(false);
  };

  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => {
      const t = e.target as Node;
      const inside =
        (rootRef.current && rootRef.current.contains(t)) ||
        (listRef.current && listRef.current.contains(t));
      if (!inside) setOpen(false);
    };
    const onScrollOrResize = (ev: Event) => {
      // Scrolling inside the popup itself (e.g. the auto scroll-into-view of the
      // selected item) must NOT close it; only outside scrolls / resizes do.
      if (ev.type === "scroll" && listRef.current) {
        const t = ev.target;
        if (t instanceof Node && listRef.current.contains(t)) return;
      }
      setOpen(false);
    };
    document.addEventListener("mousedown", onDoc);
    window.addEventListener("scroll", onScrollOrResize, true);
    window.addEventListener("resize", onScrollOrResize);
    return () => {
      document.removeEventListener("mousedown", onDoc);
      window.removeEventListener("scroll", onScrollOrResize, true);
      window.removeEventListener("resize", onScrollOrResize);
    };
  }, [open]);

  useEffect(() => {
    if (open && listRef.current) {
      const el = listRef.current.querySelector('[data-idx="' + active + '"]');
      if (el) (el as HTMLElement).scrollIntoView({ block: "nearest" });
    }
  }, [open, active]);

  const list = (
    <div
      ref={listRef}
      className="dd-scroll fixed z-50 overflow-y-auto rounded-xl border border-slate-700 bg-[#0d1219] py-1 shadow-2xl shadow-black/70"
      style={
        pos
          ? {
              left: pos.left,
              width: pos.width,
              maxHeight: pos.maxH,
              ...(pos.up ? { bottom: pos.bottom } : { top: pos.top }),
            }
          : { display: "none" }
      }
    >
      {options.map((o, i) => (
        <button
          key={o.v}
          type="button"
          data-idx={i}
          onMouseEnter={() => setActive(i)}
          onClick={() => pick(o.v)}
          className={
            "block w-full truncate px-3 py-1.5 text-left text-sm transition-colors " +
            (i === active ? "bg-slate-800/80 text-slate-100" : "text-slate-400") +
            (o.v === value ? " font-medium text-sky-300" : "")
          }
        >
          {o.label}
        </button>
      ))}
    </div>
  );

  return (
    <div
      className="relative w-full min-w-0 focus:outline-none"
      ref={rootRef}
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === "Escape") {
          setOpen(false);
          return;
        }
        if (!open) {
          if (e.key === "ArrowDown" || e.key === "Enter" || e.key === " ") {
            e.preventDefault();
            toggle();
          }
          return;
        }
        if (e.key === "ArrowDown") {
          e.preventDefault();
          setActive((a) => Math.min(options.length - 1, a + 1));
        } else if (e.key === "ArrowUp") {
          e.preventDefault();
          setActive((a) => Math.max(0, a - 1));
        } else if (e.key === "Enter") {
          e.preventDefault();
          pick(options[active].v);
        }
      }}
    >
      <button
        type="button"
        onClick={toggle}
        className={
          inputCls +
          " flex w-full items-center justify-between gap-2 text-left " +
          (open ? "border-sky-500" : "")
        }
      >
        <span className="truncate">{current ? current.label : ""}</span>
        <span
          className={"text-xs text-slate-500 transition-transform " + (open ? "rotate-180" : "")}
        >
          ▾
        </span>
      </button>
      {open && pos && typeof document !== "undefined" ? createPortal(list, document.body) : null}
    </div>
  );
}

function SlotEditor({
  value,
  live,
  lang,
  onChange,
}: {
  value: string;
  live: number;
  lang: Lang;
  onChange: (v: string) => void;
}) {
  const isFixed = /^\d+$/.test(value);
  const options = SOURCES.map((s) => ({ v: s.key, label: lang === "zh" ? s.zh : s.en })).concat([
    { v: "__fixed", label: lang === "zh" ? "固定值…" : "Fixed value…" },
  ]);
  return (
    <div className="flex items-center gap-2">
      <div className="min-w-0 flex-1">
        <Dropdown
          value={isFixed ? "__fixed" : value}
          options={options}
          onChange={(v) => {
            if (v === "__fixed") onChange(isFixed ? value : "50");
            else onChange(v);
          }}
        />
      </div>
      {isFixed ? (
        <NumInput
          value={parseInt(value, 10)}
          min={0}
          max={99}
          onChange={(n) => onChange(String(n))}
          width="w-20"
        />
      ) : (
        <span className="min-w-14 rounded-lg border border-slate-800 bg-slate-950/60 px-2.5 py-1.5 text-center text-sm tabular-nums text-slate-400">
          {live}
        </span>
      )}
    </div>
  );
}

/* ---------------- page ---------------- */

type MsgKey =
  | "connecting"
  | "connectedHint"
  | "applying"
  | "applied"
  | "applyFailed"
  | "offline"
  | "applyOffline";

export default function Home() {
  const [lang, setLang] = useState<Lang>("zh");
  const [config, setConfig] = useState<Config>(DEFAULT_CONFIG);
  const [sensors, setSensors] = useState<Record<string, number>>({});
  const [show, setShow] = useState("");
  const [screenEff, setScreenEff] = useState<"on" | "off">("on");
  const [connected, setConnected] = useState(false);
  const [sensorsActive, setSensorsActive] = useState(true);
  const [msg, setMsg] = useState<{ k: MsgKey; d?: string }>({ k: "connecting" });

  // clock input fields (kept locally, applied on change)
  const [offsetN, setOffsetN] = useState(90);
  const [hhN, setHhN] = useState(12);
  const [mmN, setMmN] = useState(34);
  const [downM, setDownM] = useState(5);
  const [downS, setDownS] = useState(0);

  const initialLoaded = useRef(false);
  const skipNextApply = useRef(true);
  const applyTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const t = useCallback((k: UIKey) => UI[lang][k], [lang]);

  // language: restore preference (or detect) on mount, persist on change
  useEffect(() => {
    let l: Lang = "zh";
    try {
      const saved = localStorage.getItem("xkscreen.lang");
      if (saved === "zh" || saved === "en") l = saved;
      else if (!String(navigator.language || "").toLowerCase().startsWith("zh")) l = "en";
    } catch {}
    setLang(l);
  }, []);

  const changeLang = (l: Lang) => {
    setLang(l);
    try {
      localStorage.setItem("xkscreen.lang", l);
    } catch {}
  };

  useEffect(() => {
    try {
      document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";
      document.title = UI[lang].title;
    } catch {}
  }, [lang]);

  const poll = useCallback(async () => {
    try {
      const r = await fetch(API + "/status", { cache: "no-store" });
      const j = await r.json();
      setConnected(true);
      setSensorsActive(j.sensors_active !== false);
      setSensors(j.sensors || {});
      setShow(j.show || "");
      setScreenEff(j.screen === "off" ? "off" : "on");
      // Recalibrate the local timer anchor from the server's authoritative value
      // when it drifts too far (or on first sight of a running spec).
      const ts: string | undefined = j.config ? j.config.time : undefined;
      if (ts) {
        const now = Date.now();
        let kind: "up" | "down" | null = null;
        let base = 0;
        let m = ts.match(/^timer_from:(\d{1,2}:\d{2})$/);
        if (m) {
          kind = "up";
          base = mmssOf(m[1]);
        } else if (ts === "timer") {
          kind = "up";
          base = 0;
        } else if ((m = ts.match(/^timer_down:(\d{1,2}:\d{2})$/))) {
          kind = "down";
          base = mmssOf(m[1]);
        }
        if (kind) {
          const showSec = showToSec(j.show || "");
          const serverElapsed = kind === "up" ? showSec - base : base - showSec;
          const ourElapsed = elapsedOf(anchorRef.current, ts, now);
          if (anchorRef.current.spec !== ts || Math.abs(ourElapsed - serverElapsed) > 1.5) {
            anchorRef.current = { spec: ts, at: now - serverElapsed * 1000 };
          }
        } else {
          anchorRef.current = { spec: ts, at: now };
        }
      }
      if (!initialLoaded.current && j.config) {
        initialLoaded.current = true;
        const tt: string = j.config.time || "auto";
        const sch = j.config.schedule;
        const msp = tt.match(/^split:([^,]+),(.+)$/);
        setConfig({
          cpu: j.config.cpu || ["auto", "auto"],
          gpu: j.config.gpu || ["auto", "auto"],
          time: tt,
          interval_ms: j.config.interval_ms || 500,
          screen: j.config.screen === "off" ? "off" : "on",
          schEnabled: !!sch,
          schOff: sch && sch.off ? String(sch.off) : "23:30",
          schOn: sch && sch.on ? String(sch.on) : "07:00",
          splitL: msp ? msp[1].trim() : "cpu_temp",
          splitR: msp ? msp[2].trim() : "mem_pct",
        });
        if (/^[+-]\d+$/.test(tt)) setOffsetN(parseInt(tt, 10));
        const mf = tt.match(/^(\d{1,2}):(\d{2})$/);
        if (mf) {
          setHhN(parseInt(mf[1], 10));
          setMmN(parseInt(mf[2], 10));
        }
        const md = tt.match(/^timer_down(?:_paused)?:(\d{1,2}):(\d{2})$/);
        if (md) {
          setDownM(parseInt(md[1], 10));
          setDownS(parseInt(md[2], 10));
        }
        setMsg({ k: "connectedHint" });
      }
    } catch {
      setConnected(false);
      setMsg({ k: "offline" });
    }
  }, []);

  useEffect(() => {
    poll();
    const tmr = setInterval(poll, 500);
    return () => clearInterval(tmr);
  }, [poll]);

  const applyConfig = useCallback(async (cfg: Config) => {
    try {
      setMsg({ k: "applying" });
      const r = await fetch(API + "/config", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(toApi(cfg)),
      });
      const j = await r.json();
      if (j.ok) setMsg({ k: "applied", d: new Date().toLocaleTimeString() });
      else setMsg({ k: "applyFailed", d: j.error || "" });
    } catch {
      setMsg({ k: "applyOffline" });
    }
  }, []);

  const anchorRef = useRef<TimerAnchor>({ spec: "", at: 0 });
  const [, setTick] = useState(0);
  useEffect(() => {
    const tmr = setInterval(() => setTick((x) => (x + 1) % 1000000), 250);
    return () => clearInterval(tmr);
  }, []);

  // instant apply for clock buttons; debounced apply for the rest
  const applyTime = useCallback(
    (spec: string) => {
      anchorRef.current = { spec, at: Date.now() };
      const next = { ...config, time: spec };
      setConfig(next);
      applyConfig(next);
    },
    [config, applyConfig]
  );

  useEffect(() => {
    if (skipNextApply.current) {
      skipNextApply.current = false;
      return;
    }
    if (applyTimer.current) clearTimeout(applyTimer.current);
    applyTimer.current = setTimeout(() => applyConfig(config), 400);
  }, [config, applyConfig]);

  const setSlot = (ring: "cpu" | "gpu", idx: 0 | 1, val: string) => {
    setConfig((c) => ({ ...c, [ring]: idx === 0 ? [val, c[ring][1]] : [c[ring][0], val] }));
  };

  const mode = modeOf(config.time);

  // stopwatch / countdown state derivation
  const swRunning = config.time === "timer" || config.time.startsWith("timer_from:");
  const swPaused = config.time.startsWith("timer_paused:");
  const cdRunning =
    config.time.startsWith("timer_down:") && !config.time.startsWith("timer_down_paused:");
  const cdPaused = config.time.startsWith("timer_down_paused:");

  const swDisplay = displayOf(config.time, anchorRef.current, Date.now());
  const cdDisplay = swDisplay;

  const switchMode = (m: ClockMode) => {
    if (m === "auto") applyTime("auto");
    else if (m === "offset") applyTime((offsetN >= 0 ? "+" : "-") + Math.abs(offsetN));
    else if (m === "fixed") applyTime(`${hhN}:${String(mmN).padStart(2, "0")}`);
    else if (m === "split") applyTime(`split:${config.splitL},${config.splitR}`);
    else if (m === "timer") applyTime("timer_paused:00:00");
    else {
      setDownM(downM);
      setDownS(downS);
      applyTime(`timer_down_paused:${fmt(downM * 60 + downS)}`);
    }
  };

  const [cpuA, cpuB] = ringPreview(config.cpu, "cpu", sensors);
  const [gpuA, gpuB] = ringPreview(config.gpu, "gpu", sensors);

  return (
    <div className="flex h-screen flex-col gap-4 overflow-hidden px-5 py-4">
      {/* toolbar */}
      <div className="flex flex-none items-center justify-between gap-3">
        <span className="text-xs text-slate-600">{t("openInBrowser")}</span>
        <div className="flex items-center gap-3">
          <span className="text-xs text-slate-500">
            {t(msg.k)}
            {msg.d ? " " + msg.d : ""}
          </span>
          <span
            className={
              "inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs " +
              (connected
                ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-300"
                : "border-red-500/30 bg-red-500/10 text-red-300")
            }
          >
            <span
              className={"h-1.5 w-1.5 rounded-full " + (connected ? "bg-emerald-400" : "bg-red-400")}
            />
            {connected ? t("connected") : t("disconnected")}
          </span>
          <Segmented<Lang>
            value={lang}
            options={[
              { v: "zh", label: "中文" },
              { v: "en", label: "EN" },
            ]}
            onChange={changeLang}
          />
        </div>
      </div>

      {/* sensor pipeline warning */}
      {connected && !sensorsActive && (
        <div className="flex-none rounded-xl border border-amber-500/40 bg-amber-500/10 px-4 py-2 text-xs text-amber-300">
          {t("sensorsInactive")}
        </div>
      )}

      {/* hero preview */}
      <div className="flex flex-none items-center justify-between gap-4 rounded-2xl border border-slate-800/80 bg-black px-10 py-4">
        <Gauge label="CPU" a={cpuA} b={cpuB} ring="cpu" />
        <div className="flex flex-col items-center">
          <span className="text-[10px] tracking-[0.35em] text-slate-500">CLOCK</span>
          <div className="mt-1 font-mono text-6xl tracking-[0.15em] text-emerald-300 drop-shadow-[0_0_18px_rgba(52,211,153,0.4)]">
            {show || "--:--"}
          </div>
          <span className="mt-1 text-[11px] text-slate-600">{t("previewHint")}</span>
        </div>
        <Gauge label="GPU" a={gpuA} b={gpuB} ring="gpu" />
      </div>

      {/* controls */}
      <div className="grid min-h-0 flex-1 grid-cols-2 gap-4">
        <div className="flex min-h-0 flex-col gap-4 overflow-y-auto">
          <Panel title={t("refreshRate")}>
            <div className="flex flex-wrap items-center gap-3">
              <Segmented
                value={String(config.interval_ms)}
                options={INTERVALS.map((iv) => ({ v: String(iv), label: iv + "ms" }))}
                onChange={(v) => setConfig((c) => ({ ...c, interval_ms: parseInt(v, 10) }))}
              />
              <span className="text-xs text-slate-500">
                {(Math.round((1000 / config.interval_ms) * 10) / 10).toFixed(1)} {t("timesPerSec")}
              </span>
            </div>
          </Panel>

          <Panel title={t("clock")}>
            <div className="flex flex-col gap-3">
              <Segmented<ClockMode>
                value={mode}
                options={[
                  { v: "auto", label: t("modeAuto") },
                  { v: "offset", label: t("modeOffset") },
                  { v: "fixed", label: t("modeFixed") },
                  { v: "split", label: t("modeSplit") },
                  { v: "timer", label: t("modeTimer") },
                  { v: "timer_down", label: t("modeTimerDown") },
                ]}
                onChange={switchMode}
              />

              {mode === "offset" && (
                <div className="flex items-center gap-2 text-sm text-slate-300">
                  {t("vsSystem")}
                  <NumInput
                    value={offsetN}
                    min={-720}
                    max={720}
                    width="w-24"
                    onChange={(n) => {
                      setOffsetN(n);
                      applyTime((n >= 0 ? "+" : "-") + Math.abs(n));
                    }}
                  />
                  {t("minutesPosAhead")}
                </div>
              )}

              {mode === "fixed" && (
                <div className="flex items-center gap-2 text-sm text-slate-300">
                  {t("showFixed")}
                  <NumInput
                    value={hhN}
                    min={0}
                    max={99}
                    width="w-16"
                    onChange={(n) => {
                      setHhN(n);
                      applyTime(`${n}:${String(mmN).padStart(2, "0")}`);
                    }}
                  />
                  :
                  <NumInput
                    value={mmN}
                    min={0}
                    max={59}
                    width="w-16"
                    onChange={(n) => {
                      setMmN(n);
                      applyTime(`${hhN}:${String(n).padStart(2, "0")}`);
                    }}
                  />
                  <span className="text-xs text-slate-500">{t("hourUpTo99")}</span>
                </div>
              )}

              {mode === "split" && (
                <div className="flex flex-col gap-2">
                  <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                    <div className="flex items-center gap-2">
                      <span className="w-14 text-xs text-slate-500">{t("splitLeft")}</span>
                      <div className="min-w-0 flex-1">
                        <SlotEditor
                          value={config.splitL}
                          live={resolveLive(config.splitL, sensors)}
                          lang={lang}
                          onChange={(v) =>
                            setConfig((c) => ({ ...c, splitL: v, time: `split:${v},${c.splitR}` }))
                          }
                        />
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="w-14 text-xs text-slate-500">{t("splitRight")}</span>
                      <div className="min-w-0 flex-1">
                        <SlotEditor
                          value={config.splitR}
                          live={resolveLive(config.splitR, sensors)}
                          lang={lang}
                          onChange={(v) =>
                            setConfig((c) => ({ ...c, splitR: v, time: `split:${c.splitL},${v}` }))
                          }
                        />
                      </div>
                    </div>
                  </div>
                  <span className="text-xs text-slate-500">{t("splitHint")}</span>
                </div>
              )}

              {mode === "timer" && (
                <div className="flex flex-wrap items-center gap-3">
                  <div className="w-32 font-mono text-3xl tabular-nums text-emerald-300">
                    {swDisplay}
                  </div>
                  <button
                    className={btnPrimary}
                    disabled={swRunning}
                    onClick={() =>
                      applyTime(
                        swPaused && mmssOf(swDisplay) > 0 ? `timer_from:${swDisplay}` : "timer"
                      )
                    }
                  >
                    {swPaused && mmssOf(swDisplay) > 0 ? t("btnResume") : t("btnStart")}
                  </button>
                  <button
                    className={btnGhost}
                    disabled={!swRunning}
                    onClick={() => applyTime(`timer_paused:${swDisplay}`)}
                  >
                    {t("btnPause")}
                  </button>
                  <button className={btnGhost} onClick={() => applyTime("timer_paused:00:00")}>
                    {t("btnReset")}
                  </button>
                </div>
              )}

              {mode === "timer_down" && (
                <div className="flex flex-wrap items-center gap-3">
                  <div className="w-32 font-mono text-3xl tabular-nums text-emerald-300">
                    {cdRunning || cdPaused ? cdDisplay : fmt(downM * 60 + downS)}
                  </div>
                  <label className="flex items-center gap-1.5 text-sm text-slate-400">
                    {t("duration")}
                    <NumInput
                      value={downM}
                      min={0}
                      max={99}
                      width="w-14"
                      onChange={(n) => {
                        setDownM(n);
                        if (cdPaused) applyTime(`timer_down_paused:${fmt(n * 60 + downS)}`);
                      }}
                    />
                    {t("min")}
                    <NumInput
                      value={downS}
                      min={0}
                      max={59}
                      width="w-14"
                      onChange={(n) => {
                        setDownS(n);
                        if (cdPaused) applyTime(`timer_down_paused:${fmt(downM * 60 + n)}`);
                      }}
                    />
                    {t("sec")}
                  </label>
                  <button
                    className={btnPrimary}
                    disabled={cdRunning}
                    onClick={() =>
                      applyTime(
                        cdPaused && mmssOf(cdDisplay) > 0
                          ? `timer_down:${cdDisplay}`
                          : `timer_down:${fmt(downM * 60 + downS)}`
                      )
                    }
                  >
                    {cdPaused && mmssOf(cdDisplay) > 0 ? t("btnResume") : t("btnStart")}
                  </button>
                  <button
                    className={btnGhost}
                    disabled={!cdRunning}
                    onClick={() => applyTime(`timer_down_paused:${cdDisplay}`)}
                  >
                    {t("btnPause")}
                  </button>
                  <button
                    className={btnGhost}
                    onClick={() => applyTime(`timer_down_paused:${fmt(downM * 60 + downS)}`)}
                  >
                    {t("btnReset")}
                  </button>
                </div>
              )}
            </div>
          </Panel>
        </div>

        <div className="flex min-h-0 flex-col gap-4 overflow-y-auto">
          <Panel
            title={t("screenPanel")}
            right={
              <span
                className={
                  "rounded-full border px-2.5 py-0.5 text-xs " +
                  (screenEff === "off"
                    ? "border-red-500/30 bg-red-500/10 text-red-300"
                    : "border-emerald-500/30 bg-emerald-500/10 text-emerald-300")
                }
              >
                {screenEff === "off" ? t("effOff") : t("effOn")}
              </span>
            }
          >
            <div className="flex flex-col gap-3">
              <div className="flex items-center gap-3">
                <span className="w-14 text-sm text-slate-300">{t("powerLabel")}</span>
                <Segmented<"on" | "off">
                  value={config.screen}
                  options={[
                    { v: "on", label: t("screenOn") },
                    { v: "off", label: t("screenOff") },
                  ]}
                  onChange={(v) => setConfig((c) => ({ ...c, screen: v }))}
                />
              </div>
              <div className="flex flex-wrap items-center gap-3">
                <span className="w-14 text-sm text-slate-300">{t("scheduleLabel")}</span>
                <Segmented<"on" | "off">
                  value={config.schEnabled ? "on" : "off"}
                  options={[
                    { v: "on", label: t("schedEnable") },
                    { v: "off", label: t("schedDisable") },
                  ]}
                  onChange={(v) => setConfig((c) => ({ ...c, schEnabled: v === "on" }))}
                />
                {config.schEnabled && (
                  <label className="flex items-center gap-2 text-sm text-slate-400">
                    {t("schedOffLabel")}
                    <input
                      type="time"
                      className={inputCls + " [color-scheme:dark]"}
                      value={config.schOff}
                      onChange={(e) =>
                        setConfig((c) => ({ ...c, schOff: e.target.value || "23:30" }))
                      }
                    />
                    {t("schedOnLabel")}
                    <input
                      type="time"
                      className={inputCls + " [color-scheme:dark]"}
                      value={config.schOn}
                      onChange={(e) => setConfig((c) => ({ ...c, schOn: e.target.value || "07:00" }))}
                    />
                  </label>
                )}
              </div>
            </div>
          </Panel>

          <Panel title={t("cpuRing")} right={<span className="text-xs text-slate-500">{t("topBottom")}</span>}>
            <div className="flex flex-col gap-3">
              <div className="flex items-center gap-2">
                <span className="w-8 text-xs text-slate-500">{t("top")}</span>
                <div className="flex-1">
                  <SlotEditor
                    value={config.cpu[0]}
                    live={cpuA}
                    lang={lang}
                    onChange={(v) => setSlot("cpu", 0, v)}
                  />
                </div>
              </div>
              <div className="flex items-center gap-2">
                <span className="w-8 text-xs text-slate-500">{t("bottom")}</span>
                <div className="flex-1">
                  <SlotEditor
                    value={config.cpu[1]}
                    live={cpuB}
                    lang={lang}
                    onChange={(v) => setSlot("cpu", 1, v)}
                  />
                </div>
              </div>
            </div>
          </Panel>

          <Panel title={t("gpuRing")} right={<span className="text-xs text-slate-500">{t("topBottom")}</span>}>
            <div className="flex flex-col gap-3">
              <div className="flex items-center gap-2">
                <span className="w-8 text-xs text-slate-500">{t("top")}</span>
                <div className="flex-1">
                  <SlotEditor
                    value={config.gpu[0]}
                    live={gpuA}
                    lang={lang}
                    onChange={(v) => setSlot("gpu", 0, v)}
                  />
                </div>
              </div>
              <div className="flex items-center gap-2">
                <span className="w-8 text-xs text-slate-500">{t("bottom")}</span>
                <div className="flex-1">
                  <SlotEditor
                    value={config.gpu[1]}
                    live={gpuB}
                    lang={lang}
                    onChange={(v) => setSlot("gpu", 1, v)}
                  />
                </div>
              </div>
            </div>
          </Panel>
        </div>
      </div>
    </div>
  );
}
