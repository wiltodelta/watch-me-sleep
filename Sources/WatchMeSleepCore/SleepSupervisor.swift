import AppKit
import Combine
import Foundation
import os

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
    /// Bedtime starts and ends at the same time, so it never comes.
    case noBedtime
    /// Only sound plays and the person chose to keep it playing.
    case keepingSound
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
    /// When only sound plays (a podcast, white noise), keep it playing through
    /// the night instead of sleeping the Mac once the person is asleep. The
    /// display still turns off by itself: sound holds only the system awake.
    @Published public var keepsSoundPlaying = false { didSet { persist() } }
    /// The sound choice was put to the person once (`AppDelegate`).
    public var soundChoiceAsked: Bool {
        get { defaults.bool(forKey: Key.soundChoiceAsked) }
        set { defaults.set(newValue, forKey: Key.soundChoiceAsked) }
    }

    @Published public private(set) var status: NightWatchStatus = .off
    /// Watching outside bedtime because someone asked to, for a nap. Not
    /// persisted: it ends when the Mac or its display sleeps, when bedtime
    /// starts, or by hand.
    @Published public private(set) var isWatchingNow = false
    /// Sound with no video plays while the night watch watches, so the panel
    /// offers the sound choice right there.
    @Published public private(set) var isSoundOnlyPlaying = false

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
        /// The camera has seen a face in this stretch, so a later look that
        /// finds none means the person left or turned away to sleep. Until
        /// then the camera may just not cover them (a TV, a far laptop).
        var faceSeen = false
    }

    var stretch = Stretch()
    /// A camera look is running, for a decision or for a final minute.
    var isLooking = false
    /// When the running decision look started: input after it outdates its answer.
    private var lookStarted: Date = .distantPast
    /// What keeps the Mac awake, read once per poll while watching.
    private var holders = WakeHolders.none
    /// The running timer is the quiet Mac's, which media starting overrules.
    private var quietTimerArmed = false
    /// Input idle time at the latest poll, for the journal.
    private var lastIdle: TimeInterval = 0

    /// Input more recent than this counts as someone using the Mac.
    static let inUseIdle: TimeInterval = 30
    private let pollInterval: TimeInterval = 10
    private var pollTimer: Timer?
    private var timerObservation: AnyCancellable?
    private(set) var isLoaded = false
    private let log = Logger.app("nightwatch")

    private init() {
        load()
        isLoaded = true
        // The nap is over once the Mac or its display has gone to sleep,
        // whoever put it there.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.stopWatchingNow()
            }
        }
    }

    /// Watch now, outside bedtime: a nap.
    public func watchNow() {
        Journal.shared.record("nap", ["on": true])
        isWatchingNow = true
        refreshStatus()
    }

    public func stopWatchingNow() {
        guard isWatchingNow else { return }
        Journal.shared.record("nap", ["on": false])
        isWatchingNow = false
        refreshStatus()
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
            isWatchingNow = false
            status = .off
            return
        }
        observeTimer()
        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Nothing here needs second precision; let macOS batch the wakeups.
        timer.tolerance = 2
        pollTimer = timer
        tick()
    }

    /// A timer started or stopped by hand changes the status at once, not at
    /// the next poll. Only the status: acting here, as a full tick would, could
    /// start a look or a timer in the instant a timer ends and sleeps the Mac.
    func observeTimer() {
        timerObservation = timer.$isTimerActive.removeDuplicates().dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatus() }
    }

    private func refreshStatus() {
        let idle = idleSecondsProvider()
        lastIdle = idle
        if let gate = gate(idle: idle) {
            setStatus(gate)
        } else {
            act(idle: idle, statusOnly: true)
        }
    }

    // MARK: - Tick

    func tick() {
        let idle = idleSecondsProvider()
        lastIdle = idle
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
        let inWindow = bedtimeMinutes > 0 && isWithinWindow(now())
        if inWindow, isWatchingNow {
            Journal.shared.record("nap", ["on": false, "why": "bedtime"])
            isWatchingNow = false // Bedtime takes over the nap.
        }
        let watching = inWindow || isWatchingNow
        holders = watching ? wakeHolders() : .none
        if isSoundOnlyPlaying != holders.soundOnly { isSoundOnlyPlaying = holders.soundOnly }
        if timer.isTimerActive, !overruleQuietTimer(watching: watching) { return .timerRunning }
        if !watching { return bedtimeMinutes == 0 ? .noBedtime : .outsideHours }
        if inUse { return .inUse }
        if stretch.acted { return .done }
        if isLooking { return .looking }
        if keepsSoundPlaying, holders.soundOnly { return .keepingSound }
        return nil
    }

    /// The quiet Mac's timer assumed nothing plays; once something does, it
    /// stops and the night watch watches that instead. True when it stopped.
    private func overruleQuietTimer(watching: Bool) -> Bool {
        guard watching, quietTimerArmed, timer.stopsOnInput, holders.mediaPlaying else { return false }
        log.info("Media started during the quiet timer; watching it instead")
        Journal.shared.record("quietTimer.overruled", context([:]))
        timer.stopTimer(reason: .mediaStarted)
        stretch.acted = false
        return true
    }

    /// - Parameter statusOnly: say what the night watch sees without doing
    ///   anything about it (no look, no timer) until the next poll.
    private func act(idle: TimeInterval, statusOnly: Bool = false) {
        let input = NightWatchPolicy.Input(
            idle: idle,
            mediaPlaying: holders.mediaPlaying,
            cameraUsable: cameraUsable,
            unclearLooks: stretch.unclearLooks,
            lookDue: now() >= stretch.nextLook
        )

        let decision = NightWatchPolicy.decide(input)
        if decision == .wait || statusOnly {
            // To the minute, as shown: a status that changes every tick would
            // re-render the panel every 10 seconds for nothing.
            let next = input.cameraDecides
                ? Self.minuteUp(max(stretch.nextLook, now().addingTimeInterval(NightWatchPolicy.firstLookIdle - idle)))
                : nil
            setStatus(.watching(idleMinutes: Int(idle / 60), mediaPlaying: holders.mediaPlaying, nextLook: next))
            return
        }
        switch decision {
        case .wait:
            break
        case .look:
            look()
        case .armQuietTimer:
            arm(for: NightWatchPolicy.quietTimer, reason: "nobody watching", quiet: true)
        case .askStillWatching:
            arm(for: TimerManager.finalPhaseDuration, reason: "still watching?")
        }
    }

    private static func minuteUp(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
    }

    /// The camera will really look: chosen, and access given.
    var cameraUsable: Bool {
        usesCamera && cameraAuthorized()
    }

    private func look() {
        isLooking = true
        lookStarted = now()
        setStatus(.looking)
        checkPresence { [weak self] verdict in
            self?.handle(verdict)
        }
    }

    private func handle(_ verdict: PresenceCheck.Verdict) {
        isLooking = false
        log.info("Camera look: \(String(describing: verdict), privacy: .public)")
        // Any input since the look began outdates its answer, as does a timer
        // started meanwhile.
        let sinceLook = now().timeIntervalSince(lookStarted)
        guard idleSecondsProvider() >= max(Self.inUseIdle, sinceLook), !timer.isTimerActive else {
            Journal.shared.record("look.ignored", context([
                "verdict": String(describing: verdict), "timerRunning": timer.isTimerActive
            ]))
            return
        }

        // Only eyes read open or closed prove a face: unclear also covers a
        // look that saw nothing but darkness.
        if verdict == .asleep || verdict == .awake {
            stretch.faceSeen = true
        }
        // Never seen in this stretch: the camera may not cover the viewer.
        let verdict = verdict == .absent && !stretch.faceSeen ? .unclear : verdict
        Journal.shared.record("look.result", context(["verdict": String(describing: verdict)]))
        let recheck = recheckDate
        switch verdict {
        case .asleep, .absent:
            arm(for: NightWatchPolicy.cameraTimer, reason: "camera: \(verdict)", looksAgain: true)
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

    /// When to look again after open eyes or an unclear picture.
    private var recheckDate: Date {
        now().addingTimeInterval(NightWatchPolicy.recheckInterval)
    }

    /// - Parameter looksAgain: the camera started this timer, so it looks once
    ///   more in the final minute. Not for a quiet Mac, which never turns the
    ///   camera on, and not for "still watching?", which asks because open eyes
    ///   cannot be trusted that late.
    /// - Parameter quiet: the quiet Mac's timer, which media starting overrules.
    private func arm(for duration: TimeInterval, reason: String, looksAgain: Bool = false, quiet: Bool = false) {
        log.info("Starting a \(duration / 60, privacy: .public)-minute timer: \(reason, privacy: .public)")
        Journal.shared.record("arm", context(["minutes": duration / 60, "reason": reason, "looksAgain": looksAgain]))
        stretch.acted = true
        quietTimerArmed = quiet
        let check: TimerManager.FinalPhaseCheck? = looksAgain
            ? { [weak self] someoneThere in self?.lookInFinalPhase(someoneThere: someoneThere) }
            : nil
        timer.startTimer(hours: duration / 3600, stopsOnInput: true, finalPhaseCheck: check)
        setStatus(.timerRunning)
    }

    /// The final minute of its own timer: one more look, and open eyes count as
    /// someone still watching, like a touch of the mouse.
    private func lookInFinalPhase(someoneThere: @escaping () -> Void) {
        guard !isLooking, cameraUsable else {
            return Journal.shared.record("look.skipped", context(["kind": "final minute", "looking": isLooking]))
        }
        isLooking = true
        Journal.shared.record("look", context(["kind": "final minute"]))
        checkPresence { [weak self] verdict in
            guard let self else { return }
            self.isLooking = false
            let fields: [String: Any] = ["kind": "final minute", "verdict": String(describing: verdict)]
            Journal.shared.record("look.result", self.context(fields))
            guard verdict == .awake else { return }
            self.log.info("Open eyes in the final minute; stopping the timer")
            let wasRunning = self.timer.isTimerActive
            someoneThere()
            guard wasRunning, !self.timer.isTimerActive else { return }
            // Still watching: back to looking every so often, as after any open eyes.
            self.stretch.acted = false
            self.stretch.nextLook = self.recheckDate
        }
    }

    private func setStatus(_ new: NightWatchStatus) {
        guard status != new else { return }
        status = new
        Journal.shared.record("status", context(["status": String(describing: new)]))
    }

    /// What the night watch saw at the latest poll, around a journal entry.
    private func context(_ fields: [String: Any]) -> [String: Any] {
        fields.merging([
            "idle": Int(lastIdle),
            "media": holders.mediaPlaying, "video": holders.videoPlaying, "work": holders.work,
            "nap": isWatchingNow, "cameraUsable": cameraUsable, "faceSeen": stretch.faceSeen,
            "unclearLooks": stretch.unclearLooks, "acted": stretch.acted
        ]) { own, _ in own }
    }

    /// Whether `date` falls inside `[bedtimeStart, bedtimeEnd)`, wrapping across
    /// midnight when the start is later than the end. Equal times make no window.
    func isWithinWindow(_ date: Date, calendar: Calendar = .current) -> Bool {
        let sinceStart = (BedtimeFormat.minutes(of: date, calendar: calendar) - bedtimeStart + 24 * 60) % (24 * 60)
        return sinceStart < bedtimeMinutes
    }

    /// "10:30 PM", for the status texts.
    public var bedtimeStartText: String { BedtimeFormat.time(bedtimeStart) }

    /// "10:30 PM – 6:00 AM", for the panel.
    var bedtimeRangeText: String { "\(bedtimeStartText) – \(BedtimeFormat.time(bedtimeEnd))" }

    /// The status in one line: the panel's status title and the menu bar
    /// tooltip read the same words (UX-10).
    public var statusTitle: String {
        switch status {
        case .off: return "Night watch is off"
        case .outsideHours: return "Night watch starts at \(bedtimeStartText)"
        case .inUse: return "Night watch is on"
        case .timerRunning: return "Sleep timer running"
        case .watching(_, let mediaPlaying, _): return mediaPlaying ? "Something is playing" : "Your Mac is quiet"
        case .looking: return "Looking with the camera"
        case .done: return "Display off, work still running"
        case .noBedtime: return "Bedtime has no length"
        case .keepingSound: return "Sound keeps playing"
        }
    }

    /// Bedtime's length in minutes, across midnight when it wraps.
    public var bedtimeMinutes: Int {
        (bedtimeEnd - bedtimeStart + 24 * 60) % (24 * 60)
    }
}
