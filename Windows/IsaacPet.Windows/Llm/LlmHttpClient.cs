using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace IsaacPet.Windows.Llm;

public interface ILLMReplyProvider
{
    Task<string> RespondAsync(LlmConnectionConfig config, string systemPrompt, string input, CancellationToken cancellationToken);
}

/// <summary>连接测试结果：是否连通 + 面向用户的一句话结论。</summary>
public sealed record LlmConnectionTestResult(bool Ok, string Message);

/// <summary>
/// HTTP LLM 客户端：按配置的 API 格式发送 OpenAI chat/completions 或
/// Anthropic messages 请求。移植自 macOS 版 HTTPLLMClient
/// （store:false、30 秒超时、80 字气泡限制在上层处理）。
/// 兼容性对齐 magpie 网关的做法：推理模型的 reasoning_content、数组型 content、
/// 思考标签统一规整；finish_reason=length 且正文为空时加大输出预算重试一次。
/// </summary>
public sealed class LlmHttpClient : ILLMReplyProvider
{
    private const int InitialMaxTokens = 256;
    private const int ReasoningRetryMaxTokens = 1024;
    private const string AnthropicVersion = "2023-06-01";
    private static readonly TimeSpan ProbeTimeout = TimeSpan.FromSeconds(15);
    private static readonly HttpClient Http = CreateClient(TimeSpan.FromSeconds(30));
    private static readonly HttpClient LocalHttp = CreateClient(TimeSpan.FromSeconds(30), useProxy: false);

    private static HttpClient CreateClient(TimeSpan timeout, bool useProxy = true) =>
        new(new SocketsHttpHandler { UseProxy = useProxy }) { Timeout = timeout };

    /// <summary>本机服务（Ollama / LM Studio）不走系统代理：代理常把 localhost 请求转发失败。</summary>
    private static HttpClient ClientFor(Uri endpoint) => endpoint.IsLoopback ? LocalHttp : Http;

    public async Task<string> RespondAsync(
        LlmConnectionConfig config,
        string systemPrompt,
        string input,
        CancellationToken cancellationToken)
    {
        var reply = await SendOnceAsync(config, systemPrompt, input, InitialMaxTokens, cancellationToken).ConfigureAwait(false);
        if (!LlmReplyDecoder.HasVisibleContent(config.ApiFormat, reply)
            && LlmReplyDecoder.WasTruncated(config.ApiFormat, reply))
        {
            // 推理模型把预算全用在思考上：加大预算重试一次。
            var retried = await SendOnceAsync(config, systemPrompt, input, ReasoningRetryMaxTokens, cancellationToken).ConfigureAwait(false);
            if (LlmReplyDecoder.HasVisibleContent(config.ApiFormat, retried))
            {
                return LlmReplyDecoder.ExtractVisibleText(config.ApiFormat, retried);
            }
            // 重试仍无正文：有思考内容就展示思考，否则报预算耗尽。
            var salvaged = LlmReplyDecoder.TryExtractVisibleText(config.ApiFormat, retried);
            if (salvaged != null) return salvaged;
            throw new InvalidOperationException("模型把输出预算全用在了思考上，没有返回正文。可以换一个非推理模型，或换一个输出预算更大的模型。");
        }
        return LlmReplyDecoder.ExtractVisibleText(config.ApiFormat, reply);
    }

