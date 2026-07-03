import XCTest
@testable import WatchMeSleepCore

final class EyeStateTrackerTests: XCTestCase {
    // EAR values clearly on either side of the default thresholds (closed < 0.20,
    // open > 0.27), so `record(ear:)` maps them to unambiguous closed/open frames.
    private let closedEAR = 0.10
    private let openEAR = 0.35

    // MARK: - Blink vs sleep

    func testBlinkDoesNotTriggerSleep() {
        var tracker = EyeStateTracker()

        // A blink is a short run of closed frames, far under the 150-frame threshold.
        for _ in 0..<20 {
            XCTAssertEqual(tracker.record(ear: closedEAR), .noChange)
        }
        // Eyes reopen, resetting the consecutive run.
        for _ in 0..<5 {
            XCTAssertEqual(tracker.record(ear: openEAR), .noChange)
        }

        XCTAssertFalse(tracker.isAsleep)
        XCTAssertEqual(tracker.consecutiveClosedFrames, 0, "An open frame must reset the run")
    }

    // MARK: - Early trigger on a long continuous closure

    func testConsecutiveClosedFramesTriggerSleepBeforeWindowFills() {
        var tracker = EyeStateTracker() // windowSize 600, minContinuousClosedFrames 150

        // The first 149 closed frames are not yet enough.
        for _ in 0..<149 {
            XCTAssertEqual(tracker.record(ear: closedEAR), .noChange)
        }
        XCTAssertFalse(tracker.isAsleep)

        // The 150th consecutive closed frame triggers sleep even though the 600-frame
        // window is nowhere near full.
        XCTAssertEqual(tracker.record(ear: closedEAR), .sleepDetected)
        XCTAssertTrue(tracker.isAsleep)
        XCTAssertLessThan(tracker.windowCount, 600, "Sleep should fire early, before the window saturates")
    }

    // MARK: - High closed percentage over a full window

    func testHighClosedPercentageOverFullWindowTriggersSleep() {
        // Small window so the run reaches the consecutive threshold only after the
        // window is already full, exercising the percentage path rather than the
        // early (not-yet-full) path.
        var tracker = EyeStateTracker(
            windowSize: 5,
            sleepThresholdPercent: 0.6,
            minContinuousClosedFrames: 3
        )

        // Fill the window without a 3-frame run: closed, closed, open, open, closed.
        let prefix = [true, true, false, false, true]
        for closed in prefix {
            XCTAssertEqual(tracker.record(ear: closed ? closedEAR : openEAR), .noChange)
        }
        XCTAssertEqual(tracker.windowCount, 5, "Window should be full")

        // Two more closed frames keep the window full at 3/5 = 60% closed and grow the
        // run to 3; that crosses both thresholds with the window full -> sleep.
        XCTAssertEqual(tracker.record(ear: closedEAR), .noChange)
        XCTAssertEqual(tracker.record(ear: closedEAR), .sleepDetected)
        XCTAssertTrue(tracker.isAsleep)
        XCTAssertEqual(tracker.closedPercentage, 0.6, accuracy: 0.0001)
    }

    // MARK: - Wake on a low closed percentage

    func testLowClosedPercentageOverFullWindowTriggersWake() {
        var tracker = EyeStateTracker(
            windowSize: 5,
            sleepThresholdPercent: 0.6,
            wakeThresholdPercent: 0.2,
            minContinuousClosedFrames: 3
        )

        // Fall asleep via three continuous closed frames (early trigger).
        for _ in 0..<2 {
            XCTAssertEqual(tracker.record(ear: closedEAR), .noChange)
        }
        XCTAssertEqual(tracker.record(ear: closedEAR), .sleepDetected)

        // Open frames slide the closed count down. Wake only fires once the window is
        // full (5 frames) and at/under 20% closed, i.e. 1 of 5.
        XCTAssertEqual(tracker.record(ear: openEAR), .noChange) // window not full yet
        XCTAssertEqual(tracker.record(ear: openEAR), .noChange) // full, 60% closed
        XCTAssertEqual(tracker.record(ear: openEAR), .noChange) // full, 40% closed
        XCTAssertEqual(tracker.record(ear: openEAR), .wakeDetected) // full, 20% closed
        XCTAssertFalse(tracker.isAsleep)
    }

    // MARK: - Missed-frame tolerance

    func testMissedFramesToleranceResetsWindow() {
        var tracker = EyeStateTracker(windowSize: 10, minContinuousClosedFrames: 3, maxMissedFrames: 3)

        for _ in 0..<4 {
            _ = tracker.record(ear: closedEAR)
        }
        XCTAssertEqual(tracker.windowCount, 4)
        XCTAssertEqual(tracker.consecutiveClosedFrames, 4)

        // Missed frames within tolerance leave the window intact.
        XCTAssertFalse(tracker.recordMissedFrame())
        XCTAssertFalse(tracker.recordMissedFrame())
        XCTAssertEqual(tracker.windowCount, 4, "Window must survive within the missed-frame tolerance")

        // The frame that crosses the tolerance drops the window and the run.
        XCTAssertTrue(tracker.recordMissedFrame())
        XCTAssertTrue(tracker.isWindowEmpty)
        XCTAssertEqual(tracker.consecutiveClosedFrames, 0)
        XCTAssertEqual(tracker.closedPercentage, 0.0, accuracy: 0.0001)
    }

    func testMissedFramesDoNotClearAsleepFlag() {
        var tracker = EyeStateTracker(windowSize: 5, minContinuousClosedFrames: 3, maxMissedFrames: 2)

        for _ in 0..<2 {
            _ = tracker.record(ear: closedEAR)
        }
        XCTAssertEqual(tracker.record(ear: closedEAR), .sleepDetected)

        // Losing the face drops the window but must not silently wake the user.
        XCTAssertFalse(tracker.recordMissedFrame())
        XCTAssertTrue(tracker.recordMissedFrame())
        XCTAssertTrue(tracker.isWindowEmpty)
        XCTAssertTrue(tracker.isAsleep, "Asleep state should persist while the face is briefly lost")
    }

    // MARK: - Reset

    func testResetClearsAllState() {
        var tracker = EyeStateTracker(windowSize: 5, minContinuousClosedFrames: 3)

        for _ in 0..<2 {
            _ = tracker.record(ear: closedEAR)
        }
        XCTAssertEqual(tracker.record(ear: closedEAR), .sleepDetected)
        _ = tracker.recordMissedFrame()

        tracker.reset()

        XCTAssertFalse(tracker.isAsleep)
        XCTAssertTrue(tracker.isWindowEmpty)
        XCTAssertEqual(tracker.consecutiveClosedFrames, 0)
        XCTAssertEqual(tracker.missedFramesCount, 0)
        XCTAssertEqual(tracker.closedPercentage, 0.0, accuracy: 0.0001)
    }
}
