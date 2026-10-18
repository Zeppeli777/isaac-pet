using System.Windows;
using System.Windows.Controls;
using IsaacPet.Windows.Llm;
using IsaacPet.Windows.Ui.Pixel;
using Button = System.Windows.Controls.Button;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;
using TextBox = System.Windows.Controls.TextBox;

namespace IsaacPet.Windows.Ui;

/// <summary>像素风模态文本输入框，对应 macOS 版 PixelDialog.prompt。</summary>
public sealed class TextInputDialog : PixelWindow
{
    private readonly TextBox _input;

    public string? Result { get; private set; }

    public TextInputDialog(string title, string message, string placeholder, string confirmTitle = "确定")
        : base(title, resizable: false)
    {
        Width = 460;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;

        var root = new StackPanel();
        root.Children.Add(new TextBlock
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 10),
        });

        _input = PixelStyle.CreateField(placeholder);
        _input.Margin = new Thickness(0, 0, 0, 12);
        root.Children.Add(_input);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        var confirmButton = new PixelButton { Content = confirmTitle, IsDefault = true, Margin = new Thickness(0, 0, 8, 0) };
        var cancelButton = new PixelButton { Content = "取消", IsCancel = true };
        confirmButton.Click += (_, _) => { Result = _input.Text; DialogResult = true; };
        buttons.Children.Add(confirmButton);
        buttons.Children.Add(cancelButton);
        root.Children.Add(buttons);

        SetContent(root);
        Loaded += (_, _) => _input.Focus();
    }

    /// <summary>显示对话框；用户确认时返回文本（可能为空），取消返回 null。</summary>
    public static string? Prompt(string title, string message, string placeholder, string confirmTitle = "确定")
    {
        var dialog = new TextInputDialog(title, message, placeholder, confirmTitle);
        return dialog.ShowDialog() == true ? dialog.Result : null;
    }
}

/// <summary>像素风 LLM 设置窗口：服务格式、Base URL、API Key（DPAPI 密文存储）、模型和导入配置文件。</summary>
public sealed class LlmSettingsDialog : PixelWindow
{
    private sealed record ProviderPreset(string Label, string BaseUrl, LlmApiFormat Format, string SuggestedModel);

    /// <summary>常见 OpenAI / Anthropic 兼容服务商预设（借鉴 magpie 的 provider 预设）：一键填写 Base URL 与格式。</summary>
    private static readonly ProviderPreset[] Presets =
    {
        new("StepFun 阶跃星辰", "https://api.stepfun.com/v1", LlmApiFormat.OpenAi, "step-2-16k"),
        new("DeepSeek", "https://api.deepseek.com", LlmApiFormat.OpenAi, "deepseek-chat"),
        new("Moonshot Kimi", "https://api.moonshot.cn/v1", LlmApiFormat.OpenAi, "kimi-k2-0905-preview"),
        new("智谱 GLM", "https://open.bigmodel.cn/api/paas/v4", LlmApiFormat.OpenAi, "glm-4.6"),
        new("SiliconFlow 硅基流动", "https://api.siliconflow.cn/v1", LlmApiFormat.OpenAi, ""),
        new("OpenRouter", "https://openrouter.ai/api/v1", LlmApiFormat.OpenAi, ""),
        new("OpenAI", "https://api.openai.com/v1", LlmApiFormat.OpenAi, "gpt-5-mini"),
        new("Anthropic", "https://api.anthropic.com", LlmApiFormat.Anthropic, "claude-sonnet-4-5"),
        new("Ollama（本机）", "http://localhost:11434/v1", LlmApiFormat.OpenAi, ""),
        new("LM Studio（本机）", "http://localhost:1234/v1", LlmApiFormat.OpenAi, ""),
    };

    private readonly System.Windows.Controls.PasswordBox _tokenBox;
    private readonly TextBox _baseURLBox;
    private readonly TextBox _modelBox;
    private readonly System.Windows.Controls.ComboBox _formatBox;
    private readonly System.Windows.Controls.ComboBox _presetBox;
    private readonly PixelButton _testButton;
    private readonly PixelButton _fetchButton;
    private readonly string? _savedToken;
    private bool _applyingPreset;
    private LlmConnectionConfig? _importedConfig;

