# Isaac Pet → Windows 迁移方案

## 一、结论

**可以迁移，工作量中等偏大。**

项目总代码约 **6,570 行**，其中 **1,515 行** 是纯平台无关的核心逻辑（动画规格、状态机、Todo 数据模型、Agent 决策、塔罗牌、网络编解码），可以直接翻译为 C# 复用；剩余 **~4,440 行** 是 macOS AppKit 窗口、渲染、交互和系统集成代码，需要在 Windows 上全部重写。

预估工期：**单人全职 4–6 周**，或兼职（每天 2–3 小时）**3–4 个月**。

---

## 二、macOS 依赖拆解

### 2.1 可复用核心（IsaacPetCore/）— 1,515 行

| 文件 | 行数 | 依赖 | 可复用性 |
|------|------|------|----------|
| `Models.swift` | 528 | `Foundation`, `CoreGraphics` | ⭐⭐⭐ 逻辑直接翻译 |
| `TodoStore.swift` | 102 | `Foundation` | ⭐⭐⭐ 文件持久化逻辑不变 |
| `AgentModels.swift` | 366 | `Foundation` | ⭐⭐⭐ 纯算法 |
| `TarotModels.swift` | 76 | `Foundation` | ⭐⭐⭐ 数据定义 |
| `LLMModels.swift` | 116 | `Foundation` | ⭐⭐⭐ 编解码逻辑 |
| `NotionPayloadDecoder.swift` | 178 | `Foundation` | ⭐⭐⭐ JSON 解析 |
| `AgentAuditStore.swift` | 149 | `Foundation` | ⭐⭐⭐ 日志逻辑 |

> 这一层完全不含 `AppKit`、`Cocoa`、`Security`、`EventKit` 等 macOS 专属框架，只依赖 Swift 标准库和 `CoreGraphics` 的几何类型（`CGRect`、`CGPoint`、`CGVector`）。翻译为 C# 时，几何类型对应 `System.Drawing` 或 SkiaSharp 的 `SKRect`、`SKPoint`。

### 2.2 必须重写（IsaacPetApp/）— ~4,440 行

| 文件 | 行数 | macOS 专属依赖 | 替换难度 |
|------|------|----------------|----------|
| `PetController.swift` | 1,934 | `AppKit` 全套（NSPanel/NSView/NSMenu/NSStatusBar/NSEvent/NSScreen/CALayer） | 高 — 核心状态机 + 菜单 + 交互 |
| `AgentWindowController.swift` | 392 | `AppKit` | 中 |
| `TodoWindowController.swift` | 320 | `AppKit` | 中 |
| `SpeechBubbleController.swift` | 252 | `AppKit`（NSPanel + NSBezierPath 像素风绘制） | 中 — 气泡样式需复刻 |
| `SpriteAtlas.swift` | 205 | `AppKit`（NSImage/CGImage/NSBitmapImageRep） | 中 — 图集裁剪 + 像素命中检测 |
| `TarotWindowController.swift` | 185 | `AppKit` | 低 |
| `DailyPlanWindowController.swift` | 127 | `AppKit` | 低 |
| `AppleRemindersAdapter.swift` | 129 | `EventKit` | — **Windows 无此功能，需移除** |
| `PetView.swift` | 136 | `AppKit`（NSView + CALayer） | 中 — 鼠标/键盘事件 |
| `RoleAppearanceCatalog.swift` | 114 | `AppKit`（NSImage） | 低 |
| `NotionTodoAdapter.swift` | 106 | `Foundation`（URLSession） | 低 — 换 HttpClient |
| `OpenAIResponsesClient.swift` | 57 | `Foundation`（URLSession） | 低 — 换 HttpClient |
| `TodoReminderCoordinator.swift` | 68 | `UserNotifications` | 低 — 换 Windows Toast |
| `AgentReminderCoordinator.swift` | 47 | `UserNotifications` | 低 — 换 Windows Toast |
| `LLMCredentialStore.swift` | 75 | `Security`（Keychain） | 低 — 换 DPAPI |
| `NotionCredentialStore.swift` | 80 | `Security`（Keychain） | 低 — 换 DPAPI |
| `SettingsStore.swift` | 73 | `Foundation`（UserDefaults） | 低 — 换 JSON 设置文件 |
| `TearProjectile.swift` | 77 | `AppKit`（NSPanel + CALayer） | 中 |
| `PetSpeechLibrary.swift` | 30 | `Foundation` | ⭐⭐⭐ 直接翻译 |
| `PetPanel.swift` | 7 | `AppKit`（NSPanel） | 低 |
| `AppDelegate.swift` | 38 | `AppKit`（NSApplication） | 低 — 换 WinForms 入口 |
| `IsaacPetMain.swift` | 12 | `AppKit` | 低 — 换 C# `Program.cs` |

