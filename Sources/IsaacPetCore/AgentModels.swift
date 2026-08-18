import Foundation

public enum AgentRoleID: String, Codable, CaseIterable, Sendable {
    case isaac
    case magdalene
    case cain
    case judas
}

public enum AgentCapability: String, Codable, CaseIterable, Sendable {
    case readLocalTodos
    case writeLocalTodos
    case focusTimer
    case readExternalTasks
    case writeExternalTasks
    case networkResearch
    case runCommands
}

public enum AgentAuthorization: String, Codable, Equatable, Sendable {
    case automatic
    case requiresConfirmation
    case unavailable
}

public struct AgentRoleProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: AgentRoleID
    public let displayName: String
    public let specialty: String
    public let capabilities: Set<AgentCapability>

    public init(
        id: AgentRoleID,
        displayName: String,
        specialty: String,
        capabilities: Set<AgentCapability>
    ) {
        self.id = id
        self.displayName = displayName
        self.specialty = specialty
        self.capabilities = capabilities
    }
}

public enum AgentCatalog {
    public static let profiles: [AgentRoleProfile] = [
        AgentRoleProfile(
            id: .isaac,
            displayName: "Isaac",
            specialty: "Todo 总览与今日计划",
            capabilities: [.readLocalTodos]
        ),
        AgentRoleProfile(
            id: .magdalene,
            displayName: "Magdalene",
            specialty: "休息、健康与节奏提醒",
            capabilities: [.readLocalTodos]
        ),
        AgentRoleProfile(
            id: .cain,
            displayName: "Cain",
            specialty: "资料研究（尚未启用联网工具）",
            capabilities: [.networkResearch]
        ),
        AgentRoleProfile(
            id: .judas,
            displayName: "Judas",
            specialty: "专注计时与任务执行",
            capabilities: [.readLocalTodos, .writeLocalTodos, .focusTimer]
        ),
    ]

    public static func profile(for id: AgentRoleID) -> AgentRoleProfile {
        profiles.first(where: { $0.id == id })!
    }
}

public enum AgentExecutionPolicy {
    public static func authorization(
        for capability: AgentCapability,
        role: AgentRoleProfile
    ) -> AgentAuthorization {
        guard role.capabilities.contains(capability) else { return .unavailable }
        switch capability {
        case .readLocalTodos, .focusTimer:
            return .automatic
        case .writeLocalTodos, .readExternalTasks:
            return .requiresConfirmation
        case .writeExternalTasks, .networkResearch, .runCommands:
            // These require both an installed tool adapter and per-action confirmation.
            // No such adapter is installed in the initial local-agent release.
            return .unavailable
        }
    }
}

public enum AgentTaskStatus: String, Codable, Equatable, Sendable {
    case queued
    case running
    case awaitingConfirmation
    case succeeded
    case failed
    case cancelled

    /// Keeps persisted task history append-only in spirit: terminal states cannot be reopened,
    /// and a confirmation-gated capability cannot jump straight from queued to success.
    public func allowsTransition(to next: AgentTaskStatus) -> Bool {
        switch self {
        case .queued:
            return [.running, .awaitingConfirmation, .cancelled, .failed].contains(next)
        case .running:
            return [.succeeded, .failed, .cancelled].contains(next)
        case .awaitingConfirmation:
            return [.running, .succeeded, .failed, .cancelled].contains(next)
        case .succeeded, .failed, .cancelled:
            return false
        }
    }

    public var isTerminal: Bool {
        [.succeeded, .failed, .cancelled].contains(self)
    }
}

public struct AgentTask: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let roleID: AgentRoleID
    public let capability: AgentCapability
    public let title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var status: AgentTaskStatus
    public var resultSummary: String?
    public var deadlineAt: Date?
    public var subject: String?

    public init(
        id: UUID = UUID(),
        roleID: AgentRoleID,
        capability: AgentCapability,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        status: AgentTaskStatus = .queued,
        resultSummary: String? = nil,
        deadlineAt: Date? = nil,
        subject: String? = nil
    ) {
        self.id = id
        self.roleID = roleID
        self.capability = capability
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.status = status
        self.resultSummary = resultSummary
        self.deadlineAt = deadlineAt
        self.subject = subject
    }
}

public struct AgentAuditEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let taskID: UUID
    public let timestamp: Date
    public let roleID: AgentRoleID
    public let capability: AgentCapability
    public let status: AgentTaskStatus
    public let summary: String

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        timestamp: Date = Date(),
        roleID: AgentRoleID,
        capability: AgentCapability,
        status: AgentTaskStatus,
        summary: String
    ) {
        self.id = id
        self.taskID = taskID
        self.timestamp = timestamp
        self.roleID = roleID
        self.capability = capability
        self.status = status
        self.summary = String(summary.prefix(240))
    }
}

public struct DailyPlan: Equatable, Sendable {
    public let headline: String
    public let steps: [String]
    public let sourceTodoIDs: [UUID]

    public init(headline: String, steps: [String], sourceTodoIDs: [UUID]) {
        self.headline = headline
        self.steps = steps
        self.sourceTodoIDs = sourceTodoIDs
    }
}

public struct WellbeingPlan: Equatable, Sendable {
    public let headline: String
    public let suggestions: [String]
    public let workloadCount: Int

