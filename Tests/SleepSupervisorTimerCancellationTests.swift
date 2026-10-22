import XCTest
@testable import WatchMeSleepCore

@MainActor
final class SleepSupervisorTimerCancellationTests: SleepSupervisorTestCase {
    private func armCameraTimer() {
        idleFor(minutes: 10)
        answer(.asleep)
        XCTAssertTrue(timer.isTimerActive)
        XCTAssertTrue(timer.stopsOnInput)
    }

    private func advance(_ seconds: TimeInterval) {
        clock += seconds
        idle += seconds
        timer.tick()
    }

    private func assertCanceled(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(timer.isTimerActive, file: file, line: line)
        advance(5 * 60)
        supervisor.tick()
        XCTAssertFalse(slept, file: file, line: line)
    }

    func testDisablingWatchCancelsItsTimerImmediately() {
        armCameraTimer()

        supervisor.isEnabled = false

        XCTAssertEqual(supervisor.status, .off)
        assertCanceled()
    }

    func testEndingNapCancelsItsTimerImmediately() {
        clock = at(13, 0)
        supervisor.watchNow()
        armCameraTimer()

        supervisor.stopWatchingNow()

        XCTAssertFalse(supervisor.isWatchingNow)
        XCTAssertEqual(supervisor.status, .outsideHours)
        assertCanceled()
    }

    func testKeepingSoundCancelsItsTimerImmediately() {
        holders = Self.sound
        armCameraTimer()

        supervisor.keepsSoundPlaying = true

        XCTAssertEqual(supervisor.status, .keepingSound)
        assertCanceled()
    }

    func testDisablingWatchPreservesAHandSetTimer() {
        timer.startTimer(hours: 1)

        supervisor.isEnabled = false

        advance(60)
        XCTAssertTrue(timer.isTimerActive)
        XCTAssertFalse(timer.stopsOnInput)
        XCTAssertEqual(timer.remainingTime, 59 * 60, accuracy: 0.01)
    }

    func testEndingNapPreservesAHandSetTimer() {
        clock = at(13, 0)
        supervisor.watchNow()
        timer.startTimer(hours: 1)

        supervisor.stopWatchingNow()

        advance(60)
        XCTAssertTrue(timer.isTimerActive)
        XCTAssertFalse(timer.stopsOnInput)
        XCTAssertEqual(timer.remainingTime, 59 * 60, accuracy: 0.01)
    }

    func testKeepingSoundPreservesAHandSetTimer() {
        holders = Self.sound
        timer.startTimer(hours: 1)

        supervisor.keepsSoundPlaying = true

        advance(60)
        XCTAssertTrue(timer.isTimerActive)
        XCTAssertFalse(timer.stopsOnInput)
        XCTAssertEqual(timer.remainingTime, 59 * 60, accuracy: 0.01)
    }

    func testKeepingSoundDoesNotCancelAFilmTimer() {
        armCameraTimer()
        XCTAssertTrue(holders.videoPlaying)

        supervisor.keepsSoundPlaying = true

        advance(60)
        XCTAssertTrue(timer.isTimerActive)
        XCTAssertEqual(timer.remainingTime, 4 * 60, accuracy: 0.01)
    }

    func testSoundPolicyAppliesWhenAFilmBecomesSoundOnly() {
        supervisor.keepsSoundPlaying = true
        armCameraTimer()

        holders = Self.sound
        supervisor.tick()

        XCTAssertEqual(supervisor.status, .keepingSound)
        assertCanceled()
    }

    func testCancellationRestoresVolumeAndInvalidatesFinalLook() throws {
        holders = Self.sound
        armCameraTimer()
        advance(241)
        XCTAssertTrue(timer.isInFinalPhase)
        XCTAssertTrue(supervisor.isLooking)
        let oldAnswer = pendingLook
        let volume = try XCTUnwrap(timer.volume as? FakeVolume)
        XCTAssertFalse(volume.fades.isEmpty)

        supervisor.keepsSoundPlaying = true

        XCTAssertFalse(timer.isTimerActive)
        XCTAssertFalse(supervisor.isLooking)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(volume.restores, 1)
        timer.startTimer(hours: 1)
        oldAnswer?(.awake)
        XCTAssertTrue(timer.isTimerActive)
        XCTAssertEqual(timer.totalTime, 3600)
    }

    func testReenablingWatchCanArmAgainWithoutNewInput() {
        armCameraTimer()
        supervisor.isEnabled = false
        XCTAssertFalse(timer.isTimerActive)

        supervisor.isEnabled = true
        supervisor.tick()
        XCTAssertNotNil(pendingLook)
        answer(.asleep)

        XCTAssertTrue(timer.isTimerActive)
        XCTAssertTrue(timer.stopsOnInput)
        XCTAssertEqual(looks, 2)
    }

