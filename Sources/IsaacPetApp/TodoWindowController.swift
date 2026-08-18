import AppKit
import IsaacPetCore

@MainActor
final class TodoWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let store: TodoStore
    private let onItemsChanged: () -> Void
    private let tableView = NSTableView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let titleField = NSTextField()
    private let reminderCheckbox = NSButton(checkboxWithTitle: "定时提醒", target: nil, action: nil)
    private let datePicker = NSDatePicker()
    private let completeButton = NSButton(title: "完成", target: nil, action: nil)
    private let deleteButton = NSButton(title: "删除", target: nil, action: nil)
    private var displayedItems: [TodoItem] = []

    init(store: TodoStore, onItemsChanged: @escaping () -> Void) {
        self.store = store
        self.onItemsChanged = onItemsChanged

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 430),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Isaac Todo"
        window.minSize = NSSize(width: 520, height: 360)
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

    func present(focusComposer: Bool = false) {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if focusComposer { window?.makeFirstResponder(titleField) }
    }

    func reload() {
        displayedItems = TodoPolicy.sorted(store.items)
        tableView.reloadData()
        let pendingCount = displayedItems.filter { !$0.isCompleted }.count
        let completedCount = displayedItems.count - pendingCount
        summaryLabel.stringValue = "待办 \(pendingCount)  ·  已完成 \(completedCount)"
        updateSelectionButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < displayedItems.count, let tableColumn else { return nil }
        let item = displayedItems[row]
        let identifier = tableColumn.identifier
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField)
            ?? makeCell(identifier: identifier)

        switch identifier.rawValue {
        case "status":
            field.stringValue = item.isCompleted ? "✓" : "□"
            field.alignment = .center
            field.textColor = item.isCompleted ? .systemGreen : .secondaryLabelColor
        case "title":
            field.attributedStringValue = titleText(for: item)
            field.alignment = .left
            if let source = item.externalSource {
                switch source.kind {
                case .appleReminders:
                    field.toolTip = "来自 Apple 提醒事项 · \(source.containerTitle ?? "未知列表")"
                case .notion:
                    field.toolTip = "来自 Notion · \(source.containerIdentifier ?? "未知 data source")"
                }
            } else {
                field.toolTip = nil
            }
        case "due":
            field.stringValue = TodoFormatting.dueText(for: item)
            field.alignment = .left
            if !item.isCompleted, let dueAt = item.dueAt, dueAt <= Date() {
                field.textColor = .systemRed
            } else {
                field.textColor = .secondaryLabelColor
            }
        default:
            break
        }
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionButtons()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.deactivate()
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let heading = NSTextField(labelWithString: "ISAAC TODO")
        heading.font = NSFont(name: "Menlo-Bold", size: 20)
            ?? NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        heading.textColor = NSColor(calibratedRed: 0.76, green: 0.26, blue: 0.20, alpha: 1)

        summaryLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor

        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.title = ""
        statusColumn.width = 38
        statusColumn.minWidth = 38
        statusColumn.maxWidth = 38
        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "任务"
        titleColumn.width = 320
        titleColumn.minWidth = 180
        let dueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("due"))
        dueColumn.title = "提醒时间"
        dueColumn.width = 180
        dueColumn.minWidth = 150
        tableView.addTableColumn(statusColumn)
        tableView.addTableColumn(titleColumn)
        tableView.addTableColumn(dueColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true
        tableView.doubleAction = #selector(toggleSelectedTodo)
        tableView.target = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        titleField.placeholderString = "添加一个 Todo…"
        titleField.font = .systemFont(ofSize: 13)
        titleField.target = self
        titleField.action = #selector(addTodo)

        reminderCheckbox.target = self
        reminderCheckbox.action = #selector(toggleReminderInput)
        reminderCheckbox.state = .off

        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay, .hourMinute]
        datePicker.dateValue = Date().addingTimeInterval(3600)
        datePicker.isEnabled = false

        let addButton = NSButton(title: "添加", target: self, action: #selector(addTodo))
        configurePixelButton(addButton)
        completeButton.target = self
        completeButton.action = #selector(toggleSelectedTodo)
        configurePixelButton(completeButton)
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedTodo)
        configurePixelButton(deleteButton)

        let composer = NSStackView(views: [titleField, reminderCheckbox, datePicker, addButton])
        composer.orientation = .horizontal
        composer.alignment = .centerY
        composer.spacing = 8
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        datePicker.setContentHuggingPriority(.required, for: .horizontal)

        let actionButtons = NSStackView(views: [completeButton, deleteButton])
        actionButtons.orientation = .horizontal
        actionButtons.alignment = .centerY
        actionButtons.spacing = 8

        for view in [heading, summaryLabel, scrollView, composer, actionButtons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            heading.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            summaryLabel.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            summaryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            composer.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            composer.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),

            actionButtons.topAnchor.constraint(equalTo: composer.bottomAnchor, constant: 10),
            actionButtons.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            actionButtons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.identifier = identifier
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func titleText(for item: TodoItem) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: item.isCompleted ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        if item.isCompleted { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return NSAttributedString(string: item.title, attributes: attributes)
    }

    private func configurePixelButton(_ button: NSButton) {
        button.bezelStyle = .regularSquare
        button.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
    }

    private func updateSelectionButtons() {
        let item = selectedItem
        completeButton.isEnabled = item != nil
        deleteButton.isEnabled = item != nil
        completeButton.title = item?.isCompleted == true ? "恢复" : "完成"
    }

    private var selectedItem: TodoItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < displayedItems.count else { return nil }
        return displayedItems[row]
    }

    @objc private func toggleReminderInput() {
        datePicker.isEnabled = reminderCheckbox.state == .on
    }

    @objc private func addTodo() {
        let dueAt = reminderCheckbox.state == .on ? datePicker.dateValue : nil
        if let dueAt, dueAt <= Date() {
            showError(message: "提醒时间需要晚于现在。")
            return
        }
        do {
            try store.add(title: titleField.stringValue, dueAt: dueAt)
            titleField.stringValue = ""
            if reminderCheckbox.state == .on {
                datePicker.dateValue = Date().addingTimeInterval(3600)
            }
            reload()
            onItemsChanged()
            window?.makeFirstResponder(titleField)
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    @objc private func toggleSelectedTodo() {
        guard let item = selectedItem else { return }
        do {
            try store.toggleCompleted(id: item.id)
            reload()
            onItemsChanged()
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    @objc private func deleteSelectedTodo() {
        guard let item = selectedItem else { return }
        let alert = NSAlert()
        alert.messageText = "删除这个 Todo？"
        alert.informativeText = item.title
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.remove(id: item.id)
            reload()
            onItemsChanged()
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    private func showError(message: String) {
        let alert = NSAlert()
        alert.messageText = "无法更新 Todo"
        alert.informativeText = message
        alert.runModal()
    }
}

enum TodoFormatting {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static func dueText(for item: TodoItem) -> String {
        guard let dueAt = item.dueAt else { return "无提醒" }
        return dateFormatter.string(from: dueAt)
    }
}
