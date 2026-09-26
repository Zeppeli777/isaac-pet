import AppKit

/// Game-style push button: stepped pixel border around a paper face, pixel-font
/// label, hover/pressed/disabled states. Replaces the regularSquare+monospace
/// button convention across the tool windows and dialogs.
@MainActor
final class PixelButton: NSButton {
    var fontSize: CGFloat = PixelFont.speechSize {
        didSet {
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }
    /// Default buttons get the brick-red outline, like a game's highlighted choice.
    var isDefaultStyled = false {
        didSet { needsDisplay = true }
    }

    private var isHovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isBordered = false
        setButtonType(.momentaryPushIn)
        // .inVisibleRect keeps the area following the button's bounds automatically.
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let textSize = (title as NSString).size(withAttributes: [
            .font: PixelFont.font(ofSize: fontSize)
        ])
        return NSSize(width: ceil(textSize.width) + 26, height: ceil(textSize.height) + 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.shouldAntialias = false

        let pressed = cell?.isHighlighted == true
        let borderColor: NSColor
        if isDefaultStyled {
            borderColor = PixelStyle.accentColor
        } else if isHovering, isEnabled {
            borderColor = PixelStyle.buttonBorderColor.blended(
                withFraction: 0.25,
                of: PixelStyle.accentColor
            ) ?? PixelStyle.buttonBorderColor
        } else {
            borderColor = PixelStyle.buttonBorderColor
        }

        // The outline is the ring left between the outer fill and the inner face.
        let outer = bounds.insetBy(dx: 0.5, dy: 0.5)
        borderColor.setFill()
        PixelStyle.pixelRoundedPath(outer, radius: 6).fill()

        let faceColor = !isEnabled
            ? PixelStyle.fillColor
            : (pressed ? PixelStyle.buttonFaceDownColor : PixelStyle.buttonFaceColor)
        faceColor.setFill()
        // When pressed the face shifts one pixel toward the visually bottom edge,
        // like a physical button.
        let shift: CGFloat = pressed ? -1 : 0
        PixelStyle.pixelRoundedPath(
            NSRect(
                x: outer.minX + 3,
                y: outer.minY + 3 + shift,
                width: outer.width - 6,
                height: outer.height - 6
            ),
            radius: 3
        ).fill()

        let attributes = PixelStyle.textAttributes(
            size: fontSize,
            color: isEnabled ? PixelStyle.textColor : PixelStyle.disabledTextColor
        )
        let textSize = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(
            at: NSPoint(
                x: bounds.midX - textSize.width / 2,
                y: bounds.midY - textSize.height / 2 + shift
            ),
            withAttributes: attributes
        )
        context.restoreGraphicsState()
    }
}
