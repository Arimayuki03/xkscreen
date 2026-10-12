using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Net.NetworkInformation;
using System.Reflection;

namespace XkScreen.Service
{
    /// <summary>
    /// Reads live hardware values from the official XKWLib hardware object
    /// (reflection into hardware.SystemData.GetSystemRunData(DataType.X)).
    /// Ported 1:1 from the proven PowerShell driver. All slot values are
    /// scaled to fit 0-99 with the final data catalogue.
    /// </summary>
    internal static class Sensors
    {
        private static object sysData;
        private static MethodInfo runDataMethod;
        private static readonly Dictionary<string, object> EnumMap = new Dictionary<string, object>();
        private static bool ready;

        // network sampling state
        private static long lastNetRx = -1;
        private static long lastNetTx = -1;
        private static DateTime lastNetTime = DateTime.MinValue;
        private static double cachedDownMb;
        private static double cachedUpMb;

        public static bool Ready { get { return ready; } }

        public static void Init(object help)
        {
            try
            {
                Type t = help.GetType();
                FieldInfo f = t.GetField("hardware", BindingFlags.NonPublic | BindingFlags.Instance);
                if (f == null) { Log.Write("sensors: hardware field not found"); return; }
                object hw = f.GetValue(help);
                if (hw == null) { Log.Write("sensors: hardware is null"); return; }
                PropertyInfo prop = hw.GetType().GetProperty("SystemData");
                if (prop == null) { Log.Write("sensors: SystemData prop not found"); return; }
                sysData = prop.GetValue(hw, null);
                if (sysData == null) { Log.Write("sensors: SystemData is null"); return; }

                foreach (MethodInfo m in sysData.GetType().GetMethods())
                {
                    ParameterInfo[] ps = m.GetParameters();
                    if (m.Name == "GetSystemRunData" && ps.Length == 1) { runDataMethod = m; break; }
                }
                if (runDataMethod == null) { Log.Write("sensors: GetSystemRunData not found"); return; }

                Type et = runDataMethod.GetParameters()[0].ParameterType;
                string[] names = new string[] { "Cpu", "Gpu", "Network", "Ram", "HHD", "Fan" };
                for (int i = 0; i < names.Length; i++)
                {
                    try { EnumMap[names[i]] = Enum.Parse(et, names[i]); }
                    catch { }
                }
                ready = true;
                Log.Write("sensors: init ok, enums=" + EnumMap.Count);
            }
            catch (Exception ex) { Log.Write("sensors init exc: " + ex.Message); }
        }

        private static object RunData(string key)
        {
            if (!ready || !EnumMap.ContainsKey(key)) return null;
            try { return runDataMethod.Invoke(sysData, new object[] { EnumMap[key] }); }
            catch { return null; }
        }

        private static int GetSize(object item)
        {
            try { return Convert.ToInt32(item.GetType().GetProperty("Size").GetValue(item, null)); }
            catch { return 0; }
        }

        private static Dictionary<string, object> GetItemAt(object item, int index)
        {
            try
            {
                foreach (PropertyInfo p in item.GetType().GetProperties())
                {
                    ParameterInfo[] ps = p.GetIndexParameters();
                    if (ps.Length == 1 && ps[0].ParameterType == typeof(int))
                        return (Dictionary<string, object>)p.GetValue(item, new object[] { index });
                }
            }
            catch { }
            return null;
        }

        private static double ToDbl(object v)
        {
            if (v == null) return 0.0;
            double d;
            if (double.TryParse(Convert.ToString(v, CultureInfo.InvariantCulture),
                    NumberStyles.Float, CultureInfo.InvariantCulture, out d)) return d;
            return 0.0;
        }

        /// <summary>
        /// Sum traffic across all up network adapters and derive MB/s from the
        /// byte delta since the previous sample. Cached when called within 200ms
        /// so frequent /status polls do not zero the reading.
        /// </summary>
        private static void SampleNet(out double downMb, out double upMb)
        {
            downMb = cachedDownMb;
            upMb = cachedUpMb;
            try
            {
                long rx = 0;
                long tx = 0;
                foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (ni.OperationalStatus != OperationalStatus.Up) continue;
                    try
                    {
                        IPv4InterfaceStatistics st = ni.GetIPv4Statistics();
                        if (st.BytesReceived > 0 || st.BytesSent > 0)
                        {
                            rx += st.BytesReceived;
                            tx += st.BytesSent;
                        }
                    }
                    catch { }
                }
                DateTime now = DateTime.Now;
                if (lastNetRx >= 0 && lastNetTime != DateTime.MinValue)
                {
                    double dt = (now - lastNetTime).TotalSeconds;
                    if (dt >= 0.2)
                    {
                        cachedDownMb = Math.Max(0, rx - lastNetRx) / dt / 1048576.0;
                        cachedUpMb = Math.Max(0, tx - lastNetTx) / dt / 1048576.0;
                        lastNetRx = rx;
                        lastNetTx = tx;
                        lastNetTime = now;
                        downMb = cachedDownMb;
                        upMb = cachedUpMb;
                    }
                }
                else
                {
                    lastNetRx = rx;
                    lastNetTx = tx;
                    lastNetTime = now;
                }
            }
            catch { }
        }

