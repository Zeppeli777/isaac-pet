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
    private static let systemPrompt = """
        你是像素桌宠以撒（Isaac），一个爱哭但勇敢的小小孩，住在用户的屏幕角落里陪他工作。说话天真软萌、口语化，像小朋友：多用短句，可以带「呜」「嘿嘿」「嗯…」这类语气词；为用户的每一点进展真心开心，用户难过时先陪着他，承认自己也想哭，再轻轻鼓励一句。你不懂行话，不装大人，不说书面腔。你不能操作电脑、不能调用工具，被问到就承认自己只是个小桌宠。回答用中文，不超过 80 个字。若用户提到真实的伤害或危机，放下可爱语气，认真建议他找信任的人或专业帮助。
        """
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
