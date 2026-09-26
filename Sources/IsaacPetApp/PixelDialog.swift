import AppKit

/// Modal game-style dialog replacing NSAlert. Runs a nested NSApp modal session so
/// call sites keep their synchronous control flow. All dialogs run through
/// `presentForm`; after each one closes, `onDismiss` lets the host restore the
/// floating pet (the activate/deactivate dance every NSAlert call site used to do).
@MainActor
enum PixelDialog {
    struct Button {
        let identifier: String
        let title: String
        var isDefault = false
        var isCancel = false

        init(identifier: String, title: String, isDefault: Bool = false, isCancel: Bool = false) {
            self.identifier = identifier
            self.title = title
            self.isDefault = isDefault
            self.isCancel = isCancel
        }
    }

    /// Set by the host (PetController) once at startup.
    static var onDismiss: (() -> Void)?

    private static let columnWidth: CGFloat = 440

    static func presentMessage(title: String, message: String, buttonTitle: String = "知道了") {
        presentForm(title: title, message: message, content: nil, initialFirstResponder: nil, buttons: [
            Button(identifier: "ok", title: buttonTitle, isDefault: true, isCancel: true),
        ])
    }

    /// Destructive confirms keep Enter on the safe choice, like NSAlert's warning style.
    static func confirm(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String = "取消",
        isDestructive: Bool = false
    ) -> Bool {
        presentForm(
            title: title,
            message: message,
            content: nil,
            initialFirstResponder: nil,
            buttons: [
                Button(identifier: "confirm", title: confirmTitle, isDefault: !isDestructive),
                Button(identifier: "cancel", title: cancelTitle, isDefault: isDestructive, isCancel: true),
            ]
        ) == "confirm"
    }

    static func prompt(
        title: String,
        message: String? = nil,
        placeholder: String = "",
        defaultValue: String = "",
        confirmTitle: String = "确定",
        cancelTitle: String = "取消"
    ) -> String? {
        let field = PixelStyledField()
        field.placeholderString = placeholder
        field.stringValue = defaultValue
        let result = presentForm(
            title: title,
            message: message,
            content: field,
            initialFirstResponder: field,
            buttons: [
                Button(identifier: "confirm", title: confirmTitle, isDefault: true),
                Button(identifier: "cancel", title: cancelTitle, isCancel: true),
            ]
        )
        return result == "confirm" ? field.stringValue : nil
    }

    /// Shows `content` (a form view) inside the dialog and returns the pressed
    /// button's identifier.
    @discardableResult
    static func presentForm(
        title: String,
        message: String?,
        content: NSView?,
        initialFirstResponder: NSView?,
        buttons: [Button]
    ) -> String {
        let handler = DialogButtonClickHandler {
            NSApp.stopModal(withCode: NSApplication.ModalResponse($0))
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        if let message, !message.isEmpty {
            let messageRow = NSTextField(wrappingLabelWithString: message)
            messageRow.font = PixelFont.speech
            messageRow.textColor = PixelStyle.textColor
            stack.addArrangedSubview(messageRow)
        }
        if let content {
            stack.addArrangedSubview(content)
        }

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        for (index, button) in buttons.enumerated() {
            let pixelButton = PixelButton(title: button.title, target: handler, action: #selector(DialogButtonClickHandler.buttonPressed(_:)))
            pixelButton.tag = index
            pixelButton.isDefaultStyled = button.isDefault
            if button.isDefault {
                pixelButton.keyEquivalent = "\r"
            }
            if button.isCancel {
                pixelButton.keyEquivalent = "\u{1b}"
            }
            buttonRow.addArrangedSubview(pixelButton)
        }
        // Spacer pushes the buttons to the trailing edge.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonRow.insertArrangedSubview(spacer, at: 0)
        stack.addArrangedSubview(buttonRow)
        if let beforeButtons = stack.arrangedSubviews.dropLast().last {
            stack.setCustomSpacing(16, after: beforeButtons)
        }

        let contentWidth = content?.frame.width ?? 0
        let dialogWidth = max(columnWidth, contentWidth)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = stack.widthAnchor.constraint(equalToConstant: dialogWidth)
        widthConstraint.isActive = true
        let fittingHeight = max(96, stack.fittingSize.height)

        let window = PixelWindow(
            size: NSSize(
                width: dialogWidth + (PixelWindow.borderWidth + PixelWindow.contentPadding) * 2,
                height: fittingHeight + PixelWindow.borderWidth * 2 + PixelWindow.contentPadding + PixelWindow.headerHeight
            ),
            title: title,
            resizable: false
        )
        window.contentContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: window.contentContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentContainer.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentContainer.bottomAnchor),
        ])

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        if let initialFirstResponder {
            window.makeFirstResponder(initialFirstResponder)
        }
        let response = NSApp.runModal(for: window).rawValue
        window.orderOut(nil)
        onDismiss?()
        guard buttons.indices.contains(response) else {
            return buttons.first(where: \.isCancel)?.identifier ?? "cancel"
        }
        return buttons[response].identifier
    }
}

@MainActor
private final class DialogButtonClickHandler: NSObject {
    private let onButton: (Int) -> Void

    init(onButton: @escaping (Int) -> Void) {
        self.onButton = onButton
    }

    @objc func buttonPressed(_ sender: NSButton) {
        onButton(sender.tag)
    }
}

/// Single-line field with pixel font and paper styling for dialogs and forms.
@MainActor
final class PixelStyledField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        font = PixelFont.speech
        textColor = PixelStyle.textColor
        backgroundColor = PixelStyle.fillColor
        drawsBackground = true
        isBezeled = true
        bezelStyle = .squareBezel
        focusRingType = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PixelStyledField is created in code only")
    }
}
