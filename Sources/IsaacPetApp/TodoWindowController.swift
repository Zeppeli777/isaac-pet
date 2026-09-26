import AppKit
import IsaacPetCore

@MainActor
final class TodoWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let store: TodoStore
    private let onItemsChanged: () -> Void
    private let tableView = NSTableView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let titleField = PixelStyledField()
    private let reminderCheckbox = NSButton(checkboxWithTitle: "定时提醒", target: nil, action: nil)
    private let datePicker = NSDatePicker()
    private let completeButton = PixelButton(title: "完成", target: nil, action: nil)
    private let deleteButton = PixelButton(title: "删除", target: nil, action: nil)
    private var displayedItems: [TodoItem] = []

    init(store: TodoStore, onItemsChanged: @escaping () -> Void) {
        self.store = store
        self.onItemsChanged = onItemsChanged

        let window = PixelWindow(
            size: NSSize(width: 600, height: 430),
            title: "Isaac Todo",
            minSize: NSSize(width: 520, height: 360)
        )
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
            field.textColor = item.isCompleted ? .systemGreen : PixelStyle.disabledTextColor
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
                field.textColor = PixelStyle.disabledTextColor
            }
        default:
            break
        }
        return field
    }

    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        rowView.backgroundColor = row.isMultiple(of: 2)
            ? PixelStyle.fillColor
            : PixelStyle.shadowColor.withAlphaComponent(0.35)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PixelTableRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionButtons()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.deactivate()
    }

    private func configureContent() {
        guard let contentView = (window as? PixelWindow)?.contentContainer else { return }

        summaryLabel.font = PixelFont.speech
        summaryLabel.textColor = PixelStyle.disabledTextColor

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
        for column in [statusColumn, titleColumn, dueColumn] {
            column.headerCell.font = PixelFont.speech
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.allowsEmptySelection = true
        tableView.doubleAction = #selector(toggleSelectedTodo)
        tableView.target = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        let tableFrame = PixelFrameBoxView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        tableFrame.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tableFrame)
        tableFrame.addSubview(scrollView)

        titleField.placeholderString = "添加一个 Todo…"
        titleField.target = self
        titleField.action = #selector(addTodo)

        reminderCheckbox.target = self
        reminderCheckbox.action = #selector(toggleReminderInput)
        reminderCheckbox.state = .off
        reminderCheckbox.font = PixelFont.speech

        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay, .hourMinute]
        datePicker.dateValue = Date().addingTimeInterval(3600)
        datePicker.isEnabled = false

        let addButton = PixelButton(title: "添加", target: self, action: #selector(addTodo))
        completeButton.target = self
        completeButton.action = #selector(toggleSelectedTodo)
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedTodo)

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

        for view in [summaryLabel, composer, actionButtons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            summaryLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            summaryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),

            tableFrame.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 8),
            tableFrame.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableFrame.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            scrollView.leadingAnchor.constraint(equalTo: tableFrame.leadingAnchor, constant: 3),
            scrollView.trailingAnchor.constraint(equalTo: tableFrame.trailingAnchor, constant: -3),
            scrollView.topAnchor.constraint(equalTo: tableFrame.topAnchor, constant: 3),
            scrollView.bottomAnchor.constraint(equalTo: tableFrame.bottomAnchor, constant: -3),

            composer.topAnchor.constraint(equalTo: tableFrame.bottomAnchor, constant: 12),
            composer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            actionButtons.topAnchor.constraint(equalTo: composer.bottomAnchor, constant: 10),
            actionButtons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionButtons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.identifier = identifier
        field.font = PixelFont.speech
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func titleText(for item: TodoItem) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: PixelFont.speech,
            .foregroundColor: item.isCompleted ? PixelStyle.disabledTextColor : PixelStyle.textColor,
        ]
        if item.isCompleted { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return NSAttributedString(string: item.title, attributes: attributes)
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
        guard PixelDialog.confirm(
            title: "删除这个 Todo？",
            message: item.title,
            confirmTitle: "删除",
            isDestructive: true
        ) else { return }
        do {
            try store.remove(id: item.id)
            reload()
            onItemsChanged()
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    private func showError(message: String) {
        PixelDialog.presentMessage(title: "无法更新 Todo", message: message)
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
