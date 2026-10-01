using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace IsaacPet.Windows.Llm;

public interface ILLMReplyProvider
{
    Task<string> RespondAsync(LlmConnectionConfig config, string systemPrompt, string input, CancellationToken cancellationToken);
}

/// <summary>
/// HTTP LLM 客户端：按配置的 API 格式发送 OpenAI chat/completions 或
/// Anthropic messages 请求。移植自 macOS 版 HTTPLLMClient
/// （store:false、30 秒超时、80 字气泡限制在上层处理）。
/// </summary>
public sealed class LlmHttpClient : ILLMReplyProvider
{
    private const int MaxOutputTokens = 120;
    private const string AnthropicVersion = "2023-06-01";
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };

    public async Task<string> RespondAsync(
        LlmConnectionConfig config,
        string systemPrompt,
        string input,
        CancellationToken cancellationToken)
    {
        var model = config.Model.Trim();
        if (model.Length == 0) throw new InvalidOperationException("模型名称不能为空。");
        var endpoint = config.EndpointUrl() ?? throw new InvalidOperationException("Base URL 无效。");

        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        var key = config.ApiKey.Trim();
        switch (config.ApiFormat)
        {
            case LlmApiFormat.OpenAi:
                request.Content = JsonContent(new
                {
                    model,
                    messages = new object[]
                    {
                        new { role = "system", content = systemPrompt },
                        new { role = "user", content = input },
                    },
                    max_tokens = Math.Clamp(MaxOutputTokens, 16, 512),
                    stream = false,
                });
                if (key.Length > 0) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
                break;
            case LlmApiFormat.Anthropic:
                request.Content = JsonContent(new
                {
                    model,
                    system = systemPrompt,
                    max_tokens = Math.Clamp(MaxOutputTokens, 16, 512),
                    messages = new object[] { new { role = "user", content = input } },
                });
                request.Headers.TryAddWithoutValidation("anthropic-version", AnthropicVersion);
                if (key.Length > 0) request.Headers.TryAddWithoutValidation("x-api-key", key);
                break;
        }

        using var response = await Http.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(DecodeApiError(config.ApiFormat, body, (int)response.StatusCode));
        }
        return DecodeText(config.ApiFormat, body);
    }

    private static StringContent JsonContent(object payload) =>
        new(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

    private static string DecodeText(LlmApiFormat format, string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.TryGetProperty("error", out var error)
                && error.ValueKind == JsonValueKind.Object
                && error.TryGetProperty("message", out var message)
                && message.GetString() is { Length: > 0 } apiMessage)
            {
                throw new InvalidOperationException(apiMessage);
            }
            var text = format switch
            {
                LlmApiFormat.OpenAi => DecodeOpenAiText(root),
                LlmApiFormat.Anthropic => DecodeAnthropicText(root),
                _ => "",
            };
            text = text.Trim();
            if (text.Length == 0) throw new InvalidOperationException("LLM 没有返回可显示的文字。");
            return text;
        }
        catch (JsonException)
        {
            throw new InvalidOperationException("LLM 返回了无法解析的数据。");
        }
    }

    private static string DecodeOpenAiText(JsonElement root)
    {
        var builder = new StringBuilder();
        if (root.TryGetProperty("choices", out var choices) && choices.ValueKind == JsonValueKind.Array)
        {
            foreach (var choice in choices.EnumerateArray())
            {
                if (!choice.TryGetProperty("message", out var message)) continue;
                if (message.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.String)
                {
                    if (builder.Length > 0) builder.Append('\n');
                    builder.Append(content.GetString());
                }
            }
        }
        return builder.ToString();
    }

    private static string DecodeAnthropicText(JsonElement root)
    {
        var builder = new StringBuilder();
        if (root.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in content.EnumerateArray())
            {
                if (item.TryGetProperty("type", out var type) && type.GetString() == "text"
                    && item.TryGetProperty("text", out var text) && text.ValueKind == JsonValueKind.String)
                {
                    if (builder.Length > 0) builder.Append('\n');
                    builder.Append(text.GetString());
                }
            }
        }
        return builder.ToString();
    }

    private static string DecodeApiError(LlmApiFormat format, string json, int statusCode)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.TryGetProperty("error", out var error)
                && error.ValueKind == JsonValueKind.Object
                && error.TryGetProperty("message", out var message)
                && message.GetString() is { Length: > 0 } apiMessage)
            {
                return apiMessage;
            }
        }
        catch (JsonException)
        {
            // fall through
        }
        return $"LLM 请求失败（HTTP {statusCode}）。";
    }
}
