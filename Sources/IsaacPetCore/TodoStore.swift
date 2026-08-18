import Foundation

public enum TodoStoreError: LocalizedError {
    case invalidTitle
    case missingApplicationSupportDirectory

    public var errorDescription: String? {
        switch self {
        case .invalidTitle:
            return "Todo 标题不能为空。"
        case .missingApplicationSupportDirectory:
            return "无法找到本机的 Application Support 目录。"
        }
    }
}

@MainActor
public final class TodoStore {
    public private(set) var items: [TodoItem]
    public let fileURL: URL

    public init(fileURL: URL? = nil) throws {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            guard let supportDirectory = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw TodoStoreError.missingApplicationSupportDirectory
            }
            self.fileURL = supportDirectory
                .appendingPathComponent("Isaac Pet", isDirectory: true)
                .appendingPathComponent("todos-v1.json", isDirectory: false)
        }
        items = try Self.load(from: self.fileURL)
    }

    @discardableResult
    public func add(title rawTitle: String, dueAt: Date?) throws -> TodoItem {
        guard let title = TodoPolicy.normalizedTitle(rawTitle) else {
            throw TodoStoreError.invalidTitle
        }
        let item = TodoItem(title: title, dueAt: dueAt)
        var updated = items
        updated.append(item)
        try commit(updated)
        return item
    }

    @discardableResult
    public func toggleCompleted(id: UUID, at date: Date = Date()) throws -> TodoItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = items
        updated[index].completedAt = updated[index].isCompleted ? nil : date
        if !updated[index].isCompleted {
            // Restoring a task is a new reminder lifecycle. This includes overdue tasks:
            // otherwise an earlier delivery timestamp would suppress the reminder forever.
            updated[index].remindedAt = nil
        }
        try commit(updated)
        return updated[index]
    }

    public func remove(id: UUID) throws {
        try commit(items.filter { $0.id != id })
    }

    public func markRemindersDelivered(ids: Set<UUID>, at date: Date = Date()) throws {
        guard !ids.isEmpty else { return }
        var updated = items
        for index in updated.indices where ids.contains(updated[index].id) {
            updated[index].remindedAt = date
        }
        try commit(updated)
    }

    @discardableResult
    public func importExternalRecords(
        _ records: [ExternalTodoRecord],
        at date: Date = Date()
    ) throws -> TodoImportSummary {
        let result = TodoPolicy.merging(records, into: items, now: date)
        try commit(result.items)
        return result.summary
    }

    private func commit(_ updatedItems: [TodoItem]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try TodoFileCodec.encode(updatedItems).write(to: fileURL, options: .atomic)
        items = TodoPolicy.sorted(updatedItems)
    }

    private static func load(from fileURL: URL) throws -> [TodoItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try TodoFileCodec.decode(Data(contentsOf: fileURL))
    }
}
