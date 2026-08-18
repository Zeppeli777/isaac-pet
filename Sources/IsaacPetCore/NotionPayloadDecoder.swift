import Foundation

public struct NotionRecordPage: Equatable, Sendable {
    public let records: [ExternalTodoRecord]
    public let nextCursor: String?
    public let hasMore: Bool
}

public enum NotionDataSourceIdentifier {
    public static func normalized(_ rawValue: String) -> String? {
        let compact = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}"#
        guard let range = compact.range(of: pattern, options: .regularExpression) else { return nil }
        let hex = compact[range].replacingOccurrences(of: "-", with: "").lowercased()
        guard hex.count == 32 else { return nil }

        var parts: [String] = []
        var index = hex.startIndex
        for length in [8, 4, 4, 4, 12] {
            let end = hex.index(index, offsetBy: length)
            parts.append(String(hex[index..<end]))
            index = end
        }
        return parts.joined(separator: "-")
    }
}

public enum NotionPayloadDecoder {
    public static func decode(
        _ data: Data,
        dataSourceIdentifier: String,
        knownItemIdentifiers: Set<String>,
        syncDate: Date = Date()
    ) throws -> NotionRecordPage {
        let response = try JSONDecoder().decode(QueryResponse.self, from: data)
        let records = response.results.compactMap { page -> ExternalTodoRecord? in
            guard page.archived != true, page.inTrash != true else { return nil }
            let title = page.properties.values
                .first(where: { $0.type == "title" })?
                .title?
                .map(\.plainText)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return nil }

            let dueAt = bestDate(in: page.properties)
            let completed = isCompleted(page.properties)
            guard !completed || knownItemIdentifiers.contains(page.id) else { return nil }
            let completedAt = completed
                ? parseDate(page.lastEditedTime) ?? syncDate
                : nil
            return ExternalTodoRecord(
                source: TodoExternalSource(
                    kind: .notion,
                    itemIdentifier: page.id,
                    containerIdentifier: dataSourceIdentifier,
                    containerTitle: "Notion",
                    lastSyncedAt: syncDate
                ),
                title: title,
                dueAt: dueAt,
                completedAt: completedAt
            )
        }
        return NotionRecordPage(
            records: records,
            nextCursor: response.nextCursor,
            hasMore: response.hasMore
        )
    }

    private static let completionPropertyKeywords = [
        "done", "complete", "completed", "finished", "完成", "已完成",
    ]
    private static let completedStatusNames = [
        "done", "complete", "completed", "finished", "完成", "已完成",
    ]
    private static let duePropertyKeywords = [
        "due", "deadline", "date", "when", "截止", "日期", "时间",
    ]

    private static func isCompleted(_ properties: [String: PageProperty]) -> Bool {
        for (name, property) in properties {
            let normalizedName = name.lowercased()
            if property.type == "checkbox",
               property.checkbox == true,
               completionPropertyKeywords.contains(where: normalizedName.contains) {
                return true
            }
            if property.type == "status",
               let statusName = property.status?.name.lowercased(),
               completedStatusNames.contains(statusName) {
                return true
            }
        }
        return false
    }

    private static func bestDate(in properties: [String: PageProperty]) -> Date? {
        let candidates = properties.compactMap { name, property -> (String, String)? in
            guard property.type == "date", let start = property.date?.start else { return nil }
            return (name.lowercased(), start)
        }
        let preferred = candidates.first { name, _ in
            duePropertyKeywords.contains(where: name.contains)
        } ?? candidates.first
        return preferred.flatMap { parseDate($0.1) }
    }

    private static func parseDate(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: rawValue) { return date }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: rawValue) { return date }

        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2], hour: 9
        ))
    }

    private struct QueryResponse: Decodable {
        let results: [Page]
        let nextCursor: String?
        let hasMore: Bool

        enum CodingKeys: String, CodingKey {
            case results
            case nextCursor = "next_cursor"
            case hasMore = "has_more"
        }
    }

    private struct Page: Decodable {
        let id: String
        let archived: Bool?
        let inTrash: Bool?
        let lastEditedTime: String?
        let properties: [String: PageProperty]

        enum CodingKeys: String, CodingKey {
            case id
            case archived
            case inTrash = "in_trash"
            case lastEditedTime = "last_edited_time"
            case properties
        }
    }

    private struct PageProperty: Decodable {
        let type: String
        let title: [RichText]?
        let date: DateValue?
        let checkbox: Bool?
        let status: StatusValue?
    }

    private struct RichText: Decodable {
        let plainText: String

        enum CodingKeys: String, CodingKey {
            case plainText = "plain_text"
        }
    }

    private struct DateValue: Decodable {
        let start: String
    }

    private struct StatusValue: Decodable {
        let name: String
    }
}
