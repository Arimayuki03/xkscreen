using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

namespace XkScreen.Service
{
    /// <summary>
    /// Product config: %ProgramData%\XkScreen\config.json
    /// {
    ///   "cpu": ["auto","auto"],     // two slot tokens; "auto" = official real data
    ///   "gpu": ["mem_pct","net_down"],
    ///   "time": "auto",             // auto | +N | -N | HH:MM
    ///   "interval_ms": 500
    /// }
    /// Slot tokens: 0-99 fixed number or a source name (cpu_load cpu_temp cpu_clock
    /// cpu_watt cpu_volt gpu_load gpu_temp gpu_clock gpu_fan mem_pct mem_used_gb
    /// net_down net_up fan_rpm hdd_load). Every slot is clamped to 0-99.
    /// </summary>
    internal sealed class Config
    {
        public string[] Cpu;
        public string[] Gpu;
        public string Time = "auto";
        public int IntervalMs = 500;

        private static readonly string Dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "XkScreen");
        private static readonly string FilePath = Path.Combine(Dir, "config.json");

        public static string ConfigPath { get { return FilePath; } }

        public static void EnsureDefault()
        {
            try
            {
                if (!Directory.Exists(Dir)) Directory.CreateDirectory(Dir);
                if (!File.Exists(FilePath))
                {
                    File.WriteAllText(FilePath,
                        "{\"cpu\":[\"auto\",\"auto\"],\"gpu\":[\"auto\",\"auto\"],\"time\":\"auto\",\"interval_ms\":500}",
                        new UTF8Encoding(false));
                }
            }
            catch (Exception ex) { Log.Write("config init exc: " + ex.Message); }
        }

        public static Config Load()
        {
            Config c = new Config();
            try
            {
                if (!File.Exists(FilePath)) return c;
                string txt = File.ReadAllText(FilePath, Encoding.UTF8);
                JavaScriptSerializer ser = new JavaScriptSerializer();
                Dictionary<string, object> root = ser.Deserialize<Dictionary<string, object>>(txt);
                if (root == null) return c;
                c.Cpu = ParsePair(root, "cpu");
                c.Gpu = ParsePair(root, "gpu");
                if (root.ContainsKey("time") && root["time"] != null) c.Time = Convert.ToString(root["time"]);
                if (root.ContainsKey("interval_ms") && root["interval_ms"] != null)
                {
                    int iv;
                    if (int.TryParse(Convert.ToString(root["interval_ms"]), out iv) && iv >= 100 && iv <= 5000)
                        c.IntervalMs = iv;
                }
            }
            catch (Exception ex) { Log.Write("config load exc: " + ex.Message); }
            return c;
        }

        private static string[] ParsePair(Dictionary<string, object> root, string key)
        {
            try
            {
                if (!root.ContainsKey(key) || root[key] == null) return null;
                // NOTE: generic Deserialize<Dictionary<string,object>> turns JSON arrays
                // into ArrayList (not object[]); IList covers both shapes.
                IList arr = root[key] as IList;
                if (arr == null || arr.Count < 2) return null;
                string[] pair = new string[2];
                pair[0] = Convert.ToString(arr[0]).Trim();
                pair[1] = Convert.ToString(arr[1]).Trim();
                return pair;
            }
            catch { return null; }
        }

        // ---- validation + save (used by the local HTTP API /config) ----

        public static readonly string[] KnownSources = {
            "cpu_load", "cpu_temp", "cpu_clock", "cpu_watt", "cpu_watt10", "cpu_volt",
            "gpu_load", "gpu_temp", "gpu_clock", "gpu_fan",
            "mem_pct", "mem_used_gb",
            "net_down", "net_up", "net_down_x10", "net_up_x10",
            "fan_rpm", "hdd_load"
        };

        /// <summary>Validate and persist a config JSON. Returns null on success, error text otherwise.</summary>
        public static string SaveValidated(string json)
        {
            try
            {
                JavaScriptSerializer ser = new JavaScriptSerializer();
                Dictionary<string, object> root = ser.Deserialize<Dictionary<string, object>>(json);
                if (root == null) return "invalid json";

                string[] cpu = ValidPair(root, "cpu");
                if (cpu == null) return "bad cpu pair";
                string[] gpu = ValidPair(root, "gpu");
                if (gpu == null) return "bad gpu pair";

                string time = (root.ContainsKey("time") && root["time"] != null)
                    ? Convert.ToString(root["time"]).Trim() : "auto";
                if (!IsValidTimeSpec(time)) return "bad time spec";

                int iv = 500;
                if (root.ContainsKey("interval_ms") && root["interval_ms"] != null)
                {
                    if (!int.TryParse(Convert.ToString(root["interval_ms"]), out iv)) return "bad interval";
                    if (iv < 100 || iv > 5000) return "interval out of range (100-5000)";
                }

                Dictionary<string, object> canon = new Dictionary<string, object>();
                canon["cpu"] = cpu;
                canon["gpu"] = gpu;
                canon["time"] = time;
                canon["interval_ms"] = iv;

                if (!Directory.Exists(Dir)) Directory.CreateDirectory(Dir);
                File.WriteAllText(FilePath, new JavaScriptSerializer().Serialize(canon), new UTF8Encoding(false));
                return null;
            }
            catch (Exception ex) { return "exc: " + ex.Message; }
        }

        private static string[] ValidPair(Dictionary<string, object> root, string key)
        {
            string[] pair = ParsePair(root, key);
            if (pair == null) return null;
            for (int i = 0; i < 2; i++)
            {
                string t = pair[i];
                if (string.IsNullOrEmpty(t)) t = "auto";
                int dummy;
                if (t == "auto" || int.TryParse(t, out dummy)) { }
                else if (Array.IndexOf(KnownSources, t) < 0) return null;
                pair[i] = t;
            }
            return pair;
        }

        private static bool IsValidTimeSpec(string s)
        {
            if (string.IsNullOrEmpty(s) || s == "auto" || s == "timer") return true;
            if (s.StartsWith("timer_from:")) return IsValidMmSs(s.Substring("timer_from:".Length));
            if (s.StartsWith("timer_paused:")) return IsValidMmSs(s.Substring("timer_paused:".Length));
            if (s.StartsWith("timer_down_paused:")) return IsValidMmSs(s.Substring("timer_down_paused:".Length));
            if (s.StartsWith("timer_down:")) return IsValidMmSs(s.Substring("timer_down:".Length));
            if (s.Length > 1 && (s[0] == '+' || s[0] == '-'))
            {
                int m;
                return int.TryParse(s.Substring(1), out m) && m >= 0 && m <= 720;
            }
            string[] parts = s.Split(':');
            if (parts.Length == 2)
            {
                int h; int mi;
                return int.TryParse(parts[0], out h) && int.TryParse(parts[1], out mi) && h >= 0 && h <= 99 && mi >= 0 && mi <= 59;
            }
            return false;
        }

        private static bool IsValidMmSs(string v)
        {
            string[] tt = v.Split(':');
            if (tt.Length != 2) return false;
            int tm; int ts;
            return int.TryParse(tt[0], out tm) && int.TryParse(tt[1], out ts) && tm >= 0 && tm <= 99 && ts >= 0 && ts <= 59;
        }

        public string Describe()
        {
            string a = Cpu == null ? "auto" : (Cpu[0] + "/" + Cpu[1]);
            string b = Gpu == null ? "auto" : (Gpu[0] + "/" + Gpu[1]);
            return "cpu:" + a + " gpu:" + b + " time:" + Time + " iv:" + IntervalMs;
        }
    }
}
