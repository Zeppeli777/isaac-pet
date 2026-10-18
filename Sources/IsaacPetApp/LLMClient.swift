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
    func respond(to input: String, config: LLMConnectionConfig, systemPrompt: String) async throws -> String
}

struct HTTPLLMClient: LLMReplyProvider {
    private static let initialMaxTokens = 256
    private static let reasoningRetryMaxTokens = 1024
    private static let probeTimeout: TimeInterval = 15

    /// 本机服务（Ollama / LM Studio）不走系统代理：代理常把 localhost 请求转发失败。
    private static let loopbackSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func respond(to input: String, config: LLMConnectionConfig, systemPrompt: String) async throws -> String {
        let reply = try await send(
            to: input,
            config: config,
            systemPrompt: systemPrompt,
            maxOutputTokens: Self.initialMaxTokens
        )
        if !LLMReplyDecoder.hasVisibleContent(format: config.apiFormat, json: reply),
           LLMReplyDecoder.wasTruncated(format: config.apiFormat, json: reply) {
            // 推理模型把预算全用在思考上：加大预算重试一次。
            let retried = try await send(
                to: input,
                config: config,
                systemPrompt: systemPrompt,
                maxOutputTokens: Self.reasoningRetryMaxTokens
            )
            if LLMReplyDecoder.hasVisibleContent(format: config.apiFormat, json: retried) {
                return try LLMReplyDecoder.extractVisibleText(format: config.apiFormat, json: retried)
            }
            // 重试仍无正文：有思考内容就展示思考，否则报预算耗尽。
            if let salvaged = try LLMReplyDecoder.tryExtractVisibleText(format: config.apiFormat, json: retried) {
                return salvaged
            }
            throw LLMClientError.http("模型把输出预算全用在了思考上，没有返回正文。可以换一个非推理模型，或换一个输出预算更大的模型。")
        }
        return try LLMReplyDecoder.extractVisibleText(format: config.apiFormat, json: reply)
    }

