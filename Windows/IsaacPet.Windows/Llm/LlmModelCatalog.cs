using System.Text.Json;

namespace IsaacPet.Windows.Llm;

/// <summary>
/// GET /models 响应的解析：OpenAI 与 Anthropic 兼容服务都是这个约定，
/// 返回 {"data":[{"id":"..."}]}；同时容忍顶层数组和字符串数组两种宽松形态。
/// </summary>
public static class LlmModelCatalog
{
    /// <summary>解析模型 ID 列表：去重、按 ID 排序。无法解析时抛 InvalidOperationException。</summary>
    public static IReadOnlyList<string> ParseIds(string json)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(json);
        }
        catch (JsonException)
        {
            throw new InvalidOperationException("模型列表返回了无法解析的数据。");
        }
        using (document)
        {
            var root = document.RootElement;
            var array = root.ValueKind == JsonValueKind.Array
                ? root
                : root.ValueKind == JsonValueKind.Object
                  && root.TryGetProperty("data", out var data)
                  && data.ValueKind == JsonValueKind.Array
                    ? data
                    : default;
            if (array.ValueKind != JsonValueKind.Array) return Array.Empty<string>();

            var ids = new List<string>();
            foreach (var item in array.EnumerateArray())
            {
                switch (item.ValueKind)
                {
                    case JsonValueKind.String:
                        Add(item.GetString());
                        break;
                    case JsonValueKind.Object:
                        if (item.TryGetProperty("id", out var id) && id.ValueKind == JsonValueKind.String)
                        {
                            Add(id.GetString());
                        }
                        break;
                }
            }
            return ids
                .Distinct(StringComparer.Ordinal)
                .OrderBy(id => id, StringComparer.Ordinal)
                .ToList();

            void Add(string? value)
            {
                if (!string.IsNullOrWhiteSpace(value)) ids.Add(value.Trim());
            }
        }
    }

    /// <summary>测试连接时只要个数：解析失败按 0 处理，不打断连通性结论。</summary>
    public static int CountFromJson(string json)
    {
        try
        {
            return ParseIds(json).Count;
        }
        catch (InvalidOperationException)
        {
            return 0;
        }
    }
}
