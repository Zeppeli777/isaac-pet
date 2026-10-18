import AppKit
import IsaacPetCore
import UniformTypeIdentifiers

/// “LLM 设置”弹窗的输入区：服务商预设、服务格式、Base URL、API Key、模型、
/// 连接测试、拉取模型列表和导入配置文件。
final class LLMSettingsAccessoryView: NSView, NSTextFieldDelegate {
    var onError: ((String, String) -> Void)?
    /// 测试连接 / 拉取模型等操作的结论弹窗（设置窗体处于模态会话中，由宿主再叠一层模态展示）。
    var onInfo: ((String, String) -> Void)?

    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let baseURLField = NSTextField(string: "")
    private let keyField = NSSecureTextField(string: "")
    private let modelField = NSTextField(string: "")
    private let testButton = PixelButton(title: "测试连接", target: nil, action: nil)
    private let fetchButton = PixelButton(title: "拉取模型…", target: nil, action: nil)

    /// 预设正在回填字段时为 true，避免回填触发「手动改过 Base URL」的重置逻辑。
    private var isApplyingPreset = false

    private struct ProviderPreset {
        let label: String
        let baseURL: String
        let format: LLMAPIFormat
        let suggestedModel: String
    }

    /// 常见 OpenAI / Anthropic 兼容服务商预设：一键填写 Base URL 与格式。
    private static let presets: [ProviderPreset] = [
        ProviderPreset(label: "StepFun 阶跃星辰", baseURL: "https://api.stepfun.com/v1", format: .openai, suggestedModel: "step-2-16k"),
        ProviderPreset(label: "DeepSeek", baseURL: "https://api.deepseek.com", format: .openai, suggestedModel: "deepseek-chat"),
        ProviderPreset(label: "Moonshot Kimi", baseURL: "https://api.moonshot.cn/v1", format: .openai, suggestedModel: "kimi-k2-0905-preview"),
        ProviderPreset(label: "智谱 GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4", format: .openai, suggestedModel: "glm-4.6"),
        ProviderPreset(label: "SiliconFlow 硅基流动", baseURL: "https://api.siliconflow.cn/v1", format: .openai, suggestedModel: ""),
        ProviderPreset(label: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", format: .openai, suggestedModel: ""),
        ProviderPreset(label: "OpenAI", baseURL: "https://api.openai.com/v1", format: .openai, suggestedModel: "gpt-5-mini"),
        ProviderPreset(label: "Anthropic", baseURL: "https://api.anthropic.com", format: .anthropic, suggestedModel: "claude-sonnet-4-5"),
        ProviderPreset(label: "Ollama（本机）", baseURL: "http://localhost:11434/v1", format: .openai, suggestedModel: ""),
        ProviderPreset(label: "LM Studio（本机）", baseURL: "http://localhost:1234/v1", format: .openai, suggestedModel: ""),
    ]

    private static let formatTitles = ["OpenAI 兼容", "Anthropic 兼容"]
    private static let presetPlaceholder = "选择预设自动填写…"
    private static let openAIURLPlaceholder = "https://api.openai.com/v1"
    private static let anthropicURLPlaceholder = "https://api.anthropic.com"
    private static let reasoningHint = "兼容推理模型（如 step-r1-v-mini、deepseek-reasoner）：输出预算被思考占满时会自动加大预算重试；思考过程不会显示在气泡里。"

    var initialFirstResponder: NSView { baseURLField }

    init(existingConfig: LLMConnectionConfig?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 470, height: 240))

