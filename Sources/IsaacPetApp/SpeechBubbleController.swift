import AppKit
import IsaacPetCore

@MainActor
final class SpeechBubbleController: NSObject {
    private let panel: NSPanel
    private let bubbleView: SpeechBubbleView
    private var hideTimer: Timer?
    private var petFrame = NSRect.zero
    private var screenFrame = NSRect.zero

    override init() {
        bubbleView = SpeechBubbleView(frame: NSRect(x: 0, y: 0, width: 160, height: 76))
        panel = NSPanel(
            contentRect: bubbleView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.contentView = bubbleView
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

    func show(_ rawMessage: String, anchoredTo petFrame: NSRect, in screenFrame: NSRect) {
        guard let message = SpeechBubblePolicy.normalized(rawMessage) else { return }
        self.petFrame = petFrame
        self.screenFrame = screenFrame

        hideTimer?.invalidate()
        bubbleView.message = message
        let size = bubbleView.fittingSize(for: message)
        panel.setContentSize(size)
        bubbleView.frame = NSRect(origin: .zero, size: size)
        updatePosition()
        panel.orderFrontRegardless()

        let timer = Timer(
            timeInterval: SpeechBubblePolicy.displayDuration(for: message),
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

        let aboveY = petFrame.maxY - 8
        let belowY = petFrame.minY - size.height + 8
        let originY: CGFloat
        if aboveY + size.height <= screenFrame.maxY - edgePadding {
            originY = aboveY
            bubbleView.tailEdge = .bottom
        } else if belowY >= screenFrame.minY + edgePadding {
            originY = belowY
            bubbleView.tailEdge = .top
        } else {
            originY = min(
                max(aboveY, screenFrame.minY + edgePadding),
                max(screenFrame.minY + edgePadding, screenFrame.maxY - size.height - edgePadding)
            )
            bubbleView.tailEdge = petFrame.midY < originY + size.height / 2 ? .bottom : .top
        }

        bubbleView.tailX = min(max(petFrame.midX - originX, 24), size.width - 24)
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}

@MainActor
private final class SpeechBubbleView: NSView {
    enum TailEdge {
        case top
        case bottom
    }

    private enum Layout {
        static let tailHeight: CGFloat = 14
        static let outerInset: CGFloat = 3
        static let border: CGFloat = 4
        static let textHorizontalInset: CGFloat = 13
        static let textVerticalInset: CGFloat = 10
        static let maximumTextWidth: CGFloat = 236
        static let minimumBodyWidth: CGFloat = 88
        static let minimumBodyHeight: CGFloat = 43
    }

    var message = "" {
        didSet { needsDisplay = true }
    }
    var tailX: CGFloat = 80 {
        didSet { needsDisplay = true }
    }
    var tailEdge: TailEdge = .bottom {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    private static let font = NSFont(name: "Menlo-Bold", size: 15)
        ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)

    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 2
        return style
    }()

    private static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedWhite: 0.10, alpha: 1),
        .paragraphStyle: paragraphStyle,
    ]

    func fittingSize(for message: String) -> NSSize {
        let attributed = NSAttributedString(string: message, attributes: Self.textAttributes)
        let textBounds = attributed.boundingRect(
            with: NSSize(width: Layout.maximumTextWidth, height: 500),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let bodyWidth = min(
            Layout.maximumTextWidth + Layout.textHorizontalInset * 2,
            max(Layout.minimumBodyWidth, ceil(textBounds.width) + Layout.textHorizontalInset * 2)
        )
        let bodyHeight = max(
            Layout.minimumBodyHeight,
            ceil(textBounds.height) + Layout.textVerticalInset * 2
        )
        return NSSize(
            width: bodyWidth + Layout.outerInset * 2,
            height: bodyHeight + Layout.tailHeight + Layout.outerInset * 2
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !message.isEmpty, let context = NSGraphicsContext.current else { return }

        context.saveGraphicsState()
        context.shouldAntialias = false
        let tailSpace = Layout.tailHeight
        let bodyY = tailEdge == .bottom ? tailSpace + Layout.outerInset : Layout.outerInset
        let bodyRect = NSRect(
            x: Layout.outerInset,
            y: bodyY,
            width: bounds.width - Layout.outerInset * 2,
            height: bounds.height - tailSpace - Layout.outerInset * 2
        )

        drawPixelBody(in: bodyRect)
        drawTail(from: bodyRect)

        let innerRect = bodyRect.insetBy(dx: Layout.border, dy: Layout.border)
        let textRect = innerRect.insetBy(
            dx: Layout.textHorizontalInset - Layout.border,
            dy: Layout.textVerticalInset - Layout.border
        )
        NSAttributedString(string: message, attributes: Self.textAttributes).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        context.restoreGraphicsState()
    }

    private func drawPixelBody(in rect: NSRect) {
        let corner: CGFloat = 6
        let outerPath = NSBezierPath()
        outerPath.move(to: NSPoint(x: rect.minX + corner, y: rect.minY))
        outerPath.line(to: NSPoint(x: rect.maxX - corner, y: rect.minY))
        outerPath.line(to: NSPoint(x: rect.maxX, y: rect.minY + corner))
        outerPath.line(to: NSPoint(x: rect.maxX, y: rect.maxY - corner))
        outerPath.line(to: NSPoint(x: rect.maxX - corner, y: rect.maxY))
        outerPath.line(to: NSPoint(x: rect.minX + corner, y: rect.maxY))
        outerPath.line(to: NSPoint(x: rect.minX, y: rect.maxY - corner))
        outerPath.line(to: NSPoint(x: rect.minX, y: rect.minY + corner))
        outerPath.close()
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        outerPath.fill()

        let inner = rect.insetBy(dx: Layout.border, dy: Layout.border)
        NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.82, alpha: 1).setFill()
        NSBezierPath(rect: inner).fill()

        NSColor(calibratedRed: 0.76, green: 0.26, blue: 0.20, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: 3)).fill()
    }

    private func drawTail(from bodyRect: NSRect) {
        let bodyEdgeY = tailEdge == .bottom ? bodyRect.minY : bodyRect.maxY
        let tipY = tailEdge == .bottom ? bounds.minY + 1 : bounds.maxY - 1
        let outer = NSBezierPath()
        outer.move(to: NSPoint(x: tailX - 13, y: bodyEdgeY))
        outer.line(to: NSPoint(x: tailX + 10, y: bodyEdgeY))
        outer.line(to: NSPoint(x: tailX + 3, y: tipY))
        outer.line(to: NSPoint(x: tailX - 4, y: tipY))
        outer.close()
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        outer.fill()

        let innerTipY = tailEdge == .bottom ? tipY + 5 : tipY - 5
        let inner = NSBezierPath()
        inner.move(to: NSPoint(x: tailX - 7, y: bodyEdgeY))
        inner.line(to: NSPoint(x: tailX + 4, y: bodyEdgeY))
        inner.line(to: NSPoint(x: tailX, y: innerTipY))
        inner.close()
        NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.82, alpha: 1).setFill()
        inner.fill()
    }
}
