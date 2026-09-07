using System.Windows;
using System.Windows.Controls;
using Button = System.Windows.Controls.Button;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;
using TextBox = System.Windows.Controls.TextBox;

namespace IsaacPet.Windows.Ui;

/// <summary>简单的模态文本输入框，对应 macOS 版带 accessoryView 的 NSAlert。</summary>
public sealed class TextInputDialog : Window
{
    private readonly TextBox _input;
    private readonly Button _confirmButton;

    public string? Result { get; private set; }

    public TextInputDialog(string title, string message, string placeholder, string confirmTitle = "确定")
    {
        Title = title;
        Width = 420;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;

        var root = new StackPanel { Margin = new Thickness(16) };
        root.Children.Add(new TextBlock
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 10),
        });

        _input = new TextBox { Margin = new Thickness(0, 0, 0, 12) };
        _input.SetValue(System.Windows.Controls.ToolTipService.ToolTipProperty, placeholder);
        root.Children.Add(_input);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        _confirmButton = new Button { Content = confirmTitle, Width = 88, Margin = new Thickness(0, 0, 8, 0), IsDefault = true };
        var cancelButton = new Button { Content = "取消", Width = 88, IsCancel = true };
        _confirmButton.Click += (_, _) => { Result = _input.Text; DialogResult = true; };
        buttons.Children.Add(_confirmButton);
        buttons.Children.Add(cancelButton);
        root.Children.Add(buttons);

        Content = root;
        Loaded += (_, _) => _input.Focus();
    }

    /// <summary>显示对话框；用户确认时返回文本（可能为空），取消返回 null。</summary>
    public static string? Prompt(string title, string message, string placeholder, string confirmTitle = "确定")
    {
        var dialog = new TextInputDialog(title, message, placeholder, confirmTitle);
        return dialog.ShowDialog() == true ? dialog.Result : null;
    }
}

/// <summary>LLM 设置窗口：API Key（DPAPI 密文存储）+ 模型 ID。</summary>
public sealed class LlmSettingsDialog : Window
{
    private readonly System.Windows.Controls.PasswordBox _tokenBox;
    private readonly TextBox _modelBox;

    public bool DisconnectRequested { get; private set; }
    public string? NewToken => string.IsNullOrWhiteSpace(_tokenBox.Password) ? null : _tokenBox.Password.Trim();
    public string Model => _modelBox.Text.Trim();

    /// <summary>返回 true 表示用户点了“保存”，false 表示取消；断开通过 DisconnectRequested 区分。</summary>
    public bool Saved { get; private set; }

    public LlmSettingsDialog(bool hasSavedToken, string currentModel)
    {
        Title = "可选 LLM 连接";
        Width = 500;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;

        var root = new StackPanel { Margin = new Thickness(16) };
        root.Children.Add(new TextBlock
        {
            Text = "默认关闭。API Key 仅通过 Windows DPAPI 加密后保存在本机；只有你主动点击“问 Isaac”时，输入文字才会发送到 api.openai.com。不会发送 Todo、Notion 内容或桌面数据。",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 12),
        });

        root.Children.Add(new TextBlock { Text = "API Key" });
        _tokenBox = new System.Windows.Controls.PasswordBox { Margin = new Thickness(0, 2, 0, 10) };
        _tokenBox.SetValue(System.Windows.Controls.ToolTipService.ToolTipProperty,
            hasSavedToken ? "已保存在本机（留空保持不变）" : "sk-…");
        root.Children.Add(_tokenBox);

        root.Children.Add(new TextBlock { Text = "模型" });
        _modelBox = new TextBox { Text = currentModel, Margin = new Thickness(0, 2, 0, 14), Width = 260, HorizontalAlignment = HorizontalAlignment.Left };
        root.Children.Add(_modelBox);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var saveButton = new Button { Content = "保存", Width = 80, Margin = new Thickness(0, 0, 8, 0), IsDefault = true };
        var disconnectButton = new Button { Content = "断开", Width = 80, Margin = new Thickness(0, 0, 8, 0) };
        var cancelButton = new Button { Content = "取消", Width = 80, IsCancel = true };
        saveButton.Click += (_, _) => { Saved = true; DialogResult = true; };
        disconnectButton.Click += (_, _) => { DisconnectRequested = true; DialogResult = true; };
        buttons.Children.Add(saveButton);
        buttons.Children.Add(disconnectButton);
        buttons.Children.Add(cancelButton);
        root.Children.Add(buttons);

        Content = root;
    }
}
