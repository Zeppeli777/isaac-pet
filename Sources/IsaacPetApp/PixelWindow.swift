import AppKit

/// Borderless game-style window: paper fill inside a stepped pixel frame, a
/// pixel-font title row with a pixel close button, background dragging, and a
/// corner grip for resizing. Hosts add their UI to `contentContainer`, which
/// sits inside the frame with the same paper background as the message box.
@MainActor
final class PixelWindow: NSWindow {
    static let borderWidth: CGFloat = 6
    static let headerHeight: CGFloat = 40
    static let contentPadding: CGFloat = 16
    static let gripSize = NSSize(width: 22, height: 22)

    private let chrome: PixelChromeView

    /// Where host content goes; autoresizing with the window.
    var contentContainer: NSView { chrome.contentContainer }

    init(size: NSSize, title: String, minSize: NSSize? = nil, resizable: Bool = true) {
        chrome = PixelChromeView(title: title, resizable: resizable)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        chrome.frame = NSRect(origin: .zero, size: size)
        contentView = chrome
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.moveToActiveSpace]
        if let minSize {
            self.minSize = minSize
        }
        chrome.closeButton.target = self
        chrome.closeButton.action = #selector(close)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    static func contentAreaRect(in bounds: NSRect) -> NSRect {
        NSRect(
            x: borderWidth + contentPadding,
            y: borderWidth + contentPadding,
            width: bounds.width - (borderWidth + contentPadding) * 2,
            height: bounds.height - borderWidth * 2 - contentPadding - headerHeight
        )
    }
}

@MainActor
private final class PixelChromeView: NSView {
    private let title: String
    private let isResizable: Bool
    fileprivate var contentContainer = NSView()
    fileprivate let closeButton = PixelButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
    private let titleAttributes = PixelStyle.textAttributes(
        size: PixelFont.titleSize,
        color: PixelStyle.accentColor
    )

    init(title: String, resizable: Bool) {
        self.title = title
        isResizable = resizable
        super.init(frame: .zero)
        closeButton.title = "×"
        closeButton.isDefaultStyled = false
        contentContainer.autoresizingMask = [.width, .height]
        contentContainer.frame = PixelWindow.contentAreaRect(in: bounds)
        addSubview(contentContainer)
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PixelChromeView is created in code only")
    }

    override var isOpaque: Bool { false }

    private var gripRect: NSRect {
        NSRect(
            x: bounds.maxX - PixelWindow.borderWidth - PixelWindow.gripSize.width,
            y: bounds.minY + PixelWindow.borderWidth,
            width: PixelWindow.gripSize.width,
            height: PixelWindow.gripSize.height
        )
    }

    override func layout() {
        super.layout()
        let bounds = bounds
        contentContainer.frame = PixelWindow.contentAreaRect(in: bounds)
        closeButton.frame = NSRect(
            x: bounds.maxX - PixelWindow.borderWidth - 10 - 24,
            y: bounds.maxY - PixelWindow.borderWidth - 8 - 24,
            width: 24,
            height: 24
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.shouldAntialias = false

        let border = PixelWindow.borderWidth
        let inner = PixelStyle.drawFrame(
            in: bounds,
            borderWidth: border,
            radius: 10
        )

        // Header row: divider line under the visual title bar.
        let headerY = bounds.maxY - border - PixelWindow.headerHeight
        PixelStyle.shadowColor.setFill()
        context.cgContext.fill(NSRect(x: inner.minX, y: headerY, width: inner.width, height: 2))

        // Title sits in the header row (visually top strip).
        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        (title as NSString).draw(
            at: NSPoint(
                x: inner.minX + 6,
                y: headerY + (PixelWindow.headerHeight - 2 - titleSize.height) / 2 + 2
            ),
            withAttributes: titleAttributes
        )

        // Resize grip: pixel staircase in the visually bottom-right corner.
        if isResizable {
            PixelStyle.shadowColor.setFill()
            let grip = gripRect
            for step in 0..<4 {
                let offset = CGFloat(step * 4)
                NSBezierPath(rect: NSRect(
                    x: grip.maxX - 4 - offset,
                    y: grip.minY + offset,
                    width: 4,
                    height: grip.height - offset
                )).fill()
            }
        }
        context.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        if isResizable, gripRect.contains(convert(event.locationInWindow, from: nil)) {
            trackResize()
        } else {
            super.mouseDown(with: event)
        }
    }

    private func trackResize() {
        guard let window else { return }
        let startFrame = window.frame
        let startMouse = NSEvent.mouseLocation
        let minimum = window.minSize
        let maximum = (window.screen ?? NSScreen.main)?.frame.size
            ?? NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            guard event.type == .leftMouseDragged else { break }
            let mouse = NSEvent.mouseLocation
            var width = startFrame.width + (mouse.x - startMouse.x)
            // Dragging the visually bottom edge downward (screen y decreases) grows height.
            var height = startFrame.height - (mouse.y - startMouse.y)
            width = min(max(width, minimum.width), maximum.width)
            height = min(max(height, minimum.height), maximum.height)
            window.setFrame(
                NSRect(
                    x: startFrame.minX,
                    y: startFrame.maxY - height,
                    width: width,
                    height: height
                ),
                display: true
            )
        }
    }
}
