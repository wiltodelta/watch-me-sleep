import Foundation
import AppKit

public class TimerManager: ObservableObject {
    public static let shared = TimerManager()

    @Published public var isTimerActive: Bool = false
    @Published public var remainingTime: TimeInterval = 0
    @Published public var totalTime: TimeInterval = 0

    private var timer: Timer?
    private var targetDate: Date?

    // Seam for tests: invoked when the timer reaches zero. Defaults to putting
    // the computer to sleep; tests override it so the suite never sleeps the machine.
    var sleepHandler: () -> Void = {}

    // Seam for tests: the current-time provider. Production uses the wall clock;
    // tests inject a controllable clock so they can advance time synchronously
    // instead of waiting on a real `Timer` (which is flaky under CI load).
    var now: () -> Date = Date.init

    private init() {
        sleepHandler = { [weak self] in self?.putComputerToSleep() }
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
        timer?.invalidate()
        timer = nil
        isTimerActive = false
        remainingTime = 0
        totalTime = 0
        targetDate = nil
        notifyTimerUpdated()
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

        if remainingTime <= 0 {
            stopTimer()
            sleepHandler()
            return
        }

        notifyTimerUpdated()
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
            NSLog("Failed to put computer to sleep: \(error.localizedDescription)")

            // Show alert to user
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                alert.messageText = "Sleep Failed"
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

        let newTarget = currentTarget.addingTimeInterval(TimeInterval(minutes * 60))
        targetDate = newTarget
        totalTime += TimeInterval(minutes * 60)
        updateTimer()
    }

    public func sleepNow() {
        putComputerToSleep()
    }
}
