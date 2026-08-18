# Isaac Pet

一个面向桌面平台的非官方 Isaac 桌宠项目，使用项目中提供的《The Binding of Isaac: Rebirth》Isaac 像素素材制作。

当前版本是原生 macOS 应用；仓库使用与平台无关的名称，后续可在同一项目中扩展 Windows 版本。

![Isaac direction preview](qa/direction-contact-sheet.png)

## 功能

- 透明无边框窗口，始终置顶并可出现在所有桌面空间
- Isaac 会在当前屏幕底部自主走动，并朝鼠标方向观察
- 单击招手、双击跳跃、拖拽移动、右键打开菜单
- 可从菜单栏或右键菜单进入游玩模式，使用 WASD 移动、方向键发射泪弹
- 菜单可触发哭泣、点赞和观察动画，调整大小或暂停走动
- 像素风对话气泡，可随机说话、显示颜文字或输入自定义文字
- 可选 OpenAI Responses API 对话：默认关闭，API Key 只存 macOS 钥匙串
- 内置本地 Todo 窗口，可新增、完成、恢复和删除任务，并设置定时提醒
- 到期任务会通过 Isaac 气泡提醒；授权后也会发送 macOS 系统通知
- 可手动从 Apple“提醒事项”导入指定列表，并按系统条目 ID 去重更新
- 可手动从 Notion data source 导入任务，访问令牌只保存在 macOS 钥匙串
- 内置 Agent 中心：查看角色能力、任务状态与审计记录，并运行 Isaac Planner、Magdalene 节奏检查与 Judas 专注/确认式 Todo 创建
- 记忆大小、走动开关、屏幕和横向位置
- 可选登录时启动，不显示 Dock 图标，菜单栏保留 Isaac 入口
- 默认本地独立运行；只有手动同步 Notion 或主动使用 LLM 时才访问对应服务，不收集遥测

## 平台状态

- macOS 13+：已实现，使用 Swift 6 和 AppKit
- Windows：规划中，当前仓库尚不提供 Windows 可执行文件

## 系统要求

- macOS 13 或更高版本
- Apple Silicon 或 Intel Mac
- 从源码构建需要 Swift 6 和 macOS Command Line Tools

## 构建

```bash
scripts/build_app.sh
```

生成结果：

```text
dist/Isaac Pet.app
```

应用使用 ad-hoc 本地签名，可以直接在本机运行。若要重新生成 Isaac 图集和图标，需要安装 Pillow，并设置 `ISAAC_REGENERATE_ASSETS=1`：

```bash
ISAAC_REGENERATE_ASSETS=1 scripts/build_app.sh
```

## 安装

```bash
scripts/install_app.sh
```

默认安装到 `~/Applications/Isaac Pet.app` 并打开。也可以直接双击 `dist/Isaac Pet.app`。

## 操作

- 单击 Isaac：招手
- 双击 Isaac：跳跃
- 拖拽 Isaac：移动到另一个位置或屏幕，松手后停在该屏幕底部
- 右键 Isaac：打开动作与设置菜单
- 对话气泡：从右键或菜单栏菜单选择随机文字、颜文字或“自定义气泡…”
- LLM：先从“LLM 设置…”保存 API Key 和模型，再用“问 Isaac（LLM）…”主动发送单条问题
- Todo：从菜单进入“新建 Todo…”、“查看 Todo…”或“查看今日计划…”。今日计划只读本机 Todo，按逾期、今天到期、后续到期、无日期的顺序给出最多三项重点，也可以让 Isaac 显示下一项
- Apple 提醒事项：从 Todo 子菜单选择“从 Apple 提醒事项同步…”，授权后选择一个列表或全部列表
- Notion：从 Todo 子菜单进入“Notion 设置…”，保存 internal integration token 与 data source ID 后手动同步
- Agents：打开 Agent 中心查看角色权限；Isaac 生成今日计划，Magdalene 检查任务节奏，Judas 启动本地专注计时或提出创建 Todo（必须再次确认）
- 桌宠形象：从“桌宠形象”子菜单切换已安装角色图集；运行 Agent 时会临时切换对应角色，任务结束、取消或失败后恢复你的选择
- 菜单栏 Isaac 图标：随时打开同一个菜单
- 游玩模式：WASD 连续移动，方向键可按住连发泪弹，Esc 退出并恢复桌宠行为
- 游玩模式行走：A/D 使用左右步态；W 使用后脑勺和背面身体步态，S 使用正脸和正面身体步态
- 发射瞬间：左右/向下会短暂闭眼，向上会显示轻微压扁的后脑勺姿态

