import Foundation
import os

/// A short camera look the night watch (`SleepSupervisor`) takes when it is
/// unclear whether anyone is still watching, so a film someone is awake for is
/// not cut off, while a dark room or an empty chair still counts as bedtime.
///
/// Pure and frame-driven: `CameraWatcher` feeds it one value per video frame
/// on its video queue, which serializes all access.
struct PresenceCheck {
    enum Verdict: Equatable {
        /// Eyes stayed closed long enough to count as sleep.
        case asleep
        /// No face for almost the whole look: nobody there, or too dark to see.
        case absent
        /// Eyes open.
        case awake
        /// A face, but too little of it to tell (seen only briefly, closed eyes
        /// broken up by a lost face): not to be taken for either.
        case unclear
        /// The camera could not be used (no access, no frames).
        case unavailable
    }

    /// The whole look.
    let lookSeconds: TimeInterval
    /// Open eyes for this long in total settle it as awake, blinks aside.
    let openSecondsForAwake: TimeInterval
    /// Share of the look with a face at or below which nobody counts as there.
    let absentFaceShare: Double
    /// Eyes closed without a break for this long is sleep, not a blink.
    let closedSecondsForAsleep: TimeInterval
    /// A lost face tolerated inside a closed-eye run before it starts over: a
    /// head moving on the pillow should not undo it, a face gone for long should.
    let missedSecondsTolerated: TimeInterval

    /// Below this Eye Aspect Ratio the eyes count as closed, at or above it as
    /// open. Measured live (2026-10-05, built-in camera, `.low` preset): open
    /// eyes looking at the screen ran 0.20-0.26, median 0.234, never 0.27;
    /// blinks dropped to 0.03.
    static let earClosedThreshold = 0.20
    /// A longer gap between frames counts as this much, so one stall cannot
    /// settle a verdict on its own.
    static let maxFrameGap: TimeInterval = 0.5

    // Durations, not frame counts: the built-in camera delivered ~14 fps where
    // 10 were asked (measured 2026-10-05), and auto exposure can slow it in
    // the dark.
    private(set) var frames = 0
    private var lastFrame: TimeInterval?
    private var elapsed: TimeInterval = 0
    private var faceSeconds: TimeInterval = 0
    private var openSeconds: TimeInterval = 0
    private var closedRun: TimeInterval = 0
    private var missedRun: TimeInterval = 0

    init(lookSeconds: TimeInterval = 30, openSecondsForAwake: TimeInterval = 3, absentFaceShare: Double = 0.1,
         closedSecondsForAsleep: TimeInterval = 15, missedSecondsTolerated: TimeInterval = 15) {
        self.lookSeconds = lookSeconds
        self.openSecondsForAwake = openSecondsForAwake
        self.absentFaceShare = absentFaceShare
        self.closedSecondsForAsleep = closedSecondsForAsleep
        self.missedSecondsTolerated = missedSecondsTolerated
    }

    /// One frame at `time` (seconds, any steady clock): `ear` is the eyes'
    /// average aspect ratio, or nil when no face with both eyes was found.
    /// Returns the verdict once there is one.
    mutating func record(ear: Double?, at time: TimeInterval) -> Verdict? {
        // A frame stands for the time since the one before it.
        let span = lastFrame.map { min(max(time - $0, 0), Self.maxFrameGap) } ?? 0
        lastFrame = time
        frames += 1
        elapsed += span

        if let ear {
            faceSeconds += span
            missedRun = 0
            if ear < Self.earClosedThreshold {
                closedRun += span
                if reached(closedRun, closedSecondsForAsleep) { return .asleep }
            } else {
                // Any reopening breaks the run: that was a blink.
                closedRun = 0
                openSeconds += span
                if reached(openSeconds, openSecondsForAwake) { return .awake }
            }
        } else {
            missedRun += span
            if reached(missedRun, missedSecondsTolerated) {
                closedRun = 0
            }
        }
        return reached(elapsed, lookSeconds) ? finalVerdict : nil
    }

    /// Durations are sums of frame gaps, so allow for floating-point error.
    private func reached(_ value: TimeInterval, _ limit: TimeInterval) -> Bool {
        value >= limit - 0.001
    }

    /// The verdict for a look cut short, or one that ran its full length.
    var finalVerdict: Verdict {
        guard frames > 0 else { return .unavailable }
        return faceSeconds <= elapsed * absentFaceShare ? .absent : .unclear
    }
}

// MARK: - Running a check on the camera

extension CameraWatcher {
    /// Longest a look may hold the camera, frames or not; a camera that never
    /// delivers (lid closed, taken by another app) ends as `.unavailable`.
    private static let presenceCheckTimeout: TimeInterval = 45

    /// Takes a short look and reports what it saw, on main. Never asks for
    /// camera access: a prompt at night, unasked, would be worse than no look,
    /// so without access the verdict is `.unavailable`. One look at a time is
    /// the caller's to keep (`SleepSupervisor`).
    func checkPresence(completion: @escaping (PresenceCheck.Verdict) -> Void) {
        guard Self.isAuthorized else {
            completion(.unavailable)
            return
        }

        presenceGeneration += 1
        let generation = presenceGeneration
        Logger.app("presence").info("Looking with the camera")

        videoOutputQueue.async {
            self.presenceCheck = PresenceCheck()
            self.presenceCompletion = completion
        }
        acquire(.look)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.presenceCheckTimeout) { [weak self] in
            guard let self, self.presenceGeneration == generation else { return }
            self.videoOutputQueue.async {
                self.finishPresenceCheck(self.presenceCheck?.finalVerdict ?? .unavailable)
            }
        }
    }

    /// One frame into the running look, if there is one. Runs on the video queue.
    func recordPresence(ear: Double?, at time: TimeInterval) {
        guard let verdict = presenceCheck?.record(ear: ear, at: time) else { return }
        finishPresenceCheck(verdict)
    }

    /// Runs on the video queue.
    private func finishPresenceCheck(_ verdict: PresenceCheck.Verdict) {
        guard let completion = presenceCompletion else { return }
        let frames = presenceCheck?.frames ?? 0
        presenceCheck = nil
        presenceCompletion = nil
        Logger.app("presence").info(
            "Camera look: \(String(describing: verdict), privacy: .public) after \(frames) frames"
        )
        DispatchQueue.main.async {
            self.release(.look)
            completion(verdict)
        }
    }
}
