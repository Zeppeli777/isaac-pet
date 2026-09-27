import AppKit
import IsaacPetCore


/// Shows the drawn tarot card above the pet's head: a pixel paper panel with the
/// card icon, its name and effect. Like the speech and emote bubbles it is a
/// non-activating floating panel, and only one of the three may be visible.
@MainActor
final class CardBubbleController: NSObject {
    private let panel: NSPanel
    private let cardView: CardPanelView
    private var hideTimer: Timer?
    private var petFrame = NSRect.zero
    private var screenFrame = NSRect.zero

    override init() {
        cardView = CardPanelView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        panel = NSPanel(
            contentRect: cardView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.contentView = cardView
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    var isVisible: Bool { panel.isVisible }

    func show(
        _ card: TarotCard,
        spriteFrame: SpriteFrame,
        anchoredTo petFrame: NSRect,
        in screenFrame: NSRect,
        scale: CGFloat
    ) {
        self.petFrame = petFrame
        self.screenFrame = screenFrame

        hideTimer?.invalidate()
        cardView.configure(card: card, spriteFrame: spriteFrame, scale: scale)
        let size = cardView.fittingSize()
        panel.setContentSize(size)
        cardView.frame = NSRect(origin: .zero, size: size)
        updatePosition()
        panel.orderFrontRegardless()

        let timer = Timer(
            timeInterval: TarotDrawPolicy.cardPanelDisplayDuration,
            target: self,
            selector: #selector(hideFromTimer),
            userInfo: nil,
            repeats: false
        )
        hideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func updateAnchor(petFrame: NSRect, screenFrame: NSRect) {
        guard isVisible else { return }
        self.petFrame = petFrame
        self.screenFrame = screenFrame
        updatePosition()
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel.orderOut(nil)
    }

    func stop() {
        hide()
        panel.close()
    }

    @objc private func hideFromTimer() {
        hide()
    }

    private func updatePosition() {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return }
        let size = panel.frame.size
        let edgePadding: CGFloat = 8
        let minimumX = screenFrame.minX + edgePadding
        let maximumX = max(minimumX, screenFrame.maxX - size.width - edgePadding)
        let originX = min(max(petFrame.midX - size.width / 2, minimumX), maximumX)

        let aboveY = petFrame.maxY - 6
        let belowY = petFrame.minY - size.height + 6
        let originY: CGFloat
        if aboveY + size.height <= screenFrame.maxY - edgePadding {
            originY = aboveY
            cardView.tailEdge = .bottom
        } else if belowY >= screenFrame.minY + edgePadding {
            originY = belowY
            cardView.tailEdge = .top
        } else {
            originY = min(
                max(aboveY, screenFrame.minY + edgePadding),
                max(screenFrame.minY + edgePadding, screenFrame.maxY - size.height - edgePadding)
            )
            cardView.tailEdge = petFrame.midY < originY + size.height / 2 ? .bottom : .top
        }

        cardView.tailX = min(max(petFrame.midX - originX, 20), size.width - 20)
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}

@MainActor
private final class CardPanelView: NSView {
    enum TailEdge {
        case top
        case bottom
    }

    private enum Layout {
        static let tailHeight: CGFloat = 12
        static let frameBorder: CGFloat = 3
        static let radius: CGFloat = 5
        static let padding: CGFloat = 10
        static let iconGap: CGFloat = 12
        static let textGap: CGFloat = 6
        static let maximumTextWidth: CGFloat = 190
        /// The card icon is a 14×18 HUD sprite; 4× keeps it head-sized next to the
        /// 192pt pet and on whole pixels under nearest filtering.
        static let iconMagnification: CGFloat = 4
    }

    private var card: TarotCard?
    private var spriteFrame: SpriteFrame?
    private var scale: CGFloat = 1
    var tailX: CGFloat = 120 { didSet { needsDisplay = true } }
    var tailEdge: TailEdge = .bottom { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    func configure(card: TarotCard, spriteFrame: SpriteFrame, scale: CGFloat) {
        self.card = card
        self.spriteFrame = spriteFrame
        self.scale = scale
        needsDisplay = true
    }

    private static let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: PixelFont.speech,
        .foregroundColor: PixelStyle.accentColor,
    ]

    private static let pickupAttributes: [NSAttributedString.Key: Any] = [
        .font: PixelFont.speech,
        .foregroundColor: PixelStyle.disabledTextColor,
    ]

    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        style.lineSpacing = 2
        return style
    }()

    private static func effectAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: PixelFont.speech,
            .foregroundColor: PixelStyle.textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    private var iconSize: NSSize {
        guard let spriteFrame else { return .zero }
        return NSSize(
            width: CGFloat(spriteFrame.width) * Layout.iconMagnification * scale,
            height: CGFloat(spriteFrame.height) * Layout.iconMagnification * scale
        )
    }

    private var textWidth: CGFloat {
        guard let card else { return Layout.maximumTextWidth }
        let title = NSAttributedString(string: TarotDrawPolicy.displayTitle(for: card), attributes: Self.titleAttributes)
        let pickup = NSAttributedString(string: card.pickupZH, attributes: Self.pickupAttributes)
        let effect = NSAttributedString(
            string: TarotDrawPolicy.effectText(for: card),
            attributes: Self.effectAttributes()
        )
        let attributedParts: [NSAttributedString] = [title, pickup, effect]
        let widths = attributedParts.map { attributed -> CGFloat in
            ceil(attributed.boundingRect(
                with: NSSize(width: Layout.maximumTextWidth, height: 600),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).width)
        }
        return min(Layout.maximumTextWidth, max(80, widths.max() ?? 80))
    }

    /// Total panel size including the stepped border and the tail space.
    func fittingSize() -> NSSize {
        guard let card else { return NSSize(width: 240, height: 120) }
        let title = NSAttributedString(string: TarotDrawPolicy.displayTitle(for: card), attributes: Self.titleAttributes)
        let pickup = NSAttributedString(string: card.pickupZH, attributes: Self.pickupAttributes)
        let effect = NSAttributedString(
            string: TarotDrawPolicy.effectText(for: card),
            attributes: Self.effectAttributes()
        )
        let titleHeight = ceil(title.size().height)
        let pickupHeight = pickup.length == 0 ? 0 : ceil(pickup.size().height) + Layout.textGap
        let effectHeight = ceil(effect.boundingRect(
            with: NSSize(width: textWidth, height: 600),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)
        let textHeight = titleHeight + pickupHeight + effectHeight

        let bodyWidth = iconSize.width + Layout.iconGap + textWidth + Layout.padding * 2
        let bodyHeight = max(iconSize.height, textHeight) + Layout.padding * 2
        let outerInset = Layout.frameBorder * 2
        return NSSize(
            width: ceil(bodyWidth) + outerInset,
            height: ceil(bodyHeight) + outerInset + Layout.tailHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let card, let spriteFrame, let context = NSGraphicsContext.current else { return }

        context.saveGraphicsState()
        context.shouldAntialias = false

        let tailSpace = Layout.tailHeight
        let bodyY = tailEdge == .bottom ? tailSpace : 0
        let bodyRect = NSRect(
            x: 0,
            y: bodyY,
            width: bounds.width,
            height: bounds.height - tailSpace
        )
        let inner = PixelStyle.drawFrame(
            in: bodyRect,
            borderWidth: Layout.frameBorder,
            radius: Layout.radius
        )
        drawTail(from: bodyRect)
        drawContent(card: card, spriteFrame: spriteFrame, in: inner)

        context.restoreGraphicsState()
    }

    private func drawContent(card: TarotCard, spriteFrame: SpriteFrame, in inner: NSRect) {
        let content = inner.insetBy(dx: Layout.padding, dy: Layout.padding)
        let iconRect = NSRect(
            x: content.minX,
            y: content.minY + (content.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )

        let title = NSAttributedString(string: TarotDrawPolicy.displayTitle(for: card), attributes: Self.titleAttributes)
        let pickup = NSAttributedString(string: card.pickupZH, attributes: Self.pickupAttributes)
        let effect = NSAttributedString(
            string: TarotDrawPolicy.effectText(for: card),
            attributes: Self.effectAttributes()
        )
        let titleHeight = ceil(title.size().height)
        let pickupHeight = pickup.length == 0 ? 0 : ceil(pickup.size().height) + Layout.textGap
        let effectHeight = ceil(effect.boundingRect(
            with: NSSize(width: textWidth, height: 600),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)
        let textHeight = titleHeight + pickupHeight + effectHeight
        let textY = content.minY + (content.height - textHeight) / 2
        let textX = iconRect.maxX + Layout.iconGap

        title.draw(at: NSPoint(x: textX, y: textY + textHeight - titleHeight))
        if pickup.length > 0 {
            pickup.draw(at: NSPoint(x: textX, y: textY + effectHeight))
        }
        effect.draw(
            with: NSRect(x: textX, y: textY, width: textWidth, height: effectHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        drawIcon(spriteFrame, in: iconRect)
    }

    /// The card icon must stay pixel-crisp, so it is drawn with interpolation off.
    private func drawIcon(_ spriteFrame: SpriteFrame, in rect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.imageInterpolation = .none
        spriteFrame.image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        context.restoreGraphicsState()
    }

    private func drawTail(from bodyRect: NSRect) {
        let downward = tailEdge == .bottom
        let direction: CGFloat = downward ? -1 : 1
        // Staircase tail: (step height, outer width, inner width, inner height). The
        // inner fill hugs the body side and leaves a border cap at the tip.
        let steps: [(height: CGFloat, outer: CGFloat, inner: CGFloat, innerHeight: CGFloat)] = [
            (4, 20, 14, 4),
            (4, 12, 6, 4),
            (3, 6, 2, 1),
        ]
        var y = downward ? bodyRect.minY : bodyRect.maxY
        for step in steps {
            let outerY = downward ? y - step.height : y
            PixelStyle.borderColor.setFill()
            NSBezierPath(rect: NSRect(
                x: tailX - step.outer / 2,
                y: outerY,
                width: step.outer,
                height: step.height
            )).fill()
            PixelStyle.fillColor.setFill()
            NSBezierPath(rect: NSRect(
                x: tailX - step.inner / 2,
                y: downward ? y - step.innerHeight : y,
                width: step.inner,
                height: step.innerHeight
            )).fill()
            y += direction * step.height
        }
    }
}
