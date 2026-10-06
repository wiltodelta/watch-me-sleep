import XCTest
@testable import WatchMeSleepCore

/// Records what the final phase asks of the volume instead of touching a device.
/// Like `SystemVolumeFader`, a restore with no fade before it changes nothing,
/// so only effective restores are counted.
final class FakeVolume: VolumeControl {
    var fades: [Double] = []
    var restores = 0
    private var isFaded = false

    func fade(to fraction: Double) {
        fades.append(fraction)
        isFaded = true
    }

    func restore() {
        guard isFaded else { return }
        isFaded = false
        restores += 1
    }
}

final class TimerManagerTests: XCTestCase {
    var timerManager: TimerManager!
    var didTriggerSleep = false
    var fakeVolume: FakeVolume!
    var idleSeconds: TimeInterval = .infinity

    override func setUp() {
        super.setUp()
        timerManager = TimerManager.shared
        timerManager.stopTimer()
        // Override the sleep seam so the suite never actually sleeps the machine.
        didTriggerSleep = false
        timerManager.sleepHandler = { [weak self] in self?.didTriggerSleep = true }
        // Reset the clock seam so a frozen clock never leaks between tests (shared singleton).
        timerManager.now = Date.init
        // Nobody at the keyboard unless a test says so, and no real volume changes.
        idleSeconds = .infinity
        timerManager.idleSecondsProvider = { [weak self] in self?.idleSeconds ?? .infinity }
        fakeVolume = FakeVolume()
        timerManager.volume = fakeVolume
    }

    override func tearDown() {
        timerManager.stopTimer()
        timerManager.now = Date.init
        super.tearDown()
    }

    /// Starts a 15-minute timer on a frozen clock and returns a way to move it.
    private func startFrozenTimer() -> (TimeInterval) -> Void {
        var fakeNow = Date()
        timerManager.now = { fakeNow }
        timerManager.startTimer(hours: 0.25)
        return { seconds in
            fakeNow = fakeNow.addingTimeInterval(seconds)
            self.timerManager.tick()
        }
    }

    // MARK: - Final Phase Tests

    func testNoFinalPhaseBeforeLastMinute() {
        let advance = startFrozenTimer()

        advance(15 * 60 - 61)

        XCTAssertFalse(timerManager.isInFinalPhase)
        XCTAssertTrue(fakeVolume.fades.isEmpty, "Volume must not fade before the final minute")
    }

    func testFinalPhaseFadesVolumeWithRemainingTime() {
        let advance = startFrozenTimer()

        advance(15 * 60 - 60)
        XCTAssertTrue(timerManager.isInFinalPhase)
        advance(30)

        XCTAssertEqual(fakeVolume.fades.count, 2)
        XCTAssertEqual(fakeVolume.fades[0], 1.0, accuracy: 0.001)
        XCTAssertEqual(fakeVolume.fades[1], 0.5, accuracy: 0.001)
    }

    func testIdleMacSleepsAtZeroWithVolumeStillDown() {
        let advance = startFrozenTimer()
        advance(15 * 60 - 60)

        advance(60)

        XCTAssertTrue(didTriggerSleep)
        XCTAssertFalse(timerManager.isTimerActive)
        XCTAssertFalse(timerManager.isInFinalPhase)
        XCTAssertEqual(fakeVolume.restores, 0, "Volume comes back on wake, not just before sleep")
    }

    func testActivityDuringFinalPhasePostponesInsteadOfSleeping() {
        let advance = startFrozenTimer()
        advance(15 * 60 - 60)
        advance(20)
        // Someone touched the mouse 5 seconds ago, inside the final phase.
        idleSeconds = 5
        advance(1)
        XCTAssertTrue(timerManager.isUserActive)
        XCTAssertEqual(fakeVolume.restores, 1, "Volume comes back as soon as someone is active")
        let fadesBeforeActivity = fakeVolume.fades.count

        advance(39)

        XCTAssertFalse(didTriggerSleep, "A Mac in use must not be put to sleep")
        XCTAssertTrue(timerManager.isTimerActive)
        XCTAssertFalse(timerManager.isInFinalPhase)
        XCTAssertFalse(timerManager.isUserActive)
        XCTAssertEqual(timerManager.remainingTime, TimeInterval(TimerManager.postponeMinutes * 60), accuracy: 0.001)
        XCTAssertEqual(fakeVolume.fades.count, fadesBeforeActivity, "No fading once someone is active")
    }

    func testActivityBeforeFinalPhaseDoesNotCount() {
        let advance = startFrozenTimer()
        advance(15 * 60 - 60)
        // Ten seconds into the warning, the last input was 30 seconds ago:
        // twenty seconds before the warning appeared.
        idleSeconds = 30
        advance(10)

        XCTAssertFalse(timerManager.isUserActive)
        XCTAssertEqual(fakeVolume.restores, 0, "The fade goes on for input older than the warning")

        idleSeconds = 80
        advance(50)
        XCTAssertTrue(didTriggerSleep)
    }

