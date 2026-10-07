import Foundation

/// What the night watch decides from one look at the signals. Pure and
/// side-effect free, so every rule is unit-tested without clocks or cameras.
///
/// The question is never "is the Mac idle" (macOS sleeps an idle Mac by itself)
/// but "is something keeping it awake that nobody is using any more".
enum NightWatchPolicy {
    // The job is to turn the screen off soon after someone falls asleep, so
    // the camera looks often: a look at open eyes ends in about 3 seconds.
    /// Media playing and no input this long: the camera takes its first look.
    static let firstLookIdle: TimeInterval = 5 * 60
    /// Wait before looking again after open eyes or an unclear picture.
    static let recheckInterval: TimeInterval = 5 * 60
    /// Nothing playing and no input this long means nobody is there. No camera
    /// here: with nothing playing, nobody is watching anything, and macOS would
    /// dim the display about now anyway.
    static let quietIdle: TimeInterval = 20 * 60
    /// Without a camera: media playing and no input this long, ask "still
    /// watching?". Long enough for a whole film; Netflix asks after 90 minutes,
    /// but counts episodes.
    static let stillWatchingIdle: TimeInterval = 2 * 60 * 60
    /// Even with the camera seeing open eyes, ask after this long: some people
    /// sleep with their eyes partly open, and the final minute spares anyone awake.
    static let askAnywayIdle: TimeInterval = 3 * 60 * 60
    /// Unclear looks in one idle stretch before the camera stops being trusted.
    static let maxUnclearLooks = 2
    /// Timer started once the camera sees closed eyes or nobody: short, because
    /// its final minute looks again and open eyes stop it.
    static let cameraTimer: TimeInterval = 5 * 60
    /// Timer started when nothing plays and nobody touches the Mac: no camera
    /// confirms it, so it leaves time to come back.
    static let quietTimer: TimeInterval = 15 * 60

    enum Decision: Equatable {
        case wait
        case look
        /// Start the quiet Mac's timer: nothing plays and nobody touches it.
        case armQuietTimer
        /// Go straight to the final minute: "still watching?".
        case askStillWatching
    }

    struct Input {
        var idle: TimeInterval
        var mediaPlaying: Bool
        var cameraUsable: Bool
        var unclearLooks: Int
        /// The recheck interval since the last look has passed.
        var lookDue: Bool

        /// The camera can answer: usable, and not unclear too often this stretch.
        var cameraTrusted: Bool { cameraUsable && unclearLooks < maxUnclearLooks }

        /// The camera answers only the one unclear case: something plays and
        /// nobody touches the Mac. Watching, or asleep in front of it?
        var cameraDecides: Bool { mediaPlaying && cameraTrusted }
    }

    static func decide(_ input: Input) -> Decision {
        if input.idle >= askAnywayIdle {
            return .askStillWatching
        }
        if input.cameraDecides {
            return input.idle >= firstLookIdle && input.lookDue ? .look : .wait
        }
        if !input.mediaPlaying {
            return input.idle >= quietIdle ? .armQuietTimer : .wait
        }
        return input.idle >= stillWatchingIdle ? .askStillWatching : .wait
    }
}
