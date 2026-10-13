using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

namespace XkScreen.Service
{
    /// <summary>
    /// XkScreen resident driver, C# port of the proven PowerShell script.
    /// Loads the official XKWLib chain, drives every frame itself and applies
    /// per-slot data-source overrides + clock control from config.json.
    /// M1: console prototype (run elevated). Service hosting comes in M3.
    /// </summary>
    internal static class Program
    {
        // The vendor directory that provides XKWLib.dll / TempComm.dll / HardwareHelp64.dll
        // / cpuidsdk64.dll (the components installed by the original software). Override
        // with --official-dir <path> or the XKSCREEN_VENDOR_DIR environment variable; a
        // "vendor" folder next to this exe is used when it contains XKWLib.dll.
        private static string officialDir = @"D:\Code\Xingcan-Xiaolan-Drive\official";

        [DllImport("psapi.dll")]
        private static extern bool EmptyWorkingSet(IntPtr hProcess);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        private static MethodInfo miStart;
        private static MethodInfo miSetCpuDyn;
        private static MethodInfo miSetGpuDyn;
        private static MethodInfo miSetDeviceTime;

        /// <summary>Effective screen power state (true = frames paused, display dark).</summary>
        private static bool screenOffState;

        /// <summary>Last clock-area content actually sent to the screen (HH:MM display string).</summary>
        internal static string LastShow = "";

        /// <summary>Sensor cache for fast animation ticks (re-read at most ~1/s).</summary>
        private static Dictionary<string, double> lastSensors;
        private static DateTime lastHeavyMs = DateTime.MinValue;

        /// <summary>Previous countdown value, for one-shot effects on 00:00.</summary>
        private static int lastRemainSec;

        /// <summary>Hardware sampling cadence (our own, replacing the vendor thread).</summary>
        private static DateTime nextSampleAt = DateTime.MinValue;

        /// <summary>Cycles between official CPU/GPU frames (≈1 s worth).</summary>
        private static int officialCycle;
        private static int officialEvery = 2;

        /// <summary>Stopwatch / countdown state (reset whenever the spec string changes).</summary>
        private sealed class TimerState
        {
            public string LastSpec = "";
            public DateTime T0 = DateTime.MinValue;
            public int BaseSec;
        }
        private static readonly TimerState Timer = new TimerState();

