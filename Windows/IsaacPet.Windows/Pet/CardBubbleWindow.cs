using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using IsaacPet.Windows.Core;
using IsaacPet.Windows.Sprites;
using IsaacPet.Windows.Ui.Pixel;
using Color = System.Windows.Media.Color;
using Image = System.Windows.Controls.Image;
using Rectangle = System.Windows.Shapes.Rectangle;
using Size = System.Windows.Size;

namespace IsaacPet.Windows.Pet;

/// <summary>
/// 抽牌结果面板：像素纸面上放卡面图标、牌名和领取祝福语。
/// 与语音、表情气泡一样是非激活浮动窗，三者同时只显示一个。
/// 移植自 macOS 版 CardBubbleController/CardPanelView。
/// </summary>
public sealed class CardBubbleWindow : TransparentTopmostWindow
{
    private enum TailEdge { Top, Bottom }

    private const double TailHeight = 12;
    private const double FrameBorder = 3;
    private const double Radius = 5;
    private const double PanelPadding = 10;
    private const double IconGap = 12;
    private const double TextGap = 6;
    private const double MaximumTextWidth = 190;
    /// <summary>卡面图标是 14×18 的 HUD 精灵；4 倍保持与桌宠同量级且像素对齐。</summary>
    private const double IconMagnification = 4;

    private readonly Canvas _canvas = new();
    private DispatcherTimer? _hideTimer;
    private TarotCard? _card;
    private SpriteFrame? _icon;
    private double _scale = 1;
    private TailEdge _tailEdge = TailEdge.Bottom;
    private double _tailX = 120;
    private Rect _petFrameDip;
    private ScreenBoundsDip _screenDip;

    public CardBubbleWindow()
    {
        Content = _canvas;
    }

    public bool IsShowing => IsVisible;

    public void Show(TarotCard card, SpriteFrame icon, Rect petFrameDip, ScreenBoundsDip screenDip, double scale)
    {
        _card = card;
        _icon = icon;
        _petFrameDip = petFrameDip;
        _screenDip = screenDip;
        _scale = scale;

        _hideTimer?.Stop();
        var size = FittingSize();
        Width = size.Width;
        Height = size.Height;
        UpdatePosition();
        Redraw();
        Show();

        _hideTimer = new DispatcherTimer { Interval = TarotDrawPolicy.CardPanelDisplayDuration };
        _hideTimer.Tick += (_, _) => Hide();
        _hideTimer.Start();
    }

    public void UpdateAnchor(Rect petFrameDip, ScreenBoundsDip screenDip)
    {
        if (!IsShowing) return;
        _petFrameDip = petFrameDip;
        _screenDip = screenDip;
        UpdatePosition();
        Redraw();
    }

    public new void Hide()
    {
        _hideTimer?.Stop();
        _hideTimer = null;
        base.Hide();
    }

    public void Stop() => Hide();

    private double IconWidth => _icon == null ? 0 : _icon.PixelWidth * IconMagnification * _scale;
    private double IconHeight => _icon == null ? 0 : _icon.PixelHeight * IconMagnification * _scale;

    private (string Title, string PickupZh, string PickupEn) TextLines() => _card == null
        ? ("", "", "")
        : (TarotDrawPolicy.DisplayTitle(_card), _card.PickupZh, _card.PickupEn);

    private double LineHeight()
    {
        var formatted = new FormattedText(
            "测",
            System.Globalization.CultureInfo.CurrentCulture,
            System.Windows.FlowDirection.LeftToRight,
            new Typeface(PixelFont.Family, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal),
            PixelFont.SpeechSize,
            PixelStyle.Brush(PixelStyle.TextColor),
            1.0);
        return Math.Ceiling(formatted.Height);
    }

    private double TextWidth()
    {
        var (title, pickupZh, pickupEn) = TextLines();
        var maxWidth = 0.0;
        foreach (var line in new[] { title, pickupZh, pickupEn })
        {
            if (line.Length == 0) continue;
            var formatted = Measure(line, MaximumTextWidth, FontWeights.Bold);
            maxWidth = Math.Max(maxWidth, formatted.Width);
        }
        return Math.Min(MaximumTextWidth, Math.Max(80, Math.Ceiling(maxWidth)));
    }

