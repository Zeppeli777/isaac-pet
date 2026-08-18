import AppKit
import IsaacPetCore
import ServiceManagement

@MainActor
final class PetController: NSObject, NSMenuDelegate, NSWindowDelegate, PetViewDelegate {
    private static let baseSize = NSSize(
        width: AnimationCatalog.cellWidth,
        height: AnimationCatalog.cellHeight
    )
    private static let shootingPoseDuration: TimeInterval = 0.11

    private let panel: PetPanel
    private let petView: PetView
    private var atlas: SpriteAtlas
    private let tearFrame: SpriteFrame
    private let settingsStore: SettingsStore
    private let speechBubble: SpeechBubbleController
    private let todoStore: TodoStore
    private let todoReminderCoordinator: TodoReminderCoordinator
    private let agentReminderCoordinator: AgentReminderCoordinator
    private let appleRemindersAdapter: AppleRemindersAdapter
    private let notionTodoAdapter: NotionTodoAdapter
    private let notionCredentialStore: NotionCredentialStore
    private let llmCredentialStore: LLMCredentialStore
    private let llmClient: any LLMReplyProvider
    private let agentAuditStore: AgentAuditStore
    private let menu = NSMenu(title: "Isaac Pet")
    private let statusItem: NSStatusItem

    private var settings: PetSettings
    private var activeAppearance: PetAppearanceID
    private var preferredAppearance: PetAppearanceID
    private var state: PetState = .idle
    private var stateStartedAt = ProcessInfo.processInfo.systemUptime
    private var actionEndsAt: TimeInterval?
    private var targetX: CGFloat?
    private var nextRoamAt = ProcessInfo.processInfo.systemUptime + Double.random(in: 4...10)
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var currentFrameKey = ""
    private var hoveredSince: TimeInterval?
    private var lastWaitingAt: TimeInterval = 0
    private var isDragging = false
    private var isPlayMode = false
    private var pressedPlayKeys: Set<PlayKey> = []
    private var playFacing: Direction8 = .down
    private var playWalkingDirection: PlayWalkingDirection?
    private var nextShotAt: TimeInterval = 0
    private var shootingPoseDirection: Direction8?
    private var shootingPoseEndsAt: TimeInterval = 0
    private var projectiles: [TearProjectile] = []
    private var keyEventMonitor: Any?
    private var todoWindowController: TodoWindowController?
    private var dailyPlanWindowController: DailyPlanWindowController?
    private var tarotWindowController: TarotWindowController?
    private var agentWindowController: AgentWindowController?
    private var activeAgentTask: Task<Void, Never>?
    private var activeAgentTaskID: UUID?
    private var todoSyncTask: Task<Void, Never>?
    private var appleRemindersSyncTask: Task<Void, Never>?
    private var notionSyncTask: Task<Void, Never>?
    private var llmTask: Task<Void, Never>?
    private var nextTodoCheckAt = ProcessInfo.processInfo.systemUptime + 0.75
    private var nextAgentUIRefreshAt = ProcessInfo.processInfo.systemUptime
    private var didExplainNotificationDenial = false