    public bool DisconnectRequested { get; private set; }
    public string? NewToken => string.IsNullOrWhiteSpace(_tokenBox.Password) ? null : _tokenBox.Password.Trim();
    public string BaseUrl => _baseURLBox.Text.Trim();
    public string Model => _modelBox.Text.Trim();
    public LlmApiFormat ApiFormat => _formatBox.SelectedIndex == 1 ? LlmApiFormat.Anthropic : LlmApiFormat.OpenAi;
    /// <summary>用户点了「导入配置文件…」时解析出的配置（含文件内的 API Key）。</summary>
    public LlmConnectionConfig? ImportedConfig => _importedConfig;

    /// <summary>返回 true 表示用户点了“保存”，false 表示取消；断开通过 DisconnectRequested 区分。</summary>
    public bool Saved { get; private set; }

    public LlmSettingsDialog(bool hasSavedToken, string? savedToken, string baseUrl, LlmApiFormat apiFormat, string currentModel)
        : base("可选 LLM 连接", resizable: false)
    {
        Width = 560;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        _savedToken = string.IsNullOrWhiteSpace(savedToken) ? null : savedToken.Trim();

        var root = new StackPanel();
        root.Children.Add(new TextBlock
        {
            Text = "默认关闭。API Key 仅通过 Windows DPAPI 加密后保存在本机；只有你主动点击「问桌宠（LLM）」时，输入文字才会发送到上面配置的服务。不会发送 Todo、Notion 内容或桌面数据。",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 12),
        });

