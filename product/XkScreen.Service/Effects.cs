using System;

namespace XkScreen.Service
{
    /// <summary>
    /// Screen animation layer. Only digit values are controllable on this panel
    /// (colors and brightness are firmware-fixed), so every effect is a scripted
    /// sequence of values applied to six animation cells:
    ///   0-3 = rings: cpu top / cpu bottom / gpu top / gpu bottom
    ///   4-5 = clock area: left 2-digit group / right 2-digit group
    /// All cells take 0-99. The base values are the real ones the screen would
    /// show without the effect, so every animation can settle onto live data.
    /// </summary>
    internal static class Effects
    {
        public const string Off = "off";

        private static readonly string[] Modes = { "scroll", "chase", "rain", "wave", "counter", "glitch" };
        private static readonly string[] Shots = { "steinsgate", "boot", "burst" };
        private static readonly string[] TargetNames = { "clock", "rings", "all" };

        public static bool IsValidMode(string s)
        {
            if (s == null) return false;
            if (s == Off) return true;
            for (int i = 0; i < Modes.Length; i++) if (Modes[i] == s) return true;
            return false;
        }

        public static bool IsValidOneShot(string s)
        {
            if (s == null) return false;
            for (int i = 0; i < Shots.Length; i++) if (Shots[i] == s) return true;
            return false;
        }

        public static bool IsValidTarget(string s)
        {
            if (s == null) return false;
            for (int i = 0; i < TargetNames.Length; i++) if (TargetNames[i] == s) return true;
            return false;
        }

        // ---- one-shot state ----
        private static string oneName;
        private static string oneTarget = "all";
        private static DateTime oneStart;
        private static int oneDurationMs = 3000;
        private static int oneSpeedMs = 90;
        private static readonly double[] lockAt = new double[6];

        // ---- persistent animation state ----
        // Cosmetic digit flicker only - not a security primitive.
        private static long tick;
        private static readonly Random Rnd = new Random();
        private static readonly int[] scrollVals = new int[4];
        private static readonly int[] scrollDigits = new int[4];
        private static bool scrollReady;
        private static int scrollDigitSeq;
        private static readonly int[] glitchHold = new int[6];
        private static readonly int[] glitchVal = new int[6];

        public static string OneShot { get { return oneName; } }
        public static bool OneShotActive { get { return oneName != null; } }

        public static void StopOneShot() { oneName = null; }

        public static void StartOneShot(string name, string target, int durationMs, int speedMs)
        {
            oneName = name;
            oneTarget = IsValidTarget(target) ? target : "all";
            oneStart = DateTime.Now;
            if (durationMs < 200) durationMs = 200;
            if (durationMs > 15000) durationMs = 15000;
            if (speedMs < 60) speedMs = 60;
            if (speedMs > 1000) speedMs = 1000;
            oneDurationMs = durationMs;
            oneSpeedMs = speedMs;

            // Steins;Gate: cells lock onto the real value one by one in random
            // order (plus a little jitter), like the divergence meter settling.
            // Thresholds spread across the targeted cells only, so a clock-only
            // or rings-only scramble still uses the whole duration.
            int[] order = { 0, 1, 2, 3, 4, 5 };
            for (int i = 5; i > 0; i--)
            {
                int j = Rnd.Next(i + 1);
                int t = order[i]; order[i] = order[j]; order[j] = t;
            }
            int count = 0;
            for (int i = 0; i < 6; i++) if (InTarget(oneTarget, order[i])) count++;
            if (count < 1) count = 1;
            int k = 0;
            for (int i = 0; i < 6; i++)
            {
                int cell = order[i];
                if (!InTarget(oneTarget, cell)) { lockAt[cell] = 0.0; continue; }
                lockAt[cell] = 0.15 + 0.68 * (k + 1) / count + (Rnd.NextDouble() - 0.5) * 0.08;
                k++;
            }
        }

        /// <summary>True while any animation (persistent mode or one-shot) is running.</summary>
        public static bool Active(string cfgMode)
        {
            return oneName != null || (cfgMode != null && cfgMode != Off);
        }

        public static int SpeedMs(int cfgSpeed)
        {
            int s = oneName != null ? oneSpeedMs : cfgSpeed;
            if (s < 60) s = 60;
            if (s > 1000) s = 1000;
            return s;
        }

        public static string EffectiveTarget(string cfgTarget)
        {
            if (oneName != null) return oneTarget;
            return IsValidTarget(cfgTarget) ? cfgTarget : "all";
        }

        /// <summary>Advance one animation step and produce the six output cells
        /// (overrides on top of baseCells).</summary>
        public static void Step(string cfgMode, string cfgTarget, int[] baseCells, int[] outCells)
        {
            for (int i = 0; i < 6; i++) outCells[i] = baseCells[i];
            string target = EffectiveTarget(cfgTarget);

            if (oneName != null)
            {
                double p = (DateTime.Now - oneStart).TotalMilliseconds / Math.Max(1, oneDurationMs);
                if (p >= 1.0)
                {
                    oneName = null; // finished; fall back to the persistent mode (if any)
                }
                else
                {
                    ApplyOneShot(oneName, target, p, baseCells, outCells);
                    tick++;
                    return;
                }
            }
            if (cfgMode != null && cfgMode != Off) ApplyPersistent(cfgMode, target, baseCells, outCells);
            tick++;
        }