        private static Dictionary<string, object> SelectGpuDict(object g, int gsize)
        {
            if (g == null || gsize <= 0) return null;
            if (gsize > 1)
            {
                for (int i = 0; i < gsize; i++)
                {
                    Dictionary<string, object> it = GetItemAt(g, i);
                    if (it == null) continue;
                    string n = it.ContainsKey("name") ? Convert.ToString(it["name"]).ToUpperInvariant() : "";
                    if (n.Contains("GTX") || n.Contains("RTX") || n.Contains("NVIDIA")) return it;
                }
                for (int i = 0; i < gsize; i++)
                {
                    Dictionary<string, object> it = GetItemAt(g, i);
                    if (it != null && it.ContainsKey("clock") && it.ContainsKey("temperature")) return it;
                }
            }
            return GetItemAt(g, 0);
        }

        /// <summary>Official-format GPU data frame: [load, temp, clock_lo, clock_hi].</summary>
        public static byte[] BuildGpuArray()
        {
            try
            {
                object g = RunData("Gpu");
                int gsize = g != null ? GetSize(g) : 0;
                Dictionary<string, object> d = SelectGpuDict(g, gsize);
                if (d == null) return null;
                byte[] arr = new byte[8];
                int clock = 0;
                if (d.ContainsKey("clock")) clock = (int)ToDbl(d["clock"]);
                if (d.ContainsKey("load")) arr[0] = (byte)(int)ToDbl(d["load"]);
                if (d.ContainsKey("temperature")) arr[1] = (byte)(int)ToDbl(d["temperature"]);
                arr[2] = (byte)(clock & 0xFF);
                arr[3] = (byte)((clock >> 8) & 0xFF);
                return arr;
            }
            catch { return null; }
        }

        /// <summary>Official-format CPU data frame: 8 bytes per core [load, temp, clock_lo, clock_hi, 0...].</summary>
        public static byte[] BuildCpuArray()
        {
            try
            {
                object c = RunData("Cpu");
                int size = c != null ? GetSize(c) : 0;
                if (size <= 0) return null;
                byte[] arr = new byte[size * 8];
                for (int k = 0; k < size; k++)
                {
                    Dictionary<string, object> d = GetItemAt(c, k);
                    if (d == null) continue;
                    int clock = 0;
                    if (d.ContainsKey("clock")) clock = (int)ToDbl(d["clock"]);
                    if (d.ContainsKey("load")) arr[8 * k] = (byte)(int)ToDbl(d["load"]);
                    if (d.ContainsKey("temperature")) arr[8 * k + 1] = (byte)(int)ToDbl(d["temperature"]);
                    arr[8 * k + 2] = (byte)(clock & 0xFF);
                    arr[8 * k + 3] = (byte)((clock >> 8) & 0xFF);
                }
                return arr;
            }
            catch { return null; }
        }

