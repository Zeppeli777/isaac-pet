import AppKit
import QuartzCore

@MainActor
protocol PetViewDelegate: AnyObject {
    func petViewDidSingleClick(_ view: PetView)
    func petViewDidDoubleClick(_ view: PetView)
    func petViewDidBeginDragging(_ view: PetView)
    func petView(_ view: PetView, draggedTo windowOrigin: NSPoint)
    func petViewDidEndDragging(_ view: PetView)
    func petView(_ view: PetView, showContextMenu event: NSEvent)
    func petView(_ view: PetView, changedKeyCode keyCode: UInt16, isDown: Bool, isRepeat: Bool) -> Bool
}

@MainActor
final class PetView: NSView {
    weak var delegate: PetViewDelegate?
    var spriteFrame: SpriteFrame? {
        didSet { replaceLayerContents() }
    }

    private var mouseDownScreenPoint = NSPoint.zero
    private var mouseDownWindowOrigin = NSPoint.zero
    private var didDrag = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureBackingLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureBackingLayer()
    }

    private func configureBackingLayer() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
    }

    private func replaceLayerContents() {
        // Replacing CALayer.contents swaps the complete transparent frame atomically. This avoids
        // partial dirty-rect redraws retaining pixels when the pointer changes direction quickly.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = spriteFrame?.cgImage
        CATransaction.commit()
    }

    func hasVisiblePixel(at point: NSPoint) -> Bool {
        spriteFrame?.isOpaque(at: point, in: bounds) ?? false
    }

    override func mouseDown(with event: NSEvent) {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(fireSingleClick),
            object: nil
        )
        mouseDownScreenPoint = NSEvent.mouseLocation
        mouseDownWindowOrigin = window?.frame.origin ?? .zero
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        let delta = NSPoint(x: location.x - mouseDownScreenPoint.x, y: location.y - mouseDownScreenPoint.y)
        if !didDrag, hypot(delta.x, delta.y) >= 3 {
            didDrag = true
            delegate?.petViewDidBeginDragging(self)
        }
        guard didDrag else { return }
        delegate?.petView(
            self,
            draggedTo: NSPoint(x: mouseDownWindowOrigin.x + delta.x, y: mouseDownWindowOrigin.y + delta.y)
        )
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            delegate?.petViewDidEndDragging(self)
            return
        }
        if event.clickCount >= 2 {
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(fireSingleClick),
                object: nil
            )
            delegate?.petViewDidDoubleClick(self)
        } else {
            perform(
                #selector(fireSingleClick),
                with: nil,
                afterDelay: 0.22,
                inModes: [.common]
            )
        }
    }

    @objc private func fireSingleClick() {
        delegate?.petViewDidSingleClick(self)
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.petView(self, showContextMenu: event)
    }

    override func keyDown(with event: NSEvent) {
        if delegate?.petView(
            self,
            changedKeyCode: event.keyCode,
            isDown: true,
            isRepeat: event.isARepeat
        ) == true { return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if delegate?.petView(
            self,
            changedKeyCode: event.keyCode,
            isDown: false,
            isRepeat: event.isARepeat
        ) == true { return }
        super.keyUp(with: event)
    }
}
