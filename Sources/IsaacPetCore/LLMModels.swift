import Foundation

public enum LLMCodecError: LocalizedError, Equatable {
    case invalidResponse
    case emptyResponse
    case invalidModelList
    case api(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "LLM 返回了无法解析的数据。"
        case .emptyResponse:
            return "LLM 没有返回可显示的文字（服务可能只返回了思考过程，或被安全策略拦截）。"
        case .invalidModelList:
            return "模型列表返回了无法解析的数据。"
        case let .api(message):
            return message
        }
    }
}

public enum LLMConfigError: LocalizedError, Equatable {
    case invalidFile
    case invalidBaseURL
    case missingModel

    public var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "配置文件不是有效的 JSON 对象。"
        case .invalidBaseURL:
            return "Base URL 必须是以 http(s):// 开头的有效地址。"
        case .missingModel:
            return "模型名称不能为空，且不能包含空格。"
        }
    }
}

/// LLM 服务的 API 风格。OpenAI 兼容格式走 `chat/completions`，
/// Anthropic 兼容格式走 `messages`。
public enum LLMAPIFormat: String, Codable, Sendable, CaseIterable {
    case openai
    case anthropic
}

/// 连接测试结果：是否连通 + 面向用户的一句话结论。
public struct LLMConnectionTestResult: Equatable, Sendable {
    public let ok: Bool
    public let message: String

    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }
}

/// LLM 回复的方言归一化：从 OpenAI / Anthropic 兼容服务的响应体里提取一段可显示文字。
/// 借鉴 magpie 网关的做法——不假设服务端返回标准字符串，把 reasoning_content、
/// 数组型 content、思考标签、finish_reason=length 等形态在客户端统一规整。
public enum LLMReplyDecoder {
    /// 思考块标签名，按长度降序排列，保证前缀判断时 `<thinking>` 不会被误判成 `<think>`。
    private static let thinkTagNames = ["thinking", "reasoning", "think"]

    /// 提取可显示文字；服务端错误直接抛出（消息取服务端原文），无文字时抛通用错误。
    public static func extractVisibleText(format: LLMAPIFormat, json: String) throws -> String {
        guard let text = try tryExtractVisibleText(format: format, json: json) else {
            throw LLMCodecError.emptyResponse
        }
        return text
    }

    /// 同 `extractVisibleText`，但没有可显示文字时返回 nil 而不抛错，
    /// 供调用方判断是否值得加大预算重试。解析失败与服务端错误仍然抛错。
    public static func tryExtractVisibleText(format: LLMAPIFormat, json: String) throws -> String? {
        let root = try parseRoot(json)
        try throwIfAPIError(root)
        var visible = ""
        var reasoning = ""
        collect(format: format, root: root, visible: &visible, reasoning: &reasoning)
        // 推理模型可能只返回思考过程：退而展示思考内容，好过直接报错
        // （对应 magpie 把 reasoning_content 并回回复的做法）。
        let text = normalizeVisibleText(visible.isEmpty ? reasoning : visible)
        return text.isEmpty ? nil : text
    }

    /// 是否只返回了思考内容：正文（content / text 块）为空。
    /// 推理模型把输出预算全部用在思考上时会出现这种情况，调用方应加大预算重试。
    public static func hasVisibleContent(format: LLMAPIFormat, json: String) -> Bool {
        guard let root = try? parseRoot(json) else { return false }
        var visible = ""
        var reasoning = ""
        collect(format: format, root: root, visible: &visible, reasoning: &reasoning)
        return !visible.isEmpty
    }

    /// finish_reason / stop_reason 表示输出被长度截断（推理模型常见）。
    public static func wasTruncated(format: LLMAPIFormat, json: String) -> Bool {
        guard let root = try? parseRoot(json) else { return false }
        switch format {
        case .openai:
            guard let choices = root["choices"] as? [[String: Any]] else { return false }
            return choices.contains { isLengthLike($0["finish_reason"] as? String) }
        case .anthropic:
            return isLengthLike(root["stop_reason"] as? String)
        }
    }

