namespace IsaacPet.Windows.Core;

/// <summary>
/// 专注计时的纯逻辑策略：默认时长、上限、剩余秒数与文案。
/// 移植自 macOS 版 Planning.swift 的 FocusSessionPolicy。
/// </summary>
public static class FocusSessionPolicy
{
    public static readonly TimeSpan DefaultDuration = TimeSpan.FromMinutes(25);
    public static readonly TimeSpan MaximumDuration = TimeSpan.FromHours(2);

    /// <summary>解析环境变量传入的测试时长（秒）；无效值回退默认 25 分钟。</summary>
    public static TimeSpan DurationFromSeconds(string? rawValue)
    {
        if (rawValue == null || !double.TryParse(rawValue, System.Globalization.CultureInfo.InvariantCulture, out var seconds)
            || !double.IsFinite(seconds) || seconds < 1)
        {
            return DefaultDuration;
        }
        return TimeSpan.FromSeconds(Math.Min(seconds, MaximumDuration.TotalSeconds));
    }

    public static int RemainingSeconds(DateTimeOffset deadline, DateTimeOffset now) =>
        Math.Max(0, (int)Math.Ceiling((deadline - now).TotalSeconds));

    public static string ClockText(int remainingSeconds)
    {
        var clamped = Math.Max(0, remainingSeconds);
        return $"{clamped / 60:D2}:{clamped % 60:D2}";
    }

    public static string DurationText(TimeSpan duration)
    {
        var seconds = Math.Max(1, (int)Math.Round(duration.TotalSeconds));
        return seconds % 60 == 0 ? $"{seconds / 60} 分钟" : $"{seconds} 秒";
    }
}
