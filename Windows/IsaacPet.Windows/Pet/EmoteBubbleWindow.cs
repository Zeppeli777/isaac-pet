using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using IsaacPet.Windows.Core;
using IsaacPet.Windows.Sprites;
using Image = System.Windows.Controls.Image;

namespace IsaacPet.Windows.Pet;

/// <summary>
/// 桌宠头顶的游戏风表情气泡。气泡素材的尾巴大约在宽度 81% 处，
/// 摆放时让那一列对准桌宠中线（与游戏在以撒头顶的表现一致）。
/// 移植自 macOS 版 EmoteBubbleController。
/// </summary>
public sealed class EmoteBubbleWindow : TransparentTopmostWindow
{
    /// <summary>表情素材是 48px 网格精灵；放大两倍与 192px 的桌宠同量级，整数倍保持像素对齐。</summary>
    private const double Magnification = 2;

    /// <summary>尾巴尖端在素材内的横向位置（宽度占比）。</summary>
    private const double TailAnchor = 0.81;

    private readonly Image _image = new();
    private DispatcherTimer? _hideTimer;
    private Rect _petFrameDip;
    private ScreenBoundsDip _screenDip;

    public EmoteBubbleWindow()
    {
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.NearestNeighbor);
        Content = _image;
    }

    public bool IsShowing => IsVisible;

    public void Show(SpriteFrame spriteFrame, Rect petFrameDip, ScreenBoundsDip screenDip, double scale)
    {
        _petFrameDip = petFrameDip;
        _screenDip = screenDip;

        _hideTimer?.Stop();
        var size = spriteFrame.PixelWidth * Magnification * scale;
        Width = size;
        Height = spriteFrame.PixelHeight * Magnification * scale;
        _image.Source = spriteFrame.Image;
        UpdatePosition();
        Show();

        _hideTimer = new DispatcherTimer { Interval = SpeechBubblePolicy.EmoteDisplayDuration };
        _hideTimer.Tick += (_, _) => Hide();
        _hideTimer.Start();
    }

    public void UpdateAnchor(Rect petFrameDip, ScreenBoundsDip screenDip)
    {
        if (!IsShowing) return;
        _petFrameDip = petFrameDip;
        _screenDip = screenDip;
        UpdatePosition();
    }

    public void Hide()
    {
        _hideTimer?.Stop();
        _hideTimer = null;
        base.Hide(); // 调用 Window.Hide；直接写 Hide() 会递归到本方法。
    }

    public void Stop() => Hide();

    private void UpdatePosition()
    {
        if (_screenDip.Width <= 0 || _screenDip.Height <= 0) return;
        const double edgePadding = 8;
        var minimumX = _screenDip.MinX + edgePadding;
        var maximumX = Math.Max(minimumX, _screenDip.MaxX - Width - edgePadding);
        var originX = Math.Clamp(_petFrameDip.Left + _petFrameDip.Width / 2 - Width * TailAnchor, minimumX, maximumX);

        // 气泡底边悬在桌宠头顶上方 6 DIP；顶部放不下时贴住屏幕上缘。
        var bottom = _petFrameDip.Top - 6;
        var originY = Math.Max(bottom - Height, _screenDip.MinY + edgePadding);

        Left = originX;
        Top = originY;
    }
}
