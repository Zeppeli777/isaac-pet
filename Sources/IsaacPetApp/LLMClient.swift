import Foundation
import IsaacPetCore

enum LLMClientError: LocalizedError {
    case invalidBaseURL
    case invalidModel
    case invalidHTTPResponse
    case http(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Base URL 无效。"
        case .invalidModel:
            return "模型名称不能为空。"
        case .invalidHTTPResponse:
            return "LLM 服务返回了无效的网络响应。"
        case let .http(message):
            return message
        }
    }
}

protocol LLMReplyProvider: Sendable {
    func respond(to input: String, config: LLMConnectionConfig) async throws -> String
}

struct HTTPLLMClient: LLMReplyProvider {
    private static let systemPrompt =
        "你是像素桌宠 Isaac。用温和、简短、有帮助的中文回答，不要声称操作了用户的电脑，不要调用工具，答案不超过 80 个中文字符。"
    private static let maxOutputTokens = 120
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func respond(to input: String, config: LLMConnectionConfig) async throws -> String {
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw LLMClientError.invalidModel }
        guard let endpoint = config.endpointURL() else { throw LLMClientError.invalidBaseURL }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch config.apiFormat {
        case .openai:
            request.httpBody = try OpenAIChatCodec.encodeRequest(
                OpenAIChatRequest(
                    model: model,
                    system: Self.systemPrompt,
                    input: input,
                    maxOutputTokens: Self.maxOutputTokens
                )
            )
            if !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        case .anthropic:
            request.httpBody = try AnthropicMessagesCodec.encodeRequest(
                AnthropicMessagesRequest(
                    model: model,
                    system: Self.systemPrompt,
                    input: input,
                    maxOutputTokens: Self.maxOutputTokens
                )
            )
            request.setValue(AnthropicMessagesCodec.versionHeader, forHTTPHeaderField: "anthropic-version")
            if !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMClientError.invalidHTTPResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message: String
            switch config.apiFormat {
            case .openai:
                message = OpenAIChatCodec.decodeAPIError(from: data, statusCode: http.statusCode)
            case .anthropic:
                message = AnthropicMessagesCodec.decodeAPIError(from: data, statusCode: http.statusCode)
            }
            throw LLMClientError.http(message)
        }
        switch config.apiFormat {
        case .openai:
            return try OpenAIChatCodec.decodeText(from: data)
        case .anthropic:
            return try AnthropicMessagesCodec.decodeText(from: data)
        }
    }
}
