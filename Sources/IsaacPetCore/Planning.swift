import Foundation

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
