using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace IsaacPet.Windows.Llm;

public interface ILLMReplyProvider
{
    Task<string> RespondAsync(string input, string model, string token, CancellationToken cancellationToken);
}

/// <summary>OpenAI Responses API 客户端，行为与 macOS 版一致（store:false、30 秒超时、80 字气泡限制在上层处理）。</summary>
public sealed class OpenAIResponsesClient : ILLMReplyProvider
{
    private static readonly Uri Endpoint = new("https://api.openai.com/v1/responses");
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };

    public async Task<string> RespondAsync(string input, string model, string token, CancellationToken cancellationToken)
    {
        var trimmedModel = model.Trim();
        if (trimmedModel.Length == 0) throw new InvalidOperationException("模型名称不能为空。");

        var maxOutputTokens = Math.Clamp(120, 16, 512);
        var payload = JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["model"] = trimmedModel,
            ["instructions"] = "你是像素桌宠 Isaac。用温和、简短、有帮助的中文回答，不要声称操作了用户的电脑，不要调用工具，答案不超过 80 个中文字符。",
            ["input"] = input,
            ["max_output_tokens"] = maxOutputTokens,
            ["store"] = false,
        });

        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint)
        {
            Content = new StringContent(payload, Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        using var response = await Http.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(DecodeApiError(body, (int)response.StatusCode));
        }
        return DecodeText(body);
    }

    private static string DecodeText(string json)
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

        var builder = new StringBuilder();
        if (root.TryGetProperty("output", out var output) && output.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in output.EnumerateArray())
            {
                if (!item.TryGetProperty("content", out var content) || content.ValueKind != JsonValueKind.Array) continue;
                foreach (var part in content.EnumerateArray())
                {
                    if (part.TryGetProperty("type", out var type) && type.GetString() == "output_text"
                        && part.TryGetProperty("text", out var text))
                    {
                        if (builder.Length > 0) builder.Append('\n');
                        builder.Append(text.GetString());
                    }
                }
            }
        }
        var result = builder.ToString().Trim();
        if (result.Length == 0) throw new InvalidOperationException("LLM 没有返回可显示的文字。");
        return result;
    }

    private static string DecodeApiError(string json, int statusCode)
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
