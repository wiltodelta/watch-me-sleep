import XCTest
@testable import WatchMeSleepCore

@MainActor
final class SleepSupervisorCancellationTests: SleepSupervisorTestCase {
    func testDisablingCameraEndsTheRunningLookImmediately() {
        idleFor(minutes: 10)
        XCTAssertTrue(supervisor.isLooking)
        XCTAssertEqual(cancellations, 0)

        supervisor.usesCamera = false

        XCTAssertFalse(supervisor.isLooking)
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(timer.isTimerActive)
    }

    func testDisablingWatchCancelsTheRunningLook() {
        idleFor(minutes: 10)
        XCTAssertTrue(supervisor.isLooking)

        supervisor.isEnabled = false

        XCTAssertFalse(supervisor.isLooking)
        XCTAssertEqual(cancellations, 1)
        answer(.asleep)
        XCTAssertFalse(timer.isTimerActive)
    }

    func testEndingNapCancelsTheLookAndAllowsANewOne() {
        clock = at(13, 0)
        supervisor.watchNow()
        idleFor(minutes: 10)
        XCTAssertTrue(supervisor.isLooking)
        let oldAnswer = pendingLook

        supervisor.stopWatchingNow()
        XCTAssertFalse(supervisor.isLooking)
        XCTAssertEqual(cancellations, 1)
        supervisor.watchNow()
        supervisor.tick()
        XCTAssertEqual(looks, 2)
        XCTAssertTrue(supervisor.isLooking)

        oldAnswer?(.asleep)
        XCTAssertTrue(supervisor.isLooking, "A stale answer cannot clear the new look's state")
        XCTAssertFalse(timer.isTimerActive)
        answer(.awake)
        XCTAssertFalse(supervisor.isLooking)
    }

    func testBedtimeEndingCancelsALookOnTheNextPoll() {
        clock = at(7, 59).addingTimeInterval(50)
        idleFor(minutes: 10)
        XCTAssertTrue(supervisor.isLooking)

        clock += 20
        idle += 20
        supervisor.tick()

        XCTAssertEqual(supervisor.status, .outsideHours)
        XCTAssertFalse(supervisor.isLooking)
        XCTAssertEqual(cancellations, 1)
        answer(.asleep)
        XCTAssertFalse(timer.isTimerActive)
    }

    func testInputCancelsTheLookOnTheNextPoll() {
        idleFor(minutes: 10)
        XCTAssertTrue(supervisor.isLooking)

        idleFor(minutes: 0)

        XCTAssertEqual(supervisor.status, .inUse)
        XCTAssertFalse(supervisor.isLooking)
        XCTAssertEqual(cancellations, 1)
    }

    func testSleepEndsALookEvenWhenThereIsNoNap() {
        idleFor(minutes: 10)
        XCTAssertTrue(supervisor.isLooking)
        XCTAssertFalse(supervisor.isWatchingNow)

        supervisor.stopWatchingNow() // The workspace sleep notification's handler.

        XCTAssertFalse(supervisor.isLooking)
        XCTAssertEqual(cancellations, 1)
    }

    func testPartialCameraTimeoutCannotArmEvenAfterSeeingAFace() {
        supervisor.stretch.faceSeen = true
        idleFor(minutes: 10)
        XCTAssertTrue(supervisor.isLooking)
        var check = PresenceCheck()
        XCTAssertNil(check.record(eyes: .open, at: 0, luma: 0.5))

        answer(check.finalVerdict)

        XCTAssertFalse(timer.isTimerActive)
        XCTAssertFalse(slept)
        XCTAssertEqual(supervisor.stretch.unclearLooks, NightWatchPolicy.maxUnclearLooks)
    }
}
