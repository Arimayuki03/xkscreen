// Phase 1 长驻测试：让 TempComm 内部工作线程完成握手并持续发送 30 秒。
// 依据（RE-NOTES §7）：CheckOnlineDevice 内部为每台设备启动工作线程(0x30E4)，
// 线程内 30×100ms 重试打开设备，成功后做固件 hash 握手（LED/0x4445/0xBF81F43），
// 通过后进入 500ms 周期发送循环。Set* 仅写全局变量，由线程组包下发。

using System.Runtime.InteropServices;

namespace XkScreen;

internal static class Program
{
    [DllImport("HWCX")] private static extern int CheckOnlineDevice();
    [DllImport("HWCX")] private static extern int GetOnlineDeviceQty();
    [DllImport("HWCX")] private static extern int SetColor(int deviceIndex, byte[] rgba);

    private static int Main()
    {
        Console.WriteLine($"[T] {DateTime.Now:HH:mm:ss.fff} CheckOnlineDevice...");
        int online = CheckOnlineDevice();
        Console.WriteLine($"[T] online={online}, qty={GetOnlineDeviceQty()}");

        Console.WriteLine("[T] 等待 12s 让工作线程完成设备打开(30x100ms)+固件握手...");
        Thread.Sleep(12_000);

        byte[][] colors = { [0xFF, 0, 0, 0xFF], [0, 0xFF, 0, 0xFF], [0, 0, 0xFF, 0xFF] };
        string[] names = { "RED", "GREEN", "BLUE" };
        for (int round = 0; round < 3; round++)
        {
            Console.WriteLine($"[T] {DateTime.Now:HH:mm:ss.fff} SetColor {names[round]} -> {SetColor(0, colors[round])}");
            Thread.Sleep(6_000);
        }

        Console.WriteLine($"[T] {DateTime.Now:HH:mm:ss.fff} 保持 10s 后退出");
        Thread.Sleep(10_000);
        return 0;
    }
}
