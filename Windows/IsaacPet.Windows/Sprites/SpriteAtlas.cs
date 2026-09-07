using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IsaacPet.Windows.Core;

namespace IsaacPet.Windows.Sprites;

/// <summary>单帧：冻结的 WPF 图像 + 逐像素 alpha（行主序，左上角原点），用于透明像素穿透。</summary>
public sealed class SpriteFrame
{
    public required BitmapSource Image { get; init; }
    public required byte[] Alpha { get; init; }
    public required int PixelWidth { get; init; }
    public required int PixelHeight { get; init; }

    /// <summary>判断窗口内 DIP 坐标处是否是不透明像素（阈值与 macOS 版一致：alpha > 0.08）。</summary>
    public bool IsOpaqueAt(double dipX, double dipY, double boundsWidth, double boundsHeight, double threshold = 0.08)
    {
        if (boundsWidth <= 0 || boundsHeight <= 0) return false;
        if (dipX < 0 || dipY < 0 || dipX >= boundsWidth || dipY >= boundsHeight) return false;
        var x = Math.Clamp((int)(dipX / boundsWidth * PixelWidth), 0, PixelWidth - 1);
        var y = Math.Clamp((int)(dipY / boundsHeight * PixelHeight), 0, PixelHeight - 1);
        return Alpha[y * PixelWidth + x] > threshold * 255;
    }
}

public sealed class SpriteAtlas
{
    private const string IsaacSheet = "spritesheet";

    private readonly BitmapSource _source;
    private readonly BitmapSource _shootingSource;
    private readonly BitmapSource _verticalWalkingSource;
    private readonly string _assetsDirectory;
    private readonly Dictionary<(int Row, int Column), SpriteFrame> _cache = new();
    private readonly Dictionary<int, SpriteFrame> _shootingCache = new();
    private readonly Dictionary<(int Row, int Column), SpriteFrame> _verticalWalkingCache = new();
    private SpriteFrame? _cachedTear;

    private SpriteAtlas(BitmapSource source, BitmapSource shooting, BitmapSource verticalWalking, string assetsDirectory)
    {
        _source = source;
        _shootingSource = shooting;
        _verticalWalkingSource = verticalWalking;
        _assetsDirectory = assetsDirectory;
    }

    public static string AssetsDirectory => Path.Combine(AppContext.BaseDirectory, "Assets");

    public static bool AppearanceAvailable(string sheetName) =>
        File.Exists(Path.Combine(AssetsDirectory, sheetName + ".png"));

    public static SpriteAtlas Load(string spriteSheetName = IsaacSheet, string? subdirectory = null)
    {
        var sheetDirectory = subdirectory == null
            ? AssetsDirectory
            : Path.Combine(AssetsDirectory, subdirectory);
        var source = LoadPng(Path.Combine(sheetDirectory, spriteSheetName + ".png"));
        // 射击、泪弹和竖向行走辅助图集始终沿用基础图集目录（与 macOS 版 SpriteAtlas 架构一致）。
        var assets = AssetsDirectory;
        var expectedWidth = AnimationCatalog.CellWidth * AnimationCatalog.Columns;
        var expectedHeight = AnimationCatalog.CellHeight * AnimationCatalog.Rows;
        if (source.PixelWidth != expectedWidth || source.PixelHeight != expectedHeight)
        {
            throw new InvalidDataException($"动画图集尺寸错误：{source.PixelWidth}×{source.PixelHeight}。");
        }

        var shooting = LoadPng(Path.Combine(assets, "shooting-atlas.png"));
        if (shooting.PixelWidth != AnimationCatalog.CellWidth * 4 || shooting.PixelHeight != AnimationCatalog.CellHeight)
        {
            throw new InvalidDataException($"射击姿态尺寸错误：{shooting.PixelWidth}×{shooting.PixelHeight}。");
        }

        var verticalWalking = LoadPng(Path.Combine(assets, "walking-vertical-atlas.png"));
        var expectedVerticalWidth = AnimationCatalog.CellWidth * AnimationCatalog.VerticalWalkingColumns;
        var expectedVerticalHeight = AnimationCatalog.CellHeight * AnimationCatalog.VerticalWalkingRows;
        if (verticalWalking.PixelWidth != expectedVerticalWidth || verticalWalking.PixelHeight != expectedVerticalHeight)
        {
            throw new InvalidDataException($"上下行走姿态尺寸错误：{verticalWalking.PixelWidth}×{verticalWalking.PixelHeight}。");
        }

        return new SpriteAtlas(source, shooting, verticalWalking, assets);
    }

