import XCTest
@testable import WatchMeSleepCore

@MainActor
final class CameraWatcherTests: XCTestCase {
    private var sessionChanges: [Bool] = []

    private func makeWatcher(authorized: Bool = true) -> CameraWatcher {
        CameraWatcher(cameraAuthorized: { authorized }, setSessionRunning: { _, running in
            self.sessionChanges.append(running)
        })
    }

    /// A barrier behind video work and its main-queue delivery, with no timer sleeps.
    private func drain(_ watcher: CameraWatcher) async {
        await withCheckedContinuation { continuation in
            watcher.videoOutputQueue.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    func testWithoutAccessALookNeverStartsTheCamera() {
        let watcher = makeWatcher(authorized: false)
        var verdict: PresenceCheck.Verdict?

        watcher.checkPresence { verdict = $0 }

        XCTAssertEqual(verdict, .unavailable, "Answered at once, without asking")
        XCTAssertTrue(sessionChanges.isEmpty)
        XCTAssertFalse(watcher.isSessionRunning)
    }

    func testCancellationReleasesTheCameraAndDiscardsTheAnswer() async {
        let watcher = makeWatcher()
        var answers = 0
        watcher.checkPresence { _ in answers += 1 }
        XCTAssertEqual(sessionChanges, [true])
        let generation = watcher.presenceGeneration

        watcher.cancelPresenceCheck()
        XCTAssertEqual(sessionChanges, [true, false], "Releases ownership before video cleanup")
        watcher.timeOutPresenceCheck(generation: generation)
        await drain(watcher)

        XCTAssertEqual(answers, 0)
        let cleared = await withCheckedContinuation { continuation in
            watcher.videoOutputQueue.async {
                continuation.resume(returning: watcher.presenceLook == nil)
            }
        }
        XCTAssertTrue(cleared)
    }

    func testCancellationLeavesThePreviewRunning() async {
        let watcher = makeWatcher()
        watcher.setPreviewActive(true)
        watcher.checkPresence { _ in XCTFail("A cancelled look must not answer") }
        XCTAssertEqual(sessionChanges, [true])

        watcher.cancelPresenceCheck()
        await drain(watcher)
        XCTAssertEqual(sessionChanges, [true], "The preview still owns the session")

        watcher.setPreviewActive(false)
        XCTAssertEqual(sessionChanges, [true, false])
    }

    func testQueuedAnswerFromCancelledLookCannotReleaseItsReplacement() async {
        let watcher = makeWatcher()
        var oldAnswers = 0
        var newVerdict: PresenceCheck.Verdict?
        watcher.checkPresence { _ in oldAnswers += 1 }
        // Wait only for video work. Its answer is then queued on main while this
        // main-actor turn still owns execution, before cancel/restart can yield.
        watcher.videoOutputQueue.sync {
            for index in 0...30 {
                watcher.recordPresence(eyes: .open, at: Double(index) / 10, luma: 0.5)
            }
        }
        watcher.cancelPresenceCheck()
        watcher.checkPresence { newVerdict = $0 }
        await drain(watcher)

        XCTAssertEqual(oldAnswers, 0)
        XCTAssertNil(newVerdict)
        XCTAssertEqual(sessionChanges, [true, false, true])

        watcher.timeOutPresenceCheck(generation: watcher.presenceGeneration)
        await drain(watcher)
        XCTAssertEqual(newVerdict, .unavailable)
        XCTAssertEqual(sessionChanges, [true, false, true, false])
    }

    func testTimeoutUsesObservationTimeAndIgnoresAnOlderGeneration() async {
        let watcher = makeWatcher()
        var oldAnswers = 0
        var newVerdict: PresenceCheck.Verdict?
        watcher.checkPresence { _ in oldAnswers += 1 }
        let oldGeneration = watcher.presenceGeneration
        watcher.cancelPresenceCheck()
        watcher.checkPresence { newVerdict = $0 }
        watcher.videoOutputQueue.async {
            watcher.recordPresence(eyes: .open, at: 0, luma: 0.5)
        }

        watcher.timeOutPresenceCheck(generation: oldGeneration)
        await drain(watcher)
        XCTAssertEqual(oldAnswers, 0)
        XCTAssertNil(newVerdict)
        XCTAssertEqual(sessionChanges, [true, false, true])

        watcher.timeOutPresenceCheck(generation: watcher.presenceGeneration)
        await drain(watcher)
        XCTAssertEqual(newVerdict, .unavailable, "One open-eye frame cannot establish absence")
        XCTAssertEqual(sessionChanges, [true, false, true, false])
    }
}