        // ---- one-shot effects ----

        private static void ApplyOneShot(string name, string target, double p, int[] baseCells, int[] outCells)
        {
            if (name == "steinsgate")
            {
                for (int i = 0; i < 6; i++)
                {
                    if (!InTarget(target, i)) continue;
                    outCells[i] = p < lockAt[i] ? Rnd.Next(100) : baseCells[i];
                }
            }
            else if (name == "boot")
            {
                for (int i = 0; i < 6; i++)
                {
                    if (!InTarget(target, i)) continue;
                    if (p < 0.22) outCells[i] = 88;                       // all-eights flash
                    else if (p < 0.9) outCells[i] = (baseCells[i] * (int)((p - 0.22) * 147)) / 100; // odometer ramp
                    else outCells[i] = baseCells[i];
                }
            }
            else if (name == "burst")
            {
                for (int i = 0; i < 6; i++)
                {
                    if (!InTarget(target, i)) continue;
                    if (Rnd.Next(100) < 65) outCells[i] = Rnd.Next(100);
                }
            }
        }

        // ---- persistent effects ----

        private static void ApplyPersistent(string mode, string target, int[] baseCells, int[] outCells)
        {
            if (mode == "scroll")
            {
                if (!scrollReady)
                {
                    scrollReady = true;
                    for (int i = 0; i < 4; i++) scrollVals[i] = baseCells[i];
                    for (int i = 0; i < 4; i++) scrollDigits[i] = Rnd.Next(10);
                    scrollDigitSeq = 0;
                }
                // rings: values travel around cpuTop -> cpuBottom -> gpuTop -> gpuBottom,
                // a fresh streamed value entering each step
                int nv = (scrollVals[3] + 3 + Rnd.Next(9)) % 100;
                scrollVals[0] = scrollVals[1];
                scrollVals[1] = scrollVals[2];
                scrollVals[2] = scrollVals[3];
                scrollVals[3] = nv;
                for (int i = 0; i < 4; i++) if (InTarget(target, i)) outCells[i] = scrollVals[i];

                // clock: four digits slide left, a running 0-9 stream entering
                for (int i = 0; i < 3; i++) scrollDigits[i] = scrollDigits[i + 1];
                scrollDigits[3] = scrollDigitSeq = (scrollDigitSeq + 1) % 10;
                int clockVal = scrollDigits[0] * 1000 + scrollDigits[1] * 100 + scrollDigits[2] * 10 + scrollDigits[3];
                if (InTarget(target, 4)) outCells[4] = (clockVal / 100) % 100;
                if (InTarget(target, 5)) outCells[5] = clockVal % 100;
            }
            else if (mode == "chase")
            {
                int count = target == "all" ? 6 : (target == "rings" ? 4 : 2);
                int first = target == "rings" ? 0 : (target == "clock" ? 4 : 0);
                int pos = first + (int)(tick % count);
                for (int i = 0; i < 6; i++) if (InTarget(target, i)) outCells[i] = baseCells[i];
                outCells[pos] = 88;
            }
            else if (mode == "rain")
            {
                for (int i = 0; i < 6; i++) if (InTarget(target, i)) outCells[i] = Rnd.Next(100);
            }
            else if (mode == "wave")
            {
                double phase = tick * 0.55;
                for (int i = 0; i < 6; i++)
                {
                    if (!InTarget(target, i)) continue;
                    double v = 49.5 + 49.5 * Math.Sin(phase + i * 1.05);
                    outCells[i] = (int)Math.Round(v);
                }
            }
            else if (mode == "counter")
            {
                for (int i = 0; i < 4; i++)
                    if (InTarget(target, i)) outCells[i] = (int)(tick * (2 + i * 3) % 100);
                long v = tick * 13 % 10000;
                if (InTarget(target, 4)) outCells[4] = (int)(v / 100);
                if (InTarget(target, 5)) outCells[5] = (int)(v % 100);
            }
            else if (mode == "glitch")
            {
                for (int i = 0; i < 6; i++)
                {
                    if (!InTarget(target, i)) continue;
                    if (glitchHold[i] > 0) { outCells[i] = glitchVal[i]; glitchHold[i]--; }
                    else if (Rnd.Next(100) < 9) { glitchVal[i] = Rnd.Next(100); glitchHold[i] = 1 + Rnd.Next(2); outCells[i] = glitchVal[i]; }
                }
            }
        }

        private static bool InTarget(string target, int cell)
        {
            if (target == "all") return true;
            if (target == "rings") return cell < 4;
            return cell >= 4; // "clock"
        }
    }
}
