using IsaacPet.Windows.Core;
using IsaacPet.Windows.Platform;
using IsaacPet.Windows.Pet;
using IsaacPet.Windows.Settings;
using IsaacPet.Windows.Ui;

namespace IsaacPet.Windows.Llm;

/// <summary>
/// LLM 流程编排：设置、提问、断开、取消。
/// 行为与 macOS 版一致：默认关闭；Key 只存 DPAPI 密文；仅主动提问时联网。
/// </summary>
public sealed class LlmService
{
    private readonly PetController _pet;
    private readonly SettingsStore _settings;
    private readonly DpapiCredentialStore _credentials = new("llm-credential.bin");
    private readonly OpenAIResponsesClient _client = new();
    private CancellationTokenSource? _requestCts;

    public bool RequestRunning => _requestCts != null;
    public bool CredentialConfigured => _settings.LlmCredentialConfigured;

    public LlmService(PetController pet, SettingsStore settings)
    {
        _pet = pet;
        _settings = settings;
    }

    public void Configure()
    {
        if (_pet.IsPlayMode || RequestRunning) return;
        string? existingToken = null;
        try
        {
            existingToken = _credentials.Load();
            _settings.LlmCredentialConfigured = existingToken != null;
        }
        catch (Exception error)
        {
            System.Windows.MessageBox.Show(error.Message, "无法读取 LLM 设置");
            return;
        }

        var dialog = new LlmSettingsDialog(existingToken != null, _settings.LlmModel);
        if (dialog.ShowDialog() != true) return;
        if (dialog.DisconnectRequested)
        {
            Disconnect();
            return;
        }

        var model = dialog.Model;
        if (model.Length == 0 || model.Any(char.IsWhiteSpace))
        {
            System.Windows.MessageBox.Show("请输入一个不含空格的模型 ID。", "模型名称无效");
            return;
        }
        try
        {
            if (dialog.NewToken is { } newToken)
            {
                _credentials.Save(newToken);
                _settings.LlmCredentialConfigured = true;
            }
            else if (existingToken == null)
            {
                System.Windows.MessageBox.Show("API Key 不能为空。", "无法保存 LLM 设置");
                return;
            }
            _settings.LlmModel = model[..Math.Min(model.Length, 100)];
            _pet.ShowSpeech("LLM 设置已保存。只有主动提问才会联网。");
        }
        catch (Exception error)
        {
            System.Windows.MessageBox.Show(error.Message, "无法保存 LLM 设置");
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
        catch (Exception error)
        {
            System.Windows.MessageBox.Show(error.Message, "无法读取 API Key");
            return;
        }

        var input = TextInputDialog.Prompt(
            "问 Isaac",
            "下面的文字会发送到 api.openai.com；不会附带 Todo、Notion 内容、文件或历史对话。",
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
            var answer = await _client.RespondAsync(boundedInput, _settings.LlmModel, token, _requestCts.Token);
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
            System.Windows.MessageBox.Show(error.Message, "无法断开 LLM");
        }
    }

    public void CancelRequest() => _requestCts?.Cancel();
}
