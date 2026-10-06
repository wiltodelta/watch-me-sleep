import XCTest
@testable import WatchMeSleepCore

/// Shapes measured on macOS 26 (2026-10-05); see `WakeHolderClassifier`.
final class WakeHolderClassifierTests: XCTestCase {
    private let own: pid_t = 1

    private func holder(_ pid: pid_t, _ name: String, _ type: String, _ path: String?) -> PowerAssertion {
        PowerAssertion(pid: pid, processName: name, type: type, processPath: path)
    }

    private var daemons: [PowerAssertion] {
        [
            holder(358, "powerd", "PreventUserIdleSystemSleep", "/System/Library/CoreServices/powerd.bundle/powerd"),
            holder(732, "sharingd", "PreventUserIdleSystemSleep", "/usr/libexec/sharingd"),
            holder(414, "WindowServer", "UserIsActive", "/System/Library/PrivateFrameworks/SkyLight.framework/x")
        ]
    }

    private func classify(_ extra: [PowerAssertion], audio: Set<pid_t>? = [], running: Bool = false) -> WakeHolders {
        WakeHolderClassifier.classify(daemons + extra, audioPIDs: audio, audioRunning: running, ownPID: own)
    }

    func testDaemonsAloneAreNothing() {
        XCTAssertEqual(classify([]), .none)
    }

    func testAVideoPlayerIsMedia() {
        let quickTime = holder(7843, "QuickTime Player", "PreventUserIdleDisplaySleep",
                               "/System/Applications/QuickTime Player.app/Contents/MacOS/QuickTime Player")
        // Under /System, but an app: its display assertion is a video someone may watch.
        XCTAssertEqual(classify([quickTime]), WakeHolders(mediaPlaying: true, work: []))
        let browser = holder(900, "Google Chrome", "PreventUserIdleDisplaySleep",
                             "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        XCTAssertEqual(classify([browser]), WakeHolders(mediaPlaying: true, work: []))
    }

    func testCaffeinateIsWorkNotMedia() {
        let caffeinate = [
            holder(10081, "caffeinate", "PreventUserIdleSystemSleep", "/usr/bin/caffeinate"),
            holder(10081, "caffeinate", "PreventUserIdleDisplaySleep", "/usr/bin/caffeinate")
        ]
        XCTAssertEqual(classify(caffeinate), WakeHolders(mediaPlaying: false, work: ["caffeinate"]))
    }

    func testAnAgentHoldingTheSystemIsWork() {
        let claude = holder(85353, "Claude", "NoIdleSleepAssertion", "/Applications/Claude.app/Contents/MacOS/Claude")
        XCTAssertEqual(classify([claude]).work, ["Claude"])
    }

    func testPlayingAudioIsMediaEvenWithItsOwnSystemAssertion() {
        let spotify = holder(500, "Spotify", "PreventUserIdleSystemSleep", "/Applications/Spotify.app/Contents/MacOS/Spotify")
        let coreaudiod = holder(536, "coreaudiod", "PreventUserIdleSystemSleep", "/usr/sbin/coreaudiod")
        XCTAssertEqual(classify([spotify, coreaudiod], audio: [500]), WakeHolders(mediaPlaying: true, work: []))
    }

    func testBefore142TheDeviceAnswersForAudio() {
        XCTAssertTrue(classify([], audio: nil, running: true).mediaPlaying)
        XCTAssertFalse(classify([], audio: nil, running: false).mediaPlaying)
    }

    func testOwnAssertionsAndOwnAudioAreIgnored() {
        let mine = holder(own, "WatchMeSleep", "PreventUserIdleSystemSleep", "/Applications/W.app/Contents/MacOS/W")
        XCTAssertEqual(classify([mine], audio: [own]), .none)
    }

    func testAnUnreadablePathCountsAsWork() {
        // Safer to keep the system up for unknown work than to cut it off.
        let unknown = holder(42, "mystery", "PreventUserIdleSystemSleep", nil)
        XCTAssertEqual(classify([unknown]).work, ["mystery"])
    }
}