---

## 三、Windows 技术栈选型

### 3.1 推荐方案：C# + WinForms + SkiaSharp

```
┌─────────────────────────────────────────────┐
│  IsaacPetWin（C# .NET 8/9）                  │
│  ┌───────────────────────────────────────┐  │
│  │  WinForms Layered Window（WS_EX_LAYERED）│ │
│  │  ── 透明无边框、鼠标穿透、置顶           │  │
│  ├───────────────────────────────────────┤  │
│  │  SkiaSharp（SKBitmap/SKCanvas）        │  │
│  │  ── WebP 图集加载、精灵裁剪、像素绘制    │  │
│  ├───────────────────────────────────────┤  │
│  │  核心逻辑层（C# 翻译自 IsaacPetCore）    │  │
│  │  ── 状态机、Todo、Agent、塔罗、LLM      │  │
│  └───────────────────────────────────────┘  │
│                    ↓                         │
│  HttpClient ──→ OpenAI / Notion API         │
│  DPAPI ───────→ 保护 API Token              │
│  NotifyIcon ──→ 系统托盘 + 右键菜单          │
│  WinToast ────→ Windows 通知                │
└─────────────────────────────────────────────┘
```

#### 为什么选这个组合？

| 候选方案 | 不选原因 |
|---------|---------|
| **WPF** | `AllowsTransparency` 有已知黑色闪烁和性能问题，不适合高频精灵动画更新 |
| **WinUI 3** | 透明窗口支持仍不完善，运行时依赖大（~100MB+） |
| **C++/Win32 + GDI+** | 开发效率过低，同样的功能需要 2-3 倍代码量 |
| **Electron/Tauri** | 包体积过大（>100MB），桌宠应该轻量（目标 <30MB） |
| **Swift on Windows** | 生态不成熟，没有 AppKit 等价框架，等于重写 |

#### 为什么 WinForms + SkiaSharp 最适合？

1. **透明窗口**：WinForms 可以直接调用 Win32 API 创建 `WS_EX_LAYERED` + `WS_EX_TRANSPARENT` 窗口，`UpdateLayeredWindow` 实现像素级透明和鼠标穿透，行为与 macOS 的 `NSPanel` 最接近
2. **精灵渲染**：SkiaSharp 支持 WebP 解码（通过 Skia 内置编解码器），提供 `SKBitmap` 裁剪和 `SKCanvas` 绘制，支持 `NearestNeighbor` 滤波保持像素风
3. **像素命中检测**：`SKBitmap.GetPixel()` 替代 `NSBitmapImageRep.colorAt()`
4. **开发效率**：C# 语法和 Swift 接近，都有 GC、都有 async/await、都有 LINQ（对应 Swift 的 `map/filter`）
5. **体积**：.NET 8+ 支持单文件发布 + 裁剪，可以做到 **15-30MB**

---

## 四、关键模块映射（macOS → Windows）

### 4.1 窗口与渲染

