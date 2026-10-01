using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using IsaacPet.Windows.Core;
using IsaacPet.Windows.Ui.Pixel;
using Point = System.Windows.Point;
using Rectangle = System.Windows.Shapes.Rectangle;
using Size = System.Windows.Size;

namespace IsaacPet.Windows.Pet;

/// <summary>
/// 像素风对话气泡：纸面底色 + 阶梯像素描边 + 楼梯状尾巴 + 纸纹斑点，
/// 文字用 Fusion Pixel 像素字体。移植自 macOS 版 SpeechBubbleController/SpeechBubbleView
/// （重绘后的游戏内消息框风格）。始终鼠标穿透，锚定在桌宠上方（放不下时放下方）。
/// </summary>
public sealed class SpeechBubbleWindow : TransparentTopmostWindow
{
    private enum TailEdge { Top, Bottom }

    private const double TailHeight = 14;
    private const double OuterInset = 3;
    private const double Border = 4;
    private const double CornerRadius = 7;
    private const double TextHorizontalInset = 13;
    private const double TextVerticalInset = 10;
    private const double MaximumTextWidth = 236;
    private const double MinimumBodyWidth = 88;
    private const double MinimumBodyHeight = 43;
    private const double BottomShadow = 2;

    private readonly Canvas _canvas = new();
    private DispatcherTimer? _hideTimer;
    private string _message = "";
    private TailEdge _tailEdge = TailEdge.Bottom;
    private double _tailX = 80;
    private Rect _petFrameDip;
    private ScreenBoundsDip _screenDip;

    public SpeechBubbleWindow()
    {
        Content = _canvas;
    }

    public bool IsShowing => IsVisible;

