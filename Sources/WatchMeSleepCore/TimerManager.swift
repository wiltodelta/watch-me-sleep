import Foundation
import os
import AppKit

public class TimerManager: ObservableObject {
    public static let shared = TimerManager()

    /// How long before the timer runs out the warning shows and the volume fades.
    public static let finalPhaseDuration: TimeInterval = 60
    /// The lengths offered for one click, in hours: the panel's buttons and
    /// the status item's menu list the same ones (UX-11).
    public static let presetHours: [Double] = [0.25, 0.5, 1, 1.5, 2, 3, 4, 6]
    /// How far the timer moves when someone is still using the Mac at zero.
    public static let postponeMinutes = 15
    /// A deadline missed by this much passed while nothing ticked: the Mac was
    /// asleep. Well above the few seconds App Nap may delay a tick.
    static let overdueAfter: TimeInterval = 2 * 60

    @Published public var isTimerActive: Bool = false
    @Published public var remainingTime: TimeInterval = 0
    @Published public var totalTime: TimeInterval = 0
    /// The last `finalPhaseDuration` seconds: the warning is up and the volume fades.
    public var isInFinalPhase: Bool { finalPhaseStart != nil }
    /// Someone used the Mac during the final phase, so the timer will be postponed
    /// at zero instead of sleeping the Mac.
    @Published public private(set) var isUserActive: Bool = false
    /// Work holds the Mac awake, so zero will only turn the display off (UX-04):
    /// what the panel and the warning promise follows this, not "sleep".
    @Published public private(set) var endsWithDisplayOff: Bool = false

    private var timer: Timer?
    private var targetDate: Date?
    private var finalPhaseStart: Date?
    private var finalPhaseCheck: FinalPhaseCheck?
    /// Bumped per timer, so a late answer to an earlier final phase check
    /// cannot mark a later timer.
    private var generation = 0

    /// Asked once per final minute by whoever started the timer; it calls back
    /// when it finds someone still there (the night watch's camera look).
    public typealias FinalPhaseCheck = (_ someoneThere: @escaping () -> Void) -> Void

    public enum SleepKind {
        /// The timer ran out: sleep, or only turn the display off while work
        /// holds the Mac awake.
        case unlessWorkHolds
        /// Someone pressed Sleep Now: they are awake and chose it.
        case always
    }

    // Seam for tests: performs the sleep. Defaults to putting the computer to
    // sleep; tests override it so the suite never sleeps the machine.
    var sleepHandler: (SleepKind) -> Void = { _ in }

    // Seam for tests: the current-time provider. Production uses the wall clock;
    // tests inject a controllable clock so they can advance time synchronously
    // instead of waiting on a real `Timer` (which is flaky under CI load).
    var now: () -> Date = Date.init

    // Seam for tests: seconds since the last keyboard or mouse input.
    var idleSecondsProvider: () -> TimeInterval = { SystemSignals.idleSeconds() }

    // Seam for tests: processes holding the Mac awake with work.
    var workHolders: () -> [String] = { SystemSignals.wakeHolders().work }
    private var lastWorkCheck: Date = .distantPast
    /// Work starts and stops slowly; the promise need not track it by the second.
    private static let workCheckInterval: TimeInterval = 15

    // Seam for tests: the output volume the final phase fades.
    var volume: VolumeControl = SystemVolumeFader()

