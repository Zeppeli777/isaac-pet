using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using IsaacPet.Windows.Core;
using Color = System.Windows.Media.Color;
using FontFamily = System.Windows.Media.FontFamily;
using Point = System.Windows.Point;
using Rectangle = System.Windows.Shapes.Rectangle;
using Size = System.Windows.Size;

namespace IsaacPet.Windows.Pet;

/// <summary>
/// 像素风对话气泡，移植自 macOS 版 SpeechBubbleController/SpeechBubbleView。
/// 始终鼠标穿透，锚定在桌宠上方（放不下时放下方）。
/// </summary>
public sealed class SpeechBubbleWindow : TransparentTopmostWindow
{
    private enum TailEdge { Top, Bottom }

    private const double TailHeight = 14;
    private const double OuterInset = 3;
    private const double Border = 4;
    private const double TextHorizontalInset = 13;
    private const double TextVerticalInset = 10;
    private const double MaximumTextWidth = 236;
    private const double MinimumBodyWidth = 88;
    private const double MinimumBodyHeight = 43;

    private static readonly Color OutlineColor = Color.FromRgb(20, 20, 20);
    private static readonly Color FillColor = Color.FromRgb(255, 245, 209);   // 1.0 / 0.96 / 0.82
    private static readonly Color AccentColor = Color.FromRgb(194, 66, 51);     // 0.76 / 0.26 / 0.20
    private static readonly Color TextColor = Color.FromRgb(26, 26, 26);        // 0.10 white

    private static readonly FontFamily Font = new("Consolas, Microsoft YaHei UI");

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
            new Typeface(Font, FontStyles.Normal, FontWeights.Bold, FontStretches.Normal),
            15,
            System.Windows.Media.Brushes.Black,
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
            FontFamily = Font,
            FontWeight = FontWeights.Bold,
            FontSize = 15,
            Foreground = new SolidColorBrush(TextColor),
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            Width = bodyRect.Width - Border * 2 - (TextHorizontalInset - Border) * 2,
        };
        Canvas.SetLeft(textBlock, bodyRect.X + TextHorizontalInset);
        Canvas.SetTop(textBlock, bodyRect.Y + TextVerticalInset);
        _canvas.Children.Add(textBlock);
    }

    private void DrawPixelBody(Rect rect)
    {
        const double corner = 6;
        var outline = new Polygon
        {
            Fill = new SolidColorBrush(OutlineColor),
            Points =
            {
                new Point(rect.Left + corner, rect.Top),
                new Point(rect.Right - corner, rect.Top),
                new Point(rect.Right, rect.Top + corner),
                new Point(rect.Right, rect.Bottom - corner),
                new Point(rect.Right - corner, rect.Bottom),
                new Point(rect.Left + corner, rect.Bottom),
                new Point(rect.Left, rect.Bottom - corner),
                new Point(rect.Left, rect.Top + corner),
            },
        };
        _canvas.Children.Add(outline);

        var inner = new Rect(rect.X + Border, rect.Y + Border, rect.Width - Border * 2, rect.Height - Border * 2);
        var innerRect = new Rectangle
        {
            Fill = new SolidColorBrush(FillColor),
            Width = inner.Width,
            Height = inner.Height,
        };
        Canvas.SetLeft(innerRect, inner.X);
        Canvas.SetTop(innerRect, inner.Y);
        _canvas.Children.Add(innerRect);

        // 红色饰条与 macOS 版一致，位于内框底部 3px。
        var accent = new Rectangle
        {
            Fill = new SolidColorBrush(AccentColor),
            Width = inner.Width,
            Height = 3,
        };
        Canvas.SetLeft(accent, inner.X);
        Canvas.SetTop(accent, inner.Bottom - 3);
        _canvas.Children.Add(accent);
    }

    private void DrawTail(Rect bodyRect)
    {
        var bodyEdgeY = _tailEdge == TailEdge.Bottom ? bodyRect.Bottom : bodyRect.Top;
        var tipY = _tailEdge == TailEdge.Bottom ? Height - 1 : 1;

        _canvas.Children.Add(new Polygon
        {
            Fill = new SolidColorBrush(OutlineColor),
            Points =
            {
                new Point(_tailX - 13, bodyEdgeY),
                new Point(_tailX + 10, bodyEdgeY),
                new Point(_tailX + 3, tipY),
                new Point(_tailX - 4, tipY),
            },
        });

        var innerTipY = _tailEdge == TailEdge.Bottom ? tipY - 5 : tipY + 5;
        _canvas.Children.Add(new Polygon
        {
            Fill = new SolidColorBrush(FillColor),
            Points =
            {
                new Point(_tailX - 7, bodyEdgeY),
                new Point(_tailX + 4, bodyEdgeY),
                new Point(_tailX, innerTipY),
            },
        });
    }
}