    /// 发送一次请求并原样返回响应体；HTTP 错误换算成服务端原文，交给上层解码。
    private func send(
        to input: String,
        config: LLMConnectionConfig,
        systemPrompt: String,
        maxOutputTokens: Int
    ) async throws -> String {
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
                    system: systemPrompt,
                    input: input,
                    maxOutputTokens: maxOutputTokens
                )
            )
            if !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        case .anthropic:
            request.httpBody = try AnthropicMessagesCodec.encodeRequest(
                AnthropicMessagesRequest(
                    model: model,
                    system: systemPrompt,
                    input: input,
                    maxOutputTokens: maxOutputTokens
                )
            )
            request.setValue(AnthropicMessagesCodec.versionHeader, forHTTPHeaderField: "anthropic-version")
            if !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
            }
        }

        let (data, response) = try await session(for: endpoint).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMClientError.invalidHTTPResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMClientError.http(Self.decodeAPIError(config: config, data: data, statusCode: http.statusCode))
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// 测试连通性：优先 GET /models（OpenAI 兼容约定，顺带报告可用模型数）；
    /// 服务不支持该端点时退回一次最小 chat 请求。Key 错误、超时等都换算成一句话结论。
    func testConnection(config: LLMConnectionConfig) async -> LLMConnectionTestResult {
        guard let endpoint = config.endpointURL(), let modelsURL = config.modelsURL() else {
            return LLMConnectionTestResult(ok: false, message: "Base URL 无效。")
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.probeTimeout
        Self.applyAuth(to: &request, config: config)
        do {
            let (data, response) = try await session(for: modelsURL).data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return LLMConnectionTestResult(ok: false, message: LLMClientError.invalidHTTPResponse.localizedDescription)
            }
            if (200..<300).contains(http.statusCode) {
                let count = LLMModelCatalog.count(fromJSON: String(decoding: data, as: UTF8.self))
                let host = endpoint.host ?? "服务"
                return LLMConnectionTestResult(
                    ok: true,
                    message: count > 0
                        ? "连接正常（\(host)），发现 \(count) 个可用模型。"
                        : "连接正常（\(host)）。该服务没有返回模型列表。"
                )
            }
            // /models 不可用或需要聊天权限（404 / 405 / 501 / 401 / 403）：退回最小 chat 请求再试。
            if [404, 405, 501, 401, 403].contains(http.statusCode) {
                return await probeWithChat(config: config)
            }
            return LLMConnectionTestResult(
                ok: false,
                message: Self.decodeAPIError(config: config, data: data, statusCode: http.statusCode)
            )
        } catch {
            return Self.transportFailure(error, host: endpoint.host ?? "服务")
        }
    }

    /// 拉取服务端可用模型列表（GET /models）；失败时抛出错误（消息取服务端原文）。
    func listModels(config: LLMConnectionConfig) async throws -> [String] {
        guard config.endpointURL() != nil, let modelsURL = config.modelsURL() else {
            throw LLMClientError.invalidBaseURL
        }
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.probeTimeout
        Self.applyAuth(to: &request, config: config)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session(for: modelsURL).data(for: request)
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw LLMClientError.http("拉取模型列表超时。")
            }
            throw LLMClientError.http("无法连接模型列表端点：\(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else { throw LLMClientError.invalidHTTPResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMClientError.http(Self.decodeAPIError(config: config, data: data, statusCode: http.statusCode))
        }
        return try LLMModelCatalog.parseIDs(String(decoding: data, as: UTF8.self))
    }

    /// /models 不可用时的退路：发一条 16 token 的 ping，验证 Key 与模型可用性。
    private func probeWithChat(config: LLMConnectionConfig) async -> LLMConnectionTestResult {
        guard let endpoint = config.endpointURL() else {
            return LLMConnectionTestResult(ok: false, message: "Base URL 无效。")
        }
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            return LLMConnectionTestResult(
                ok: false,
                message: "服务不支持 /models 接口，且模型名称留空，无法进一步测试。请填写模型名称后再试。"
            )
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.probeTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch config.apiFormat {
        case .openai:
            request.httpBody = try? OpenAIChatCodec.encodeRequest(
                OpenAIChatRequest(model: model, system: "", input: "ping", maxOutputTokens: 16)
            )
            if !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        case .anthropic:
            request.httpBody = try? AnthropicMessagesCodec.encodeRequest(
                AnthropicMessagesRequest(model: model, system: "", input: "ping", maxOutputTokens: 16)
            )
            request.setValue(AnthropicMessagesCodec.versionHeader, forHTTPHeaderField: "anthropic-version")
            if !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
            }
        }

        do {
            let (data, response) = try await session(for: endpoint).data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return LLMConnectionTestResult(ok: false, message: LLMClientError.invalidHTTPResponse.localizedDescription)
            }
            if (200..<300).contains(http.statusCode) {
                return LLMConnectionTestResult(
                    ok: true,
                    message: "连接正常（\(endpoint.host ?? "服务")），模型 \(model) 有响应。"
                )
            }
            return LLMConnectionTestResult(
                ok: false,
                message: Self.decodeAPIError(config: config, data: data, statusCode: http.statusCode)
            )
        } catch {
            return Self.transportFailure(error, host: endpoint.host ?? "服务")
        }
    }

    // MARK: - 传输辅助

    private func session(for endpoint: URL) -> URLSession {
        Self.isLoopback(endpoint) ? Self.loopbackSession : session
    }

    /// 本机回环地址（localhost、127.0.0.0/8、::1）：与 Windows 的 Uri.IsLoopback 对齐。
    private static func isLoopback(_ endpoint: URL) -> Bool {
        guard let host = endpoint.host?.lowercased() else { return false }
        if host == "localhost" || host == "::1" { return true }
        guard host.hasPrefix("127.") else { return false }
        let octets = host.dropFirst(4).split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 3 && octets.allSatisfy { part in
            guard let value = Int(part) else { return false }
            return (0...255).contains(value)
        }
    }

    private static func applyAuth(to request: inout URLRequest, config: LLMConnectionConfig) {
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        switch config.apiFormat {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(AnthropicMessagesCodec.versionHeader, forHTTPHeaderField: "anthropic-version")
        case .openai:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func decodeAPIError(config: LLMConnectionConfig, data: Data, statusCode: Int) -> String {
        switch config.apiFormat {
        case .openai:
            return OpenAIChatCodec.decodeAPIError(from: data, statusCode: statusCode)
        case .anthropic:
            return AnthropicMessagesCodec.decodeAPIError(from: data, statusCode: statusCode)
        }
    }

    private static func transportFailure(_ error: Error, host: String) -> LLMConnectionTestResult {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return LLMConnectionTestResult(ok: false, message: "连接 \(host) 超时。")
        }
        return LLMConnectionTestResult(ok: false, message: "无法连接 \(host)：\(error.localizedDescription)")
    }
}
