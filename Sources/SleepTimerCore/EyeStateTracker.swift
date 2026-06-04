import Foundation

/// Pure, unit-testable sliding-window sleep/wake decision logic for camera mode.
///
/// `SleepDetectionManager` feeds one value per video frame -- the average Eye
/// Aspect Ratio when a face is found, or a "missed" signal when it is not -- and
/// translates the returned `Decision` into UI, timer, and notification side
/// effects. Keeping the thresholds, the sliding window, and the blink-versus-sleep
/// discrimination here, free of `DispatchQueue`/`TimerManager`/`NotificationCenter`,
/// makes them testable in isolation. The EAR math itself lives in `EyeAspectRatio`.
///
/// Not thread-safe: the owner serializes all access on its video-output queue,
/// exactly as it did when this state lived inline in the manager.
struct EyeStateTracker {
    /// The transition produced by folding one frame into the window.
    enum Decision: Equatable {
        /// The user just fell asleep (a long enough run of closed frames).
        case sleepDetected
        /// The user just woke (a full window that has mostly reopened).
        case wakeDetected
        /// No state transition this frame.
        case noChange
    }

    // MARK: - Configuration

    /// Number of frames the sliding window holds (~60 seconds at 10 fps).
    let windowSize: Int
    /// Closed fraction a full window needs to register sleep.
    let sleepThresholdPercent: Double
    /// Closed fraction at or below which a full window registers waking.
    let wakeThresholdPercent: Double
    /// Consecutive closed frames required before sleep can trigger. This is what
    /// separates a blink from sleep (~15 seconds at 10 fps).
    let minContinuousClosedFrames: Int
    /// Below this EAR the eyes count as closing (strict, no hysteresis).
    let earClosedThreshold: Double
    /// Above this EAR the eyes count as opening (the hysteresis ceiling).
    let earOpenThreshold: Double
    /// Consecutive missed frames tolerated before the window is dropped.
    let maxMissedFrames: Int

    // MARK: - State

    /// Whether the tracker currently considers the user asleep.
    private(set) var isAsleep = false
    /// Length of the current uninterrupted run of strictly-closed frames.
    private(set) var consecutiveClosedFrames = 0
    /// Running count of consecutive frames with no face/eyes detected.
    private(set) var missedFramesCount = 0
    /// Hysteresis display state: false = open, true = closed.
    private(set) var currentEyeState = false

    /// Sliding window of per-frame closed/open flags (true = closed).
    private var eyeStateWindow: [Bool] = []
    /// Cached count of closed frames in `eyeStateWindow`, maintained incrementally.
    private var closedFramesCount = 0

    // MARK: - Init

    init(
        windowSize: Int = 600,
        sleepThresholdPercent: Double = 0.90,
        wakeThresholdPercent: Double = 0.20,
        minContinuousClosedFrames: Int = 150,
        earClosedThreshold: Double = 0.20,
        earOpenThreshold: Double = 0.27,
        maxMissedFrames: Int? = nil
    ) {
        self.windowSize = windowSize
        self.sleepThresholdPercent = sleepThresholdPercent
        self.wakeThresholdPercent = wakeThresholdPercent
        self.minContinuousClosedFrames = minContinuousClosedFrames
        self.earClosedThreshold = earClosedThreshold
        self.earOpenThreshold = earOpenThreshold
        // Tolerance defaults to 25% of the window (~15 seconds at 10 fps for a 60-second window).
        self.maxMissedFrames = maxMissedFrames ?? Int(Double(windowSize) * 0.25)
    }

    // MARK: - Derived state (read by the owner for UI)

    /// Fraction of the current window in which eyes were closed (0 when empty).
    var closedPercentage: Double {
        eyeStateWindow.isEmpty ? 0.0 : Double(closedFramesCount) / Double(eyeStateWindow.count)
    }

    /// Number of frames currently in the window.
    var windowCount: Int { eyeStateWindow.count }

    /// Whether the window holds no frames yet.
    var isWindowEmpty: Bool { eyeStateWindow.isEmpty }

    // MARK: - Frame intake

    /// Folds a frame in which a face and both eyes were found into the window and
    /// returns the resulting transition. `ear` is the average Eye Aspect Ratio.
    mutating func record(ear: Double) -> Decision {
        // A detected face clears the missed-frame tolerance.
        missedFramesCount = 0

        // Hysteresis prevents display flicker: once closed, the eyes must rise clearly
        // above the open threshold to reopen; once open, they must drop clearly below
        // the closed threshold to close.
        if currentEyeState {
            currentEyeState = ear < earOpenThreshold
        } else {
            currentEyeState = ear < earClosedThreshold
        }

        // The window and the consecutive counter use the strict threshold (no
        // hysteresis) so a blink's partial reopening resets the run.
        return handleEyeState(closed: ear < earClosedThreshold)
    }

    /// Records a frame in which no face or eyes were found. Returns `true` once the
    /// missed-frame tolerance is exceeded and the window is dropped (the face is
    /// considered lost), so the owner can show the "looking for face" message. The
    /// asleep flag and the running missed-frame count are intentionally preserved.
    mutating func recordMissedFrame() -> Bool {
        missedFramesCount += 1
        guard missedFramesCount >= maxMissedFrames else { return false }

        eyeStateWindow.removeAll()
        closedFramesCount = 0
        currentEyeState = false
        // Reset the run so a lost face can't carry over into an early sleep trigger.
        consecutiveClosedFrames = 0
        return true
    }

    /// Clears all detection state, including the asleep flag and missed-frame count.
    mutating func reset() {
        eyeStateWindow.removeAll()
        closedFramesCount = 0
        missedFramesCount = 0
        currentEyeState = false
        consecutiveClosedFrames = 0
        isAsleep = false
    }

    // MARK: - Decision

    /// Appends one strict closed/open flag to the sliding window and evaluates the
    /// sleep and wake conditions.
    private mutating func handleEyeState(closed: Bool) -> Decision {
        // Track consecutive closed frames to distinguish blinks from sleep.
        if closed {
            consecutiveClosedFrames += 1
        } else {
            consecutiveClosedFrames = 0
        }

        // Slide the window, keeping the cached closed count in sync incrementally.
        if eyeStateWindow.count >= windowSize {
            let removed = eyeStateWindow.removeFirst()
            if removed { closedFramesCount -= 1 }
        }
        eyeStateWindow.append(closed)
        if closed { closedFramesCount += 1 }

        let windowFull = eyeStateWindow.count >= windowSize
        let hasEnoughConsecutive = consecutiveClosedFrames >= minContinuousClosedFrames
        let hasHighPercentage = closedPercentage >= sleepThresholdPercent

        // Sleep: a long enough run of closed frames, plus either a saturated window
        // meeting the percentage or a window that has not filled yet (early trigger).
        if !isAsleep && hasEnoughConsecutive && (hasHighPercentage || !windowFull) {
            isAsleep = true
            return .sleepDetected
        }

        // Wake: a full window that has mostly reopened.
        if isAsleep && windowFull && closedPercentage <= wakeThresholdPercent {
            isAsleep = false
            return .wakeDetected
        }

        return .noChange
    }
}
