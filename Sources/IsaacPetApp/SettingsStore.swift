import CoreGraphics
import Foundation
import IsaacPetCore

@MainActor
final class SettingsStore {
    private enum Key {
        static let scale = "pet.scale"
        static let roaming = "pet.roaming"
        static let screen = "pet.screen"
        static let horizontalPosition = "pet.horizontalPosition"
        static let appleReminderCalendar = "integration.appleReminders.calendarIdentifier"
        static let notionDataSource = "integration.notion.dataSourceIdentifier"
        static let activeAppearance = "pet.activeAppearance"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.scale: 1.0,
            Key.roaming: true,
            Key.horizontalPosition: 0.82,
        ])
    }

    func load() -> PetSettings {
        PetSettings(
            scale: defaults.double(forKey: Key.scale),
            roamingEnabled: defaults.bool(forKey: Key.roaming),
            screenIdentifier: defaults.string(forKey: Key.screen),
            horizontalPosition: defaults.double(forKey: Key.horizontalPosition)
        )
    }

    func save(_ settings: PetSettings) {
        defaults.set(Double(settings.scale), forKey: Key.scale)
        defaults.set(settings.roamingEnabled, forKey: Key.roaming)
        defaults.set(settings.screenIdentifier, forKey: Key.screen)
        defaults.set(Double(settings.horizontalPosition), forKey: Key.horizontalPosition)
    }

    var appleReminderCalendarIdentifier: String? {
        get { defaults.string(forKey: Key.appleReminderCalendar) }
        set { defaults.set(newValue, forKey: Key.appleReminderCalendar) }
    }

    var notionDataSourceIdentifier: String? {
        get { defaults.string(forKey: Key.notionDataSource) }
        set { defaults.set(newValue, forKey: Key.notionDataSource) }
    }

    var activeAppearance: String {
        get { defaults.string(forKey: Key.activeAppearance) ?? PetAppearanceID.isaac.rawValue }
        set { defaults.set(newValue, forKey: Key.activeAppearance) }
    }
}
