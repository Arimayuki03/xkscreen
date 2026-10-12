using System;
using System.IO;

namespace XkScreen.Service
{
    internal static class Log
    {
        private static readonly object Gate = new object();
        private static string path;

        public static void Init()
        {
            path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "xkscreen_service.log");
        }

        public static void Write(string msg)
        {
            string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "\t" + msg;
            lock (Gate)
            {
                try { File.AppendAllText(path, line + Environment.NewLine); }
                catch { }
            }
            try { Console.WriteLine(line); }
            catch { }
        }
    }
}
