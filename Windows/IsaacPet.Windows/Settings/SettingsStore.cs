using System.IO;
using System.Text.Json;
using IsaacPet.Windows.Core;

namespace IsaacPet.Windows.Settings;

/// <summary>
/// JSON 设置存储，对应 macOS 版的 UserDefaults。保存到 %APPDATA%\Isaac Pet\settings-v1.json。
/// </summary>
public sealed class SettingsStore
{
    private sealed class Persisted
    {
        public double Scale { get; set; } = 1.0;
        public bool Roaming { get; set; } = true;
        public string? Screen { get; set; }
        public double HorizontalPosition { get; set; } = 0.82;
        public string? LlmModel { get; set; }
        public bool LlmCredentialConfigured { get; set; }
        public string ActiveAppearance { get; set; } = "isaac";
    }

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    private readonly string _filePath;
    private Persisted _persisted;

    public SettingsStore(string? filePath = null)
    {
        _filePath = filePath ?? Path.Combine(AppPaths.DataDirectory, "settings-v1.json");
        _persisted = LoadPersisted();
    }

    public PetSettings Load() => new()
    {
        Scale = PetSettings.ValidScale(_persisted.Scale),
        RoamingEnabled = _persisted.Roaming,
        ScreenIdentifier = _persisted.Screen,
        HorizontalPosition = Math.Clamp(_persisted.HorizontalPosition, 0, 1),
    };

    public void Save(PetSettings settings)
    {
        _persisted.Scale = settings.Scale;
        _persisted.Roaming = settings.RoamingEnabled;
        _persisted.Screen = settings.ScreenIdentifier;
        _persisted.HorizontalPosition = settings.HorizontalPosition;
        Commit();
    }

    public string LlmModel
    {
        get => string.IsNullOrWhiteSpace(_persisted.LlmModel) ? "gpt-5.6-luna" : _persisted.LlmModel!;
        set { _persisted.LlmModel = value; Commit(); }
    }

    /// <summary>仅是 UI 提示位；API Key 本体只存 DPAPI 密文，读这个标志绝不触碰凭据。</summary>
    public bool LlmCredentialConfigured
    {
        get => _persisted.LlmCredentialConfigured;
        set { _persisted.LlmCredentialConfigured = value; Commit(); }
    }

    public string ActiveAppearance
    {
        get => _persisted.ActiveAppearance;
        set { _persisted.ActiveAppearance = value; Commit(); }
    }

    private Persisted LoadPersisted()
    {
        if (!File.Exists(_filePath)) return new Persisted();
        try
        {
            return JsonSerializer.Deserialize<Persisted>(File.ReadAllText(_filePath)) ?? new Persisted();
        }
        catch (JsonException)
        {
            return new Persisted();
        }
    }

    private void Commit()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
        var temp = _filePath + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(_persisted, JsonOptions));
        File.Move(temp, _filePath, overwrite: true);
    }
}
