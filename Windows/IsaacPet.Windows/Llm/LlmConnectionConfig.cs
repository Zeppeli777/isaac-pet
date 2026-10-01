using System.Text;
using System.Text.Json;

namespace IsaacPet.Windows.Llm;

/// <summary>LLM 服务的 API 风格。OpenAI 兼容格式走 chat/completions，Anthropic 兼容格式走 messages。</summary>
public enum LlmApiFormat
{
    OpenAi,
    Anthropic,
}

/// <summary>
/// LLM 连接配置：Base URL、API Key、模型和 API 格式。移植自 macOS 版 LLMConnectionConfig。
/// API Key 在 Windows 端只存 DPAPI 密文，不落明文文件。
/// </summary>
public sealed record LlmConnectionConfig
{
    public required string BaseUrl { get; init; }
    public required string ApiKey { get; init; }
    public required string Model { get; init; }
    public required LlmApiFormat ApiFormat { get; init; }

    public static string NormalizeBaseUrl(string baseUrl)
    {
        var trimmed = baseUrl.Trim();
        while (trimmed.EndsWith('/')) trimmed = trimmed[..^1];
        return trimmed;
    }

    /// <summary>规范化 Base URL 并拼接对应格式的端点。Anthropic 约定 Base URL 含 /v1，缺失时自动补上。</summary>
    public Uri? EndpointUrl()
    {
        var base_ = NormalizeBaseUrl(BaseUrl);
        if (base_.Length == 0 || !Uri.TryCreate(base_, UriKind.Absolute, out var uri) || uri.Host.Length == 0)
        {
            return null;
        }
        var scheme = uri.Scheme.ToLowerInvariant();
        if (scheme != "https" && scheme != "http") return null;
        var path = ApiFormat switch
        {
            LlmApiFormat.Anthropic => (base_.EndsWith("/v1") ? base_ : base_ + "/v1") + "/messages",
            _ => base_ + "/chat/completions",
        };
        return new Uri(path);
    }

    public void Validate()
    {
        if (EndpointUrl() == null) throw new InvalidOperationException("Base URL 必须是以 http(s):// 开头的有效地址。");
        if (Model.Length == 0 || Model.Any(char.IsWhiteSpace)) throw new InvalidOperationException("模型名称不能为空，且不能包含空格。");
    }

    /// <summary>从配置文件文本导入。容忍常见别名键名，apiFormat 缺失时按 Base URL 主机名推断。</summary>
    public static LlmConnectionConfig ParseImported(string json)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(json);
        }
        catch (JsonException)
        {
            throw new InvalidOperationException("配置文件不是有效的 JSON 对象。");
        }
        using (document)
        {
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                throw new InvalidOperationException("配置文件不是有效的 JSON 对象。");
            }
            var fields = document.RootElement;

            string Text(params string[] names) => names
                .Select(name => fields.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
                    ? value.GetString()
                    : null)
                .FirstOrDefault(text => !string.IsNullOrWhiteSpace(text)) ?? "";

            var baseUrl = NormalizeBaseUrl(Text("baseURL", "baseUrl", "base_url", "endpoint", "url"));
            var apiKey = Text("apiKey", "api_key", "key", "token");
            var model = Text("model", "modelId", "model_id", "model_name");
            var rawFormat = Text("apiFormat", "api_format", "format", "provider", "type").ToLowerInvariant();
            var apiFormat = rawFormat switch
            {
                "anthropic" or "claude" or "anthropic-compatible" => LlmApiFormat.Anthropic,
                "openai" or "openai-compatible" or "chat-completions" => LlmApiFormat.OpenAi,
                _ => baseUrl.ToLowerInvariant().Contains("anthropic") ? LlmApiFormat.Anthropic : LlmApiFormat.OpenAi,
            };
            return new LlmConnectionConfig { BaseUrl = baseUrl, ApiKey = apiKey, Model = model, ApiFormat = apiFormat };
        }
    }

    public string DescribeEndpoint()
    {
        var uri = EndpointUrl();
        return uri?.Host ?? "(未配置)";
    }

    public override string ToString()
    {
        var builder = new StringBuilder();
        builder.Append(ApiFormat == LlmApiFormat.Anthropic ? "Anthropic" : "OpenAI").Append(" · ").Append(BaseUrl).Append(" · ").Append(Model);
        return builder.ToString();
    }
}
