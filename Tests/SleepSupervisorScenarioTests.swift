import XCTest
@testable import WatchMeSleepCore

@MainActor
final class SleepSupervisorScenarioTests: SleepSupervisorTestCase {
    private let verdicts: [PresenceCheck.Verdict] = [.awake, .asleep, .absent, .unclear, .unavailable]

    private func resetScenario() {
        timer.stopTimer()
        supervisor.invalidateLook()
        supervisor.stretch = .init()
        clock = at(23, 0)
        idle = 0
        looks = 0
        pendingLook = nil
        slept = false
    }

    func testEveryDecisionAndFinalMinuteVerdictCombination() {
        for decision in verdicts {
            for final in verdicts {
                resetScenario()
                let scenario = "Decision: \(decision), final minute: \(final)"
                idleFor(minutes: 10)
                answer(decision)
                let shouldArm = decision != .awake && decision != .unavailable
                XCTAssertEqual(timer.isTimerActive, shouldArm, scenario)
                guard shouldArm else { continue }

                clock += 4 * 60
                idle += 4 * 60
                timer.tick()
                XCTAssertEqual(looks, 2, scenario)
                answer(final)
                XCTAssertEqual(timer.isTimerActive, final != .awake, scenario)

                clock += 60
                idle += 60
                timer.tick()
                XCTAssertEqual(slept, final != .awake, scenario)
            }
        }
    }

    func testInputOutdatesEveryDecisionVerdict() {
        for verdict in verdicts {
            resetScenario()
            idleFor(minutes: 10)
            clock += 5
            idle = 1
            answer(verdict)
            XCTAssertFalse(timer.isTimerActive, "Stale verdict: \(verdict)")
            XCTAssertFalse(slept)
        }
    }

    func testEveryAutomaticCameraTimerStopsOnInput() {
        for verdict in [PresenceCheck.Verdict.asleep, .absent, .unclear] {
            resetScenario()
            idleFor(minutes: 10)
            answer(verdict)
            clock += 60
            idle = 1
            timer.tick()
            XCTAssertFalse(timer.isTimerActive, "Timer from: \(verdict)")
            clock += 5 * 60
            idle += 5 * 60
            timer.tick()
            XCTAssertFalse(slept)
        }
    }
}
