using System.Windows;
using System.Windows.Media;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;

namespace IsaacPet.Windows.Ui.Pixel;

/// <summary>
/// 游戏风 UI 的共享调色板与像素几何（对应 macOS 版 PixelStyle）。
/// 颜色取自游戏内消息框参考图 Assets/Source/Emotes/reference-message-box.png。
/// </summary>
public static class PixelStyle
{
    public static readonly Color BorderColor = Color.FromRgb(0xB3, 0xAD, 0xA8);
    public static readonly Color FillColor = Color.FromRgb(0xED, 0xE8, 0xE6);
    public static readonly Color ShadowColor = Color.FromRgb(0xD1, 0xCC, 0xCA);
    public static readonly Color TextColor = Color.FromRgb(0x3D, 0x3B, 0x38);
    public static readonly Color DisabledTextColor = Color.FromRgb(0x85, 0x80, 0x7D);

    /// <summary>窗口标题行的砖红强调色（与气泡口音色一致）。</summary>
    public static readonly Color AccentColor = Color.FromRgb(0xC2, 0x42, 0x33);

    /// <summary>按钮：暖色深描边包着稍深的纸面。</summary>
    public static readonly Color ButtonBorderColor = Color.FromRgb(0x57, 0x4F, 0x4A);
    public static readonly Color ButtonBorderHoverColor = Color.FromRgb(0x66, 0x4B, 0x44);
    public static readonly Color ButtonFaceColor = Color.FromRgb(0xDE, 0xD9, 0xD4);
    public static readonly Color ButtonFaceDownColor = Color.FromRgb(0xC4, 0xBF, 0xBA);

    public static SolidColorBrush Brush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    /// <summary>
    /// 把圆角量化到像素网格：逐行缩进形成的阶梯角（对应 macOS 版 pixelRoundedPath），
    /// 避免抗锯齿把角画成曲线。几何只含水平/垂直段，整数坐标渲染即保持硬边。
    /// 退化几何（空/负/非有限尺寸）返回空路径。
    /// </summary>
    public static Geometry SteppedRoundedRect(double width, double height, double radius)
    {
        var geometry = new StreamGeometry();
        if (!double.IsFinite(width) || !double.IsFinite(height) || width < 1 || height < 1)
        {
            geometry.Freeze();
            return geometry;
        }
        var w = (int)Math.Floor(width);
        var h = (int)Math.Floor(height);
        var r = (int)Math.Clamp(Math.Floor(radius), 0, Math.Min(w, h) / 2.0);

        int Inset(int y)
        {
            var depth = Math.Min(y, h - 1 - y);
            if (depth >= r) return 0;
            var offset = r - depth - 0.5;
            var span = (int)Math.Floor(Math.Sqrt((double)r * r - offset * offset));
            return r - span;
        }

        using (var context = geometry.Open())
        {
            context.BeginFigure(new Point(Inset(0), 0), true, true);
            // 右边界自上而下：缩进变化时先横后竖，保持阶梯。
            var previous = Inset(0);
            for (var y = 0; y < h; y++)
            {
                var x = w - Inset(y);
                if (x != previous)
                {
                    context.LineTo(new Point(previous, y), true, false);
                    context.LineTo(new Point(x, y), true, false);
                    previous = x;
                }
            }
            context.LineTo(new Point(Inset(0), h - 1), true, false);
            // 左边界自下而上。
            previous = Inset(0);
            for (var y = h - 1; y >= 0; y--)
            {
                var x = Inset(y);
                if (x != previous)
                {
                    context.LineTo(new Point(previous, y), true, false);
                    context.LineTo(new Point(x, y), true, false);
                    previous = x;
                }
            }
        }
        geometry.Freeze();
        return geometry;
    }

    /// <summary>像素风单行输入框：纸面底色 + 方形描边，字体随窗口继承。</summary>
    public static System.Windows.Controls.TextBox CreateField(string? toolTip = null)
    {
        var field = new System.Windows.Controls.TextBox
        {
            Background = Brush(FillColor),
            BorderBrush = Brush(ButtonBorderColor),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(4, 2, 4, 2),
        };
        if (toolTip != null) field.ToolTip = toolTip;
        return field;
    }
}
