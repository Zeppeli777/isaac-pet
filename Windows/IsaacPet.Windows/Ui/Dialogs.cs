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
    private readonly System.Windows.Controls.PasswordBox _tokenBox;
    private readonly TextBox _baseURLBox;
    private readonly TextBox _modelBox;
    private readonly System.Windows.Controls.ComboBox _formatBox;
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

    public LlmSettingsDialog(bool hasSavedToken, string baseUrl, LlmApiFormat apiFormat, string currentModel)
        : base("可选 LLM 连接", resizable: false)
    {
        Width = 560;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;

        var root = new StackPanel();
        root.Children.Add(new TextBlock
        {
            Text = "默认关闭。API Key 仅通过 Windows DPAPI 加密后保存在本机；只有你主动点击「问桌宠（LLM）」时，输入文字才会发送到上面配置的服务。不会发送 Todo、Notion 内容或桌面数据。",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 12),
        });

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
        var importButton = new PixelButton { Content = "导入配置文件…" };
        importButton.Click += (_, _) => ImportConfigFile();
        DockPanel.SetDock(importButton, Dock.Right);
        baseURLRow.Children.Add(importButton);
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
        _modelBox = PixelStyle.CreateField("例如 gpt-5-mini、claude-sonnet-4-5");
        _modelBox.Text = currentModel;
        _modelBox.Margin = new Thickness(0, 2, 0, 14);
        _modelBox.Width = 300;
        _modelBox.HorizontalAlignment = HorizontalAlignment.Left;
        root.Children.Add(_modelBox);

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
}
