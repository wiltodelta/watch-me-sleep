import Foundation
import AVFoundation
import os

/// A short camera look that auto-start takes before arming a timer, so an idle
/// Mac with someone watching a film is not put to sleep, while a dark room or an
/// empty chair still counts as bedtime.
///
/// Pure and frame-driven like `EyeStateTracker`, which it reuses for the
/// blink-versus-sleep decision; `SleepDetectionManager` feeds it one value per
/// video frame on its video queue. Not thread-safe for the same reason.
struct PresenceCheck {
    enum Verdict: Equatable {
        /// Eyes stayed closed long enough to count as sleep.
        case asleep
        /// No face for almost the whole look: nobody there, or too dark to see.
        case absent
        /// Eyes open, or nothing conclusive: look again later.
        case awake
        /// The camera could not be used (no access, no frames, camera mode took it).
        case unavailable
    }

    /// Frames in the whole look (~30 seconds at 10 fps).
    let maxFrames: Int
    /// Open-eye frames that settle it as awake (~3 seconds at 10 fps, blinks aside).
    let openFramesForAwake: Int
    /// Share of the look with a face at or below which nobody counts as there.
    let absentFaceShare: Double

    private var tracker: EyeStateTracker
    private(set) var frames = 0
    private var faceFrames = 0
    private var openFrames = 0

    init(maxFrames: Int = 300, openFramesForAwake: Int = 30, absentFaceShare: Double = 0.1,
         tracker: EyeStateTracker = EyeStateTracker()) {
        self.maxFrames = maxFrames
        self.openFramesForAwake = openFramesForAwake
        self.absentFaceShare = absentFaceShare
        self.tracker = tracker
    }

    /// A frame with a face and both eyes; `ear` is their average Eye Aspect Ratio.
    /// Returns the verdict once there is one.
    mutating func record(ear: Double) -> Verdict? {
        frames += 1
        faceFrames += 1
        if tracker.record(ear: ear) == .sleepDetected {
            return .asleep
        }
        if ear >= tracker.earOpenThreshold {
            openFrames += 1
            if openFrames >= openFramesForAwake {
                return .awake
            }
        }
        return verdictIfDone()
    }

    /// A frame with no face or eyes found.
    mutating func recordMissedFrame() -> Verdict? {
        frames += 1
        _ = tracker.recordMissedFrame()
        return verdictIfDone()
    }

    /// The verdict for a look cut short, or one that ran its full length.
    var finalVerdict: Verdict {
        guard frames > 0 else { return .unavailable }
        return Double(faceFrames) <= Double(frames) * absentFaceShare ? .absent : .awake
    }

    private func verdictIfDone() -> Verdict? {
        frames >= maxFrames ? finalVerdict : nil
    }
}

// MARK: - Running a check on the camera

extension SleepDetectionManager {
    /// Longest a check may hold the camera, frames or not; a camera that never
    /// delivers (lid closed, taken by another app) ends as `.unavailable`.
    private static let presenceCheckTimeout: TimeInterval = 45

    /// Takes a short look with the camera and reports what it saw on main. Never
    /// asks for camera access: a prompt at night, unasked, would be worse than
    /// no check, so without access the verdict is `.unavailable`.
    func checkPresence(completion: @escaping (PresenceCheck.Verdict) -> Void) {
        // One look at a time is the caller's to keep (`AutoActivationManager`).
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized, !isCameraModeEnabled else {
            completion(.unavailable)
            return
        }

        isCheckingPresence = true
        presenceGeneration += 1
        let generation = presenceGeneration
        Logger.app("presence").info("Checking with the camera before auto-start")

        videoOutputQueue.async {
            self.presenceCheck = PresenceCheck()
            self.presenceCompletion = completion
            self.startSessionIfNeeded()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.presenceCheckTimeout) { [weak self] in
            guard let self, self.presenceGeneration == generation else { return }
            self.videoOutputQueue.async {
                self.finishPresenceCheck(self.presenceCheck?.finalVerdict ?? .unavailable)
            }
        }
    }

    /// Camera mode wants the camera: end any check without a verdict to act on.
    func cancelPresenceCheck() {
        guard isCheckingPresence else { return }
        videoOutputQueue.async {
            self.finishPresenceCheck(.unavailable)
        }
    }

    /// One frame into the running check. Runs on the video queue.
    func recordPresence(ear: Double?) {
        guard var check = presenceCheck else { return }
        let verdict: PresenceCheck.Verdict?
        if let ear {
            verdict = check.record(ear: ear)
        } else {
            verdict = check.recordMissedFrame()
        }
        presenceCheck = check
        if let verdict {
            finishPresenceCheck(verdict)
        }
    }

    /// Runs on the video queue.
    private func finishPresenceCheck(_ verdict: PresenceCheck.Verdict) {
        guard let completion = presenceCompletion else { return }
        let frames = presenceCheck?.frames ?? 0
        presenceCheck = nil
        presenceCompletion = nil
        if !isCameraModeEnabled {
            stopSession()
        }
        Logger.app("presence").info(
            "Camera check: \(String(describing: verdict), privacy: .public) after \(frames) frames"
        )
        DispatchQueue.main.async {
            self.isCheckingPresence = false
            completion(verdict)
        }
    }
}