    private init() {
        sleepHandler = { [weak self] kind in self?.putComputerToSleep(kind) }
        // The display waking counts too: with work holding the Mac, only the
        // display went off and the system never slept.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let center = NSWorkspace.shared.notificationCenter
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.handleWake()
            }
        }
    }

    public func startTimer(hours: Double, finalPhaseCheck: FinalPhaseCheck? = nil) {
        stopTimer()
        generation += 1
        refreshEndAction(force: true)
        self.finalPhaseCheck = finalPhaseCheck

        totalTime = hours * 3600
        remainingTime = totalTime
        targetDate = now().addingTimeInterval(totalTime)
        isTimerActive = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }

        notifyTimerUpdated()
    }

    public func stopTimer() {
        deactivate()
        volume.restore()
    }

    /// Clears the timer state but keeps the volume faded, for the paths that
    /// sleep the Mac: the volume comes back on wake, not just before sleep.
    private func deactivate() {
        timer?.invalidate()
        timer = nil
        isTimerActive = false
        remainingTime = 0
        totalTime = 0
        targetDate = nil
        finalPhaseCheck = nil
        endFinalPhase()
        notifyTimerUpdated()
    }

    /// Someone is still there during the final minute (input, or the final
    /// phase check): the volume comes back and zero postpones instead of sleeping.
    func markUserActive() {
        guard isInFinalPhase, !isUserActive else { return }
        isUserActive = true
        volume.restore()
        notifyTimerUpdated()
    }

    /// Sleep left the volume faded; bring it back. A timer that ran out during
    /// the sleep is stopped by its next tick (`updateTimer`), whichever of the two
    /// runs first after wake.
    func handleWake() {
        volume.restore()
    }

    // Seam for tests: run one timer update cycle synchronously, as the scheduled
    // `Timer` would. Lets tests drive completion by advancing the injected clock
    // and calling this directly, without waiting on wall-clock time.
    func tick() {
        updateTimer()
    }

    private func updateTimer() {
        guard let targetDate = targetDate else {
            stopTimer()
            return
        }

        remainingTime = targetDate.timeIntervalSince(now())
        refreshEndAction(force: false)

        if remainingTime < -Self.overdueAfter {
            // Ran out while the Mac slept (lid closed, Apple menu): its job is
            // done, and sleeping now would put a just-woken Mac straight back.
            Logger.app("timer").info("Timer ran out during sleep; stopping it")
            stopTimer()
            return
        }

        if remainingTime <= 0 {
            finish()
            return
        }

        if remainingTime <= Self.finalPhaseDuration {
            updateFinalPhase()
        } else if finalPhaseStart != nil {
            // Time was added during the warning.
            endFinalPhase()
            volume.restore()
        }

        notifyTimerUpdated()
    }

    private func refreshEndAction(force: Bool) {
        guard force || now().timeIntervalSince(lastWorkCheck) >= Self.workCheckInterval else { return }
        lastWorkCheck = now()
        let displayOnly = !workHolders().isEmpty
        if endsWithDisplayOff != displayOnly { endsWithDisplayOff = displayOnly }
    }

    private func updateFinalPhase() {
        if finalPhaseStart == nil {
            finalPhaseStart = now()
            let asked = generation
            finalPhaseCheck? { [weak self] in
                guard let self, self.generation == asked else { return }
                self.markUserActive()
            }
        }

        if userWasActive(since: finalPhaseStart) {
            markUserActive()
        } else if !isUserActive {
            volume.fade(to: remainingTime / Self.finalPhaseDuration)
        }
    }

    private func endFinalPhase() {
        finalPhaseStart = nil
        isUserActive = false
    }

    /// Any keyboard or mouse input after `start`. A timer that skipped its final
    /// phase (a tick missed across it) looks back one phase length instead.
    private func userWasActive(since start: Date?) -> Bool {
        let window = start.map { now().timeIntervalSince($0) } ?? Self.finalPhaseDuration
        return idleSecondsProvider() < window
    }

    /// Zero: sleep, unless someone used the Mac during the warning. Sleeping a
    /// Mac in active use is never what the timer was set for, so it moves on by
    /// `postponeMinutes` instead.
    private func finish() {
        if isUserActive || userWasActive(since: finalPhaseStart) {
            Logger.app("timer").info("Mac in use at zero; postponing \(Self.postponeMinutes) minutes")
            extend(minutes: Self.postponeMinutes, from: now())
            return
        }
        deactivate()
        sleepHandler(.unlessWorkHolds)
    }

    /// Sleeps the Mac. At the end of a timer, while work holds the Mac awake
    /// (`caffeinate`, a download, a build), only the display goes off: sleeping
    /// would cut that work off, and the Mac sleeps by itself once it lets go.
    private func putComputerToSleep(_ kind: SleepKind) {
        // The same reading `endsWithDisplayOff` promised from.
        let work = kind == .unlessWorkHolds ? workHolders() : []
        let command = work.isEmpty ? "sleepnow" : "displaysleepnow"
        if !work.isEmpty {
            let holders = work.joined(separator: ", ")
            Logger.app("timer").info("Work holds the Mac awake (\(holders, privacy: .public)); display off only")
        }

        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = [command]

        do {
            try task.run()
        } catch {
            Logger.app("timer").error("Failed to put the Mac to sleep: \(error.localizedDescription, privacy: .public)")

            // Show alert to user
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()

                let alert = NSAlert()
                // What happened, why, and what to do now (UX-13).
                alert.messageText = "Couldn’t put your Mac to sleep"
                alert.informativeText = "\(error.localizedDescription)\n\nChoose Apple menu > Sleep instead."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()

                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func notifyTimerUpdated() {
        NotificationCenter.default.post(name: .timerUpdated, object: nil)
    }

    public func addTime(minutes: Int) {
        guard isTimerActive, let currentTarget = targetDate else { return }
        extend(minutes: minutes, from: currentTarget)
    }

    /// Moves the deadline to `minutes` after `base`: the current deadline when
    /// time is added, now when a timer that ran out is postponed.
    private func extend(minutes: Int, from base: Date) {
        let extra = TimeInterval(minutes * 60)
        targetDate = base.addingTimeInterval(extra)
        totalTime += extra
        updateTimer()
    }

    /// Sleeps the Mac now, as asked, and drops any running timer, so it cannot
    /// fire again the moment the Mac wakes.
    public func sleepNow() {
        deactivate()
        sleepHandler(.always)
    }
}
