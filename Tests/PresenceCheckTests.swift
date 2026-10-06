import XCTest
@testable import WatchMeSleepCore

final class PresenceCheckTests: XCTestCase {
    private let closedEAR = 0.10
    private let openEAR = 0.32
    /// Between the closed and open thresholds: a face, but no clear answer.
    private let unclearEAR = 0.23

    /// Feeds frames until a verdict arrives; returns it and the frame it came on.
    private func run(_ check: inout PresenceCheck, _ frames: [Double?]) -> (PresenceCheck.Verdict, Int)? {
        for (index, ear) in frames.enumerated() {
            let verdict = ear.map { check.record(ear: $0) } ?? check.recordMissedFrame()
            if let verdict { return (verdict, index + 1) }
        }
        return nil
    }

    func testClosedEyesAreAsleepAfterTheTrackerRun() {
        var check = PresenceCheck()
        let result = run(&check, Array(repeating: closedEAR, count: 300))
        XCTAssertEqual(result?.0, .asleep)
        XCTAssertEqual(result?.1, 150, "Same 15-second run camera mode uses")
    }

    func testOpenEyesAreAwakeWithinSeconds() {
        var check = PresenceCheck()
        let result = run(&check, Array(repeating: openEAR, count: 300))
        XCTAssertEqual(result?.0, .awake)
        XCTAssertEqual(result?.1, 30)
    }

    func testBlinkingCountsAsAwake() {
        var check = PresenceCheck()
        let blinking: [Double?] = (0..<300).map { $0 % 3 == 0 ? closedEAR : openEAR }
        XCTAssertEqual(run(&check, blinking)?.0, .awake)
    }

    func testNoFaceIsAbsentAfterTheWholeLook() {
        var check = PresenceCheck()
        let result = run(&check, Array(repeating: nil, count: 300))
        XCTAssertEqual(result?.0, .absent)
        XCTAssertEqual(result?.1, 300)
    }

    func testAFaceInMoreThanATenthOfTheLookIsNotAbsent() {
        var atLimit = PresenceCheck()
        let tenth: [Double?] = Array(repeating: unclearEAR, count: 30) + Array(repeating: nil, count: 270)
        XCTAssertEqual(run(&atLimit, tenth)?.0, .absent)

        var overLimit = PresenceCheck()
        let more: [Double?] = Array(repeating: unclearEAR, count: 31) + Array(repeating: nil, count: 269)
        XCTAssertEqual(run(&overLimit, more)?.0, .awake)
    }

    func testAnUnclearFaceIsNotTakenForSleep() {
        var check = PresenceCheck()
        XCTAssertEqual(run(&check, Array(repeating: unclearEAR, count: 300))?.0, .awake)
    }

    func testNoFramesAtAllIsUnavailable() {
        XCTAssertEqual(PresenceCheck().finalVerdict, .unavailable)
    }
}