        private static int Main(string[] args)
        {
            Log.Init();
            Log.Write("XkScreen.Service start (M1 prototype)");
            // Single-instance guard: the HTTP port is the ownership token for the
            // panel. An upgrade install (or a stray second start) must not let a
            // second process drive the same USB device while this one does.
            if (PortServed())
            {
                Log.Write("127.0.0.1:8899 already served - another driver owns the panel; exit 1");
                return 1;
            }
            try
            {
                bool dirExplicit = false;
                for (int a = 0; a < args.Length; a++)
                {
                    if (args[a] == "--official-dir" && a + 1 < args.Length)
                    {
                        officialDir = args[a + 1];
                        dirExplicit = true;
                    }
                }
                if (!dirExplicit)
                {
                    string env = Environment.GetEnvironmentVariable("XKSCREEN_VENDOR_DIR");
                    if (!string.IsNullOrEmpty(env)) { officialDir = env; dirExplicit = true; }
                }
                if (!dirExplicit)
                {
                    string vendor = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "vendor");
                    if (File.Exists(Path.Combine(vendor, "XKWLib.dll"))) officialDir = vendor;
                }
                if (!File.Exists(Path.Combine(officialDir, "XKWLib.dll")))
                {
                    Log.Write("WARN: XKWLib.dll not found under " + officialDir
                        + " - use --official-dir <path> or set XKSCREEN_VENDOR_DIR");
                }

                Directory.SetCurrentDirectory(officialDir);

                Assembly xkwAsm = Assembly.LoadFrom(Path.Combine(officialDir, "XKWLib.dll"));
                Type tHelp = xkwAsm.GetType("XKWLib.XKWLibHelp", true);
                Type tWrap = xkwAsm.GetType("XKWLib.DllWrapper", true);

                miStart = tHelp.GetMethod("Start");
                miSetCpuDyn = tWrap.GetMethod("SetCpuDynamicInfo");
                miSetGpuDyn = tWrap.GetMethod("SetGpuDynamicInfo");
                miSetDeviceTime = tWrap.GetMethod("SetDeviceTime");
                FieldInfo fiSendDelay = tHelp.GetField("usb_send_delay", BindingFlags.NonPublic | BindingFlags.Instance);

                object help = Activator.CreateInstance(tHelp);

                bool ok = false;
                for (int attempt = 1; attempt <= 30; attempt++)
                {
                    try { ok = (bool)miStart.Invoke(help, new object[] { "SystemTemperatureMonitoring" }); }
                    catch (Exception ex) { Log.Write("Start exc: " + ex.Message); ok = false; }
                    if (ok) break;
                    Log.Write("Start attempt " + attempt + "/30 failed, retry in 10s");
                    Thread.Sleep(10000);
                }
                if (!ok) { Log.Write("Start failed x30, exit 1"); return 1; }
                Log.Write("Start ok");

                // Shut the internal auto-send thread down first: it keeps injecting
                // one real-data frame every usb_send_delay ms behind our back, which
                // made the display light up briefly while "screen off" paused our own
                // frames (the periodic relight bug).
                try
                {
                    FieldInfo fiThread = tHelp.GetField("thread_flag", BindingFlags.NonPublic | BindingFlags.Instance);
                    if (fiThread != null)
                    {
                        fiThread.SetValue(help, false);
                        Log.Write("internal send thread disabled (thread_flag=false)");
                    }
                    else Log.Write("WARN: thread_flag field not found");
                }
                catch (Exception tex) { Log.Write("thread_flag disable exc: " + tex.Message); }

                // Let any in-flight vendor init call finish before we touch the SDK:
                // concurrent native Init2 calls crash with AccessViolationException.
                Thread.Sleep(1500);

                // Deterministic sensor init. The vendor initializes its hardware
                // lazily inside the send thread we just stopped (`if (!hardware.
                // InitState && !hardware.Start()) { sleep; retry; }`), and the
                // one-shot Start() inside XKWLibHelp.Start() usually fails on the
                // first attempt - so we finish the init ourselves here, on our own
                // thread. InitState only stays false when the CPUID kernel driver
                // cannot be loaded ("Driver error 5" = access denied): that needs an
                // elevated / SYSTEM process (the boot-time scheduled task).
                object hwObj = null;
                try
                {
                    FieldInfo fiHw = tHelp.GetField("hardware", BindingFlags.NonPublic | BindingFlags.Instance);
                    hwObj = fiHw != null ? fiHw.GetValue(help) : null;
                }
                catch { }
                bool inited = false;
                int initAttempt = 0;
                if (hwObj != null)
                {
                    PropertyInfo piInit = hwObj.GetType().GetProperty("InitState");
                    MethodInfo miHwStart = hwObj.GetType().GetMethod("Start");
                    for (initAttempt = 1; initAttempt <= 40; initAttempt++)
                    {
                        inited = piInit != null && (bool)piInit.GetValue(hwObj, null);
                        if (inited) break;
                        try { miHwStart.Invoke(hwObj, null); }
                        catch (Exception iex) { Log.Write("sensor init exc: " + iex.Message); }
                        Thread.Sleep(250);
                    }
                    Log.Write(inited
                        ? "sensor init ok (attempts=" + initAttempt + ")"
                        : "WARN: sensor init failed x40 - CPUID driver not loaded (run elevated/SYSTEM)");

                // Take over the sampling cadence. The vendor DLL's refresh thread runs a
                // full WMI/CPUID sampling pass every second - it is the driver's single
                // biggest CPU cost (~10 % of one core). Stop it and let the main loop
                // call the sampling on its own schedule (1 s / 5 s while the screen is
                // off). CloseRefresh aborts the vendor thread, so run it off-thread.
                try
                {
                    MethodInfo miClose = hwObj.GetType().GetMethod("CloseRefresh");
                    if (miClose != null)
                    {
                        Thread closeThread = new Thread(delegate ()
                        {
                            try
                            {
                                miClose.Invoke(hwObj, null);
                                Log.Write("vendor refresh thread stopped; sampling on our cadence");
                            }
                            catch (Exception cex) { Log.Write("CloseRefresh exc: " + cex.Message); }
                        });
                        closeThread.IsBackground = true;
                        closeThread.Start();
                    }
                    else Log.Write("WARN: CloseRefresh not found");
                }
                catch (Exception rex) { Log.Write("refresh takeover exc: " + rex.Message); }
                }
                else Log.Write("WARN: hardware field not found, sensor init skipped");

                if (fiSendDelay != null)
                {
                    fiSendDelay.SetValue(help, 120000);
                    Log.Write("helper send_delay -> 120s (paused)");
                }
                else Log.Write("WARN: usb_send_delay not found");

                Sensors.Init(help);
                Config.EnsureDefault();
                Log.Write("config: " + Config.ConfigPath);
                StartHttpApi();

                // Verify the sensor pipeline actually publishes values (the refresh
                // thread needs one full cycle after a fresh init). This is the
                // startup evidence that the screen will show real data.
                try
                {
                    bool flow = false;
                    for (int v = 0; v < 20 && !flow; v++)
                    {
                        Sensors.Sample(); // drive the sampling ourselves
                        Dictionary<string, double> probe = Sensors.GetSensors();
                        flow = probe.ContainsKey("cpu_load");
                        if (!flow) Thread.Sleep(1000);
                    }
                    Log.Write(flow ? "sensor data flowing" : "WARN: no sensor data after 20s");
                }
                catch (Exception vex) { Log.Write("sensor verify exc: " + vex.Message); }

                // Trim the working set once the startup phase has settled: cold init
                // pages (CPUid SDK setup etc.) are released and fault back on demand.
                // Re-trim periodically so the idle driver keeps a small footprint.
                Thread trimmer = new Thread(delegate ()
                {
                    try
                    {
                        Thread.Sleep(60000);
                        while (true)
                        {
                            EmptyWorkingSet(GetCurrentProcess());
                            Thread.Sleep(600000);
                        }
                    }
                    catch { }
                });
                trimmer.IsBackground = true;
                trimmer.Start();

                int i = 0;
                while (true)
                {
                    int interval = 500;
                    string timeSpec = null;
                    int effTickMs = 0;
                    try
                    {
                        Config cfg = Config.Load();
                        interval = cfg.IntervalMs;
                        timeSpec = cfg.Time;
                        officialEvery = Math.Max(1, 1000 / Math.Max(1, interval));

                        // Hardware sampling cadence (we drive the vendor DLL's sampling
                        // ourselves): 1 s normally, 5 s while the screen is dark - nothing
                        // is displayed then, so the driver can idle at ~0 % CPU.
                        if (DateTime.Now >= nextSampleAt)
                        {
                            Sensors.Sample();
                            nextSampleAt = DateTime.Now.AddMilliseconds(screenOffState ? 5000 : 1000);
                        }

                        // Screen power: master switch + optional daily off-window.
                        // Pausing all frames blanks the display (it has no power-loss
                        // hold); resuming re-arms the device first.
                        bool offNow = IsScreenOff(cfg, DateTime.Now);
                        if (offNow != screenOffState)
                        {
                            screenOffState = offNow;
                            if (screenOffState)
                            {
                                Log.Write("screen OFF - frames paused");
                            }
                            else
                            {
                                Log.Write("screen ON - resuming");
                                if (cfg.EffectOnScreenOn == "steinsgate" || cfg.EffectOnScreenOn == "boot")
                                {
                                    Effects.StartOneShot(cfg.EffectOnScreenOn, "all", 2600, 90);
                                    Log.Write("effect on screen-on: " + cfg.EffectOnScreenOn);
                                }
                            }
                        }

                        if (!screenOffState)
                        {
                            // Animation layer: an effect drives the six digit cells at its
                            // own fast tick, while real sensor reads (and the official
                            // CPU/GPU frames) slow down to the SDK's 1 Hz refresh rate.
                            bool effActive = Effects.Active(cfg.Effect);
                            bool heavy = !effActive || (DateTime.Now - lastHeavyMs).TotalMilliseconds >= 900;
                            if (heavy)
                            {
                                lastSensors = Sensors.GetSensors();
                                lastHeavyMs = DateTime.Now;

                                // The official CPU/GPU frames carry the per-core/per-GPU
                                // values the SDK refreshes at ~1 Hz anyway, so send them
                                // about once per second; the time frame keeps flowing every
                                // cycle (that is the frame the display latches onto).
                                if (++officialCycle % officialEvery == 0)
                                {
                                    byte[] cpuArr = Sensors.BuildCpuArray();
                                    if (cpuArr != null) miSetCpuDyn.Invoke(null, new object[] { cpuArr, (uint)cpuArr.Length });
                                    byte[] gpuArr = Sensors.BuildGpuArray();
                                    if (gpuArr != null) miSetGpuDyn.Invoke(null, new object[] { gpuArr, (uint)gpuArr.Length });
                                }
                            }
                            Dictionary<string, double> sensors = lastSensors != null ? lastSensors : Sensors.GetSensors();

                            byte[] rc = BuildRing(cfg.Cpu, sensors, "cpu");
                            byte[] rg = BuildRing(cfg.Gpu, sensors, "gpu");
                            byte[] tframe = BuildTimeFrame(cfg.Time, sensors);
                            byte[] tbase = tframe != null ? tframe : TimeBytesFromDateTime(DateTime.Now);

                            if (effActive)
                            {
                                int[] baseCells = new int[6];
                                baseCells[0] = Sensors.ResolveSlot(SlotOr(cfg.Cpu, 0, "cpu_load"), sensors);
                                baseCells[1] = Sensors.ResolveSlot(SlotOr(cfg.Cpu, 1, "cpu_temp"), sensors);
                                baseCells[2] = Sensors.ResolveSlot(SlotOr(cfg.Gpu, 0, "gpu_load"), sensors);
                                baseCells[3] = Sensors.ResolveSlot(SlotOr(cfg.Gpu, 1, "gpu_temp"), sensors);
                                baseCells[4] = tbase[5];
                                baseCells[5] = tbase[6];
                                int[] outCells = new int[6];
                                Effects.Step(cfg.Effect, cfg.EffectTarget, baseCells, outCells);

                                string effTarget = Effects.EffectiveTarget(cfg.EffectTarget);
                                if (effTarget == "rings" || effTarget == "all")
                                {
                                    rc = RingFrame(outCells[0], outCells[1]);
                                    rg = RingFrame(outCells[2], outCells[3]);
                                }
                                if (effTarget == "clock" || effTarget == "all")
                                {
                                    byte[] tf = new byte[9];
                                    tf[0] = tbase[0]; tf[1] = tbase[1]; tf[2] = tbase[2];
                                    tf[3] = tbase[3]; tf[4] = tbase[4];
                                    tf[5] = (byte)outCells[4];
                                    tf[6] = (byte)outCells[5];
                                    tframe = tf;
                                }
                                effTickMs = Effects.SpeedMs(cfg.EffectSpeedMs);
                            }

                            if (rc != null) miSetCpuDyn.Invoke(null, new object[] { rc, (uint)8 });
                            if (rg != null) miSetGpuDyn.Invoke(null, new object[] { rg, (uint)8 });
                            Flush(tframe);

                            // Countdown end: fire the configured one-shot exactly once,
                            // when the displayed MM:SS reaches 00:00.
                            if (cfg.EffectOnTimerEnd != "none" && timeSpec != null
                                && timeSpec.StartsWith("timer_down") && !timeSpec.Contains("paused"))
                            {
                                int remain = Timer.BaseSec - (int)(DateTime.Now - Timer.T0).TotalSeconds;
                                if (remain <= 0 && lastRemainSec > 0)
                                {
                                    Effects.StartOneShot(cfg.EffectOnTimerEnd, "all", 2600, 90);
                                    Log.Write("effect on timer end: " + cfg.EffectOnTimerEnd);
                                }
                                lastRemainSec = remain;
                            }

                            byte[] shown = tframe != null ? tframe : TimeBytesFromDateTime(DateTime.Now);
                            LastShow = ((int)shown[5]).ToString("00") + ":" + ((int)shown[6]).ToString("00");
                        }

                        i++;
                        if (i % 40 == 0)
                            Log.Write("alive i=" + i + " " + cfg.Describe()
                                + (screenOffState ? " screen:OFF" : ""));
                    }
                    catch (Exception ex) { Log.Write("loop exc: " + ex.Message); }

                    // Running timers show a seconds digit (MM:SS). Wake the loop just
                    // after each displayed-second boundary so the screen ticks crisply
                    // instead of sometimes lagging up to half an interval behind.
                    // (Skipped while the screen is off - there are no frames to align.)
                    int sleepMs = interval;
                    try
                    {
                        if (!screenOffState && effTickMs > 0)
                        {
                            sleepMs = effTickMs;
                        }
                        else if (!screenOffState && timeSpec != null && timeSpec.StartsWith("timer") && !timeSpec.Contains("paused"))
                        {
                            double elapsedMs = (DateTime.Now - Timer.T0).TotalMilliseconds;
                            double toBoundary = 1000.0 - (elapsedMs % 1000.0);
                            sleepMs = (int)Math.Max(150, Math.Min(interval, toBoundary + 30));
                        }
                    }
                    catch { }
                    Thread.Sleep(sleepMs);
                }
            }
            catch (Exception ex)
            {
                Log.Write("fatal: " + ex.ToString());
                return 1;
            }
        }

