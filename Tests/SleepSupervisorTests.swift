import XCTest
@testable import WatchMeSleepCore

final class NightWatchPolicyTests: XCTestCase {
    private let now = Date()
    private typealias Policy = NightWatchPolicy

    private func decide(
        idleMinutes: Double, media: Bool = true, camera: Bool = true,
        unclear: Int = 0, nextLook: Date = .distantPast
    ) -> Policy.Decision {
        Policy.decide(Policy.Input(idle: idleMinutes * 60, mediaPlaying: media, cameraUsable: camera,
                                   unclearLooks: unclear, lookDue: now >= nextLook))
    }

    func testCameraLooksAfterTenMinutesOfMedia() {
        XCTAssertEqual(decide(idleMinutes: 9), .wait)
        XCTAssertEqual(decide(idleMinutes: 10), .look)
    }

    func testAQuietMacNeverUsesTheCamera() {
        XCTAssertEqual(decide(idleMinutes: 10, media: false), .wait, "Nothing playing: nothing to ask the camera")
        XCTAssertEqual(decide(idleMinutes: 20, media: false), .armConfirmed)
    }

    func testCameraWaitsForTheNextLook() {
        XCTAssertEqual(decide(idleMinutes: 30, nextLook: now.addingTimeInterval(60)), .wait)
    }

    func testWithoutCameraAQuietMacArmsAfterTwentyMinutes() {
        XCTAssertEqual(decide(idleMinutes: 19, media: false, camera: false), .wait)
        XCTAssertEqual(decide(idleMinutes: 20, media: false, camera: false), .armConfirmed)
    }

    func testWithoutCameraMediaAsksAfterNinetyMinutes() {
        XCTAssertEqual(decide(idleMinutes: 89, camera: false), .wait)
        XCTAssertEqual(decide(idleMinutes: 90, camera: false), .askStillWatching)
    }

    func testUnclearLooksFallBackToTheNoCameraRules() {
        XCTAssertEqual(decide(idleMinutes: 30, unclear: 2), .wait)
        XCTAssertEqual(decide(idleMinutes: 90, unclear: 2), .askStillWatching)
        XCTAssertEqual(decide(idleMinutes: 30, unclear: 1), .look)
    }

    func testAfterThreeHoursItAsksAnyway() {
        XCTAssertEqual(decide(idleMinutes: 180, nextLook: .distantFuture), .askStillWatching,
                       "Open eyes cannot hold the Mac up all night")
    }
}

final class SleepSupervisorTests: XCTestCase {
    private var supervisor: SleepSupervisor!
    private var timer: TimerManager!
    private var clock = Date()
    private var idle: TimeInterval = 0
    private var holders = WakeHolders.none
    private var cameraAuthorized = true
    private var looks = 0
    private var pendingLook: ((PresenceCheck.Verdict) -> Void)?
    private var slept = false