| macOS | Windows (C#) | 说明 |
|-------|-------------|------|
| `NSPanel` (borderless, nonactivating) | `Form` + `WS_EX_LAYERED` / `WS_EX_TRANSPARENT` / `WS_EX_TOOLWINDOW` | 无边框透明置顶，无任务栏图标 |
| `NSView` + `CALayer.contents` | `UpdateLayeredWindow` + `SKBitmap` | 通过 `BLENDFUNCTION` 实现 per-pixel alpha |
| `NSView.isFlipped` | 自行处理坐标系翻转 | Windows 原点在左上，macOS 在左下 |
| `NSView.hasVisiblePixel` | `SKBitmap.GetPixel(x, y).Alpha > threshold` | 像素命中检测 |
| `CATransaction` + `setDisableActions` | `BufferedGraphics` 或双缓冲 SKBitmap | 避免闪烁 |
| `NSImage(contentsOf: .webp)` | `SKBitmap.Decode(stream)` | SkiaSharp 原生支持 WebP |
| `CGImage.cropping(to:)` | `SKBitmap.Subset(rect)` 或手动 `SKCanvas.DrawBitmap` | 精灵裁剪 |
| `NSScreen.visibleFrame` | `Screen.WorkingArea` | 可用屏幕区域 |
| `NSStatusBar` + `NSStatusItem` | `NotifyIcon` + `ContextMenuStrip` | 系统托盘 + 右键菜单 |

### 4.2 输入事件

| macOS | Windows (C#) |
|-------|-------------|
| `NSEvent.mouseLocation` | `Cursor.Position` |
| `mouseDown` / `mouseDragged` / `mouseUp` | `WndProc` → `WM_LBUTTONDOWN` / `WM_MOUSEMOVE` / `WM_LBUTTONUP` |
| `rightMouseDown` | `WM_RBUTTONUP`（弹出 ContextMenuStrip） |
| `keyDown` / `keyUp` (keyCode) | `WM_KEYDOWN` / `WM_KEYUP` + `Virtual-Key Codes` |
| `NSEvent.clickCount` | 自行计时判断双击（300ms 内第二次点击） |

### 4.3 系统集成

| macOS | Windows (C#) | 说明 |
|-------|-------------|------|
| `Security` / Keychain | `ProtectedData.Protect` / `Unprotect` (DPAPI) | 系统级加密，用户无关 |
| `UserDefaults` | JSON 设置文件 (`%LOCALAPPDATA%/IsaacPet/settings.json`) | 简单 key-value |
| `UNUserNotificationCenter` | `DesktopNotificationManagerCompat` 或 WinRT `Windows.UI.Notifications` | Windows Toast 通知 |
| `ServiceManagement` (登录启动) | Registry `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run` | 或 Task Scheduler |
| `EventKit` (Apple Reminders) | **移除** | Windows 没有内置等效 API；用户可用 Notion 同步替代 |
| `URLSession` | `HttpClient` | .NET 标准 HTTP 客户端 |
| `Timer(timeInterval: 1/30)` | `System.Windows.Forms.Timer` (Interval = 33ms) | 主循环 tick |

### 4.4 气泡对话框绘制

macOS 上用 `NSBezierPath` + `NSAttributedString.draw` 手绘像素风气泡，Windows 上对应：

- `SKPath` 绘制圆角矩形 + 三角形尾巴
- `SKPaint` 设置抗锯齿关闭（`IsAntialias = false`）保持像素感
- `SKCanvas.DrawText` 或手动用等宽字体绘制
- 布局计算逻辑（`fittingSize`）完全复用

---

## 五、建议的 Windows 项目结构

```
IsaacPetWin/
├── IsaacPetWin.csproj
├── Program.cs                    # 入口
├── App.config
│
├── Core/                         # ← 翻译自 IsaacPetCore（纯逻辑，无 UI）
│   ├── AnimationCatalog.cs       # 动画规格、方向映射
│   ├── Direction8.cs
│   ├── PetState.cs               # 状态机枚举 + 优先级
│   ├── PlayInput.cs              # WASD / 方向键输入向量
│   ├── ScreenBounds.cs           # 屏幕几何计算
│   ├── PetSettings.cs
│   ├── SpeechBubblePolicy.cs
│   ├── TodoItem.cs               # Todo 模型 + Policy
│   ├── TodoStore.cs              # 本地 JSON 持久化
│   ├── AgentModels.cs            # Agent 角色、任务、状态机
│   ├── LocalPlanningAgent.cs     # 今日计划生成
│   ├── LocalWellbeingAgent.cs    # 节奏检查
│   ├── FocusSessionPolicy.cs
│   ├── TarotDeck.cs              # 22 张塔罗牌
│   ├── TarotDrawPolicy.cs
│   ├── OpenAIResponsesCodec.cs   # LLM 请求/响应编解码
│   ├── NotionPayloadDecoder.cs   # Notion JSON 解析
│   └── AgentAuditStore.cs        # 审计日志
│
├── UI/                           # ← 全新编写（对应 IsaacPetApp）
│   ├── MainForm.cs               # 主桌宠窗口（Layered Window）
│   ├── MainForm.Designer.cs
│   ├── PetRenderer.cs            # SkiaSharp 精灵渲染器
│   ├── SpriteAtlas.cs            # 图集加载 + 裁剪 + 缓存
│   ├── SpriteFrame.cs            # 单帧 + 像素命中检测
│   ├── SpeechBubbleForm.cs       # 气泡窗口（独立 Layered Window）
│   ├── SpeechBubbleRenderer.cs   # 气泡绘制
│   ├── TearProjectile.cs         # 泪弹窗口 + 更新
│   ├── TrayMenu.cs               # 系统托盘 + 上下文菜单
│   ├── SettingsForm.cs           # 设置对话框
│   ├── TodoForm.cs               # Todo 管理窗口
│   ├── DailyPlanForm.cs          # 今日计划窗口
│   ├── TarotForm.cs              # 塔罗窗口
│   ├── AgentForm.cs              # Agent 中心窗口
│   ├── LLMSettingsForm.cs        # LLM 设置
│   └── NotionSettingsForm.cs     # Notion 设置
│
├── Services/                     # ← 系统集成适配器
│   ├── HttpClientFactory.cs      # OpenAI / Notion HTTP 客户端
│   ├── CredentialStore.cs        # DPAPI 封装
│   ├── SettingsStore.cs          # JSON 设置读写
│   ├── WindowsNotifier.cs        # Toast 通知封装
│   ├── StartupManager.cs         # 注册表登录启动
│   └── NotionTodoAdapter.cs      # Notion API 同步
│
└── Assets/                       # ← 复用现有资源
    ├── spritesheet.webp
    ├── shooting-atlas.webp
    ├── walking-vertical-atlas.webp
    ├── IsaacTear.png
    └── Agents/
        ├── magdalene-spritesheet.webp
        ├── magdalene-portrait.png
        └── judas-spritesheet.webp
```

---

## 六、实施路线图

### Phase 1：核心逻辑移植（第 1–2 周）

1. 创建 .NET 8/9 WinForms 项目，引入 SkiaSharp 包
2. 将 `IsaacPetCore/` 全部翻译为 C#（7 个文件，~1,515 行）
3. 写基础单元测试确保模型层行为一致
4. 验证 Todo 的 JSON 序列化/反序列化与 macOS 版本兼容（方便用户跨平台迁移数据）

### Phase 2：主窗口与精灵渲染（第 2–3 周）

1. 实现 `WS_EX_LAYERED` 无边框透明窗口（`MainForm`）
2. 用 SkiaSharp 加载 WebP 图集，实现精灵裁剪和缓存
3. 实现 `PetRenderer`：状态机 → 当前帧 → `UpdateLayeredWindow`
4. 实现鼠标事件：单击、双击、拖拽、右键菜单
5. 实现 `ScreenBounds` 的多屏适配和底部吸附
6. 实现自主走动 + 鼠标追踪（朝鼠标方向看）

### Phase 3：气泡、游玩模式、泪弹（第 3–4 周）

1. 气泡窗口（独立 Layered Window + 像素风绘制）
2. 游玩模式：键盘监听（WASD + 方向键）
3. 泪弹系统（独立小窗口 + 移动 + 越界销毁）
4. 竖向行走动画、射击姿态动画
5. 随机说话、颜文字、自定义气泡文本

### Phase 4：菜单、设置、Todo/Agent 窗口（第 4–5 周）

1. 系统托盘 `NotifyIcon` + `ContextMenuStrip`
2. 所有对话框窗口（设置、Todo、今日计划、塔罗、Agent 中心）
3. Todo CRUD + 到期提醒逻辑
4. Agent 工作流（Isaac 计划、Magdalene 节奏、Judas 专注计时）
5. 外观切换（Isaac / Magdalene / Judas）

### Phase 5：系统集成与收尾（第 5–6 周）

1. OpenAI HttpClient（30 秒超时、取消令牌）
2. Notion 同步（保留现有 payload decoder）
3. DPAPI 凭据存储
4. Windows Toast 通知
5. 注册表登录启动
6. 单文件发布 + 安装程序（Inno Setup 或 MSI）
7. 跨平台数据兼容测试（Todo JSON、审计日志）

---

## 七、关键难点与应对

| 难点 | 说明 | 应对方案 |
|------|------|----------|
| **Layered Window 性能** | `UpdateLayeredWindow` 频繁调用可能消耗 CPU | 双缓冲：只在精灵帧变化时更新；移动时只更新位置不重新绘制 |
| **多泪弹窗口** | 16 个泪弹 = 16 个额外窗口句柄 | 实测 16 个透明小窗口在现代 Windows 上无压力；必要时可合并到一个父窗口内绘制 |
| **气泡绘制复刻** | macOS 用 `NSBezierPath` 手绘像素风 | SkiaSharp 的 `SKPath` + `IsAntialias = false` 完全等价 |
| **WebP 支持** | Windows 默认不支持 WebP | SkiaSharp 内置 WebP 解码器，无需额外依赖 |
| **鼠标穿透** | 只在 Isaac 可见身体上响应鼠标 | `UpdateLayeredWindow` 的 `ULW_ALPHA` + 像素级 alpha 检测；或 `WS_EX_TRANSPARENT` + 手动判断 |
| **C# async/await 差异** | Swift `@MainActor` vs C# `SynchronizationContext` | WinForms 的 `Control.Invoke` / `SynchronizationContext.Post` 确保 UI 线程安全 |
| **Apple Reminders 缺失** | Windows 没有内置提醒事项 | 直接移除该功能；用户可用 Notion 替代 |

---

## 八、工作量估算

| 阶段 | 预估工时 | 全职天数 |
|------|---------|---------|
| Phase 1：核心逻辑移植 | 30–40h | 5–7 天 |
| Phase 2：主窗口与精灵渲染 | 40–50h | 7–9 天 |
| Phase 3：气泡、游玩、泪弹 | 25–35h | 4–6 天 |
| Phase 4：菜单、窗口、Todo/Agent | 35–45h | 6–8 天 |
| Phase 5：系统集成与打包 | 20–30h | 3–5 天 |
| **缓冲（调试、边界情况）** | +20% | — |
| **总计** | **175–240h** | **~4–6 周** |

---

## 九、数据兼容性建议

如果用户同时在 macOS 和 Windows 上使用，建议保持以下文件格式一致：

- **Todo 文件**：`todos-v1.json` — 已经使用 ISO-8601 日期，C# `System.Text.Json` 可直接解析
- **审计日志**：`audit-v1.jsonl` — 同样兼容
- **Agent 任务**：`tasks-v1.json` — 同样兼容
- **设置文件**：建议新定义一个跨平台 JSON schema，而非复用 `plist`/UserDefaults

这样用户可以通过 iCloud/Dropbox/OneDrive 同步 `Isaac Pet/` 目录，实现跨平台 Todo 数据共享。

---

## 十、备选技术栈（如果对 C# 不满意）

| 方案 | 适合场景 | 缺点 |
|------|---------|------|
| **C++ + Win32 + Direct2D** | 追求极致性能和最小体积 | 开发效率极低，需要 2-3 倍时间 |
| **C++ + SDL2** | 游戏化程度更高的桌宠 | 系统托盘、通知、设置窗口需自行集成 |
| **Rust + winit + wgpu** | 团队熟悉 Rust | 生态不成熟，工作量可能更大 |

---

## 总结

迁移到 Windows **完全可行**，最佳路径是 **C# + WinForms + SkiaSharp**。核心逻辑（~1,500 行）可以几乎一对一翻译，UI 和系统集成需要重写（~4,400 行）。单人全职 **4–6 周** 可以交付功能对等的 Windows 版本。
