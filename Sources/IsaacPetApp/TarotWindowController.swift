import AppKit
import IsaacPetCore

@MainActor
final class TarotWindowController: NSWindowController, NSWindowDelegate {
    private let cardView = TarotPlaceholderView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let readingLabel = NSTextField(wrappingLabelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private var currentCard: TarotCard?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Isaac 今日运势"
        window.minSize = NSSize(width: 460, height: 560)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        super.init(window: window)
        window.delegate = self
        configureContent()
        showDailyCard()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showDailyCard()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.deactivate()
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let heading = NSTextField(labelWithString: "TODAY'S FORTUNE")
        heading.font = NSFont(name: "Menlo-Bold", size: 20)
            ?? NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        heading.textColor = NSColor(calibratedRed: 0.76, green: 0.26, blue: 0.20, alpha: 1)

        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.alignment = .center

        messageLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 0

        readingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        readingLabel.alignment = .center
        readingLabel.maximumNumberOfLines = 0

        hintLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center

        let drawButton = NSButton(title: "重新抽一张", target: self, action: #selector(drawRandomCard))
        drawButton.bezelStyle = .regularSquare
        drawButton.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)

        let closeButton = NSButton(title: "收起", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .regularSquare
        closeButton.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)

        let buttons = NSStackView(views: [drawButton, closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.alignment = .centerY

        for view in [heading, cardView, titleLabel, messageLabel, readingLabel, hintLabel, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            heading.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            cardView.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 18),
            cardView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cardView.widthAnchor.constraint(equalToConstant: 220),
            cardView.heightAnchor.constraint(equalToConstant: 280),

            titleLabel.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            readingLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 14),
            readingLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            readingLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            hintLabel.topAnchor.constraint(equalTo: readingLabel.bottomAnchor, constant: 14),
            hintLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            buttons.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 14),
            buttons.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
        ])
    }

    private func showDailyCard() {
        let card = TarotDrawPolicy.dailyCard()
        currentCard = card
        update(card: card, label: "今日固定牌 · 每天首次打开保持一致")
    }

    @objc private func drawRandomCard() {
        let card = TarotDrawPolicy.randomCard(excluding: currentCard?.id)
        currentCard = card
        update(card: card, label: "娱乐抽卡 · 重新打开窗口会回到今日固定牌")
    }

    @objc private func closeWindow() {
        window?.close()
    }

    private func update(card: TarotCard, label: String) {
        cardView.card = card
        titleLabel.stringValue = card.romanNumeral + " · " + card.name
        messageLabel.stringValue = "游戏内短句：" + card.gameMessage
        readingLabel.stringValue = card.reading
        hintLabel.stringValue = label + "\n仅供娱乐，不代表游戏内效果或现实预测。"
    }
}

private final class TarotPlaceholderView: NSView {
    var card: TarotCard? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds.insetBy(dx: 8, dy: 8)
        let color = card.map(Self.color(for:)) ?? NSColor.darkGray
        context.setFillColor(color.cgColor)
        context.fill(bounds)

        context.setStrokeColor(NSColor(calibratedWhite: 0.1, alpha: 1).cgColor)
        context.setLineWidth(8)
        context.stroke(bounds.insetBy(dx: 4, dy: 4))

        let inner = bounds.insetBy(dx: 18, dy: 18)
        context.setStrokeColor(NSColor(calibratedWhite: 0.92, alpha: 0.85).cgColor)
        context.setLineWidth(2)
        context.stroke(inner)

        if let card {
            let shortName = card.name.split(separator: "·").first.map(String.init) ?? card.name
            let text = card.romanNumeral + "\n\n" + shortName
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let size = attributed.size()
            attributed.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
        }
    }

    private static func color(for card: TarotCard) -> NSColor {
        let red = CGFloat((card.placeholderRGB >> 16) & 0xFF) / 255
        let green = CGFloat((card.placeholderRGB >> 8) & 0xFF) / 255
        let blue = CGFloat(card.placeholderRGB & 0xFF) / 255
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}