    /// 剥离思考标签（完整块直接删除，未闭合的从标签处截断），压缩空行并去首尾空白。
    public static func normalizeVisibleText(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        var text = removingClosedThinkBlocks(raw)
        if let open = rangeOfThinkOpen(in: text)?.range {
            text = String(text[..<open.lowerBound])
        }
        return collapsingBlankLines(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 响应体收集

    private static func collect(
        format: LLMAPIFormat,
        root: [String: Any],
        visible: inout String,
        reasoning: inout String
    ) {
        switch format {
        case .openai:
            collectOpenAI(root, visible: &visible, reasoning: &reasoning)
        case .anthropic:
            collectAnthropic(root, visible: &visible, reasoning: &reasoning)
        }
    }

    private static func collectOpenAI(_ root: [String: Any], visible: inout String, reasoning: inout String) {
        guard let choices = root["choices"] as? [[String: Any]] else { return }
        for choice in choices {
            if let message = choice["message"] as? [String: Any] {
                if let content = message["content"] {
                    collectContentParts(content, visible: &visible, reasoning: &reasoning)
                }
                if visible.isEmpty && reasoning.isEmpty {
                    // DeepSeek / StepFun / Moonshot 等推理模型的思考字段约定。
                    appendIfString(message["reasoning_content"], to: &reasoning)
                    appendIfString(message["reasoning"], to: &reasoning)
                }
            }
            if visible.isEmpty && reasoning.isEmpty {
                // 旧版 completions 形态：text 直接在 choice 上。
                appendIfString(choice["text"], to: &visible)
            }
        }
    }

    private static func collectContentParts(_ content: Any, visible: inout String, reasoning: inout String) {
        switch content {
        case let text as String:
            visible += text
        case let parts as [[String: Any]]:
            for part in parts {
                guard let text = part["text"] as? String, !text.isEmpty else { continue }
                switch part["type"] as? String {
                case "reasoning", "thinking":
                    reasoning += text
                default:
                    visible += text
                }
            }
        default:
            break
        }
    }

    private static func collectAnthropic(_ root: [String: Any], visible: inout String, reasoning: inout String) {
        guard let content = root["content"] as? [[String: Any]] else { return }
        for item in content {
            if item["type"] as? String == "thinking" {
                appendIfString(item["thinking"], to: &reasoning)
            } else {
                // text 块，以及没有 type 字段的宽松兼容形态。
                appendIfString(item["text"], to: &visible)
            }
        }
    }

    private static func appendIfString(_ value: Any?, to target: inout String) {
        if let text = value as? String {
            target += text
        }
    }

    // MARK: - 思考标签

    /// 删除完整的思考块；未闭合的开标签原样保留，由 `normalizeVisibleText` 截断。
    private static func removingClosedThinkBlocks(_ raw: String) -> String {
        var result = ""
        var cursor = raw.startIndex
        while let open = rangeOfThinkOpen(in: raw, from: cursor) {
            result += raw[cursor..<open.range.lowerBound]
            let closeCandidates = thinkTagNames.compactMap { name -> (range: Range<String.Index>, name: String)? in
                guard let range = raw.range(
                    of: "</" + name,
                    options: .caseInsensitive,
                    range: open.range.upperBound..<raw.endIndex
                ) else { return nil }
                return (range, name)
            }
            if let close = closeCandidates.min(by: { $0.range.lowerBound < $1.range.lowerBound }),
               let closingAngle = raw[close.range.lowerBound...].firstIndex(of: ">") {
                cursor = raw.index(after: closingAngle)
                continue
            }
            result += raw[open.range.lowerBound...]
            return result
        }
        result += raw[cursor..<raw.endIndex]
        return result
    }

    /// 查找下一个思考开标签 `<name …>`，返回标签范围与标签名（大小写不敏感）。
    private static func rangeOfThinkOpen(in text: String, from start: String.Index? = nil)
        -> (range: Range<String.Index>, name: String)? {
        var cursor = start ?? text.startIndex
        while let openingAngle = text[cursor...].firstIndex(of: "<") {
            let afterAngle = text.index(after: openingAngle)
            let rest = text[afterAngle...].lowercased()
            if let name = thinkTagNames.first(where: { rest.hasPrefix($0) }) {
                let nameEnd = text.index(afterAngle, offsetBy: name.count)
                // 标签名后必须是词边界（`>`、空格等），`<thinkfoo>` 不算思考标签。
                if nameEnd != text.endIndex, isBoundaryCharacter(text[nameEnd]),
                   let closingAngle = text[nameEnd...].firstIndex(of: ">") {
                    return (openingAngle..<text.index(after: closingAngle), name)
                }
            }
            cursor = afterAngle
        }
        return nil
    }

    private static func isBoundaryCharacter(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber && character != "_"
    }

    /// 把 3 个及以上连续换行压缩成两个，保留段落间的空行。
    private static func collapsingBlankLines(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var newlineRun = 0
        for character in text {
            if character == "\n" {
                newlineRun += 1
                if newlineRun <= 2 {
                    result.append(character)
                }
            } else {
                newlineRun = 0
                result.append(character)
            }
        }
        return result
    }

    // MARK: - 基础解析

    private static func parseRoot(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMCodecError.invalidResponse
        }
        return object
    }

    private static func throwIfAPIError(_ root: [String: Any]) throws {
        if let error = root["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            throw LLMCodecError.api(message)
        }
    }

    private static func isLengthLike(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.lowercased()
        return normalized == "length" || normalized == "max_tokens"
    }
}

/// GET /models 响应的解析：OpenAI 与 Anthropic 兼容服务都是这个约定，
/// 返回 `{"data":[{"id":"..."}]}`；同时容忍顶层数组和字符串数组两种宽松形态。
public enum LLMModelCatalog {
    /// 解析模型 ID 列表：去重、按 ID 排序。JSON 无法解析时抛错，形状不识别时返回空列表。
    public static func parseIDs(_ json: String) throws -> [String] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            throw LLMCodecError.invalidModelList
        }
        let elements: [Any]
        if let array = root as? [Any] {
            elements = array
        } else if let object = root as? [String: Any], let data = object["data"] as? [Any] {
            elements = data
        } else {
            return []
        }
        var ids: [String] = []
        for element in elements {
            if let text = element as? String {
                add(text, to: &ids)
            } else if let object = element as? [String: Any] {
                add(object["id"], to: &ids)
            }
        }
        return Array(Set(ids)).sorted()
    }

    /// 测试连接时只要个数：解析失败按 0 处理，不打断连通性结论。
    public static func count(fromJSON json: String) -> Int {
        (try? parseIDs(json))?.count ?? 0
    }

    private static func add(_ value: Any?, to ids: inout [String]) {
        guard let text = value as? String else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ids.append(trimmed)
    }
}

