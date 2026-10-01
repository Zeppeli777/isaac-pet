using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using IsaacPet.Windows.Core;
using IsaacPet.Windows.Sprites;
using Image = System.Windows.Controls.Image;
using Point = System.Windows.Point;

namespace IsaacPet.Windows.Pet;

/// <summary>
/// 在桌宠头顶播放抽牌揭示：卡牌绕竖直轴正反面洗牌两秒（带倾斜与浮动），
/// 向观看者放大展示结果，再落回原尺寸。文字面板（CardBubbleWindow）在其结束后接管。
/// 移植自 macOS 版 CardRevealController/CardSpinView；时间线由代码驱动，
/// 便于自检冻结关键时刻、控制器可随时取消。
/// </summary>
public sealed class CardRevealWindow : TransparentTopmostWindow
{
    private readonly Canvas _canvas = new();
    private readonly Image _cardImage = new();
    private DispatcherTimer? _timer;
    private TimeSpan _elapsed;
    private double _scale = 1;
    private double _cardWidth;
    private double _cardHeight;
    private Rect _petFrameDip;
    private ScreenBoundsDip _screenDip;
    private SpriteFrame? _front;
    private SpriteFrame? _back;

    public CardRevealWindow()
    {
        RenderOptions.SetBitmapScalingMode(_cardImage, BitmapScalingMode.NearestNeighbor);
        _canvas.Children.Add(_cardImage);
        Content = _canvas;
    }

    public bool IsShowing => IsVisible;

    /// <summary>面板必须容得下放大后的卡牌并留边距；变换超出过小的窗口会被裁掉。</summary>
    public void Prepare(SpriteFrame front, SpriteFrame back, Rect petFrameDip, ScreenBoundsDip screenDip, double scale)
    {
        _front = front;
        _back = back;
        _petFrameDip = petFrameDip;
        _screenDip = screenDip;
        _scale = scale;
        _cardWidth = front.PixelWidth * 4 * scale;
        _cardHeight = front.PixelHeight * 4 * scale;
        var factor = TarotDrawPolicy.ZoomScale * 1.15;
        Width = Math.Ceiling(_cardWidth * factor);
        Height = Math.Ceiling(_cardHeight * factor);
        _canvas.Width = Width;
        _canvas.Height = Height;
        _cardImage.Width = _cardWidth;
        _cardImage.Height = _cardHeight;
        _cardImage.Source = front.Image;
        _elapsed = TimeSpan.Zero;
        UpdatePosition();
        Show();
        Advance(_elapsed);
        _timer?.Stop();
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        _timer.Tick += (_, _) => Tick();
        _timer.Start();
    }

    private void Tick()
    {
        _elapsed += TimeSpan.FromMilliseconds(16);
        if (Advance(_elapsed)) Hide();
    }

    public void UpdateAnchor(Rect petFrameDip, ScreenBoundsDip screenDip)
    {
        if (!IsShowing) return;
        _petFrameDip = petFrameDip;
        _screenDip = screenDip;
        UpdatePosition();
    }

    public new void Hide()
    {
        _timer?.Stop();
        _timer = null;
        base.Hide();
    }

    public void Stop() => Hide();

    private void UpdatePosition()
    {
        if (_screenDip.Width <= 0 || _screenDip.Height <= 0) return;
        const double edgePadding = 8;
        var minimumX = _screenDip.MinX + edgePadding;
        var maximumX = Math.Max(minimumX, _screenDip.MaxX - Width - edgePadding);
        var originX = Math.Clamp(_petFrameDip.Left + _petFrameDip.Width / 2 - Width / 2, minimumX, maximumX);

        // 卡牌悬浮在桌宠头顶约一个卡牌高度的位置，桌宠在下方走动时它保持不动。
        var centerY = _petFrameDip.Top - _cardHeight;
        var originY = Math.Clamp(
            centerY - Height / 2,
            _screenDip.MinY + edgePadding,
            Math.Max(_screenDip.MinY + edgePadding, _screenDip.MaxY - Height - edgePadding));
        Left = originX;
        Top = originY;
    }

    /// <summary>推进洗牌 → 放大 → 回落时间线；返回 true 表示卡牌已落定。</summary>
    private bool Advance(TimeSpan elapsed)
    {
        if (_front == null || _back == null) return true;
        var spin = TarotDrawPolicy.SpinDuration.TotalSeconds;
        var zoomIn = TarotDrawPolicy.ZoomInDuration.TotalSeconds;
        var hold = TarotDrawPolicy.ZoomHoldDuration.TotalSeconds;
        var zoomOut = TarotDrawPolicy.ZoomOutDuration.TotalSeconds;
        var zoomScale = TarotDrawPolicy.ZoomScale;
        var t = elapsed.TotalSeconds;

        double angle;
        var tilt = TarotDrawPolicy.TiltDegrees;
        var zoom = 1.0;
        var bobbing = true;
        if (t < spin)
        {
            var progress = t / spin;
            // 两次完整的正反面旋转，缓出进入揭示。
            angle = Math.PI * 4 * EaseInOutCubic(progress);
        }
        else if (t < spin + zoomIn)
        {
            angle = Math.PI * 4;
            var progress = (t - spin) / zoomIn;
            tilt *= 1 - EaseOutCubic(progress);
            zoom = 1 + (zoomScale - 1) * EaseOutBack(progress);
            bobbing = false;
        }
        else if (t < spin + zoomIn + hold)
        {
            angle = Math.PI * 4;
            tilt = 0;
            zoom = zoomScale;
            bobbing = false;
        }
        else if (t < spin + zoomIn + hold + zoomOut)
        {
            angle = Math.PI * 4;
            tilt = 0;
            var progress = (t - spin - zoomIn - hold) / zoomOut;
            zoom = zoomScale + (1 - zoomScale) * progress * progress;
            bobbing = false;
        }
        else
        {
            _cardImage.Source = _front.Image;
            _cardImage.RenderTransform = Transform.Identity;
            return true;
        }

        // 竖直轴旋转的正交近似：横向按 |cos| 缩放，卡牌侧过边缘时显示卡背。
        var cos = Math.Cos(angle);
        _cardImage.Source = (cos >= 0 ? _front : _back).Image;
        var scaleX = Math.Max(0.02, Math.Abs(cos));
        var bob = bobbing ? Math.Sin(t * 2 * Math.PI / 1.2) * 4 : 0;
        _cardImage.RenderTransformOrigin = new Point(0.5, 0.5);
        var group = new TransformGroup();
        group.Children.Add(new ScaleTransform(zoom * scaleX, zoom));
        group.Children.Add(new RotateTransform(tilt));
        _cardImage.RenderTransform = group;
        Canvas.SetLeft(_cardImage, _canvas.Width / 2 - _cardWidth / 2);
        Canvas.SetTop(_cardImage, _canvas.Height / 2 - _cardHeight / 2 + bob);
        return false;
    }

    private static double EaseInOutCubic(double progress) =>
        progress < 0.5 ? 4 * progress * progress * progress : 1 - Math.Pow(-2 * progress + 2, 3) / 2;

    private static double EaseOutCubic(double progress) => 1 - Math.Pow(1 - progress, 3);

    private static double EaseOutBack(double progress)
    {
        const double overshoot = 1.70158;
        var c3 = overshoot + 1;
        return 1 + c3 * Math.Pow(progress - 1, 3) + overshoot * Math.Pow(progress - 1, 2);
    }
}
