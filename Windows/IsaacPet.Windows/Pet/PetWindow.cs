using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using IsaacPet.Windows.Platform;
using IsaacPet.Windows.Sprites;
using Image = System.Windows.Controls.Image;
using Point = System.Windows.Point;

namespace IsaacPet.Windows.Pet;

/// <summary>
/// 桌宠窗口：透明、无边框、置顶、不进任务栏。
/// 对应 macOS 版的 PetPanel（borderless + nonactivating + floating + 全工作区可见）。
/// </summary>
public class TransparentTopmostWindow : Window
{
    static TransparentTopmostWindow()
    {
        // 透明窗口不参与系统默认的命中测试优化，自行控制穿透。
    }

    public TransparentTopmostWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = System.Windows.Media.Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ShowActivated = false;
        SizeToContent = SizeToContent.Manual;
        ResizeMode = ResizeMode.NoResize;
        SourceInitialized += OnSourceInitialized;
    }

    public IntPtr Hwnd { get; private set; }

    /// <summary>窗口当前的 DIP 缩放（动态读取；不要在 SourceInitialized 时缓存）。</summary>
    public double PixelsPerDip
    {
        get
        {
            var dpi = VisualTreeHelper.GetDpi(this);
            return dpi.PixelsPerDip > 0 ? dpi.PixelsPerDip : 1.0;
        }
    }

    protected virtual bool IsClickThroughDefault => true;

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        Hwnd = new WindowInteropHelper(this).Handle;
        Win32.SetNoActivate(Hwnd, true);
        if (IsClickThroughDefault) Win32.SetClickThrough(Hwnd, true);
    }

    /// <summary>物理像素鼠标位置 → 窗口内 DIP 坐标。光标不在窗口内时返回 null。</summary>
    public Point? CursorLocalPosition()
    {
        var (px, py) = Win32.CursorPosition();
        var scale = PixelsPerDip;
        var dipX = px / scale;
        var dipY = py / scale;
        var local = new Point(dipX - Left, dipY - Top);
        if (local.X < 0 || local.Y < 0 || local.X >= Width || local.Y >= Height) return null;
        return local;
    }

    /// <summary>当前是否处于鼠标穿透状态。</summary>
    public bool IsClickThrough()
    {
        if (Hwnd == IntPtr.Zero) return false;
        var style = Win32.GetWindowLongPtr(Hwnd, Win32.GwlExStyle).ToInt64();
        return (style & Win32.WsExTransparent) != 0;
    }

    public void SetClickThrough(bool clickThrough)
    {
        if (Hwnd != IntPtr.Zero) Win32.SetClickThrough(Hwnd, clickThrough);
    }
}

/// <summary>桌宠主窗口，承载当前精灵帧。</summary>
public sealed class PetWindow : TransparentTopmostWindow
{
    private readonly Image _image;

    public PetWindow(double width, double height)
    {
        Width = width;
        Height = height;
        _image = new Image
        {
            Stretch = Stretch.Fill,
            Focusable = false,
            IsHitTestVisible = false, // 命中测试由控制器按像素 alpha 轮询决定
        };
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.NearestNeighbor);
        Content = _image;
    }

    protected override bool IsClickThroughDefault => false;

    public void SetFrame(SpriteFrame frame)
    {
        _image.Source = frame.Image;
    }
}

/// <summary>泪弹窗口：始终穿透鼠标，只负责绘制和飞行。</summary>
public sealed class TearWindow : TransparentTopmostWindow
{
    public TearWindow(SpriteFrame frame, double size)
    {
        Width = size;
        Height = size;
        var image = new Image
        {
            Source = frame.Image,
            Stretch = Stretch.Fill,
            IsHitTestVisible = false,
        };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.NearestNeighbor);
        Content = image;
    }
}
