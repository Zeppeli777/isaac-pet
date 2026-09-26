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
        field.frame = NSRect(x: 0, y: 0, width: 440, height: 24)
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
        let (window, handler) = buildDialogWindow(title: title, message: message, content: content, buttons: buttons)
        handler.onButton = { [weak handler] code in
            guard let handler, handler.isModalRunning else { return }
            handler.isModalRunning = false
            NSApp.stopModal(withCode: NSApplication.ModalResponse(code))
        }
        // A dialog closed through any other path (the close button, Cmd-W) must still
        // end the modal session, or the app stays trapped in an invisible modal loop.
        handler.onCloseWhileModal = { [weak handler] in
            guard let handler, handler.isModalRunning else { return }
            handler.isModalRunning = false
            NSApp.stopModal(withCode: NSApplication.ModalResponse(buttons.count))
        }

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        if let initialFirstResponder {
            window.makeFirstResponder(initialFirstResponder)
        }
        handler.isModalRunning = true
        let response = NSApp.runModal(for: window).rawValue
        handler.isModalRunning = false
        window.orderOut(nil)
        onDismiss?()
        guard buttons.indices.contains(response) else {
            return buttons.first(where: \.isCancel)?.identifier ?? "cancel"
        }
        return buttons[response].identifier
    }

    /// Builds the dialog's pixel window; split out so QA can render the real
    /// layout offscreen without entering a modal session.
    static func buildDialogWindow(
        title: String,
        message: String?,
        content: NSView?,
        buttons: [Button]
    ) -> (window: PixelWindow, handler: DialogButtonClickHandler) {
        let handler = DialogButtonClickHandler()

        // Manual vertical layout: deterministic for frame-based form contents
        // (the LLM settings view positions its controls with explicit frames).
        let column = NSView()
        column.translatesAutoresizingMaskIntoConstraints = false
        let dialogWidth = max(columnWidth, content?.frame.width ?? 0)

        // Width is pinned only for measurement; at window attach the edges carry
        // the content padding instead.
        let columnWidthConstraint = column.widthAnchor.constraint(equalToConstant: dialogWidth)
        var constraints: [NSLayoutConstraint] = [columnWidthConstraint]
        var previousBottom: NSLayoutYAxisAnchor = column.topAnchor
        if let message, !message.isEmpty {
            let messageRow = NSTextField(wrappingLabelWithString: message)
            messageRow.font = PixelFont.speech
            messageRow.textColor = PixelStyle.textColor
            messageRow.alignment = .left
            messageRow.translatesAutoresizingMaskIntoConstraints = false
            column.addSubview(messageRow)
            constraints += [
                messageRow.topAnchor.constraint(equalTo: previousBottom, constant: 4),
                messageRow.leadingAnchor.constraint(equalTo: column.leadingAnchor),
                messageRow.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            ]
            previousBottom = messageRow.bottomAnchor
        }
        if let content {
            content.translatesAutoresizingMaskIntoConstraints = false
            column.addSubview(content)
            constraints += [
                content.topAnchor.constraint(equalTo: previousBottom, constant: 12),
                content.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            ]
            let contentHeight = content.frame.height > 0
                ? content.frame.height
                : max(24, content.intrinsicContentSize.height)
            constraints.append(content.heightAnchor.constraint(equalToConstant: contentHeight))
            if abs(content.frame.width - dialogWidth) < 1 {
                constraints.append(content.trailingAnchor.constraint(equalTo: column.trailingAnchor))
            }
            previousBottom = content.bottomAnchor
        }

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        for (index, button) in buttons.enumerated() {
            let pixelButton = PixelButton(title: button.title, target: nil, action: nil)
            pixelButton.target = handler
            pixelButton.action = #selector(DialogButtonClickHandler.buttonPressed(_:))
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
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(buttonRow)
        constraints += [
            buttonRow.topAnchor.constraint(equalTo: previousBottom, constant: 16),
            buttonRow.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            buttonRow.leadingAnchor.constraint(greaterThanOrEqualTo: column.leadingAnchor),
            column.bottomAnchor.constraint(equalTo: buttonRow.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)

        let columnFittedHeight = max(72, column.fittingSize.height)
        columnWidthConstraint.isActive = false

        let window = PixelWindow(
            size: NSSize(
                width: dialogWidth + PixelWindow.contentPadding * 2 + PixelWindow.borderWidth * 2,
                height: columnFittedHeight + PixelWindow.contentPadding * 2 + PixelWindow.borderWidth * 2 + PixelWindow.headerHeight
            ),
            title: title,
            resizable: false
        )
        window.delegate = handler
        window.contentContainer.addSubview(column)
        let inset = PixelWindow.contentPadding
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: window.contentContainer.topAnchor, constant: inset),
            column.leadingAnchor.constraint(equalTo: window.contentContainer.leadingAnchor, constant: inset),
            column.trailingAnchor.constraint(equalTo: window.contentContainer.trailingAnchor, constant: -inset),
            column.bottomAnchor.constraint(equalTo: window.contentContainer.bottomAnchor, constant: -inset),
        ])
        return (window, handler)
    }
}

@MainActor
final class DialogButtonClickHandler: NSObject, NSWindowDelegate {
    var onButton: ((Int) -> Void)?
    /// Runs while the modal session is alive; invoked once when the window closes
    /// without a button press so the session cannot leak.
    var onCloseWhileModal: (() -> Void)?
    var isModalRunning = false

    @objc func buttonPressed(_ sender: NSButton) {
        onButton?(sender.tag)
    }

    func windowWillClose(_ notification: Notification) {
        onCloseWhileModal?()
        onCloseWhileModal = nil
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
