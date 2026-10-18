using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace IsaacPet.Windows.Llm;

/// <summary>
/// LLM 回复的方言归一化：从 OpenAI / Anthropic 兼容服务的响应体里提取一段可显示文字。
/// 借鉴 magpie 网关的做法——不假设服务端返回标准字符串，把 reasoning_content、
/// 数组型 content、思考标签、finish_reason=length 等形态在客户端统一规整。
/// </summary>
public static class LlmReplyDecoder
{
    // 完整的思考块：think / thinking / reasoning 三种常见标签名（属性容忍）。
    // 标签名用 \u003c/\u003e 转义书写，避免源码里出现字面量尖括号标签。
    private static readonly Regex ClosedThinkBlock = new(
        @"\u003c(?:think|thinking|reasoning)\b[^>]*\u003e.*?\u003c/(?:think|thinking|reasoning)\u003e",
        RegexOptions.Singleline | RegexOptions.IgnoreCase);

    private static readonly Regex AnyThinkOpen = new(
        @"\u003c(?:think|thinking|reasoning)\b[^>]*\u003e",
        RegexOptions.IgnoreCase);

    private static readonly Regex ExcessBlankLines = new(@"\n{3,}");

    /// <summary>提取可显示文字；服务端错误直接抛出（消息取服务端原文），无文字时抛通用错误。</summary>
    public static string ExtractVisibleText(LlmApiFormat format, string json)
        => TryExtractVisibleText(format, json)
           ?? throw new InvalidOperationException("LLM 没有返回可显示的文字（服务可能只返回了思考过程，或被安全策略拦截）。");

