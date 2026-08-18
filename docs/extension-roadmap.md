# Isaac Pet 扩展功能调研与计划

## 结论

第一阶段选择“像素对话气泡”。它不需要系统权限或网络服务，并且成为了 Todo 提醒、可选 LLM 回复和多 Agent 状态的共同输出层。当前版本已完成本地文字、颜文字、自定义输入、跟随定位和自动消失；远程 LLM 作为默认关闭、用户主动触发的数据源接入。

## 优先级计划表

| 阶段 | 方向 | 用户价值 | 建议实现 | 关键依赖与风险 | 预计工作量 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| P0 | 像素对话气泡 | 桌宠开始主动表达，也是提醒和 Agent 的 UI 出口 | 独立透明气泡窗口；文字/颜文字；自定义输入；消息队列接口 | 长文本排版、多屏边缘定位、避免遮挡与抢焦点 | 1–2 天 | 已实现 MVP |
| P0.5 | 可选 LLM 回复 | 让桌宠回答用户主动提出的问题 | Responses API；Keychain；模型设置；取消/超时；输出截断；默认关闭 | API 成本、密钥保护、隐私披露、网络失败 | 2–4 天 | 已实现受限 MVP |
| P1 | 本地 Todo 与提醒 | 无账号即可形成日常生产力闭环 | 本地 JSON 任务库 + Todo/今日计划窗口 + 到期时间 + macOS 本地通知；气泡展示到期事项 | 通知授权、重复提醒、休眠后补发、数据迁移 | 4–7 天 | 已实现 MVP |
| P1.5 | 系统“提醒事项”同步 | 与 Apple 生态复用已有任务 | EventKit 手动只读同步；列表选择；稳定 ID 映射；本地状态刷新 | macOS 14 使用完整提醒事项访问；macOS 13 兼容旧授权；双向写回仍需冲突策略 | 3–5 天 | 已实现只读 MVP |
| P2 | Notion 同步 | 适合已有 Notion 工作流的用户 | internal integration；data source 手动只读同步；游标分页；Keychain 存令牌；稳定 page ID 映射 | 用户必须共享 data source；网络失败、API 限流、字段映射和冲突 | 4–7 天 | 已实现只读 MVP |
| P3 | 多 Agent 助手 | 让其他角色承担研究、整理、提醒等不同职责 | 角色/能力清单；执行策略；任务状态；取消；JSONL 审计；Agent 中心；三个本地 Agent；确认式本地 Todo 写入 | 工具越权、提示注入、成本、长任务状态、失败恢复、版权素材 | 2–4 周起 | 安全底座、Isaac Planner、Magdalene 节奏检查、Judas 专注计时与确认式 Todo 创建已实现 |
| P4 | 娱乐化塔罗牌 | 提供低风险、可关闭的每日互动入口 | 22 张 Major Arcana 牌组；每日稳定抽卡；窗口内重抽；纯色占位卡面；娱乐免责声明 | 游戏素材授权、避免伪装成真实预测、后续卡面替换 | 1–2 天 | 已实现占位版；卡面素材待用户确认来源 |

## 调研要点

### 对话气泡与 LLM

- AppKit 中使用单独的 `NSPanel` 可以让气泡跟随 Isaac，同时不破坏原宠物窗口的透明像素命中区域。
- LLM 已作为独立 Provider 接入 OpenAI Responses API：默认本地短句，用户保存 API Key 并主动提问后才访问网络。
- API Key 只放进 Keychain。请求固定发往 `api.openai.com/v1/responses`，显式设置 `store: false`，30 秒超时并支持取消；只发送本次输入，不发送 Todo、Notion、文件或历史对话。
- 解码器会遍历完整 `output` 数组收集所有 `output_text`，再进入统一 80 字气泡限制；没有开放 Web、文件、命令或其他工具调用。
- Agent 输出也应先变成受长度限制的消息，再交给同一个气泡展示，避免模型直接控制窗口。

### Todo、提醒事项与 Notes

- 最稳妥的第一版是自有本地任务模型，通知使用 macOS User Notifications；这样不依赖任何账号。
- 当前 MVP 已将任务保存在 `~/Library/Application Support/Isaac Pet/todos-v1.json`，支持新增、完成/恢复、删除、下一个任务和到时气泡；只有创建未来提醒时才请求系统通知权限。
- Apple 的 EventKit 有结构化的提醒事项、截止时间和完成状态，比 Notes 更适合 Todo。macOS 14+ 提供完整提醒事项访问请求，项目当前最低支持 macOS 13，因此实现时需要做版本分支并补充用途说明。
- Apple“提醒事项”只读同步 MVP 已实现：由用户从菜单主动触发，选择单个或全部列表，以“列表 ID + 系统条目 ID”建立稳定链接，再次同步更新标题、截止时间和完成状态。它不会向系统数据库写入或删除内容，也不会按标题误合并。
- 双向写回暂不默认开启。进入下一版本前需要为“本地和系统同时修改”“列表被删除”“系统 ID 在全量同步后变化”定义可恢复的冲突界面。
- 本机 Notes 确实暴露了 AppleScript 字典，包含笔记标题、HTML 正文、创建与修改时间；但它依赖“自动化”权限，正文不是结构化任务数据，因此更适合作为导出/收集箱，而不是核心数据库。