        private static bool PairNeedsSensors(string[] pair)
        {
            if (pair == null) return false;
            for (int i = 0; i < pair.Length; i++)
            {
                string t = pair[i];
                if (string.IsNullOrEmpty(t)) continue;
                if (t == "auto") continue;
                int dummy;
                if (!int.TryParse(t, out dummy)) return true;
            }
            return false;
        }

        private static byte[] BuildRing(string[] pair, Dictionary<string, double> sensors, string kind)
        {
            if (pair == null || pair.Length < 2) return null;
            if (pair[0] == "auto" && pair[1] == "auto") return null;
            string d0 = kind == "cpu" ? "cpu_load" : "gpu_load";
            string d1 = kind == "cpu" ? "cpu_temp" : "gpu_temp";
            byte[] b = new byte[8];
            b[0] = Sensors.ResolveSlot(pair[0] == "auto" ? d0 : pair[0], sensors);
            b[1] = Sensors.ResolveSlot(pair[1] == "auto" ? d1 : pair[1], sensors);
            b[2] = 0x24; b[3] = 0x13;
            return b;
        }

        /// <summary>Ring override frame with explicit values (animation layer).</summary>
        private static byte[] RingFrame(int top, int bottom)
        {
            byte[] b = new byte[8];
            b[0] = (byte)Math.Max(0, Math.Min(99, top));
            b[1] = (byte)Math.Max(0, Math.Min(99, bottom));
            b[2] = 0x24; b[3] = 0x13;
            return b;
        }