    override func setUp() {
        super.setUp()
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour) = (2026, 1, 1, 23)
        clock = Calendar.current.date(from: components)!
        idle = 0
        holders = WakeHolders(mediaPlaying: true, work: [])
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
    }

    override func tearDown() {
        timer.stopTimer()
        timer.now = Date.init
        supervisor.now = Date.init
        supervisor.isEnabled = false
        supervisor.defaults.removePersistentDomain(forName: "SleepSupervisorTests")
        supervisor.defaults = .standard
        super.tearDown()
    }

    private func answer(_ verdict: PresenceCheck.Verdict) {
        let look = pendingLook
        pendingLook = nil
        look?(verdict)
    }

    private func idleFor(minutes: Double) {
        idle = minutes * 60
        supervisor.tick()
    }

    private func at(_ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 1, 1)
        (components.hour, components.minute) = (hour, minute)
        return Calendar.current.date(from: components)!
    }

    func testBedtimeIsMinutePrecise() {
        supervisor.bedtimeStart = 22 * 60 + 30
        supervisor.bedtimeEnd = 6 * 60 + 45
        XCTAssertFalse(supervisor.isWithinWindow(at(22, 29)))
        XCTAssertTrue(supervisor.isWithinWindow(at(22, 30)))
        XCTAssertTrue(supervisor.isWithinWindow(at(0, 0)), "Across midnight")
        XCTAssertTrue(supervisor.isWithinWindow(at(6, 44)))
        XCTAssertFalse(supervisor.isWithinWindow(at(6, 45)), "The end is exclusive")
        XCTAssertEqual(supervisor.bedtimeMinutes, 8 * 60 + 15)
    }

    func testADaytimeBedtimeWorksToo() {
        supervisor.bedtimeStart = 9 * 60
        supervisor.bedtimeEnd = 17 * 60
        XCTAssertTrue(supervisor.isWithinWindow(at(12, 0)), "Night shift sleepers")
        XCTAssertFalse(supervisor.isWithinWindow(at(23, 0)))
    }

    func testEqualTimesSayThereIsNoBedtime() {
        supervisor.bedtimeStart = 22 * 60
        supervisor.bedtimeEnd = 22 * 60
        idleFor(minutes: 5)
        XCTAssertEqual(supervisor.status, .noBedtime, "Not \"starts at 10 PM\": it never starts")
        XCTAssertEqual(supervisor.statusTitle, "Bedtime has no length")
    }

    func testATimerStartedOrStoppedUpdatesTheStatusWithoutActing() {
        supervisor.observeTimer()
        idle = 15 * 60 // In bedtime and idle long enough for a look, were it a tick.

        timer.startTimer(hours: 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(supervisor.status, .timerRunning)

        timer.stopTimer()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNotEqual(supervisor.status, .timerRunning)
        XCTAssertEqual(looks, 0, "Only the status: no look in the instant a timer ends")
    }

    func testTheTooltipTitleFollowsTheStatus() {
        supervisor.isEnabled = false
        idleFor(minutes: 1)
        XCTAssertEqual(supervisor.statusTitle, "Night watch is off")
        supervisor.isEnabled = true
        timer.startTimer(hours: 1)
        idleFor(minutes: 1)
        XCTAssertEqual(supervisor.statusTitle, "Sleep timer running")
    }

    func testEqualTimesMakeNoBedtime() {
        supervisor.bedtimeStart = 22 * 60
        supervisor.bedtimeEnd = 22 * 60
        XCTAssertFalse(supervisor.isWithinWindow(at(22, 0)))
        XCTAssertFalse(supervisor.isWithinWindow(at(3, 0)))
        XCTAssertEqual(supervisor.bedtimeMinutes, 0)
    }

    func testWholeHoursFromBeforeCarryOver() {
        let defaults = UserDefaults(suiteName: "BedtimeMigrationTests")!
        defer { defaults.removePersistentDomain(forName: "BedtimeMigrationTests") }
        let key = SleepSupervisor.Key.bedtimeStart, legacy = SleepSupervisor.Key.legacyStartHour

        XCTAssertNil(SleepSupervisor.storedMinutes(defaults, key: key, legacyHourKey: legacy))
        defaults.set(22, forKey: legacy)
        XCTAssertEqual(SleepSupervisor.storedMinutes(defaults, key: key, legacyHourKey: legacy), 22 * 60)
        defaults.set(22 * 60 + 30, forKey: key)
        XCTAssertEqual(SleepSupervisor.storedMinutes(defaults, key: key, legacyHourKey: legacy), 22 * 60 + 30,
                       "Minutes, once stored, win over the old hour")
    }

    func testInUseDoesNothing() {
        idleFor(minutes: 0.1)
        XCTAssertEqual(supervisor.status, .inUse)
        XCTAssertEqual(looks, 0)
    }

    func testOutsideBedtimeSaysSoEvenWhileInUse() {
        clock = clock.addingTimeInterval(-3 * 3600) // 20:00
        idleFor(minutes: 0.1)
        XCTAssertEqual(supervisor.status, .outsideHours)
    }

    func testOutsideBedtimeDoesNothing() {
        clock = clock.addingTimeInterval(-10 * 3600) // 13:00
        idleFor(minutes: 120)
        XCTAssertEqual(supervisor.status, .outsideHours)
        XCTAssertFalse(timer.isTimerActive)
    }

    func testClosedEyesStartAFifteenMinuteTimer() {
        idleFor(minutes: 10)
        XCTAssertEqual(looks, 1)

        answer(.asleep)

        XCTAssertTrue(timer.isTimerActive)
        XCTAssertEqual(timer.totalTime, 15 * 60, accuracy: 1)
    }

    func testNobodyThereStartsAFifteenMinuteTimer() {
        idleFor(minutes: 10)
        answer(.absent)
        XCTAssertEqual(timer.totalTime, 15 * 60, accuracy: 1)
    }

    func testOpenEyesWaitTenMinutes() {
        idleFor(minutes: 10)
        answer(.awake)
        XCTAssertFalse(timer.isTimerActive)

        clock = clock.addingTimeInterval(9 * 60)
        idleFor(minutes: 19)
        XCTAssertEqual(looks, 1)

        clock = clock.addingTimeInterval(60)
        idleFor(minutes: 20)
        XCTAssertEqual(looks, 2)
    }

    func testANoLongerUsableCameraFallsBackToStillWatching() {
        idleFor(minutes: 10)
        answer(.unavailable)

        idleFor(minutes: 89)
        XCTAssertFalse(timer.isTimerActive)
        idleFor(minutes: 90)
        XCTAssertEqual(timer.totalTime, TimerManager.finalPhaseDuration, accuracy: 1, "Straight to the final minute")
    }

    func testPersonBackDuringTheLookStartsNothing() {
        idleFor(minutes: 10)
        idle = 2
        answer(.asleep)
        XCTAssertFalse(timer.isTimerActive)
    }

    func testOneActionPerIdleStretch() {
        idleFor(minutes: 10)
        answer(.asleep)
        // The display went off for work; the timer is gone but nobody came back.
        timer.stopTimer()

        idleFor(minutes: 40)
        XCTAssertEqual(supervisor.status, .done)
        XCTAssertFalse(timer.isTimerActive)

        idleFor(minutes: 0)
        idleFor(minutes: 10)
        XCTAssertEqual(looks, 2, "Back at the Mac starts a new stretch")
    }

    func testOpenEyesInTheFinalMinuteKeepTheMacAwake() {
        idleFor(minutes: 10)
        answer(.asleep)
        clock = clock.addingTimeInterval(15 * 60 - 30)
        timer.tick()
        XCTAssertTrue(timer.isInFinalPhase)

        XCTAssertEqual(looks, 2, "Entering the final minute asks at once, not at the next poll")
        answer(.awake)

        clock = clock.addingTimeInterval(30)
        timer.tick()
        XCTAssertFalse(slept, "Someone watching is not put to sleep")
        XCTAssertTrue(timer.isTimerActive)
    }

    func testAManualTimerGetsNoFinalMinuteLook() {
        timer.startTimer(hours: 1)
        clock = clock.addingTimeInterval(3600 - 30)
        timer.tick()

        idleFor(minutes: 60)

        XCTAssertEqual(looks, 0)
    }
}
