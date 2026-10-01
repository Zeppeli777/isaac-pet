using System.Drawing.Text;
using System.IO;
using System.Windows.Media;
using FontFamily = System.Windows.Media.FontFamily;

namespace IsaacPet.Windows.Ui.Pixel;

/// <summary>
/// 加载随包分发的 Fusion Pixel 字体（SIL OFL 1.1），见 Assets/Fonts/OFL.txt。
/// 首次使用时注册到当前进程；失败时回退系统字体，保证文字始终可见。
/// </summary>
public static class PixelFont
{
    /// <summary>正文渲染 12px——字体的原生 12px 设计网格，保持字形像素对齐。</summary>
    public const double SpeechSize = 12;

    /// <summary>标题渲染 24px——设计网格的整 2 倍。</summary>
    public const double TitleSize = 24;

    private const string FileName = "fusion-pixel-12px-proportional-zh_hans.ttf";

    private static FontFamily? _family;
    private static System.Drawing.Font? _menuFont;

    public static FontFamily Family => _family ??= LoadFamily();

    /// <summary>WinForms 托盘菜单用的字体（独立于 WPF 的注册机制）。</summary>
    public static System.Drawing.Font MenuFont => _menuFont ??= CreateMenuFont();

    private static string FontPath => Path.Combine(AppContext.BaseDirectory, "Assets", "Fonts", FileName);

    private static FontFamily LoadFamily()
    {
        try
        {
            if (File.Exists(FontPath))
            {
                // WPF 侧用 GlyphTypeface 读取字体族名，再以文件 URI 构造 FontFamily。
                var typeface = new GlyphTypeface(new Uri(FontPath));
                var name = typeface.FamilyNames.Values.FirstOrDefault();
                if (!string.IsNullOrWhiteSpace(name))
                {
                    return new FontFamily(new Uri(FontPath), "./#" + name);
                }
            }
        }
        catch
        {
            // 字体加载失败时走系统回退。
        }
        return new FontFamily("Microsoft YaHei UI, Microsoft Sans Serif");
    }

    private static System.Drawing.Font CreateMenuFont()
    {
        try
        {
            if (File.Exists(FontPath))
            {
                var collection = new PrivateFontCollection();
                collection.AddFontFile(FontPath);
                if (collection.Families.Length > 0)
                {
                    return new System.Drawing.Font(collection.Families[0], 12, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Pixel);
                }
            }
        }
        catch
        {
            // 字体加载失败时走系统回退。
        }
        return new System.Drawing.Font("Microsoft YaHei UI", 12, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Pixel);
    }
}