        /// <summary>Config slot token, with the "auto" default token substitution.</summary>
        private static string SlotOr(string[] pair, int idx, string dflt)
        {
            if (pair == null || pair.Length <= idx) return dflt;
            string t = pair[idx];
            if (string.IsNullOrEmpty(t) || t == "auto") return dflt;
            return t;
        }

        /// <summary>
        /// Build the 9-byte time frame for the given spec, or null for "auto" (real time).
        /// Specs: auto | +N | -N | HH:MM (hour 0-99 accepted) | timer | timer_from:MM:SS |
        /// timer_paused:MM:SS | timer_down:MM:SS | timer_down_paused:MM:SS | split:L,R
        /// ("split" drives the clock's two 2-digit groups independently from any data
        /// source or fixed value - the colon between them is firmware-drawn).
        /// The screen clock area renders the frame's hour+minute bytes; timer modes
        /// put MM into the hour slot and SS into the minute slot to show MM:SS.
        /// </summary>
        private static byte[] BuildTimeFrame(string spec, Dictionary<string, double> sensors)
        {
            if (string.IsNullOrEmpty(spec) || spec == "auto") return null;
            try
            {
                DateTime now = DateTime.Now;
                if (spec.StartsWith("split:"))
                {
                    string[] toks = spec.Substring("split:".Length).Split(',');
                    if (toks.Length == 2)
                    {
                        byte[] t = new byte[9];
                        t[0] = (byte)(now.Year / 100);
                        t[1] = (byte)(now.Year % 100);
                        t[2] = (byte)now.Month;
                        t[3] = (byte)now.Day;
                        t[4] = (byte)(int)now.DayOfWeek;
                        t[5] = Sensors.ResolveSlot(toks[0].Trim(), sensors); // left two digits
                        t[6] = Sensors.ResolveSlot(toks[1].Trim(), sensors); // right two digits
                        t[7] = 0;
                        t[8] = 0;
                        return t;
                    }
                }
                if (spec.Length > 1 && (spec[0] == '+' || spec[0] == '-'))
                {
                    int mins;
                    if (int.TryParse(spec.Substring(1), out mins))
                        return TimeBytesFromDateTime(now.AddMinutes(spec[0] == '-' ? -mins : mins));
                    return null;
                }
                if (spec == "timer")
                {
                    if (Timer.LastSpec != spec) { Timer.LastSpec = spec; Timer.T0 = now; }
                    int total = (int)(now - Timer.T0).TotalSeconds;
                    return TimeBytesFromMmSs(total);
                }
                if (spec.StartsWith("timer_from:"))
                {
                    if (Timer.LastSpec != spec)
                    {
                        Timer.LastSpec = spec;
                        Timer.T0 = now.AddSeconds(-ParseMmSs(spec.Substring("timer_from:".Length)));
                    }
                    int total = (int)(now - Timer.T0).TotalSeconds;
                    return TimeBytesFromMmSs(total);
                }
                if (spec.StartsWith("timer_paused:") || spec.StartsWith("timer_down_paused:"))
                {
                    string v = spec.StartsWith("timer_paused:")
                        ? spec.Substring("timer_paused:".Length)
                        : spec.Substring("timer_down_paused:".Length);
                    return TimeBytesFromMmSs(ParseMmSs(v));
                }
                if (spec.StartsWith("timer_down:"))
                {
                    if (Timer.LastSpec != spec)
                    {
                        Timer.LastSpec = spec;
                        Timer.T0 = now;
                        Timer.BaseSec = ParseMmSs(spec.Substring("timer_down:".Length));
                    }
                    int total = Timer.BaseSec - (int)(now - Timer.T0).TotalSeconds;
                    if (total < 0) total = 0;
                    return TimeBytesFromMmSs(total);
                }
                string[] parts = spec.Split(':');
                if (parts.Length == 2)
                {
                    int h; int m;
                    if (int.TryParse(parts[0], out h) && int.TryParse(parts[1], out m) && h >= 0 && h <= 99 && m >= 0 && m <= 59)
                        return TimeBytesFixed(now, h, m);
                }
            }
            catch { }
            return null;
        }

