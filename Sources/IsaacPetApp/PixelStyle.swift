import AppKit

/// Shared palette and pixel-drawing helpers for the game-style UI surfaces
/// (speech bubble, windows, dialogs, buttons). Colours are sampled from the
/// in-game message box reference (Assets/Source/Emotes/reference-message-box.png).
@MainActor
enum PixelStyle {
    static let borderColor = NSColor(calibratedRed: 0.70, green: 0.68, blue: 0.66, alpha: 1)
    static let fillColor = NSColor(calibratedRed: 0.93, green: 0.91, blue: 0.90, alpha: 1)
    static let shadowColor = NSColor(calibratedRed: 0.82, green: 0.80, blue: 0.79, alpha: 1)
    static let textColor = NSColor(calibratedRed: 0.24, green: 0.23, blue: 0.22, alpha: 1)
    static let disabledTextColor = NSColor(calibratedRed: 0.52, green: 0.50, blue: 0.49, alpha: 1)
    /// Brick red accent carried over from the window headings.
    static let accentColor = NSColor(calibratedRed: 0.76, green: 0.26, blue: 0.20, alpha: 1)
    /// Buttons: dark warm outline around a slightly darker paper face.
    static let buttonBorderColor = NSColor(calibratedRed: 0.34, green: 0.31, blue: 0.29, alpha: 1)
    static let buttonFaceColor = NSColor(calibratedRed: 0.87, green: 0.85, blue: 0.83, alpha: 1)
    static let buttonFaceDownColor = NSColor(calibratedRed: 0.77, green: 0.75, blue: 0.73, alpha: 1)

    static func textAttributes(size: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: PixelFont.font(ofSize: size),
            .foregroundColor: color,
        ]
    }

    /// A quarter-circle quantized onto the pixel grid, built from per-row rects so the
    /// corners step like the game's message box instead of antialiasing into a curve.
    static func pixelRoundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
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

    /// Draws a stepped pixel frame (border + fill + shadow lip along the visually
    /// bottom edge) and returns the rect available for inner content.
    @discardableResult
    static func drawFrame(
        in rect: NSRect,
        borderWidth: CGFloat,
        radius: CGFloat,
        fill: NSColor = fillColor,
        border: NSColor = borderColor
    ) -> NSRect {
        guard let context = NSGraphicsContext.current else { return rect.insetBy(dx: borderWidth, dy: borderWidth) }
        context.saveGraphicsState()
        context.shouldAntialias = false

        border.setFill()
        pixelRoundedPath(rect, radius: radius).fill()

        let inner = rect.insetBy(dx: borderWidth, dy: borderWidth)
        let innerPath = pixelRoundedPath(inner, radius: max(1, radius - borderWidth))
        fill.setFill()
        innerPath.fill()

        context.saveGraphicsState()
        innerPath.addClip()
        shadowColor.setFill()
        context.cgContext.fill(NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: 2))
        context.restoreGraphicsState()

        context.restoreGraphicsState()
        return inner
    }
}

/// A thin stepped pixel frame for embedding scroll views and form groups.
@MainActor
final class PixelFrameBoxView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        PixelStyle.drawFrame(
            in: bounds,
            borderWidth: 3,
            radius: 5,
            fill: .clear
        )
    }
}

/// Table row view with game-palette selection highlight (brick red instead of
/// the system accent blue).
@MainActor
final class PixelTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle == .regular else { return }
        PixelStyle.accentColor.withAlphaComponent(0.22).setFill()
        bounds.fill()
    }
}
