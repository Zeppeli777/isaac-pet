using System.Text.Json;
using System.Text.Json.Serialization;

namespace IsaacPet.Windows.Core;

public enum TodoExternalKind
{
    AppleReminders,
    Notion,
}

public sealed class TodoExternalSource
{
    [JsonPropertyName("kind")]
    [JsonConverter(typeof(JsonStringEnumConverter<TodoExternalKind>))]
    public TodoExternalKind Kind { get; init; }

    [JsonPropertyName("itemIdentifier")]
    public string ItemIdentifier { get; init; } = "";

    [JsonPropertyName("containerIdentifier")]
    public string? ContainerIdentifier { get; set; }

    [JsonPropertyName("containerTitle")]
    public string? ContainerTitle { get; set; }

    [JsonPropertyName("lastSyncedAt")]
    public DateTimeOffset LastSyncedAt { get; set; } = DateTimeOffset.Now;
}

public sealed class TodoItem
{
    [JsonPropertyName("id")]
    public Guid Id { get; init; } = Guid.NewGuid();

    [JsonPropertyName("title")]
    public string Title { get; set; } = "";

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.Now;

    [JsonPropertyName("dueAt")]
    public DateTimeOffset? DueAt { get; set; }

    [JsonPropertyName("completedAt")]
    public DateTimeOffset? CompletedAt { get; set; }

    [JsonPropertyName("remindedAt")]
    public DateTimeOffset? RemindedAt { get; set; }

    [JsonPropertyName("externalSource")]
    public TodoExternalSource? ExternalSource { get; set; }

    [JsonIgnore]
    public bool IsCompleted => CompletedAt != null;

    public static TodoItem Create(string title, DateTimeOffset? dueAt = null, TodoExternalSource? source = null)
        => new()
        {
            Title = TodoPolicy.NormalizedTitle(title) ?? "",
            DueAt = dueAt,
            ExternalSource = source,
        };
}

public sealed record ExternalTodoRecord(TodoExternalSource Source, string Title, DateTimeOffset? DueAt, DateTimeOffset? CompletedAt);

public sealed record TodoImportSummary(int Inserted, int Updated, int Skipped);

public static class TodoPolicy
{
    public const int MaximumTitleCharacters = 120;

    public static string? NormalizedTitle(string? rawValue)
    {
        if (string.IsNullOrWhiteSpace(rawValue)) return null;
        var collapsed = string.Join(' ', rawValue.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        if (collapsed.Length == 0) return null;
        return collapsed.Length > MaximumTitleCharacters
            ? collapsed[..(MaximumTitleCharacters - 1)] + "…"
            : collapsed;
    }

    public static List<TodoItem> Sorted(IEnumerable<TodoItem> items) => items
        .OrderBy(i => i.IsCompleted)
        .ThenBy(i => i.DueAt ?? DateTimeOffset.MaxValue)
        .ThenBy(i => i.CreatedAt)
        .ToList();

    public static List<TodoItem> Pending(IEnumerable<TodoItem> items) =>
        Sorted(items.Where(i => !i.IsCompleted));

    public static TodoItem? NextPending(IEnumerable<TodoItem> items) => Pending(items).FirstOrDefault();

    public static List<TodoItem> DueForDelivery(IEnumerable<TodoItem> items, DateTimeOffset now) =>
        Sorted(items.Where(i => !i.IsCompleted && i.RemindedAt == null && i.DueAt is { } due && due <= now));

    public static (List<TodoItem> Items, TodoImportSummary Summary) Merging(
        IReadOnlyList<ExternalTodoRecord> records,
        IReadOnlyList<TodoItem> items,
        DateTimeOffset? now = null)
    {
        var timestamp = now ?? DateTimeOffset.Now;
        var merged = new List<TodoItem>(items);
        var inserted = 0;
        var updated = 0;
        var skipped = 0;

        foreach (var record in records)
        {
            var title = NormalizedTitle(record.Title);
            if (title == null || record.Source.ItemIdentifier.Length == 0)
            {
                skipped += 1;
                continue;
            }
            var index = merged.FindIndex(i =>
                i.ExternalSource is { } source
                && source.Kind == record.Source.Kind
                && source.ItemIdentifier == record.Source.ItemIdentifier);
            if (index >= 0)
            {
                var item = merged[index];
                var oldDueAt = item.DueAt;
                var wasCompleted = item.IsCompleted;
                item.Title = title;
                item.DueAt = record.DueAt;
                item.CompletedAt = record.CompletedAt;
                record.Source.LastSyncedAt = timestamp;
                item.ExternalSource = record.Source;
                // 重新打开或改期的来源任务需要重新获得提醒资格。
                if (record.CompletedAt == null && (wasCompleted || oldDueAt != record.DueAt))
                {
                    item.RemindedAt = null;
                }
                updated += 1;
            }
            else
            {
                record.Source.LastSyncedAt = timestamp;
                merged.Add(new TodoItem
                {
                    Title = title,
                    CreatedAt = timestamp,
                    DueAt = record.DueAt,
                    CompletedAt = record.CompletedAt,
                    ExternalSource = record.Source,
                });
                inserted += 1;
            }
        }

        return (Sorted(merged), new TodoImportSummary(inserted, updated, skipped));
    }
}
