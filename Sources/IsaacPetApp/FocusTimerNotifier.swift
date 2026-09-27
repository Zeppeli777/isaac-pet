import Foundation
import UserNotifications

/// Schedules the local notification fired when a focus countdown finishes. Each
/// countdown owns a session ID so a cancel can retract the request even while a
/// macOS permission dialog is still pending.
@MainActor
final class FocusTimerNotifier {
    private static let identifierPrefix = "isaac-pet.focus."
    private let center = UNUserNotificationCenter.current()
    private var cancelledSessionIDs: Set<UUID> = []

    func scheduleCompletion(sessionID: UUID, target: String?, deadline: Date) async throws -> Bool {
        cancelledSessionIDs.remove(sessionID)
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
        guard isAuthorized, !cancelledSessionIDs.contains(sessionID) else { return false }

        removePending(sessionID: sessionID)
        let remaining = max(1, deadline.timeIntervalSinceNow)
        let content = UNMutableNotificationContent()
        content.title = "专注结束"
        content.body = target.map { "你完成了一个专注时段：\($0)" } ?? "你完成了一个专注时段，起来休息一下吧。"
        content.sound = .default
        content.userInfo = ["focusSessionID": sessionID.uuidString]
        let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + sessionID.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        )
        try await center.add(request)
        return true
    }

    func removePending(sessionID: UUID) {
        cancelledSessionIDs.insert(sessionID)
        let identifier = Self.identifierPrefix + sessionID.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
