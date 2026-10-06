import XCTest
@testable import WatchMeSleepCore

final class AutoActivationManagerTests: XCTestCase {
    var manager: AutoActivationManager!

    override func setUp() {
        super.setUp()
        manager = AutoActivationManager.shared
        // Use a throwaway store so tests never touch the real app preferences.
        manager.defaults = UserDefaults(suiteName: "AutoActivationTests")!
        manager.isEnabled = true
        manager.activeAfterHour = 22
        manager.windowEndHour = 8
        manager.idleMinutes = 20
        manager.timerHours = 1.0
        manager.isTimerActive = { false }
        manager.isCameraModeEnabled = { false }
        manager.checksWithCamera = true
        manager.isChecking = false
        manager.nextCheck = .distantPast
        startedHours = []
        checks = 0
        pendingCheck = nil
    }

    override func tearDown() {
        manager.isEnabled = false
        manager.defaults.removePersistentDomain(forName: "AutoActivationTests")
        manager.defaults = .standard
        manager.now = Date.init
        super.tearDown()
    }

    private func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = hour
        components.minute = 30
        return Calendar.current.date(from: components)!
    }

    // MARK: - Window

    func testWindowIncludesEvening() {
        XCTAssertTrue(manager.isWithinWindow(date(hour: 22)))
        XCTAssertTrue(manager.isWithinWindow(date(hour: 23)))
    }

    func testWindowIncludesOvernight() {
        XCTAssertTrue(manager.isWithinWindow(date(hour: 0)))
        XCTAssertTrue(manager.isWithinWindow(date(hour: 7)))
    }

    func testWindowExcludesDaytime() {
        XCTAssertFalse(manager.isWithinWindow(date(hour: 8)))
        XCTAssertFalse(manager.isWithinWindow(date(hour: 12)))
        XCTAssertFalse(manager.isWithinWindow(date(hour: 21)))
    }

    // MARK: - shouldActivate

    func testActivatesWhenIdleInsideWindow() {
        XCTAssertTrue(manager.shouldActivate(now: date(hour: 23), idleSeconds: 20 * 60))
        XCTAssertTrue(manager.shouldActivate(now: date(hour: 23), idleSeconds: 60 * 60))
    }

    func testDoesNotActivateBelowIdleThreshold() {
        XCTAssertFalse(manager.shouldActivate(now: date(hour: 23), idleSeconds: 19 * 60))
    }

    func testDoesNotActivateOutsideWindow() {
        XCTAssertFalse(manager.shouldActivate(now: date(hour: 12), idleSeconds: 60 * 60))
    }

    func testDoesNotActivateWhenDisabled() {
        manager.isEnabled = false
        XCTAssertFalse(manager.shouldActivate(now: date(hour: 23), idleSeconds: 60 * 60))
    }

    func testDoesNotActivateWhenTimerAlreadyRunning() {
        manager.isTimerActive = { true }
        XCTAssertFalse(manager.shouldActivate(now: date(hour: 23), idleSeconds: 60 * 60))
    }

    func testDoesNotActivateInCameraMode() {
        manager.isCameraModeEnabled = { true }
        XCTAssertFalse(manager.shouldActivate(now: date(hour: 23), idleSeconds: 60 * 60))
    }

    // MARK: - tick

    private var startedHours: [Double] = []
    private var checks = 0
    private var pendingCheck: ((PresenceCheck.Verdict) -> Void)?
    private var clock = Date()

    /// Late at night, idle well past the threshold, with fakes for every effect.
    private func armForTick() {
        clock = date(hour: 23)
        manager.now = { [unowned self] in self.clock }
        manager.idleSecondsProvider = { 60 * 60 }
        manager.startTimer = { [unowned self] in self.startedHours.append($0) }
        manager.checkPresence = { [unowned self] completion in
            self.checks += 1
            self.pendingCheck = completion
        }
    }

    private func answer(_ verdict: PresenceCheck.Verdict) {
        let completion = pendingCheck
        pendingCheck = nil
        completion?(verdict)
    }

    func testTickWithoutCameraStartsTheConfiguredTimer() {
        armForTick()
        manager.checksWithCamera = false

        manager.tick()

        XCTAssertEqual(startedHours, [1.0])
        XCTAssertEqual(checks, 0)
    }

    func testTickLooksBeforeStarting() {
        armForTick()

        manager.tick()

        XCTAssertEqual(checks, 1)
        XCTAssertTrue(startedHours.isEmpty, "Nothing starts before the camera answers")
    }

    func testClosedEyesStartAShortTimer() {
        armForTick()
        manager.tick()

        answer(.asleep)

        XCTAssertEqual(startedHours, [AutoActivationManager.confirmedTimerHours])
    }

    func testNobodyThereStartsAShortTimer() {
        armForTick()
        manager.tick()

        answer(.absent)

        XCTAssertEqual(startedHours, [AutoActivationManager.confirmedTimerHours])
    }

    func testNoCameraFallsBackToTheConfiguredTimer() {
        armForTick()
        manager.tick()

        answer(.unavailable)

        XCTAssertEqual(startedHours, [1.0])
    }

    func testAwakeWaitsBeforeLookingAgain() {
        armForTick()
        manager.tick()
        answer(.awake)
        XCTAssertTrue(startedHours.isEmpty)

        clock = clock.addingTimeInterval(AutoActivationManager.recheckInterval - 30)
        manager.tick()
        XCTAssertEqual(checks, 1, "No second look inside the recheck interval")

        clock = clock.addingTimeInterval(30)
        manager.tick()
        XCTAssertEqual(checks, 2)
    }

    func testOneLookAtATime() {
        armForTick()
        manager.tick()

        manager.tick()

        XCTAssertEqual(checks, 1)
    }

    func testPersonBackDuringTheLookStartsNothing() {
        armForTick()
        manager.tick()
        manager.idleSecondsProvider = { 2 }

        answer(.asleep)

        XCTAssertTrue(startedHours.isEmpty)
    }
}
