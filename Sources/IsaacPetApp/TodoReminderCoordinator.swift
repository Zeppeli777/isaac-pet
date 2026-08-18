import Foundation
import IsaacPetCore
import UserNotifications

@MainActor
final class TodoReminderCoordinator {
    private static let identifierPrefix = "isaac-pet.todo."
    private let center = UNUserNotificationCenter.current()

    /// Replaces every pending Isaac Todo notification. Returns false when system notifications
    /// are denied; in-app bubble reminders can still work while Isaac Pet is running.
    func synchronize(_ items: [TodoItem], now: Date = Date()) async throws -> Bool {
        let pendingRequests = await center.pendingNotificationRequests()
        let existingIdentifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existingIdentifiers)

        let schedulable = TodoPolicy.pending(items).filter { item in
            item.remindedAt == nil && item.dueAt.map { $0 > now } == true
        }
        guard !schedulable.isEmpty else { return true }

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
        guard isAuthorized else { return false }

        for item in schedulable {
            guard let dueAt = item.dueAt else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Isaac 提醒你"
            content.body = item.title
            content.sound = .default
            content.userInfo = ["todoID": item.id.uuidString]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: dueAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.identifierPrefix + item.id.uuidString,
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
        return true
    }

    func removeAllTodoNotifications() async {
        let pendingRequests = await center.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
