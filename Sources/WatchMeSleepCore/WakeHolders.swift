import CoreAudio
import Darwin
import Foundation
import IOKit
import IOKit.pwr_mgt

/// What is keeping the Mac awake, sorted into the two kinds the night watch
/// treats differently: media someone may be watching or hearing, and work
/// someone asked the Mac to finish.
public struct WakeHolders: Equatable {
    /// Audio is playing, or an app holds the display on as a video player does.
    public var mediaPlaying: Bool
    /// Processes holding the system itself awake (`caffeinate`, a download, a
    /// build, an agent). Sleeping the Mac would cut them off, so the night watch
    /// only turns the display off while any is present.
    public var work: [String]
    /// An app holds the display on, as a video player does.
    public var videoPlaying = false

    /// Sound with no video: a podcast, an audiobook, white noise.
    public var soundOnly: Bool { mediaPlaying && !videoPlaying }

    public static let none = WakeHolders(mediaPlaying: false, work: [])
}

/// One power assertion, reduced to what classification reads.
struct PowerAssertion: Equatable {
    let pid: pid_t
    let processName: String
    let type: String
    /// The holder's executable; nil when it could not be read.
    let processPath: String?
}

/// Sorts assertions by properties macOS reports, never by app name. Measured on
/// macOS 26 (2026-10-05): a playing video holds only `PreventUserIdleDisplaySleep`
/// under the player's own pid (QuickTime); playing audio shows up as the
/// player's pid in CoreAudio's process list plus a `coreaudiod` system
/// assertion; `caffeinate` and Electron apps hold system assertions of their own.
enum WakeHolderClassifier {
    static let systemTypes: Set<String> = [
        "PreventUserIdleSystemSleep", "NoIdleSleepAssertion", "PreventSystemSleep"
    ]
    static let displayTypes: Set<String> = [
        "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"
    ]

    /// macOS's own daemons hold assertions for their own reasons (Handoff,
    /// "display is on", audio routing); none of them is the person's media or
    /// work. Apps are never daemons, Apple's included: QuickTime, TV and Music
    /// live under /System/Applications, and Finder copying files is work.
    static func isSystemDaemon(_ path: String?) -> Bool {
        guard let path, !path.contains(".app/") else { return false }
        return ["/System/", "/usr/libexec/", "/usr/sbin/"].contains { path.hasPrefix($0) }
    }

    /// - Parameters:
    ///   - audioPIDs: processes playing audio, or nil where Core Audio cannot
    ///     list them; `audioRunning` answers for the device then.
    static func classify(
        _ assertions: [PowerAssertion],
        audioPIDs: Set<pid_t>?,
        audioRunning: Bool,
        ownPID: pid_t = getpid()
    ) -> WakeHolders {
        let personal = assertions.filter { $0.pid != ownPID && !isSystemDaemon($0.processPath) }
        let holdsSystem = Set(personal.filter { systemTypes.contains($0.type) }.map(\.pid))
        let holdsDisplay = Set(personal.filter { displayTypes.contains($0.type) }.map(\.pid))
        let playing = (audioPIDs ?? []).subtracting([ownPID])

        let videoOnly = holdsDisplay.subtracting(holdsSystem)
        let mediaPlaying = !playing.isEmpty || (audioPIDs == nil && audioRunning) || !videoOnly.isEmpty

        let workPIDs = holdsSystem.subtracting(playing)
        let work = personal
            .filter { workPIDs.contains($0.pid) }
            .map(\.processName)
        // While media plays, any display hold counts as video, also from an app
        // that holds the system too: sound-only must never take a film for a
        // podcast. Without media it is `caffeinate -d`, not a video.
        return WakeHolders(mediaPlaying: mediaPlaying, work: Array(Set(work)).sorted(),
                           videoPlaying: mediaPlaying && !holdsDisplay.isEmpty)
    }
}

/// Reads the live signals. None of them needs a permission.
enum SystemSignals {
    /// Seconds since the last user input, read from the IOHIDSystem `HIDIdleTime`
    /// property (reported in nanoseconds).
    static func idleSeconds() -> TimeInterval {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDSystem")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let dict = properties?.takeRetainedValue() as? [String: Any],
            let idleNanoseconds = dict["HIDIdleTime"] as? UInt64 else {
            return 0
        }

        return TimeInterval(idleNanoseconds) / 1_000_000_000.0
    }

    static func wakeHolders() -> WakeHolders {
        let audioPIDs = audioPlayingPIDs()
        return WakeHolderClassifier.classify(
            powerAssertions(),
            audioPIDs: audioPIDs,
            // Only asked where the process list cannot answer.
            audioRunning: audioPIDs == nil && defaultOutputIsRunning()
        )
    }

    // MARK: - Power assertions

    static func powerAssertions() -> [PowerAssertion] {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
            let dict = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            return []
        }
        return dict.flatMap { pid, list in
            let path = executablePath(of: pid.int32Value)
            return list.map { assertion in
                PowerAssertion(
                    pid: pid.int32Value,
                    processName: assertion["Process Name"] as? String ?? "pid \(pid)",
                    type: assertion["AssertType"] as? String ?? "",
                    processPath: path
                )
            }
        }
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Audio

    /// Processes playing audio right now, or nil when Core Audio cannot list them.
    static func audioPlayingPIDs() -> Set<pid_t>? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = CoreAudioProperty.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return nil }

        return Set(objects.compactMap { object -> pid_t? in
            guard CoreAudioProperty.read(object, kAudioProcessPropertyIsRunningOutput, as: UInt32(0)) ?? 0 != 0 else {
                return nil
            }
            return CoreAudioProperty.read(object, kAudioProcessPropertyPID, as: pid_t(0))
        })
    }

    /// Whether the default output device plays for anyone; the fallback when
    /// the process list cannot answer.
    static func defaultOutputIsRunning() -> Bool {
        guard let device = CoreAudioProperty.defaultOutputDevice() else { return false }
        return CoreAudioProperty.read(device, kAudioDevicePropertyDeviceIsRunningSomewhere, as: UInt32(0)) ?? 0 != 0
    }
}
