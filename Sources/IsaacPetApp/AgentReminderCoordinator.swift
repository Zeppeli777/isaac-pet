import Foundation
import UserNotifications

@MainActor
final class AgentReminderCoordinator {
    private static let identifierPrefix = "isaac-pet.agent.focus."
    private let center = UNUserNotificationCenter.current()
    private var cancelledTaskIDs: Set<UUID> = []

    func scheduleFocusCompletion(taskID: UUID, target: String?, deadline: Date) async throws -> Bool {
        cancelledTaskIDs.remove(taskID)
        let settings = await center.notificationSettings()
        let isAuthorized: Bool
        switch settings.authorizationStatus {
        case .notDetermined:
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound])
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .denied:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
        guard isAuthorized, !cancelledTaskIDs.contains(taskID) else { return false }

        removeFocusCompletion(taskID: taskID)
        let remaining = max(1, deadline.timeIntervalSinceNow)
        let content = UNMutableNotificationContent()
        content.title = "Judas：专注结束"
        content.body = target.map { "你完成了一个专注时段：\($0)" } ?? "你完成了一个专注时段，起来休息一下吧。"
        content.sound = .default
        content.userInfo = ["agentTaskID": taskID.uuidString]
        let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + taskID.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        )
        try await center.add(request)
        return true
    }

    func removeFocusCompletion(taskID: UUID) {
        cancelledTaskIDs.insert(taskID)
        let identifier = Self.identifierPrefix + taskID.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