    private static async Task<string> SendOnceAsync(
        LlmConnectionConfig config,
        string systemPrompt,
        string input,
        int maxTokens,
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
                    max_tokens = maxTokens,
                    stream = false,
                });
                if (key.Length > 0) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
                break;
            case LlmApiFormat.Anthropic:
                request.Content = JsonContent(new
                {
                    model,
                    system = systemPrompt,
                    max_tokens = maxTokens,
                    messages = new object[] { new { role = "user", content = input } },
                });
                request.Headers.TryAddWithoutValidation("anthropic-version", AnthropicVersion);
                if (key.Length > 0) request.Headers.TryAddWithoutValidation("x-api-key", key);
                break;
        }

        using var response = await ClientFor(endpoint).SendAsync(request, cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(DecodeApiError(config.ApiFormat, body, (int)response.StatusCode));
        }
        return body;
    }

    /// <summary>
    /// 测试连通性：优先 GET /models（OpenAI 兼容约定，顺带报告可用模型数）；
    /// 服务不支持该端点时退回一次最小 chat 请求。Key 错误、超时等都换算成一句话结论。
    /// </summary>
    public async Task<LlmConnectionTestResult> TestConnectionAsync(
        LlmConnectionConfig config,
        CancellationToken cancellationToken)
    {
        var endpoint = config.EndpointUrl() ?? throw new InvalidOperationException("Base URL 无效。");
        var modelsUrl = config.ModelsUrl() ?? throw new InvalidOperationException("Base URL 无效。");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(ProbeTimeout);
        try
        {
            using var modelsRequest = new HttpRequestMessage(HttpMethod.Get, modelsUrl);
            ApplyAuth(modelsRequest, config);
            using var modelsResponse = await ClientFor(modelsUrl).SendAsync(modelsRequest, timeout.Token).ConfigureAwait(false);
            var modelsBody = await modelsResponse.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
            if (modelsResponse.IsSuccessStatusCode)
            {
                var count = LlmModelCatalog.CountFromJson(modelsBody);
                return new LlmConnectionTestResult(true, count > 0
                    ? $"连接正常（{endpoint.Host}），发现 {count} 个可用模型。"
                    : $"连接正常（{endpoint.Host}）。该服务没有返回模型列表。");
            }
            if (modelsResponse.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed
                or HttpStatusCode.NotImplemented or HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            {
                // /models 不可用或需要聊天权限：退回最小 chat 请求再试。
                return await ProbeWithChatAsync(config, cancellationToken).ConfigureAwait(false);
            }
            return new LlmConnectionTestResult(false,
                DecodeApiError(config.ApiFormat, modelsBody, (int)modelsResponse.StatusCode));
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return new LlmConnectionTestResult(false, $"连接 {endpoint.Host} 超时。");
        }
        catch (Exception error) when (error is HttpRequestException or IOException)
        {
            return new LlmConnectionTestResult(false, $"无法连接 {endpoint.Host}：{error.Message}");
        }
    }

    /// <summary>拉取服务端可用模型列表（GET /models）；失败时抛 InvalidOperationException（消息取服务端原文）。</summary>
    public async Task<IReadOnlyList<string>> ListModelsAsync(
        LlmConnectionConfig config,
        CancellationToken cancellationToken)
    {
        var modelsUrl = config.ModelsUrl() ?? throw new InvalidOperationException("Base URL 无效。");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(ProbeTimeout);
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, modelsUrl);
            ApplyAuth(request, config);
            using var response = await ClientFor(modelsUrl).SendAsync(request, timeout.Token).ConfigureAwait(false);
            var body = await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(DecodeApiError(config.ApiFormat, body, (int)response.StatusCode));
            }
            return LlmModelCatalog.ParseIds(body);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new InvalidOperationException("拉取模型列表超时。");
        }
        catch (Exception error) when (error is HttpRequestException or IOException)
        {
            throw new InvalidOperationException($"无法连接模型列表端点：{error.Message}");
        }
    }

    private async Task<LlmConnectionTestResult> ProbeWithChatAsync(
        LlmConnectionConfig config,
        CancellationToken cancellationToken)
    {
        var endpoint = config.EndpointUrl()!;
        var model = config.Model.Trim();
        if (model.Length == 0)
        {
            return new LlmConnectionTestResult(false, "服务不支持 /models 接口，且模型名称留空，无法进一步测试。请填写模型名称后再试。");
        }
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(ProbeTimeout);
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
            var key = config.ApiKey.Trim();
            if (config.ApiFormat == LlmApiFormat.Anthropic)
            {
                request.Content = JsonContent(new
                {
                    model,
                    max_tokens = 16,
                    messages = new object[] { new { role = "user", content = "ping" } },
                });
                request.Headers.TryAddWithoutValidation("anthropic-version", AnthropicVersion);
                if (key.Length > 0) request.Headers.TryAddWithoutValidation("x-api-key", key);
            }
            else
            {
                request.Content = JsonContent(new
                {
                    model,
                    max_tokens = 16,
                    stream = false,
                    messages = new object[] { new { role = "user", content = "ping" } },
                });
                if (key.Length > 0) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
            }
            using var response = await ClientFor(endpoint).SendAsync(request, timeout.Token).ConfigureAwait(false);
            var body = await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
            return response.IsSuccessStatusCode
                ? new LlmConnectionTestResult(true, $"连接正常（{endpoint.Host}），模型 {model} 有响应。")
                : new LlmConnectionTestResult(false, DecodeApiError(config.ApiFormat, body, (int)response.StatusCode));
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return new LlmConnectionTestResult(false, $"连接 {endpoint.Host} 超时。");
        }
        catch (Exception error) when (error is HttpRequestException or IOException)
        {
            return new LlmConnectionTestResult(false, $"无法连接 {endpoint.Host}：{error.Message}");
        }
    }

    private static void ApplyAuth(HttpRequestMessage request, LlmConnectionConfig config)
    {
        var key = config.ApiKey.Trim();
        if (key.Length == 0) return;
        if (config.ApiFormat == LlmApiFormat.Anthropic)
        {
            request.Headers.TryAddWithoutValidation("x-api-key", key);
            request.Headers.TryAddWithoutValidation("anthropic-version", AnthropicVersion);
        }
        else
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
        }
    }

    private static StringContent JsonContent(object payload) =>
        new(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

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
