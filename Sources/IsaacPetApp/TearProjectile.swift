import AppKit
import QuartzCore

@MainActor
final class TearProjectile {
    private let panel: NSPanel
    let velocity: CGVector
    let expiresAt: TimeInterval

    var frame: NSRect { panel.frame }

    init(
        spriteFrame: SpriteFrame,
        center: NSPoint,
        velocity: CGVector,
        size: CGFloat,
        expiresAt: TimeInterval
    ) {
        self.velocity = velocity
        self.expiresAt = expiresAt

        let rect = NSRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )
        let view = TearView(frame: NSRect(origin: .zero, size: rect.size), spriteFrame: spriteFrame)
        panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.orderFrontRegardless()
    }

    func update(delta: TimeInterval) {
        let origin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(
            x: origin.x + velocity.dx * delta,
            y: origin.y + velocity.dy * delta
        ))
    }

    func remove() {
        panel.orderOut(nil)
    }
}

@MainActor
private final class TearView: NSView {
    init(frame frameRect: NSRect, spriteFrame: SpriteFrame) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        layer?.contents = spriteFrame.cgImage
    }

    required init?(coder: NSCoder) {
        nil
    }
}