        let presetLabel = NSTextField(labelWithString: "服务商预设")
        presetLabel.frame = NSRect(x: 0, y: 212, width: 90, height: 22)
        presetPopup.frame = NSRect(x: 96, y: 208, width: 250, height: 26)
        presetPopup.addItems(withTitles: [Self.presetPlaceholder] + Self.presets.map(\.label))
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)

        let importButton = PixelButton(title: "导入配置文件…", target: self, action: #selector(importConfigFile))
        importButton.frame = NSRect(x: 356, y: 172, width: 114, height: 26)

        let formatLabel = NSTextField(labelWithString: "服务格式")
        formatLabel.frame = NSRect(x: 0, y: 176, width: 64, height: 22)
        formatPopup.frame = NSRect(x: 70, y: 172, width: 170, height: 26)
        formatPopup.addItems(withTitles: Self.formatTitles)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        testButton.frame = NSRect(x: 252, y: 172, width: 96, height: 26)
        testButton.target = self
        testButton.action = #selector(testConnection)

        let baseURLLabel = NSTextField(labelWithString: "Base URL")
        baseURLLabel.frame = NSRect(x: 0, y: 140, width: 64, height: 22)
        baseURLField.frame = NSRect(x: 70, y: 136, width: 400, height: 24)
        baseURLField.delegate = self

        let keyLabel = NSTextField(labelWithString: "API Key")
        keyLabel.frame = NSRect(x: 0, y: 104, width: 64, height: 22)
        keyField.frame = NSRect(x: 70, y: 100, width: 400, height: 24)
        keyField.placeholderString = "sk-…（本地服务可留空）"

        let modelLabel = NSTextField(labelWithString: "模型")
        modelLabel.frame = NSRect(x: 0, y: 68, width: 64, height: 22)
        modelField.frame = NSRect(x: 70, y: 64, width: 290, height: 24)
        modelField.placeholderString = "例如 gpt-5-mini、claude-sonnet-4-5"
        fetchButton.frame = NSRect(x: 368, y: 63, width: 102, height: 26)
        fetchButton.target = self
        fetchButton.action = #selector(fetchModels)

        let hintLabel = NSTextField(wrappingLabelWithString: Self.reasoningHint)
        hintLabel.frame = NSRect(x: 0, y: 16, width: 470, height: 40)
        hintLabel.font = PixelFont.font(ofSize: 10)
        hintLabel.textColor = PixelStyle.disabledTextColor

        presetPopup.font = PixelFont.speech
        formatPopup.font = PixelFont.speech
        for field in [baseURLField, keyField, modelField] {
            field.font = PixelFont.speech
            field.backgroundColor = PixelStyle.fillColor
            field.drawsBackground = true
            field.bezelStyle = .squareBezel
            field.focusRingType = .none
        }
        for label in [presetLabel, formatLabel, baseURLLabel, keyLabel, modelLabel] {
            label.font = PixelFont.speech
            label.textColor = PixelStyle.textColor
        }

        for view in [
            presetLabel, presetPopup,
            formatLabel, formatPopup, testButton, importButton,
            baseURLLabel, baseURLField,
            keyLabel, keyField,
            modelLabel, modelField, fetchButton,
            hintLabel,
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
        presetPopup.selectItem(at: Self.presetIndex(forBaseURL: config.baseURL))
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

    private static func presetIndex(forBaseURL baseURL: String) -> Int {
        let normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty,
              let index = presets.firstIndex(where: { normalized.contains($0.baseURL.lowercased()) }) else {
            return 0
        }
        return index + 1
    }

    @objc private func formatChanged() {
        let format: LLMAPIFormat = formatPopup.indexOfSelectedItem == 1 ? .anthropic : .openai
        baseURLField.placeholderString = placeholder(for: format)
    }

    @objc private func presetChanged() {
        guard !isApplyingPreset else { return }
        let index = presetPopup.indexOfSelectedItem
        guard index > 0, Self.presets.indices.contains(index - 1) else { return }
        let preset = Self.presets[index - 1]
        isApplyingPreset = true
        baseURLField.stringValue = preset.baseURL
        formatPopup.selectItem(at: preset.format == .anthropic ? 1 : 0)
        if modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !preset.suggestedModel.isEmpty {
            modelField.stringValue = preset.suggestedModel
        }
        baseURLField.placeholderString = placeholder(for: preset.format)
        isApplyingPreset = false
    }

    /// 手动改过 Base URL 就视作自定义，预设框回到占位项。
    func controlTextDidChange(_ notification: Notification) {
        guard !isApplyingPreset else { return }
        if presetPopup.indexOfSelectedItem != 0 {
            presetPopup.selectItem(at: 0)
        }
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

    /// 按当前窗口内容组装探测用配置：优先使用新输入的 Key，否则用已保存的 Key。
    private func probeConfig() -> LLMConnectionConfig? {
        let config = LLMConnectionConfig(
            baseURL: baseURLField.stringValue,
            apiKey: keyField.stringValue,
            model: modelField.stringValue,
            apiFormat: formatPopup.indexOfSelectedItem == 1 ? .anthropic : .openai
        )
        return config.endpointURL() == nil ? nil : config
    }

    @objc private func testConnection() {
        guard let config = probeConfig() else {
            onInfo?("无法测试连接", "请先填写有效的 Base URL（以 http:// 或 https:// 开头）。")
            return
        }
        testButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            defer { self.testButton.isEnabled = true }
            let result = await HTTPLLMClient().testConnection(config: config)
            self.onInfo?(result.ok ? "连接正常" : "连接失败", result.message)
        }
    }

    @objc private func fetchModels() {
        guard let config = probeConfig() else {
            onInfo?("无法拉取模型", "请先填写有效的 Base URL（以 http:// 或 https:// 开头）。")
            return
        }
        fetchButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            defer { self.fetchButton.isEnabled = true }
            do {
                let models = try await HTTPLLMClient().listModels(config: config)
                guard !models.isEmpty else {
                    self.onInfo?("模型列表", "服务返回了空的模型列表。")
                    return
                }
                self.presentModelPicker(models)
            } catch {
                self.onInfo?("拉取模型失败", error.localizedDescription)
            }
        }
    }

    /// 像素风模型选择框：从服务端拉取到的模型列表里选一个，回填到「模型」输入框。
    private func presentModelPicker(_ models: [String]) {
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 440, height: 24), pullsDown: false)
        picker.addItems(withTitles: models)
        picker.selectItem(at: 0)
        picker.font = PixelFont.speech
        let response = PixelDialog.presentForm(
            title: "选择模型",
            message: "服务端返回了以下模型，选中后回填到「模型」输入框：",
            content: picker,
            initialFirstResponder: picker,
            buttons: [
                PixelDialog.Button(identifier: "confirm", title: "确定", isDefault: true),
                PixelDialog.Button(identifier: "cancel", title: "取消", isCancel: true),
            ]
        )
        if response == "confirm", let selected = picker.titleOfSelectedItem {
            modelField.stringValue = selected
        }
    }
}
