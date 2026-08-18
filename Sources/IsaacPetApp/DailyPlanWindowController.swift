import AppKit
import IsaacPetCore

@MainActor
final class DailyPlanWindowController: NSWindowController, NSWindowDelegate {
    private let itemsProvider: () -> [TodoItem]
    private let headlineLabel = NSTextField(wrappingLabelWithString: "")
    private let generatedLabel = NSTextField(labelWithString: "")
    private let planTextView = NSTextView()

    init(itemsProvider: @escaping () -> [TodoItem]) {
        self.itemsProvider = itemsProvider

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 390),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Isaac 今日计划"
        window.minSize = NSSize(width: 460, height: 300)
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

    func reload(now: Date = Date()) {
        let plan = LocalPlanningAgent.makeDailyPlan(from: itemsProvider(), now: now)
        headlineLabel.stringValue = plan.headline
        generatedLabel.stringValue = "基于本机 Todo 自动排序 · " + Self.dateFormatter.string(from: now)
        planTextView.string = plan.steps.enumerated().map { index, step in
            String(index + 1) + ". " + step
        }.joined(separator: "\n\n")
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.deactivate()
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let heading = NSTextField(labelWithString: "TODAY'S PLAN")
        heading.font = NSFont(name: "Menlo-Bold", size: 20)
            ?? NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        heading.textColor = NSColor(calibratedRed: 0.76, green: 0.26, blue: 0.20, alpha: 1)

        headlineLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        headlineLabel.textColor = .labelColor
        headlineLabel.maximumNumberOfLines = 0

        generatedLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        generatedLabel.textColor = .secondaryLabelColor

        planTextView.isEditable = false
        planTextView.isSelectable = true
        planTextView.isRichText = false
        planTextView.drawsBackground = false
        planTextView.font = .systemFont(ofSize: 14, weight: .medium)
        planTextView.textColor = .labelColor
        planTextView.textContainerInset = NSSize(width: 12, height: 12)
        planTextView.autoresizingMask = [.width]
        planTextView.isVerticallyResizable = true
        planTextView.isHorizontallyResizable = false
        planTextView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = planTextView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let refreshButton = NSButton(title: "刷新计划", target: self, action: #selector(refreshPlan))
        refreshButton.bezelStyle = .regularSquare
        refreshButton.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)

        for view in [heading, headlineLabel, generatedLabel, scrollView, refreshButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            heading.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            refreshButton.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            headlineLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            headlineLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            headlineLabel.trailingAnchor.constraint(equalTo: refreshButton.trailingAnchor),

            generatedLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 6),
            generatedLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            generatedLabel.trailingAnchor.constraint(equalTo: refreshButton.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: generatedLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: refreshButton.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    @objc private func refreshPlan() {
        reload()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
