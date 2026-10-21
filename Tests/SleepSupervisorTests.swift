import XCTest
import AppKit
@testable import WatchMeSleepCore

@MainActor
final class SleepSupervisorTests: SleepSupervisorTestCase {
    func testLookCompletingAfterBedtimeCannotArmTimer() {
        clock = at(7, 59).addingTimeInterval(50)
        idleFor(minutes: 10)
        XCTAssertTrue(supervisor.isLooking)
        XCTAssertNotNil(pendingLook)
        clock += 20
        idle += 20
        XCTAssertFalse(supervisor.isWithinWindow(clock))

        answer(.asleep)

        XCTAssertFalse(timer.isTimerActive)
        XCTAssertFalse(supervisor.isLooking)
    }

    func testEndingNapInvalidatesPendingLookEvenIfNapRestarts() {
        clock = at(13, 0)
        supervisor.watchNow()
        idleFor(minutes: 10)
        XCTAssertNotNil(pendingLook)
        supervisor.stopWatchingNow()
        supervisor.watchNow()

        answer(.asleep)

        XCTAssertFalse(timer.isTimerActive)
    }

    func testFinalMinuteDoesNotStartCameraOutsideBedtime() {
        clock = at(7, 59)
        idleFor(minutes: 10)
        answer(.asleep)
        XCTAssertTrue(timer.isTimerActive)
        clock += 241
        idle += 241

        timer.tick()

        XCTAssertTrue(timer.isInFinalPhase)
        XCTAssertEqual(looks, 1)
    }

    func testDisablingAndReenablingCameraInvalidatesPendingLook() {
        idleFor(minutes: 10)
        XCTAssertNotNil(pendingLook)
        supervisor.usesCamera = false
        supervisor.usesCamera = true

        answer(.asleep)

        XCTAssertFalse(timer.isTimerActive)
    }

    func testScheduleAndEnableChangesInvalidatePendingLook() {
        idleFor(minutes: 10)
        XCTAssertNotNil(pendingLook)
        supervisor.isEnabled = false
        supervisor.bedtimeEnd = 7 * 60
        supervisor.isEnabled = true
        supervisor.bedtimeEnd = 8 * 60

        answer(.asleep)

        XCTAssertFalse(timer.isTimerActive)
    }

    func testFinalMinuteAnswerAfterDisablingWatchDoesNotStopTimer() {
        idleFor(minutes: 10)
        answer(.asleep)
        clock += 241
        idle += 241
        timer.tick()
        XCTAssertNotNil(pendingLook)
        XCTAssertTrue(supervisor.isLooking)
        supervisor.isEnabled = false

        answer(.awake)

        XCTAssertTrue(timer.isTimerActive)
        XCTAssertFalse(supervisor.isLooking)
    }

    func testBedtimeIsMinutePrecise() {
        supervisor.bedtimeStart = 22 * 60 + 30
        supervisor.bedtimeEnd = 6 * 60 + 45
        XCTAssertFalse(supervisor.isWithinWindow(at(22, 29)))
        XCTAssertTrue(supervisor.isWithinWindow(at(22, 30)))
        XCTAssertTrue(supervisor.isWithinWindow(at(0, 0)), "Across midnight")
        XCTAssertTrue(supervisor.isWithinWindow(at(6, 44)))
        XCTAssertFalse(supervisor.isWithinWindow(at(6, 45)), "The end is exclusive")
        XCTAssertEqual(supervisor.bedtimeMinutes, 8 * 60 + 15)
    }

    func testADaytimeBedtimeWorksToo() {
        supervisor.bedtimeStart = 9 * 60
        supervisor.bedtimeEnd = 17 * 60
        XCTAssertTrue(supervisor.isWithinWindow(at(12, 0)), "Night shift sleepers")
        XCTAssertFalse(supervisor.isWithinWindow(at(23, 0)))
    }

    func testEqualTimesSayThereIsNoBedtime() {
        supervisor.bedtimeStart = 22 * 60
        supervisor.bedtimeEnd = 22 * 60
        idleFor(minutes: 5)
        XCTAssertEqual(supervisor.status, .noBedtime, "Not \"starts at 10 PM\": it never starts")
        XCTAssertEqual(supervisor.statusTitle, "Bedtime has no length")
    }

