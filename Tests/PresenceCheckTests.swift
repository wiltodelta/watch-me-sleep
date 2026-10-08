import XCTest
@testable import WatchMeSleepCore

final class PresenceCheckTests: XCTestCase {

    /// Feeds frames until a verdict arrives; returns it and the frame it came on.
    private func run(_ check: inout PresenceCheck, _ frames: [EyeReading?]) -> (PresenceCheck.Verdict, Int)? {
        for (index, eyes) in frames.enumerated() {
            // 10 fps: frame n at n/10 s, so n frames span (n - 1)/10 s.
            let verdict = check.record(eyes: eyes, at: Double(index) / 10)
            if let verdict { return (verdict, index + 1) }
        }
        return nil
    }

    func testClosedEyesAreAsleepAfterTheTrackerRun() {
        var check = PresenceCheck()
        let result = run(&check, Array(repeating: EyeReading.closed, count: 300))
        XCTAssertEqual(result?.0, .asleep)
        XCTAssertEqual(result?.1, 151, "15 seconds, as camera mode used")
    }

    func testOpenEyesAreAwakeWithinSeconds() {
        var check = PresenceCheck()
        let result = run(&check, Array(repeating: EyeReading.open, count: 300))
        XCTAssertEqual(result?.0, .awake)
        XCTAssertEqual(result?.1, 31, "3 seconds")
    }

    func testBlinkingCountsAsAwake() {
        var check = PresenceCheck()
        let blinking: [EyeReading?] = (0..<300).map { $0 % 3 == 0 ? EyeReading.closed : EyeReading.open }
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
        let tenth: [EyeReading?] = Array(repeating: EyeReading.closed, count: 31) + Array(repeating: nil, count: 270)
        XCTAssertEqual(run(&atLimit, tenth)?.0, .absent)

        var overLimit = PresenceCheck()
        let more: [EyeReading?] = Array(repeating: EyeReading.closed, count: 32) + Array(repeating: nil, count: 269)
        XCTAssertEqual(run(&overLimit, more)?.0, .unclear, "Seen, but too briefly to tell")
    }

    func testAFrameReadAsOpenDoesNotBreakTheRun() {
        var check = PresenceCheck()
        let noisy: [EyeReading?] = (0..<300).map { $0 == 100 ? EyeReading.open : EyeReading.closed }
        // The noisy frame neither breaks the run nor counts toward it.
        XCTAssertEqual(run(&check, noisy)?.1, 152, "Detector noise, not waking")
    }

    func testNoisyClosedEyesStillCountAsAsleep() {
        var check = PresenceCheck()
        // Every eighth frame misread as open, as in the dark benchmark.
        let noisy: [EyeReading?] = (0..<300).map { $0 % 8 == 7 ? EyeReading.open : EyeReading.closed }
        XCTAssertEqual(run(&check, noisy)?.0, .asleep)
    }

    func testEyesOpenForASecondStartTheRunOver() {
        var check = PresenceCheck()
        let woke: [EyeReading?] = Array(repeating: EyeReading.closed, count: 100) + Array(repeating: EyeReading.open, count: 11)
            + Array(repeating: EyeReading.closed, count: 200)
        let result = run(&check, woke)
        XCTAssertEqual(result?.0, .asleep)
        XCTAssertEqual(result?.1, 111 + 150, "The run restarts after a real reopening")
    }

    func testABriefLossOfTheFaceKeepsTheRun() {
        var check = PresenceCheck()
        let frames: [EyeReading?] = Array(repeating: EyeReading.closed, count: 100) + Array(repeating: nil, count: 20)
            + Array(repeating: EyeReading.closed, count: 100)
        XCTAssertEqual(run(&check, frames)?.0, .asleep, "100 + 50 closed frames, 20 missed in between")
    }

    func testALongLossOfTheFaceStartsTheRunOver() {
        var check = PresenceCheck(lookSeconds: 100)
        let frames: [EyeReading?] = Array(repeating: EyeReading.closed, count: 100) + Array(repeating: nil, count: 150)
            + Array(repeating: EyeReading.closed, count: 149)
        XCTAssertNil(run(&check, frames), "149 closed after the reset is one short")
    }

    func testASlowCameraTakesTheSameFifteenSeconds() {
        var check = PresenceCheck()
        var verdict: PresenceCheck.Verdict?
        var time: TimeInterval = 0
        while verdict == nil {
            verdict = check.record(eyes: EyeReading.closed, at: time)
            time += 0.25 // 4 fps, a camera slowed by the dark
        }
        XCTAssertEqual(verdict, .asleep)
        XCTAssertEqual(time - 0.25, 15, accuracy: 0.001)
    }

    func testAStalledCameraCannotSettleItInOneFrame() {
        var check = PresenceCheck()
        XCTAssertNil(check.record(eyes: EyeReading.closed, at: 0))
        XCTAssertNil(check.record(eyes: EyeReading.closed, at: 20), "A 20 s gap counts as half a second")
    }

    func testNoFramesAtAllIsUnavailable() {
        XCTAssertEqual(PresenceCheck().finalVerdict, .unavailable)
    }

    func testDarkFramesWithoutAFaceAreUnclearNotAbsent() {
        var check = PresenceCheck()
        var verdict: PresenceCheck.Verdict?
        for index in 0..<400 where verdict == nil {
            verdict = check.record(eyes: nil, at: Double(index) / 10, luma: 0.01)
        }
        XCTAssertEqual(verdict, .unclear, "A black frame cannot tell an empty bed from a sleeper")
    }
}