    private Size FittingSize()
    {
        var lineHeight = LineHeight();
        var (title, pickupZh, pickupEn) = TextLines();
        var lineCount = new[] { title, pickupZh, pickupEn }.Count(line => line.Length > 0);
        var textHeight = lineCount == 0
            ? 0
            : lineCount * lineHeight + (lineCount - 1) * TextGap;
        var bodyWidth = IconWidth + IconGap + TextWidth() + PanelPadding * 2;
        var bodyHeight = Math.Max(IconHeight, textHeight) + PanelPadding * 2;
        var outerInset = FrameBorder * 2;
        return new Size(
            Math.Ceiling(bodyWidth) + outerInset,
            Math.Ceiling(bodyHeight) + outerInset + TailHeight);
    }

    private static FormattedText Measure(string text, double maxWidth, FontWeight weight) => new(
        text,
        System.Globalization.CultureInfo.CurrentCulture,
        System.Windows.FlowDirection.LeftToRight,
        new Typeface(PixelFont.Family, FontStyles.Normal, weight, FontStretches.Normal),
        PixelFont.SpeechSize,
        PixelStyle.Brush(PixelStyle.TextColor),
        1.0)
    {
        MaxTextWidth = maxWidth,
        MaxTextHeight = 600,
    };

    private void UpdatePosition()
    {
        var size = new Size(Width, Height);
        const double edgePadding = 8;
        var minimumX = _screenDip.MinX + edgePadding;
        var maximumX = Math.Max(minimumX, _screenDip.MaxX - size.Width - edgePadding);
        var originX = Math.Clamp(_petFrameDip.Left + _petFrameDip.Width / 2 - size.Width / 2, minimumX, maximumX);

        var aboveY = _petFrameDip.Top - size.Height + 6;
        var belowY = _petFrameDip.Bottom - 6;
        double originY;
        if (aboveY >= _screenDip.MinY + edgePadding)
        {
            originY = aboveY;
            _tailEdge = TailEdge.Bottom;
        }
        else if (belowY + size.Height <= _screenDip.MaxY - edgePadding)
        {
            originY = belowY;
            _tailEdge = TailEdge.Top;
        }
        else
        {
            originY = Math.Clamp(
                aboveY,
                _screenDip.MinY + edgePadding,
                Math.Max(_screenDip.MinY + edgePadding, _screenDip.MaxY - size.Height - edgePadding));
            var petMidY = _petFrameDip.Top + _petFrameDip.Height / 2;
            _tailEdge = petMidY > originY + size.Height / 2 ? TailEdge.Bottom : TailEdge.Top;
        }

        _tailX = Math.Clamp(_petFrameDip.Left + _petFrameDip.Width / 2 - originX, 20, size.Width - 20);
        Left = originX;
        Top = originY;
    }

