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
    private readonly BitmapSource _raisingSource;
    private readonly string _assetsDirectory;
    private readonly Dictionary<(int Row, int Column), SpriteFrame> _cache = new();
    private readonly Dictionary<int, SpriteFrame> _shootingCache = new();
    private readonly Dictionary<(int Row, int Column), SpriteFrame> _verticalWalkingCache = new();
    private readonly Dictionary<int, SpriteFrame> _raisingCache = new();
    private readonly Dictionary<string, SpriteFrame> _cardCache = new(StringComparer.Ordinal);
    private SpriteFrame? _cachedTear;
    private SpriteFrame? _cachedTearDrop;
    private readonly Dictionary<EmoteID, SpriteFrame> _emoteCache = new();

    private SpriteAtlas(
        BitmapSource source,
        BitmapSource shooting,
        BitmapSource verticalWalking,
        BitmapSource raising,
        string assetsDirectory)
    {
        _source = source;
        _shootingSource = shooting;
        _verticalWalkingSource = verticalWalking;
        _raisingSource = raising;
        _assetsDirectory = assetsDirectory;
    }

    public static string AssetsDirectory => Path.Combine(AppContext.BaseDirectory, "Assets");

    public static bool AppearanceAvailable(string sheetName) =>
        File.Exists(Path.Combine(AssetsDirectory, sheetName + ".png"));

    public static SpriteAtlas Load(
        string spriteSheetName = IsaacSheet,
        string? subdirectory = null,
        string? shootingAtlasName = null,
        string? verticalWalkingName = null,
        string? raisingAtlasName = null)
    {
        var sheetDirectory = subdirectory == null
            ? AssetsDirectory
            : Path.Combine(AssetsDirectory, subdirectory);
        var source = LoadPng(Path.Combine(sheetDirectory, spriteSheetName + ".png"));
        var expectedWidth = AnimationCatalog.CellWidth * AnimationCatalog.Columns;
        var expectedHeight = AnimationCatalog.CellHeight * AnimationCatalog.Rows;
        if (source.PixelWidth != expectedWidth || source.PixelHeight != expectedHeight)
        {
            throw new InvalidDataException($"动画图集尺寸错误：{source.PixelWidth}×{source.PixelHeight}。");
        }

        // 角色可以自带射击与竖向行走辅助图集；缺失时回退 Isaac 的基础图集，
        // 否则该形象在对应姿态下会露出 Isaac 的头部（与 macOS 版行为一致）。
        var shootingPath = shootingAtlasName == null
            ? Path.Combine(AssetsDirectory, "shooting-atlas.png")
            : Path.Combine(sheetDirectory, shootingAtlasName + ".png");
        var shooting = LoadPng(shootingPath);
        if (shooting.PixelWidth != AnimationCatalog.CellWidth * 4 || shooting.PixelHeight != AnimationCatalog.CellHeight)
        {
            throw new InvalidDataException($"射击姿态尺寸错误：{shooting.PixelWidth}×{shooting.PixelHeight}。");
        }

        var verticalWalkingPath = verticalWalkingName == null
            ? Path.Combine(AssetsDirectory, "walking-vertical-atlas.png")
            : Path.Combine(sheetDirectory, verticalWalkingName + ".png");
        var verticalWalking = LoadPng(verticalWalkingPath);
        var expectedVerticalWidth = AnimationCatalog.CellWidth * AnimationCatalog.VerticalWalkingColumns;
        var expectedVerticalHeight = AnimationCatalog.CellHeight * AnimationCatalog.VerticalWalkingRows;
        if (verticalWalking.PixelWidth != expectedVerticalWidth || verticalWalking.PixelHeight != expectedVerticalHeight)
        {
            throw new InvalidDataException($"上下行走姿态尺寸错误：{verticalWalking.PixelWidth}×{verticalWalking.PixelHeight}。");
        }

        // 举臂辅助图集：角色可以自带（Magdalene），缺失时回退 Isaac 的基础图集。
        var raisingPath = raisingAtlasName == null
            ? Path.Combine(AssetsDirectory, "raising-atlas.png")
            : Path.Combine(sheetDirectory, raisingAtlasName + ".png");
        var raising = LoadPng(raisingPath);
        var expectedRaisingWidth = AnimationCatalog.CellWidth * AnimationCatalog.RaisingColumns;
        var expectedRaisingHeight = AnimationCatalog.CellHeight * AnimationCatalog.RaisingRows;
        if (raising.PixelWidth != expectedRaisingWidth || raising.PixelHeight != expectedRaisingHeight)
        {
            throw new InvalidDataException($"举卡姿态尺寸错误：{raising.PixelWidth}×{raising.PixelHeight}。");
        }

        return new SpriteAtlas(source, shooting, verticalWalking, raising, AssetsDirectory);
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

    /// <summary>举卡抽牌姿势帧；渲染自举臂辅助图集（row 0，8 列）。</summary>
    public SpriteFrame RaisingFrame(int index)
    {
        var column = Math.Clamp(index, 0, AnimationCatalog.RaisingColumns - 1);
        if (_raisingCache.TryGetValue(column, out var cached)) return cached;
        var frame = Crop(_raisingSource, column * AnimationCatalog.CellWidth, 0);
        _raisingCache[column] = frame;
        return frame;
    }

    /// <summary>卡面 HUD 图标（14×18），4 倍放大后与桌宠同量级。</summary>
    public SpriteFrame CardFrame(TarotCard card)
    {
        if (_cardCache.TryGetValue(card.Id, out var cached)) return cached;
        var directory = Path.Combine(_assetsDirectory, "Cards");
        var bitmap = LoadPng(Path.Combine(directory, card.IconResource + ".png"));
        var frame = ToSpriteFrame(bitmap);
        _cardCache[card.Id] = frame;
        return frame;
    }

    /// <summary>洗牌时显示的卡背设计。</summary>
    public SpriteFrame CardBackFrame()
    {
        if (_cardCache.TryGetValue("__back__", out var cached)) return cached;
        var bitmap = LoadPng(Path.Combine(_assetsDirectory, "Cards", "CardBack.png"));
        var frame = ToSpriteFrame(bitmap);
        _cardCache["__back__"] = frame;
        return frame;
    }

    public SpriteFrame TearFrame()
    {
        if (_cachedTear != null) return _cachedTear;
        var bitmap = LoadPng(Path.Combine(_assetsDirectory, "IsaacTear.png"));
        _cachedTear = ToSpriteFrame(bitmap);
        return _cachedTear;
    }

    public SpriteFrame TearDropFrame()
    {
        if (_cachedTearDrop != null) return _cachedTearDrop;
        var bitmap = LoadPng(Path.Combine(_assetsDirectory, "IsaacTearDrop.png"));
        _cachedTearDrop = ToSpriteFrame(bitmap);
        return _cachedTearDrop;
    }

    public SpriteFrame EmoteFrame(EmoteID emote)
    {
        if (_emoteCache.TryGetValue(emote, out var cached)) return cached;
        var bitmap = LoadPng(Path.Combine(_assetsDirectory, emote.ResourceName() + ".png"));
        var frame = ToSpriteFrame(bitmap);
        _emoteCache[emote] = frame;
        return frame;
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
