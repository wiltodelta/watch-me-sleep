import XCTest
@testable import WatchMeSleepCore

final class PowerCommandTests: XCTestCase {
    func testSuccessfulExit() async {
        let result = await PowerCommand.run("unused", executable: URL(fileURLWithPath: "/usr/bin/true"))
        guard case .success = result else { return XCTFail("Exit zero must succeed") }
    }

    func testNonzeroExitIsFailure() async {
        let result = await PowerCommand.run("unused", executable: URL(fileURLWithPath: "/usr/bin/false"))
        guard case .failure(let failure) = result else { return XCTFail("Process launch alone is not success") }
        XCTAssertTrue(failure.message.contains("status 1"))
    }

    func testStderrIsIncluded() async {
        let missing = "/nonexistent-watch-me-sleep-test-input"
        let result = await PowerCommand.run(missing, executable: URL(fileURLWithPath: "/bin/ls"))
        guard case .failure(let failure) = result else { return XCTFail("Missing input must fail") }
        XCTAssertTrue(failure.message.contains(missing))
        XCTAssertTrue(failure.message.contains("status"))
    }

    func testLaunchFailure() async {
        let result = await PowerCommand.run("sleepnow", executable: URL(fileURLWithPath: "/nonexistent-power-command"))
        guard case .failure(let failure) = result else { return XCTFail("Missing executable must fail") }
        XCTAssertFalse(failure.message.isEmpty)
    }
}

@MainActor
final class PowerFailureRecoveryTests: XCTestCase {
    func testFailureRestoresVolumeAndReportsActualCommand() async {
        let manager = TimerManager.shared
        let originalCommand = manager.powerCommand
        let originalFeedback = manager.showPowerFailure
        let originalWork = manager.workHolders
        let originalVolume = manager.volume
        defer {
            manager.powerCommand = originalCommand
            manager.showPowerFailure = originalFeedback
            manager.workHolders = originalWork
            manager.volume = originalVolume
        }
        let volume = FakeVolume()
        manager.volume = volume
        manager.workHolders = { ["Synthetic work"] }
        volume.fade(to: 0.1)
        let reported = expectation(description: "Failure feedback")
        var commands: [String] = []
        manager.powerCommand = { command in
            commands.append(command)
            return await PowerCommand.run("unused", executable: URL(fileURLWithPath: "/usr/bin/false"))
        }
        manager.showPowerFailure = { command, message in
            XCTAssertEqual(command, "displaysleepnow")
            XCTAssertTrue(message.contains("status 1"))
            XCTAssertEqual(volume.restores, 1)
            reported.fulfill()
        }

        manager.putComputerToSleep(.unlessWorkHolds)
        await fulfillment(of: [reported], timeout: 5)

        XCTAssertEqual(commands, ["displaysleepnow"])
    }
}
