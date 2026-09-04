using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using IsaacPet.Windows.Core;
using CheckBox = System.Windows.Controls.CheckBox;
using Button = System.Windows.Controls.Button;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;
using TextBox = System.Windows.Controls.TextBox;

namespace IsaacPet.Windows.Ui;

/// <summary>
/// 本地 Todo 窗口：新增（可带提醒时间）、完成/恢复、删除。
/// 数据只保存在 %APPDATA%\Isaac Pet\todos-v1.json。
/// </summary>
public sealed class TodoWindow : Window
{
    private readonly TodoStore _store;
    private readonly Action _onChanged;
    private readonly StackPanel _listPanel;
    private readonly TextBox _titleBox;
    private readonly DatePicker _dueDatePicker;
    private readonly TextBox _dueTimeBox;
    private readonly CheckBox _dueEnabled;

    public TodoWindow(TodoStore store, Action onChanged)
    {
        _store = store;
        _onChanged = onChanged;

        Title = "Isaac Pet · Todo";
        Width = 460;
        Height = 520;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Topmost = true;

        var root = new DockPanel { Margin = new Thickness(12) };

        // 顶部新建区
        var composer = new StackPanel { Margin = new Thickness(0, 0, 0, 10) };
        DockPanel.SetDock(composer, Dock.Top);
        _titleBox = new TextBox { Margin = new Thickness(0, 0, 0, 6) };
        _titleBox.SetValue(ToolTipService.ToolTipProperty, "要做什么？（最多 120 字）");
        composer.Children.Add(_titleBox);

        var dueRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 6) };
        _dueEnabled = new CheckBox { Content = "提醒时间", VerticalAlignment = VerticalAlignment.Center };
        _dueDatePicker = new DatePicker { Margin = new Thickness(8, 0, 0, 0), Width = 130, IsEnabled = false };
        _dueTimeBox = new TextBox { Text = "18:00", Width = 60, Margin = new Thickness(8, 0, 0, 0), IsEnabled = false };
        _dueEnabled.Checked += (_, _) => { _dueDatePicker.IsEnabled = true; _dueTimeBox.IsEnabled = true; };
        _dueEnabled.Unchecked += (_, _) => { _dueDatePicker.IsEnabled = false; _dueTimeBox.IsEnabled = false; };
        dueRow.Children.Add(_dueEnabled);
        dueRow.Children.Add(_dueDatePicker);
        dueRow.Children.Add(_dueTimeBox);
        dueRow.Children.Add(new TextBlock { Text = "（HH:mm）", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 0, 0), Opacity = 0.6 });
        composer.Children.Add(dueRow);

        var addButton = new Button { Content = "添加 Todo", HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(12, 4, 12, 4) };
        addButton.Click += (_, _) => AddFromComposer();
        composer.Children.Add(addButton);
        root.Children.Add(composer);

        // 列表
        var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        _listPanel = new StackPanel();
        scroll.Content = _listPanel;
        root.Children.Add(scroll);

        Content = root;
        Reload();
    }

    public void Present(bool focusComposer = false)
    {
        Reload();
        Show();
        Activate();
        if (focusComposer) _titleBox.Focus();
    }

    public void Reload()
    {
        _listPanel.Children.Clear();
        foreach (var item in _store.Items)
        {
            _listPanel.Children.Add(BuildRow(item));
        }
        if (_listPanel.Children.Count == 0)
        {
            _listPanel.Children.Add(new TextBlock { Text = "还没有 Todo。让 Isaac 轻松一下 :)", Opacity = 0.6, Margin = new Thickness(4) });
        }
    }

    private UIElement BuildRow(TodoItem item)
    {
        var row = new DockPanel { Margin = new Thickness(0, 3, 0, 3) };

        var deleteButton = new Button { Content = "删除", Padding = new Thickness(8, 1, 8, 1) };
        DockPanel.SetDock(deleteButton, Dock.Right);
        var captured = item.Id;
        deleteButton.Click += (_, _) =>
        {
            _store.Remove(captured);
            _onChanged();
            Reload();
        };
        row.Children.Add(deleteButton);

        var checkbox = new CheckBox { IsChecked = item.IsCompleted, VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(checkbox, Dock.Left);
        checkbox.Click += (_, _) =>
        {
            _store.ToggleCompleted(captured);
            _onChanged();
            Reload();
        };
        row.Children.Add(checkbox);

        var text = new StackPanel { Margin = new Thickness(6, 0, 6, 0) };
        var title = new TextBlock
        {
            Text = item.Title,
            TextWrapping = TextWrapping.Wrap,
            Opacity = item.IsCompleted ? 0.45 : 1,
        };
        if (item.IsCompleted)
        {
            title.TextDecorations = TextDecorations.Strikethrough;
        }
        text.Children.Add(title);
        var due = DueText(item);
        if (due.Length > 0)
        {
            text.Children.Add(new TextBlock { Text = due, FontSize = 11, Opacity = 0.6 });
        }
        row.Children.Add(text);
        return row;
    }

    public static string DueText(TodoItem item)
    {
        if (item.DueAt is not { } due) return "";
        var local = due.LocalDateTime;
        var now = DateTime.Now;
        var prefix = local.Date == now.Date ? "今天"
            : local.Date == now.Date.AddDays(1) ? "明天"
            : local.ToString("M月d日", CultureInfo.GetCultureInfo("zh-CN"));
        return $"截止 {prefix} {local:HH:mm}";
    }

    private void AddFromComposer()
    {
        DateTimeOffset? dueAt = null;
        if (_dueEnabled.IsChecked == true)
        {
            var date = _dueDatePicker.SelectedDate ?? DateTime.Today;
            if (!TimeSpan.TryParse(_dueTimeBox.Text.Trim(), CultureInfo.InvariantCulture, out var time))
            {
                System.Windows.MessageBox.Show(this, "提醒时间格式应为 HH:mm，例如 18:00。", "Isaac Pet", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            dueAt = new DateTimeOffset(date.Date + time, DateTimeOffset.Now.Offset);
        }
        try
        {
            _store.Add(_titleBox.Text, dueAt);
        }
        catch (InvalidOperationException error)
        {
            System.Windows.MessageBox.Show(this, error.Message, "Isaac Pet", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        _titleBox.Clear();
        _onChanged();
        Reload();
    }
}
