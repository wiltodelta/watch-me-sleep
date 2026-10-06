import AudioToolbox
import CoreAudio
import os

/// The volume side of the timer's final minute, as a seam so tests never touch
/// the real output device.
protocol VolumeControl: AnyObject {
    /// Set the output to `fraction` of the volume it had when the fade began.
    func fade(to fraction: Double)
    /// Put the volume back to where the fade found it.
    func restore()
}

/// Fades the default output device through CoreAudio, which needs no permission.
/// Devices without a settable volume (many HDMI and USB outputs) are left alone.
///
/// If the person changes the volume while it fades, they have taken over: the
/// fade stops and `restore()` leaves their setting in place.
final class SystemVolumeFader: VolumeControl {
    private var saved: (device: AudioDeviceID, volume: Float32)?
    private var lastSet: Float32?
    private let log = Logger.app("volume")

    /// Volume steps from the keyboard are 1/16; a device may round what we set
    /// to its own step, so only a larger difference counts as the person's.
    private let takeoverThreshold: Float32 = 0.03

    func fade(to fraction: Double) {
        if saved == nil {
            guard let device = CoreAudioProperty.defaultOutputDevice(),
                let volume = Self.volume(of: device) else { return }
            saved = (device, volume)
            log.info("Fading volume from \(volume, privacy: .public)")
        }
        guard let saved, !personTookOver(saved.device) else { return }

        let target = saved.volume * Float32(min(max(fraction, 0), 1))
        if Self.setVolume(target, of: saved.device) {
            lastSet = target
        }
    }

    func restore() {
        guard let saved else { return }
        defer {
            self.saved = nil
            lastSet = nil
        }
        if personTookOver(saved.device) {
            log.info("Volume changed during the fade; leaving it")
            return
        }
        if Self.setVolume(saved.volume, of: saved.device) {
            log.info("Restored volume to \(saved.volume, privacy: .public)")
        }
    }

    private func personTookOver(_ device: AudioDeviceID) -> Bool {
        guard let lastSet, let current = Self.volume(of: device) else { return false }
        return abs(current - lastSet) > takeoverThreshold
    }

    // MARK: - CoreAudio

    private static func volume(of device: AudioDeviceID) -> Float32? {
        CoreAudioProperty.read(device, volumeSelector, scope: kAudioDevicePropertyScopeOutput, as: Float32(0))
    }

    private static let volumeSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume

    @discardableResult
    private static func setVolume(_ volume: Float32, of device: AudioDeviceID) -> Bool {
        var address = CoreAudioProperty.address(volumeSelector, scope: kAudioDevicePropertyScopeOutput)
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            return false
        }
        var value = volume
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }
}
