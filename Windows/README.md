# Isaac Pet · Windows 版

macOS 原生桌宠（`Sources/`）的 Windows 移植，使用 **.NET 8 + WPF** 实现，与 macOS 版共享同一份像素素材（WebP 图集在构建前转换为 PNG）。

## 功能对照

| 功能 | macOS | Windows |
| --- | --- | --- |
| 透明无边框置顶窗口、透明像素穿透 | ✅ | ✅（逐像素 alpha + `WS_EX_TRANSPARENT` 轮询切换） |
| 自主走动 / 注视鼠标 / 悬停等待动画 | ✅ | ✅（同一套动画表与状态机，30fps） |
| 单击招手、双击跳跃、拖拽、右键菜单 | ✅ | ✅ |
| 游玩模式（WASD + 方向键泪弹，Esc 退出） | ✅ | ✅（含竖向行走与射击姿态图集） |
| 像素风对话气泡 | ✅ | ✅（同一布局常量与配色） |
| Todo（本地 JSON、到期提醒） | ✅ | ✅（气泡 + 托盘气球通知） |
| 大小切换 / 暂停走动 / 回到主屏幕 | ✅ | ✅ |
| 登录时启动 | ✅ SMAppService | ✅ 注册表 Run 键 |
| 菜单栏图标 | ✅ NSStatusItem | ✅ 系统托盘（NotifyIcon） |
| LLM 对话（OpenAI Responses API） | ✅ Keychain | ✅ DPAPI 加密落盘 |
| 多角色图集（Magdalene） | ✅ | ✅（共用转换后的图集） |
| Apple 提醒事项同步 | ✅ | ➖ 平台不支持 |
| Notion 同步 | ✅ | 🔜 尚未移植 |
| Agent 中心 / 审计日志 | ✅ | 🔜 尚未移植 |

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

自检对应 macOS 版的 `IsaacPetCoreChecks`：校验图集尺寸、九组动画规格、8 方向/4 射击列映射、Direction8 角度换算、动画帧索引、Todo 排序/合并/提醒去重、气泡策略与游玩输入向量。全部通过退出码为 0。

## 数据与凭据

- Todo：`%APPDATA%\Isaac Pet\todos-v1.json`（文件名与 macOS 版一致）
- 设置：`%APPDATA%\Isaac Pet\settings-v1.json`
- LLM API Key：DPAPI（CurrentUser）加密后保存为 `llm-credential.bin`，不落明文

## 平台差异说明

- Windows 屏幕坐标 y 向下，macOS 版所有 y 向上的方向计算（注视、泪弹、行走）在换算层统一翻转，动画表保持不变。
- 屏幕工作区按**每个显示器各自的 DPI** 换算（`GetDpiForMonitor`），而不是桌宠窗口初始化时的 DpiScale——后者在窗口尚未定位到目标屏时不可靠。
- 点击穿透与 macOS 版一样采用轮询：每帧检查光标下像素的 alpha，动态切换 `WS_EX_TRANSPARENT`。
- 系统通知用托盘气球代替 macOS UserNotifications；气泡提醒始终可用。
