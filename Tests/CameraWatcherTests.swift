import XCTest
import AVFoundation
@testable import WatchMeSleepCore

final class CameraWatcherTests: XCTestCase {
    /// The test runner holds no camera grant, which is the night's case of a
    /// person who never allowed it: no prompt, no session, an `.unavailable` look.
    func testWithoutAccessALookNeverStartsTheCamera() throws {
        try XCTSkipIf(CameraWatcher.isAuthorized, "Runs only where camera access was never granted")
        var verdict: PresenceCheck.Verdict?

        CameraWatcher.shared.checkPresence { verdict = $0 }

        XCTAssertEqual(verdict, .unavailable, "Answered at once, without asking")
        XCTAssertFalse(CameraWatcher.shared.isSessionRunning)
    }
}
