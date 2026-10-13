using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Runtime.InteropServices;

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
        private static object hwObj;
        private static MethodInfo runDataMethod;
        private static MethodInfo readRunDataMethod;
        private static MethodInfo addRunDataMethod;
        private static ConstructorInfo dataItemCtor;
        private static readonly Dictionary<string, MethodInfo> runGetters = new Dictionary<string, MethodInfo>();
        private static PerformanceCounter diskCounter;
        private static bool diskCounterTried;
        private static DateTime lastDiskWmi = DateTime.MinValue;
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
                hwObj = hw;
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

                // The sampling entry point (the vendor's own refresh thread calls it
                // once per second; we take that over so the cadence is ours).
                readRunDataMethod = hw.GetType().GetMethod("ReadRunData");

                // Publishing plumbing so we can run *individual* getters instead of
                // the vendor's all-in-one pass: SystemData.AddSystemRunData(new
                // DataItem(type, list)). The all-in-one pass also runs GetNetwork
                // (~WMI performance counters) and GetWin32_DiskDrive; both cost tens
                // of milliseconds of CPU per pass and we do not need either (network
                // rates are sampled from adapter counters, disk activity comes from a
                // PDH counter).
                foreach (MethodInfo m in sysData.GetType().GetMethods())
                {
                    if (m.Name == "AddSystemRunData" && m.GetParameters().Length == 1) { addRunDataMethod = m; break; }
                }
                Type enumType = runDataMethod.GetParameters()[0].ParameterType;
                foreach (string g in new string[] { "GetCpuRunInfo", "GetGpuRunInfo", "GetRAMRunInfo", "GetFanSpeed" })
                {
                    MethodInfo gm = hw.GetType().GetMethod(g);
                    if (gm != null) runGetters[g] = gm;
                }
                if (addRunDataMethod != null)
                {
                    Type itemType = addRunDataMethod.GetParameters()[0].ParameterType;
                    foreach (KeyValuePair<string, MethodInfo> kv in runGetters)
                    {
                        dataItemCtor = itemType.GetConstructor(new Type[] { enumType, kv.Value.ReturnType });
                        if (dataItemCtor != null) break;
                    }
                }
                Log.Write("sampling: getters=" + runGetters.Count + " publisher=" + (dataItemCtor != null));

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

        /// <summary>Run one hardware sampling pass and publish the values our
        /// display uses (CPU / GPU / RAM / fan). Deliberately does NOT run the
        /// vendor's all-in-one ReadRunData: its network and disk getters go through
        /// WMI performance counters and cost tens of milliseconds of CPU per pass,
        /// while the four getters here take ~1 ms each. Network rates come from our
        /// own adapter sampling and disk activity from a PDH counter.</summary>
        private static readonly string[,] SampledTypes = {
            { "GetCpuRunInfo", "Cpu" },
            { "GetGpuRunInfo", "Gpu" },
            { "GetRAMRunInfo", "Ram" },
            { "GetFanSpeed", "Fan" },
        };

        public static bool Sample()
        {
            if (dataItemCtor == null || addRunDataMethod == null || hwObj == null)
            {
                // Fallback: the vendor's all-in-one pass (also samples network/disk).
                if (readRunDataMethod == null || hwObj == null) return false;
                try { return (bool)readRunDataMethod.Invoke(hwObj, null); }
                catch { return false; }
            }
            bool any = false;
            for (int i = 0; i < SampledTypes.GetLength(0); i++)
            {
                string getter = SampledTypes[i, 0];
                string type = SampledTypes[i, 1];
                try
                {
                    MethodInfo gm;
                    if (!runGetters.TryGetValue(getter, out gm)) continue;
                    object list = gm.Invoke(hwObj, null);
                    if (list == null) continue;
                    object item = dataItemCtor.Invoke(new object[] { EnumMap[type], list });
                    addRunDataMethod.Invoke(sysData, new object[] { item });
                    any = true;
                }
                catch { }
            }
            // Compatibility hedge for non-NVIDIA GPUs: there the GPU load/clock come
            // from the SDK, whose counters only refresh inside the vendor's
            // RefreshInformation call. Run it at a low rate (10 s, ~1 % CPU) so
            // those systems still show usable GPU values.
            try
            {
                if (EnsureNvmlDev() == IntPtr.Zero && (DateTime.Now - lastSdkRefresh).TotalSeconds >= 10)
                {
                    lastSdkRefresh = DateTime.Now;
                    object pSdk = GetPSdk();
                    if (pSdk != null)
                    {
                        MethodInfo miRef = pSdk.GetType().GetMethod("RefreshInformation");
                        if (miRef != null) miRef.Invoke(pSdk, null);
                    }
                }
            }
            catch { }
            return any;
        }

        /// <summary>Diagnostic: enumerate the vendor SDK's device/sensor inventory
        /// (name, class, value) so we can audit which sensors exist and which are
        /// live (used for the /sensors endpoint).</summary>
        public static List<object> DumpSdkSensors()
        {
            List<object> rows = new List<object>();
            try
            {
                object pSdk = GetPSdk();
                if (pSdk == null) return rows;
                Type t = pSdk.GetType();
                MethodInfo miNumDev = t.GetMethod("GetNumberOfDevices");
                MethodInfo miDevName = t.GetMethod("GetDeviceName");
                MethodInfo miDevClass = t.GetMethod("GetDeviceClass");
                MethodInfo miNum = t.GetMethod("GetNumberOfSensors");
                MethodInfo miInfo = t.GetMethod("GetSensorInfos");
                if (miNumDev == null || miNum == null || miInfo == null) return rows;
                int nd = Convert.ToInt32(miNumDev.Invoke(pSdk, null));
                int[] classes = new int[] { 4096, 8192, 12288, 24576, 57344, 61440 };
                for (int d = 0; d < nd; d++)
                {
                    string devName = "";
                    object devClass = null;
                    try { devName = Convert.ToString(miDevName.Invoke(pSdk, new object[] { d })); } catch { }
                    try { devClass = miDevClass.Invoke(pSdk, new object[] { d }); } catch { }
                    for (int c = 0; c < classes.Length; c++)
                    {
                        int ns = 0;
                        try { ns = Convert.ToInt32(miNum.Invoke(pSdk, new object[] { d, classes[c] })); }
                        catch { continue; }
                        for (int j = 0; j < ns; j++)
                        {
                            object[] args = new object[] { d, j, classes[c], 0, "", 0, 0f, 0f, 0f };
                            bool ok = false;
                            try { ok = (bool)miInfo.Invoke(pSdk, args); }
                            catch { continue; }
                            if (!ok) continue;
                            Dictionary<string, object> row = new Dictionary<string, object>();
                            row["dev"] = devName + "/" + Convert.ToString(devClass);
                            row["class"] = classes[c];
                            row["name"] = Convert.ToString(args[4]);
                            try { row["value"] = Math.Round(Convert.ToDouble(args[6]), 2); } catch { }
                            row["raw"] = args[5];
                            rows.Add(row);
                        }
                    }
                }
            }
            catch { }
            return rows;
        }

        /// <summary>CPUID SDK object behind the hardware instance; re-resolved on
        /// every call because CPUIDHardware.Start() recreates it.</summary>
        private static object GetPSdk()
        {
            try
            {
                if (hwObj == null) return null;
                FieldInfo f = hwObj.GetType().GetField("_pSdk", BindingFlags.NonPublic | BindingFlags.Instance);
                return f != null ? f.GetValue(hwObj) : null;
            }
            catch { return null; }
        }

        // ---- NVIDIA NVML (nvml.dll ships with the display driver) ----
        // The only GPU-fan source on this platform: the vendor run-data lacks a
        // GPU "fan" key, the CPUID SDK's GetDisplayAdapterFanSpeed returns -1 for
        // this card, and NVML's RPM API is unsupported (rc=25). The percentage
        // API works and reads 0 with zero-fan idle (fans physically stopped).
        [DllImport("nvml.dll")]
        private static extern int nvmlInit_v2();
        [DllImport("nvml.dll")]
        private static extern int nvmlDeviceGetHandleByIndex_v2(uint index, out IntPtr dev);
        [DllImport("nvml.dll")]
        private static extern int nvmlDeviceGetFanSpeed(IntPtr dev, out uint speed);
        [DllImport("nvml.dll")]
        private static extern int nvmlDeviceGetTemperature(IntPtr dev, int sensor, out uint temp);
        [DllImport("nvml.dll")]
        private static extern int nvmlDeviceGetUtilizationRates(IntPtr dev, out NvmlUtilization util);
        [DllImport("nvml.dll")]
        private static extern int nvmlDeviceGetClockInfo(IntPtr dev, int type, out uint mhz);

        [StructLayout(LayoutKind.Sequential)]
        private struct NvmlUtilization { public uint Gpu; public uint Memory; }

        // ---- cheap native CPU metrics (no WMI, no vendor refresh call) ----
        [DllImport("kernel32.dll")]
        private static extern bool GetSystemTimes(out long idleTime, out long kernelTime, out long userTime);

        [DllImport("powrprof.dll")]
        private static extern uint CallNtPowerInformation(int informationLevel, IntPtr inputBuffer,
            uint inputBufferSize, IntPtr outputBuffer, uint outputBufferSize);

        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessorPowerInformation
        {
            public uint Number;
            public uint MaxMhz;
            public uint CurrentMhz;
            public uint MhzLimit;
            public uint MaxIdleState;
            public uint CurrentIdleState;
        }

        private static long lastSysIdle, lastSysKernel, lastSysUser;
        private static bool sysTimesPrimed;
        private static double cpuLoadEma = -1;

        /// <summary>Total CPU load from GetSystemTimes deltas - the standard OS
        /// metric Task Manager is built on - lightly smoothed like a task manager
        /// readout. Returns -1 until the first delta is available.</summary>
        private static double TotalCpuLoad()
        {
            try
            {
                long idle, kernel, user;
                if (!GetSystemTimes(out idle, out kernel, out user)) return cpuLoadEma;
                if (!sysTimesPrimed)
                {
                    sysTimesPrimed = true;
                    lastSysIdle = idle; lastSysKernel = kernel; lastSysUser = user;
                    return cpuLoadEma;
                }
                long di = idle - lastSysIdle, dk = kernel - lastSysKernel, du = user - lastSysUser;
                lastSysIdle = idle; lastSysKernel = kernel; lastSysUser = user;
                long total = dk + du; // kernel time includes idle time
                if (total <= 0) return cpuLoadEma;
                double raw = (total - di) * 100.0 / total;
                if (raw < 0) raw = 0;
                if (raw > 100) raw = 100;
                cpuLoadEma = cpuLoadEma < 0 ? raw : cpuLoadEma * 0.5 + raw * 0.5;
                return cpuLoadEma;
            }
            catch { return cpuLoadEma; }
        }

        /// <summary>Highest current (effective) core clock in MHz via
        /// CallNtPowerInformation - the same value task managers display.</summary>
        private static double MaxCoreMhz()
        {
            try
            {
                int n = Environment.ProcessorCount;
                int one = Marshal.SizeOf(typeof(ProcessorPowerInformation));
                IntPtr buf = Marshal.AllocHGlobal(one * n);
                try
                {
                    if (CallNtPowerInformation(11, IntPtr.Zero, 0, buf, (uint)(one * n)) != 0) return -1;
                    uint max = 0;
                    long baseAddr = buf.ToInt64();
                    for (int i = 0; i < n; i++)
                    {
                        ProcessorPowerInformation p = (ProcessorPowerInformation)Marshal.PtrToStructure(
                            new IntPtr(baseAddr + i * one), typeof(ProcessorPowerInformation));
                        if (p.CurrentMhz > max) max = p.CurrentMhz;
                    }
                    return max;
                }
                finally { Marshal.FreeHGlobal(buf); }
            }
            catch { return -1; }
        }

        /// <summary>Effective CPU clock in MHz, computed the way Task Manager does:
        /// nominal clock × the OS "Processor Performance" counter. (The
        /// CallNtPowerInformation CurrentMhz values report the nominal clock on this
        /// platform - they stayed at 3500 MHz even at 4.7 GHz under load.)</summary>
        private static PerformanceCounter perfCounter;
        private static bool perfCounterTried;
        private static double nominalMhz = -1;

        private static double EffectiveCpuMhz()
        {
            try
            {
                if (!perfCounterTried)
                {
                    perfCounterTried = true;
                    try
                    {
                        perfCounter = new PerformanceCounter("Processor Information", "% Processor Performance", "_Total", true);
                        perfCounter.NextValue();
                    }
                    catch { perfCounter = null; }
                    try
                    {
                        using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(
                            @"HARDWARE\DESCRIPTION\System\CentralProcessor\0"))
                        {
                            if (k != null) nominalMhz = Convert.ToDouble(k.GetValue("~MHz"));
                        }
                    }
                    catch { }
                }
                if (perfCounter == null || nominalMhz <= 0) return -1;
                double perf = perfCounter.NextValue();
                if (perf <= 0) return -1;
                return nominalMhz * perf / 100.0;
            }
            catch { return -1; }
        }

        /// <summary>Live CPU voltage in volts, sourced in this order:
        ///   1) the per-core VID sensors ("P-Core #n" / "E-Core #n" / "CPU #n",
        ///      class 4096) - the requested voltage CPU-Z-style, which moves with
        ///      load; the maximum across cores is reported;
        ///   2) the measured "VCORE" rail (motherboard SIO);
        ///   3) give up and keep the vendor SDK's own value (its static
        ///      "VID (max)" spec - still better than nothing on exotic boards).
        /// The vendor's own getter only ever reports "VID (max)", a constant spec.
        /// Sensor indexes are resolved once and re-resolved if a read fails.</summary>
        private static readonly List<int[]> vidSensors = new List<int[]>(); // {device, index}
        private static int vcoreDev = -1;
        private static int vcoreIdx = -1;
        private static bool vcoreTried;

        private static void ResolveVoltageSensors(object pSdk, MethodInfo miNum, MethodInfo miInfo)
        {
            Type t = pSdk.GetType();
            MethodInfo miNumDev = t.GetMethod("GetNumberOfDevices");
            if (miNumDev == null) return;
            int nd = Convert.ToInt32(miNumDev.Invoke(pSdk, null));
            for (int d = 0; d < nd; d++)
            {
                int ns = Convert.ToInt32(miNum.Invoke(pSdk, new object[] { d, 4096 }));
                for (int j = 0; j < ns; j++)
                {
                    object[] args = new object[] { d, j, 4096, 0, "", 0, 0f, 0f, 0f };
                    if (!(bool)miInfo.Invoke(pSdk, args)) continue;
                    string nm = Convert.ToString(args[4]).Trim();
                    if (nm.StartsWith("P-Core") || nm.StartsWith("E-Core") || nm.StartsWith("CPU #"))
                        vidSensors.Add(new int[] { d, j });
                    else if (string.Equals(nm, "VCORE", StringComparison.OrdinalIgnoreCase) ||
                             nm.IndexOf("vcore", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        vcoreDev = d;
                        vcoreIdx = j;
                    }
                }
            }
        }

        private static double ReadLiveVoltage()
        {
            try
            {
                object pSdk = GetPSdk();
                if (pSdk == null) return -1;
                Type t = pSdk.GetType();
                MethodInfo miNum = t.GetMethod("GetNumberOfSensors");
                MethodInfo miInfo = t.GetMethod("GetSensorInfos");
                if (miNum == null || miInfo == null) return -1;
                if (!vcoreTried)
                {
                    vcoreTried = true;
                    try { ResolveVoltageSensors(pSdk, miNum, miInfo); } catch { }
                }
                double best = -1;
                for (int k = 0; k < vidSensors.Count; k++)
                {
                    int[] si = vidSensors[k];
                    object[] a = new object[] { si[0], si[1], 4096, 0, "", 0, 0f, 0f, 0f };
                    try
                    {
                        if (!(bool)miInfo.Invoke(pSdk, a)) continue;
                        double v = Convert.ToDouble(a[6]);
                        if (v > 0.2 && v < 3.0 && v > best) best = v;
                    }
                    catch { }
                }
                if (best > 0) return best;
                if (vcoreIdx >= 0)
                {
                    object[] a = new object[] { vcoreDev, vcoreIdx, 4096, 0, "", 0, 0f, 0f, 0f };
                    if ((bool)miInfo.Invoke(pSdk, a))
                    {
                        double v = Convert.ToDouble(a[6]);
                        if (v > 0.2 && v < 3.0) return v;
                    }
                    vcoreIdx = -1; // re-resolve next time
                }
                return -1;
            }
            catch { return -1; }
        }

        private static IntPtr EnsureNvmlDev()
        {
            try
            {
                if (!nvmlTried)
                {
                    nvmlTried = true;
                    try { nvmlInit_v2(); } catch { } // 5 = already initialised, fine
                    IntPtr dev;
                    if (nvmlDeviceGetHandleByIndex_v2(0, out dev) == 0) nvmlDev = dev;
                }
                return nvmlDev;
            }
            catch { return IntPtr.Zero; }
        }

        /// <summary>Live GPU utilisation / SM clock / temperature from NVML (the
        /// same source nvidia-smi reads). Returns false when unavailable.</summary>
        private static bool NvmlGpuMetrics(out double load, out double clockGhz10, out double temp)
        {
            load = -1; clockGhz10 = -1; temp = -1;
            IntPtr dev = EnsureNvmlDev();
            if (dev == IntPtr.Zero) return false;
            try
            {
                NvmlUtilization u;
                if (nvmlDeviceGetUtilizationRates(dev, out u) == 0) load = u.Gpu;
                uint mhz;
                if (nvmlDeviceGetClockInfo(dev, 1, out mhz) == 0) clockGhz10 = mhz / 100.0; // SM clock
                uint t;
                if (nvmlDeviceGetTemperature(dev, 0, out t) == 0) temp = t;
                return load >= 0 || clockGhz10 >= 0 || temp >= 0;
            }
            catch { return false; }
        }

        private static bool nvmlTried;
        private static IntPtr nvmlDev = IntPtr.Zero;
        private static DateTime lastSdkRefresh = DateTime.MinValue;

        private static double ReadNvmlFanPct()
        {
            try
            {
                IntPtr dev = EnsureNvmlDev();
                if (dev == IntPtr.Zero) return -1;
                uint pct;
                if (nvmlDeviceGetFanSpeed(dev, out pct) != 0) { nvmlDev = IntPtr.Zero; return -1; }
                return pct;
            }
            catch { return -1; }
        }

        /// <summary>
        /// Debug helper for the /raw endpoint: every item of every data type as
        /// plain key/value pairs (ToString for non-numeric values), so the actual
        /// SDK field names are visible without a debugger.
        /// </summary>
        public static Dictionary<string, object> DumpRaw()
        {
            Dictionary<string, object> all = new Dictionary<string, object>();
            string[] names = new string[] { "Cpu", "Gpu", "Network", "Ram", "HHD", "Fan" };
            for (int n = 0; n < names.Length; n++)
            {
                List<object> rows = new List<object>();
                object r = RunData(names[n]);
                int size = r != null ? GetSize(r) : 0;
                for (int i = 0; i < size; i++)
                {
                    Dictionary<string, object> d = GetItemAt(r, i);
                    Dictionary<string, object> row = new Dictionary<string, object>();
                    if (d != null)
                    {
                        foreach (KeyValuePair<string, object> kv in d)
                        {
                            object v = kv.Value;
                            if (v == null) row[kv.Key] = null;
                            else if (v is double || v is float) row[kv.Key] = Math.Round(Convert.ToDouble(v), 2);
                            else if (v is int || v is long || v is short || v is byte || v is bool) row[kv.Key] = v;
                            else row[kv.Key] = Convert.ToString(v, CultureInfo.InvariantCulture);
                        }
                    }
                    rows.Add(row);
                }
                all[names[n]] = rows;
            }
            return all;
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
        /// byte delta since the previous sample. The (long) adapter list is cached
        /// for 30 s and the byte counters are re-read at most every 400 ms, so the
        /// driver loop and concurrent /status polls share one read.
        /// </summary>
        private static NetworkInterface[] ifaceCache;
        private static DateTime ifaceCacheAt = DateTime.MinValue;

        private static void SampleNet(out double downMb, out double upMb)
        {
            downMb = cachedDownMb;
            upMb = cachedUpMb;
            try
            {
                DateTime now = DateTime.Now;
                if (now - lastNetTime < TimeSpan.FromMilliseconds(400) && lastNetTime != DateTime.MinValue)
                    return;
                if (ifaceCache == null || (now - ifaceCacheAt).TotalSeconds > 30)
                {
                    ifaceCache = NetworkInterface.GetAllNetworkInterfaces();
                    ifaceCacheAt = now;
                }
                long rx = 0;
                long tx = 0;
                foreach (NetworkInterface ni in ifaceCache)
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
                int load = 0;
                int temp = 0;
                double gl, gc, gt;
                if (NvmlGpuMetrics(out gl, out gc, out gt))
                {
                    // live values, same source as nvidia-smi
                    if (gl >= 0) load = (int)gl;
                    if (gt >= 0) temp = (int)gt;
                    if (gc >= 0) clock = (int)Math.Round(gc * 100.0); // back to MHz
                }
                else
                {
                    if (d.ContainsKey("clock")) clock = (int)ToDbl(d["clock"]);
                    if (d.ContainsKey("load")) load = (int)ToDbl(d["load"]);
                    if (d.ContainsKey("temperature")) temp = (int)ToDbl(d["temperature"]);
                }
                arr[0] = (byte)load;
                arr[1] = (byte)temp;
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
                // Load and clock come from our native samplers (the SDK's per-core
                // load/clock freeze without the vendor's RefreshInformation call);
                // per-core temperatures are still live SDK reads.
                int load = (int)Math.Round(TotalCpuLoad());
                if (load < 0) load = 0;
                if (load > 99) load = 99;
                double mhz = EffectiveCpuMhz();
                if (mhz <= 0) mhz = MaxCoreMhz();
                int clock = mhz > 0 ? (int)mhz : 0;
                if (clock > 65535) clock = 65535;
                for (int k = 0; k < size; k++)
                {
                    Dictionary<string, object> d = GetItemAt(c, k);
                    if (d == null) continue;
                    arr[8 * k] = (byte)load;
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

            // GPU fan fallback: on this platform the GPU run-data dict carries no
            // "fan" key (only name/temperature/load/clock). Prefer NVIDIA NVML's
            // percentage reading; keep the CPUID SDK reading as a last resort for
            // non-NVIDIA GPUs (-1 = unsupported / not initialised; values above 120
            // look like RPM and are scaled to the two-digit slot, smaller ones are
            // already a percentage).
            if (!s.ContainsKey("gpu_fan"))
            {
                try
                {
                    double pct = ReadNvmlFanPct();
                    if (pct >= 0) s["gpu_fan"] = pct;
                }
                catch { }
            }
            if (!s.ContainsKey("gpu_fan"))
            {
                try
                {
                    object pSdk = GetPSdk();
                    MethodInfo mFan = pSdk != null ? pSdk.GetType().GetMethod("GetDisplayAdapterFanSpeed") : null;
                    if (mFan != null)
                    {
                        double v = ToDbl(mFan.Invoke(pSdk, new object[] { 0 }));
                        if (v >= 0) s["gpu_fan"] = v > 120 ? v / 100.0 : v;
                    }
                }
                catch { }
            }

            // Live GPU utilisation / SM clock / temperature from NVML (the source
            // nvidia-smi reads). The SDK's GPU counters freeze without the vendor's
            // RefreshInformation call, so NVML is the live source here; on
            // non-NVIDIA systems the SDK values above remain in place.
            try
            {
                double gl, gc, gt;
                if (NvmlGpuMetrics(out gl, out gc, out gt))
                {
                    if (gl >= 0) s["gpu_load"] = gl;
                    if (gc >= 0) s["gpu_clock"] = gc;
                    if (gt >= 0) s["gpu_temp"] = gt;
                }
            }
            catch { }

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

            // Live CPU load / clock from native APIs. The SDK only refreshes its
            // frequency/load counters inside the vendor's RefreshInformation call
            // (~100 ms of CPU per call), so those two fields go stale without it -
            // we source them ourselves instead (GetSystemTimes / CallNtPowerInformation,
            // the same sources task managers use).
            try
            {
                double tl = TotalCpuLoad();
                if (tl >= 0) s["cpu_load"] = tl;
                double mhz = EffectiveCpuMhz();
                if (mhz <= 0) mhz = MaxCoreMhz(); // fallback: nominal clock
                if (mhz > 0) s["cpu_clock"] = mhz / 100.0;
                double vc = ReadLiveVoltage();      // live per-core VID / VCORE (SDK's own field is static)
                if (vc > 0) s["cpu_volt"] = vc * 10.0;
            }
            catch { }

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

            // ---- HDD activity (PDH counter: ~0.1 ms; the vendor's WMI disk getter
            // costs ~89 ms per pass, so it survives only as a throttled fallback) ----
            try
            {
                if (!diskCounterTried)
                {
                    diskCounterTried = true;
                    try
                    {
                        diskCounter = new PerformanceCounter("PhysicalDisk", "% Disk Time", "_Total", true);
                        diskCounter.NextValue();
                    }
                    catch { diskCounter = null; }
                }
                if (diskCounter != null)
                {
                    double v = diskCounter.NextValue();
                    if (v < 0) v = 0;
                    if (v > 99) v = 99;
                    s["hdd_load"] = v;
                }
                else if ((DateTime.Now - lastDiskWmi).TotalSeconds >= 5)
                {
                    lastDiskWmi = DateTime.Now;
                    object h = RunData("HHD");
                    int hsize = h != null ? GetSize(h) : 0;
                    if (hsize > 0)
                    {
                        Dictionary<string, object> d = GetItemAt(h, 0);
                        if (d != null && d.ContainsKey("load")) s["hdd_load"] = ToDbl(d["load"]);
                    }
                }
            }
            catch { }

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
