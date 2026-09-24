import AppKit
import IsaacPetCore
import UniformTypeIdentifiers

/// “LLM 设置”弹窗的输入区：服务格式、Base URL、API Key、模型和导入配置文件。
final class LLMSettingsAccessoryView: NSView {
    var onError: ((String, String) -> Void)?

    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let baseURLField = NSTextField(string: "")
    private let keyField = NSSecureTextField(string: "")
    private let modelField = NSTextField(string: "")

    private static let formatTitles = ["OpenAI 兼容", "Anthropic 兼容"]
    private static let openAIURLPlaceholder = "https://api.openai.com/v1"
    private static let anthropicURLPlaceholder = "https://api.anthropic.com"

    var initialFirstResponder: NSView { baseURLField }

    init(existingConfig: LLMConnectionConfig?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 470, height: 148))

        let formatLabel = NSTextField(labelWithString: "服务格式")
        formatLabel.frame = NSRect(x: 0, y: 122, width: 64, height: 22)
        formatPopup.frame = NSRect(x: 70, y: 118, width: 170, height: 26)
        formatPopup.addItems(withTitles: Self.formatTitles)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)

        let importButton = NSButton(title: "导入配置文件…", target: self, action: #selector(importConfigFile))
        importButton.bezelStyle = .rounded
        importButton.frame = NSRect(x: 280, y: 118, width: 190, height: 26)

        let baseURLLabel = NSTextField(labelWithString: "Base URL")
        baseURLLabel.frame = NSRect(x: 0, y: 86, width: 64, height: 22)
        baseURLField.frame = NSRect(x: 70, y: 82, width: 400, height: 24)

        let keyLabel = NSTextField(labelWithString: "API Key")
        keyLabel.frame = NSRect(x: 0, y: 50, width: 64, height: 22)
        keyField.frame = NSRect(x: 70, y: 46, width: 400, height: 24)
        keyField.placeholderString = "sk-…（本地服务可留空）"

        let modelLabel = NSTextField(labelWithString: "模型")
        modelLabel.frame = NSRect(x: 0, y: 14, width: 64, height: 22)
        modelField.frame = NSRect(x: 70, y: 10, width: 400, height: 24)
        modelField.placeholderString = "例如 gpt-5-mini、claude-sonnet-4-5"

        for view in [
            formatLabel, formatPopup, importButton,
            baseURLLabel, baseURLField,
            keyLabel, keyField,
            modelLabel, modelField,
        ] { addSubview(view) }

        if let existingConfig {
            apply(existingConfig)
        } else {
            formatPopup.selectItem(at: 0)
            baseURLField.placeholderString = Self.openAIURLPlaceholder
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LLMSettingsAccessoryView is created in code only")
    }

    func apply(_ config: LLMConnectionConfig) {
        formatPopup.selectItem(at: config.apiFormat == .anthropic ? 1 : 0)
        baseURLField.stringValue = config.baseURL
        keyField.stringValue = config.apiKey
        modelField.stringValue = config.model
        baseURLField.placeholderString = placeholder(for: config.apiFormat)
    }

    func currentConfig() -> LLMConnectionConfig {
        LLMConnectionConfig(
            baseURL: baseURLField.stringValue,
            apiKey: keyField.stringValue,
            model: modelField.stringValue,
            apiFormat: formatPopup.indexOfSelectedItem == 1 ? .anthropic : .openai
        )
    }

    private func placeholder(for format: LLMAPIFormat) -> String {
        format == .anthropic ? Self.anthropicURLPlaceholder : Self.openAIURLPlaceholder
    }

    @objc private func formatChanged() {
        let format: LLMAPIFormat = formatPopup.indexOfSelectedItem == 1 ? .anthropic : .openai
        baseURLField.placeholderString = placeholder(for: format)
    }

    @objc private func importConfigFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .text]
        panel.message = "选择包含 baseUrl、apiKey、model、apiFormat 的 JSON 配置文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            apply(try LLMConnectionConfig.parseImported(data))
        } catch {
            onError?("无法导入配置", error.localizedDescription)
        }
    }
}
