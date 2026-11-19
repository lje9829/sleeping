import DeviceActivity
import Foundation
import ManagedSettings

enum Restriction {
    static let activity = DeviceActivityName("bedtime")
    static let duration: TimeInterval = 3_600
    static let store = ManagedSettingsStore(named: .init("bedtime"))
    static let endKey = "bedtime.end"
    static let defaults: UserDefaults? = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SleepFirstAppGroup") as? String,
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
        else { return nil }
        return UserDefaults(suiteName: group)
    }()

    static func clear() {
        store.clearAllSettings()
        defaults?.removeObject(forKey: endKey)
    }

    static func clearIfExpired(at now: Date = .now) {
        guard let defaults else { return }
        guard let end = defaults.object(forKey: endKey) as? Date, end <= now else { return }
        clear()
    }
}