透明像素会穿透到下方应用，只有 Isaac 的可见身体响应鼠标。

Todo 数据仅保存在本机：

```text
~/Library/Application Support/Isaac Pet/todos-v1.json
```

设置了提醒时间后，应用会在首次需要时请求 macOS 通知权限。拒绝权限不会影响 Todo 和 Isaac 运行期间的气泡提醒。

Apple“提醒事项”同步是用户主动触发的只读导入：

- 首次同步时 macOS 会请求“提醒事项”读取权限。
- Isaac Pet 不会创建、修改或删除 Apple“提醒事项”中的内容。
- 再次同步会通过系统条目 ID 更新已导入 Todo，不会按标题猜测合并。
- 系统中尚未导入的已完成历史不会批量进入本地 Todo；已链接任务的完成状态会正常刷新。
- Apple“提醒事项”是已链接任务的读取源；若只在 Isaac 本地修改标题、时间或完成状态，下次同步会以系统内容为准。

Notion 同步同样采用手动只读模式：

1. 在 Notion 创建 internal integration，并只授予读取内容所需能力。
2. 把目标 data source 共享给该 integration。
3. 在 Isaac Pet 的“Notion 设置…”中填写 integration token 和 data source ID。
4. Token 只保存在 macOS 钥匙串；data source ID 保存在普通本机设置中。同步时它们只发送到 `api.notion.com`。
5. Isaac 会自动识别 title、date，以及常见的 Done/Complete/完成 checkbox 或 status。已链接条目以下次 Notion 同步结果为准。

“断开 Notion”会删除钥匙串中的 Token 和连接设置，不会删除已经导入的本地 Todo。当前使用 Notion API `2026-03-11`，单次手动同步上限为 1000 条。

## 可选 LLM 对话

LLM 默认关闭，不影响本地气泡、Todo 或 Agent：

- API Key 只保存在 macOS Keychain，不写入 UserDefaults、Todo、Agent 审计或仓库。
- 打开菜单不会读取钥匙串；只有主动进入“LLM 设置…”、提问或断开 LLM 时，才可能出现 macOS 钥匙串授权。
- 只有点击“问 Isaac（LLM）…”并确认发送时，当前输入才会发往 `https://api.openai.com/v1/responses`。
- 请求不会附带 Todo、Notion 内容、文件、桌面数据或历史对话，也不开放任何模型工具。
- 请求显式设置 `store: false`，30 秒超时，并可从菜单取消；回答经过 80 字气泡长度限制。
- 默认模型为 `gpt-5.6-luna`，可以在设置中改成账号实际可用的模型 ID。
- “断开 LLM”会删除钥匙串里的 API Key，本地功能继续可用。

## Agent 安全模型

Agent 中心当前包含四个角色档案：Isaac、Magdalene、Cain 和 Judas。角色名称代表职责与未来视觉形象，但不会绕过工具权限：

- 读取本地 Todo：只有角色显式声明后才可自动执行。
- 修改本地 Todo、读取外部任务：即使角色声明，也必须在动作发生前确认。
- 修改外部任务、联网研究、运行命令：初始版本没有安装执行适配器，界面显示“未开放”。
- Agent 输出只能作为受限文本进入气泡或结果窗口，不能直接控制桌面窗口和系统工具。

目前有三项自动本地工作流和一项确认式写入工作流：

- Isaac Planner 按逾期、今天到期、未来到期和无日期任务排序，最多给出三项行动建议。
- Magdalene 节奏检查根据逾期、今日到期和待办总量给出喝水、活动和专注/休息节奏建议。
- Judas 专注计时在本机运行 15/25/45 分钟倒计时，可填写专注目标；支持取消、完成弹窗和系统通知。
- Judas 创建 Todo 会先写入一条 `awaitingConfirmation` 审计记录，明确展示将新增的本地任务；只有用户再次点击“创建 Todo”后才会写入。取消不会修改 Todo。