    func testAddingTimeDuringFinalPhaseEndsItAndRestoresVolume() {
        let advance = startFrozenTimer()
        advance(15 * 60 - 30)
        XCTAssertTrue(timerManager.isInFinalPhase)

        timerManager.addTime(minutes: TimerManager.postponeMinutes)

        XCTAssertFalse(timerManager.isInFinalPhase)
        XCTAssertEqual(fakeVolume.restores, 1)
    }

    func testStopTimerRestoresVolume() {
        let advance = startFrozenTimer()
        advance(15 * 60 - 30)

        timerManager.stopTimer()

        XCTAssertFalse(timerManager.isInFinalPhase)
        XCTAssertEqual(fakeVolume.restores, 1)
    }

    func testSleepNowDropsTheTimer() {
        timerManager.startTimer(hours: 1.0)

        timerManager.sleepNow()

        XCTAssertTrue(didTriggerSleep)
        XCTAssertFalse(timerManager.isTimerActive, "A timer left running would sleep the Mac again on wake")
    }

    // MARK: - Wake Tests

    func testATimerThatRanOutDuringSleepStopsOnTheNextTick() {
        let advance = startFrozenTimer()
        advance(15 * 60 - 30)
        // Asleep through zero; the lid opening counts as fresh input.
        idleSeconds = 1

        advance(2 * 3600)

        XCTAssertFalse(timerManager.isTimerActive, "Not postponed into the morning")
        XCTAssertFalse(didTriggerSleep, "Waking must not put the Mac straight back to sleep")
        XCTAssertEqual(fakeVolume.restores, 1)
    }

    func testALateTickStillSleepsTheMac() {
        let advance = startFrozenTimer()
        advance(15 * 60 - 30)

        advance(30 + TimerManager.overdueAfter - 1)

        XCTAssertTrue(didTriggerSleep, "A tick delayed by App Nap is not a sleep")
    }

    func testWakeRestoresVolume() {
        let advance = startFrozenTimer()
        advance(15 * 60 - 30)

        timerManager.handleWake()

        XCTAssertEqual(fakeVolume.restores, 1)
    }

    func testWakeKeepsATimerStillRunning() {
        let advance = startFrozenTimer()
        advance(60)

        timerManager.handleWake()

        XCTAssertTrue(timerManager.isTimerActive)
    }
    
    // MARK: - Start Timer Tests
    
    func testStartTimer() {
        // Given
        let hours: Double = 1.0
        
        // When
        timerManager.startTimer(hours: hours)
        
        // Then
        XCTAssertTrue(timerManager.isTimerActive, "Timer should be active after starting")
        XCTAssertEqual(timerManager.totalTime, hours * 3600, accuracy: 1.0, "Total time should match")
        XCTAssertGreaterThan(timerManager.remainingTime, 0, "Remaining time should be positive")
    }
    
    func testStartTimerWithZeroHours() {
        // Given
        let hours: Double = 0.0
        
        // When
        timerManager.startTimer(hours: hours)
        
        // Then
        XCTAssertTrue(timerManager.isTimerActive, "Timer should start even with 0 hours")
        XCTAssertEqual(timerManager.totalTime, 0, "Total time should be 0")
    }
    
    func testStartTimerWithMultipleHours() {
        // Given
        let hours: Double = 2.5
        
        // When
        timerManager.startTimer(hours: hours)
        
        // Then
        XCTAssertEqual(timerManager.totalTime, hours * 3600, accuracy: 1.0, "Total time should be 2.5 hours in seconds")
    }
    
    // MARK: - Stop Timer Tests
    
    func testStopTimer() {
        // Given
        timerManager.startTimer(hours: 1.0)
        XCTAssertTrue(timerManager.isTimerActive)
        
        // When
        timerManager.stopTimer()
        
        // Then
        XCTAssertFalse(timerManager.isTimerActive, "Timer should not be active after stopping")
        XCTAssertEqual(timerManager.remainingTime, 0, "Remaining time should be 0")
        XCTAssertEqual(timerManager.totalTime, 0, "Total time should be 0")
    }
    
    func testStopTimerWhenNotActive() {
        // Given
        XCTAssertFalse(timerManager.isTimerActive)
        
        // When
        timerManager.stopTimer()
        
        // Then
        XCTAssertFalse(timerManager.isTimerActive, "Timer should remain inactive")
        XCTAssertEqual(timerManager.remainingTime, 0, "Remaining time should be 0")
    }
    
    // MARK: - Add Time Tests
    
