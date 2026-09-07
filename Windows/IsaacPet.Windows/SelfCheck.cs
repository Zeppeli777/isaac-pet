using System.Runtime.InteropServices;
using IsaacPet.Windows.Core;
using IsaacPet.Windows.Sprites;

namespace IsaacPet.Windows;

/// <summary>
/// 零依赖自检（--self-check），对应 macOS 版的 IsaacPetCoreChecks：
/// 校验图集尺寸、动画表、方向映射、Todo 策略和气泡策略。
/// 在调用它的终端里输出结果，退出码 0 表示全部通过。
/// </summary>
public static class SelfCheck
{
    [DllImport("kernel32.dll")]
    private static extern bool AttachConsole(int dwProcessId);

    private const int AttachParentProcess = -1;

    public static int Run()
    {
        AttachConsole(AttachParentProcess);

        var failures = new List<string>();
        void Check(bool condition, string name)
        {
            Console.WriteLine($"{(condition ? "PASS" : "FAIL")}  {name}");
            if (!condition) failures.Add(name);
        }

        // 1. 图集尺寸
        try
        {
            var atlas = SpriteAtlas.Load();
            _ = atlas.Frame(AnimationID.Idle, 0);
            Check(true, "主图集加载且尺寸正确（1536×2288）");
        }
        catch (Exception error)
        {
            Check(false, $"主图集加载失败：{error.Message}");
            return Report(failures);
        }

        // 2. 动画表完整性：每行帧数不超过图集列数、行数不超过图集行数
        var atlasOk = true;
        foreach (var (id, spec) in AnimationCatalog.Specs)
        {
            if (spec.Row >= AnimationCatalog.Rows || spec.FrameCount > AnimationCatalog.Columns || spec.FrameCount < 1)
            {
                atlasOk = false;
                Console.WriteLine($"       规格异常：{id} row={spec.Row} frames={spec.FrameCount}");
            }
            if (spec.Duration <= 0) atlasOk = false;
        }
        Check(atlasOk, "九组动画规格在图集范围内");

        // 3. 方向映射：8 方向各自落到不同单元格
        var cells = new HashSet<(int, int)>();
        var directionsDistinct = true;
        foreach (Direction8 direction in Enum.GetValues<Direction8>())
        {
            if (!cells.Add(AnimationCatalog.AtlasCell(direction))) directionsDistinct = false;
        }
        Check(directionsDistinct && cells.All(c => c.Item1 is >= 0 and < AnimationCatalog.Rows && c.Item2 is >= 0 and < AnimationCatalog.Columns),
            "8 个注视方向映射到图集内互不相同的单元格");

        // 4. 射击姿态列覆盖 4 列
        var shootingColumns = Enum.GetValues<Direction8>().Select(AnimationCatalog.ShootingColumn).ToHashSet();
        Check(shootingColumns.SetEquals([0, 1, 2, 3]), "射击姿态列覆盖全部 4 列");

        // 5. Direction8 角度映射抽查（y 向上）
        Check(Direction8Extensions.From(100, 0) == Direction8.Right, "Direction8：+x → Right");
        Check(Direction8Extensions.From(0, 100) == Direction8.Up, "Direction8：+y → Up");
        Check(Direction8Extensions.From(-100, -100) == Direction8.DownLeft, "Direction8：(-,-) → DownLeft");
        Check(Direction8Extensions.From(10, 10, deadZone: 40) == null, "Direction8：死区内返回 null");

        // 6. 动画帧索引：循环与一次性动画
        var walkSpec = AnimationCatalog.SpecFor(AnimationID.WalkRight);
        Check(walkSpec.FrameIndex(walkSpec.FrameDuration * 8.5) == 0, "循环动画帧索引回绕");
        var waveSpec = AnimationCatalog.SpecFor(AnimationID.Wave);
        Check(waveSpec.FrameIndex(99) == waveSpec.FrameCount - 1, "一次性动画停在末帧");

        // 7. Todo 策略：排序与合并去重
        var older = new TodoItem { Title = "b", CreatedAt = DateTimeOffset.Now.AddDays(-2) };
        var sooner = new TodoItem
        {
            Title = "a",
            CreatedAt = DateTimeOffset.Now.AddDays(-1),
            DueAt = DateTimeOffset.Now.AddHours(1),
        };
        var completed = new TodoItem { Title = "c", CompletedAt = DateTimeOffset.Now };
        var sorted = TodoPolicy.Sorted([older, sooner, completed]);
        Check(sorted[0] == sooner && sorted[1] == older && sorted[2] == completed, "Todo 排序：未完成优先、到期时间升序");

        var source = new TodoExternalSource { Kind = TodoExternalKind.Notion, ItemIdentifier = "n1" };
        var (merged, summary) = TodoPolicy.Merging(
            [new ExternalTodoRecord(source, "  整理   报告 ", null, null)],
            []);
        Check(merged.Count == 1 && merged[0].Title == "整理 报告" && summary.Inserted == 1, "外部记录导入：标题折叠空白并插入");
        var (mergedAgain, summaryAgain) = TodoPolicy.Merging(
            [new ExternalTodoRecord(source, "整理 报告 v2", null, null)],
            merged);
        Check(mergedAgain.Count == 1 && mergedAgain[0].Title == "整理 报告 v2" && summaryAgain.Updated == 1,
            "外部记录按来源 ID 去重更新");

        // 8. 到期提醒筛选
        var dueNow = new TodoItem { Title = "到期", DueAt = DateTimeOffset.Now.AddMinutes(-1) };
        var reminded = new TodoItem { Title = "已提醒", DueAt = DateTimeOffset.Now.AddMinutes(-1), RemindedAt = DateTimeOffset.Now };
        var dueList = TodoPolicy.DueForDelivery([dueNow, reminded], DateTimeOffset.Now);
        Check(dueList.Count == 1 && dueList[0] == dueNow, "到期提醒：已提醒任务不重复投递");

        // 9. 气泡策略
        Check(SpeechBubblePolicy.Normalized("  你好   世界  ") == "你好 世界", "气泡文本折叠空白");
        Check(SpeechBubblePolicy.Normalized(new string('字', 100))!.Length == SpeechBubblePolicy.MaximumCharacters, "气泡文本 80 字截断");
        Check(SpeechBubblePolicy.Normalized("   ") == null, "空气泡返回 null");

        // 10. 游玩输入
        var keys = new HashSet<System.Windows.Input.Key> { PlayKeys.MoveLeft, PlayKeys.MoveUp };
        var (mx, my) = PlayInput.MovementVector(keys);
        Check(mx < 0 && my > 0 && Math.Abs(Math.Sqrt(mx * mx + my * my) - 1) < 1e-9, "斜向移动向量归一化");
        Check(PlayInput.WalkingDirectionFor(mx, my) == PlayWalkingDirection.Left, "斜向步态选择：平局沿用横向步态");

        return Report(failures);
    }

    private static int Report(List<string> failures)
    {
        Console.WriteLine(failures.Count == 0
            ? "\n全部检查通过。"
            : $"\n{failures.Count} 项检查失败。");
        return failures.Count == 0 ? 0 : 1;
    }
}
