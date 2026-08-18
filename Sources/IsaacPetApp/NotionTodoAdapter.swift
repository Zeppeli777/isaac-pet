import Foundation
import IsaacPetCore

enum NotionTodoAdapterError: LocalizedError {
    case invalidDataSourceIdentifier
    case invalidResponse
    case api(statusCode: Int, message: String)
    case resultLimitReached

    var errorDescription: String? {
        switch self {
        case .invalidDataSourceIdentifier:
            return "请输入有效的 Notion data source ID（UUID 或 32 位 ID）。"
        case .invalidResponse:
            return "Notion 返回了无法识别的响应。"
        case let .api(statusCode, message):
            return "Notion API 错误 \(statusCode)：\(message)"
        case .resultLimitReached:
            return "Notion 条目超过 1000 条。请拆分数据源后再同步。"
        }
    }
}

struct NotionSyncResult: Sendable {
    let records: [ExternalTodoRecord]
    let dataSourceIdentifier: String
}

@MainActor
final class NotionTodoAdapter {
    static let apiVersion = "2026-03-11"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRecords(
        token: String,
        rawDataSourceIdentifier: String,
        knownItemIdentifiers: Set<String>
    ) async throws -> NotionSyncResult {
        guard let dataSourceID = NotionDataSourceIdentifier.normalized(rawDataSourceIdentifier) else {
            throw NotionTodoAdapterError.invalidDataSourceIdentifier
        }

        var cursor: String?
        var records: [ExternalTodoRecord] = []
        for _ in 0..<10 {
            let page = try await fetchPage(
                token: token,
                dataSourceID: dataSourceID,
                cursor: cursor,
                knownItemIdentifiers: knownItemIdentifiers
            )
            records.append(contentsOf: page.records)
            guard page.hasMore else {
                return NotionSyncResult(records: records, dataSourceIdentifier: dataSourceID)
            }
            guard let nextCursor = page.nextCursor else {
                throw NotionTodoAdapterError.invalidResponse
            }
            cursor = nextCursor
        }
        throw NotionTodoAdapterError.resultLimitReached
    }

    private func fetchPage(
        token: String,
        dataSourceID: String,
        cursor: String?,
        knownItemIdentifiers: Set<String>
    ) async throws -> NotionRecordPage {
        let url = URL(string: "https://api.notion.com/v1/data_sources/\(dataSourceID)/query")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["page_size": 100]
        if let cursor { body["start_cursor"] = cursor }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NotionTodoAdapterError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIError.self, from: data)
            throw NotionTodoAdapterError.api(
                statusCode: http.statusCode,
                message: apiError?.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        return try NotionPayloadDecoder.decode(
            data,
            dataSourceIdentifier: dataSourceID,
            knownItemIdentifiers: knownItemIdentifiers
        )
    }

    private struct APIError: Decodable {
        let message: String
    }
}
