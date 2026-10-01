# Isaac Pet · Windows 版

macOS 原生桌宠（`Sources/`）的 Windows 移植，使用 **.NET 8 + WPF** 实现，与 macOS 版共享同一份像素素材（WebP 图集在构建前转换为 PNG）。

## 功能对照

| 功能 | macOS | Windows |
| --- | --- | --- |
| 透明无边框置顶窗口、透明像素穿透 | ✅ | ✅（逐像素 alpha + `WS_EX_TRANSPARENT` 轮询切换） |
| 自主走动 / 注视鼠标 / 悬停等待动画 | ✅ | ✅（同一套动画表与状态机，30fps） |
| 单击招手、双击跳跃、拖拽、右键菜单 | ✅ | ✅ |
| 游玩模式（WASD + 方向键泪弹，Esc 退出） | ✅ | ✅（平抛泪弹 + 落地爆裂水滴 + 上射泪弹在桌宠身后） |
| 游戏风对话气泡（像素字体 + 阶梯像素边框） | ✅ | ✅（Fusion Pixel 12px，调色板与 macOS 版一致） |
| 表情气泡（Happy / Sad / Shocked，说话时互斥） | ✅ | ✅ |
| 抽张塔罗牌（举牌动画 + 洗牌/放大揭示 + 卡牌面板） | ✅ | ✅（44 张正位/逆位大阿尔克那，Magdalene 有专属举臂图集） |
| 共享像素 UI kit（窗口壳 / 对话框 / 按钮 / 菜单字体） | ✅ | ✅（同调色板 + 阶梯像素圆角，无抗锯齿） |
| Todo（本地 JSON、到期提醒） | ✅ | ✅（气泡 + 托盘气球通知） |
| 专注计时（15/25/45 分钟，重启恢复） | ✅ | ✅（托盘菜单显示剩余时间） |
| 大小切换 / 暂停走动 / 回到主屏幕 | ✅ | ✅ |
| 登录时启动 | ✅ SMAppService | ✅ 注册表 Run 键 |
| 菜单栏图标 | ✅ NSStatusItem | ✅ 系统托盘（NotifyIcon） |
| LLM 对话（OpenAI / Anthropic 兼容，可配 Base URL） | ✅ 配置文件 | ✅ DPAPI 加密落盘（不学 macOS 的明文 Key 文件） |
| 皮肤 = 形象 + 人格提示词（问 {persona}（LLM）…） | ✅ | ✅（Isaac / Magdalene / Judas 三套人格） |
| Magdalene 专属射击 / 竖走 / 举臂辅助图集 | ✅ | ✅（缺失时回退 Isaac 基础图集） |
| Apple 提醒事项同步 | ✅ | ➖ 平台不支持 |
| Notion 同步 | ✅ | 🔜 尚未移植 |
| Agent 中心 / 审计日志 | ➖ 已移除（降级为皮肤） | ➖ 从未引入 |

## 构建

前置：.NET 8 SDK（`net8.0-windows`），Python + Pillow（仅重新生成素材时需要）。

```powershell
# 1. 转换素材（Resources/*.webp -> Windows/IsaacPet.Windows/Assets/*.png）
python Windows/scripts/convert_assets.py

# 2. 构建
Windows\scripts\build_windows.bat
```

产物：`Windows/IsaacPet.Windows/bin/Release/net8.0-windows/IsaacPet.exe`，直接双击运行（绿色软件，无需安装）。

## 验证

```powershell
IsaacPet.exe --self-check
```

自检对应 macOS 版的 `IsaacPetCoreChecks`：校验图集尺寸、动画规格（含竖走 8 列与举臂图集）、8 方向/4 射击列映射、Direction8 角度换算、动画帧索引、Todo 排序/合并/提醒去重、气泡与表情策略、游玩输入向量、LLM 连接配置、皮肤人格、专注计时策略、塔罗牌组与抽卡策略。全部通过退出码为 0。

自动化/测试可用参数：`--self-check`、`--show-todos`、`--show-tarot`；专注计时支持 `ISAAC_FOCUS_DURATION_SECONDS` 环境变量注入测试时长。

## 数据与凭据

- Todo：`%APPDATA%\Isaac Pet\todos-v1.json`（文件名与 macOS 版一致）
- 设置：`%APPDATA%\Isaac Pet\settings-v1.json`
- LLM API Key：DPAPI（CurrentUser）加密后保存为 `llm-credential.bin`，不落明文

## 平台差异说明

- Windows 屏幕坐标 y 向下，macOS 版所有 y 向上的方向计算（注视、泪弹、行走）在换算层统一翻转，动画表保持不变。
- 屏幕工作区按**每个显示器各自的 DPI** 换算（`GetDpiForMonitor`），而不是桌宠窗口初始化时的 DpiScale——后者在窗口尚未定位到目标屏时不可靠。
- 点击穿透与 macOS 版一样采用轮询：每帧检查光标下像素的 alpha，动态切换 `WS_EX_TRANSPARENT`。
- 系统通知用托盘气球代替 macOS UserNotifications；气泡提醒始终可用。
- 塔罗牌与表情气泡素材来自粉丝 Wiki 与游戏内参考图（见根目录 [NOTICE.md](../NOTICE.md)）；Fusion Pixel 字体按 SIL OFL 1.1 分发（`Assets/Fonts/OFL.txt`）。
