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
    private let atlas: SpriteAtlas
    private let tearFrame: SpriteFrame
    private let settingsStore: SettingsStore
    private let menu = NSMenu(title: "Isaac Pet")
    private let statusItem: NSStatusItem

    private var settings: PetSettings
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

    init(atlas: SpriteAtlas, settingsStore: SettingsStore) throws {
        self.atlas = atlas
        tearFrame = try atlas.tearFrame()
        self.settingsStore = settingsStore
        settings = settingsStore.load()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let size = NSSize(
            width: Self.baseSize.width * settings.scale,
            height: Self.baseSize.height * settings.scale
        )
        petView = PetView(frame: NSRect(origin: .zero, size: size))
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
        startTimer()
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
        menu.item(withTag: 200)?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        for item in menu.items.compactMap(\.submenu).flatMap(\.items) {
            if [75, 100, 125].contains(item.tag) {
                item.state = abs(CGFloat(item.tag) / 100 - settings.scale) < 0.01 ? .on : .off
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
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        removeKeyEventMonitor()
        removeAllProjectiles()
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

    @objc private func wave() { perform(.wave) }
    @objc private func jump() { perform(.jump) }
    @objc private func cry() { perform(.cry) }
    @objc private func thumbsUp() { perform(.thumbsUp) }
    @objc private func observe() { perform(.observe) }

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
