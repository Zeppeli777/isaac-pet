using System.Windows;
using System.Windows.Controls;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;

namespace IsaacPet.Windows.Ui.Pixel;

/// <summary>
/// 模态游戏风对话框，替代系统 MessageBox（对应 macOS 版 PixelDialog）。
/// 所有对话框走 PixelWindow 壳；窗口以任意方式关闭都会结束 ShowDialog
/// 模态会话（WPF 原生行为），不会出现模态循环泄漏。
/// </summary>
public static class PixelDialog
{
    public static void ShowMessage(string title, string message, string buttonTitle = "知道了")
    {
        var window = new PixelWindow(title, resizable: false)
        {
            Width = 460,
            SizeToContent = SizeToContent.Height,
            ResizeMode = ResizeMode.NoResize,
        };
        var root = new StackPanel();
        root.Children.Add(new TextBlock
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 12),
        });
        var button = new PixelButton
        {
            Content = buttonTitle,
            IsDefault = true,
            IsCancel = true,
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        button.Click += (_, _) => window.Close();
        root.Children.Add(button);
        window.SetContent(root);
        window.ShowDialog();
    }

    /// <summary>确认对话框；危险操作时 Enter 落在安全选项上。</summary>
    public static bool Confirm(
        string title,
        string message,
        string confirmTitle,
        string cancelTitle = "取消",
        bool isDestructive = false)
    {
        var window = new PixelWindow(title, resizable: false)
        {
            Width = 460,
            SizeToContent = SizeToContent.Height,
            ResizeMode = ResizeMode.NoResize,
        };
        var confirmed = false;
        var root = new StackPanel();
        root.Children.Add(new TextBlock
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 12),
        });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var confirmButton = new PixelButton { Content = confirmTitle };
        var cancelButton = new PixelButton { Content = cancelTitle, IsCancel = true };
        // 危险确认时 Enter 落在安全的取消上（对应 NSAlert 的 warning 风格）。
        confirmButton.IsDefault = !isDestructive;
        cancelButton.IsDefault = isDestructive;
        confirmButton.Click += (_, _) => { confirmed = true; window.Close(); };
        cancelButton.Click += (_, _) => window.Close();
        buttons.Children.Add(confirmButton);
        buttons.Children.Add(cancelButton);
        root.Children.Add(buttons);
        window.SetContent(root);
        window.ShowDialog();
        return confirmed;
    }
}
