import XCTest
@testable import WatchMeSleepCore

final class TimerManagerTests: XCTestCase {
    var timerManager: TimerManager!
    var didTriggerSleep = false

    override func setUp() {
        super.setUp()
        timerManager = TimerManager.shared
        timerManager.stopTimer()
        // Override the sleep seam so the suite never actually sleeps the machine.
        didTriggerSleep = false
        timerManager.sleepHandler = { [weak self] in self?.didTriggerSleep = true }
        // Reset the clock seam so a frozen clock never leaks between tests (shared singleton).
        timerManager.now = Date.init
    }

    override func tearDown() {
        timerManager.stopTimer()
        timerManager.now = Date.init
        super.tearDown()
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

