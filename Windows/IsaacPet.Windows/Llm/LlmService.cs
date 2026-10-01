using IsaacPet.Windows.Core;
using IsaacPet.Windows.Platform;
using IsaacPet.Windows.Pet;
using IsaacPet.Windows.Settings;
using IsaacPet.Windows.Ui;

namespace IsaacPet.Windows.Llm;

/// <summary>
/// LLM 流程编排：设置、提问、断开、取消。移植自 macOS 版行为：
/// 默认关闭；API Key 只存 DPAPI 密文（macOS 版存明文配置文件，Windows 端不跟进）；
/// 仅主动提问时联网；配置损坏时按未配置状态恢复，不会让应用崩溃。
/// </summary>
public sealed class LlmService
{
    private readonly PetController _pet;
    private readonly SettingsStore _settings;
    private readonly DpapiCredentialStore _credentials = new("llm-credential.bin");
    private readonly LlmHttpClient _client = new();
    private CancellationTokenSource? _requestCts;

    public bool RequestRunning => _requestCts != null;
    public bool CredentialConfigured => _settings.LlmCredentialConfigured;

    public LlmService(PetController pet, SettingsStore settings)
    {
        _pet = pet;
        _settings = settings;
    }

    /// <summary>从设置 + DPAPI 凭据组装当前连接配置；Key 本体不进入设置文件。</summary>
    private LlmConnectionConfig ConfigFromSettings(string apiKey) => new()
    {
        BaseUrl = _settings.LlmBaseUrl,
        ApiKey = apiKey,
        Model = _settings.LlmModel,
        ApiFormat = _settings.LlmApiFormat == "anthropic" ? LlmApiFormat.Anthropic : LlmApiFormat.OpenAi,
    };

    private string PersonaName => PetAppearanceCatalog.DefinitionFor(_pet.PreferredAppearance).PersonaName;

    public void Configure()
    {
        if (_pet.IsPlayMode || RequestRunning) return;
        string? existingToken = null;
        try
        {
            existingToken = _credentials.Load();
            _settings.LlmCredentialConfigured = existingToken != null;
        }
        catch (Exception)
        {
            // 凭据损坏（换机器/重装系统后 DPAPI 无法解密）：按未配置处理，引导重新输入。
            existingToken = null;
            _settings.LlmCredentialConfigured = false;
        }

        var dialog = new LlmSettingsDialog(
            hasSavedToken: existingToken != null,
            baseUrl: _settings.LlmBaseUrl,
            apiFormat: _settings.LlmApiFormat == "anthropic" ? LlmApiFormat.Anthropic : LlmApiFormat.OpenAi,
            currentModel: _settings.LlmModel);
        if (dialog.ShowDialog() != true) return;
        if (dialog.DisconnectRequested)
        {
            Disconnect();
            return;
        }

        var config = new LlmConnectionConfig
        {
            BaseUrl = LlmConnectionConfig.NormalizeBaseUrl(dialog.BaseUrl),
            ApiKey = "",
            Model = dialog.Model,
            ApiFormat = dialog.ApiFormat,
        };
        try
        {
            config.Validate();
        }
        catch (Exception error)
        {
            Ui.Pixel.PixelDialog.ShowMessage("无法保存 LLM 设置", error.Message);
            return;
        }
        try
        {
            if (dialog.ImportedConfig is { } imported)
            {
                if (dialog.NewToken is { } importedToken)
                {
                    _credentials.Save(importedToken);
                    _settings.LlmCredentialConfigured = true;
                }
                else if (existingToken == null && imported.ApiKey.Length > 0)
                {
                    // 导入文件携带 Key 且本地没有凭据时才落盘；否则保持原凭据。
                    _credentials.Save(imported.ApiKey);
                    _settings.LlmCredentialConfigured = true;
                }
            }
            else if (dialog.NewToken is { } newToken)
            {
                _credentials.Save(newToken);
                _settings.LlmCredentialConfigured = true;
            }
            else if (existingToken == null)
            {
                Ui.Pixel.PixelDialog.ShowMessage("无法保存 LLM 设置", "API Key 不能为空（本地服务可留空 Key，填写任意占位符即可）。");
                return;
            }
            _settings.LlmBaseUrl = config.BaseUrl;
            _settings.LlmApiFormat = config.ApiFormat == LlmApiFormat.Anthropic ? "anthropic" : "openai";
            _settings.LlmModel = config.Model[..Math.Min(config.Model.Length, 100)];
            _pet.ShowSpeech("LLM 设置已保存。只有主动提问才会联网。");
        }
        catch (Exception error)
        {
            Ui.Pixel.PixelDialog.ShowMessage("无法保存 LLM 设置", error.Message);
        }
    }

    public async void Ask()
    {
        if (_pet.IsPlayMode || RequestRunning) return;
        string token;
        try
        {
            token = _credentials.Load() ?? "";
            if (token.Length == 0)
            {
                _settings.LlmCredentialConfigured = false;
                Configure();
                return;
            }
            _settings.LlmCredentialConfigured = true;
        }
        catch (Exception)
        {
            // 凭据损坏：按未配置处理并引导重新设置。
            _settings.LlmCredentialConfigured = false;
            Configure();
            return;
        }

        var config = ConfigFromSettings(token);
        var personaName = PersonaName;
        var input = TextInputDialog.Prompt(
            $"问 {personaName}（LLM）",
            $"下面的文字只会发送到你配置的服务（{config.DescribeEndpoint()}）；不会附带 Todo、Notion 内容、文件或历史对话。",
            "输入一个问题（最多 500 字）",
            "发送");
        var trimmed = input?.Trim() ?? "";
        if (input == null) return;
        if (trimmed.Length == 0)
        {
            _pet.ShowSpeech("先写点什么再问我吧。");
            return;
        }
        var boundedInput = trimmed[..Math.Min(trimmed.Length, 500)];
        _pet.Observe();
        _pet.ShowSpeech("让我想想…");

        _requestCts = new CancellationTokenSource();
        try
        {
            var answer = await _client.RespondAsync(
                config,
                PetPersona.SystemPrompt(_pet.PreferredAppearance),
                boundedInput,
                _requestCts.Token);
            _requestCts.Dispose();
            _requestCts = null;
            _pet.ThumbsUp();
            _pet.ShowSpeech(answer);
        }
        catch (OperationCanceledException)
        {
            _requestCts?.Dispose();
            _requestCts = null;
            _pet.ShowSpeech("LLM 请求已取消。");
        }
        catch (Exception error)
        {
            _requestCts?.Dispose();
            _requestCts = null;
            _pet.ShowSpeech($"LLM 请求失败：{error.Message}");
        }
    }

    public void Disconnect()
    {
        if (RequestRunning) return;
        try
        {
            _credentials.Delete();
            _settings.LlmCredentialConfigured = false;
            _pet.ShowSpeech("LLM 已断开，本地功能不受影响。");
        }
        catch (Exception error)
        {
            Ui.Pixel.PixelDialog.ShowMessage("无法断开 LLM", error.Message);
        }
    }

    public void CancelRequest() => _requestCts?.Cancel();
}