    init(atlas: SpriteAtlas, settingsStore: SettingsStore) throws {
        self.atlas = atlas
        self.settingsStore = settingsStore
        settings = settingsStore.load()
        activeAppearance = PetAppearanceID(rawValue: settingsStore.activeAppearance) ?? .isaac
        preferredAppearance = activeAppearance
        if activeAppearance != .isaac {
            let definition = PetAppearanceCatalog.definition(for: activeAppearance)
            if PetAppearanceCatalog.availability(activeAppearance).isAvailable {
                self.atlas = try SpriteAtlas(
                    spriteSheetResource: definition.spriteSheetResource,
                    spriteSheetSubdirectory: definition.subdirectory
                )
            } else {
                activeAppearance = .isaac
                preferredAppearance = .isaac
                settingsStore.activeAppearance = PetAppearanceID.isaac.rawValue
            }
        }
        tearFrame = try self.atlas.tearFrame()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let size = NSSize(
            width: Self.baseSize.width * settings.scale,
            height: Self.baseSize.height * settings.scale
        )
        petView = PetView(frame: NSRect(origin: .zero, size: size))
        speechBubble = SpeechBubbleController()
        todoStore = try TodoStore()
        todoReminderCoordinator = TodoReminderCoordinator()
        agentReminderCoordinator = AgentReminderCoordinator()
        appleRemindersAdapter = AppleRemindersAdapter()
        notionTodoAdapter = NotionTodoAdapter()
        notionCredentialStore = NotionCredentialStore()
        llmCredentialStore = LLMCredentialStore()
        llmClient = OpenAIResponsesClient()
        agentAuditStore = try AgentAuditStore()
        panel = PetPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        configurePanel()
        configureMenu()
        restorePlacement()
        showIdleFrame()
        panel.orderFrontRegardless()
        showSpeech("嗨！ :)")
        startTimer()
        restoreActiveAgentTask()
        synchronizeTodoReminders()
        if CommandLine.arguments.contains("--show-todos") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.showTodoList()
            }
        } else if CommandLine.arguments.contains("--show-daily-plan") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showDailyPlan()
            }
        } else if CommandLine.arguments.contains("--show-tarot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showTarot()
            }
        } else if CommandLine.arguments.contains("--show-notion-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.configureNotion()
            }
        } else if CommandLine.arguments.contains("--show-llm-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.configureLLM()
            }
        } else if CommandLine.arguments.contains("--show-agents") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showAgentCenter()
            }
        }
    }

    private func configurePanel() {
        panel.contentView = petView
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.delegate = self
        petView.delegate = self
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(item("进入游玩模式", action: #selector(togglePlayMode), tag: 300))
        menu.addItem(.separator())
        menu.addItem(item("随机说一句", action: #selector(sayRandomPhrase), tag: 115))
        menu.addItem(item("表个情", action: #selector(showRandomExpression), tag: 116))
        menu.addItem(item("自定义气泡…", action: #selector(composeSpeech), tag: 117))
        menu.addItem(item("今日运势（塔罗）…", action: #selector(showTarot), tag: 130))
        menu.addItem(item("问 Isaac（LLM）…", action: #selector(askLLM), tag: 118))
        menu.addItem(item("LLM 设置…", action: #selector(configureLLM), tag: 119))
        menu.addItem(item("断开 LLM", action: #selector(disconnectLLM), tag: 120))
        menu.addItem(item("取消 LLM 请求", action: #selector(cancelLLMRequest), tag: 121))
        menu.addItem(.separator())

        let todoMenu = NSMenu(title: "Todo")
        todoMenu.addItem(item("新建 Todo…", action: #selector(addTodo), tag: 401))
        todoMenu.addItem(item("查看 Todo…", action: #selector(showTodoList), tag: 402))
        todoMenu.addItem(item("查看今日计划…", action: #selector(showDailyPlan), tag: 408))
        todoMenu.addItem(item("显示下一个 Todo", action: #selector(showNextTodo), tag: 403))
        todoMenu.addItem(.separator())
        todoMenu.addItem(item("从 Apple 提醒事项同步…", action: #selector(syncAppleReminders), tag: 404))
        todoMenu.addItem(.separator())
        todoMenu.addItem(item("从 Notion 同步…", action: #selector(syncNotion), tag: 405))
        todoMenu.addItem(item("Notion 设置…", action: #selector(configureNotion), tag: 406))
        todoMenu.addItem(item("断开 Notion", action: #selector(disconnectNotion), tag: 407))
        let todoRoot = NSMenuItem(title: "Todo", action: nil, keyEquivalent: "")
        todoRoot.tag = 400
        menu.setSubmenu(todoMenu, for: todoRoot)
        menu.addItem(todoRoot)
        menu.addItem(.separator())

        let agentMenu = NSMenu(title: "Agents")
        agentMenu.addItem(item("打开 Agent 中心…", action: #selector(showAgentCenter), tag: 500))
        agentMenu.addItem(item("Isaac：生成今日计划", action: #selector(runDailyPlanAgent), tag: 501))
        agentMenu.addItem(item("Magdalene：检查今日节奏", action: #selector(runWellbeingAgent), tag: 503))
        agentMenu.addItem(item("Judas：开始专注", action: #selector(runFocusAgent), tag: 504))
        agentMenu.addItem(item("Judas：创建 Todo（需确认）", action: #selector(requestTodoWithJudas), tag: 505))
        agentMenu.addItem(item("取消当前 Agent 任务", action: #selector(cancelActiveAgentTask), tag: 502))
        let agentRoot = NSMenuItem(title: "Agents", action: nil, keyEquivalent: "")
        agentRoot.tag = 510
        menu.setSubmenu(agentMenu, for: agentRoot)
        menu.addItem(agentRoot)
        menu.addItem(.separator())

        let appearanceMenu = NSMenu(title: "桌宠形象")
        for appearance in PetAppearanceID.allCases {
            let definition = PetAppearanceCatalog.definition(for: appearance)
            let item = item(definition.displayName, action: #selector(selectAppearance(_:)), tag: 600)
            item.representedObject = appearance.rawValue
            appearanceMenu.addItem(item)
        }
        let appearanceRoot = NSMenuItem(title: "桌宠形象", action: nil, keyEquivalent: "")
        appearanceRoot.tag = 610
        menu.setSubmenu(appearanceMenu, for: appearanceRoot)
        menu.addItem(appearanceRoot)
        menu.addItem(.separator())

        menu.addItem(item("暂停走动", action: #selector(toggleRoaming), tag: 100))
        menu.addItem(.separator())
        menu.addItem(item("招手", action: #selector(wave), tag: 110))
        menu.addItem(item("跳一下", action: #selector(jump), tag: 111))
        menu.addItem(item("哭一下", action: #selector(cry), tag: 112))
        menu.addItem(item("赞一个", action: #selector(thumbsUp), tag: 113))
        menu.addItem(item("观察一下", action: #selector(observe), tag: 114))
        menu.addItem(.separator())

        let sizeMenu = NSMenu(title: "大小")
        for (title, scale, tag) in [("75%", 0.75, 75), ("100%", 1.0, 100), ("125%", 1.25, 125)] {
            let sizeItem = item(title, action: #selector(changeScale(_:)), tag: tag)
            sizeItem.representedObject = scale
            sizeMenu.addItem(sizeItem)
        }
        let sizeRoot = NSMenuItem(title: "大小", action: nil, keyEquivalent: "")
        menu.setSubmenu(sizeMenu, for: sizeRoot)
        menu.addItem(sizeRoot)
        menu.addItem(item("登录时启动", action: #selector(toggleLaunchAtLogin), tag: 200))
        menu.addItem(item("回到主屏幕", action: #selector(returnToMainScreen)))
        menu.addItem(.separator())
        menu.addItem(item("退出 Isaac Pet", action: #selector(quit), keyEquivalent: "q"))

        if let button = statusItem.button {
            button.toolTip = "Isaac Pet"
            if let url = Bundle.main.url(forResource: "StatusIsaac", withExtension: "png"),
               let icon = NSImage(contentsOf: url) {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            }
        }
        statusItem.menu = menu
    }

    private func item(
        _ title: String,
        action: Selector?,
        tag: Int = 0,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.target = self
        menuItem.tag = tag
        return menuItem
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTag: 300)?.title = isPlayMode ? "退出游玩模式（Esc）" : "进入游玩模式"
        if let roaming = menu.item(withTag: 100) {
            roaming.title = settings.roamingEnabled ? "暂停走动" : "继续走动"
            roaming.isEnabled = !isPlayMode
        }
        for tag in 110...114 { menu.item(withTag: tag)?.isEnabled = !isPlayMode }
        for tag in 115...117 { menu.item(withTag: tag)?.isEnabled = !isPlayMode }
        menu.item(withTag: 130)?.isEnabled = !isPlayMode
        for tag in 118...119 { menu.item(withTag: tag)?.isEnabled = !isPlayMode && llmTask == nil }
        // Never query Keychain while an NSMenu is tracking input. That can surface a
        // system authorization dialog behind the menu and leave its password field
        // without keyboard focus. The non-secret setting is updated only by explicit
        // LLM actions below.
        menu.item(withTag: 120)?.isEnabled = !isPlayMode && settingsStore.llmCredentialConfigured
        menu.item(withTag: 121)?.isEnabled = !isPlayMode && llmTask != nil
        let pendingTodoCount = TodoPolicy.pending(todoStore.items).count
        menu.item(withTag: 400)?.title = pendingTodoCount == 0 ? "Todo" : "Todo（\(pendingTodoCount)）"
        menu.item(withTag: 200)?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        for item in menu.items.compactMap(\.submenu).flatMap(\.items) {
            if [75, 100, 125].contains(item.tag) {
                item.state = abs(CGFloat(item.tag) / 100 - settings.scale) < 0.01 ? .on : .off
            }
            if [401, 402, 404, 405, 406, 408].contains(item.tag) { item.isEnabled = !isPlayMode }
            if item.tag == 403 { item.isEnabled = !isPlayMode && pendingTodoCount > 0 }
            if item.tag == 407 {
                item.isEnabled = !isPlayMode && settingsStore.notionDataSourceIdentifier != nil
            }
            if [500, 501, 503, 504, 505].contains(item.tag) {
                item.isEnabled = !isPlayMode && (item.tag == 500 || activeAgentTask == nil)
            }
            if item.tag == 502 { item.isEnabled = !isPlayMode && activeAgentTask != nil }
            if item.tag == 600,
               let rawValue = item.representedObject as? String,
               let appearance = PetAppearanceID(rawValue: rawValue) {
                item.state = appearance == preferredAppearance ? .on : .off
                let availability = PetAppearanceCatalog.availability(appearance)
                item.isEnabled = !isPlayMode && availability.isAvailable
                if !item.isEnabled {
                    item.toolTip = availability.unavailableReason
                }
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard isPlayMode else { return }
        DispatchQueue.main.async { [weak self] in self?.focusPlayControls() }
    }

    private func startTimer() {
        timer = Timer(
            timeInterval: 1 / 30,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    @objc private func timerFired() {
        tick()
        checkDueTodos(now: ProcessInfo.processInfo.systemUptime)
        refreshAgentUI(now: ProcessInfo.processInfo.systemUptime)
        updateSpeechBubbleAnchor()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        removeKeyEventMonitor()
        removeAllProjectiles()
        todoSyncTask?.cancel()
        appleRemindersSyncTask?.cancel()
        notionSyncTask?.cancel()
        llmTask?.cancel()
        activeAgentTask?.cancel()
        todoWindowController?.close()
        dailyPlanWindowController?.close()
        tarotWindowController?.close()
        agentWindowController?.close()
        speechBubble.stop()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = min(max(now - lastTick, 0), 0.1)
        lastTick = now

        if isPlayMode {
            updateProjectiles(delta: delta, now: now)
            if isDragging {
                render(now: now)
                updateMousePassThrough()
                return
            }
            updatePlayMode(delta: delta, now: now)
            render(now: now)
            updateMousePassThrough()
            return
        }

        if isDragging {
            render(now: now)
            updateMousePassThrough()
            return
        }

        if let actionEndsAt, now >= actionEndsAt {
            self.actionEndsAt = nil
            transition(to: .idle, at: now)
            scheduleNextRoam(now: now)
        }

        if actionEndsAt == nil, let targetX {
            updateWalking(targetX: targetX, delta: delta, now: now)
        } else if actionEndsAt == nil {
            updateAttention(now: now)
            if settings.roamingEnabled, now >= nextRoamAt {
                beginRoaming(now: now)
            }
        }

        render(now: now)
        updateMousePassThrough()
    }

    private func updateWalking(targetX: CGFloat, delta: TimeInterval, now: TimeInterval) {
        let origin = panel.frame.origin
        let distance = targetX - origin.x
        let step = CGFloat(80 * delta)
        if abs(distance) <= step {
            panel.setFrameOrigin(NSPoint(x: targetX, y: origin.y))
            self.targetX = nil
            transition(to: .idle, at: now)
            persistPlacement()
            scheduleNextRoam(now: now)
            return
        }

        let direction: WalkingDirection = distance > 0 ? .right : .left
        if state != .walking(direction) { transition(to: .walking(direction), at: now) }
        panel.setFrameOrigin(NSPoint(x: origin.x + (distance > 0 ? step : -step), y: origin.y))
    }

    private func updatePlayMode(delta: TimeInterval, now: TimeInterval) {
        let movement = PlayInput.movementVector(for: pressedPlayKeys)
        let isMoving = movement != .zero
        playWalkingDirection = PlayInput.walkingDirection(for: movement)
        if isMoving {
            let origin = panel.frame.origin
            let proposed = NSPoint(
                x: origin.x + movement.dx * CGFloat(180 * delta),
                y: origin.y + movement.dy * CGFloat(180 * delta)
            )
            if let screen = currentScreen() {
                let clamped = ScreenBounds(rect: screen.visibleFrame).clampedFreeOrigin(
                    proposed,
                    petSize: panel.frame.size
                )
                panel.setFrameOrigin(clamped)
            }
            if let direction = Direction8.from(
                deltaX: movement.dx,
                deltaY: movement.dy,
                deadZone: 0
            ) {
                playFacing = direction
            }
        }

        if let firingDirection = PlayInput.firingDirection(for: pressedPlayKeys) {
            playFacing = firingDirection
            if now >= nextShotAt {
                spawnTear(direction: firingDirection, now: now)
                nextShotAt = now + 0.22
            }
        }

        transition(to: .playing(playFacing, moving: isMoving), at: now)
    }

    private func spawnTear(direction: Direction8, now: TimeInterval) {
        shootingPoseDirection = direction
        shootingPoseEndsAt = now + Self.shootingPoseDuration
        currentFrameKey = ""
        if projectiles.count >= 16 {
            projectiles.removeFirst().remove()
        }
        let vector = PlayInput.unitVector(for: direction)
        let center = NSPoint(
            x: panel.frame.midX + vector.dx * 26 * settings.scale,
            y: panel.frame.midY + vector.dy * 26 * settings.scale
        )
        projectiles.append(TearProjectile(
            spriteFrame: tearFrame,
            center: center,
            velocity: CGVector(dx: vector.dx * 330, dy: vector.dy * 330),
            size: 18 * settings.scale,
            expiresAt: now + 1.45
        ))
    }

    private func updateProjectiles(delta: TimeInterval, now: TimeInterval) {
        for projectile in projectiles { projectile.update(delta: delta) }
        projectiles.removeAll { projectile in
            let shouldRemove = now >= projectile.expiresAt || !NSScreen.screens.contains { screen in
                screen.frame.intersects(projectile.frame)
            }
            if shouldRemove { projectile.remove() }
            return shouldRemove
        }
    }

    private func removeAllProjectiles() {
        for projectile in projectiles { projectile.remove() }
        projectiles.removeAll()
    }

    private func updateAttention(now: TimeInterval) {
        let mouse = NSEvent.mouseLocation
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let distance = hypot(mouse.x - center.x, mouse.y - center.y)
        let sameScreen = screen(containing: mouse) === currentScreen()

        if sameScreen, distance <= 400,
           let direction = Direction8.from(deltaX: mouse.x - center.x, deltaY: mouse.y - center.y) {
            if state != .tracking(direction) { transition(to: .tracking(direction), at: now) }
        } else if state.priority <= PetState.tracking(.up).priority, state != .idle {
            transition(to: .idle, at: now)
        }

        let windowPoint = panel.convertPoint(fromScreen: mouse)
        let localPoint = petView.convert(windowPoint, from: nil)
        if petView.hasVisiblePixel(at: localPoint) {
            if hoveredSince == nil { hoveredSince = now }
            if let hoveredSince, now - hoveredSince > 1.3, now - lastWaitingAt > 8, actionEndsAt == nil {
                lastWaitingAt = now
                perform(.waiting, now: now)
            }
        } else {
            hoveredSince = nil
        }
    }

    private func beginRoaming(now: TimeInterval) {
        guard let screen = currentScreen() else { return }
        let frame = screen.visibleFrame
        let minimum = frame.minX
        let maximum = max(minimum, frame.maxX - panel.frame.width)
        guard maximum - minimum > 40 else { return }

        var candidate = CGFloat.random(in: minimum...maximum)
        if abs(candidate - panel.frame.origin.x) < 120 {
            candidate = panel.frame.origin.x < frame.midX ? maximum : minimum
        }
        targetX = candidate
        let direction: WalkingDirection = candidate >= panel.frame.origin.x ? .right : .left
        transition(to: .walking(direction), at: now)
    }

    private func scheduleNextRoam(now: TimeInterval) {
        nextRoamAt = now + Double.random(in: 4...10)
    }

    private func transition(to newState: PetState, at now: TimeInterval) {
        guard state != newState else { return }
        state = newState
        stateStartedAt = now
        currentFrameKey = ""
    }

    private func perform(_ animation: AnimationID, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        targetX = nil
        transition(to: .action(animation), at: now)
        actionEndsAt = now + AnimationCatalog.spec(for: animation).duration
    }

    private func render(now: TimeInterval) {
        do {
            switch state {
            case let .tracking(direction):
                let key = "direction-\(direction.rawValue)"
                guard currentFrameKey != key else { return }
                petView.spriteFrame = try atlas.frame(direction: direction)
                currentFrameKey = key
            case let .walking(direction):
                let animation: AnimationID = direction == .right ? .walkRight : .walkLeft
                try render(animation: animation, now: now)
            case let .action(animation):
                try render(animation: animation, now: now)
            case let .playing(direction, moving):
                if let shootingPoseDirection, now < shootingPoseEndsAt {
                    let key = "shooting-\(AnimationCatalog.shootingColumn(for: shootingPoseDirection))"
                    guard currentFrameKey != key else { return }
                    petView.spriteFrame = try atlas.frame(shooting: shootingPoseDirection)
                    currentFrameKey = key
                } else if moving, let walkingDirection = playWalkingDirection {
                    switch walkingDirection {
                    case .left:
                        try render(animation: .walkLeft, now: now)
                    case .right:
                        try render(animation: .walkRight, now: now)
                    case .down, .up:
                        guard let verticalDirection = walkingDirection.verticalDirection else { return }
                        try render(verticalWalking: verticalDirection, now: now)
                    }
                } else {
                    let key = "play-direction-\(direction.rawValue)"
                    guard currentFrameKey != key else { return }
                    petView.spriteFrame = try atlas.frame(direction: direction)
                    currentFrameKey = key
                }
            case .idle, .dragging:
                try render(animation: .idle, now: now)
            }
        } catch {
            present(error: error)
        }
    }

    private func render(animation: AnimationID, now: TimeInterval) throws {
        let spec = AnimationCatalog.spec(for: animation)
        let frameIndex = spec.frameIndex(elapsed: now - stateStartedAt)
        let key = "\(animation.rawValue)-\(frameIndex)"
        guard currentFrameKey != key else { return }
        petView.spriteFrame = try atlas.frame(animation: animation, index: frameIndex)
        currentFrameKey = key
    }

    private func render(verticalWalking direction: VerticalWalkingDirection, now: TimeInterval) throws {
        let spec = AnimationCatalog.verticalWalkingSpec(for: direction)
        let frameIndex = spec.frameIndex(elapsed: now - stateStartedAt)
        let key = "vertical-walk-\(direction.rawValue)-\(frameIndex)"
        guard currentFrameKey != key else { return }
        petView.spriteFrame = try atlas.frame(verticalWalking: direction, index: frameIndex)
        currentFrameKey = key
    }

    private func showIdleFrame() {
        do {
            petView.spriteFrame = try atlas.frame(animation: .idle, index: 0)
            currentFrameKey = "idle-0"
        } catch {
            present(error: error)
        }
    }

    private func updateMousePassThrough() {
        guard !isDragging else {
            panel.ignoresMouseEvents = false
            return
        }
        let mouse = NSEvent.mouseLocation
        let windowPoint = panel.convertPoint(fromScreen: mouse)
        let localPoint = petView.convert(windowPoint, from: nil)
        panel.ignoresMouseEvents = !petView.hasVisiblePixel(at: localPoint)
    }

    private func restorePlacement() {
        let screen = screen(identifier: settings.screenIdentifier) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let origin = ScreenBounds(rect: screen.visibleFrame).origin(
            horizontalPosition: settings.horizontalPosition,
            petSize: panel.frame.size
        )
        panel.setFrameOrigin(origin)
    }

    private func persistPlacement() {
        guard let screen = currentScreen() else { return }
        settings.screenIdentifier = identifier(for: screen)
        settings.horizontalPosition = ScreenBounds(rect: screen.visibleFrame).horizontalPosition(
            for: panel.frame.origin,
            petSize: panel.frame.size
        )
        settingsStore.save(settings)
    }

    private func clampToVisibleScreen() {
        guard let screen = currentScreen() ?? NSScreen.main else { return }
        let origin = ScreenBounds(rect: screen.visibleFrame).clampedOrigin(
            panel.frame.origin,
            petSize: panel.frame.size
        )
        panel.setFrameOrigin(origin)
        persistPlacement()
    }

    func handleScreenConfigurationChange() {
        isPlayMode ? clampPlayToVisibleScreen() : clampToVisibleScreen()
    }

    private func currentScreen() -> NSScreen? {
        screen(containing: NSPoint(x: panel.frame.midX, y: panel.frame.midY))
            ?? screen(containing: panel.frame.origin)
            ?? NSScreen.main
    }

    private func showSpeech(_ message: String) {
        guard !isPlayMode, let screen = currentScreen() else { return }
        speechBubble.show(message, anchoredTo: panel.frame, in: screen.visibleFrame)
    }

    private func updateSpeechBubbleAnchor() {
        guard speechBubble.isVisible, let screen = currentScreen() else { return }
        speechBubble.updateAnchor(petFrame: panel.frame, screenFrame: screen.visibleFrame)
    }

    private func checkDueTodos(now: TimeInterval) {
        guard now >= nextTodoCheckAt else { return }
        nextTodoCheckAt = now + 0.75
        guard !isPlayMode else { return }

        let dueItems = TodoPolicy.dueForDelivery(in: todoStore.items, at: Date())
        guard !dueItems.isEmpty else { return }
        do {
            try todoStore.markRemindersDelivered(ids: Set(dueItems.map(\.id)))
            todoWindowController?.reload()
            perform(.observe)
            if dueItems.count == 1, let item = dueItems.first {
                showSpeech("提醒：\(item.title)")
            } else {
                showSpeech("有 \(dueItems.count) 个 Todo 到时间了！")
            }
            synchronizeTodoReminders()
        } catch {
            showSpeech("Todo 提醒保存失败：\(error.localizedDescription)")
        }
    }

    private func synchronizeTodoReminders() {
        todoSyncTask?.cancel()
        let items = todoStore.items
        todoSyncTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                let notificationsEnabled = try await todoReminderCoordinator.synchronize(items)
                guard !Task.isCancelled else { return }
                if !notificationsEnabled, !didExplainNotificationDenial {
                    didExplainNotificationDenial = true
                    showSpeech("系统通知未开启；Isaac 运行时仍会用气泡提醒。")
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                showSpeech("系统提醒设置失败；运行时气泡提醒仍然有效。")
            }
        }
    }

    private func todoWindow() -> TodoWindowController {
        if let todoWindowController { return todoWindowController }
        let controller = TodoWindowController(store: todoStore) { [weak self] in
            self?.synchronizeTodoReminders()
        }
        todoWindowController = controller
        return controller
    }

    private func dailyPlanWindow() -> DailyPlanWindowController {
        if let dailyPlanWindowController { return dailyPlanWindowController }
        let controller = DailyPlanWindowController { [weak self] in
            self?.todoStore.items ?? []
        }
        dailyPlanWindowController = controller
        return controller
    }

    private func tarotWindow() -> TarotWindowController {
        if let tarotWindowController { return tarotWindowController }
        let controller = TarotWindowController()
        tarotWindowController = controller
        return controller
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func identifier(for screen: NSScreen) -> String? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }

    private func screen(identifier: String?) -> NSScreen? {
        guard let identifier else { return nil }
        return NSScreen.screens.first { self.identifier(for: $0) == identifier }
    }

    private func present(error: Error) {
        timer?.invalidate()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.messageText = "Isaac Pet 遇到问题"
        alert.runModal()
    }

    private func clampPlayToVisibleScreen() {
        guard let screen = currentScreen() ?? NSScreen.main else { return }
        let origin = ScreenBounds(rect: screen.visibleFrame).clampedFreeOrigin(
            panel.frame.origin,
            petSize: panel.frame.size
        )
        panel.setFrameOrigin(origin)
        persistPlacement()
    }

    @objc private func togglePlayMode() {
        isPlayMode ? exitPlayMode() : enterPlayMode()
    }

    private func enterPlayMode() {
        guard !isPlayMode else { return }
        isPlayMode = true
        speechBubble.hide()
        targetX = nil
        actionEndsAt = nil
        hoveredSince = nil
        pressedPlayKeys.removeAll()
        playWalkingDirection = nil
        nextShotAt = 0
        shootingPoseDirection = nil
        shootingPoseEndsAt = 0
        transition(to: .playing(playFacing, moving: false), at: ProcessInfo.processInfo.systemUptime)
        installKeyEventMonitor()
        focusPlayControls()
    }

    private func exitPlayMode() {
        guard isPlayMode else { return }
        isPlayMode = false
        pressedPlayKeys.removeAll()
        playWalkingDirection = nil
        shootingPoseDirection = nil
        shootingPoseEndsAt = 0
        removeKeyEventMonitor()
        removeAllProjectiles()
        clampToVisibleScreen()
        transition(to: .idle, at: ProcessInfo.processInfo.systemUptime)
        scheduleNextRoam(now: ProcessInfo.processInfo.systemUptime)
        panel.resignKey()
        NSApp.deactivate()
        panel.orderFrontRegardless()
    }

    private func focusPlayControls() {
        guard isPlayMode else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(petView)
    }

    private func installKeyEventMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, self.isPlayMode else { return event }
            let handled = self.petView(
                self.petView,
                changedKeyCode: event.keyCode,
                isDown: event.type == .keyDown,
                isRepeat: event.isARepeat
            )
            return handled ? nil : event
        }
    }

    private func removeKeyEventMonitor() {
        guard let keyEventMonitor else { return }
        NSEvent.removeMonitor(keyEventMonitor)
        self.keyEventMonitor = nil
    }

    @objc private func toggleRoaming() {
        guard !isPlayMode else { return }
        settings.roamingEnabled.toggle()
        targetX = nil
        transition(to: .idle, at: ProcessInfo.processInfo.systemUptime)
        scheduleNextRoam(now: ProcessInfo.processInfo.systemUptime)
        settingsStore.save(settings)
    }

    @objc private func selectAppearance(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let appearance = PetAppearanceID(rawValue: rawValue) else { return }
        activateAppearance(appearance, announce: true)
    }

    @discardableResult
    private func activateAppearance(
        _ appearance: PetAppearanceID,
        announce: Bool,
        persistUserSelection: Bool = true
    ) -> Bool {
        if appearance == activeAppearance {
            if persistUserSelection {
                preferredAppearance = appearance
                settingsStore.activeAppearance = appearance.rawValue
            }
            return true
        }
        guard PetAppearanceCatalog.availability(appearance).isAvailable else {
            if announce {
                let reason = PetAppearanceCatalog.availability(appearance).unavailableReason
                showSpeech("\(PetAppearanceCatalog.definition(for: appearance).displayName)：\(reason)")
            }
            return false
        }
        let definition = PetAppearanceCatalog.definition(for: appearance)
        do {
            atlas = try SpriteAtlas(
                spriteSheetResource: definition.spriteSheetResource,
                spriteSheetSubdirectory: definition.subdirectory
            )
            activeAppearance = appearance
            if persistUserSelection {
                preferredAppearance = appearance
                settingsStore.activeAppearance = appearance.rawValue
            }
            currentFrameKey = ""
            showIdleFrame()
            if announce { showSpeech("已切换为 \(definition.displayName)。") }
            return true
        } catch {
            if announce { showSpeech("无法加载角色图集：\(error.localizedDescription)") }
            return false
        }
    }

    @discardableResult
    private func activateAgentAppearance(for roleID: AgentRoleID) -> Bool {
        guard let appearance = PetAppearanceID(roleID: roleID) else { return false }
        if activateAppearance(appearance, announce: false, persistUserSelection: false) { return true }
        return activateAppearance(.isaac, announce: false, persistUserSelection: false)
    }

    private func restorePreferredAppearance() {
        guard activeAppearance != preferredAppearance else { return }
        _ = activateAppearance(preferredAppearance, announce: false, persistUserSelection: false)
    }

    @objc private func wave() { perform(.wave) }
    @objc private func jump() { perform(.jump) }
    @objc private func cry() { perform(.cry) }
    @objc private func thumbsUp() { perform(.thumbsUp) }
    @objc private func observe() { perform(.observe) }

    @objc private func sayRandomPhrase() {
        perform(.observe)
        showSpeech(PetSpeechLibrary.randomPhrase())
    }

    @objc private func showRandomExpression() {
        perform(.thumbsUp)
        showSpeech(PetSpeechLibrary.randomExpression())
    }

    @objc private func composeSpeech() {
        guard !isPlayMode else { return }
        targetX = nil

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "输入文字或颜文字（最多 80 字）"
        let alert = NSAlert()
        alert.messageText = "让 Isaac 说什么？"
        alert.informativeText = "内容只会显示在本机桌面，不会上传。"
        alert.accessoryView = input
        alert.addButton(withTitle: "显示气泡")
        alert.addButton(withTitle: "取消")

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = input
        let response = alert.runModal()
        panel.orderFrontRegardless()
        NSApp.deactivate()
        guard response == .alertFirstButtonReturn else { return }
        showSpeech(input.stringValue)
    }

    @objc private func configureLLM() {
        guard !isPlayMode, llmTask == nil else { return }
        targetX = nil
        NSApp.activate(ignoringOtherApps: true)
        let existingToken: String?
        do {
            existingToken = try llmCredentialStore.loadToken()
            settingsStore.llmCredentialConfigured = existingToken != nil
        } catch {
            presentLLMMessage(title: "无法读取 LLM 设置", message: error.localizedDescription)
            return
        }

        let tokenField = NSSecureTextField(string: "")
        tokenField.placeholderString = existingToken == nil ? "sk-…" : "已保存在钥匙串；留空保持不变"
        let modelField = NSTextField(string: settingsStore.llmModel)
        let tokenLabel = NSTextField(labelWithString: "API Key")
        let modelLabel = NSTextField(labelWithString: "模型")
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 70))
        tokenLabel.frame = NSRect(x: 0, y: 42, width: 72, height: 22)
        tokenField.frame = NSRect(x: 80, y: 39, width: 380, height: 26)
        modelLabel.frame = NSRect(x: 0, y: 7, width: 72, height: 22)
        modelField.frame = NSRect(x: 80, y: 4, width: 250, height: 26)
        for view in [tokenLabel, tokenField, modelLabel, modelField] { accessory.addSubview(view) }

        let alert = NSAlert()
        alert.messageText = "可选 LLM 连接"
        alert.informativeText = "默认关闭。API Key 仅保存在 macOS 钥匙串；只有你主动点击“问 Isaac”时，输入文字才会发送到 api.openai.com。不会发送 Todo、Notion 内容或桌面数据。"
        alert.accessoryView = accessory
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "断开")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        panel.orderFrontRegardless()
        guard response != .alertThirdButtonReturn else { return }
        if response == .alertSecondButtonReturn {
            disconnectLLM()
            return
        }

        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !model.contains(where: \.isWhitespace) else {
            presentLLMMessage(title: "模型名称无效", message: "请输入一个不含空格的模型 ID。")
            return
        }
        do {
            let newToken = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newToken.isEmpty {
                try llmCredentialStore.saveToken(newToken)
                settingsStore.llmCredentialConfigured = true
            } else if existingToken == nil {
                throw LLMCredentialError.emptyToken
            }
            settingsStore.llmModel = String(model.prefix(100))
            showSpeech("LLM 设置已保存。只有主动提问才会联网。")
        } catch {
            presentLLMMessage(title: "无法保存 LLM 设置", message: error.localizedDescription)
        }
    }

    @objc private func disconnectLLM() {
        guard llmTask == nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        do {
            try llmCredentialStore.deleteToken()
            settingsStore.llmCredentialConfigured = false
            showSpeech("LLM 已断开，本地功能不受影响。")
        } catch {
            presentLLMMessage(title: "无法断开 LLM", message: error.localizedDescription)
        }
    }

    @objc private func askLLM() {
        guard !isPlayMode, llmTask == nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        let token: String
        do {
            guard let storedToken = try llmCredentialStore.loadToken() else {
                settingsStore.llmCredentialConfigured = false
                configureLLM()
                return
            }
            settingsStore.llmCredentialConfigured = true
            token = storedToken
        } catch {
            presentLLMMessage(title: "无法读取 API Key", message: error.localizedDescription)
            return
        }

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 26))
        inputField.placeholderString = "输入一个问题（最多 500 字）"
        let alert = NSAlert()
        alert.messageText = "问 Isaac"
        alert.informativeText = "下面的文字会发送到 api.openai.com；不会附带 Todo、Notion 内容、文件或历史对话。"
        alert.accessoryView = inputField
        alert.addButton(withTitle: "发送")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = inputField
        let response = alert.runModal()
        panel.orderFrontRegardless()
        guard response == .alertFirstButtonReturn else { return }
        let input = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            showSpeech("先写点什么再问我吧。")
            return
        }
        let boundedInput = String(input.prefix(500))
        perform(.observe)
        showSpeech("让我想想…")
        llmTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let answer = try await llmClient.respond(
                    to: boundedInput,
                    model: settingsStore.llmModel,
                    token: token
                )
                try Task.checkCancellation()
                llmTask = nil
                perform(.thumbsUp)
                showSpeech(answer)
            } catch is CancellationError {
                llmTask = nil
                showSpeech("LLM 请求已取消。")
            } catch {
                llmTask = nil
                showSpeech("LLM 请求失败：\(error.localizedDescription)")
            }
        }
    }

    @objc private func cancelLLMRequest() {
        llmTask?.cancel()
    }

    private func presentLLMMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
        panel.orderFrontRegardless()
    }

    @objc private func addTodo() {
        guard !isPlayMode else { return }
        targetX = nil
        todoWindow().present(focusComposer: true)
    }

    @objc private func showTodoList() {
        guard !isPlayMode else { return }
        targetX = nil
        todoWindow().present()
    }

    @objc private func showDailyPlan() {
        guard !isPlayMode else { return }
        targetX = nil
        dailyPlanWindow().present()
    }

    @objc private func showTarot() {
        guard !isPlayMode else { return }
        targetX = nil
        perform(.observe)
        tarotWindow().present()
    }

    @objc private func showNextTodo() {
        guard !isPlayMode else { return }
        guard let todo = TodoPolicy.nextPending(in: todoStore.items) else {
            showSpeech("Todo 已清空！ :)")
            return
        }
        let dueText = todo.dueAt == nil ? "" : " · \(TodoFormatting.dueText(for: todo))"
        perform(.observe)
        showSpeech("下一项：\(todo.title)\(dueText)")
    }

    @objc private func syncAppleReminders() {
        guard !isPlayMode, appleRemindersSyncTask == nil else { return }
        targetX = nil
        NSApp.activate(ignoringOtherApps: true)

        appleRemindersSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                appleRemindersSyncTask = nil
                panel.orderFrontRegardless()
                if todoWindowController?.window?.isVisible != true { NSApp.deactivate() }
            }
            do {
                let granted = try await appleRemindersAdapter.requestReadAccess()
                guard granted else {
                    presentAppleRemindersMessage(
                        title: "未获得提醒事项权限",
                        message: "可在“系统设置 → 隐私与安全性 → 提醒事项”中允许 Isaac Pet 读取。应用不会修改或删除系统提醒事项。"
                    )
                    return
                }

                let lists = try appleRemindersAdapter.reminderLists()
                guard let choice = chooseAppleReminderList(from: lists) else { return }
                settingsStore.appleReminderCalendarIdentifier = choice
                let knownIdentifiers = Set(todoStore.items.compactMap { item -> String? in
                    guard item.externalSource?.kind == .appleReminders else { return nil }
                    return item.externalSource?.itemIdentifier
                })
                let records = try await appleRemindersAdapter.fetchRecords(
                    calendarIdentifier: choice,
                    knownItemIdentifiers: knownIdentifiers
                )
                let summary = try todoStore.importExternalRecords(records)
                todoWindowController?.reload()
                synchronizeTodoReminders()
                perform(.observe)
                showSpeech("提醒事项同步完成：新增 \(summary.inserted)，更新 \(summary.updated)。")
            } catch {
                presentAppleRemindersMessage(
                    title: "无法同步 Apple 提醒事项",
                    message: error.localizedDescription
                )
            }
        }
    }

    /// Returns `.some(nil)` for all lists, `.some(id)` for one list, and `nil` for cancel.
    private func chooseAppleReminderList(from lists: [AppleReminderList]) -> String?? {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        popup.addItem(withTitle: "所有列表")
        for list in lists {
            popup.addItem(withTitle: list.title)
            popup.lastItem?.representedObject = list.identifier
        }
        if let selected = settingsStore.appleReminderCalendarIdentifier,
           let index = popup.itemArray.firstIndex(where: { $0.representedObject as? String == selected }) {
            popup.selectItem(at: index)
        }

        let alert = NSAlert()
        alert.messageText = "同步 Apple 提醒事项"
        alert.informativeText = "选择要读取的列表。同步只会导入或更新 Isaac 本地 Todo，不会改写 Apple“提醒事项”。"
        alert.accessoryView = popup
        alert.addButton(withTitle: "开始同步")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return .some(popup.selectedItem?.representedObject as? String)
    }

    private func presentAppleRemindersMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func syncNotion() {
        guard !isPlayMode, notionSyncTask == nil else { return }
        do {
            guard let token = try notionCredentialStore.loadToken(),
                  let dataSourceID = settingsStore.notionDataSourceIdentifier else {
                configureNotion()
                return
            }
            startNotionSync(token: token, dataSourceID: dataSourceID)
        } catch {
            presentNotionMessage(title: "无法读取 Notion 设置", message: error.localizedDescription)
        }
    }

    @objc private func configureNotion() {
        guard !isPlayMode, notionSyncTask == nil else { return }
        targetX = nil
        NSApp.activate(ignoringOtherApps: true)
        do {
            let existingToken = try notionCredentialStore.loadToken()
            guard let configuration = presentNotionConfiguration(hasSavedToken: existingToken != nil) else {
                panel.orderFrontRegardless()
                NSApp.deactivate()
                return
            }
            let token: String
            if configuration.token.isEmpty {
                guard let existingToken else { throw NotionCredentialError.emptyToken }
                token = existingToken
            } else {
                try notionCredentialStore.saveToken(configuration.token)
                token = configuration.token.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let dataSourceID = NotionDataSourceIdentifier.normalized(configuration.dataSourceID) else {
                throw NotionTodoAdapterError.invalidDataSourceIdentifier
            }
            settingsStore.notionDataSourceIdentifier = dataSourceID
            if configuration.shouldSync {
                startNotionSync(token: token, dataSourceID: dataSourceID)
            } else {
                showSpeech("Notion 设置已保存到本机。")
                panel.orderFrontRegardless()
                NSApp.deactivate()
            }
        } catch {
            presentNotionMessage(title: "无法保存 Notion 设置", message: error.localizedDescription)
            panel.orderFrontRegardless()
            NSApp.deactivate()
        }
    }

    @objc private func disconnectNotion() {
        guard !isPlayMode, notionSyncTask == nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "断开 Notion？"
        alert.informativeText = "这会从 macOS 钥匙串移除访问令牌并清除 data source ID。已经导入的本地 Todo 不会删除。"
        alert.addButton(withTitle: "断开")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            NSApp.deactivate()
            return
        }
        do {
            try notionCredentialStore.deleteToken()
            settingsStore.notionDataSourceIdentifier = nil
            showSpeech("Notion 已断开，本地 Todo 保留。")
        } catch {
            presentNotionMessage(title: "无法断开 Notion", message: error.localizedDescription)
        }
        panel.orderFrontRegardless()
        NSApp.deactivate()
    }

    private func startNotionSync(token: String, dataSourceID: String) {
        guard notionSyncTask == nil else { return }
        targetX = nil
        notionSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                notionSyncTask = nil
                panel.orderFrontRegardless()
                if todoWindowController?.window?.isVisible != true { NSApp.deactivate() }
            }
            do {
                let knownIdentifiers = Set(todoStore.items.compactMap { item -> String? in
                    guard item.externalSource?.kind == .notion else { return nil }
                    return item.externalSource?.itemIdentifier
                })
                let result = try await notionTodoAdapter.fetchRecords(
                    token: token,
                    rawDataSourceIdentifier: dataSourceID,
                    knownItemIdentifiers: knownIdentifiers
                )
                guard !Task.isCancelled else { return }
                settingsStore.notionDataSourceIdentifier = result.dataSourceIdentifier
                let summary = try todoStore.importExternalRecords(result.records)
                todoWindowController?.reload()
                synchronizeTodoReminders()
                perform(.observe)
                showSpeech("Notion 同步完成：新增 \(summary.inserted)，更新 \(summary.updated)。")
            } catch is CancellationError {
                return
            } catch {
                presentNotionMessage(title: "无法同步 Notion", message: error.localizedDescription)
            }
        }
    }

    private func presentNotionConfiguration(hasSavedToken: Bool) -> (
        token: String,
        dataSourceID: String,
        shouldSync: Bool
    )? {
        let tokenField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        tokenField.placeholderString = hasSavedToken
            ? "已保存在钥匙串（留空保持原令牌）"
            : "Notion internal integration token"
        let dataSourceField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        dataSourceField.placeholderString = "Data source ID 或包含 ID 的链接"
        dataSourceField.stringValue = settingsStore.notionDataSourceIdentifier ?? ""

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: 64))
        let tokenLabel = NSTextField(labelWithString: "Token")
        tokenLabel.frame = NSRect(x: 0, y: 38, width: 100, height: 22)
        tokenLabel.alignment = .right
        tokenField.frame = NSRect(x: 110, y: 36, width: 320, height: 24)
        let dataSourceLabel = NSTextField(labelWithString: "Data source")
        dataSourceLabel.frame = NSRect(x: 0, y: 4, width: 100, height: 22)
        dataSourceLabel.alignment = .right
        dataSourceField.frame = NSRect(x: 110, y: 2, width: 320, height: 24)
        for view in [tokenLabel, tokenField, dataSourceLabel, dataSourceField] {
            accessory.addSubview(view)
        }

        let alert = NSAlert()
        alert.messageText = "Notion 只读连接"
        alert.informativeText = "令牌只保存在 macOS 钥匙串，并仅在手动同步时发送到 api.notion.com。请先把目标 data source 共享给对应 integration。"
        alert.accessoryView = accessory
        alert.addButton(withTitle: "保存并同步")
        alert.addButton(withTitle: "仅保存")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        guard response != .alertThirdButtonReturn else { return nil }
        return (
            tokenField.stringValue,
            dataSourceField.stringValue,
            response == .alertFirstButtonReturn
        )
    }

    private func presentNotionMessage(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func showAgentCenter() {
        guard !isPlayMode else { return }
        targetX = nil
        NSApp.activate(ignoringOtherApps: true)
        agentWindow().present()
    }

    private func agentWindow() -> AgentWindowController {
        if let agentWindowController { return agentWindowController }
        let controller = AgentWindowController(
            auditStore: agentAuditStore,
            onRunRole: { [weak self] roleID in self?.runAgent(roleID: roleID) },
            onRequestTodoProposal: { [weak self] in self?.requestTodoWithJudas() },
            onCancelTask: { [weak self] id in self?.cancelAgentTask(id: id) }
        )
        agentWindowController = controller
        return controller
    }

    @objc private func runDailyPlanAgent() {
        runAgent(roleID: .isaac)
    }

    @objc private func runWellbeingAgent() {
        runAgent(roleID: .magdalene)
    }

    @objc private func runFocusAgent() {
        runAgent(roleID: .judas)
    }

    @objc private func requestTodoWithJudas() {
        guard !isPlayMode, activeAgentTask == nil else { return }
        let role = AgentCatalog.profile(for: .judas)
        guard AgentExecutionPolicy.authorization(for: .writeLocalTodos, role: role) == .requiresConfirmation else {
            showSpeech("Judas 当前没有创建 Todo 的权限。")
            return
        }

        _ = activateAgentAppearance(for: .judas)
        defer { restorePreferredAppearance() }

        let titleField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
        titleField.placeholderString = "例如：整理报告大纲"
        let inputAlert = NSAlert()
        inputAlert.messageText = "Judas 提议创建本地 Todo"
        inputAlert.informativeText = "先输入要创建的任务。下一步仍会要求你明确确认，Judas 不会自行写入。"
        inputAlert.accessoryView = titleField
        inputAlert.addButton(withTitle: "继续")
        inputAlert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard inputAlert.runModal() == .alertFirstButtonReturn else { return }
        guard let title = TodoPolicy.normalizedTitle(titleField.stringValue) else {
            showSpeech("Todo 标题不能为空。")
            return
        }
        confirmJudasTodoProposal(title: title)
    }

    private func confirmJudasTodoProposal(title: String) {
        do {
            let task = try agentAuditStore.createTask(
                roleID: .judas,
                capability: .writeLocalTodos,
                title: "创建 Todo：\(title)"
            )
            try agentAuditStore.transition(
                taskID: task.id,
                to: .awaitingConfirmation,
                summary: "Judas 请求创建本地 Todo：\(title)"
            )
            agentWindowController?.reload()

            let confirmation = NSAlert()
            confirmation.messageText = "允许 Judas 创建本地 Todo？"
            confirmation.informativeText = "将仅写入 Isaac Pet 的本地 Todo：\n\n\(title)\n\n不会修改 Apple 提醒事项、Notion 或其他应用。"
            confirmation.alertStyle = .warning
            confirmation.addButton(withTitle: "创建 Todo")
            confirmation.addButton(withTitle: "取消")
            let approved = confirmation.runModal() == .alertFirstButtonReturn
            if !approved {
                try agentAuditStore.transition(
                    taskID: task.id,
                    to: .cancelled,
                    summary: "用户拒绝创建本地 Todo"
                )
                agentWindowController?.reload()
                showSpeech("已取消创建 Todo。")
                return
            }

            do {
                _ = try todoStore.add(title: title, dueAt: nil)
                try agentAuditStore.transition(
                    taskID: task.id,
                    to: .succeeded,
                    summary: "已按用户确认创建本地 Todo：\(title)"
                )
                agentWindowController?.reload()
                synchronizeTodoReminders()
                showSpeech("Judas 已创建 Todo：\(title)")
            } catch {
                _ = try? agentAuditStore.transition(
                    taskID: task.id,
                    to: .failed,
                    summary: "用户已确认，但本地 Todo 创建失败：\(error.localizedDescription)"
                )
                agentWindowController?.reload()
                showSpeech("无法创建 Todo：\(error.localizedDescription)")
            }
        } catch {
            showSpeech("无法创建 Todo：\(error.localizedDescription)")
        }
    }

    private func runAgent(roleID: AgentRoleID) {
        _ = activateAgentAppearance(for: roleID)
        switch roleID {
        case .isaac:
            startReadOnlyAgent(
                roleID: .isaac,
                title: "读取本地 Todo 并生成今日计划",
                runningSummary: "Isaac 正在只读分析本地 Todo",
                runningSpeech: "Isaac Planner 正在整理今日计划…",
                onFinished: { [weak self] in self?.restorePreferredAppearance() }
            ) { [weak self] taskID in
                guard let self else { return }
                let plan = LocalPlanningAgent.makeDailyPlan(from: todoStore.items)
                let result = ([plan.headline] + plan.steps).joined(separator: "\n")
                try agentAuditStore.transition(taskID: taskID, to: .succeeded, summary: result)
                presentDailyPlan(plan)
                perform(.thumbsUp)
                showSpeech(plan.headline)
            }
        case .magdalene:
            startReadOnlyAgent(
                roleID: .magdalene,
                title: "读取本地 Todo 并检查今日节奏",
                runningSummary: "Magdalene 正在只读评估今日任务密度",
                runningSpeech: "Magdalene 正在看看今天的节奏…",
                onFinished: { [weak self] in self?.restorePreferredAppearance() }
            ) { [weak self] taskID in
                guard let self else { return }
                let plan = LocalWellbeingAgent.makeRhythmCheck(from: todoStore.items)
                let result = ([plan.headline] + plan.suggestions).joined(separator: "\n")
                try agentAuditStore.transition(taskID: taskID, to: .succeeded, summary: result)
                presentWellbeingPlan(plan)
                perform(.wave)
                showSpeech(plan.headline)
            }
        case .judas:
            presentFocusComposer()
            if activeAgentTask == nil { restorePreferredAppearance() }
        case .cain:
            showSpeech("这个角色的工作流还没有开放。")
            restorePreferredAppearance()
        }
    }

    private func presentFocusComposer() {
        guard !isPlayMode, activeAgentTask == nil else { return }
        let targetField = NSTextField(string: "")
        targetField.placeholderString = "可选，例如：完成报告初稿"
        let durationPopup = NSPopUpButton()
        for (title, seconds) in [("25 分钟", 1500.0), ("15 分钟", 900.0), ("45 分钟", 2700.0)] {
            durationPopup.addItem(withTitle: title)
            durationPopup.lastItem?.representedObject = seconds
        }
        if ProcessInfo.processInfo.environment["ISAAC_FOCUS_DURATION_SECONDS"] != nil {
            durationPopup.addItem(withTitle: "测试时长")
            durationPopup.lastItem?.representedObject = FocusSessionPolicy.duration(
                from: ProcessInfo.processInfo.environment["ISAAC_FOCUS_DURATION_SECONDS"]
            )
            durationPopup.selectItem(at: durationPopup.numberOfItems - 1)
        }

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: 70))
        let targetLabel = NSTextField(labelWithString: "专注目标")
        let durationLabel = NSTextField(labelWithString: "时长")
        targetLabel.frame = NSRect(x: 0, y: 42, width: 72, height: 22)
        targetField.frame = NSRect(x: 80, y: 39, width: 350, height: 26)
        durationLabel.frame = NSRect(x: 0, y: 7, width: 72, height: 22)
        durationPopup.frame = NSRect(x: 80, y: 4, width: 160, height: 28)
        for view in [targetLabel, targetField, durationLabel, durationPopup] { accessory.addSubview(view) }

        let alert = NSAlert()
        alert.messageText = "Judas 专注计时"
        alert.informativeText = "计时完全在本机运行。开始后可以在 Agent 中心查看剩余时间或随时取消。"
        alert.accessoryView = accessory
        alert.addButton(withTitle: "开始专注")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let target = normalizedFocusTarget(targetField.stringValue)
        let duration = (durationPopup.selectedItem?.representedObject as? NSNumber)?.doubleValue
            ?? FocusSessionPolicy.defaultDuration
        startFocusSession(target: target, duration: duration)
    }

    private func startFocusSession(target: String?, duration: TimeInterval) {
        guard !isPlayMode, activeAgentTask == nil else { return }
        let role = AgentCatalog.profile(for: .judas)
        let capability: AgentCapability = .focusTimer
        guard AgentExecutionPolicy.authorization(for: capability, role: role) == .automatic else {
            showSpeech("Judas 当前没有专注计时权限。")
            return
        }
        let safeDuration = min(max(duration, 1), FocusSessionPolicy.maximumDuration)
        let deadline = Date().addingTimeInterval(safeDuration)
        let durationText = FocusSessionPolicy.durationText(safeDuration)
        let subjectText = target.map { "：\($0)" } ?? ""
        do {
            let task = try agentAuditStore.createTask(
                roleID: .judas,
                capability: capability,
                title: "专注 \(durationText)\(subjectText)",
                deadlineAt: deadline,
                subject: target
            )
            activeAgentTaskID = task.id
            try agentAuditStore.transition(
                taskID: task.id,
                to: .running,
                summary: "Judas 已开始本地专注计时（\(durationText)）"
            )
            agentWindowController?.reload()
            perform(.observe)
            showSpeech("专注开始！\(durationText)后见。")
            beginFocusCountdown(taskID: task.id, deadline: deadline, target: target)
        } catch {
            showSpeech("无法开始专注：\(error.localizedDescription)")
        }
    }

    private func beginFocusCountdown(taskID: UUID, deadline: Date, target: String?) {
        activeAgentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = Task { [agentReminderCoordinator] in
                    try? await agentReminderCoordinator.scheduleFocusCompletion(
                        taskID: taskID, target: target, deadline: deadline
                    )
                }
                try await FocusSessionTimer.wait(until: deadline)
                let result = target.map { "专注完成：\($0)" } ?? "专注时段已完成"
                _ = try agentAuditStore.transition(taskID: taskID, to: .succeeded, summary: result)
                finishAgentTask()
                presentFocusCompletion(target: target)
                perform(.thumbsUp)
                showSpeech("专注完成！起来休息一下吧。")
                restorePreferredAppearance()
            } catch is CancellationError {
                // The notification request runs independently so a pending macOS permission
                // dialog cannot block cancellation of the local countdown.
                agentReminderCoordinator.removeFocusCompletion(taskID: taskID)
                _ = try? agentAuditStore.transition(taskID: taskID, to: .cancelled, summary: "用户取消了专注计时")
                activeAgentTask = nil
                activeAgentTaskID = nil
                agentWindowController?.reload()
                showSpeech("专注计时已取消。")
                restorePreferredAppearance()
            } catch {
                agentReminderCoordinator.removeFocusCompletion(taskID: taskID)
                _ = try? agentAuditStore.transition(taskID: taskID, to: .failed, summary: error.localizedDescription)
                activeAgentTask = nil
                activeAgentTaskID = nil
                agentWindowController?.reload()
                showSpeech("专注计时失败：\(error.localizedDescription)")
                restorePreferredAppearance()
            }
        }
    }

    private func restoreActiveAgentTask() {
        var resumedFocus = false
        let now = Date()
        for task in agentAuditStore.tasks where [.queued, .running, .awaitingConfirmation].contains(task.status) {
            guard task.capability == .focusTimer, let deadline = task.deadlineAt else {
                _ = try? agentAuditStore.transition(
                    taskID: task.id,
                    to: .cancelled,
                    summary: "App 重启后清理了无法恢复的旧任务"
                )
                continue
            }
            if deadline <= now {
                let finalStatus: AgentTaskStatus = task.status == .running ? .succeeded : .cancelled
                let summary = finalStatus == .succeeded
                    ? "专注时段在 App 未运行期间结束"
                    : "App 重启后清理了未开始的过期专注任务"
                _ = try? agentAuditStore.transition(taskID: task.id, to: finalStatus, summary: summary)
                continue
            }
            guard !resumedFocus else {
                _ = try? agentAuditStore.transition(
                    taskID: task.id,
                    to: .cancelled,
                    summary: "App 重启后清理了重复的专注任务"
                )
                continue
            }
            resumedFocus = true
            activeAgentTaskID = task.id
            _ = activateAgentAppearance(for: .judas)
            if task.status != .running {
                _ = try? agentAuditStore.transition(taskID: task.id, to: .running, summary: "App 重启后恢复了专注计时")
            }
            beginFocusCountdown(taskID: task.id, deadline: deadline, target: task.subject)
        }
        if resumedFocus { showSpeech("Judas 已恢复专注计时。") }
    }

    private func refreshAgentUI(now: TimeInterval) {
        guard now >= nextAgentUIRefreshAt else { return }
        nextAgentUIRefreshAt = now + 1
        agentWindowController?.refreshActiveTask()
    }

    private func normalizedFocusTarget(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return String(value.prefix(80))
    }

    private func startReadOnlyAgent(
        roleID: AgentRoleID,
        title: String,
        runningSummary: String,
        runningSpeech: String,
        onFinished: @escaping @MainActor () -> Void,
        work: @escaping @MainActor (UUID) throws -> Void
    ) {
        guard !isPlayMode, activeAgentTask == nil else {
            onFinished()
            return
        }
        let role = AgentCatalog.profile(for: roleID)
        let capability: AgentCapability = .readLocalTodos
        guard AgentExecutionPolicy.authorization(for: capability, role: role) == .automatic else {
            showSpeech("\(role.displayName) 当前没有所需权限。")
            onFinished()
            return
        }
        do {
            let task = try agentAuditStore.createTask(
                roleID: roleID,
                capability: capability,
                title: title
            )
            activeAgentTaskID = task.id
            try agentAuditStore.transition(
                taskID: task.id,
                to: .running,
                summary: runningSummary
            )
            agentWindowController?.reload()
            perform(.observe)
            showSpeech(runningSpeech)

            activeAgentTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    // A small suspension keeps task state visible and makes cancellation meaningful.
                    try await Task.sleep(for: .milliseconds(350))
                    try Task.checkCancellation()
                    try work(task.id)
                    finishAgentTask()
                    onFinished()
                } catch is CancellationError {
                    _ = try? agentAuditStore.transition(
                        taskID: task.id,
                        to: .cancelled,
                        summary: "用户取消了任务"
                    )
                    activeAgentTask = nil
                    activeAgentTaskID = nil
                    agentWindowController?.reload()
                    showSpeech("Agent 任务已取消。")
                    onFinished()
                } catch {
                    _ = try? agentAuditStore.transition(
                        taskID: task.id,
                        to: .failed,
                        summary: error.localizedDescription
                    )
                    activeAgentTask = nil
                    activeAgentTaskID = nil
                    agentWindowController?.reload()
                    showSpeech("Agent 任务失败：\(error.localizedDescription)")
                    onFinished()
                }
            }
        } catch {
            showSpeech("无法创建 Agent 任务：\(error.localizedDescription)")
            onFinished()
        }
    }

    private func finishAgentTask() {
        activeAgentTask = nil
        activeAgentTaskID = nil
        agentWindowController?.reload()
    }

    @objc private func cancelActiveAgentTask() {
        guard let id = activeAgentTaskID else { return }
        cancelAgentTask(id: id)
    }

    private func cancelAgentTask(id: UUID) {
        guard id == activeAgentTaskID else { return }
        activeAgentTask?.cancel()
    }

    private func presentDailyPlan(_ plan: DailyPlan) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Isaac 的今日计划"
        alert.informativeText = plan.headline + "\n\n" + plan.steps.enumerated().map {
            "\($0.offset + 1). \($0.element)"
        }.joined(separator: "\n")
        alert.addButton(withTitle: "知道了")
        alert.runModal()
        panel.orderFrontRegardless()
        if agentWindowController?.window?.isVisible != true { NSApp.deactivate() }
    }

    private func presentWellbeingPlan(_ plan: WellbeingPlan) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Magdalene 的节奏检查"
        alert.informativeText = plan.headline + "\n\n" + plan.suggestions.enumerated().map {
            "\($0.offset + 1). \($0.element)"
        }.joined(separator: "\n")
        alert.addButton(withTitle: "知道了")
        alert.runModal()
        panel.orderFrontRegardless()
        if agentWindowController?.window?.isVisible != true { NSApp.deactivate() }
    }

    private func presentFocusCompletion(target: String?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Judas：专注完成"
        let subject = target.map { "\n\n目标：\($0)" } ?? ""
        alert.informativeText = "起来休息一下，再决定下一步。\(subject)\n系统通知会在允许时触发，桌面气泡始终有效。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
        panel.orderFrontRegardless()
        if agentWindowController?.window?.isVisible != true { NSApp.deactivate() }
    }

    @objc private func changeScale(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        let oldFrame = panel.frame
        settings.scale = PetSettings.validScale(value)
        let size = NSSize(
            width: Self.baseSize.width * settings.scale,
            height: Self.baseSize.height * settings.scale
        )
        let origin = NSPoint(x: oldFrame.midX - size.width / 2, y: oldFrame.minY)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        petView.frame = NSRect(origin: .zero, size: size)
        isPlayMode ? clampPlayToVisibleScreen() : clampToVisibleScreen()
        settingsStore.save(settings)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert(error: error)
            alert.messageText = "无法更改登录启动设置"
            alert.informativeText = "请先把 Isaac Pet 安装到“应用程序”文件夹，再重试。\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    @objc private func returnToMainScreen() {
        guard let screen = NSScreen.main else { return }
        settings.screenIdentifier = identifier(for: screen)
        settings.horizontalPosition = 0.82
        let origin = ScreenBounds(rect: screen.visibleFrame).origin(
            horizontalPosition: settings.horizontalPosition,
            petSize: panel.frame.size
        )
        panel.setFrameOrigin(origin)
        settingsStore.save(settings)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func petViewDidSingleClick(_ view: PetView) {
        isPlayMode ? focusPlayControls() : perform(.wave)
    }
    func petViewDidDoubleClick(_ view: PetView) {
        isPlayMode ? focusPlayControls() : perform(.jump)
    }

    func petViewDidBeginDragging(_ view: PetView) {
        isDragging = true
        pressedPlayKeys.removeAll()
        playWalkingDirection = nil
        targetX = nil
        actionEndsAt = nil
        transition(to: .dragging, at: ProcessInfo.processInfo.systemUptime)
        panel.ignoresMouseEvents = false
    }

    func petView(_ view: PetView, draggedTo windowOrigin: NSPoint) {
        panel.setFrameOrigin(windowOrigin)
    }

    func petViewDidEndDragging(_ view: PetView) {
        isDragging = false
        if isPlayMode {
            clampPlayToVisibleScreen()
            transition(to: .playing(playFacing, moving: false), at: ProcessInfo.processInfo.systemUptime)
            focusPlayControls()
        } else {
            clampToVisibleScreen()
            transition(to: .idle, at: ProcessInfo.processInfo.systemUptime)
            scheduleNextRoam(now: ProcessInfo.processInfo.systemUptime)
        }
    }

    func petView(_ view: PetView, showContextMenu event: NSEvent) {
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func petView(_ view: PetView, changedKeyCode keyCode: UInt16, isDown: Bool, isRepeat: Bool) -> Bool {
        guard isPlayMode, let key = PlayKey(rawValue: keyCode) else { return false }
        if key == .escape, isDown {
            exitPlayMode()
            return true
        }
        guard !isRepeat else { return true }
        if isDown {
            let inserted = pressedPlayKeys.insert(key).inserted
            if inserted, [.shootUp, .shootRight, .shootDown, .shootLeft].contains(key) {
                let now = ProcessInfo.processInfo.systemUptime
                if let direction = PlayInput.firingDirection(for: pressedPlayKeys) {
                    playFacing = direction
                    spawnTear(direction: direction, now: now)
                    nextShotAt = now + 0.22
                    transition(to: .playing(direction, moving: false), at: now)
                }
            }
        } else {
            pressedPlayKeys.remove(key)
        }
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isPlayMode else { return }
        pressedPlayKeys.removeAll()
        playWalkingDirection = nil
        transition(to: .playing(playFacing, moving: false), at: ProcessInfo.processInfo.systemUptime)
    }
}