    public void ShowMessage(string rawMessage, Rect petFrameDip, ScreenBoundsDip screenDip)
    {
        var message = SpeechBubblePolicy.Normalized(rawMessage);
        if (message == null) return;
        _message = message;
        _petFrameDip = petFrameDip;
        _screenDip = screenDip;

        _hideTimer?.Stop();
        var size = FittingSize(message);
        Width = size.Width;
        Height = size.Height;
        UpdatePosition();
        Redraw();
        Show();

        _hideTimer = new DispatcherTimer { Interval = SpeechBubblePolicy.DisplayDuration(message) };
        _hideTimer.Tick += (_, _) => HideBubble();
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

    public void HideBubble()
    {
        _hideTimer?.Stop();
        _hideTimer = null;
        Hide();
    }

    public void Stop() => HideBubble();

    private static Size FittingSize(string message)
    {
        var text = Measure(message, MaximumTextWidth);
        var bodyWidth = Math.Min(
            MaximumTextWidth + TextHorizontalInset * 2,
            Math.Max(MinimumBodyWidth, Math.Ceiling(text.Width) + TextHorizontalInset * 2));
        var bodyHeight = Math.Max(MinimumBodyHeight, Math.Ceiling(text.Height) + TextVerticalInset * 2);
        return new Size(bodyWidth + OuterInset * 2, bodyHeight + TailHeight + OuterInset * 2);
    }

    private static Size Measure(string message, double maxWidth)
    {
        var formatted = new FormattedText(
            message,
            System.Globalization.CultureInfo.CurrentCulture,
            System.Windows.FlowDirection.LeftToRight,
            new Typeface(PixelFont.Family, FontStyles.Normal, FontWeights.Bold, FontStretches.Normal),
            PixelFont.SpeechSize,
            PixelStyle.Brush(PixelStyle.TextColor),
            1.0)
        {
            MaxTextWidth = maxWidth,
            MaxTextHeight = 500,
            TextAlignment = TextAlignment.Center,
        };
        return new Size(formatted.Width, formatted.Height);
    }

    private void UpdatePosition()
    {
        var size = new Size(Width, Height);
        const double edgePadding = 8;
        var minimumX = _screenDip.MinX + edgePadding;
        var maximumX = Math.Max(minimumX, _screenDip.MaxX - size.Width - edgePadding);
        var originX = Math.Clamp(_petFrameDip.Left + _petFrameDip.Width / 2 - size.Width / 2, minimumX, maximumX);

        // WPF 的 y 向下：“宠物上方” = petFrame.Top - bubbleHeight。
        var aboveY = _petFrameDip.Top - size.Height + 8;
        var belowY = _petFrameDip.Bottom - 8;
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

        _tailX = Math.Clamp(_petFrameDip.Left + _petFrameDip.Width / 2 - originX, 24, size.Width - 24);
        Left = originX;
        Top = originY;
    }

    private void Redraw()
    {
        _canvas.Children.Clear();
        _canvas.Width = Width;
        _canvas.Height = Height;

        // 尾巴在下方时身体贴顶部；在上方时身体贴底部（macOS y 向上坐标的镜像）。
        var bodyY = _tailEdge == TailEdge.Bottom ? OuterInset : TailHeight + OuterInset;
        var bodyRect = new Rect(
            OuterInset,
            bodyY,
            Width - OuterInset * 2,
            Height - TailHeight - OuterInset * 2);

        DrawPixelBody(bodyRect);
        DrawTail(bodyRect);

        var textBlock = new TextBlock
        {
            Text = _message,
            FontFamily = PixelFont.Family,
            FontWeight = FontWeights.Bold,
            FontSize = PixelFont.SpeechSize,
            Foreground = PixelStyle.Brush(PixelStyle.TextColor),
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            LineHeight = double.NaN,
            Width = bodyRect.Width - Border * 2 - (TextHorizontalInset - Border) * 2,
        };
        Canvas.SetLeft(textBlock, bodyRect.X + TextHorizontalInset);
        Canvas.SetTop(textBlock, bodyRect.Y + TextVerticalInset);
        _canvas.Children.Add(textBlock);
    }

    private void DrawPixelBody(Rect rect)
    {
        // 阶梯像素外框 + 纸面内衬（与像素 UI kit 同一套画法）。
        _canvas.Children.Add(new Path
        {
            Data = Offset(PixelStyle.SteppedRoundedRect(rect.Width, rect.Height, CornerRadius), rect.X, rect.Y),
            Fill = PixelStyle.Brush(PixelStyle.BorderColor),
        });
        _canvas.Children.Add(new Path
        {
            Data = Offset(
                PixelStyle.SteppedRoundedRect(rect.Width - Border * 2, rect.Height - Border * 2, CornerRadius - Border),
                rect.X + Border, rect.Y + Border),
            Fill = PixelStyle.Brush(PixelStyle.FillColor),
        });

        var inner = new Rect(rect.X + Border, rect.Y + Border, rect.Width - Border * 2, rect.Height - Border * 2);
        _canvas.Children.Add(new Rectangle
        {
            Fill = PixelStyle.Brush(PixelStyle.ShadowColor),
            Width = inner.Width,
            Height = BottomShadow,
        });
        Canvas.SetLeft(_canvas.Children[^1], inner.X);
        Canvas.SetTop(_canvas.Children[^1], inner.Bottom - BottomShadow);

        DrawPaperSpeckles(inner);
    }

    private void DrawPaperSpeckles(Rect innerRect)
    {
        if (innerRect.Width < 60 || innerRect.Height < 36) return;
        (double X, double Y)[] spots =
        [
            (0.16, 0.32),
            (0.71, 0.24),
            (0.86, 0.62),
            (0.31, 0.70),
        ];
        foreach (var (fx, fy) in spots)
        {
            var speckle = new Rectangle
            {
                Fill = PixelStyle.Brush(PixelStyle.ShadowColor),
                Width = 2,
                Height = 2,
            };
            Canvas.SetLeft(speckle, Math.Floor(innerRect.X + innerRect.Width * fx));
            Canvas.SetTop(speckle, Math.Floor(innerRect.Y + innerRect.Height * fy));
            _canvas.Children.Add(speckle);
        }
    }

    private void DrawTail(Rect bodyRect)
    {
        var downward = _tailEdge == TailEdge.Bottom;
        // 楼梯状尾巴：（步高，外宽，内宽，内高）。内衬贴住身体一侧，尖端留出描边帽。
        (double Height, double Outer, double Inner, double InnerHeight)[] steps =
        [
            (5, 26, 20, 5),
            (5, 18, 12, 5),
            (4, 10, 4, 1),
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