前三项自动工作流都不会调用 LLM、访问网络或修改 Todo；Judas 的 Todo 写入仅限本机，并且必须经过该次操作的明确确认。LLM 对话是独立、用户主动触发的数据路径；Cain 仍只显示角色档案，联网研究尚未开放。

任务及审计日志保存在：

```text
~/Library/Application Support/Isaac Pet/Agents/tasks-v1.json
~/Library/Application Support/Isaac Pet/Agents/audit-v1.jsonl
```

每个任务会记录排队、运行、等待确认、成功、失败或取消状态；状态机禁止已完成、失败或取消的任务重新运行，也禁止任务从排队直接跳到成功。日志不写 Todo 全文快照、Notion Token 或其他凭据。

## 多角色图集

角色外观和 Agent 权限是两层独立机制：外观不会额外获得读取、写入、联网或命令权限。Isaac 是内置默认图集；其他角色需要单独通过图集 QA 后放入对应资源位置：

```text
Resources/Agents/magdalene-spritesheet.webp
Resources/Agents/judas-spritesheet.webp
```

每个图集必须是 `1536×2288` 的 8×11 WebP，兼容现有的 192×208 单元格、九组动画和 16 个视线方向。资源不存在时菜单项保持禁用，应用安全回退为 Isaac，不会把单帧或未验证图像误作完整角色皮肤。

Magdalene 已具备完整桌宠图集：`Resources/Agents/magdalene-spritesheet.webp`。它以已审核的 Isaac 完整动作图集为身体、动作时序和注册位置基础，并将用户提供的 Golden Locks 原始像素按每个占用格的头部位置确定性叠加；不使用 AI 生成、重绘或插值。可用以下命令重建，并在 `qa/` 中检查接触表、方向表和校验报告：

```bash
MAG_PYTHON="/Users/zeppeli/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
"$MAG_PYTHON" scripts/derive_magdalene_atlas.py
"$MAG_PYTHON" /Users/zeppeli/.codex/skills/hatch-pet/scripts/validate_atlas.py \
  Resources/Agents/magdalene-spritesheet.webp --require-v2
```

原始角色图和 Golden Locks 条保存在 `Assets/Source/agents/`，不会被打进应用包。`magdalene-portrait.png` 仍供 Agent 中心使用。用户从菜单选择的外观会持久保存；Agent 的角色外观只是运行期间的临时覆盖，不会修改这项偏好。射击、泪弹和竖向行走辅助资源目前仍沿用 Isaac 的基础辅助图集，这是现有 `SpriteAtlas` 架构的范围。

需要从终端或自动化工具直接打开界面时，可传入 `--show-todos`、`--show-daily-plan`、`--show-notion-settings`、`--show-llm-settings` 或 `--show-agents`。测试时可用 `ISAAC_AGENT_DATA_DIR` 指向隔离的审计目录。

## 验证

```bash
scripts/verify_app.sh
```

该命令验证应用包结构、签名、图集尺寸、独立性以及动画、方向、状态优先级和屏幕几何逻辑。当前纯命令行工具链不包含 XCTest，因此核心检查使用零依赖的 Swift 可执行测试程序 `IsaacPetCoreChecks`。

## 项目结构

- `Sources/IsaacPetCore`：可复用的动画表、方向映射、状态和屏幕几何
- `Sources/IsaacPetApp`：当前 macOS 版的 AppKit 窗口、渲染、交互、菜单与登录启动
- `Assets/Source`：平台共享的 Isaac 原始像素素材
- `Resources`：应用图集、图标和 Info.plist
- `scripts`：素材生成、构建、安装和验证脚本

未来增加 Windows 版本时，应保留现有 macOS 应用和共享素材，在独立的平台目录中添加 Windows UI、窗口管理及安装打包实现。

## 声明

这是非官方、非商业同人项目。Isaac、《The Binding of Isaac》及原始美术素材的权利归各自权利方所有。重新分发或商业使用前，请阅读 [NOTICE.md](NOTICE.md) 并自行确认所需授权。