    public init(headline: String, suggestions: [String], workloadCount: Int) {
        self.headline = headline
        self.suggestions = suggestions
        self.workloadCount = workloadCount
    }
}

public enum LocalPlanningAgent {
    public static func makeDailyPlan(
        from items: [TodoItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyPlan {
        let pending = TodoPolicy.pending(items)
        guard !pending.isEmpty else {
            return DailyPlan(
                headline: "今天没有待办，留一点时间休息吧。",
                steps: ["检查是否需要补充新的 Todo"],
                sourceTodoIDs: []
            )
        }

        let overdue = pending.filter { $0.dueAt.map { $0 < now } == true }
        let dueToday = pending.filter { item in
            guard let dueAt = item.dueAt, dueAt >= now else { return false }
            return calendar.isDate(dueAt, inSameDayAs: now)
        }
        let upcoming = pending.filter { item in
            guard let dueAt = item.dueAt else { return false }
            return dueAt > now && !calendar.isDate(dueAt, inSameDayAs: now)
        }
        let undated = pending.filter { $0.dueAt == nil }

        var selected: [TodoItem] = []
        selected.append(contentsOf: overdue.prefix(2))
        selected.append(contentsOf: dueToday.prefix(max(0, 3 - selected.count)))
        selected.append(contentsOf: upcoming.prefix(max(0, 3 - selected.count)))
        selected.append(contentsOf: undated.prefix(max(0, 3 - selected.count)))

        var steps = selected.enumerated().map { index, item in
            let prefix: String
            if overdue.contains(where: { $0.id == item.id }) {
                prefix = "先处理逾期"
            } else if dueToday.contains(where: { $0.id == item.id }) {
                prefix = "今天完成"
            } else {
                prefix = index == 0 ? "先做" : "接着做"
            }
            return "\(prefix)：\(item.title)"
        }
        if pending.count > selected.count {
            steps.append("其余 \(pending.count - selected.count) 项留在 Todo 中，完成后再排")
        }
        let headline: String
        if !overdue.isEmpty {
            headline = "有 \(overdue.count) 项逾期，先清理最紧急的任务。"
        } else if !dueToday.isEmpty {
            headline = "今天有 \(dueToday.count) 项到期，建议聚焦前三项。"
        } else {
            headline = "没有今天到期的任务，选三项稳步推进。"
        }
        return DailyPlan(
            headline: headline,
            steps: steps,
            sourceTodoIDs: selected.map(\.id)
        )
    }
}

public enum LocalWellbeingAgent {
    public static func makeRhythmCheck(
        from items: [TodoItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WellbeingPlan {
        let pending = TodoPolicy.pending(items)
        let overdueCount = pending.filter { $0.dueAt.map { $0 < now } == true }.count
        let dueTodayCount = pending.filter { item in
            guard let dueAt = item.dueAt, dueAt >= now else { return false }
            return calendar.isDate(dueAt, inSameDayAs: now)
        }.count
        let immediateCount = overdueCount + dueTodayCount

        guard !pending.isEmpty else {
            return WellbeingPlan(
                headline: "今天的 Todo 很轻，别忘了照顾自己。",
                suggestions: ["喝点水，活动一下肩颈", "休息后再决定是否添加新任务"],
                workloadCount: 0
            )
        }

        let headline: String
        if overdueCount > 0 {
            headline = "有 \(overdueCount) 项逾期，先减压，再处理最重要的一项。"
        } else if dueTodayCount >= 3 {
            headline = "今天有 \(dueTodayCount) 项到期，任务较密集。"
        } else if dueTodayCount > 0 {
            headline = "今天有 \(dueTodayCount) 项到期，保持稳定节奏。"
        } else {
            headline = "没有临近截止的 Todo，可以从容推进。"
        }

        var suggestions = ["先喝水并离开屏幕 2 分钟"]
        if immediateCount >= 3 {
            suggestions.append("只选一项开始，专注 25 分钟后休息 5 分钟")
        } else {
            suggestions.append("完成一小步后，起身活动 5 分钟")
        }
        if pending.count > immediateCount {
            suggestions.append("其余 \(pending.count - immediateCount) 项暂不抢占注意力")
        }
        return WellbeingPlan(
            headline: headline,
            suggestions: Array(suggestions.prefix(3)),
            workloadCount: pending.count
        )
    }
}

public enum FocusSessionPolicy {
    public static let defaultDuration: TimeInterval = 25 * 60
    public static let maximumDuration: TimeInterval = 2 * 60 * 60

    public static func duration(from rawValue: String?) -> TimeInterval {
        guard let rawValue,
              let seconds = TimeInterval(rawValue),
              seconds.isFinite,
              seconds >= 1 else {
            return defaultDuration
        }
        return min(seconds, maximumDuration)
    }

    public static func remainingSeconds(until deadline: Date, now: Date = Date()) -> Int {
        max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    public static func clockText(remainingSeconds: Int) -> String {
        let clamped = max(0, remainingSeconds)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    public static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(1, Int(duration.rounded()))
        if seconds.isMultiple(of: 60) {
            return "\(seconds / 60) 分钟"
        }
        return "\(seconds) 秒"
    }
}

public enum FocusSessionTimer {
    public static func wait(until deadline: Date) async throws {
        let remaining = deadline.timeIntervalSinceNow
        if remaining > 0 {
            try await Task.sleep(for: .seconds(remaining))
        }
        try Task.checkCancellation()
    }
}
