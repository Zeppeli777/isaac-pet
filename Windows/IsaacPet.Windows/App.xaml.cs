using System.IO;
using System.Windows;
using IsaacPet.Windows.Core;
using IsaacPet.Windows.Llm;
using IsaacPet.Windows.Pet;
using IsaacPet.Windows.Settings;
using IsaacPet.Windows.Tray;
using IsaacPet.Windows.Ui;

namespace IsaacPet.Windows;

public partial class App : System.Windows.Application
{
    private PetController? _pet;
    private TrayIconHost? _tray;
    private TodoWindow? _todoWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += (_, args) =>
        {
            LogFatal("DispatcherUnhandledException", args.Exception);
            args.Handled = true;
        };

        try
        {
            StartupCore(e);
        }
        catch (Exception error)
        {
            LogFatal("OnStartup", error);
            System.Windows.MessageBox.Show(
                error.Message,
                "Isaac Pet 遇到问题",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    private static void LogFatal(string phase, Exception error)
    {
        try
        {
            Directory.CreateDirectory(AppPaths.DataDirectory);
            File.AppendAllText(
                Path.Combine(AppPaths.DataDirectory, "startup-error.log"),
                $"[{DateTime.Now:O}] {phase}: {error}\n\n");
        }
        catch { /* 日志失败不影响退出 */ }
    }

    private void StartupCore(StartupEventArgs e)
    {
        if (e.Args.Contains("--self-check"))
        {
            var exitCode = SelfCheck.Run();
            Shutdown(exitCode);
            return;
        }

        var settingsStore = new SettingsStore();
        try
        {
            _pet = new PetController(settingsStore);
        }
        catch (Exception error)
        {
            LogFatal("PetController", error);
            System.Windows.MessageBox.Show(
                error.Message,
                "Isaac Pet 遇到问题",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Shutdown(1);
            return;
        }

        var llm = new LlmService(_pet, settingsStore);
        _tray = new TrayIconHost(
            _pet,
            showTodoWindow: () => ShowTodoWindow(focusComposer: false),
            addTodo: () => ShowTodoWindow(focusComposer: true),
            showNextTodo: ShowNextTodo,
            configureLlm: llm.Configure,
            askLlm: llm.Ask,
            disconnectLlm: llm.Disconnect,
            cancelLlmRequest: llm.CancelRequest,
            llmRequestRunning: () => llm.RequestRunning,
            llmCredentialConfigured: () => llm.CredentialConfigured,
            quit: Quit);

        if (e.Args.Contains("--show-todos"))
        {
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
            timer.Tick += (_, _) =>
            {
                timer.Stop();
                ShowTodoWindow(focusComposer: false);
            };
            timer.Start();
        }
    }

    private void ShowTodoWindow(bool focusComposer)
    {
        if (_pet == null || _pet.IsPlayMode) return;
        _todoWindow ??= new TodoWindow(_pet.TodoStore, () => _pet.NotifyTodosChanged());
        _todoWindow.Present(focusComposer);
    }

    private void ShowNextTodo()
    {
        if (_pet == null || _pet.IsPlayMode) return;
        var todo = TodoPolicy.NextPending(_pet.TodoStore.Items);
        if (todo == null)
        {
            _pet.ShowSpeech("Todo 已清空！ :)");
            return;
        }
        var dueText = todo.DueAt == null ? "" : $" · {TodoWindow.DueText(todo)}";
        _pet.Observe();
        _pet.ShowSpeech($"下一项：{todo.Title}{dueText}");
    }

    private void Quit()
    {
        _pet?.Stop();
        _tray?.Dispose();
        Shutdown();
    }
}
