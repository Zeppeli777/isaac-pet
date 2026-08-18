import Foundation
import IsaacPetCore

enum LLMClientError: LocalizedError {
    case invalidModel
    case invalidHTTPResponse
    case http(String)

    var errorDescription: String? {
        switch self {
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
    func respond(to input: String, model: String, token: String) async throws -> String
}

struct OpenAIResponsesClient: LLMReplyProvider {
    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func respond(to input: String, model rawModel: String, token: String) async throws -> String {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw LLMClientError.invalidModel }
        let payload = OpenAIResponsesRequest(
            model: model,
            instructions: "你是像素桌宠 Isaac。用温和、简短、有帮助的中文回答，不要声称操作了用户的电脑，不要调用工具，答案不超过 80 个中文字符。",
            input: input,
            maxOutputTokens: 120,
            store: false
        )
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try OpenAIResponsesCodec.encodeRequest(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMClientError.invalidHTTPResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMClientError.http(OpenAIResponsesCodec.decodeAPIError(from: data, statusCode: http.statusCode))
        }
        return try OpenAIResponsesCodec.decodeText(from: data)
    }
}
