using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Button = System.Windows.Controls.Button;
using Brushes = System.Windows.Media.Brushes;
using Cursors = System.Windows.Input.Cursors;

namespace IsaacPet.Windows.Ui.Pixel;

/// <summary>
/// 游戏风格按钮：阶梯像素描边包着纸面色按钮面，像素字体标签，
/// 悬停/按下/禁用状态。默认按钮用砖红描边，像游戏里的高亮选项。
/// 对应 macOS 版 PixelButton。
/// </summary>
public sealed class PixelButton : Button
{
    public static readonly DependencyProperty IsDefaultStyledProperty = DependencyProperty.Register(
        nameof(IsDefaultStyled), typeof(bool), typeof(PixelButton),
        new FrameworkPropertyMetadata(false, FrameworkPropertyMetadataOptions.AffectsRender));

    /// <summary>默认按钮获得砖红描边。</summary>
    public bool IsDefaultStyled
    {
        get => (bool)GetValue(IsDefaultStyledProperty);
        set => SetValue(IsDefaultStyledProperty, value);
    }

    private PixelFrame? _frame;

    static PixelButton()
    {
        // IsDefault 变化时同步描边样式（默认按钮 = 砖红描边）。
        Button.IsDefaultProperty.OverrideMetadata(
            typeof(PixelButton),
            new FrameworkPropertyMetadata(false, (sender, _) =>
            {
                if (sender is PixelButton button) button.ApplyBorderStyle();
            }));
    }

    public PixelButton()
    {
        Template = BuildTemplate();
        FontFamily = PixelFont.Family;
        FontSize = PixelFont.SpeechSize;
        Foreground = PixelStyle.Brush(PixelStyle.TextColor);
        Cursor = Cursors.Hand;
    }

    public override void OnApplyTemplate()
    {
        base.OnApplyTemplate();
        _frame = GetTemplateChild("Frame") as PixelFrame;
        ApplyBorderStyle();
    }

    private void ApplyBorderStyle()
    {
        if (_frame != null)
        {
            _frame.BorderBrush = PixelStyle.Brush(
                IsDefaultStyled ? PixelStyle.AccentColor : PixelStyle.ButtonBorderColor);
        }
    }

    private static ControlTemplate BuildTemplate()
    {
        var template = new ControlTemplate(typeof(Button));

        var root = new FrameworkElementFactory(typeof(Grid));
        root.Name = "Root";
        root.SetValue(System.Windows.Controls.Panel.BackgroundProperty, System.Windows.Media.Brushes.Transparent);

        var frame = new FrameworkElementFactory(typeof(PixelFrame));
        frame.Name = "Frame";
        frame.SetValue(PixelFrame.RadiusProperty, 6.0);
        frame.SetValue(PixelFrame.BorderWidthProperty, 2.0);
        frame.SetValue(PixelFrame.BorderBrushProperty, PixelStyle.Brush(PixelStyle.ButtonBorderColor));
        frame.SetValue(PixelFrame.FaceBrushProperty, PixelStyle.Brush(PixelStyle.ButtonFaceColor));
        root.AppendChild(frame);

        var content = new FrameworkElementFactory(typeof(ContentPresenter));
        content.Name = "Content";
        content.SetValue(MarginProperty, new Thickness(13, 6, 13, 7));
        content.SetValue(HorizontalAlignmentProperty, System.Windows.HorizontalAlignment.Center);
        content.SetValue(VerticalAlignmentProperty, System.Windows.VerticalAlignment.Center);
        root.AppendChild(content);

        template.VisualTree = root;

        var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(PixelFrame.BorderBrushProperty, PixelStyle.Brush(PixelStyle.ButtonBorderHoverColor), "Frame"));
        template.Triggers.Add(hover);

        var pressed = new Trigger { Property = Button.IsPressedProperty, Value = true };
        pressed.Setters.Add(new Setter(PixelFrame.FaceBrushProperty, PixelStyle.Brush(PixelStyle.ButtonFaceDownColor), "Frame"));
        pressed.Setters.Add(new Setter(MarginProperty, new Thickness(13, 7, 13, 6), "Content"));
        template.Triggers.Add(pressed);

        var disabled = new Trigger { Property = IsEnabledProperty, Value = false };
        disabled.Setters.Add(new Setter(PixelFrame.FaceBrushProperty, PixelStyle.Brush(PixelStyle.FillColor), "Frame"));
        disabled.Setters.Add(new Setter(ForegroundProperty, PixelStyle.Brush(PixelStyle.DisabledTextColor)));
        template.Triggers.Add(disabled);

        return template;
    }
}
