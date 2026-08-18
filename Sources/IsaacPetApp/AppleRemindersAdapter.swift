@preconcurrency import EventKit
import Foundation
import IsaacPetCore

struct AppleReminderList: Equatable, Sendable {
    let identifier: String
    let title: String
}

enum AppleRemindersAdapterError: LocalizedError {
    case accessDenied
    case calendarUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Isaac Pet 没有读取 Apple“提醒事项”的权限。"
        case .calendarUnavailable:
            return "之前选择的提醒事项列表已不存在，请重新选择。"
        }
    }
}

@MainActor
final class AppleRemindersAdapter {
    private let eventStore = EKEventStore()

    var hasReadAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    func requestReadAccess() async throws -> Bool {
        if hasReadAccess { return true }
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .denied || status == .restricted { return false }

        if #available(macOS 14.0, *) {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .reminder) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func reminderLists() throws -> [AppleReminderList] {
        guard hasReadAccess else { throw AppleRemindersAdapterError.accessDenied }
        return eventStore.calendars(for: .reminder)
            .map { AppleReminderList(identifier: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func fetchRecords(
        calendarIdentifier: String?,
        knownItemIdentifiers: Set<String>
    ) async throws -> [ExternalTodoRecord] {
        guard hasReadAccess else { throw AppleRemindersAdapterError.accessDenied }

        let calendars: [EKCalendar]?
        if let calendarIdentifier {
            guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) else {
                throw AppleRemindersAdapterError.calendarUnavailable
            }
            calendars = [calendar]
        } else {
            calendars = nil
        }
        let predicate = eventStore.predicateForReminders(in: calendars)
        let syncDate = Date()

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let records = (reminders ?? []).compactMap { reminder -> ExternalTodoRecord? in
                    let calendarID = reminder.calendar.calendarIdentifier
                    let externalID = reminder.calendarItemExternalIdentifier
                        ?? reminder.calendarItemIdentifier
                    let stableID = "\(calendarID)::\(externalID)"

                    // Import every pending reminder. Completed reminders are only refreshed when
                    // they were already linked, which avoids importing a user's entire history.
                    guard !reminder.isCompleted || knownItemIdentifiers.contains(stableID) else {
                        return nil
                    }
                    let dueAt = Self.date(from: reminder.dueDateComponents)
                    let completedAt = reminder.isCompleted
                        ? reminder.completionDate ?? reminder.lastModifiedDate ?? syncDate
                        : nil
                    return ExternalTodoRecord(
                        source: TodoExternalSource(
                            kind: .appleReminders,
                            itemIdentifier: stableID,
                            containerIdentifier: calendarID,
                            containerTitle: reminder.calendar.title,
                            lastSyncedAt: syncDate
                        ),
                        title: reminder.title ?? "",
                        dueAt: dueAt,
                        completedAt: completedAt
                    )
                }
                continuation.resume(returning: records)
            }
        }
    }

    private static func date(from components: DateComponents?) -> Date? {
        guard let components else { return nil }
        var calendar = components.calendar ?? Calendar(identifier: .gregorian)
        if let timeZone = components.timeZone { calendar.timeZone = timeZone }
        return calendar.date(from: components)
    }
}