public struct LLMConnectionConfig: Codable, Equatable, Sendable {
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var apiFormat: LLMAPIFormat

    public init(baseURL: String, apiKey: String, model: String, apiFormat: LLMAPIFormat) {
        var trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmedBaseURL.hasSuffix("/") { trimmedBaseURL.removeLast() }
        self.baseURL = trimmedBaseURL
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiFormat = apiFormat
    }

    /// 规范化 Base URL（去掉结尾斜杠）并拼接对应格式的端点。
    /// Anthropic 兼容服务约定 Base URL 含 `/v1`（如 `https://api.anthropic.com`），缺失时自动补上。
    public func endpointURL() -> URL? {
        guard let base = normalizedBaseOrNull() else { return nil }
        let url: String
        switch apiFormat {
        case .openai:
            url = base + "/chat/completions"
        case .anthropic:
            url = (base.hasSuffix("/v1") ? base : base + "/v1") + "/messages"
        }
        return URL(string: url)
    }

    /// GET /models 端点：OpenAI 与 Anthropic 兼容服务都是这个约定，用于拉取可用模型。
    public func modelsURL() -> URL? {
        guard let base = normalizedBaseOrNull() else { return nil }
        let url: String
        switch apiFormat {
        case .anthropic:
            url = (base.hasSuffix("/v1") ? base : base + "/v1") + "/models"
        case .openai:
            url = base + "/models"
        }
        return URL(string: url)
    }

    /// 去掉结尾斜杠并校验 http(s) scheme 与主机名；无效返回 nil。
    private func normalizedBaseOrNull() -> String? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty,
              let url = URL(string: base),
              url.host != nil,
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return base
    }

    public func validate() throws {
        guard endpointURL() != nil else { throw LLMConfigError.invalidBaseURL }
        guard !model.isEmpty, !model.contains(where: \.isWhitespace) else { throw LLMConfigError.missingModel }
    }

    /// 保存到本机文件时使用规范的键名。
    private enum CodingKeys: String, CodingKey {
        case baseURL
        case apiKey
        case model
        case apiFormat
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        let raw = try container.decodeIfPresent(String.self, forKey: .apiFormat)
        apiFormat = raw.flatMap(LLMAPIFormat.init(rawValue:))
            ?? (baseURL.lowercased().contains("anthropic") ? .anthropic : .openai)
    }

    /// 导入/加载配置文件。容忍常见别名键名（`baseUrl`、`api_key`、`format` 等），
    /// `apiFormat` 缺失时根据 Base URL 主机名推断。
    public static func parseImported(_ data: Data) throws -> LLMConnectionConfig {
        let object = try? JSONSerialization.jsonObject(with: data)
        guard let fields = object as? [String: Any] else { throw LLMConfigError.invalidFile }

        func text(_ names: [String]) -> String {
            names
                .compactMap { fields[$0] as? String }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        }
        var baseURL = text(["baseURL", "baseUrl", "base_url", "endpoint", "url"])
        while baseURL.hasSuffix("/") { baseURL.removeLast() }
        let apiKey = text(["apiKey", "api_key", "key", "token"])
        let model = text(["model", "modelId", "model_id", "model_name"])
        let rawFormat = text(["apiFormat", "api_format", "format", "provider", "type"]).lowercased()
        let apiFormat: LLMAPIFormat
        switch rawFormat {
        case "anthropic", "claude", "anthropic-compatible":
            apiFormat = .anthropic
        case "openai", "openai-compatible", "chat-completions":
            apiFormat = .openai
        default:
            apiFormat = baseURL.lowercased().contains("anthropic") ? .anthropic : .openai
        }
        return LLMConnectionConfig(baseURL: baseURL, apiKey: apiKey, model: model, apiFormat: apiFormat)
    }
}