    /// <summary>
    /// 同 <see cref="ExtractVisibleText"/>，但没有可显示文字时返回 null 而不抛错，
    /// 供调用方判断是否值得加大预算重试。解析失败与服务端错误仍然抛错。
    /// </summary>
    public static string? TryExtractVisibleText(LlmApiFormat format, string json)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(json);
        }
        catch (JsonException)
        {
            throw new InvalidOperationException("LLM 返回了无法解析的数据。");
        }
        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                throw new InvalidOperationException("LLM 返回了无法解析的数据。");
            }
            ThrowIfApiError(root);

            var visible = new StringBuilder();
            var reasoning = new StringBuilder();
            switch (format)
            {
                case LlmApiFormat.OpenAi:
                    CollectOpenAi(root, visible, reasoning);
                    break;
                case LlmApiFormat.Anthropic:
                    CollectAnthropic(root, visible, reasoning);
                    break;
            }

            // 推理模型可能只返回思考过程：退而展示思考内容，好过直接报错
            // （对应 magpie think-tags 中间件把 reasoning_content 并回回复的做法）。
            var text = NormalizeVisibleText(visible.Length > 0 ? visible.ToString() : reasoning.ToString());
            return text.Length == 0 ? null : text;
        }
    }

    /// <summary>
    /// 是否只返回了思考内容：正文（content / text 块）为空。
    /// 推理模型把输出预算全部用在思考上时会出现这种情况，调用方应加大预算重试。
    /// </summary>
    public static bool HasVisibleContent(LlmApiFormat format, string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return false;
            var visible = new StringBuilder();
            var reasoning = new StringBuilder();
            switch (format)
            {
                case LlmApiFormat.OpenAi:
                    CollectOpenAi(root, visible, reasoning);
                    break;
                case LlmApiFormat.Anthropic:
                    CollectAnthropic(root, visible, reasoning);
                    break;
            }
            return visible.Length > 0;
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException)
        {
            // 解析失败或服务端错误体：按「无正文」处理，真正的错误由 ExtractVisibleText 抛出。
            return false;
        }
    }

    /// <summary>finish_reason / stop_reason 表示输出被长度截断（推理模型常见）。</summary>
    public static bool WasTruncated(LlmApiFormat format, string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            switch (format)
            {
                case LlmApiFormat.OpenAi:
                    return root.TryGetProperty("choices", out var choices)
                        && choices.ValueKind == JsonValueKind.Array
                        && choices.EnumerateArray().Any(HasLengthFinishReason);
                case LlmApiFormat.Anthropic:
                    return root.TryGetProperty("stop_reason", out var stopReason)
                        && stopReason.ValueKind == JsonValueKind.String
                        && IsLengthLike(stopReason.GetString());
                default:
                    return false;
            }
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static bool HasLengthFinishReason(JsonElement choice)
        => choice.TryGetProperty("finish_reason", out var reason)
        && reason.ValueKind == JsonValueKind.String
        && IsLengthLike(reason.GetString());

    private static bool IsLengthLike(string? value)
        => value != null
        && (value.Equals("length", StringComparison.OrdinalIgnoreCase)
            || value.Equals("max_tokens", StringComparison.OrdinalIgnoreCase));

    private static void CollectOpenAi(JsonElement root, StringBuilder visible, StringBuilder reasoning)
    {
        if (!root.TryGetProperty("choices", out var choices) || choices.ValueKind != JsonValueKind.Array) return;
        foreach (var choice in choices.EnumerateArray())
        {
            if (choice.TryGetProperty("message", out var message) && message.ValueKind == JsonValueKind.Object)
            {
                if (message.TryGetProperty("content", out var content))
                {
                    CollectContentParts(content, visible, reasoning);
                }
                if (visible.Length == 0 && reasoning.Length == 0)
                {
                    // DeepSeek / StepFun / Moonshot 等推理模型的思考字段约定。
                    AppendIfString(message, "reasoning_content", reasoning);
                    AppendIfString(message, "reasoning", reasoning);
                }
            }
            if (visible.Length == 0 && reasoning.Length == 0)
            {
                // 旧版 completions 形态：text 直接在 choice 上。
                AppendIfString(choice, "text", visible);
            }
        }
    }

    private static void CollectContentParts(JsonElement content, StringBuilder visible, StringBuilder reasoning)
    {
        switch (content.ValueKind)
        {
            case JsonValueKind.String:
                visible.Append(content.GetString());
                break;
            case JsonValueKind.Array:
                foreach (var part in content.EnumerateArray())
                {
                    if (part.ValueKind != JsonValueKind.Object) continue;
                    if (!part.TryGetProperty("text", out var text) || text.ValueKind != JsonValueKind.String) continue;
                    var value = text.GetString();
                    if (string.IsNullOrEmpty(value)) continue;
                    var type = part.TryGetProperty("type", out var t) && t.ValueKind == JsonValueKind.String
                        ? t.GetString()
                        : null;
                    if (type is "reasoning" or "thinking") reasoning.Append(value);
                    else visible.Append(value);
                }
                break;
        }
    }

    private static void CollectAnthropic(JsonElement root, StringBuilder visible, StringBuilder reasoning)
    {
        if (!root.TryGetProperty("content", out var content) || content.ValueKind != JsonValueKind.Array) return;
        foreach (var item in content.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object) continue;
            var type = item.TryGetProperty("type", out var t) && t.ValueKind == JsonValueKind.String ? t.GetString() : null;
            if (type == "thinking")
            {
                AppendIfString(item, "thinking", reasoning);
            }
            else
            {
                // text 块，以及没有 type 字段的宽松兼容形态。
                AppendIfString(item, "text", visible);
            }
        }
    }

    private static void AppendIfString(JsonElement parent, string name, StringBuilder target)
    {
        if (parent.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String)
        {
            target.Append(value.GetString());
        }
    }

    private static void ThrowIfApiError(JsonElement root)
    {
        if (root.TryGetProperty("error", out var error) && error.ValueKind == JsonValueKind.Object
            && error.TryGetProperty("message", out var message) && message.ValueKind == JsonValueKind.String
            && message.GetString() is { Length: > 0 } apiMessage)
        {
            throw new InvalidOperationException(apiMessage);
        }
    }

    /// <summary>剥离思考标签（完整块直接删除，未闭合的从标签处截断），压缩空行并去首尾空白。</summary>
    public static string NormalizeVisibleText(string raw)
    {
        if (string.IsNullOrEmpty(raw)) return "";
        var text = ClosedThinkBlock.Replace(raw, "");
        var unclosed = AnyThinkOpen.Match(text);
        if (unclosed.Success) text = text[..unclosed.Index];
        text = ExcessBlankLines.Replace(text, "\n\n");
        return text.Trim();
    }
}
