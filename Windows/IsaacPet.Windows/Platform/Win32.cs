using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using IsaacPet.Windows.Core;
using Microsoft.Win32;

namespace IsaacPet.Windows.Platform;

internal static class Win32
{
    public const int GwlExStyle = -20;
    public const int WsExTransparent = 0x00000020;
    public const int WsExNoActivate = 0x08000000;
    public const int WsExToolWindow = 0x00000080;

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hwnd, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtr64(IntPtr hwnd, int index, IntPtr value);

    public static IntPtr GetWindowLongPtr(IntPtr hwnd, int index) => GetWindowLongPtr64(hwnd, index);

    public static void SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value) => SetWindowLongPtr64(hwnd, index, value);

    /// <summary>物理像素坐标的鼠标位置。</summary>
    public static (int X, int Y) CursorPosition()
    {
        GetCursorPos(out var point);
        return (point.X, point.Y);
    }

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromPoint(POINT point, uint flags);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

    private const uint MonitorDefaultToNearest = 2;
    private const int MdtEffectiveDpi = 0;

    /// <summary>指定物理像素坐标所在显示器的 DPI 缩放（96 DPI = 1.0）。</summary>
    public static double DipScaleAt(int physicalX, int physicalY)
    {
        var monitor = MonitorFromPoint(new POINT { X = physicalX, Y = physicalY }, MonitorDefaultToNearest);
        if (GetDpiForMonitor(monitor, MdtEffectiveDpi, out var dpiX, out _) == 0 && dpiX > 0)
        {
            return dpiX / 96.0;
        }
        return 1.0;
    }

    public static void SetClickThrough(IntPtr hwnd, bool clickThrough)
    {
        var style = GetWindowLongPtr(hwnd, GwlExStyle).ToInt64();
        var has = (style & WsExTransparent) != 0;
        if (has == clickThrough) return;
        style = clickThrough ? style | WsExTransparent : style & ~WsExTransparent;
        SetWindowLongPtr(hwnd, GwlExStyle, new IntPtr(style));
    }

    public static void SetNoActivate(IntPtr hwnd, bool noActivate)
    {
        var style = GetWindowLongPtr(hwnd, GwlExStyle).ToInt64();
        var has = (style & WsExNoActivate) != 0;
        if (has == noActivate) return;
        style = noActivate ? style | WsExNoActivate : style & ~WsExNoActivate;
        SetWindowLongPtr(hwnd, GwlExStyle, new IntPtr(style));
    }
}

/// <summary>
/// 屏幕工作区辅助：基于 WinForms Screen（物理像素），按各显示器自身 DPI 换算为 DIP。
/// 注意：不使用桌宠窗口的 DpiScale——窗口初始化时尚未定位到目标显示器，读到的缩放不可靠。
/// </summary>
public sealed class ScreenInfo
{
    public required string Identifier { get; init; }
    public required bool IsPrimary { get; init; }
    public required ScreenBoundsDip WorkingArea { get; init; }

    public static List<ScreenInfo> All()
    {
        return System.Windows.Forms.Screen.AllScreens
            .Select(s =>
            {
                var scale = Win32.DipScaleAt(s.WorkingArea.Left + 10, s.WorkingArea.Top + 10);
                return new ScreenInfo
                {
                    Identifier = s.DeviceName,
                    IsPrimary = s.Primary,
                    WorkingArea = new ScreenBoundsDip(
                        s.WorkingArea.Left / scale,
                        s.WorkingArea.Top / scale,
                        s.WorkingArea.Width / scale,
                        s.WorkingArea.Height / scale),
                };
            })
            .ToList();
    }

    public static ScreenInfo Primary() =>
        All().FirstOrDefault(s => s.IsPrimary) ?? All()[0];
}

/// <summary>“登录时启动”通过注册表 Run 键实现（对应 macOS 的 SMAppService）。</summary>
public static class StartupRegistration
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Isaac Pet";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: false);
            return key?.GetValue(ValueName) is string;
        }
    }

    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)
            ?? throw new InvalidOperationException("无法打开启动项注册表。");
        if (enabled)
        {
            var exe = Environment.ProcessPath
                ?? throw new InvalidOperationException("无法定位当前可执行文件。");
            key.SetValue(ValueName, $"\"{exe}\"");
        }
        else
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }
}
