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

        // 4.5 竖向行走：8 列 2 行，上下各 8 帧
        Check(AnimationCatalog.VerticalWalkingColumns == 8, "竖向行走图集 8 列");
        Check(AnimationCatalog.VerticalWalkingRows == 2, "竖向行走图集 2 行");
        Check(AnimationCatalog.VerticalWalkingSpecFor(VerticalWalkingDirection.Down).FrameCount == 8 &&
              AnimationCatalog.VerticalWalkingSpecFor(VerticalWalkingDirection.Up).FrameCount == 8,
            "竖向行走上下各 8 帧");

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

        // 9.5 表情气泡：素材名与配套动画一一对应
        Check(SpeechBubblePolicy.EmoteDisplayDuration == TimeSpan.FromSeconds(3.2), "表情气泡显示 3.2 秒");
        Check(EmoteID.Sad.ResourceName() == "EmoteSad" && EmoteID.Sad.CompanionAnimation() == AnimationID.Cry, "Sad 表情配套哭泣动画");
        Check(EmoteID.Shocked.ResourceName() == "EmoteShocked" && EmoteID.Shocked.CompanionAnimation() == AnimationID.Observe, "Shocked 表情配套观察动画");
        Check(EmoteID.Happy.ResourceName() == "EmoteHappy" && EmoteID.Happy.CompanionAnimation() == AnimationID.ThumbsUp, "Happy 表情配套点赞动画");

        // 10. 游玩输入
        var keys = new HashSet<System.Windows.Input.Key> { PlayKeys.MoveLeft, PlayKeys.MoveUp };
        var (mx, my) = PlayInput.MovementVector(keys);
        Check(mx < 0 && my > 0 && Math.Abs(Math.Sqrt(mx * mx + my * my) - 1) < 1e-9, "斜向移动向量归一化");
        Check(PlayInput.WalkingDirectionFor(mx, my) == PlayWalkingDirection.Left, "斜向步态选择：平局沿用横向步态");

        // 11. LLM 连接配置：端点拼接与导入容错
        var openAiConfig = new Llm.LlmConnectionConfig
        {
            BaseUrl = "https://api.openai.com/v1/",
            ApiKey = "k",
            Model = "gpt-5-mini",
            ApiFormat = Llm.LlmApiFormat.OpenAi,
        };
        Check(openAiConfig.EndpointUrl()?.ToString() == "https://api.openai.com/v1/chat/completions", "OpenAI 端点拼接并去掉结尾斜杠");
        var anthropicConfig = openAiConfig with
        {
            BaseUrl = "https://api.anthropic.com",
            ApiFormat = Llm.LlmApiFormat.Anthropic,
        };
        Check(anthropicConfig.EndpointUrl()?.ToString() == "https://api.anthropic.com/v1/messages", "Anthropic 端点自动补 /v1");
        var imported = Llm.LlmConnectionConfig.ParseImported(
            """{"baseUrl": "https://api.example.com/", "api_key": "sk-test", "model_name": "claude-x"}""");
        Check(imported.BaseUrl == "https://api.example.com" && imported.Model == "claude-x" && imported.ApiKey == "sk-test",
            "导入配置容忍别名键名并规范化 Base URL");
        Check(imported.ApiFormat == Llm.LlmApiFormat.OpenAi, "导入配置按 Base URL 推断 API 格式");
        Check(Llm.LlmConnectionConfig.ParseImported(
                """{"baseURL":"https://api.anthropic.com","model":"m"}""").ApiFormat == Llm.LlmApiFormat.Anthropic,
            "导入配置识别 Anthropic 主机名");
        try
        {
            Llm.LlmConnectionConfig.ParseImported("[1,2]");
            Check(false, "导入非对象 JSON 报配置文件无效");
        }
        catch (Exception error)
        {
            Check(error.Message.Contains("JSON"), "导入非对象 JSON 报配置文件无效");
        }

        // 12. 皮肤人格：每个形象都有包含人设要素的 system prompt
        foreach (PetAppearanceID appearance in Enum.GetValues<PetAppearanceID>())
        {
            var prompt = PetPersona.SystemPrompt(appearance);
            Check(prompt.Length > 80 && prompt.Contains("小桌宠") && prompt.Contains("80 个字"), $"皮肤人格提示词：{appearance}");
        }

        // 13. 专注计时策略
        Check(FocusSessionPolicy.DefaultDuration == TimeSpan.FromMinutes(25), "专注默认时长 25 分钟");
        Check(FocusSessionPolicy.DurationFromSeconds(null) == FocusSessionPolicy.DefaultDuration, "无效时长回退默认");
        Check(FocusSessionPolicy.DurationFromSeconds("3") == TimeSpan.FromSeconds(3), "测试时长解析");
        Check(FocusSessionPolicy.DurationFromSeconds("999999") == FocusSessionPolicy.MaximumDuration, "时长封顶 2 小时");
        var focusDeadline = DateTimeOffset.Now.AddSeconds(90.4);
        Check(FocusSessionPolicy.RemainingSeconds(focusDeadline, DateTimeOffset.Now) is > 89 and <= 91, "剩余秒数向上取整");
        Check(FocusSessionPolicy.ClockText(1505) == "25:05", "倒计时文案 mm:ss");
        Check(FocusSessionPolicy.DurationText(TimeSpan.FromMinutes(25)) == "25 分钟" &&
              FocusSessionPolicy.DurationText(TimeSpan.FromSeconds(90)) == "90 秒", "时长文案整分钟归一");

        // 14. 塔罗牌组与抽卡策略
        Check(TarotDeck.Cards.Count == TarotDeck.ArcanaCount * 2, "塔罗牌组含 22 正位 + 22 逆位");
        Check(TarotDeck.Cards.Select(card => card.Id).Distinct().Count() == TarotDeck.Cards.Count, "塔罗卡牌 ID 唯一");
        Check(TarotDeck.Cards.Count == TarotDeck.Cards.Count(card => TarotDeck.Card(card.NumeralIndex, card.IsReversed) != null),
            "按编号与正逆位可检索到每张牌");
        Check(TarotDeck.Cards.First(card => !card.IsReversed).NameZh == "0-愚者", "牌组以愚者开头");
        Check(TarotDeck.Cards.Last(card => !card.IsReversed).NameZh == "XXI-世界", "正位以世界结尾");
        Check(TarotDeck.Cards.Where(card => card.IsReversed).All(card => card.Unlock != null) &&
              TarotDeck.Cards.Where(card => !card.IsReversed).All(card => card.Unlock == null),
            "仅逆位牌带解锁条件");
        Check(TarotDeck.Cards.All(card => card.EffectLines.Length > 0), "每张牌都有使用效果说明");
        Check(TarotCardIconResources(TarotDeck.Cards), "44 张牌面图标资源名符合 Tarot00…TarotReversed21 规则");
        var drawnNormal = TarotDrawPolicy.Draw(() => 0.9);
        Check(!drawnNormal.IsReversed && drawnNormal.NumeralIndex == (int)(0.9 * TarotDeck.ArcanaCount), "抽卡按注入随机数取正位编号");
        var drawnReversed = TarotDrawPolicy.Draw(() => 0.1);
        Check(drawnReversed.IsReversed, "低于逆位概率阈值时抽到逆位");
        Check(TarotDrawPolicy.DisplayTitle(drawnReversed).StartsWith("逆位 · ") &&
              !TarotDrawPolicy.DisplayTitle(drawnNormal).StartsWith("逆位"), "逆位标题带标记");
        Check(AnimationCatalog.SpecFor(AnimationID.DrawCard).FrameCount == 4, "举卡姿势 4 帧");
        Check(AnimationCatalog.RaisingColumns == 8 && AnimationCatalog.RaisingRows == 1, "举臂图集 8 列 1 行");

        return Report(failures);
    }

    private static int Report(List<string> failures)
    {
        Console.WriteLine(failures.Count == 0
            ? "\n全部检查通过。"
            : $"\n{failures.Count} 项检查失败。");
        return failures.Count == 0 ? 0 : 1;
    }

    private static bool TarotCardIconResources(IReadOnlyList<TarotCard> cards)
    {
        var expected = new HashSet<string>();
        for (var index = 0; index < TarotDeck.ArcanaCount; index++)
        {
            expected.Add($"Tarot{index:00}");
            expected.Add($"TarotReversed{index:00}");
        }
        return cards.All(card => expected.Contains(card.IconResource));
    }
}
