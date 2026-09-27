import AppKit
import QuartzCore

@MainActor
final class TearProjectile {
    /// Isaac ties a tear's arc to its shot speed: it leaves the muzzle at a fraction of
    /// the travel speed and gravity pulls it back down, so faster tears fly a longer,
    /// flatter path and land further away.
    private static let launchSpeedFactor: CGFloat = 0.5
    private static let gravity: CGFloat = 290
    /// How much the tear shrinks at the top of its arc, where it is furthest away.
    private static let peakShrink: CGFloat = 0.18

    private let panel: NSPanel
    private let velocity: CGVector
    private let center: NSPoint
    private let baseSize: CGFloat
    private let peakHeight: CGFloat
    private var elapsed: TimeInterval = 0
    private let gravity: CGFloat
    private var verticalVelocity: CGFloat
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
        verticalVelocity = hypot(velocity.dx, velocity.dy) * Self.launchSpeedFactor
        gravity = Self.gravity * scale
        peakHeight = verticalVelocity * verticalVelocity / (2 * gravity)

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
        // The arc is the range: the tear bursts once gravity brings it back down.
        if height <= 0, verticalVelocity < 0 {
            landed = true
            return
        }
        let time = CGFloat(elapsed)
        let scale = 1 - Self.peakShrink * min(1, max(0, height / peakHeight))
        let size = baseSize * scale
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