        public static Dictionary<string, double> GetSensors()
        {
            Dictionary<string, double> s = new Dictionary<string, double>();

            // ---- GPU ----
            object g = RunData("Gpu");
            int gsize = g != null ? GetSize(g) : 0;
            if (gsize > 0)
            {
                try
                {
                    Dictionary<string, object> d = SelectGpuDict(g, gsize);
                    if (d != null)
                    {
                        if (d.ContainsKey("load")) s["gpu_load"] = ToDbl(d["load"]);
                        if (d.ContainsKey("temperature")) s["gpu_temp"] = ToDbl(d["temperature"]);
                        if (d.ContainsKey("clock")) s["gpu_clock"] = ToDbl(d["clock"]) / 100.0;
                        if (d.ContainsKey("fan")) s["gpu_fan"] = ToDbl(d["fan"]) / 100.0;
                    }
                }
                catch { }
            }

            // ---- CPU (the "packge" item also carries load/temperature/clock) ----
            object c = RunData("Cpu");
            int csize = c != null ? GetSize(c) : 0;
            if (csize > 0)
            {
                try
                {
                    double loadSum = 0.0; int loadN = 0; double tMax = 0.0; double clkMax = 0.0;
                    foreach (object o in (IEnumerable)c)
                    {
                        Dictionary<string, object> d = o as Dictionary<string, object>;
                        if (d == null) continue;
                        string nm = d.ContainsKey("name") ? Convert.ToString(d["name"]) : "";
                        if (nm == "packge")
                        {
                            if (d.ContainsKey("powers"))
                            {
                                double w = ToDbl(d["powers"]);
                                s["cpu_watt"] = w;
                                s["cpu_watt10"] = w / 10.0;
                            }
                            if (d.ContainsKey("voltage")) s["cpu_volt"] = ToDbl(d["voltage"]) * 10.0;
                        }
                        if (d.ContainsKey("load")) { loadSum += ToDbl(d["load"]); loadN++; }
                        if (d.ContainsKey("temperature")) { double tv = ToDbl(d["temperature"]); if (tv > tMax) tMax = tv; }
                        if (d.ContainsKey("clock")) { double tv = ToDbl(d["clock"]); if (tv > clkMax) clkMax = tv; }
                    }
                    if (loadN > 0) s["cpu_load"] = loadSum / loadN;
                    s["cpu_temp"] = tMax;
                    s["cpu_clock"] = clkMax / 100.0;
                }
                catch { }
            }

            // ---- Network (own high-resolution sampling: adapter byte deltas) ----
            // More accurate and responsive than the SDK's 1s average; the rate is
            // computed from a ~500ms window and cached when called too frequently.
            double downMb; double upMb;
            SampleNet(out downMb, out upMb);
            s["net_down"] = downMb;
            s["net_up"] = upMb;
            s["net_down_x10"] = downMb * 10.0;
            s["net_up_x10"] = upMb * 10.0;

            // ---- RAM (SDK fields are already in GB) ----
            object r = RunData("Ram");
            int rsize = r != null ? GetSize(r) : 0;
            if (rsize > 0)
            {
                try
                {
                    Dictionary<string, object> d = GetItemAt(r, 0);
                    if (d != null)
                    {
                        double used = 0.0; double avail = 0.0;
                        if (d.ContainsKey("Memory Used") && d.ContainsKey("Memory Available"))
                        {
                            used = ToDbl(d["Memory Used"]); avail = ToDbl(d["Memory Available"]);
                        }
                        else if (d.ContainsKey("Used Memory") && d.ContainsKey("Available Memory"))
                        {
                            used = ToDbl(d["Used Memory"]); avail = ToDbl(d["Available Memory"]);
                        }
                        if ((used + avail) > 0) s["mem_pct"] = used / (used + avail) * 100.0;
                        if (used > 0) s["mem_used_gb"] = used;
                    }
                }
                catch { }
            }

            // ---- Fan (scan all items for the first non-zero speed, like the official flow) ----
            object f = RunData("Fan");
            int fsize = f != null ? GetSize(f) : 0;
            if (fsize > 0)
            {
                try
                {
                    for (int i = 0; i < fsize; i++)
                    {
                        Dictionary<string, object> d = GetItemAt(f, i);
                        if (d == null || !d.ContainsKey("speed")) continue;
                        double sp = ToDbl(d["speed"]);
                        if (sp > 0) { s["fan_rpm"] = sp / 100.0; break; }
                    }
                    if (!s.ContainsKey("fan_rpm")) s["fan_rpm"] = 0.0;
                }
                catch { }
            }

            // ---- HDD ----
            object h = RunData("HHD");
            int hsize = h != null ? GetSize(h) : 0;
            if (hsize > 0)
            {
                try
                {
                    Dictionary<string, object> d = GetItemAt(h, 0);
                    if (d != null && d.ContainsKey("load")) s["hdd_load"] = ToDbl(d["load"]);
                }
                catch { }
            }

            return s;
        }

        /// <summary>Resolve one slot token to a byte clamped to 0-99.</summary>
        public static byte ResolveSlot(string tok, Dictionary<string, double> sensors)
        {
            if (tok == null) return 0;
            int fixedV;
            if (int.TryParse(tok, out fixedV))
            {
                if (fixedV < 0) fixedV = 0;
                if (fixedV > 99) fixedV = 99;
                return (byte)fixedV;
            }
            string k = tok.ToLowerInvariant();
            if (sensors != null && sensors.ContainsKey(k))
            {
                double v = Math.Round(sensors[k]);
                if (v < 0) v = 0;
                if (v > 99) v = 99;
                return (byte)v;
            }
            return 0;
        }
    }
}