    func testATimerStartedOrStoppedUpdatesTheStatusWithoutActing() {
        supervisor.observeTimer()
        idle = 15 * 60 // In bedtime and idle long enough for a look, were it a tick.

        timer.startTimer(hours: 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(supervisor.status, .timerRunning)

        timer.stopTimer()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNotEqual(supervisor.status, .timerRunning)
        XCTAssertEqual(looks, 0, "Only the status: no look in the instant a timer ends")
    }

    func testTheTooltipTitleFollowsTheStatus() {
        supervisor.isEnabled = false
        idleFor(minutes: 1)
        XCTAssertEqual(supervisor.statusTitle, "Night watch is off")
        supervisor.isEnabled = true
        timer.startTimer(hours: 1)
        idleFor(minutes: 1)
        XCTAssertEqual(supervisor.statusTitle, "Sleep timer running")
    }

    func testEqualTimesMakeNoBedtime() {
        supervisor.bedtimeStart = 22 * 60
        supervisor.bedtimeEnd = 22 * 60
        XCTAssertFalse(supervisor.isWithinWindow(at(22, 0)))
        XCTAssertFalse(supervisor.isWithinWindow(at(3, 0)))
        XCTAssertEqual(supervisor.bedtimeMinutes, 0)
    }

    func testWholeHoursFromBeforeCarryOver() {
        let defaults = UserDefaults(suiteName: "BedtimeMigrationTests")!
        defer { defaults.removePersistentDomain(forName: "BedtimeMigrationTests") }
        let key = SleepSupervisor.Key.bedtimeStart, legacy = SleepSupervisor.Key.legacyStartHour

        XCTAssertNil(SleepSupervisor.storedMinutes(defaults, key: key, legacyHourKey: legacy))
        defaults.set(22, forKey: legacy)
        XCTAssertEqual(SleepSupervisor.storedMinutes(defaults, key: key, legacyHourKey: legacy), 22 * 60)
        defaults.set(22 * 60 + 30, forKey: key)
        XCTAssertEqual(SleepSupervisor.storedMinutes(defaults, key: key, legacyHourKey: legacy), 22 * 60 + 30,
                       "Minutes, once stored, win over the old hour")
    }

    func testInUseDoesNothing() {
        idleFor(minutes: 0.1)
        XCTAssertEqual(supervisor.status, .inUse)
        XCTAssertEqual(looks, 0)
    }

    func testOutsideBedtimeSaysSoEvenWhileInUse() {
        clock = clock.addingTimeInterval(-3 * 3600) // 20:00
        idleFor(minutes: 0.1)
        XCTAssertEqual(supervisor.status, .outsideHours)
    }

    func testOutsideBedtimeDoesNothing() {
        clock = clock.addingTimeInterval(-10 * 3600) // 13:00
        idleFor(minutes: 120)
        XCTAssertEqual(supervisor.status, .outsideHours)
        XCTAssertFalse(timer.isTimerActive)
    }

    func testClosedEyesStartAFiveMinuteTimer() {
        idleFor(minutes: 10)
        XCTAssertEqual(looks, 1)

        answer(.asleep)

        XCTAssertTrue(timer.isTimerActive)
        XCTAssertEqual(timer.totalTime, 5 * 60, accuracy: 1)
    }

    func testNobodyThereAfterAFaceStartsAFiveMinuteTimer() {
        idleFor(minutes: 10)
        answer(.awake)
        clock = clock.addingTimeInterval(5 * 60)
        idleFor(minutes: 15)
        answer(.absent)
        XCTAssertEqual(timer.totalTime, 5 * 60, accuracy: 1, "Seen, then gone: left, or asleep turned away")
    }

    func testNobodyEverSeenIsNotEvidence() {
        // A film on a TV, a laptop far away: the camera may not cover the viewer.
        idleFor(minutes: 10)
        answer(.absent)
        XCTAssertFalse(timer.isTimerActive)
        XCTAssertEqual(supervisor.stretch.unclearLooks, 1)
    }

    func testOpenEyesWaitFiveMinutes() {
        idleFor(minutes: 10)
        answer(.awake)
        XCTAssertFalse(timer.isTimerActive)

        clock = clock.addingTimeInterval(4 * 60)
        idleFor(minutes: 14)
        XCTAssertEqual(looks, 1)

        clock = clock.addingTimeInterval(60)
        idleFor(minutes: 15)
        XCTAssertEqual(looks, 2)
    }

    func testANoLongerUsableCameraFallsBackToStillWatching() {
        idleFor(minutes: 10)
        answer(.unavailable)

        idleFor(minutes: 119)
        XCTAssertFalse(timer.isTimerActive)
        idleFor(minutes: 120)
        XCTAssertEqual(timer.totalTime, TimerManager.finalPhaseDuration, accuracy: 1, "Straight to the final minute")
    }

    func testPersonBackDuringTheLookStartsNothing() {
        idleFor(minutes: 10)
        idle = 2
        answer(.asleep)
        XCTAssertFalse(timer.isTimerActive)
    }

    func testOneActionPerIdleStretch() {
        idleFor(minutes: 10)
        answer(.asleep)
        // The display went off for work; the timer is gone but nobody came back.
        timer.stopTimer()

        idleFor(minutes: 40)
        XCTAssertEqual(supervisor.status, .done)
        XCTAssertFalse(timer.isTimerActive)

        idleFor(minutes: 0)
        idleFor(minutes: 10)
        XCTAssertEqual(looks, 2, "Back at the Mac starts a new stretch")
    }

    func testOpenEyesInTheFinalMinuteKeepTheMacAwake() {
        idleFor(minutes: 10)
        answer(.asleep)
        clock = clock.addingTimeInterval(5 * 60 - 30)
        idle += 5 * 60 - 30 // Nobody touched the Mac meanwhile.
        timer.tick()
        XCTAssertTrue(timer.isInFinalPhase)

        XCTAssertEqual(looks, 2, "Entering the final minute asks at once, not at the next poll")
        answer(.awake)

        XCTAssertFalse(timer.isTimerActive, "Someone watching: the timer stops")
        XCTAssertFalse(slept)

        idleFor(minutes: 24)
        XCTAssertEqual(looks, 2)
        XCTAssertNotEqual(supervisor.status, .done, "Still watching over the film")
        clock = clock.addingTimeInterval(5 * 60)
        idleFor(minutes: 30)
        XCTAssertEqual(looks, 3, "Looks again five minutes later")
    }

    func testAManualTimerGetsNoFinalMinuteLook() {
        timer.startTimer(hours: 1)
        clock = clock.addingTimeInterval(3600 - 30)
        timer.tick()

        idleFor(minutes: 60)

        XCTAssertEqual(looks, 0)
    }

    func testUsingTheMacStopsTheNightWatchTimer() {
        idleFor(minutes: 10)
        answer(.asleep)
        XCTAssertTrue(timer.stopsOnInput)

        clock = clock.addingTimeInterval(3 * 60)
        idle = 2 // Mid-timer, long before the final minute.
        timer.tick()
        XCTAssertFalse(timer.isTimerActive, "It started because nobody seemed there")
        supervisor.tick()
        XCTAssertEqual(supervisor.status, .inUse)
    }

    func testInputBeforeTheNightWatchTimerDoesNotStopIt() {
        idleFor(minutes: 10)
        answer(.asleep)
        clock = clock.addingTimeInterval(60)
        idle = 11 * 60
        timer.tick()
        XCTAssertTrue(timer.isTimerActive)
    }

    func testUsingTheMacKeepsAManualTimer() {
        timer.startTimer(hours: 1)
        clock = clock.addingTimeInterval(60)
        idle = 2
        timer.tick()
        XCTAssertTrue(timer.isTimerActive)
    }

    func testAQuietMacTimerGetsNoFinalMinuteLook() {
        holders = .none
        idleFor(minutes: 20)
        XCTAssertTrue(timer.isTimerActive)
        clock = clock.addingTimeInterval(15 * 60 - 30)
        timer.tick()
        XCTAssertTrue(timer.isInFinalPhase)
        XCTAssertEqual(looks, 0, "A quiet Mac never turns the camera on")
    }

    func testStillWatchingAfterThreeHoursIsNotAnsweredByOpenEyes() {
        // The camera keeps seeing open eyes, so the night watch asks anyway at
        // three hours; open eyes cannot answer that question, only input can.
        idleFor(minutes: 180)
        XCTAssertEqual(timer.totalTime, TimerManager.finalPhaseDuration, accuracy: 1)
        timer.tick()
        XCTAssertTrue(timer.isInFinalPhase)
        XCTAssertEqual(looks, 0)

        clock = clock.addingTimeInterval(60)
        idle = 181 * 60
        timer.tick()
        XCTAssertTrue(slept)
    }

    func testWatchNowWorksOutsideBedtime() {
        clock = clock.addingTimeInterval(-10 * 3600) // 13:00
        idleFor(minutes: 10)
        XCTAssertEqual(supervisor.status, .outsideHours)
        XCTAssertEqual(looks, 0)

        supervisor.watchNow()
        idleFor(minutes: 10)
        XCTAssertEqual(looks, 1, "A nap is watched like a night")
    }

    func testTheNapEndsWhenTheMacSleeps() {
        clock = clock.addingTimeInterval(-10 * 3600) // 13:00
        supervisor.watchNow()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertFalse(supervisor.isWatchingNow)

        idleFor(minutes: 10)
        XCTAssertEqual(supervisor.status, .outsideHours)
        XCTAssertEqual(looks, 0)
    }

    func testBedtimeTakesOverANap() {
        clock = at(20, 50)
        supervisor.watchNow()
        idleFor(minutes: 1)
        XCTAssertTrue(supervisor.isWatchingNow)

        clock = at(21, 0)
        idleFor(minutes: 2)
        XCTAssertFalse(supervisor.isWatchingNow, "From bedtime on it watches as at night")
    }

    func testSoundKeptPlayingWhenChosen() {
        holders = Self.sound
        supervisor.keepsSoundPlaying = true
        idleFor(minutes: 200)
        XCTAssertEqual(supervisor.status, .keepingSound)
        XCTAssertEqual(looks, 0)
        XCTAssertFalse(timer.isTimerActive, "Not even the three-hour question")
    }

    func testAFilmIsWatchedEvenWhenSoundIsKept() {
        holders = Self.film
        supervisor.keepsSoundPlaying = true
        idleFor(minutes: 10)
        XCTAssertEqual(looks, 1)
    }

    func testThePanelHearsSoundOnlyWhileInUse() {
        holders = Self.sound
        idleFor(minutes: 0)
        XCTAssertTrue(supervisor.isSoundOnlyPlaying, "Opening the panel is input; the choice must still show")
        holders = Self.film
        idleFor(minutes: 0)
        XCTAssertFalse(supervisor.isSoundOnlyPlaying)
    }

    func testMediaStartingCancelsTheQuietTimer() {
        holders = .none
        idleFor(minutes: 20)
        XCTAssertTrue(timer.isTimerActive)

        holders = Self.film
        idleFor(minutes: 21)
        XCTAssertEqual(looks, 1, "Something plays now: the camera decides instead")
        XCTAssertFalse(timer.isTimerActive)
    }

    func testInputDuringALookOutdatesItsAnswer() {
        idleFor(minutes: 10)
        clock = clock.addingTimeInterval(40)
        idle = 35 // Touched 5 s into the 40 s look, then left alone.
        answer(.asleep)
        XCTAssertFalse(timer.isTimerActive)
    }

    func testADarkLookDoesNotCountAsASeenFace() {
        // A dark scene during the first look, then a lit frame with nobody:
        // the camera still never saw the viewer.
        idleFor(minutes: 10)
        answer(.unclear)
        clock = clock.addingTimeInterval(5 * 60)
        idleFor(minutes: 15)
        answer(.absent)
        XCTAssertFalse(timer.isTimerActive)
    }

    func testANightLeavesItsDecisionsInTheJournal() throws {
        let journal = Journal.shared
        let (directory, enabled) = (journal.directory, journal.isEnabled)
        journal.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        journal.isEnabled = { true }
        defer {
            try? FileManager.default.removeItem(at: journal.directory)
            (journal.directory, journal.isEnabled) = (directory, enabled)
        }

        idleFor(minutes: 10)
        answer(.asleep)

        journal.flush()
        let entries = try String(contentsOf: journal.fileURL, encoding: .utf8).split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        let events = entries.compactMap { $0["event"] as? String }
        let result = entries.first { $0["event"] as? String == "look.result" }
        XCTAssertEqual(result?["verdict"] as? String, "asleep")
        XCTAssertEqual(result?["media"] as? Bool, true)
        XCTAssertEqual(result?["idle"] as? Int, 600)
        XCTAssertTrue(events.contains("arm") && events.contains("timer.start"), "\(events)")
    }
}