    private void Redraw()
    {
        _canvas.Children.Clear();
        if (_card == null || _icon == null) return;
        _canvas.Width = Width;
        _canvas.Height = Height;

        // 尾巴在下方时身体贴顶部；在上方时身体贴底部（macOS y 向上坐标的镜像）。
        var bodyY = _tailEdge == TailEdge.Bottom ? 0 : TailHeight;
        var bodyRect = new Rect(0, bodyY, Width, Height - TailHeight);

        // 阶梯像素外框 + 纸面（PixelStyle.drawFrame 同款）。
        _canvas.Children.Add(new Path
        {
            Data = Offset(PixelStyle.SteppedRoundedRect(bodyRect.Width, bodyRect.Height, Radius), bodyRect.X, bodyRect.Y),
            Fill = PixelStyle.Brush(PixelStyle.BorderColor),
        });
        _canvas.Children.Add(new Path
        {
            Data = Offset(
                PixelStyle.SteppedRoundedRect(bodyRect.Width - FrameBorder * 2, bodyRect.Height - FrameBorder * 2, Math.Max(1, Radius - FrameBorder)),
                bodyRect.X + FrameBorder, bodyRect.Y + FrameBorder),
            Fill = PixelStyle.Brush(PixelStyle.FillColor),
        });

        DrawTail(bodyRect);

        var inner = new Rect(
            bodyRect.X + FrameBorder, bodyRect.Y + FrameBorder,
            bodyRect.Width - FrameBorder * 2, bodyRect.Height - FrameBorder * 2);
        var content = new Rect(
            inner.X + PanelPadding, inner.Y + PanelPadding,
            inner.Width - PanelPadding * 2, inner.Height - PanelPadding * 2);

        var icon = new Image
        {
            Source = _icon.Image,
            Width = IconWidth,
            Height = IconHeight,
        };
        RenderOptions.SetBitmapScalingMode(icon, BitmapScalingMode.NearestNeighbor);
        Canvas.SetLeft(icon, content.X);
        Canvas.SetTop(icon, content.Y + (content.Height - IconHeight) / 2);
        _canvas.Children.Add(icon);

        var lineHeight = LineHeight();
        var (title, pickupZh, pickupEn) = TextLines();
        var lines = new (string Text, FontWeight Weight, Color Tint)[]
        {
            (title, FontWeights.Bold, PixelStyle.AccentColor),
            (pickupZh, FontWeights.Normal, PixelStyle.TextColor),
            (pickupEn, FontWeights.Normal, PixelStyle.DisabledTextColor),
        };
        var textHeight = lines.Count(line => line.Text.Length > 0) * lineHeight
            + Math.Max(0, lines.Count(line => line.Text.Length > 0) - 1) * TextGap;
        var textX = content.X + IconWidth + IconGap;
        var lineTop = content.Y + (content.Height - textHeight) / 2;
        foreach (var (text, weight, tint) in lines)
        {
            if (text.Length == 0) continue;
            var textBlock = new TextBlock
            {
                Text = text,
                FontFamily = PixelFont.Family,
                FontSize = PixelFont.SpeechSize,
                FontWeight = weight,
                Foreground = PixelStyle.Brush(tint),
                TextWrapping = TextWrapping.Wrap,
                Width = Math.Min(MaximumTextWidth, content.Width - IconWidth - IconGap),
            };
            Canvas.SetLeft(textBlock, textX);
            Canvas.SetTop(textBlock, lineTop);
            _canvas.Children.Add(textBlock);
            lineTop += lineHeight + TextGap;
        }
    }

    private void DrawTail(Rect bodyRect)
    {
        var downward = _tailEdge == TailEdge.Bottom;
        (double Height, double Outer, double Inner, double InnerHeight)[] steps =
        [
            (4, 20, 14, 4),
            (4, 12, 6, 4),
            (3, 6, 2, 1),
        ];
        var y = downward ? bodyRect.Bottom : bodyRect.Top;
        foreach (var step in steps)
        {
            var outerY = downward ? y : y - step.Height;
            var innerY = downward ? outerY : outerY + step.Height - step.InnerHeight;
            _canvas.Children.Add(new Rectangle
            {
                Fill = PixelStyle.Brush(PixelStyle.BorderColor),
                Width = step.Outer,
                Height = step.Height,
            });
            Canvas.SetLeft(_canvas.Children[^1], _tailX - step.Outer / 2);
            Canvas.SetTop(_canvas.Children[^1], outerY);

            _canvas.Children.Add(new Rectangle
            {
                Fill = PixelStyle.Brush(PixelStyle.FillColor),
                Width = step.Inner,
                Height = step.InnerHeight,
            });
            Canvas.SetLeft(_canvas.Children[^1], _tailX - step.Inner / 2);
            Canvas.SetTop(_canvas.Children[^1], innerY);

            y += downward ? step.Height : -step.Height;
        }
    }

    private static Geometry Offset(Geometry geometry, double x, double y)
    {
        var positioned = (StreamGeometry)geometry.Clone();
        positioned.Transform = new TranslateTransform(x, y);
        positioned.Freeze();
        return positioned;
    }
}
