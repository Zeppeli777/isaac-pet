using System.Windows;
using System.Windows.Media;
using Brush = System.Windows.Media.Brush;
using Size = System.Windows.Size;

namespace IsaacPet.Windows.Ui.Pixel;

/// <summary>
/// 阶梯像素描边框：描边色外圈包着纸面色内面，圆角量化到像素网格。
/// 测量为零尺寸，因此放进 SizeToContent 窗口不会造成布局反馈。
/// </summary>
public sealed class PixelFrame : FrameworkElement
{
    public static readonly DependencyProperty BorderBrushProperty = DependencyProperty.Register(
        nameof(BorderBrush), typeof(Brush), typeof(PixelFrame),
        new FrameworkPropertyMetadata(PixelStyle.Brush(PixelStyle.ButtonBorderColor), FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty FaceBrushProperty = DependencyProperty.Register(
        nameof(FaceBrush), typeof(Brush), typeof(PixelFrame),
        new FrameworkPropertyMetadata(PixelStyle.Brush(PixelStyle.ButtonFaceColor), FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty RadiusProperty = DependencyProperty.Register(
        nameof(Radius), typeof(double), typeof(PixelFrame),
        new FrameworkPropertyMetadata(6.0, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty BorderWidthProperty = DependencyProperty.Register(
        nameof(BorderWidth), typeof(double), typeof(PixelFrame),
        new FrameworkPropertyMetadata(2.0, FrameworkPropertyMetadataOptions.AffectsRender));

    public Brush BorderBrush
    {
        get => (Brush)GetValue(BorderBrushProperty);
        set => SetValue(BorderBrushProperty, value);
    }

    public Brush FaceBrush
    {
        get => (Brush)GetValue(FaceBrushProperty);
        set => SetValue(FaceBrushProperty, value);
    }

    public double Radius
    {
        get => (double)GetValue(RadiusProperty);
        set => SetValue(RadiusProperty, value);
    }

    public double BorderWidth
    {
        get => (double)GetValue(BorderWidthProperty);
        set => SetValue(BorderWidthProperty, value);
    }

    protected override Size MeasureOverride(Size availableSize) => default;

    protected override Size ArrangeOverride(Size finalSize) => finalSize;

    protected override void OnRenderSizeChanged(SizeChangedInfo sizeInfo) => InvalidateVisual();

    protected override void OnRender(DrawingContext context)
    {
        var w = ActualWidth;
        var h = ActualHeight;
        if (w < 1 || h < 1) return;
        var radius = Radius;
        var border = BorderWidth;
        context.DrawGeometry(BorderBrush, null, PixelStyle.SteppedRoundedRect(w, h, radius));
        if (border > 0 && w > border * 2 && h > border * 2)
        {
            var inner = PixelStyle.SteppedRoundedRect(w - border * 2, h - border * 2, Math.Max(1, radius - border));
            var positioned = (StreamGeometry)inner.Clone();
            positioned.Transform = new TranslateTransform(border, border);
            positioned.Freeze();
            context.DrawGeometry(FaceBrush, null, positioned);
        }
    }
}
