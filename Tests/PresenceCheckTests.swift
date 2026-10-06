import XCTest
@testable import WatchMeSleepCore

final class PresenceCheckTests: XCTestCase {
    private let closedEAR = 0.10
    /// Open eyes as measured live: median 0.234 (see `PresenceCheck`).
    private let openEAR = 0.234

    /// Feeds frames until a verdict arrives; returns it and the frame it came on.
    private func run(_ check: inout PresenceCheck, _ frames: [Double?]) -> (PresenceCheck.Verdict, Int)? {
        for (index, ear) in frames.enumerated() {
            // 10 fps: frame n at n/10 s, so n frames span (n - 1)/10 s.
            let verdict = check.record(ear: ear, at: Double(index) / 10)
            if let verdict { return (verdict, index + 1) }
        }
        return nil
    }

    func testClosedEyesAreAsleepAfterTheTrackerRun() {
        var check = PresenceCheck()
        let result = run(&check, Array(repeating: closedEAR, count: 300))
        XCTAssertEqual(result?.0, .asleep)
        XCTAssertEqual(result?.1, 151, "15 seconds, as camera mode used")
    }

    func testOpenEyesAreAwakeWithinSeconds() {
        var check = PresenceCheck()
        let result = run(&check, Array(repeating: openEAR, count: 300))
        XCTAssertEqual(result?.0, .awake)
        XCTAssertEqual(result?.1, 31, "3 seconds")
    }

    func testBlinkingCountsAsAwake() {
        var check = PresenceCheck()
        let blinking: [Double?] = (0..<300).map { $0 % 3 == 0 ? closedEAR : openEAR }
        XCTAssertEqual(run(&check, blinking)?.0, .awake)
    }

    func testNoFaceIsAbsentAfterTheWholeLook() {
        var check = PresenceCheck()
        let result = run(&check, Array(repeating: nil, count: 301))
        XCTAssertEqual(result?.0, .absent)
        XCTAssertEqual(result?.1, 301, "30 seconds")
    }

    func testAFaceInMoreThanATenthOfTheLookIsNotAbsent() {
        var atLimit = PresenceCheck()
        // A frame stands for the gap before it: 31 face frames are 3.0 s of 30.
        let tenth: [Double?] = Array(repeating: closedEAR, count: 31) + Array(repeating: nil, count: 270)
        XCTAssertEqual(run(&atLimit, tenth)?.0, .absent)

        var overLimit = PresenceCheck()
        let more: [Double?] = Array(repeating: closedEAR, count: 32) + Array(repeating: nil, count: 269)
        XCTAssertEqual(run(&overLimit, more)?.0, .unclear, "Seen, but too briefly to tell")
    }

    func testEyesJustAboveTheClosedLineAreOpen() {
        var check = PresenceCheck()
        XCTAssertEqual(run(&check, Array(repeating: 0.20, count: 300))?.0, .awake)
    }

    func testABlinkStartsTheClosedRunOver() {
        var check = PresenceCheck()
        let blinkAt100: [Double?] = (0..<300).map { $0 == 100 ? openEAR : closedEAR }
        let result = run(&check, blinkAt100)
        XCTAssertEqual(result?.0, .asleep)
        XCTAssertEqual(result?.1, 101 + 150, "The run restarts after the reopening")
    }

    func testABriefLossOfTheFaceKeepsTheRun() {
        var check = PresenceCheck()
        let frames: [Double?] = Array(repeating: closedEAR, count: 100) + Array(repeating: nil, count: 20)
            + Array(repeating: closedEAR, count: 100)
        XCTAssertEqual(run(&check, frames)?.0, .asleep, "100 + 50 closed frames, 20 missed in between")
    }

    func testALongLossOfTheFaceStartsTheRunOver() {
        var check = PresenceCheck(lookSeconds: 100)
        let frames: [Double?] = Array(repeating: closedEAR, count: 100) + Array(repeating: nil, count: 150)
            + Array(repeating: closedEAR, count: 149)
        XCTAssertNil(run(&check, frames), "149 closed after the reset is one short")
    }

    func testASlowCameraTakesTheSameFifteenSeconds() {
        var check = PresenceCheck()
        var verdict: PresenceCheck.Verdict?
        var time: TimeInterval = 0
        while verdict == nil {
            verdict = check.record(ear: closedEAR, at: time)
            time += 0.25 // 4 fps, a camera slowed by the dark
        }
        XCTAssertEqual(verdict, .asleep)
        XCTAssertEqual(time - 0.25, 15, accuracy: 0.001)
    }

    func testAStalledCameraCannotSettleItInOneFrame() {
        var check = PresenceCheck()
        XCTAssertNil(check.record(ear: closedEAR, at: 0))
        XCTAssertNil(check.record(ear: closedEAR, at: 20), "A 20 s gap counts as half a second")
    }

    func testNoFramesAtAllIsUnavailable() {
        XCTAssertEqual(PresenceCheck().finalVerdict, .unavailable)
    }
}
