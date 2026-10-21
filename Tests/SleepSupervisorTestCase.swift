import XCTest
import AppKit
@testable import WatchMeSleepCore

@MainActor
class SleepSupervisorTestCase: XCTestCase {
    static let film = WakeHolders(mediaPlaying: true, work: [], videoPlaying: true)
    static let sound = WakeHolders(mediaPlaying: true, work: [], videoPlaying: false)
    var supervisor: SleepSupervisor!
    var timer: TimerManager!
    var clock = Date()
    var idle: TimeInterval = 0
    var holders = WakeHolders.none
    var cameraAuthorized = true
    var looks = 0
    var pendingLook: (@MainActor (PresenceCheck.Verdict) -> Void)?
    var slept = false
    var cancellations = 0

    override func setUp() async throws {
        try await super.setUp()
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour) = (2026, 1, 1, 23)
        clock = Calendar.current.date(from: components)!
        idle = 0
        holders = Self.film
        cameraAuthorized = true
        looks = 0
        pendingLook = nil
        slept = false

        timer = TimerManager.shared
        timer.stopTimer()
        timer.now = { [unowned self] in self.clock }
        timer.idleSecondsProvider = { [unowned self] in self.idle }
        timer.volume = FakeVolume()
        timer.sleepHandler = { [unowned self] _ in self.slept = true }
        timer.workHolders = { [] }

        supervisor = SleepSupervisor.shared
        supervisor.cancelPresence = { [unowned self] in self.cancellations += 1 }
        supervisor.defaults = UserDefaults(suiteName: "SleepSupervisorTests")!
        supervisor.isEnabled = true
        supervisor.bedtimeStart = 21 * 60
        supervisor.bedtimeEnd = 8 * 60
        supervisor.usesCamera = true
        supervisor.now = { [unowned self] in self.clock }
        supervisor.idleSecondsProvider = { [unowned self] in self.idle }
        supervisor.wakeHolders = { [unowned self] in self.holders }
        supervisor.cameraAuthorized = { [unowned self] in self.cameraAuthorized }
        supervisor.checkPresence = { [unowned self] completion in
            self.looks += 1
            self.pendingLook = completion
        }
        supervisor.timer = timer
        supervisor.stretch = .init()
        supervisor.isLooking = false
        supervisor.stopWatchingNow()
        supervisor.keepsSoundPlaying = false
        cancellations = 0
    }

    override func tearDown() async throws {
        timer.stopTimer()
        timer.now = Date.init
        supervisor.now = Date.init
        supervisor.isEnabled = false
        supervisor.defaults.removePersistentDomain(forName: "SleepSupervisorTests")
        supervisor.defaults = .standard
        try await super.tearDown()
    }

    func answer(_ verdict: PresenceCheck.Verdict) {
        let look = pendingLook
        pendingLook = nil
        look?(verdict)
    }

    func idleFor(minutes: Double) {
        idle = minutes * 60
        supervisor.tick()
    }

    func at(_ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 1, 1)
        (components.hour, components.minute) = (hour, minute)
        return Calendar.current.date(from: components)!
    }

}
