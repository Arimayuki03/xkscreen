using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Drawing = System.Drawing;
using WinForms = System.Windows.Forms;

namespace XkScreen.Gui
{
    public partial class MainWindow : Window
    {
        private const string Api = "http://127.0.0.1:8899";
        private static readonly HttpClient Http = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr ShellExecute(IntPtr hwnd, string lpOperation, string lpFile, string lpParameters, string lpDirectory, int nShowCmd);

        [DllImport("psapi.dll")]
        private static extern bool EmptyWorkingSet(IntPtr hProcess);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr hwnd);

        /// <summary>WebView2 is created on demand and disposed while the window is
        /// hidden to the tray, so the msedgewebview2 process tree does not keep
        /// idling in the background.</summary>
        private Microsoft.Web.WebView2.Wpf.WebView2 Web;
        private static Mutex singleInstance;
        private static EventWaitHandle showRequest;

        private WinForms.NotifyIcon tray;
        private WinForms.ToolStripMenuItem miStatus;
        private DispatcherTimer tipTimer;
        private bool closeToTray = true;
        private bool reallyExit;
        private string lastStatusText = "连接中…";

        public MainWindow()
        {
            // Single instance: a second launch (e.g. double-clicking the desktop
            // icon while the window sits in the tray) just asks the running
            // instance to show its window, instead of starting a duplicate.
            showRequest = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\XkScreenGuiShowRequest");
            bool createdNew;
            singleInstance = new Mutex(true, @"Local\XkScreenGuiSingleInstance", out createdNew);
            if (!createdNew)
            {
                try { showRequest.Set(); } catch { }
                Environment.Exit(0);
                return;
            }
            InitializeComponent();
            Loaded += OnLoaded;
            Closing += OnClosing;
        }

