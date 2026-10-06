import Foundation
import os
import AppKit

public class TimerManager: ObservableObject {
    public static let shared = TimerManager()

    /// How long before the timer runs out the warning shows and the volume fades.
    public static let finalPhaseDuration: TimeInterval = 60
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

    private var timer: Timer?
    private var targetDate: Date?
    private var finalPhaseStart: Date?

    // Seam for tests: invoked when the timer reaches zero. Defaults to putting
    // the computer to sleep; tests override it so the suite never sleeps the machine.
    var sleepHandler: () -> Void = {}

    // Seam for tests: the current-time provider. Production uses the wall clock;
    // tests inject a controllable clock so they can advance time synchronously
    // instead of waiting on a real `Timer` (which is flaky under CI load).
    var now: () -> Date = Date.init

    // Seam for tests: seconds since the last keyboard or mouse input.
    var idleSecondsProvider: () -> TimeInterval = { AutoActivationManager.systemIdleSeconds() }

    // Seam for tests: the output volume the final phase fades.
    var volume: VolumeControl = SystemVolumeFader()

    private init() {
        sleepHandler = { [weak self] in self?.putComputerToSleep() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
    }

    public func startTimer(hours: Double) {
        stopTimer()

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
        endFinalPhase()
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

    private func updateFinalPhase() {
        if finalPhaseStart == nil {
            finalPhaseStart = now()
        }

        if userWasActive(since: finalPhaseStart) {
            if !isUserActive {
                isUserActive = true
                volume.restore()
            }
        } else {
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
        if userWasActive(since: finalPhaseStart) {
            Logger.app("timer").info("Mac in use at zero; postponing \(Self.postponeMinutes) minutes")
            extend(minutes: Self.postponeMinutes, from: now())
            return
        }
        sleepNow()
    }

    private func putComputerToSleep() {
        // Disable camera mode before sleep (switch back to manual mode)
        SleepDetectionManager.shared.setCameraModeEnabled(false)

        // Notify UI to switch back to manual mode
        NotificationCenter.default.post(name: .cameraModeDisabled, object: nil)

        // Use pmset command (most reliable method)
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["sleepnow"]

        do {
            try task.run()
        } catch {
            Logger.app("timer").error("Failed to put the Mac to sleep: \(error.localizedDescription, privacy: .public)")

            // Show alert to user
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()

                let alert = NSAlert()
                alert.messageText = "Sleep failed"
                alert.informativeText = "Unable to put the computer to sleep.\n\nError: \(error.localizedDescription)"
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

    /// Sleeps the Mac now and drops any running timer, so it cannot fire again
    /// the moment the Mac wakes.
    public func sleepNow() {
        deactivate()
        sleepHandler()
    }
}
