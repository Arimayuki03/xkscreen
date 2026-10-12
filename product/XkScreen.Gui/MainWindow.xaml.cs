using System;
using System.IO;
using System.Windows;
using System.Windows.Input;
using Microsoft.Web.WebView2.Core;

namespace XkScreen.Gui
{
    public partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
            Loaded += OnLoaded;
        }

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
            Close();
        }

        private async void OnLoaded(object sender, RoutedEventArgs e)
        {
            try
            {
                // Keep the page's polling running even when the window is unfocused or
                // occluded, and render with the software rasteriser: the UI is light
                // static content, so dropping the GPU process saves memory.
                const string flags =
                    "--disable-background-timer-throttling --disable-backgrounding-occluded-windows "
                    + "--disable-renderer-backgrounding --disable-gpu";
                CoreWebView2Environment env = await CoreWebView2Environment.CreateAsync(
                    null, null, new CoreWebView2EnvironmentOptions(flags));
                await Web.EnsureCoreWebView2Async(env);

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
                Web.CoreWebView2.Navigate("http://127.0.0.1:8899/");
            }
            catch (Exception ex)
            {
                MessageBox.Show("界面初始化失败: " + ex.Message);
            }
        }
    }
}