    func testRestartingNapCanArmAgainWithoutNewInput() {
        clock = at(13, 0)
        supervisor.watchNow()
        armCameraTimer()
        supervisor.stopWatchingNow()
        XCTAssertFalse(timer.isTimerActive)

        supervisor.watchNow()
        supervisor.tick()
        answer(.asleep)

        XCTAssertTrue(timer.isTimerActive)
        XCTAssertTrue(timer.stopsOnInput)
        XCTAssertEqual(looks, 2)
    }

    func testChangingBackToStopSoundCanArmAgainWithoutNewInput() {
        holders = Self.sound
        armCameraTimer()
        supervisor.keepsSoundPlaying = true
        XCTAssertFalse(timer.isTimerActive)

        supervisor.keepsSoundPlaying = false
        supervisor.tick()
        answer(.asleep)

        XCTAssertTrue(timer.isTimerActive)
        XCTAssertTrue(timer.stopsOnInput)
        XCTAssertEqual(looks, 2)
    }

    func testDisablingWatchCancelsQuietAndStillWatchingTimers() {
        holders = .none
        idleFor(minutes: 20)
        XCTAssertEqual(timer.totalTime, 15 * 60)
        supervisor.isEnabled = false
        XCTAssertFalse(timer.isTimerActive)

        supervisor.isEnabled = true
        holders = Self.film
        supervisor.usesCamera = false
        idleFor(minutes: 120)
        XCTAssertTrue(timer.stopsOnInput)
        XCTAssertEqual(timer.totalTime, 60)
        supervisor.isEnabled = false
        XCTAssertFalse(timer.isTimerActive)
    }

    func testEndingANonexistentNapPreservesTheBedtimeTimer() {
        armCameraTimer()
        XCTAssertFalse(supervisor.isWatchingNow)

        supervisor.stopWatchingNow()

        XCTAssertTrue(timer.isTimerActive)
    }

    func testKeepingSoundInvalidatesAnUnfinishedDecisionLook() {
        holders = Self.sound
        idleFor(minutes: 10)
        XCTAssertTrue(supervisor.isLooking)

        supervisor.keepsSoundPlaying = true
        answer(.asleep)

        XCTAssertFalse(supervisor.isLooking)
        XCTAssertFalse(timer.isTimerActive)
        XCTAssertEqual(supervisor.status, .keepingSound)
    }

    func testKeepingSoundCancelsAStillWatchingTimerWithoutCamera() {
        holders = Self.sound
        supervisor.usesCamera = false
        idleFor(minutes: 120)
        XCTAssertEqual(timer.totalTime, 60)
        XCTAssertTrue(timer.stopsOnInput)

        supervisor.keepsSoundPlaying = true

        assertCanceled()
        XCTAssertEqual(looks, 0)
    }

    func testEndingNapCancelsAQuietTimer() {
        clock = at(13, 0)
        holders = .none
        supervisor.watchNow()
        idleFor(minutes: 20)
        XCTAssertEqual(timer.totalTime, 15 * 60)
        XCTAssertTrue(timer.stopsOnInput)

        supervisor.stopWatchingNow()

        assertCanceled()
    }

    func testBedtimeTakingOverANapPreservesItsTimer() {
        clock = at(20, 59)
        supervisor.watchNow()
        armCameraTimer()

        advance(60)
        supervisor.tick()

        XCTAssertFalse(supervisor.isWatchingNow)
        XCTAssertTrue(timer.isTimerActive)
        XCTAssertEqual(timer.remainingTime, 4 * 60, accuracy: 0.01)
    }

    func testCancellationReasonsReachTheJournal() throws {
        let journal = Journal.shared
        let (directory, enabled) = (journal.directory, journal.isEnabled)
        journal.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        journal.isEnabled = { true }
        defer {
            journal.flush()
            try? FileManager.default.removeItem(at: journal.directory)
            (journal.directory, journal.isEnabled) = (directory, enabled)
        }

        armCameraTimer()
        supervisor.isEnabled = false
        supervisor.isEnabled = true
        clock = at(13, 0)
        supervisor.watchNow()
        armCameraTimer()
        supervisor.stopWatchingNow()
        clock = at(23, 0)
        holders = Self.sound
        armCameraTimer()
        supervisor.keepsSoundPlaying = true

        journal.flush()
        let entries = try String(contentsOf: journal.fileURL, encoding: .utf8).split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        let reasons = entries.filter { $0["event"] as? String == "timer.stop" }
            .compactMap { $0["reason"] as? String }
        XCTAssertEqual(reasons, [TimerManager.StopReason.watchDisabled.rawValue,
                                 TimerManager.StopReason.napEnded.rawValue,
                                 TimerManager.StopReason.keepingSound.rawValue])
    }
}
