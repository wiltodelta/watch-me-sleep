import Foundation

/// Settings on disk, and their snapshot for the journal.
extension SleepSupervisor {
    enum Key {
        static let enabled = "NightWatch.enabled"
        static let bedtimeStart = "NightWatch.bedtimeStart"
        static let bedtimeEnd = "NightWatch.bedtimeEnd"
        // Whole hours, as 3.0 and earlier stored them; read once to carry over.
        static let legacyStartHour = "AutoActivation.afterHour"
        static let legacyEndHour = "AutoActivation.untilHour"
        static let usesCamera = "AutoActivation.checksWithCamera"
        static let keepsSoundPlaying = "NightWatch.keepsSoundPlaying"
        static let soundChoiceAsked = "NightWatch.soundChoiceAsked"
    }

    /// A bedtime in minutes after midnight, or the whole hour 3.0 and earlier
    /// stored under the legacy key, or nil when neither is there.
    static func storedMinutes(_ defaults: UserDefaults, key: String, legacyHourKey: String) -> Int? {
        if defaults.object(forKey: key) != nil {
            return defaults.integer(forKey: key)
        }
        if defaults.object(forKey: legacyHourKey) != nil {
            return defaults.integer(forKey: legacyHourKey) * 60
        }
        return nil
    }

    func load() {
        if defaults.object(forKey: Key.enabled) != nil {
            isEnabled = defaults.bool(forKey: Key.enabled)
        }
        if let start = Self.storedMinutes(defaults, key: Key.bedtimeStart, legacyHourKey: Key.legacyStartHour) {
            bedtimeStart = start
        }
        if let end = Self.storedMinutes(defaults, key: Key.bedtimeEnd, legacyHourKey: Key.legacyEndHour) {
            bedtimeEnd = end
        }
        if defaults.object(forKey: Key.usesCamera) != nil {
            usesCamera = defaults.bool(forKey: Key.usesCamera)
        }
        keepsSoundPlaying = defaults.bool(forKey: Key.keepsSoundPlaying)
    }

    func persist() {
        guard isLoaded else { return }
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(bedtimeStart, forKey: Key.bedtimeStart)
        defaults.set(bedtimeEnd, forKey: Key.bedtimeEnd)
        defaults.set(usesCamera, forKey: Key.usesCamera)
        defaults.set(keepsSoundPlaying, forKey: Key.keepsSoundPlaying)
        Journal.shared.record("settings", settingsSnapshot)
    }

    /// The settings as they stand, for the journal.
    public var settingsSnapshot: [String: Any] {
        ["enabled": isEnabled, "bedtime": bedtimeRangeText, "usesCamera": usesCamera,
         "cameraAuthorized": cameraAuthorized(), "keepsSoundPlaying": keepsSoundPlaying]
    }

    func settingsChanged() {
        persist()
        startMonitoring()
    }
}
