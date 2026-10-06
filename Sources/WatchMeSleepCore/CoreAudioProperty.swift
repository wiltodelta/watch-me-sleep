import CoreAudio

/// Reads CoreAudio object properties, the one copy of the address and size
/// boilerplate `SystemVolumeFader` and `SystemSignals` share.
enum CoreAudioProperty {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// A fixed-size value (a number or an object id, never a reference), or
    /// nil when the object lacks the property.
    static func read<Value>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        as initial: Value
    ) -> Value? {
        var address = address(selector, scope: scope)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutableBytes(of: &value) { bytes in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, bytes.baseAddress!)
        }
        return status == noErr ? value : nil
    }

    static func defaultOutputDevice() -> AudioDeviceID? {
        let device = read(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
            as: AudioDeviceID(kAudioObjectUnknown)
        )
        return device == AudioDeviceID(kAudioObjectUnknown) ? nil : device
    }
}
