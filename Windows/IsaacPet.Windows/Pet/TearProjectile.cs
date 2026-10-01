using System.Windows;
using IsaacPet.Windows.Platform;
using IsaacPet.Windows.Sprites;

namespace IsaacPet.Windows.Pet;

/// <summary>
/// 泪弹：离开枪口时没有向上的初速，重力把它从发射线往下拉，
/// 下坠到预算距离即视为射程尽头并爆裂。移植自 macOS 版 TearProjectile
/// （wiki 描述的泪弹机制：平抛 + 落点即射程）。
/// </summary>
public sealed class TearProjectile
{
    private const double Gravity = 120;     // DIP / 秒²，随外观缩放
    private const double DropBudget = 80;   // 低于发射线多少 DIP 后爆裂

    private readonly TearWindow _window;
    private readonly double _velocityX;
    private readonly double _velocityY; // 屏幕 DIP/秒（y 向下为正）
    private readonly double _centerX;   // 发射点（屏幕 DIP）
    private readonly double _centerY;
    private readonly double _baseSize;
    private readonly double _gravity;
    private readonly double _dropBudget;
    private double _elapsed;
    private double _verticalVelocity; // 屏幕坐标，向下为正
    private double _height;           // 距发射线高度（向上为正），持续下沉

    public bool Landed { get; private set; }

    public TearWindow Window => _window;

    public TearProjectile(
        SpriteFrame frame,
        double centerX,
        double centerY,
        double velocityX,
        double velocityY,
        double size,
        double scale,
        bool behindPet = false,
        IntPtr petHwnd = default)
    {
        _velocityX = velocityX;
        _velocityY = velocityY;
        _centerX = centerX;
        _centerY = centerY;
        _baseSize = size;
        _gravity = Gravity * scale;
        _dropBudget = DropBudget * scale;

        _window = new TearWindow(frame, size)
        {
            Left = centerX - size / 2,
            Top = centerY - size / 2,
        };
        _window.Show();
        if (behindPet && petHwnd != IntPtr.Zero)
        {
            // 上射泪弹从背面头的后方出发：排到桌宠窗口 z-order 之下，
            // 飞出轮廓前由桌宠遮住，而不是亮在头发上。
            Win32.PlaceWindowBelow(_window.Hwnd, petHwnd);
        }
    }

    public void Update(double delta)
    {
        _elapsed += delta;
        _verticalVelocity += _gravity * delta;
        _height -= _verticalVelocity * delta;
        // 下坠量就是射程：沉到发射线下方预算距离即爆裂。
        if (-_height >= _dropBudget)
        {
            Landed = true;
            return;
        }
        var time = _elapsed;
        _window.Left = _centerX + _velocityX * time - _baseSize / 2;
        _window.Top = _centerY + _velocityY * time - _height - _baseSize / 2;
    }

    public void Remove() => _window.Close();
}

/// <summary>泪弹落地后爆出的小水滴，边飞边淡出。移植自 macOS 版 TearDrop。</summary>
public sealed class TearDrop
{
    private const double Gravity = 520;
    private const double Lifetime = 0.36;

    private readonly TearWindow _window;
    private readonly double _originX;
    private readonly double _originY;
    private readonly double _velocityX;
    private readonly double _velocityY; // 屏幕 y 向下为正
    private readonly double _gravity;
    private double _elapsed;

    public TearDrop(
        SpriteFrame frame,
        double centerX,
        double centerY,
        double velocityX,
        double velocityY,
        double size,
        double scale)
    {
        _velocityX = velocityX;
        _velocityY = velocityY;
        _originX = centerX;
        _originY = centerY;
        _gravity = Gravity * scale;
        _window = new TearWindow(frame, size)
        {
            Left = centerX - size / 2,
            Top = centerY - size / 2,
        };
        _window.Show();
    }

    /// <summary>返回 true 表示水滴已消散。</summary>
    public bool Update(double delta)
    {
        _elapsed += delta;
        if (_elapsed >= Lifetime) return true;
        var time = _elapsed;
        _window.Left = _originX + _velocityX * time - _window.Width / 2;
        _window.Top = _originY + _velocityY * time + _gravity * time * time / 2 - _window.Width / 2;
        _window.Opacity = 1 - _elapsed / Lifetime;
        return false;
    }

    public void Remove() => _window.Close();
}
