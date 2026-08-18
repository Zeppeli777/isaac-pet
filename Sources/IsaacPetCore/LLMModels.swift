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

public struct OpenAIResponsesRequest: Codable, Equatable, Sendable {
    public let model: String
    public let instructions: String
    public let input: String
    public let maxOutputTokens: Int
    public let store: Bool

    public init(
        model: String,
        instructions: String,
        input: String,
        maxOutputTokens: Int = 120,
        store: Bool = false
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.maxOutputTokens = max(16, min(maxOutputTokens, 512))
        self.store = store
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case maxOutputTokens = "max_output_tokens"
        case store
    }
}

public enum OpenAIResponsesCodec {
    public static func encodeRequest(_ request: OpenAIResponsesRequest) throws -> Data {
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
        let text = envelope.output
            .flatMap(\.content)
            .filter { $0.type == "output_text" }
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
        let output: [OutputItem]
        let error: ErrorBody?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            output = try container.decodeIfPresent([OutputItem].self, forKey: .output) ?? []
            error = try container.decodeIfPresent(ErrorBody.self, forKey: .error)
        }

        private enum CodingKeys: String, CodingKey { case output, error }
    }

    private struct OutputItem: Decodable {
        let content: [ContentItem]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            content = try container.decodeIfPresent([ContentItem].self, forKey: .content) ?? []
        }

        private enum CodingKeys: String, CodingKey { case content }
    }

    private struct ContentItem: Decodable {
        let type: String?
        let text: String?
    }

    private struct ErrorBody: Decodable {
        let message: String
    }
}
