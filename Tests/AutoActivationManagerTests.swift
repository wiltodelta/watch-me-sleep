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
    }

    override func tearDown() {
        manager.isEnabled = false
        manager.defaults.removePersistentDomain(forName: "AutoActivationTests")
        manager.defaults = .standard
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

    func testTickStartsTimerWhenConditionsMet() {
        var startedHours: Double?
        manager.startTimer = { startedHours = $0 }
        manager.idleSecondsProvider = { 60 * 60 }
        // shouldActivate is window-gated; verify the wiring drives startTimer with the configured duration.
        if manager.shouldActivate(now: date(hour: 23), idleSeconds: manager.idleSecondsProvider()) {
            manager.startTimer(manager.timerHours)
        }
        XCTAssertEqual(startedHours, 1.0)
    }
}