        private static int ParseMmSs(string s)
        {
            try
            {
                string[] parts = s.Split(':');
                if (parts.Length == 2)
                {
                    int m; int sec;
                    if (int.TryParse(parts[0], out m) && int.TryParse(parts[1], out sec) && m >= 0 && m <= 99 && sec >= 0 && sec <= 59)
                        return m * 60 + sec;
                }
            }
            catch { }
            return 0;
        }

        private static byte[] TimeBytesFromMmSs(int totalSec)
        {
            if (totalSec < 0) totalSec = 0;
            if (totalSec > 99 * 60 + 59) totalSec = 99 * 60 + 59;
            DateTime n = DateTime.Now;
            byte[] t = new byte[9];
            t[0] = (byte)(n.Year / 100);
            t[1] = (byte)(n.Year % 100);
            t[2] = (byte)n.Month;
            t[3] = (byte)n.Day;
            t[4] = (byte)(int)n.DayOfWeek;
            t[5] = (byte)(totalSec / 60);   // shown in the hour slot  -> timer minutes
            t[6] = (byte)(totalSec % 60);   // shown in the minute slot -> timer seconds
            t[7] = 0;
            t[8] = 0;
            return t;
        }

        private static byte[] TimeBytesFixed(DateTime n, int h, int m)
        {
            byte[] t = new byte[9];
            t[0] = (byte)(n.Year / 100);
            t[1] = (byte)(n.Year % 100);
            t[2] = (byte)n.Month;
            t[3] = (byte)n.Day;
            t[4] = (byte)(int)n.DayOfWeek;
            t[5] = (byte)h;
            t[6] = (byte)m;
            t[7] = (byte)n.Second;
            t[8] = (byte)(n.Millisecond / 10);
            return t;
        }

