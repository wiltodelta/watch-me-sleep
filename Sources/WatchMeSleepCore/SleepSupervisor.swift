import Foundation
import os

/// What the night watch decides from one look at the signals. Pure and
/// side-effect free, so every rule is unit-tested without clocks or cameras.
///
/// The question is never "is the Mac idle" (macOS sleeps an idle Mac by itself)
/// but "is something keeping it awake that nobody is using any more".
enum NightWatchPolicy {
    /// Media playing and no input this long: the camera takes its first look.
    static let firstLookIdle: TimeInterval = 10 * 60
    /// Wait before looking again after open eyes or an unclear picture.
    static let recheckInterval: TimeInterval = 10 * 60
    /// Nothing playing and no input this long means nobody is there. No camera
    /// here: with nothing playing, nobody is watching anything, and macOS would
    /// dim the display about now anyway.
    static let quietIdle: TimeInterval = 20 * 60
    /// Without a camera: media playing and no input this long, ask "still watching?".
    static let stillWatchingIdle: TimeInterval = 90 * 60
    /// Even with the camera seeing open eyes, ask after this long: some people
    /// sleep with their eyes partly open, and the final minute spares anyone awake.
    static let askAnywayIdle: TimeInterval = 3 * 60 * 60
    /// Unclear looks in one idle stretch before the camera stops being trusted.
    static let maxUnclearLooks = 2
    /// Timer started once the camera (or a quiet Mac) says nobody is watching.
    static let confirmedTimerHours = 0.25

    enum Decision: Equatable {
        case wait
        case look
        /// Start a 15-minute timer: asleep, gone, or nothing left playing.
        case armConfirmed
        /// Go straight to the final minute: "still watching?".
        case askStillWatching
    }

    struct Input {
        var idle: TimeInterval
        var mediaPlaying: Bool
        var cameraUsable: Bool
        var unclearLooks: Int
        /// The recheck interval since the last look has passed.
        var lookDue: Bool

        /// The camera can answer: usable, and not unclear too often this stretch.
        var cameraTrusted: Bool { cameraUsable && unclearLooks < maxUnclearLooks }

        /// The camera answers only the one unclear case: something plays and
        /// nobody touches the Mac. Watching, or asleep in front of it?
        var cameraDecides: Bool { mediaPlaying && cameraTrusted }
    }

    static func decide(_ input: Input) -> Decision {
        if input.idle >= askAnywayIdle {
            return .askStillWatching
        }
        if input.cameraDecides {
            return input.idle >= firstLookIdle && input.lookDue ? .look : .wait
        }
        if !input.mediaPlaying {
            return input.idle >= quietIdle ? .armConfirmed : .wait
        }
        return input.idle >= stillWatchingIdle ? .askStillWatching : .wait
    }
}

/// What the night watch is doing, for the panel and the menu bar tooltip.
public enum NightWatchStatus: Equatable {
    case off
    case outsideHours
    case inUse
    case timerRunning
    case watching(idleMinutes: Int, mediaPlaying: Bool, nextLook: Date?)
    case looking
    /// It already acted in this idle stretch (the display went off for work
    /// that holds the Mac awake); nothing more until someone is back.
    case done
}

/// The one automatic mode: during bedtime hours it watches what keeps the Mac
/// awake and, when nobody is using it any more, starts a timer that ends in
/// sleep (or display off, when work holds the Mac). Replaces the old separate
/// camera mode and idle auto-start.
public final class SleepSupervisor: ObservableObject {
    public static let shared = SleepSupervisor()

    // MARK: - Settings (persisted)

    @Published public var isEnabled: Bool = true { didSet { settingsChanged() } }
    /// Bedtime start, in minutes after midnight.
    @Published public var bedtimeStart: Int = 21 * 60 { didSet { persist() } }
    /// Bedtime end (exclusive), in minutes after midnight; the next morning
    /// when it is earlier than the start.
    @Published public var bedtimeEnd: Int = 8 * 60 { didSet { persist() } }
    /// Look with the camera when it is unclear whether anyone is watching.
    @Published public var usesCamera: Bool = true { didSet { persist() } }

    @Published public private(set) var status: NightWatchStatus = .off

    // MARK: - Test seams

    var now: () -> Date = Date.init
    var idleSecondsProvider: () -> TimeInterval = { SystemSignals.idleSeconds() }
    var wakeHolders: () -> WakeHolders = { SystemSignals.wakeHolders() }
    var cameraAuthorized: () -> Bool = { CameraWatcher.isAuthorized }
    var checkPresence: (@escaping (PresenceCheck.Verdict) -> Void) -> Void = {
        CameraWatcher.shared.checkPresence(completion: $0)
    }
    var timer: TimerManager = .shared
    var defaults: UserDefaults = .standard

    // MARK: - State (internal so tests on the shared instance can reset it)

    /// One stretch of not using the Mac; starts over when someone is back.
    struct Stretch {
        var nextLook: Date = .distantPast
        /// Unclear looks so far; a camera that cannot be used counts as the
        /// maximum, so both ways of not trusting it are one rule.
        var unclearLooks = 0
        /// Already acted in this stretch.
        var acted = false
    }

    var stretch = Stretch()
    /// A camera look is running, for a decision or for a final minute.
    var isLooking = false

    /// Input more recent than this counts as someone using the Mac.
    static let inUseIdle: TimeInterval = 30
    private let pollInterval: TimeInterval = 10
    private var pollTimer: Timer?
    private var isLoaded = false
    private let log = Logger.app("nightwatch")

    enum Key {
        static let enabled = "NightWatch.enabled"
        static let bedtimeStart = "NightWatch.bedtimeStart"
        static let bedtimeEnd = "NightWatch.bedtimeEnd"
        // Whole hours, as 3.0 and earlier stored them; read once to carry over.
        static let legacyStartHour = "AutoActivation.afterHour"
        static let legacyEndHour = "AutoActivation.untilHour"
        static let usesCamera = "AutoActivation.checksWithCamera"
    }

