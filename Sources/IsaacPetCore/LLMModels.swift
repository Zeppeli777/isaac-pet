import Foundation

public enum LLMCodecError: LocalizedError, Equatable {
    case invalidResponse
    case emptyResponse
    case api(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "LLM 返回了无法解析的数据。"
        case .emptyResponse:
            return "LLM 没有返回可显示的文字。"
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
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty,
              let url = URL(string: base),
              url.host != nil,
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        let path: String
        switch apiFormat {
        case .openai:
            path = "/chat/completions"
        case .anthropic:
            if !base.hasSuffix("/v1") { base += "/v1" }
            path = "/messages"
        }
        return URL(string: base + path)
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

    public init(model: String, system: String, input: String, maxOutputTokens: Int = 120) {
        self.model = model
        self.messages = [
            Message(role: "system", content: system),
            Message(role: "user", content: input),
        ]
        self.maxTokens = max(16, min(maxOutputTokens, 512))
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
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(ResponseEnvelope.self, from: data) else {
            throw LLMCodecError.invalidResponse
        }
        if let message = envelope.error?.message, !message.isEmpty {
            throw LLMCodecError.api(message)
        }
        let text = envelope.choices.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw LLMCodecError.emptyResponse }
        return text
    }

    public static func decodeAPIError(from data: Data, statusCode: Int) -> String {
        if let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data),
           let message = envelope.error?.message,
           !message.isEmpty {
            return message
        }
        return "LLM 请求失败（HTTP \(statusCode)）。"
    }

    private struct ResponseEnvelope: Decodable {
        let choices: [Choice]
        let error: ErrorBody?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
            error = try container.decodeIfPresent(ErrorBody.self, forKey: .error)
        }

        private enum CodingKeys: String, CodingKey { case choices, error }
    }

    private struct Choice: Decodable {
        let message: MessageBody?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try container.decodeIfPresent(MessageBody.self, forKey: .message)
        }

        private enum CodingKeys: String, CodingKey { case message }
    }

    struct MessageBody: Decodable {
        let content: String?
    }

    private struct ErrorBody: Decodable {
        let message: String
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

    public init(model: String, system: String, input: String, maxOutputTokens: Int = 120) {
        self.model = model
        self.system = system
        self.maxTokens = max(16, min(maxOutputTokens, 512))
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
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(ResponseEnvelope.self, from: data) else {
            throw LLMCodecError.invalidResponse
        }
        if let message = envelope.error?.message, !message.isEmpty {
            throw LLMCodecError.api(message)
        }
        let text = envelope.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMCodecError.emptyResponse }
        return text
    }

    public static func decodeAPIError(from data: Data, statusCode: Int) -> String {
        if let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data),
           let message = envelope.error?.message,
           !message.isEmpty {
            return message
        }
        return "LLM 请求失败（HTTP \(statusCode)）。"
    }

    private struct ResponseEnvelope: Decodable {
        let content: [ContentItem]
        let error: ErrorBody?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            content = try container.decodeIfPresent([ContentItem].self, forKey: .content) ?? []
            error = try container.decodeIfPresent(ErrorBody.self, forKey: .error)
        }

        private enum CodingKeys: String, CodingKey { case content, error }
    }

    private struct ContentItem: Decodable {
        let type: String?
        let text: String?
    }

    private struct ErrorBody: Decodable {
        let message: String
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
