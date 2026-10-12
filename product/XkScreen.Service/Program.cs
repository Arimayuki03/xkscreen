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
        private static MethodInfo miCheckOnline;

        /// <summary>Effective screen power state (true = frames paused, display dark).</summary>
        private static bool screenOffState;

        /// <summary>Last clock-area content actually sent to the screen (HH:MM display string).</summary>
        internal static string LastShow = "";

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
                miCheckOnline = tHelp.GetMethod("CheckOnlineDevice");
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
                    try
                    {
                        Config cfg = Config.Load();
                        interval = cfg.IntervalMs;
                        timeSpec = cfg.Time;

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
                                try { miCheckOnline.Invoke(help, null); }
                                catch (Exception rex) { Log.Write("re-arm exc: " + rex.Message); }
                            }
                        }

                        if (!screenOffState)
                        {
                            Dictionary<string, double> sensors = Sensors.GetSensors();

                            // Push hardware data ourselves in the official frame formats.
                            // This replaces SendDynamicDataNew entirely so each cycle emits
                            // exactly ONE time frame - no more occasional real-time flashes
                            // while a custom clock (timer/offset/fixed) is active.
                            byte[] cpuArr = Sensors.BuildCpuArray();
                            if (cpuArr != null) miSetCpuDyn.Invoke(null, new object[] { cpuArr, (uint)cpuArr.Length });
                            byte[] gpuArr = Sensors.BuildGpuArray();
                            if (gpuArr != null) miSetGpuDyn.Invoke(null, new object[] { gpuArr, (uint)gpuArr.Length });

                            byte[] rc = BuildRing(cfg.Cpu, sensors, "cpu");
                            if (rc != null) miSetCpuDyn.Invoke(null, new object[] { rc, (uint)8 });
                            byte[] rg = BuildRing(cfg.Gpu, sensors, "gpu");
                            if (rg != null) miSetGpuDyn.Invoke(null, new object[] { rg, (uint)8 });

                            byte[] tframe = BuildTimeFrame(cfg.Time);
                            Flush(tframe);

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
                        if (!screenOffState && timeSpec != null && timeSpec.StartsWith("timer") && !timeSpec.Contains("paused"))
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

        /// <summary>
        /// Build the 9-byte time frame for the given spec, or null for "auto" (real time).
        /// Specs: auto | +N | -N | HH:MM (hour 0-99 accepted; rendered as-is on screen) |
        ///        timer (stopwatch MM:SS up) | timer_down:MM:SS (countdown to 00:00).
        /// The screen clock area renders the frame's hour+minute bytes; timer modes
        /// put MM into the hour slot and SS into the minute slot to show MM:SS.
        /// </summary>
        private static byte[] BuildTimeFrame(string spec)
        {
            if (string.IsNullOrEmpty(spec) || spec == "auto") return null;
            try
            {
                DateTime now = DateTime.Now;
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