    public SpriteFrame Frame(AnimationID animation, int index)
    {
        var spec = AnimationCatalog.SpecFor(animation);
        return Frame(spec.Row, Math.Clamp(index, 0, spec.FrameCount - 1));
    }

    public SpriteFrame Frame(Direction8 direction)
    {
        var (row, column) = AnimationCatalog.AtlasCell(direction);
        return Frame(row, column);
    }

    public SpriteFrame ShootingFrame(Direction8 direction)
    {
        var column = AnimationCatalog.ShootingColumn(direction);
        if (_shootingCache.TryGetValue(column, out var cached)) return cached;
        var frame = Crop(_shootingSource, column * AnimationCatalog.CellWidth, 0);
        _shootingCache[column] = frame;
        return frame;
    }

    public SpriteFrame VerticalWalkingFrame(VerticalWalkingDirection direction, int index)
    {
        var spec = AnimationCatalog.VerticalWalkingSpecFor(direction);
        var column = Math.Clamp(index, 0, spec.FrameCount - 1);
        if (_verticalWalkingCache.TryGetValue((spec.Row, column), out var cached)) return cached;
        var frame = Crop(
            _verticalWalkingSource,
            column * AnimationCatalog.CellWidth,
            spec.Row * AnimationCatalog.CellHeight);
        _verticalWalkingCache[(spec.Row, column)] = frame;
        return frame;
    }

    public SpriteFrame TearFrame()
    {
        if (_cachedTear != null) return _cachedTear;
        var bitmap = LoadPng(Path.Combine(_assetsDirectory, "IsaacTear.png"));
        _cachedTear = ToSpriteFrame(bitmap);
        return _cachedTear;
    }

    private SpriteFrame Frame(int row, int column)
    {
        if (_cache.TryGetValue((row, column), out var cached)) return cached;
        var frame = Crop(_source, column * AnimationCatalog.CellWidth, row * AnimationCatalog.CellHeight);
        _cache[(row, column)] = frame;
        return frame;
    }

    private static SpriteFrame Crop(BitmapSource source, int x, int y)
    {
        var crop = new CroppedBitmap(source, new System.Windows.Int32Rect(
            x, y, AnimationCatalog.CellWidth, AnimationCatalog.CellHeight));
        crop.Freeze();
        return ToSpriteFrame(crop);
    }

    private static BitmapSource LoadPng(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException($"找不到素材 {Path.GetFileName(path)}。请先运行 Windows/scripts/convert_assets.py。", path);
        }
        using var stream = File.OpenRead(path);
        var decoder = new PngBitmapDecoder(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        var frame = decoder.Frames[0];
        frame.Freeze();
        return frame;
    }

    /// <summary>统一转成 BGRA32 提取 alpha 通道，供点击穿透判定。</summary>
    private static SpriteFrame ToSpriteFrame(BitmapSource bitmap)
    {
        BitmapSource normalized = bitmap;
        if (bitmap.Format != PixelFormats.Bgra32)
        {
            var converted = new FormatConvertedBitmap(bitmap, PixelFormats.Bgra32, null, 0);
            converted.Freeze();
            normalized = converted;
        }
        var width = normalized.PixelWidth;
        var height = normalized.PixelHeight;
        var stride = width * 4;
        var bgra = new byte[stride * height];
        normalized.CopyPixels(bgra, stride, 0);
        var alpha = new byte[width * height];
        for (var i = 0; i < alpha.Length; i++)
        {
            alpha[i] = bgra[i * 4 + 3];
        }
        return new SpriteFrame { Image = normalized, Alpha = alpha, PixelWidth = width, PixelHeight = height };
    }
}
