import AppKit
import IsaacPetCore
import QuartzCore

/// Shows the in-game style emote bubble above the pet's head. The bubble artwork carries
/// its tail at roughly 81% of its width, so the panel is placed with that column over the
/// pet's centre line, like the game does above Isaac's head.
@MainActor
final class EmoteBubbleController: NSObject {
    /// The emote art is a 48px grid sprite; magnifying it twice keeps it head-sized next
    /// to the 192pt pet and stays on whole pixels under .nearest filtering.
    private static let magnification: CGFloat = 2
    /// Horizontal position of the tail tip inside the emote artwork, as a width fraction.
    private static let tailAnchor: CGFloat = 0.81

    private let panel: NSPanel
    private let emoteView: EmoteView
    private var hideTimer: Timer?
    private var petFrame = NSRect.zero
    private var screenFrame = NSRect.zero

    override init() {
        emoteView = EmoteView(frame: NSRect(x: 0, y: 0, width: 96, height: 102))
        panel = NSPanel(
            contentRect: emoteView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.contentView = emoteView
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
        _ spriteFrame: SpriteFrame,
        anchoredTo petFrame: NSRect,
        in screenFrame: NSRect,
        scale: CGFloat
    ) {
        self.petFrame = petFrame
        self.screenFrame = screenFrame

        hideTimer?.invalidate()
        let size = NSSize(
            width: CGFloat(spriteFrame.width) * Self.magnification * scale,
            height: CGFloat(spriteFrame.height) * Self.magnification * scale
        )
        emoteView.setSpriteFrame(spriteFrame)
        panel.setContentSize(size)
        emoteView.frame = NSRect(origin: .zero, size: size)
        updatePosition()
        panel.orderFrontRegardless()

        let timer = Timer(
            timeInterval: SpeechBubblePolicy.emoteDisplayDuration,
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
        let originX = min(max(petFrame.midX - size.width * Self.tailAnchor, minimumX), maximumX)

        let aboveY = petFrame.maxY - 6
        let originY = min(aboveY, screenFrame.maxY - size.height - edgePadding)
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}

@MainActor
private final class EmoteView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setSpriteFrame(_ spriteFrame: SpriteFrame) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = spriteFrame.cgImage
        CATransaction.commit()
    }
}