        private static byte[] TimeBytesFromDateTime(DateTime n)
        {
            byte[] t = new byte[9];
            t[0] = (byte)(n.Year / 100);
            t[1] = (byte)(n.Year % 100);
            t[2] = (byte)n.Month;
            t[3] = (byte)n.Day;
            t[4] = (byte)(int)n.DayOfWeek;
            t[5] = (byte)n.Hour;
            t[6] = (byte)n.Minute;
            t[7] = (byte)n.Second;
            t[8] = (byte)(n.Millisecond / 10);
            return t;
        }

        private static void Flush(byte[] t)
        {
            if (t == null) t = TimeBytesFromDateTime(DateTime.Now);
            miSetDeviceTime.Invoke(null, new object[] { t, (uint)9 });
        }

        /// <summary>Parse "HH:MM" into minutes-since-midnight, or -1 when invalid.</summary>
        private static int ParseHHMM(string s)
        {
            try
            {
                string[] p = s.Split(':');
                if (p.Length == 2)
                {
                    int h; int m;
                    if (int.TryParse(p[0], out h) && int.TryParse(p[1], out m) && h >= 0 && h <= 23 && m >= 0 && m <= 59)
                        return h * 60 + m;
                }
            }
            catch { }
            return -1;
        }

        /// <summary>
        /// Effective screen power: manual master switch OR inside the daily
        /// off-window (off time -> on time, wrapping midnight when needed).
        /// </summary>
        private static bool IsScreenOff(Config cfg, DateTime now)
        {
            if (cfg.Screen == "off") return true;
            int offM = ParseHHMM(cfg.ScheduleOff ?? "");
            int onM = ParseHHMM(cfg.ScheduleOn ?? "");
            if (offM >= 0 && onM >= 0 && offM != onM)
            {
                int nowM = now.Hour * 60 + now.Minute;
                if (offM < onM) return nowM >= offM && nowM < onM;
                return nowM >= offM || nowM < onM;
            }
            return false;
        }

        // ---- single-instance guard ----
        // True when something already answers on our API port. A bare TCP probe is
        // used on purpose: HttpListener's own failure codes cannot distinguish
        // "port taken" from "URL ACL missing", and the latter must keep working.
        private static bool PortServed()
        {
            try
            {
                using (System.Net.Sockets.TcpClient c = new System.Net.Sockets.TcpClient())
                {
                    IAsyncResult ar = c.BeginConnect("127.0.0.1", 8899, null, null);
                    if (!ar.AsyncWaitHandle.WaitOne(400)) return false;
                    c.EndConnect(ar);
                    return true;
                }
            }
            catch { return false; }
        }

        // ---- local HTTP API (for the GUI): 127.0.0.1:8899 ----
        // GET  /status  -> { ok, config:{cpu,gpu,time,interval_ms}, sensors:{...} }
        // POST /config  -> validate + save config json, { ok } or { ok:false, error }

        private static void StartHttpApi()
        {
            try
            {
                HttpListener listener = new HttpListener();
                listener.Prefixes.Add("http://127.0.0.1:8899/");
                listener.Start();
                Thread t = new Thread(delegate () { HttpLoop(listener); });
                t.IsBackground = true;
                t.Start();
                Log.Write("http api on http://127.0.0.1:8899/");
            }
            catch (Exception ex) { Log.Write("http api start exc: " + ex.Message); }
        }

        private static void HttpLoop(HttpListener listener)
        {
            while (true)
            {
                HttpListenerContext ctx = null;
                try { ctx = listener.GetContext(); }
                catch { break; }
                try { HandleRequest(ctx); }
                catch (Exception ex)
                {
                    try { Log.Write("http exc: " + ex.Message); } catch { }
                    try { ctx.Response.StatusCode = 500; ctx.Response.Close(); } catch { }
                }
            }
        }

