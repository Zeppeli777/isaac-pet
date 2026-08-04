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
}
