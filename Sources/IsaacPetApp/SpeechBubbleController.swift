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
final class SpeechBubbleView: NSView {
    enum TailEdge {
        case top
        case bottom
    }

    private enum Layout {
        static let tailHeight: CGFloat = 14
        static let outerInset: CGFloat = 3
        static let border: CGFloat = 4
        static let cornerRadius: CGFloat = 7
        static let textHorizontalInset: CGFloat = 13
        static let textVerticalInset: CGFloat = 10
        static let maximumTextWidth: CGFloat = 236
        static let minimumBodyWidth: CGFloat = 88
        static let minimumBodyHeight: CGFloat = 43
        static let bottomShadow: CGFloat = 2
    }

    // Palette sampled from the in-game message box reference
    // (Assets/Source/Emotes/reference-message-box.png).
    private static let borderColor = NSColor(calibratedRed: 0.70, green: 0.68, blue: 0.66, alpha: 1)
    private static let fillColor = NSColor(calibratedRed: 0.93, green: 0.91, blue: 0.90, alpha: 1)
    private static let shadowColor = NSColor(calibratedRed: 0.82, green: 0.80, blue: 0.79, alpha: 1)
    private static let textColor = NSColor(calibratedRed: 0.24, green: 0.23, blue: 0.22, alpha: 1)

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

    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byCharWrapping
        style.lineSpacing = 2
        return style
    }()

    private static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: PixelFont.speech,
        .foregroundColor: textColor,
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
        Self.borderColor.setFill()
        pixelRoundedPath(rect, radius: Layout.cornerRadius).fill()

        let inner = rect.insetBy(dx: Layout.border, dy: Layout.border)
        let innerPath = pixelRoundedPath(inner, radius: Layout.cornerRadius - Layout.border)
        Self.fillColor.setFill()
        innerPath.fill()

        // The reference box darkens along its visually bottom inner edge, giving the
        // paper a lip; speckles keep the subtle grain of the game's message paper.
        if let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            innerPath.addClip()
            Self.shadowColor.setFill()
            NSBezierPath(rect: NSRect(
                x: inner.minX,
                y: inner.minY,
                width: inner.width,
                height: Layout.bottomShadow
            )).fill()
            drawPaperSpeckles(in: inner)
            context.restoreGraphicsState()
        }
    }

    private func drawPaperSpeckles(in innerRect: NSRect) {
        guard innerRect.width > 60, innerRect.height > 36 else { return }
        Self.shadowColor.setFill()
        let spots: [NSPoint] = [
            NSPoint(x: 0.16, y: 0.32),
            NSPoint(x: 0.71, y: 0.24),
            NSPoint(x: 0.86, y: 0.62),
            NSPoint(x: 0.31, y: 0.70),
        ]
        for spot in spots {
            let x = (innerRect.minX + innerRect.width * spot.x).rounded(.down)
            let y = (innerRect.minY + innerRect.height * spot.y).rounded(.down)
            NSBezierPath(rect: NSRect(x: x, y: y, width: 2, height: 2)).fill()
        }
    }

    /// A quarter-circle quantized onto the pixel grid, built from per-row rects so the
    /// corners step like the game's message box instead of antialiasing into a curve.
    private func pixelRoundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let left = Int(rect.minX.rounded(.down))
        let right = Int(rect.maxX.rounded(.up))
        let bottom = Int(rect.minY.rounded(.down))
        let top = Int(rect.maxY.rounded(.up))
        let radiusInt = Int(radius)
        for y in bottom..<top {
            let depth = min(y - bottom, top - 1 - y)
            let inset: Int
            if depth >= radiusInt {
                inset = 0
            } else {
                let offset = CGFloat(radiusInt - depth) - 0.5
                let span = sqrt(CGFloat(radiusInt * radiusInt) - offset * offset).rounded(.down)
                inset = radiusInt - Int(span)
            }
            path.append(NSBezierPath(rect: NSRect(
                x: CGFloat(left + inset),
                y: CGFloat(y),
                width: CGFloat(right - left - inset * 2),
                height: 1
            )))
        }
        return path
    }

    private func drawTail(from bodyRect: NSRect) {
        let downward = tailEdge == .bottom
        let direction: CGFloat = downward ? -1 : 1
        // Staircase tail: (step height, outer width, inner width, inner height). The
        // inner fill hugs the body side and leaves a border cap at the tip.
        let steps: [(height: CGFloat, outer: CGFloat, inner: CGFloat, innerHeight: CGFloat)] = [
            (5, 26, 20, 5),
            (5, 18, 12, 5),
            (4, 10, 4, 1),
        ]
        var y = downward ? bodyRect.minY : bodyRect.maxY
        for step in steps {
            let outerY = downward ? y - step.height : y
            let innerY = downward ? y - step.innerHeight : y
            Self.borderColor.setFill()
            NSBezierPath(rect: NSRect(
                x: tailX - step.outer / 2,
                y: outerY,
                width: step.outer,
                height: step.height
            )).fill()
            Self.fillColor.setFill()
            NSBezierPath(rect: NSRect(
                x: tailX - step.inner / 2,
                y: innerY,
                width: step.inner,
                height: step.innerHeight
            )).fill()
            y += direction * step.height
        }
    }
}
