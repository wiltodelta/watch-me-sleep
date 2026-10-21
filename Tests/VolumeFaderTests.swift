import XCTest
import CoreAudio
@testable import WatchMeSleepCore

final class VolumeFaderTests: XCTestCase {
    private var output: AudioDeviceID? = 1
    private var volumes: [AudioDeviceID: Float32] = [1: 0.8, 2: 0.6]
    private var writes: [(AudioDeviceID, Float32)] = []

    private func makeFader() -> SystemVolumeFader {
        SystemVolumeFader(
            defaultOutputDevice: { self.output },
            readVolume: { self.volumes[$0] },
            writeVolume: { volume, device in
                self.writes.append((device, volume))
                guard self.volumes[device] != nil else { return false }
                self.volumes[device] = volume
                return true
            }
        )
    }

    func testChangingOutputRestoresOldDeviceAndFadesNewDevice() throws {
        let fader = makeFader()
        fader.fade(to: 0.5)
        XCTAssertEqual(try XCTUnwrap(volumes[1]), 0.4, accuracy: 0.001)

        output = 2
        fader.fade(to: 0.25)

        XCTAssertEqual(writes.map(\.0), [1, 1, 2])
        XCTAssertEqual(try XCTUnwrap(volumes[1]), 0.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(volumes[2]), 0.15, accuracy: 0.001)
        fader.restore()
        XCTAssertEqual(try XCTUnwrap(volumes[2]), 0.6, accuracy: 0.001)
    }

    func testChangingOutputPreservesManualVolumeOnTheOldDevice() throws {
        let fader = makeFader()
        fader.fade(to: 0.5)
        volumes[1] = 0.9

        output = 2
        fader.fade(to: 0.25)

        XCTAssertEqual(writes.map(\.0), [1, 2])
        XCTAssertEqual(try XCTUnwrap(volumes[1]), 0.9, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(volumes[2]), 0.15, accuracy: 0.001)
    }

    func testDisconnectingTheOldDeviceDoesNotPreventFadingItsReplacement() throws {
        let fader = makeFader()
        fader.fade(to: 0.5)
        volumes[1] = nil
        output = 2

        fader.fade(to: 0.25)

        XCTAssertNil(volumes[1], "A disconnected device cannot be written")
        XCTAssertEqual(try XCTUnwrap(volumes[2]), 0.15, accuracy: 0.001)
        fader.restore()
        XCTAssertEqual(try XCTUnwrap(volumes[2]), 0.6, accuracy: 0.001)
    }

    func testLosingAllOutputsRestoresThePreviousDevice() throws {
        let fader = makeFader()
        fader.fade(to: 0.5)
        output = nil

        fader.fade(to: 0.25)

        XCTAssertEqual(try XCTUnwrap(volumes[1]), 0.8, accuracy: 0.001)
        XCTAssertEqual(writes.map(\.0), [1, 1])
        fader.restore()
        XCTAssertEqual(writes.count, 2, "The old device was already released")
    }

    func testReturningToAPreviousOutputUsesItsOriginalVolume() throws {
        let fader = makeFader()
        fader.fade(to: 0.5)
        output = 2
        fader.fade(to: 0.25)
        output = 1

        fader.fade(to: 0.1)

        XCTAssertEqual(try XCTUnwrap(volumes[1]), 0.08, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(volumes[2]), 0.6, accuracy: 0.001)
        fader.restore()
        XCTAssertEqual(try XCTUnwrap(volumes[1]), 0.8, accuracy: 0.001)
    }
}