    func testAddTime() {
        // Given
        timerManager.startTimer(hours: 1.0)
        let initialTotal = timerManager.totalTime
        let minutesToAdd = 15
        
        // When
        timerManager.addTime(minutes: minutesToAdd)
        
        // Then
        XCTAssertTrue(timerManager.isTimerActive, "Timer should remain active")
        XCTAssertEqual(
            timerManager.totalTime,
            initialTotal + TimeInterval(minutesToAdd * 60),
            accuracy: 1.0,
            "Total time should increase by added minutes"
        )
    }
    
    func testAddTimeWhenTimerNotActive() {
        // Given
        XCTAssertFalse(timerManager.isTimerActive)
        
        // When
        timerManager.addTime(minutes: 10)
        
        // Then
        XCTAssertFalse(timerManager.isTimerActive, "Timer should remain inactive")
        XCTAssertEqual(timerManager.totalTime, 0, "Total time should remain 0")
    }
    
    func testAddNegativeTime() {
        // Given
        timerManager.startTimer(hours: 1.0)
        let initialTotal = timerManager.totalTime
        
        // When
        timerManager.addTime(minutes: -10)
        
        // Then
        XCTAssertEqual(
            timerManager.totalTime,
            initialTotal - TimeInterval(10 * 60),
            accuracy: 1.0,
            "Total time should decrease when negative minutes are added"
        )
    }
    
    // MARK: - Restart Timer Tests
    
    func testRestartTimer() {
        // Given
        timerManager.startTimer(hours: 1.0)
        timerManager.addTime(minutes: 10)
        let firstTotal = timerManager.totalTime
        
        // When
        timerManager.startTimer(hours: 2.0)
        
        // Then
        XCTAssertTrue(timerManager.isTimerActive, "Timer should be active")
        XCTAssertEqual(timerManager.totalTime, 2.0 * 3600, accuracy: 1.0, "Total should reset to new duration")
        XCTAssertNotEqual(timerManager.totalTime, firstTotal, "Total should be different from previous")
    }
    
    // MARK: - Timer Update Tests
    
    func testTimerUpdatesRemainingTime() {
        // Given a controllable clock so the assertion is deterministic, not wall-clock timed.
        var fakeNow = Date()
        timerManager.now = { fakeNow }
        timerManager.startTimer(hours: 1.0)
        let initialRemaining = timerManager.remainingTime

        // When time advances and a timer cycle runs
        fakeNow = fakeNow.addingTimeInterval(60)
        timerManager.tick()

        // Then
        XCTAssertLessThan(
            timerManager.remainingTime,
            initialRemaining,
            "Remaining time should decrease"
        )
    }
    
    // MARK: - Notification Tests
    
    func testTimerStartSendsNotification() {
        // Given
        let expectation = self.expectation(description: "Timer start notification")
        var observerToken: Any?
        observerToken = NotificationCenter.default.addObserver(
            forName: .timerUpdated,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
            // Remove observer immediately after first call to prevent multiple fulfills
            if let token = observerToken {
                NotificationCenter.default.removeObserver(token)
            }
        }
        
        // When
        timerManager.startTimer(hours: 1.0)
        
        // Then
        waitForExpectations(timeout: 1.0)
        // Ensure cleanup even if test fails
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    func testTimerStopSendsNotification() {
        // Given
        timerManager.startTimer(hours: 1.0)
        
        // Wait a bit to ensure start notification is processed
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        
        let expectation = self.expectation(description: "Timer stop notification")
        var observerToken: Any?
        observerToken = NotificationCenter.default.addObserver(
            forName: .timerUpdated,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
            // Remove observer immediately after first call
            if let token = observerToken {
                NotificationCenter.default.removeObserver(token)
            }
        }
        
        // When
        timerManager.stopTimer()
        
        // Then
        waitForExpectations(timeout: 1.0)
        // Ensure cleanup
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    // MARK: - Edge Cases
    
    func testVeryShortTimer() {
        // Given a controllable clock so completion is driven deterministically,
        // not by waiting on a real Timer (which is flaky under CI load).
        var fakeNow = Date()
        timerManager.now = { fakeNow }

        // When a short timer is started and time advances past its target
        timerManager.startTimer(hours: 0.0003) // ~1 second
        XCTAssertTrue(timerManager.isTimerActive, "Timer should be active right after starting")

        fakeNow = fakeNow.addingTimeInterval(2)
        timerManager.tick()

        // Then
        XCTAssertFalse(timerManager.isTimerActive, "Timer should stop after completion")
        XCTAssertTrue(didTriggerSleep, "Sleep handler should fire when the timer reaches zero")
    }
    
    func testTimerWithLargeHours() {
        // Given
        let hours: Double = 12.0
        
        // When
        timerManager.startTimer(hours: hours)
        
        // Then
        XCTAssertEqual(timerManager.totalTime, hours * 3600, accuracy: 1.0, "Should handle large hour values")
        XCTAssertTrue(timerManager.isTimerActive)
    }
}