        private static void HandleRequest(HttpListenerContext ctx)
        {
            HttpListenerRequest req = ctx.Request;
            HttpListenerResponse res = ctx.Response;
            res.Headers["Access-Control-Allow-Origin"] = "*";
            res.Headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS";
            res.Headers["Access-Control-Allow-Headers"] = "Content-Type";

            if (req.HttpMethod == "OPTIONS") { res.StatusCode = 204; res.Close(); return; }

            string path = req.Url.AbsolutePath.ToLowerInvariant();

            if (req.HttpMethod == "GET" && path == "/status")
            {
                Dictionary<string, object> cfgDict = new Dictionary<string, object>();
                try
                {
                    Config cfg = Config.Load();
                    cfgDict["cpu"] = cfg.Cpu != null ? (object)cfg.Cpu : new string[] { "auto", "auto" };
                    cfgDict["gpu"] = cfg.Gpu != null ? (object)cfg.Gpu : new string[] { "auto", "auto" };
                    cfgDict["time"] = cfg.Time;
                    cfgDict["interval_ms"] = cfg.IntervalMs;
                    cfgDict["screen"] = cfg.Screen;
                    cfgDict["effect"] = cfg.Effect;
                    cfgDict["effect_target"] = cfg.EffectTarget;
                    cfgDict["effect_speed_ms"] = cfg.EffectSpeedMs;
                    cfgDict["effect_on_screen_on"] = cfg.EffectOnScreenOn;
                    cfgDict["effect_on_timer_end"] = cfg.EffectOnTimerEnd;
                    if (!string.IsNullOrEmpty(cfg.ScheduleOff) && !string.IsNullOrEmpty(cfg.ScheduleOn))
                    {
                        Dictionary<string, object> sd = new Dictionary<string, object>();
                        sd["off"] = cfg.ScheduleOff;
                        sd["on"] = cfg.ScheduleOn;
                        cfgDict["schedule"] = sd;
                    }
                }
                catch { }

                Dictionary<string, object> sensors = new Dictionary<string, object>();
                try
                {
                    Dictionary<string, double> s = Sensors.GetSensors();
                    foreach (KeyValuePair<string, double> kv in s) sensors[kv.Key] = Math.Round(kv.Value, 1);
                }
                catch { }

                Dictionary<string, object> root = new Dictionary<string, object>();
                root["ok"] = true;
                root["config"] = cfgDict;
                root["sensors"] = sensors;
                root["show"] = LastShow;
                root["screen"] = screenOffState ? "off" : "on";
                root["sensors_active"] = sensors.ContainsKey("cpu_load");
                try
                {
                    Config cfg2 = Config.Load();
                    root["effect"] = cfg2.Effect;
                    root["effect_target"] = cfg2.EffectTarget;
                    root["effect_oneshot"] = Effects.OneShot;
                    root["effect_active"] = Effects.Active(cfg2.Effect);
                }
                catch { }
                WriteJson(res, root);
                return;
            }

            if (req.HttpMethod == "POST" && path == "/effect")
            {
                string body;
                using (StreamReader sr = new StreamReader(req.InputStream, Encoding.UTF8))
                    body = sr.ReadToEnd();

                Dictionary<string, object> resp = new Dictionary<string, object>();
                try
                {
                    JavaScriptSerializer fxSer = new JavaScriptSerializer();
                    Dictionary<string, object> fx = fxSer.Deserialize<Dictionary<string, object>>(body);
                    string name = fx != null && fx.ContainsKey("name") ? Convert.ToString(fx["name"]).Trim().ToLowerInvariant() : "";
                    if (name == "stop" || name == "off" || name == "none")
                    {
                        Effects.StopOneShot();
                        resp["ok"] = true;
                    }
                    else if (!Effects.IsValidOneShot(name))
                    {
                        resp["ok"] = false;
                        resp["error"] = "unknown effect (steinsgate | boot | burst | stop)";
                    }
                    else
                    {
                        string target = fx.ContainsKey("target") ? Convert.ToString(fx["target"]).Trim().ToLowerInvariant() : "all";
                        if (!Effects.IsValidTarget(target)) { resp["ok"] = false; resp["error"] = "bad target (clock | rings | all)"; }
                        else
                        {
                            int dur = 3000;
                            if (fx.ContainsKey("duration_ms"))
                                int.TryParse(Convert.ToString(fx["duration_ms"]), out dur);
                            int spd = 90;
                            if (fx.ContainsKey("speed_ms"))
                                int.TryParse(Convert.ToString(fx["speed_ms"]), out spd);
                            Effects.StartOneShot(name, target, dur, spd);
                            Log.Write("one-shot effect: " + name + " target:" + target + " " + dur + "ms/" + spd + "ms");
                            resp["ok"] = true;
                        }
                    }
                }
                catch (Exception fex) { resp["ok"] = false; resp["error"] = "exc: " + fex.Message; }
                WriteJson(res, resp);
                return;
            }

            if (req.HttpMethod == "GET" && path == "/perf")
            {
                Dictionary<string, object> root = new Dictionary<string, object>();
                root["ok"] = true;
                try
                {
                    System.Diagnostics.Stopwatch sw = System.Diagnostics.Stopwatch.StartNew();
                    for (int k = 0; k < 5; k++) Sensors.Sample();
                    root["sample_ms"] = Math.Round(sw.Elapsed.TotalMilliseconds / 5, 2);

                    sw.Restart();
                    for (int k = 0; k < 20; k++) Sensors.GetSensors();
                    root["getSensors_ms"] = Math.Round(sw.Elapsed.TotalMilliseconds / 20, 2);

                    sw.Restart();
                    for (int k = 0; k < 20; k++) Sensors.BuildCpuArray();
                    root["buildCpu_ms"] = Math.Round(sw.Elapsed.TotalMilliseconds / 20, 2);

                    sw.Restart();
                    for (int k = 0; k < 20; k++) Sensors.BuildGpuArray();
                    root["buildGpu_ms"] = Math.Round(sw.Elapsed.TotalMilliseconds / 20, 2);

                    sw.Restart();
                    for (int k = 0; k < 50; k++) Config.Load();
                    root["config_ms"] = Math.Round(sw.Elapsed.TotalMilliseconds / 50, 3);

                    Config pc = Config.Load();
                    root["interval_ms"] = pc.IntervalMs;
                    root["officialEvery"] = officialEvery;
                }
                catch (Exception pex) { root["error"] = pex.Message; }
                WriteJson(res, root);
                return;
            }

            if (req.HttpMethod == "POST" && path == "/config")
            {
                string body;
                using (StreamReader sr = new StreamReader(req.InputStream, Encoding.UTF8))
                    body = sr.ReadToEnd();

                string err = Config.SaveValidated(body);
                Dictionary<string, object> resp = new Dictionary<string, object>();
                if (err == null) resp["ok"] = true;
                else { resp["ok"] = false; resp["error"] = err; }
                WriteJson(res, resp);
                return;
            }

            if (req.HttpMethod == "GET" && path == "/raw")
            {
                Dictionary<string, object> root = new Dictionary<string, object>();
                root["ok"] = true;
                root["raw"] = Sensors.DumpRaw();
                WriteJson(res, root);
                return;
            }

            if (req.HttpMethod == "GET" && path == "/sensors")
            {
                Dictionary<string, object> root = new Dictionary<string, object>();
                root["ok"] = true;
                root["sensors"] = Sensors.DumpSdkSensors();
                WriteJson(res, root);
                return;
            }

            // Static UI: serve the built frontend from the "web" folder next to the
            // service, so the console is also usable from any browser at
            // http://127.0.0.1:8899/ (same-origin, no CORS involved).
            if ((req.HttpMethod == "GET" || req.HttpMethod == "HEAD") && TryServeStatic(req, res)) return;

            res.StatusCode = 404;
            res.Close();
        }

