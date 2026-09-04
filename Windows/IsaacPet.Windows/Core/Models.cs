using System.IO;
using System.Text.Json;

namespace IsaacPet.Windows.Core;

/// <summary>桌宠设置，等价于 macOS 版 IsaacPetCore 的 PetSettings。</summary>
public sealed class PetSettings
{
    public double Scale { get; set; } = 1.0;
    public bool RoamingEnabled { get; set; } = true;
    public string? ScreenIdentifier { get; set; }
    public double HorizontalPosition { get; set; } = 0.82;

    public void Normalize()
    {
        Scale = ValidScale(Scale);
        HorizontalPosition = Math.Clamp(HorizontalPosition, 0, 1);
    }

    public static double ValidScale(double value)
    {
        double[] choices = [0.75, 1.0, 1.25];
        var best = choices[0];
        foreach (var choice in choices)
        {
            if (Math.Abs(choice - value) < Math.Abs(best - value)) best = choice;
        }
        return best;
    }
}

public static class SpeechBubblePolicy
{
    public const int MaximumCharacters = 80;

    public static string? Normalized(string? rawValue)
    {
        if (string.IsNullOrWhiteSpace(rawValue)) return null;
        var collapsed = string.Join(' ', rawValue.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        if (collapsed.Length == 0) return null;
        return collapsed.Length > MaximumCharacters
            ? collapsed[..(MaximumCharacters - 1)] + "…"
            : collapsed;
    }

    public static TimeSpan DisplayDuration(string message) =>
        TimeSpan.FromSeconds(Math.Clamp(3 + message.Length * 0.055, 3, 8));
}

public static class PetSpeechLibrary
{
    private static readonly string[] Phrases =
    [
        "嗨！今天也要加油 :)",
        "记得休息一下。",
        "我会在这里陪你。",
        "先完成最小的一步吧！",
        "喝口水？",
        "今天想做什么？",
    ];

    private static readonly string[] Expressions =
    [
        ":)",
        "♥",
        "...",
        "!",
        "T_T",
        "o_o",
        ":P",
    ];

    private static readonly Random Rng = new();

    public static string RandomPhrase() => Phrases[Rng.Next(Phrases.Length)];

    public static string RandomExpression() => Expressions[Rng.Next(Expressions.Length)];
}

/// <summary>
/// 屏幕工作区（DIP 单位，左上原点）。macOS 版以左下为原点，这里在转换层处理 y 方向差异。
/// </summary>
public readonly record struct ScreenBoundsDip(double X, double Y, double Width, double Height)
{
    public double MinX => X;
    public double MinY => Y;
    public double MaxX => X + Width;
    public double MaxY => Y + Height;
    public double MidX => X + Width / 2;

    public bool Contains(double px, double py) =>
        px >= MinX && px < MaxX && py >= MinY && py < MaxY;

    /// <summary>桌宠停靠在屏幕底部时的位置。</summary>
    public (double Left, double Top) Origin(double horizontalPosition, double petWidth, double petHeight, double bottomPadding = 4)
    {
        var availableWidth = Math.Max(0, Width - petWidth);
        return (MinX + availableWidth * Math.Clamp(horizontalPosition, 0, 1), MaxY - petHeight - bottomPadding);
    }

    public (double Left, double Top) ClampedOrigin(double left, double top, double petWidth, double petHeight, double bottomPadding = 4)
    {
        var maxX = Math.Max(MinX, MaxX - petWidth);
        return (Math.Clamp(left, MinX, maxX), MaxY - petHeight - bottomPadding);
    }

    public (double Left, double Top) ClampedFreeOrigin(double left, double top, double petWidth, double petHeight, double padding = 4)
    {
        var minX = MinX + padding;
        var maxX = Math.Max(minX, MaxX - petWidth - padding);
        var minY = MinY + padding;
        var maxY = Math.Max(minY, MaxY - petHeight - padding);
        return (Math.Clamp(left, minX, maxX), Math.Clamp(top, minY, maxY));
    }

    public double HorizontalPositionFor(double left, double petWidth)
    {
        var availableWidth = Width - petWidth;
        if (availableWidth <= 0) return 0;
        return Math.Clamp((left - MinX) / availableWidth, 0, 1);
    }
}

public static class TodoFileCodec
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public static string Encode(IReadOnlyList<TodoItem> items) =>
        JsonSerializer.Serialize(TodoPolicy.Sorted(items), Options);

    public static List<TodoItem> Decode(string json) =>
        TodoPolicy.Sorted(JsonSerializer.Deserialize<List<TodoItem>>(json, Options) ?? []);
}

public sealed class TodoStore
{
    private readonly string _filePath;

    public IReadOnlyList<TodoItem> Items { get; private set; } = [];

    public TodoStore(string? filePath = null)
    {
        _filePath = filePath ?? Path.Combine(AppPaths.DataDirectory, "todos-v1.json");
        Items = Load();
    }

    public TodoItem Add(string rawTitle, DateTimeOffset? dueAt)
    {
        var title = TodoPolicy.NormalizedTitle(rawTitle)
            ?? throw new InvalidOperationException("Todo 标题不能为空。");
        var item = new TodoItem { Title = title, DueAt = dueAt };
        Commit([.. Items, item]);
        return item;
    }

    public TodoItem? ToggleCompleted(Guid id, DateTimeOffset? at = null)
    {
        var items = Items.ToList();
        var index = items.FindIndex(i => i.Id == id);
        if (index < 0) return null;
        var item = items[index];
        item.CompletedAt = item.IsCompleted ? null : (at ?? DateTimeOffset.Now);
        if (!item.IsCompleted)
        {
            // 恢复任务是一个新的提醒生命周期，包括已过期任务。
            item.RemindedAt = null;
        }
        Commit(items);
        return item;
    }

    public void Remove(Guid id) => Commit(Items.Where(i => i.Id != id).ToList());

    public void MarkRemindersDelivered(IReadOnlyCollection<Guid> ids, DateTimeOffset? at = null)
    {
        if (ids.Count == 0) return;
        var timestamp = at ?? DateTimeOffset.Now;
        var items = Items.ToList();
        foreach (var item in items)
        {
            if (ids.Contains(item.Id)) item.RemindedAt = timestamp;
        }
        Commit(items);
    }

    public TodoImportSummary ImportExternalRecords(IReadOnlyList<ExternalTodoRecord> records, DateTimeOffset? at = null)
    {
        var (items, summary) = TodoPolicy.Merging(records, Items, at);
        Commit(items);
        return summary;
    }

    private void Commit(List<TodoItem> updated)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
        var temp = _filePath + ".tmp";
        File.WriteAllText(temp, TodoFileCodec.Encode(updated));
        File.Move(temp, _filePath, overwrite: true);
        Items = TodoPolicy.Sorted(updated);
    }

    private List<TodoItem> Load()
    {
        if (!File.Exists(_filePath)) return [];
        try
        {
            return TodoFileCodec.Decode(File.ReadAllText(_filePath));
        }
        catch (JsonException)
        {
            return [];
        }
    }
}

public static class AppPaths
{
    /// <summary>Windows 端数据目录：%APPDATA%\Isaac Pet（对应 macOS 的 Application Support）。</summary>
    public static string DataDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Isaac Pet");
}
