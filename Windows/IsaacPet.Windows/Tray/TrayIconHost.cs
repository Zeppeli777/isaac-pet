using System.Drawing;
using System.IO;
using System.Windows.Forms;
using IsaacPet.Windows.Core;
using IsaacPet.Windows.Pet;

namespace IsaacPet.Windows.Tray;

/// <summary>
/// 托盘图标 + 右键菜单，对应 macOS 版的 NSStatusItem + NSMenu。
/// 同一个菜单同时用于托盘图标和桌宠右键。
/// </summary>
public sealed class TrayIconHost : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly ContextMenuStrip _menu;
    private readonly PetController _controller;

    // 菜单项引用，用于 Opening 时刷新状态（对应 menuWillOpen）
    private ToolStripMenuItem _playModeItem = null!;
    private ToolStripMenuItem _roamingItem = null!;
    private ToolStripMenuItem _todoRoot = null!;
    private ToolStripMenuItem _llmAskItem = null!;
    private ToolStripMenuItem _llmSettingsItem = null!;
    private ToolStripMenuItem _llmDisconnectItem = null!;
    private ToolStripMenuItem _llmCancelItem = null!;
    private ToolStripMenuItem _launchAtLoginItem = null!;
    private readonly List<(ToolStripMenuItem Item, double Scale)> _scaleItems = [];
    private readonly List<(ToolStripMenuItem Item, PetAppearanceID Appearance)> _appearanceItems = [];
    private readonly List<ToolStripItem> _playModeDisabledItems = [];
    private ToolStripMenuItem _nextTodoItem = null!;

    public TrayIconHost(
        PetController controller,
        Action showTodoWindow,
        Action addTodo,
        Action showNextTodo,
        Action configureLlm,
        Action askLlm,
        Action disconnectLlm,
        Action cancelLlmRequest,
        Func<bool> llmRequestRunning,
        Func<bool> llmCredentialConfigured,
        Action quit)
    {
        _controller = controller;

        _menu = new ContextMenuStrip();
        _playModeItem = Add("进入游玩模式", () => { controller.TogglePlayMode(); UpdateStates(); });
        _menu.Items.Add(new ToolStripSeparator());
        Add("随机说一句", controller.SayRandomPhrase, disableInPlayMode: true);
        Add("表个情", controller.ShowRandomExpression, disableInPlayMode: true);
        Add("自定义气泡…", () =>
        {
            if (controller.IsPlayMode) return;
            var text = Ui.TextInputDialog.Prompt("让 Isaac 说什么？", "内容只会显示在本机桌面，不会上传。", "输入文字或颜文字（最多 80 字）", "显示气泡");
            if (text != null) controller.ShowCustomSpeech(text);
        }, disableInPlayMode: true);

        _llmAskItem = Add("问 Isaac（LLM）…", askLlm, disableInPlayMode: true);
        _llmSettingsItem = Add("LLM 设置…", configureLlm, disableInPlayMode: true);
        _llmDisconnectItem = Add("断开 LLM", disconnectLlm, disableInPlayMode: true);
        _llmCancelItem = Add("取消 LLM 请求", cancelLlmRequest, disableInPlayMode: true);
        _menu.Items.Add(new ToolStripSeparator());

        _todoRoot = new ToolStripMenuItem("Todo");
        AddTo(_todoRoot, "新建 Todo…", addTodo, disableInPlayMode: true);
        AddTo(_todoRoot, "查看 Todo…", showTodoWindow, disableInPlayMode: true);
        _nextTodoItem = AddTo(_todoRoot, "显示下一个 Todo", showNextTodo, disableInPlayMode: true);
        _menu.Items.Add(_todoRoot);
        _menu.Items.Add(new ToolStripSeparator());

        var appearanceMenu = new ToolStripMenuItem("桌宠形象");
        foreach (var definition in PetAppearanceCatalog.Definitions)
        {
            var id = definition.Id;
            var item = new ToolStripMenuItem(definition.DisplayName, null, (_, _) => controller.ActivateAppearance(id));
            _appearanceItems.Add((item, id));
            appearanceMenu.DropDownItems.Add(item);
            _playModeDisabledItems.Add(item);
        }
        _menu.Items.Add(appearanceMenu);
        _menu.Items.Add(new ToolStripSeparator());

        _roamingItem = Add("暂停走动", () => { controller.ToggleRoaming(); }, disableInPlayMode: true);
        _menu.Items.Add(new ToolStripSeparator());
        Add("招手", controller.Wave, disableInPlayMode: true);
        Add("跳一下", controller.Jump, disableInPlayMode: true);
        Add("哭一下", controller.Cry, disableInPlayMode: true);
        Add("赞一个", controller.ThumbsUp, disableInPlayMode: true);
        Add("观察一下", controller.Observe, disableInPlayMode: true);
        _menu.Items.Add(new ToolStripSeparator());

        var sizeMenu = new ToolStripMenuItem("大小");
        foreach (var (title, scale) in new (string, double)[] { ("75%", 0.75), ("100%", 1.0), ("125%", 1.25) })
        {
            var value = scale;
            var item = new ToolStripMenuItem(title, null, (_, _) => controller.ChangeScale(value));
            _scaleItems.Add((item, scale));
            sizeMenu.DropDownItems.Add(item);
        }
        _menu.Items.Add(sizeMenu);

        _launchAtLoginItem = Add("登录时启动", () =>
        {
            try { controller.ToggleLaunchAtLogin(); }
            catch (Exception error)
            {
                MessageBox.Show(error.Message, "无法更改登录启动设置", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        });
        Add("回到主屏幕", controller.ReturnToMainScreen);
        _menu.Items.Add(new ToolStripSeparator());
        Add("退出 Isaac Pet", quit);

        _menu.Opening += (_, _) => UpdateStates();

        _notifyIcon = new NotifyIcon
        {
            Text = "Isaac Pet",
            Visible = true,
            ContextMenuStrip = _menu,
        };
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "IsaacPet.ico");
        _notifyIcon.Icon = File.Exists(iconPath)
            ? new Icon(iconPath)
            : SystemIcons.Application;

        controller.ContextMenuRequested += () =>
        {
            UpdateStates();
            // 在鼠标位置弹出（桌宠右键）。
            _menu.Show(Cursor.Position);
        };
        controller.DueTodosDelivered += items =>
        {
            var text = items.Count == 1 ? $"提醒：{items[0].Title}" : $"有 {items.Count} 个 Todo 到时间了！";
            try { _notifyIcon.ShowBalloonTip(3000, "Isaac Pet", text, ToolTipIcon.Info); }
            catch { /* 通知区域不可用时忽略，桌面气泡仍然有效 */ }
        };
        controller.TodosChanged += UpdateStates;

        // LLM 状态回调
        _llmRequestRunning = llmRequestRunning;
        _llmCredentialConfigured = llmCredentialConfigured;
    }

    private readonly Func<bool> _llmRequestRunning;
    private readonly Func<bool> _llmCredentialConfigured;

    private ToolStripMenuItem Add(string title, Action action, bool disableInPlayMode = false)
    {
        var item = new ToolStripMenuItem(title, null, (_, _) => action());
        _menu.Items.Add(item);
        if (disableInPlayMode) _playModeDisabledItems.Add(item);
        return item;
    }

    private ToolStripMenuItem AddTo(ToolStripMenuItem parent, string title, Action action, bool disableInPlayMode = false)
    {
        var item = new ToolStripMenuItem(title, null, (_, _) => action());
        parent.DropDownItems.Add(item);
        if (disableInPlayMode) _playModeDisabledItems.Add(item);
        return item;
    }

    public void UpdateStates()
    {
        var inPlay = _controller.IsPlayMode;
        _playModeItem.Text = inPlay ? "退出游玩模式（Esc）" : "进入游玩模式";
        _roamingItem.Text = _controller.CurrentSettings.RoamingEnabled ? "暂停走动" : "继续走动";
        foreach (var item in _playModeDisabledItems) item.Enabled = !inPlay;

        var pendingCount = TodoPolicy.Pending(_controller.TodoStore.Items).Count;
        _todoRoot.Text = pendingCount == 0 ? "Todo" : $"Todo（{pendingCount}）";
        _nextTodoItem.Enabled = !inPlay && pendingCount > 0;

        var llmRunning = _llmRequestRunning();
        _llmAskItem.Enabled = !inPlay && !llmRunning;
        _llmSettingsItem.Enabled = !inPlay && !llmRunning;
        _llmDisconnectItem.Enabled = !inPlay && _llmCredentialConfigured();
        _llmCancelItem.Enabled = !inPlay && llmRunning;

        _launchAtLoginItem.Checked = Platform.StartupRegistration.IsEnabled;

        foreach (var (item, scale) in _scaleItems)
        {
            item.Checked = Math.Abs(scale - _controller.CurrentSettings.Scale) < 0.01;
        }
        foreach (var (item, appearance) in _appearanceItems)
        {
            item.Checked = appearance == _controller.PreferredAppearance;
            var availability = PetAppearanceCatalog.Availability(appearance);
            item.Enabled = !inPlay && availability.IsAvailable;
            if (!item.Enabled && !availability.IsAvailable)
            {
                item.ToolTipText = availability.UnavailableReason;
            }
        }
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _menu.Dispose();
    }
}
