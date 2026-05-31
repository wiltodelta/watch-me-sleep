import Foundation
import IOKit

/// Automatically arms a regular sleep timer when the Mac has been idle for a
/// configurable number of minutes inside a nightly time window. This solves the
/// "I keep forgetting to start the timer" problem: set it once and it triggers
/// on its own when you stop using the Mac late at night.
public final class AutoActivationManager: ObservableObject {
    public static let shared = AutoActivationManager()

    // MARK: - User-configurable settings (persisted)

    @Published public var isEnabled: Bool = false { didSet { settingsChanged() } }
    @Published public var activeAfterHour: Int = 21 { didSet { persist() } }
    @Published public var idleMinutes: Int = 30 { didSet { persist() } }
    @Published public var timerHours: Double = 1.0 { didSet { persist() } }

    /// End of the nightly window (exclusive). Fixed for now; the window runs from
    /// `activeAfterHour` overnight until this morning hour.
    public let windowEndHour = 8

    // MARK: - Test seams

    /// Source of the current system idle time, in seconds. Overridable in tests.
    var idleSecondsProvider: () -> TimeInterval = { AutoActivationManager.systemIdleSeconds() }
    /// Whether a timer is already running. Overridable in tests.
    var isTimerActive: () -> Bool = { TimerManager.shared.isTimerActive }
    /// Whether camera mode is handling sleep detection. Overridable in tests.
    var isCameraModeEnabled: () -> Bool = { SleepDetectionManager.shared.isCameraModeEnabled }
    /// Action that arms the timer. Overridable in tests.
    var startTimer: (Double) -> Void = { TimerManager.shared.startTimer(hours: $0) }
    /// UserDefaults store. Overridable in tests to avoid polluting standard defaults.
    var defaults: UserDefaults = .standard

    // MARK: - Persistence keys

    private enum Key {
        static let enabled = "AutoActivation.enabled"
        static let afterHour = "AutoActivation.afterHour"
        static let idleMinutes = "AutoActivation.idleMinutes"
        static let timerHours = "AutoActivation.timerHours"
    }

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 30
    private var isLoaded = false

    private init() {
        load()
        isLoaded = true
    }

    // MARK: - Monitoring

    /// Starts (or stops) the idle poll based on the current enabled state.
    /// Safe to call multiple times.
    public func startMonitoring() {
        DispatchQueue.main.async { [weak self] in
            self?.reschedule()
        }
    }

    private func reschedule() {
        pollTimer?.invalidate()
        pollTimer = nil

        guard isEnabled else { return }

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        if shouldActivate(now: Date(), idleSeconds: idleSecondsProvider()) {
            startTimer(timerHours)
        }
    }

    // MARK: - Decision logic (pure, unit-tested)

    /// Whether the timer should be armed right now. Side-effect free.
    func shouldActivate(now: Date, idleSeconds: TimeInterval, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        guard !isTimerActive() else { return false }       // don't disturb a running timer
        guard !isCameraModeEnabled() else { return false }  // camera mode does its own detection
        guard isWithinWindow(now, calendar: calendar) else { return false }
        return idleSeconds >= TimeInterval(idleMinutes * 60)
    }

    /// Whether `date` falls inside the nightly window `[activeAfterHour, windowEndHour)`,
    /// wrapping across midnight when the start hour is later than the end hour.
    func isWithinWindow(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if activeAfterHour <= windowEndHour {
            return hour >= activeAfterHour && hour < windowEndHour
        } else {
            return hour >= activeAfterHour || hour < windowEndHour
        }
    }

    // MARK: - System idle time

    /// Seconds since the last user input, read from the IOHIDSystem `HIDIdleTime`
    /// property (reported in nanoseconds). Requires no special permission.
    static func systemIdleSeconds() -> TimeInterval {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let dict = properties?.takeRetainedValue() as? [String: Any],
            let idleNanoseconds = dict["HIDIdleTime"] as? UInt64 else {
            return 0
        }

        return TimeInterval(idleNanoseconds) / 1_000_000_000.0
    }

    // MARK: - Persistence

    private func load() {
        if defaults.object(forKey: Key.enabled) != nil {
            isEnabled = defaults.bool(forKey: Key.enabled)
        }
        if defaults.object(forKey: Key.afterHour) != nil {
            activeAfterHour = defaults.integer(forKey: Key.afterHour)
        }
        if defaults.object(forKey: Key.idleMinutes) != nil {
            idleMinutes = defaults.integer(forKey: Key.idleMinutes)
        }
        if defaults.object(forKey: Key.timerHours) != nil {
            timerHours = defaults.double(forKey: Key.timerHours)
        }
    }

    private func persist() {
        guard isLoaded else { return }
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(activeAfterHour, forKey: Key.afterHour)
        defaults.set(idleMinutes, forKey: Key.idleMinutes)
        defaults.set(timerHours, forKey: Key.timerHours)
    }

    private func settingsChanged() {
        persist()
        startMonitoring()
    }
}