        /// <summary>
        /// The console is a wide dashboard: the rings sit side by side, everything
        /// else is a full-width card, and the whole page fits in ~1520x1360 DIPs.
        /// Open at that size when the screen allows it, otherwise fill the working
        /// area, and centre it there. Runs before the window is shown, so the size
        /// and position never visibly jump (WPF's CenterScreen mis-centres when the
        /// monitor scale is not 100%).
        /// </summary>
        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            try
            {
                // SystemParameters.WorkArea is reported at the system DPI, so convert
                // it to DIPs with the window's own monitor scale (e.g. 150%).
                double scale = GetDpiForWindow(new WindowInteropHelper(this).Handle) / 96.0;
                if (scale <= 0) scale = 1.0;
                double areaLeft = SystemParameters.WorkArea.Left / scale;
                double areaTop = SystemParameters.WorkArea.Top / scale;
                double areaW = SystemParameters.WorkArea.Width / scale;
                double areaH = SystemParameters.WorkArea.Height / scale;
                Width = Math.Min(1520, Math.Max(1100, areaW - 40));
                Height = Math.Min(1360, Math.Max(720, areaH - 30));
                Left = areaLeft + Math.Max(0, (areaW - Width) / 2);
                Top = areaTop + Math.Max(0, (areaH - Height) / 2);
            }
            catch { }
        }

        // ---- window chrome ----

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ClickCount == 2)
            {
                ToggleMax();
                return;
            }
            if (e.ButtonState == MouseButtonState.Pressed && WindowState != WindowState.Maximized)
                DragMove();
        }

        private void ToggleMax()
        {
            WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        }

        private void BtnMin_Click(object sender, RoutedEventArgs e)
        {
            WindowState = WindowState.Minimized;
        }

        private void BtnMax_Click(object sender, RoutedEventArgs e)
        {
            ToggleMax();
        }

        private void BtnClose_Click(object sender, RoutedEventArgs e)
        {
            Close(); // Closing handler decides: hide to tray or exit
        }

        private void OnClosing(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (!reallyExit && closeToTray)
            {
                e.Cancel = true;
                Hide();
                ReleaseWeb();
            }
        }

        private async void RestoreWindow()
        {
            Show();
            if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
            Activate();
            await EnsureWebAsync();
        }

        private void ShowAbout()
        {
            string ver = "";
            try { ver = " v" + System.Reflection.Assembly.GetExecutingAssembly().GetName().Version.ToString(3); }
            catch { }
            WinForms.MessageBox.Show(
                "XkScreen 星璨屏幕控制台" + ver + "\n\n"
                + "适用于：爱国者星璨小岚机箱小屏（Xingcan Xiaolan / XK003）\n"
                + "用途：把小屏的 CPU/GPU 圆环与时钟区变成任意数据的显示面板，\n"
                + "并提供动画效果、开关屏与定时、网页控制台等能力。\n\n"
                + "原版驱动下载：https://www.aigodiy.com/HuaqiHOMEAPP/index.aspx\n"
                + "项目主页：https://github.com/Arimayuki03/xkscreen\n\n"
                + "开源软件（MIT 许可）。屏幕通信与传感器数据复用原版驱动组件。",
                "关于 XkScreen", WinForms.MessageBoxButtons.OK, WinForms.MessageBoxIcon.Information);
        }

        // ---- tray ----

        private void SetupTray()
        {
            tray = new WinForms.NotifyIcon();
            try
            {
                tray.Icon = Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath);
            }
            catch { }
            tray.Text = "XkScreen 屏幕控制台";

            var menu = new WinForms.ContextMenuStrip();
            var miShow = new WinForms.ToolStripMenuItem("显示窗口");
            miShow.Click += (s, e) => RestoreWindow();
            var miWeb = new WinForms.ToolStripMenuItem("在浏览器中打开");
            miWeb.Click += (s, e) =>
            {
                // 固定本机 URL，交给 shell32 打开系统默认浏览器
                try { ShellExecute(IntPtr.Zero, "open", "http://127.0.0.1:8899/", null, null, 1); } catch { }
            };
            miStatus = new WinForms.ToolStripMenuItem("连接中…") { Enabled = false };
            var miOn = new WinForms.ToolStripMenuItem("打开屏幕");
            miOn.Click += async (s, e) => await SetScreenAsync(true);
            var miOff = new WinForms.ToolStripMenuItem("关闭屏幕");
            miOff.Click += async (s, e) => await SetScreenAsync(false);
            var miCloseMode = new WinForms.ToolStripMenuItem("关闭窗口时收进托盘")
            {
                CheckOnClick = true,
                Checked = closeToTray,
            };
            miCloseMode.CheckedChanged += (s, e) =>
            {
                closeToTray = miCloseMode.Checked;
                SaveGuiSettings();
            };
            var miAbout = new WinForms.ToolStripMenuItem("关于 XkScreen");
            miAbout.Click += (s, e) => ShowAbout();
            menu.Items.Add(miAbout);

            var miExit = new WinForms.ToolStripMenuItem("退出程序");
            miExit.Click += (s, e) =>
            {
                reallyExit = true;
                try { tray.Visible = false; } catch { }
                Close();
            };

            menu.Items.Add(miShow);
            menu.Items.Add(miWeb);
            menu.Items.Add(new WinForms.ToolStripSeparator());
            menu.Items.Add(miStatus);
            menu.Items.Add(new WinForms.ToolStripSeparator());
            menu.Items.Add(miOn);
            menu.Items.Add(miOff);
            menu.Items.Add(new WinForms.ToolStripSeparator());
            menu.Items.Add(miCloseMode);
            menu.Items.Add(new WinForms.ToolStripSeparator());
            menu.Items.Add(miExit);

            tray.ContextMenuStrip = menu;
            tray.DoubleClick += (s, e) => RestoreWindow();
            tray.Visible = true;
        }

        // ---- live data for the tooltip / tray menu ----

        private async Task UpdateStatusAsync()
        {
            try
            {
                string j = await Http.GetStringAsync(Api + "/status");
                using JsonDocument doc = JsonDocument.Parse(j);
                JsonElement root = doc.RootElement;
                JsonElement s = root.GetProperty("sensors");
                string cpu = Fmt(s, "cpu_load") + "%/" + Fmt(s, "cpu_temp") + "C";
                string gpu = Fmt(s, "gpu_load") + "%/" + Fmt(s, "gpu_temp") + "C";
                string mem = Fmt(s, "mem_pct") + "%";
                bool off = root.TryGetProperty("screen", out JsonElement se) && se.GetString() == "off";
                lastStatusText = "CPU " + cpu + "  GPU " + gpu + "  RAM " + mem + (off ? "  屏幕:关" : "");
                RefreshTrayText();
                if (miStatus != null) miStatus.Text = "CPU " + cpu + "   GPU " + gpu + "   内存 " + mem + (off ? "   屏幕已关闭" : "");
            }
            catch
            {
                lastStatusText = "未连接驱动服务";
                RefreshTrayText();
                if (miStatus != null) miStatus.Text = "未连接驱动服务（127.0.0.1:8899）";
            }
        }

        private static string Fmt(JsonElement s, string key)
        {
            if (s.TryGetProperty(key, out JsonElement v) && v.ValueKind == JsonValueKind.Number)
                return Math.Round(v.GetDouble()).ToString("0");
            return "-";
        }

        private void RefreshTrayText()
        {
            try
            {
                if (tray == null) return;
                string t = "XkScreen · " + lastStatusText;
                if (t.Length > 63) t = t.Substring(0, 60) + "...";
                tray.Text = t;
            }
            catch { }
        }

        /// <summary>Merge the current driver config with a screen off/on switch and save it.</summary>
        private async Task SetScreenAsync(bool on)
        {
            try
            {
                string j = await Http.GetStringAsync(Api + "/status");
                using JsonDocument doc = JsonDocument.Parse(j);
                JsonElement cfg = doc.RootElement.GetProperty("config");
                var body = new Dictionary<string, object>();
                body["cpu"] = cfg.GetProperty("cpu").Clone();
                body["gpu"] = cfg.GetProperty("gpu").Clone();
                body["time"] = cfg.TryGetProperty("time", out JsonElement te) ? te.GetString() : "auto";
                body["interval_ms"] = cfg.TryGetProperty("interval_ms", out JsonElement ie) ? ie.GetInt32() : 500;
                body["screen"] = on ? "on" : "off";
                if (cfg.TryGetProperty("schedule", out JsonElement sch) && sch.ValueKind == JsonValueKind.Object)
                    body["schedule"] = sch.Clone();
                using var content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");
                await Http.PostAsync(Api + "/config", content);
                await UpdateStatusAsync();
            }
            catch { }
        }

        // ---- gui settings (close-to-tray preference) ----

        private static string GuiSettingsPath()
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "XkScreen", "gui.json");
        }

        private void LoadGuiSettings()
        {
            try
            {
                string p = GuiSettingsPath();
                if (File.Exists(p))
                {
                    using JsonDocument d = JsonDocument.Parse(File.ReadAllText(p));
                    if (d.RootElement.TryGetProperty("closeToTray", out JsonElement c))
                        closeToTray = c.GetBoolean();
                }
            }
            catch { }
        }

        private void SaveGuiSettings()
        {
            try
            {
                string p = GuiSettingsPath();
                Directory.CreateDirectory(Path.GetDirectoryName(p));
                File.WriteAllText(p, JsonSerializer.Serialize(new { closeToTray }));
            }
            catch { }
        }

        // ---- startup ----

        private async void OnLoaded(object sender, RoutedEventArgs e)
        {
            LoadGuiSettings();
            SetupTray();

            tipTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
            tipTimer.Tick += async (s, args) => await UpdateStatusAsync();
            tipTimer.Start();
            await UpdateStatusAsync();

            // While the window lives in the tray, trim the working set periodically:
            // the runtime pages its used pages back in over time, and without a trim
            // the tray footprint creeps from ~7 MB towards ~20 MB.
            DispatcherTimer trimTimer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(3) };
            trimTimer.Tick += (s, args) =>
            {
                if (!IsVisible) { try { EmptyWorkingSet(GetCurrentProcess()); } catch { } }
            };
            trimTimer.Start();

            // A second launch (desktop icon while running in the tray) asks this
            // instance to show its window; there is only ever one console process.
            Thread listener = new Thread(delegate ()
            {
                try
                {
                    while (true)
                    {
                        if (!showRequest.WaitOne()) break;
                        Dispatcher.BeginInvoke(new Action(delegate () { RestoreWindow(); }));
                    }
                }
                catch { }
            });
            listener.IsBackground = true;
            listener.Start();

            await EnsureWebAsync();
        }

        // ---- console autostart (HKCU Run value, the same one the installer writes) ----

        private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string RunValueName = "XkScreen";

        private static bool GetAutostart()
        {
            try
            {
                using (Microsoft.Win32.RegistryKey k =
                    Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunKeyPath))
                    return k != null && k.GetValue(RunValueName) != null;
            }
            catch { return false; }
        }

        private static bool SetAutostart(bool on)
        {
            try
            {
                using (Microsoft.Win32.RegistryKey k =
                    Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunKeyPath, true))
                {
                    if (k == null) return GetAutostart();
                    if (on)
                    {
                        string exe = Environment.ProcessPath;
                        if (string.IsNullOrEmpty(exe)) return GetAutostart();
                        k.SetValue(RunValueName, "\"" + exe + "\"");
                    }
                    else
                    {
                        k.DeleteValue(RunValueName, false);
                    }
                }
            }
            catch { }
            return GetAutostart();
        }

        private void SendAutostart()
        {
            try
            {
                Web.CoreWebView2.PostWebMessageAsJson(
                    "{\"type\":\"autostart\",\"value\":"
                    + (GetAutostart() ? "true" : "false") + "}");
            }
            catch { }
        }

        private void OnWebMessageReceived(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            try
            {
                using (JsonDocument doc = JsonDocument.Parse(e.WebMessageAsJson))
                {
                    JsonElement root = doc.RootElement;
                    string cmd = root.TryGetProperty("cmd", out JsonElement c) ? c.GetString() : null;
                    if (cmd == "autostart.get")
                    {
                        SendAutostart();
                    }
                    else if (cmd == "autostart.set")
                    {
                        bool on = root.TryGetProperty("value", out JsonElement v)
                                  && v.ValueKind == JsonValueKind.True;
                        SetAutostart(on);
                        SendAutostart();
                    }
                }
            }
            catch { }
        }

        /// <summary>Create the WebView2 and navigate to the console. Called on
        /// startup and again whenever the window is shown after a tray hide.</summary>
        private async Task EnsureWebAsync()
        {
            if (Web != null && Web.CoreWebView2 != null) return;
            try
            {
                Web = new Microsoft.Web.WebView2.Wpf.WebView2();
                try { Web.DefaultBackgroundColor = Drawing.Color.FromArgb(13, 18, 25); } catch { }
                WebHost.Children.Add(Web);

                // Keep the page's polling running even when the window is unfocused or
                // occluded, and render with the software rasteriser: the UI is light
                // static content, so dropping the GPU process saves memory.
                const string flags =
                    "--disable-background-timer-throttling --disable-backgrounding-occluded-windows "
                    + "--disable-renderer-backgrounding --disable-gpu";
                CoreWebView2Environment env = await CoreWebView2Environment.CreateAsync(
                    null, null, new CoreWebView2EnvironmentOptions(flags));
                await Web.EnsureCoreWebView2Async(env);

                // The page cannot touch the registry itself, so the console's
                // "start with Windows" switch is served over the WebView2 message
                // bridge (only present in the desktop console, not in a browser).
                Web.CoreWebView2.WebMessageReceived += OnWebMessageReceived;

                // Primary source: the copy hosted by the driver service (same one any
                // browser sees at http://127.0.0.1:8899/). Fall back to the embedded
                // copy via a virtual host when the service is not up yet.
                string wwwroot = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "web");
                if (!Directory.Exists(wwwroot))
                {
                    string alt = Path.GetFullPath(Path.Combine(
                        AppDomain.CurrentDomain.BaseDirectory, @"..\..\..\..\frontend\out"));
                    if (Directory.Exists(alt)) wwwroot = alt;
                }
                bool fallbackReady = Directory.Exists(wwwroot);
                if (fallbackReady)
                {
                    Web.CoreWebView2.SetVirtualHostNameToFolderMapping(
                        "xkscreen.local", wwwroot, CoreWebView2HostResourceAccessKind.Allow);
                }

                bool fellBack = false;
                EventHandler<CoreWebView2NavigationCompletedEventArgs> handler = null;
                handler = (s, args) =>
                {
                    if (args.IsSuccess)
                    {
                        Web.CoreWebView2.NavigationCompleted -= handler;
                        return;
                    }
                    if (!fellBack && fallbackReady)
                    {
                        fellBack = true;
                        Web.CoreWebView2.Navigate("https://xkscreen.local/index.html");
                    }
                    else
                    {
                        Web.CoreWebView2.NavigationCompleted -= handler;
                    }
                };
                Web.CoreWebView2.NavigationCompleted += handler;
                Web.CoreWebView2.Navigate(Api + "/");
            }
            catch (Exception ex)
            {
                MessageBox.Show("界面初始化失败: " + ex.Message);
            }
        }

        /// <summary>Dispose the WebView2 - which frees the whole msedgewebview2
        /// process tree (100+ MB) - and trim our working set, for the tray state.</summary>
        private void ReleaseWeb()
        {
            try
            {
                if (Web != null)
                {
                    try { if (Web.CoreWebView2 != null) Web.CoreWebView2.Stop(); } catch { }
                    WebHost.Children.Remove(Web);
                    Web.Dispose();
                }
            }
            catch { }
            Web = null;
            try { EmptyWorkingSet(GetCurrentProcess()); } catch { }
        }
    }
}
