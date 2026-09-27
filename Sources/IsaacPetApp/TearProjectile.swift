import AppKit
import QuartzCore

@MainActor
final class TearProjectile {
    /// Per the tear mechanics the wiki describes, a tear leaves the muzzle with no
    /// upward rate: its height starts at the character's tear height and gravity pulls
    /// it down from there, so the flight reads as a flat line that drops near its end.
    private static let gravity: CGFloat = 120
    /// How far below the launch line the tear falls before it bursts.
    private static let dropBudget: CGFloat = 80

    private let panel: NSPanel
    private let velocity: CGVector
    private let center: NSPoint
    private let baseSize: CGFloat
    private let dropBudget: CGFloat
    private var elapsed: TimeInterval = 0
    private let gravity: CGFloat
    private var verticalVelocity: CGFloat = 0
    private var height: CGFloat = 0
    private(set) var landed = false

    var frame: NSRect { panel.frame }

    init(
        spriteFrame: SpriteFrame,
        center: NSPoint,
        velocity: CGVector,
        size: CGFloat,
        scale: CGFloat
    ) {
        self.velocity = velocity
        self.center = center
        baseSize = size
        gravity = Self.gravity * scale
        dropBudget = Self.dropBudget * scale

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
        elapsed += delta
        verticalVelocity -= gravity * delta
        height += verticalVelocity * delta
        // The drop is the range: the tear bursts once it has sunk below its launch line.
        if -height >= dropBudget {
            landed = true
            return
        }
        let time = CGFloat(elapsed)
        let size = baseSize
        let origin = NSPoint(
            x: center.x + velocity.dx * time - size / 2,
            y: center.y + velocity.dy * time + height - size / 2
        )
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: size, height: size)), display: true)
    }

    func remove() {
        panel.orderOut(nil)
    }
}

/// One of the small droplets a tear bursts into when its arc ends.
@MainActor
final class TearDrop {
    private static let gravity: CGFloat = 520
    private static let lifetime: TimeInterval = 0.36

    private let panel: NSPanel
    private let velocity: CGVector
    private let gravity: CGFloat
    private var verticalVelocity: CGFloat
    private let origin: NSPoint
    private var elapsed: TimeInterval = 0

    init(
        spriteFrame: SpriteFrame,
        center: NSPoint,
        velocity: CGVector,
        size: CGFloat,
        scale: CGFloat
    ) {
        self.velocity = velocity
        self.origin = center
        verticalVelocity = velocity.dy
        gravity = Self.gravity * scale

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

    /// Returns true once the droplet has faded out.
    func update(delta: TimeInterval) -> Bool {
        elapsed += delta
        guard elapsed < Self.lifetime else { return true }
        let time = CGFloat(elapsed)
        let size = panel.frame.width
        panel.setFrameOrigin(NSPoint(
            x: origin.x + velocity.dx * time - size / 2,
            y: origin.y + verticalVelocity * time - gravity * time * time / 2 - size / 2
        ))
        panel.contentView?.layer?.opacity = Float(1 - elapsed / Self.lifetime)
        return false
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
