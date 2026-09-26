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

        let window = PixelWindow(
            size: NSSize(width: 560, height: 390),
            title: "Isaac 今日计划",
            minSize: NSSize(width: 460, height: 300)
        )
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

        headlineLabel.font = PixelFont.speech
        headlineLabel.textColor = PixelStyle.textColor
        headlineLabel.textColor = .labelColor
        headlineLabel.maximumNumberOfLines = 0

        generatedLabel.font = PixelFont.speech
        generatedLabel.textColor = PixelStyle.disabledTextColor

        planTextView.isEditable = false
        planTextView.isSelectable = true
        planTextView.isRichText = false
        planTextView.drawsBackground = false
        planTextView.font = PixelFont.speech
        planTextView.textColor = .labelColor
        planTextView.textContainerInset = NSSize(width: 12, height: 12)
        planTextView.autoresizingMask = [.width]
        planTextView.isVerticallyResizable = true
        planTextView.isHorizontallyResizable = false
        planTextView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = planTextView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        let planFrame = PixelFrameBoxView()
        planFrame.addSubview(scrollView)

        let refreshButton = PixelButton(title: "刷新计划", target: self, action: #selector(refreshPlan))

        for view in [headlineLabel, generatedLabel, planFrame, refreshButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headlineLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            headlineLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headlineLabel.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -12),

            generatedLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 6),
            generatedLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            generatedLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            planFrame.topAnchor.constraint(equalTo: generatedLabel.bottomAnchor, constant: 10),
            planFrame.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            planFrame.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            planFrame.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: planFrame.leadingAnchor, constant: 3),
            scrollView.trailingAnchor.constraint(equalTo: planFrame.trailingAnchor, constant: -3),
            scrollView.topAnchor.constraint(equalTo: planFrame.topAnchor, constant: 3),
            scrollView.bottomAnchor.constraint(equalTo: planFrame.bottomAnchor, constant: -3),

            refreshButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            refreshButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
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
