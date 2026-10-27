import XCTest
@testable import WatchMeSleepCore

@MainActor
final class NightWatchPolicyTests: XCTestCase {
    private let now = Date()
    private typealias Policy = NightWatchPolicy

    private func decide(
        idleMinutes: Double, media: Bool = true, camera: Bool = true,
        unavailable: Bool = false, nextLook: Date = .distantPast
    ) -> Policy.Decision {
        Policy.decide(Policy.Input(idle: idleMinutes * 60, mediaPlaying: media, cameraUsable: camera,
                                   cameraUnavailable: unavailable, lookDue: now >= nextLook))
    }

    func testCameraLooksAfterFiveMinutesOfMedia() {
        XCTAssertEqual(decide(idleMinutes: 4), .wait)
        XCTAssertEqual(decide(idleMinutes: 5), .look)
    }

    func testAQuietMacNeverUsesTheCamera() {
        XCTAssertEqual(decide(idleMinutes: 10, media: false), .wait, "Nothing playing: nothing to ask the camera")
        XCTAssertEqual(decide(idleMinutes: 20, media: false), .armQuietTimer)
    }

    func testCameraWaitsForTheNextLook() {
        XCTAssertEqual(decide(idleMinutes: 30, nextLook: now.addingTimeInterval(60)), .wait)
    }

    func testWithoutCameraAQuietMacArmsAfterTwentyMinutes() {
        XCTAssertEqual(decide(idleMinutes: 19, media: false, camera: false), .wait)
        XCTAssertEqual(decide(idleMinutes: 20, media: false, camera: false), .armQuietTimer)
    }

    func testWithoutCameraMediaAsksAfterTwoHours() {
        XCTAssertEqual(decide(idleMinutes: 119, camera: false), .wait)
        XCTAssertEqual(decide(idleMinutes: 120, camera: false), .askStillWatching)
    }

    func testAnUnavailableLookFallsBackToTheNoCameraRules() {
        XCTAssertEqual(decide(idleMinutes: 30, unavailable: true), .wait)
        XCTAssertEqual(decide(idleMinutes: 120, unavailable: true), .askStillWatching)
        XCTAssertEqual(decide(idleMinutes: 30, unavailable: false), .look)
    }

    func testOpenEyesStillUseTheRecheckIntervalAfterThreeHours() {
        XCTAssertEqual(decide(idleMinutes: 180, nextLook: .distantFuture), .wait)
        XCTAssertEqual(decide(idleMinutes: 185), .look)
        XCTAssertEqual(decide(idleMinutes: 180, camera: false), .askStillWatching)
    }
}