    private init() {
        load()
        isLoaded = true
    }

    // MARK: - Monitoring

    public func startMonitoring() {
        DispatchQueue.main.async { [weak self] in
            self?.reschedule()
        }
    }

    private func reschedule() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard isEnabled else {
            status = .off
            return
        }
        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Nothing here needs second precision; let macOS batch the wakeups.
        timer.tolerance = 2
        pollTimer = timer
        tick()
    }

    // MARK: - Tick

    func tick() {
        let idle = idleSecondsProvider()
        if let gate = gate(idle: idle) {
            return setStatus(gate)
        }
        act(idle: idle)
    }

    /// The states in which the night watch does nothing new; nil when it may act.
    private func gate(idle: TimeInterval) -> NightWatchStatus? {
        let inUse = idle < Self.inUseIdle
        if inUse {
            stretch = Stretch()
        }
        guard isEnabled else { return .off }
        if timer.isTimerActive { return .timerRunning }
        guard isWithinWindow(now()) else { return .outsideHours }
        if inUse { return .inUse }
        if stretch.acted { return .done }
        if isLooking { return .looking }
        return nil
    }

    private func act(idle: TimeInterval) {
        let holders = wakeHolders()
        let input = NightWatchPolicy.Input(
            idle: idle,
            mediaPlaying: holders.mediaPlaying,
            cameraUsable: cameraUsable,
            unclearLooks: stretch.unclearLooks,
            lookDue: now() >= stretch.nextLook
        )

        switch NightWatchPolicy.decide(input) {
        case .wait:
            // To the minute, as shown: a status that changes every tick would
            // re-render the panel every 10 seconds for nothing.
            let next = input.cameraDecides
                ? Self.minuteUp(max(stretch.nextLook, now().addingTimeInterval(NightWatchPolicy.firstLookIdle - idle)))
                : nil
            setStatus(.watching(idleMinutes: Int(idle / 60), mediaPlaying: holders.mediaPlaying, nextLook: next))
        case .look:
            look()
        case .armConfirmed:
            arm(hours: NightWatchPolicy.confirmedTimerHours, reason: "nobody watching")
        case .askStillWatching:
            arm(hours: TimerManager.finalPhaseDuration / 3600, reason: "still watching?")
        }
    }

    private static func minuteUp(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
    }

    private var cameraUsable: Bool {
        usesCamera && cameraAuthorized()
    }

    private func look() {
        isLooking = true
        setStatus(.looking)
        checkPresence { [weak self] verdict in
            self?.handle(verdict)
        }
    }

    private func handle(_ verdict: PresenceCheck.Verdict) {
        isLooking = false
        log.info("Camera look: \(String(describing: verdict), privacy: .public)")
        // The person may have come back, or started a timer, while the camera looked.
        guard idleSecondsProvider() >= Self.inUseIdle, !timer.isTimerActive else { return }

        let recheck = now().addingTimeInterval(NightWatchPolicy.recheckInterval)
        switch verdict {
        case .asleep, .absent:
            arm(hours: NightWatchPolicy.confirmedTimerHours, reason: "camera: \(verdict)")
        case .awake:
            stretch.nextLook = recheck
        case .unclear:
            stretch.unclearLooks += 1
            stretch.nextLook = recheck
        case .unavailable:
            stretch.unclearLooks = NightWatchPolicy.maxUnclearLooks
        }
        tick()
    }

    private func arm(hours: Double, reason: String) {
        log.info("Starting a \(hours * 60, privacy: .public)-minute timer: \(reason, privacy: .public)")
        stretch.acted = true
        timer.startTimer(hours: hours) { [weak self] someoneThere in
            self?.lookInFinalPhase(someoneThere: someoneThere)
        }
        setStatus(.timerRunning)
    }

    /// The final minute of its own timer: one more look, and open eyes count as
    /// someone still watching, like a touch of the mouse.
    private func lookInFinalPhase(someoneThere: @escaping () -> Void) {
        guard !isLooking, cameraUsable else { return }
        isLooking = true
        checkPresence { [weak self] verdict in
            self?.isLooking = false
            guard verdict == .awake else { return }
            self?.log.info("Open eyes in the final minute; keeping the Mac awake")
            someoneThere()
        }
    }

    private func setStatus(_ new: NightWatchStatus) {
        if status != new { status = new }
    }

    /// Whether `date` falls inside `[bedtimeStart, bedtimeEnd)`, wrapping across
    /// midnight when the start is later than the end. Equal times make no window.
    func isWithinWindow(_ date: Date, calendar: Calendar = .current) -> Bool {
        let sinceStart = (BedtimeFormat.minutes(of: date, calendar: calendar) - bedtimeStart + 24 * 60) % (24 * 60)
        return sinceStart < bedtimeMinutes
    }

    /// "10:30 PM", for the menu bar tooltip.
    public var bedtimeStartText: String { BedtimeFormat.time(bedtimeStart) }

    /// Bedtime's length in minutes, across midnight when it wraps.
    public var bedtimeMinutes: Int {
        (bedtimeEnd - bedtimeStart + 24 * 60) % (24 * 60)
    }

    // MARK: - Persistence

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

    private func load() {
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
    }

    private func persist() {
        guard isLoaded else { return }
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(bedtimeStart, forKey: Key.bedtimeStart)
        defaults.set(bedtimeEnd, forKey: Key.bedtimeEnd)
        defaults.set(usesCamera, forKey: Key.usesCamera)
    }

    private func settingsChanged() {
        persist()
        startMonitoring()
    }
}