        root.Children.Add(new TextBlock { Text = "服务商预设" });
        var presetLabels = new List<string> { "选择预设自动填写…" };
        foreach (var preset in Presets) presetLabels.Add(preset.Label);
        _presetBox = new System.Windows.Controls.ComboBox
        {
            ItemsSource = presetLabels.ToArray(),
            SelectedIndex = Math.Max(Array.FindIndex(Presets, preset => baseUrl.Contains(preset.BaseUrl, StringComparison.OrdinalIgnoreCase)) + 1, 0),
            Margin = new Thickness(0, 2, 0, 10),
            Width = 240,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        root.Children.Add(_presetBox);

        root.Children.Add(new TextBlock { Text = "服务格式" });
        _formatBox = new System.Windows.Controls.ComboBox
        {
            ItemsSource = new[] { "OpenAI 兼容", "Anthropic 兼容" },
            SelectedIndex = apiFormat == LlmApiFormat.Anthropic ? 1 : 0,
            Margin = new Thickness(0, 2, 0, 10),
            Width = 180,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        root.Children.Add(_formatBox);

        var baseURLRow = new DockPanel();
        var baseURLButtons = new StackPanel { Orientation = Orientation.Horizontal };
        _testButton = new PixelButton { Content = "测试连接", Margin = new Thickness(0, 0, 8, 0) };
        _testButton.Click += (_, _) => TestConnection();
        var importButton = new PixelButton { Content = "导入配置文件…" };
        importButton.Click += (_, _) => ImportConfigFile();
        baseURLButtons.Children.Add(_testButton);
        baseURLButtons.Children.Add(importButton);
        DockPanel.SetDock(baseURLButtons, Dock.Right);
        baseURLRow.Children.Add(baseURLButtons);
        var baseURLColumn = new StackPanel();
        baseURLColumn.Children.Add(new TextBlock { Text = "Base URL" });
        _baseURLBox = PixelStyle.CreateField("https://api.openai.com/v1");
        _baseURLBox.Text = baseUrl;
        _baseURLBox.Margin = new Thickness(0, 2, 8, 10);
        baseURLColumn.Children.Add(_baseURLBox);
        baseURLRow.Children.Add(baseURLColumn);
        root.Children.Add(baseURLRow);

        root.Children.Add(new TextBlock { Text = "API Key" });
        _tokenBox = new System.Windows.Controls.PasswordBox { Margin = new Thickness(0, 2, 0, 10) };
        _tokenBox.ToolTip = hasSavedToken ? "已保存在本机（留空保持不变）" : "sk-…（本地服务可留空）";
        root.Children.Add(_tokenBox);

        root.Children.Add(new TextBlock { Text = "模型" });
        var modelRow = new DockPanel { Margin = new Thickness(0, 2, 0, 6) };
        _fetchButton = new PixelButton { Content = "拉取模型…" };
        _fetchButton.Click += (_, _) => FetchModels();
        DockPanel.SetDock(_fetchButton, Dock.Right);
        modelRow.Children.Add(_fetchButton);
        _modelBox = PixelStyle.CreateField("例如 gpt-5-mini、claude-sonnet-4-5");
        _modelBox.Text = currentModel;
        _modelBox.Width = 300;
        _modelBox.HorizontalAlignment = HorizontalAlignment.Left;
        modelRow.Children.Add(_modelBox);
        root.Children.Add(modelRow);

        root.Children.Add(new TextBlock
        {
            Text = "兼容推理模型（如 step-r1-v-mini、deepseek-reasoner）：输出预算被思考占满时会自动加大预算重试；思考过程不会显示在气泡里。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = PixelStyle.Brush(PixelStyle.DisabledTextColor),
            Margin = new Thickness(0, 0, 0, 12),
        });

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var saveButton = new PixelButton { Content = "保存", IsDefault = true, Margin = new Thickness(0, 0, 8, 0) };
        var disconnectButton = new PixelButton { Content = "断开", Margin = new Thickness(0, 0, 8, 0) };
        var cancelButton = new PixelButton { Content = "取消", IsCancel = true };
        saveButton.Click += (_, _) => { Saved = true; DialogResult = true; };
        disconnectButton.Click += (_, _) => { DisconnectRequested = true; DialogResult = true; };
        buttons.Children.Add(saveButton);
        buttons.Children.Add(disconnectButton);
        buttons.Children.Add(cancelButton);
        root.Children.Add(buttons);

        SetContent(root);

        // 手动改过 Base URL 就视作自定义，预设框回到占位项。
        _baseURLBox.TextChanged += (_, _) =>
        {
            if (_applyingPreset) return;
            if (_presetBox.SelectedIndex != 0) _presetBox.SelectedIndex = 0;
        };
        _presetBox.SelectionChanged += (_, _) =>
        {
            if (_applyingPreset) return;
            if (_presetBox.SelectedIndex <= 0 || _presetBox.SelectedIndex > Presets.Length) return;
            var preset = Presets[_presetBox.SelectedIndex - 1];
            _applyingPreset = true;
            _baseURLBox.Text = preset.BaseUrl;
            _formatBox.SelectedIndex = preset.Format == LlmApiFormat.Anthropic ? 1 : 0;
            if (_modelBox.Text.Trim().Length == 0 && preset.SuggestedModel.Length > 0)
            {
                _modelBox.Text = preset.SuggestedModel;
            }
            _applyingPreset = false;
        };
    }

    private void ImportConfigFile()
    {
        var picker = new Microsoft.Win32.OpenFileDialog
        {
            Title = "导入 LLM 配置文件",
            Filter = "JSON 配置|*.json|所有文件|*.*",
        };
        if (picker.ShowDialog(this) != true) return;
        try
        {
            var imported = LlmConnectionConfig.ParseImported(System.IO.File.ReadAllText(picker.FileName));
            _importedConfig = imported;
            if (imported.BaseUrl.Length > 0) _baseURLBox.Text = imported.BaseUrl;
            if (imported.Model.Length > 0) _modelBox.Text = imported.Model;
            _formatBox.SelectedIndex = imported.ApiFormat == LlmApiFormat.Anthropic ? 1 : 0;
            if (imported.ApiKey.Length > 0 && _tokenBox.Password.Length == 0)
            {
                _tokenBox.Password = imported.ApiKey;
            }
        }
        catch (Exception error)
        {
            PixelDialog.ShowMessage("无法导入配置文件", error.Message);
        }
    }

    /// <summary>按当前窗口内容组装探测用配置：新输入的 Key 优先，否则用已保存的 Key（仅内存中使用）。</summary>
    private LlmConnectionConfig? ProbeConfig()
    {
        var config = new LlmConnectionConfig
        {
            BaseUrl = LlmConnectionConfig.NormalizeBaseUrl(_baseURLBox.Text),
            ApiKey = NewToken ?? _savedToken ?? "",
            Model = _modelBox.Text.Trim(),
            ApiFormat = ApiFormat,
        };
        return config.EndpointUrl() == null ? null : config;
    }

    private async void TestConnection()
    {
        var config = ProbeConfig();
        if (config == null)
        {
            PixelDialog.ShowMessage("无法测试连接", "请先填写有效的 Base URL（以 http:// 或 https:// 开头）。");
            return;
        }
        _testButton.IsEnabled = false;
        try
        {
            var result = await new LlmHttpClient().TestConnectionAsync(config, CancellationToken.None);
            if (!IsVisible) return; // 等待期间用户关掉了设置窗口：不必再弹结论
            PixelDialog.ShowMessage(result.Ok ? "连接正常" : "连接失败", result.Message);
        }
        catch (Exception error)
        {
            PixelDialog.ShowMessage("连接失败", error.Message);
        }
        finally
        {
            _testButton.IsEnabled = true;
        }
    }

    private async void FetchModels()
    {
        var config = ProbeConfig();
        if (config == null)
        {
            PixelDialog.ShowMessage("无法拉取模型", "请先填写有效的 Base URL（以 http:// 或 https:// 开头）。");
            return;
        }
        _fetchButton.IsEnabled = false;
        try
        {
            var models = await new LlmHttpClient().ListModelsAsync(config, CancellationToken.None);
            if (!IsVisible) return; // 等待期间用户关掉了设置窗口
            if (models.Count == 0)
            {
                PixelDialog.ShowMessage("模型列表", "服务返回了空的模型列表。");
                return;
            }
            var picker = new ModelPickerDialog(models) { Owner = this };
            if (picker.ShowDialog() == true && picker.SelectedModel is { } selected)
            {
                _modelBox.Text = selected;
            }
        }
        catch (Exception error)
        {
            PixelDialog.ShowMessage("拉取模型失败", error.Message);
        }
        finally
        {
            _fetchButton.IsEnabled = true;
        }
    }
}

/// <summary>像素风模型选择框：从服务端拉取到的模型列表里选一个，回填到设置窗口的「模型」输入框。</summary>
public sealed class ModelPickerDialog : PixelWindow
{
    private readonly System.Windows.Controls.ListBox _list;

    public string? SelectedModel { get; private set; }

    public ModelPickerDialog(IReadOnlyList<string> models)
        : base("选择模型", resizable: false)
    {
        Width = 400;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;

        var root = new StackPanel();
        root.Children.Add(new TextBlock
        {
            Text = "服务端返回了以下模型，选中后回填到「模型」输入框：",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 10),
        });

        _list = new System.Windows.Controls.ListBox
        {
            ItemsSource = models,
            MaxHeight = 320,
            FontFamily = PixelFont.Family,
            FontSize = 12,
        };
        _list.MouseDoubleClick += (_, _) => Confirm();
        root.Children.Add(_list);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var confirmButton = new PixelButton { Content = "确定", IsDefault = true, Margin = new Thickness(0, 0, 8, 0) };
        var cancelButton = new PixelButton { Content = "取消", IsCancel = true };
        confirmButton.Click += (_, _) => Confirm();
        buttons.Children.Add(confirmButton);
        buttons.Children.Add(cancelButton);
        root.Children.Add(buttons);

        SetContent(root);
    }

    private void Confirm()
    {
        if (_list.SelectedItem is string selected)
        {
            SelectedModel = selected;
            DialogResult = true;
        }
    }
}
