import AppKit
import IsaacPetCore

@MainActor
final class AgentWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private enum Row: Equatable {
        case task(AgentTask)
        case empty
    }

    private let auditStore: AgentAuditStore
    private let onRunRole: (AgentRoleID) -> Void
    private let onRequestTodoProposal: () -> Void
    private let onCancelTask: (UUID) -> Void
    private let rolePopup = NSPopUpButton()
    private let rolePortraitView = NSImageView()
    private let specialtyLabel = NSTextField(wrappingLabelWithString: "")
    private let capabilityLabel = NSTextField(wrappingLabelWithString: "")
    private let activeStatusLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let runButton = NSButton(title: "生成今日计划", target: nil, action: nil)
    private let proposalButton = NSButton(title: "创建 Todo（需确认）", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消任务", target: nil, action: nil)
    private var rows: [Row] = []
    private var lastActiveStatusText = ""

    init(
        auditStore: AgentAuditStore,
        onRunRole: @escaping (AgentRoleID) -> Void,
        onRequestTodoProposal: @escaping () -> Void,
        onCancelTask: @escaping (UUID) -> Void
    ) {
        self.auditStore = auditStore
        self.onRunRole = onRunRole
        self.onRequestTodoProposal = onRequestTodoProposal
        self.onCancelTask = onCancelTask

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Isaac Agents"
        window.minSize = NSSize(width: 600, height: 430)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        super.init(window: window)
        window.delegate = self
        configureContent()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func reload() {
        rows = auditStore.tasks.isEmpty ? [.empty] : auditStore.tasks.prefix(100).map(Row.task)
        tableView.reloadData()
        if let activeIndex = rows.firstIndex(where: { row in
            guard case let .task(task) = row else { return false }
            return Self.activeStatuses.contains(task.status)
        }) {
            tableView.selectRowIndexes(IndexSet(integer: activeIndex), byExtendingSelection: false)
        }
        updateRoleDescription()
        refreshActiveTask()
        updateSelection()
    }

    func refreshActiveTask(now: Date = Date()) {
        let activeTask = auditStore.tasks.first(where: { Self.activeStatuses.contains($0.status) })
        let text: String
        if let task = activeTask, task.capability == .focusTimer, let deadline = task.deadlineAt {
            let remaining = FocusSessionPolicy.remainingSeconds(until: deadline, now: now)
            let target = task.subject.map { " · \($0)" } ?? ""
            text = "FOCUS \(FocusSessionPolicy.clockText(remainingSeconds: remaining))\(target)"
        } else if let task = activeTask {
            text = "RUNNING · \(AgentCatalog.profile(for: task.roleID).displayName) · \(task.title)"
        } else {
            text = "IDLE · 当前没有运行中的 Agent 任务"
        }
        guard text != lastActiveStatusText else { return }
        lastActiveStatusText = text
        activeStatusLabel.stringValue = text
        updateRoleDescription()
        updateSelection()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < rows.count, let tableColumn else { return nil }
        let field = (tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTextField)
            ?? makeCell(identifier: tableColumn.identifier)
        guard case let .task(task) = rows[row] else {
            field.stringValue = tableColumn.identifier.rawValue == "title" ? "还没有 Agent 任务" : ""
            field.textColor = .secondaryLabelColor
            return field
        }
        field.textColor = .labelColor
        switch tableColumn.identifier.rawValue {
        case "role":
            field.stringValue = AgentCatalog.profile(for: task.roleID).displayName
        case "title":
            field.stringValue = task.title
        case "status":
            field.stringValue = statusText(task.status)
            field.textColor = statusColor(task.status)
        case "time":
            field.stringValue = Self.dateFormatter.string(from: task.updatedAt)
            field.textColor = .secondaryLabelColor
        default:
            field.stringValue = ""
        }
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelection()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.deactivate()
    }

    private func configureContent() {
        guard let content = window?.contentView else { return }
        let heading = NSTextField(labelWithString: "AGENT CONTROL")
        heading.font = NSFont(name: "Menlo-Bold", size: 20)
            ?? NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        heading.textColor = NSColor(calibratedRed: 0.76, green: 0.26, blue: 0.20, alpha: 1)

        for profile in AgentCatalog.profiles {
            rolePopup.addItem(withTitle: profile.displayName)
            rolePopup.lastItem?.representedObject = profile.id.rawValue
        }
        rolePopup.target = self
        rolePopup.action = #selector(roleChanged)

        rolePortraitView.imageScaling = .scaleProportionallyUpOrDown
        rolePortraitView.imageAlignment = .alignCenter
        rolePortraitView.wantsLayer = true
        rolePortraitView.layer?.magnificationFilter = .nearest
        rolePortraitView.layer?.minificationFilter = .nearest

        specialtyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        capabilityLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        capabilityLabel.textColor = .secondaryLabelColor
        activeStatusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        activeStatusLabel.textColor = .systemBlue

        let roleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("role"))
        roleColumn.title = "角色"
        roleColumn.width = 92
        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "任务"
        titleColumn.width = 300
        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.title = "状态"
        statusColumn.width = 90
        let timeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        timeColumn.title = "更新时间"
        timeColumn.width = 140
        for column in [roleColumn, titleColumn, statusColumn, timeColumn] {
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 3

        runButton.target = self
        runButton.action = #selector(runDailyPlan)
        runButton.bezelStyle = .regularSquare
        runButton.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        proposalButton.target = self
        proposalButton.action = #selector(requestTodoProposal)
        proposalButton.bezelStyle = .regularSquare
        proposalButton.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        cancelButton.target = self
        cancelButton.action = #selector(cancelSelectedTask)
        cancelButton.bezelStyle = .regularSquare
        cancelButton.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)

        let topRow = NSStackView(views: [heading, rolePortraitView, rolePopup])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 12
        heading.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rolePopup.setContentHuggingPriority(.required, for: .horizontal)
        rolePortraitView.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            rolePortraitView.widthAnchor.constraint(equalToConstant: 42),
            rolePortraitView.heightAnchor.constraint(equalToConstant: 42),
        ])

        let actionRow = NSStackView(views: [proposalButton, runButton, cancelButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8

        for view in [topRow, specialtyLabel, capabilityLabel, activeStatusLabel, scrollView, detailLabel, actionRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            topRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            topRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            specialtyLabel.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 10),
            specialtyLabel.leadingAnchor.constraint(equalTo: topRow.leadingAnchor),
            specialtyLabel.trailingAnchor.constraint(equalTo: topRow.trailingAnchor),
            capabilityLabel.topAnchor.constraint(equalTo: specialtyLabel.bottomAnchor, constant: 5),
            capabilityLabel.leadingAnchor.constraint(equalTo: topRow.leadingAnchor),
            capabilityLabel.trailingAnchor.constraint(equalTo: topRow.trailingAnchor),
            activeStatusLabel.topAnchor.constraint(equalTo: capabilityLabel.bottomAnchor, constant: 8),
            activeStatusLabel.leadingAnchor.constraint(equalTo: topRow.leadingAnchor),
            activeStatusLabel.trailingAnchor.constraint(equalTo: topRow.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: activeStatusLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: topRow.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: topRow.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),
            detailLabel.leadingAnchor.constraint(equalTo: topRow.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: topRow.trailingAnchor),
            actionRow.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 10),
            actionRow.trailingAnchor.constraint(equalTo: topRow.trailingAnchor),
            actionRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.identifier = identifier
        field.font = .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    @objc private func roleChanged() {
        updateRoleDescription()
    }

    private func updateRoleDescription() {
        guard let roleID = selectedRoleID else { return }
        let profile = AgentCatalog.profile(for: roleID)
        let hasActiveTask = auditStore.tasks.contains(where: { Self.activeStatuses.contains($0.status) })
        rolePortraitView.image = AgentPortraitCatalog.image(for: roleID)
        rolePortraitView.isHidden = rolePortraitView.image == nil
        specialtyLabel.stringValue = profile.specialty
        capabilityLabel.stringValue = AgentCapability.allCases.map { capability in
            let auth = AgentExecutionPolicy.authorization(for: capability, role: profile)
            return "\(capabilityText(capability)): \(authorizationText(auth))"
        }.joined(separator: "  ·  ")
        switch roleID {
        case .isaac:
            proposalButton.isHidden = true
            runButton.title = "生成今日计划"
            runButton.isEnabled = !hasActiveTask
            runButton.toolTip = "Isaac 只读本地 Todo 并生成行动建议"
        case .magdalene:
            proposalButton.isHidden = true
            runButton.title = "检查今日节奏"
            runButton.isEnabled = !hasActiveTask
            runButton.toolTip = "Magdalene 只读本地 Todo 并给出休息建议"
        case .cain:
            proposalButton.isHidden = true
            runButton.title = "联网研究（未开放）"
            runButton.isEnabled = false
            runButton.toolTip = "联网研究适配器尚未安装"
        case .judas:
            proposalButton.isHidden = false
            proposalButton.isEnabled = !hasActiveTask
            proposalButton.toolTip = "Judas 只能在你明确确认后创建一条本地 Todo"
            runButton.title = "开始专注"
            runButton.isEnabled = !hasActiveTask
            runButton.toolTip = "Judas 启动一个完全本地的专注倒计时"
        }
    }

    private var selectedRoleID: AgentRoleID? {
        guard let raw = rolePopup.selectedItem?.representedObject as? String else { return nil }
        return AgentRoleID(rawValue: raw)
    }

    private var selectedTask: AgentTask? {
        let row = tableView.selectedRow
        guard row >= 0, row < rows.count, case let .task(task) = rows[row] else { return nil }
        return task
    }

    private func updateSelection() {
        guard let task = selectedTask else {
            detailLabel.stringValue = "选择一条任务可查看结果摘要；所有状态变化都会写入本机审计日志。"
            cancelButton.isEnabled = false
            return
        }
        let events = auditStore.events.filter { $0.taskID == task.id }.prefix(3)
        detailLabel.stringValue = events.map {
            "[\(statusText($0.status))] \($0.summary)"
        }.joined(separator: "   ")
        cancelButton.isEnabled = [.queued, .running, .awaitingConfirmation].contains(task.status)
    }

    @objc private func runDailyPlan() {
        guard let roleID = selectedRoleID, [.isaac, .magdalene, .judas].contains(roleID) else { return }
        onRunRole(roleID)
    }

    @objc private func requestTodoProposal() {
        guard selectedRoleID == .judas else { return }
        onRequestTodoProposal()
    }

    @objc private func cancelSelectedTask() {
        let task = selectedTask ?? auditStore.tasks.first(where: { Self.activeStatuses.contains($0.status) })
        guard let task else { return }
        onCancelTask(task.id)
    }

    private func capabilityText(_ capability: AgentCapability) -> String {
        switch capability {
        case .readLocalTodos: return "读取本地 Todo"
        case .writeLocalTodos: return "修改本地 Todo"
        case .focusTimer: return "本地专注计时"
        case .readExternalTasks: return "读取外部任务"
        case .writeExternalTasks: return "修改外部任务"
        case .networkResearch: return "联网研究"
        case .runCommands: return "运行命令"
        }
    }

    private func authorizationText(_ authorization: AgentAuthorization) -> String {
        switch authorization {
        case .automatic: return "自动"
        case .requiresConfirmation: return "需确认"
        case .unavailable: return "未开放"
        }
    }

    private func statusText(_ status: AgentTaskStatus) -> String {
        switch status {
        case .queued: return "排队中"
        case .running: return "运行中"
        case .awaitingConfirmation: return "等待确认"
        case .succeeded: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    private func statusColor(_ status: AgentTaskStatus) -> NSColor {
        switch status {
        case .running: return .systemBlue
        case .awaitingConfirmation: return .systemOrange
        case .succeeded: return .systemGreen
        case .failed: return .systemRed
        case .cancelled: return .secondaryLabelColor
        case .queued: return .labelColor
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let activeStatuses: Set<AgentTaskStatus> = [.queued, .running, .awaitingConfirmation]
}