### Notion 与多 Agent

- Notion 集成需要授权流程或个人令牌，并要求用户明确把页面/数据库共享给集成；同步层必须处理字段映射、限流和冲突。
- 当前 Notion 只读 MVP 使用官方 `2026-03-11` API 和 `/v1/data_sources/{id}/query`，支持 100 条一页的游标分页，最多读取 1000 条。Token 只写入 macOS Keychain，不会进入 JSON、UserDefaults 或日志。
- 映射规则会自动选择 title 和 date 属性，并识别常见 Done/Complete/完成 checkbox 或 status；未链接的已完成历史不会批量导入，已链接 page 会刷新标题、日期与完成状态。
- 断开连接不会删除本地 Todo。双向写回仍需显式冲突界面和逐项授权，因此不在只读 MVP 中暗中开启。
- 多 Agent 不应先从“新增角色皮肤”开始。应先定义每个角色能调用的工具、数据范围、是否需要用户确认、超时/取消机制和可审计日志，再把角色动画绑定到运行状态。
- 推荐首批角色分工：Isaac 负责对话与总览；Magdalene 负责健康/休息提醒；Cain 负责资料查找；Judas 负责专注计时。名称和美术发布前仍需单独评估版权边界。
- 多 Agent 安全底座已实现：每个角色声明能力，中央策略返回“自动、需确认、未开放”；任务状态支持排队、运行、等待确认、成功、失败和取消，并将状态变化写入本地 JSONL 审计日志。状态机只允许前进式合法转换，终态任务不能被重新打开，确认式任务不能从排队直接跳到成功。
- Isaac Planner 仅拥有 `readLocalTodos`，按截止状态生成最多三项今日建议；Magdalene 节奏检查用同一只读权限评估逾期、今日到期和待办总量，给出最多三条休息与节奏建议；Judas 拥有独立的 `focusTimer` 自动权限，在本机运行 15/25/45 分钟倒计时，可填写目标、取消或完成，不会因为计时而修改 Todo。三者都不联网、不调用 LLM，因此可自动执行。Cain 的联网研究和任何命令执行在没有适配器时均为“未开放”。
- Agent 中心可以查看四个角色档案、能力策略、任务历史和最近审计事件，并根据 Isaac/Magdalene/Judas 切换不同动作；焦点任务会显示剩余时间并支持取消。Judas 的本地 Todo 创建先进入 `awaitingConfirmation` 并展示精确写入内容；用户确认后才执行，取消只写入审计，不更改 Todo。角色外观现在有资源目录、菜单选择、持久化和运行时绑定：用户选择的外观和 Agent 的临时运行外观分离，任务结束、取消或失败后恢复前者。完整图集必须位于 `Resources/Agents/<role>-spritesheet.webp`，不存在或未通过图集 QA 时菜单禁用并安全回退 Isaac。Magdalene 完整 8×11 图集现已通过 QA：它确定性复用已审核 Isaac 动作，并仅按定位叠加用户提供的 Golden Locks 原始像素；射击、泪弹和竖向行走辅助资源暂仍复用 Isaac 基础素材。下一步可评估带冲突界面的外部 Todo 写入能力。

## 建议的演进接口

```text
本地短句 / Todo 提醒 / LLM 回复 / Agent 事件
                    ↓
            统一 BubbleMessage
                    ↓
        像素气泡 + 通知 + 历史记录
```

## 资料来源

- [OpenAI Text generation](https://developers.openai.com/api/docs/guides/text)
- [OpenAI Responses API: Create a response](https://developers.openai.com/api/docs/api-reference/responses/create)
- [Notion Authorization](https://developers.notion.com/docs/authorization)
- [Notion API Introduction and request limits](https://developers.notion.com/reference/intro)
- [Apple EventKit](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui)
- [Apple User Notifications](https://developer.apple.com/documentation/usernotifications)
- 本机 `/System/Applications/Notes.app/Contents/Resources/Notes.sdef`，用于核对 Notes 的 AppleScript 能力。
