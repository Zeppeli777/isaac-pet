import AppKit
import IsaacPetCore
import QuartzCore

/// Plays the card-draw reveal above the pet's head: the card shuffles
/// face-to-back around a tilted vertical axis for two seconds, zooms toward
/// the viewer to show the result, then settles back to rest size. The text
/// panel (CardBubbleController) takes over once this timeline finishes.
@MainActor
final class CardRevealController: NSObject {
    private let panel: NSPanel
    private let spinView: CardSpinView
    private var petFrame = NSRect.zero
    private var screenFrame = NSRect.zero

    override init() {
        spinView = CardSpinView(frame: NSRect(x: 0, y: 0, width: 240, height: 280))
        panel = NSPanel(
            contentRect: spinView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.contentView = spinView
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

    func prepare(
        spriteFrame: SpriteFrame,
        backFrame: SpriteFrame,
        anchoredTo petFrame: NSRect,
        in screenFrame: NSRect,
        scale: CGFloat
    ) {
        self.petFrame = petFrame
        self.screenFrame = screenFrame
        spinView.configure(front: spriteFrame, back: backFrame, scale: scale)
        let size = spinView.requiredPanelSize()
        panel.setContentSize(size)
        spinView.frame = NSRect(origin: .zero, size: size)
        spinView.advance(to: 0)
        updatePosition()
        panel.orderFrontRegardless()
    }

    /// Drives the shuffle → zoom → settle timeline. Returns once the card has
    /// settled; throws on cancellation, leaving the panel hidden.
    func run() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        while true {
            try Task.checkCancellation()
            if spinView.advance(to: ProcessInfo.processInfo.systemUptime - start) { break }
            try await Task.sleep(nanoseconds: 16_000_000)
        }
        hide()
    }

    func updateAnchor(petFrame: NSRect, screenFrame: NSRect) {
        guard isVisible else { return }
        self.petFrame = petFrame
        self.screenFrame = screenFrame
        updatePosition()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func stop() {
        panel.close()
    }

    private func updatePosition() {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return }
        let size = panel.frame.size
        let edgePadding: CGFloat = 8
        let minimumX = screenFrame.minX + edgePadding
        let maximumX = max(minimumX, screenFrame.maxX - size.width - edgePadding)
        let originX = min(max(petFrame.midX - size.width / 2, minimumX), maximumX)

        // The card hovers about one card-height above the pet's head, staying
        // put while the pet roams underneath it.
        let centerY = petFrame.maxY + spinView.restCardHeight
        let originY = min(
            max(centerY - size.height / 2, screenFrame.minY + edgePadding),
            max(screenFrame.minY + edgePadding, screenFrame.maxY - size.height - edgePadding)
        )
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}

/// The floating card layer plus the phase math for the reveal timeline.
/// `advance(to:)` is timeline-driven (no implicit CA animations) so QA can
/// freeze exact moments and the pet controller can cancel mid-flight.
@MainActor
final class CardSpinView: NSView {
    private var front: CGImage?
    private var back: CGImage?
    private var scale: CGFloat = 1

    private let cardLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        cardLayer.contentsGravity = .resize
        cardLayer.magnificationFilter = .nearest
        cardLayer.minificationFilter = .nearest
        cardLayer.isOpaque = false
        layer?.addSublayer(cardLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(front: SpriteFrame, back: SpriteFrame, scale: CGFloat) {
        self.front = front.cgImage
        self.back = back.cgImage
        self.scale = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardLayer.bounds = NSRect(origin: .zero, size: cardSize)
        cardLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        cardLayer.contents = front.cgImage
        cardLayer.transform = CATransform3DIdentity
        CATransaction.commit()
        needsLayout = true
    }

    private var cardSize: NSSize {
        guard let front else { return .zero }
        return NSSize(
            width: CGFloat(front.width) * 4 * scale,
            height: CGFloat(front.height) * 4 * scale
        )
    }

    /// Panel must hold the zoomed card with margin; transforms may overflow a
    /// tight window frame, which would clip the reveal.
    func requiredPanelSize() -> NSSize {
        let factor = CGFloat(TarotDrawPolicy.zoomScale) * 1.15
        return NSSize(width: ceil(cardSize.width * factor), height: ceil(cardSize.height * factor))
    }

    var restCardHeight: CGFloat { cardSize.height }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    /// Advances the timeline to `elapsed` seconds since the shuffle started.
    /// Returns true when the card has settled back to rest.
    @discardableResult
    func advance(to elapsed: TimeInterval) -> Bool {
        guard let front else { return true }
        let spin = TarotDrawPolicy.spinDuration
        let zoomIn = TarotDrawPolicy.zoomInDuration
        let hold = TarotDrawPolicy.zoomHoldDuration
        let zoomOut = TarotDrawPolicy.zoomOutDuration
        let zoomScale = CGFloat(TarotDrawPolicy.zoomScale)

        var angle: CGFloat = 0
        var tilt: CGFloat = TarotDrawPolicy.tiltAngle
        var zoom: CGFloat = 1
        var bobbing = true

        if elapsed < spin {
            let progress = CGFloat(elapsed / spin)
            // Two full face-to-back rotations, easing out into the reveal.
            angle = .pi * 4 * Self.easeInOutCubic(progress)
        } else if elapsed < spin + zoomIn {
            angle = .pi * 4
            let progress = CGFloat((elapsed - spin) / zoomIn)
            tilt *= 1 - Self.easeOutCubic(progress)
            zoom = 1 + (zoomScale - 1) * Self.easeOutBack(progress)
            bobbing = false
        } else if elapsed < spin + zoomIn + hold {
            angle = .pi * 4
            tilt = 0
            zoom = zoomScale
            bobbing = false
        } else if elapsed < spin + zoomIn + hold + zoomOut {
            angle = .pi * 4
            tilt = 0
            let progress = CGFloat((elapsed - spin - zoomIn - hold) / zoomOut)
            zoom = zoomScale + (1 - zoomScale) * progress * progress
            bobbing = false
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cardLayer.contents = front
            cardLayer.transform = CATransform3DIdentity
            cardLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
            return true
        }

        var transform = CATransform3DIdentity
        transform.m34 = -1 / 600
        transform = CATransform3DRotate(transform, angle, 0, 1, 0)
        transform = CATransform3DRotate(transform, tilt, 0, 0, 1)
        transform = CATransform3DScale(transform, zoom, zoom, 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The back design shows whenever the card passes edge-on.
        cardLayer.contents = cos(angle) >= 0 ? front : back
        cardLayer.transform = transform
        let bob: CGFloat = bobbing
            ? CGFloat(sin(elapsed * 2 * .pi / 1.2)) * 4
            : 0
        cardLayer.position = CGPoint(x: bounds.midX, y: bounds.midY + bob)
        CATransaction.commit()
        return false
    }

    static func easeInOutCubic(_ progress: CGFloat) -> CGFloat {
        progress < 0.5
            ? 4 * progress * progress * progress
            : 1 - pow(-2 * progress + 2, 3) / 2
    }

    static func easeOutCubic(_ progress: CGFloat) -> CGFloat {
        1 - pow(1 - progress, 3)
    }

    static func easeOutBack(_ progress: CGFloat) -> CGFloat {
        let overshoot: CGFloat = 1.70158
        let c3 = overshoot + 1
        return 1 + c3 * pow(progress - 1, 3) + overshoot * pow(progress - 1, 2)
    }
}