public struct OpenAIChatRequest: Codable, Equatable, Sendable {
    public struct Message: Codable, Equatable, Sendable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public let model: String
    public let messages: [Message]
    public let maxTokens: Int
    public let stream: Bool

    public init(model: String, system: String, input: String, maxOutputTokens: Int = 256) {
        self.model = model
        self.messages = [
            Message(role: "system", content: system),
            Message(role: "user", content: input),
        ]
        self.maxTokens = max(16, maxOutputTokens)
        self.stream = false
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case stream
    }
}

public enum OpenAIChatCodec {
    public static func encodeRequest(_ request: OpenAIChatRequest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(request)
    }

    public static func decodeText(from data: Data) throws -> String {
        guard let json = String(data: data, encoding: .utf8) else {
            throw LLMCodecError.invalidResponse
        }
        // 与 HTTPLLMClient 共用同一套方言归一化（reasoning_content、数组 content、思考标签）。
        return try LLMReplyDecoder.extractVisibleText(format: .openai, json: json)
    }

    public static func decodeAPIError(from data: Data, statusCode: Int) -> String {
        // 容错解析：错误体可能带任何附加字段，逐个取出 message 即可。
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        return "LLM 请求失败（HTTP \(statusCode)）。"
    }
}

public struct AnthropicMessagesRequest: Codable, Equatable, Sendable {
    public struct Message: Codable, Equatable, Sendable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public let model: String
    public let system: String
    public let maxTokens: Int
    public let messages: [Message]

    public init(model: String, system: String, input: String, maxOutputTokens: Int = 256) {
        self.model = model
        self.system = system
        self.maxTokens = max(16, maxOutputTokens)
        self.messages = [Message(role: "user", content: input)]
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case system
        case maxTokens = "max_tokens"
        case messages
    }
}

public enum AnthropicMessagesCodec {
    public static let versionHeader = "2023-06-01"

    public static func encodeRequest(_ request: AnthropicMessagesRequest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(request)
    }

    public static func decodeText(from data: Data) throws -> String {
        guard let json = String(data: data, encoding: .utf8) else {
            throw LLMCodecError.invalidResponse
        }
        // 与 HTTPLLMClient 共用同一套方言归一化（thinking 块、宽松 text 形态）。
        return try LLMReplyDecoder.extractVisibleText(format: .anthropic, json: json)
    }

    public static func decodeAPIError(from data: Data, statusCode: Int) -> String {
        // 容错解析：错误体可能带任何附加字段，逐个取出 message 即可。
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        return "LLM 请求失败（HTTP \(statusCode)）。"
    }
}

/// LLM 连接配置的本机文件存储。API Key 以明文保存在用户目录下、
/// 权限 0600 的 JSON 文件中（与常见开发工具的做法一致），不使用钥匙串，
/// 因此读取永远不会触发系统授权弹窗。
public struct LLMConfigFileStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = LLMConfigFileStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["ISAAC_LLM_CONFIG_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return support
            .appendingPathComponent("IsaacPet", isDirectory: true)
            .appendingPathComponent("llm-config.json")
    }

    public func load() throws -> LLMConnectionConfig? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try LLMConnectionConfig.parseImported(data)
    }

    public func save(_ config: LLMConnectionConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.createFile(atPath: fileURL.path, contents: data, attributes: [.posixPermissions: 0o600]) {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
