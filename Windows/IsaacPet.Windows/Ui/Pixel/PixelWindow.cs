using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Brushes = System.Windows.Media.Brushes;
using Size = System.Windows.Size;

namespace IsaacPet.Windows.Ui.Pixel;

/// <summary>
/// 无边框游戏风窗口：纸面填充、阶梯像素外框、像素字体标题行、
/// 右上角像素关闭按钮，背景可拖动。宿主通过 SetContent 添加内容，
/// 内容区位于外框内，与游戏消息框同样的纸面底色。
/// 对应 macOS 版 PixelWindow。关闭时 ShowDialog 自然结束模态会话。
/// </summary>
public class PixelWindow : Window
{
    public const double BorderWidth = 6;
    public const double HeaderHeight = 40;
    public const double ContentPadding = 16;

    private readonly ContentPresenter _contentHost = new();

    public PixelWindow(string title, bool resizable = true)
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ResizeMode = resizable ? ResizeMode.CanResize : ResizeMode.NoResize;
        FontFamily = PixelFont.Family;
        FontSize = PixelFont.SpeechSize;
        Foreground = PixelStyle.Brush(PixelStyle.TextColor);

        var chrome = new Grid { Background = Brushes.Transparent };

        var chromeFrame = new PixelChromeElement();
        chromeFrame.MouseLeftButtonDown += BeginDragMove;
        chrome.Children.Add(chromeFrame);

        var titleText = new TextBlock
        {
            Text = title,
            FontSize = PixelFont.TitleSize,
            FontFamily = PixelFont.Family,
            FontWeight = FontWeights.Bold,
            Foreground = PixelStyle.Brush(PixelStyle.AccentColor),
            HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(BorderWidth + 10, BorderWidth + 4, 0, 0),
            IsHitTestVisible = true,
        };
        titleText.MouseLeftButtonDown += BeginDragMove;
        chrome.Children.Add(titleText);

        var closeButton = new PixelButton
        {
            Content = "×",
            Width = 26,
            Height = 26,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, BorderWidth + 6, BorderWidth + 10, 0),
        };
        closeButton.Click += (_, _) => Close();
        chrome.Children.Add(closeButton);

        _contentHost.Margin = new Thickness(
            BorderWidth + ContentPadding,
            BorderWidth + HeaderHeight + ContentPadding,
            BorderWidth + ContentPadding,
            BorderWidth + ContentPadding);

        var root = new Grid();
        root.Children.Add(chrome);
        root.Children.Add(_contentHost);
        Content = root;
    }

    /// <summary>窗口内容；位于外框内容区（含边框、标题行和内边距的偏移）。</summary>
    public void SetContent(UIElement content) => _contentHost.Content = content;

    private void BeginDragMove(object sender, MouseButtonEventArgs e)
    {
        try
        {
            DragMove();
        }
        catch (InvalidOperationException)
        {
            // 鼠标已释放等瞬态状态直接忽略。
        }
    }

    /// <summary>窗口底图：阶梯外框 + 纸面 + 标题分隔线 + 底部阴影唇边。测量为零，不影响 SizeToContent。</summary>
    private sealed class PixelChromeElement : FrameworkElement
    {
        protected override Size MeasureOverride(Size availableSize) => default;

        protected override Size ArrangeOverride(Size finalSize)
        {
            InvalidateVisual();
            return finalSize;
        }

        protected override void OnRenderSizeChanged(SizeChangedInfo sizeInfo) => InvalidateVisual();

        protected override void OnRender(DrawingContext context)
        {
            var w = ActualWidth;
            var h = ActualHeight;
            if (w < BorderWidth * 2 + 2 || h < BorderWidth * 2 + HeaderHeight + 2) return;

            context.DrawGeometry(
                PixelStyle.Brush(PixelStyle.BorderColor), null,
                PixelStyle.SteppedRoundedRect(w, h, 10));

            var inner = PixelStyle.SteppedRoundedRect(w - BorderWidth * 2, h - BorderWidth * 2, 4);
            var positioned = (StreamGeometry)inner.Clone();
            positioned.Transform = new TranslateTransform(BorderWidth, BorderWidth);
            positioned.Freeze();
            context.DrawGeometry(PixelStyle.Brush(PixelStyle.FillColor), null, positioned);

            // 标题行底部的分隔线。
            context.DrawRectangle(
                PixelStyle.Brush(PixelStyle.ShadowColor), null,
                new Rect(BorderWidth + 1, BorderWidth + HeaderHeight - 2, w - BorderWidth * 2 - 2, 2));

            // 视觉底边内侧的阴影唇边。
            context.DrawRectangle(
                PixelStyle.Brush(PixelStyle.ShadowColor), null,
                new Rect(BorderWidth + 2, h - BorderWidth - 3, w - BorderWidth * 2 - 4, 2));
        }
    }
}
