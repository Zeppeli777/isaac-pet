import Foundation

public enum AgentAuditStoreError: LocalizedError {
    case missingApplicationSupportDirectory
    case invalidTransition(from: AgentTaskStatus, to: AgentTaskStatus)

    public var errorDescription: String? {
        switch self {
        case .missingApplicationSupportDirectory:
            return "无法找到本机的 Application Support 目录。"
        case let .invalidTransition(from, to):
            return "Agent 任务不能从 \(from.rawValue) 转为 \(to.rawValue)。"
        }
    }
}

@MainActor
public final class AgentAuditStore {
    public private(set) var tasks: [AgentTask]
    public private(set) var events: [AgentAuditEvent]
    public let directoryURL: URL
    private let tasksURL: URL
    private let eventsURL: URL

    public init(directoryURL: URL? = nil) throws {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else if let overridePath = ProcessInfo.processInfo.environment["ISAAC_AGENT_DATA_DIR"],
                  !overridePath.isEmpty {
            self.directoryURL = URL(fileURLWithPath: overridePath, isDirectory: true)
        } else {
            guard let supportDirectory = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw AgentAuditStoreError.missingApplicationSupportDirectory
            }
            self.directoryURL = supportDirectory
                .appendingPathComponent("Isaac Pet", isDirectory: true)
                .appendingPathComponent("Agents", isDirectory: true)
        }
        tasksURL = self.directoryURL.appendingPathComponent("tasks-v1.json")
        eventsURL = self.directoryURL.appendingPathComponent("audit-v1.jsonl")
        tasks = try Self.loadTasks(from: tasksURL)
        events = try Self.loadEvents(from: eventsURL)
    }

    @discardableResult
    public func createTask(
        roleID: AgentRoleID,
        capability: AgentCapability,
        title: String,
        deadlineAt: Date? = nil,
        subject: String? = nil,
        at date: Date = Date()
    ) throws -> AgentTask {
        let task = AgentTask(
            roleID: roleID,
            capability: capability,
            title: String(title.prefix(160)),
            createdAt: date,
            deadlineAt: deadlineAt,
            subject: subject.map { String($0.prefix(120)) }
        )
        tasks.insert(task, at: 0)
        try persistTasks()
        try appendEvent(for: task, status: .queued, summary: "任务已加入队列", at: date)
        return task
    }

    @discardableResult
    public func transition(
        taskID: UUID,
        to status: AgentTaskStatus,
        summary: String,
        at date: Date = Date()
    ) throws -> AgentTask? {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return nil }
        guard tasks[index].status.allowsTransition(to: status) else {
            throw AgentAuditStoreError.invalidTransition(from: tasks[index].status, to: status)
        }
        tasks[index].status = status
        tasks[index].updatedAt = date
        if [.succeeded, .failed, .cancelled].contains(status) {
            tasks[index].resultSummary = String(summary.prefix(240))
        }
        try persistTasks()
        try appendEvent(for: tasks[index], status: status, summary: summary, at: date)
        return tasks[index]
    }

    private func appendEvent(
        for task: AgentTask,
        status: AgentTaskStatus,
        summary: String,
        at date: Date
    ) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let event = AgentAuditEvent(
            taskID: task.id,
            timestamp: date,
            roleID: task.roleID,
            capability: task.capability,
            status: status,
            summary: summary
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(event)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: eventsURL.path) {
            let handle = try FileHandle(forWritingTo: eventsURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: eventsURL, options: .atomic)
        }
        events.insert(event, at: 0)
        if events.count > 500 { events.removeLast(events.count - 500) }
    }

    private func persistTasks() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Array(tasks.prefix(100))).write(to: tasksURL, options: .atomic)
    }

    private static func loadTasks(from url: URL) throws -> [AgentTask] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AgentTask].self, from: Data(contentsOf: url))
    }

    private static func loadEvents(from url: URL) throws -> [AgentAuditEvent] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try Data(contentsOf: url)
            .split(separator: 0x0A)
            .compactMap { try? decoder.decode(AgentAuditEvent.self, from: Data($0)) }
            .reversed()
            .prefix(500)
            .map { $0 }
    }
}