        private static bool TryServeStatic(HttpListenerRequest req, HttpListenerResponse res)
        {
            try
            {
                string root = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "web");
                if (!Directory.Exists(root)) return false;

                string urlPath = req.Url.AbsolutePath;
                if (string.IsNullOrEmpty(urlPath) || urlPath == "/") urlPath = "/index.html";

                string rel = urlPath.TrimStart('/')
                    .Replace('/', Path.DirectorySeparatorChar)
                    .Replace('\\', Path.DirectorySeparatorChar);
                string rootFull = Path.GetFullPath(root);
                string full = Path.GetFullPath(Path.Combine(rootFull, rel));

                if (!full.StartsWith(rootFull + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                {
                    res.StatusCode = 403; // path traversal attempt
                    res.Close();
                    return true;
                }
                if (!File.Exists(full))
                {
                    res.StatusCode = 404;
                    res.Close();
                    return true;
                }

                byte[] data = File.ReadAllBytes(full);
                res.ContentType = MimeOf(full);
                res.Headers["Cache-Control"] = "no-cache";
                res.ContentLength64 = data.Length;
                if (req.HttpMethod != "HEAD") res.OutputStream.Write(data, 0, data.Length);
                res.Close();
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static string MimeOf(string p)
        {
            switch (Path.GetExtension(p).ToLowerInvariant())
            {
                case ".html": return "text/html; charset=utf-8";
                case ".js": return "application/javascript; charset=utf-8";
                case ".css": return "text/css; charset=utf-8";
                case ".json": return "application/json; charset=utf-8";
                case ".txt": return "text/plain; charset=utf-8";
                case ".png": return "image/png";
                case ".ico": return "image/x-icon";
                case ".svg": return "image/svg+xml";
                case ".woff": return "font/woff";
                case ".woff2": return "font/woff2";
                default: return "application/octet-stream";
            }
        }

        private static void WriteJson(HttpListenerResponse res, object obj)
        {
            string txt = new JavaScriptSerializer().Serialize(obj);
            byte[] buf = Encoding.UTF8.GetBytes(txt);
            res.ContentType = "application/json; charset=utf-8";
            res.ContentLength64 = buf.Length;
            res.OutputStream.Write(buf, 0, buf.Length);
            res.Close();
        }
    }
}
