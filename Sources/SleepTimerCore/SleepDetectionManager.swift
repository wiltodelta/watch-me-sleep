import Foundation
import AVFoundation
import Vision
import AppKit

public final class SleepDetectionManager: NSObject, ObservableObject {
    public static let shared = SleepDetectionManager()

    @Published public var isCameraModeEnabled: Bool = false
    @Published public var isCameraAuthorized: Bool = false
    @Published public var isSessionRunning: Bool = false
    @Published public var isUserAsleep: Bool = false
    @Published public var isFaceDetected: Bool = false
    @Published public var statusMessage: String = "Camera tracking is off."

    // Shadow of isFaceDetected mutated only on the video queue, so we dispatch to
    // main (to publish) only when the value actually flips, not every frame.
    private var faceDetectedShadow = false

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "SleepDetectionManager.SessionQueue")
    private var isSessionConfigured = false

    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoOutputQueue = DispatchQueue(label: "SleepDetectionManager.VideoOutput", qos: .userInitiated)

    private let sequenceHandler = VNSequenceRequestHandler()

    // Sliding window parameters
    private let windowSize = 600 // Number of frames to consider (~60 seconds at 10 fps)
    private let sleepThresholdPercent = 0.90 // 90% of frames must be closed
    private let wakeThresholdPercent = 0.20 // 20% or less closed frames means awake

    // Continuous closure detection to distinguish blinks from sleep
    private let minContinuousClosedFrames = 150 // Must have 150+ consecutive closed frames (~15 sec) for sleep
    private var consecutiveClosedFrames = 0

    // EAR thresholds with hysteresis to prevent flicker
    // Based on research: typical open eyes ~0.25-0.35, closed ~0.10-0.20
    private let earClosedThreshold = 0.20 // Below this = eyes closing
    private let earOpenThreshold = 0.27   // Above this = eyes opening

    // Frame smoothing to reduce flicker
    // Tolerance is 25% of window size for consistent behavior
    private let maxMissedFrames: Int // Calculated in init
    private var missedFramesCount = 0

    // Sliding window buffer: true = eyes closed, false = eyes open
    private var eyeStateWindow: [Bool] = []
    private var closedFramesCount: Int = 0 // Cached count for performance

    // Current eye state for hysteresis
    private var currentEyeState: Bool = false // false = open, true = closed

    // UI update throttling
    private var lastUIUpdateTime: Date?
    private let uiUpdateInterval: TimeInterval = 1.0 // Update UI max 1 time per second

    // Activity check timer (1.5-hour periodic check)
    private var activityCheckTimer: Timer?
    private let activityCheckInterval: TimeInterval = 1.5 * 60 * 60 // 1.5 hours

    private override init() {
        // Set tolerance to 25% of window size (~15 seconds at 10 fps for 60-second window)
        self.maxMissedFrames = Int(Double(windowSize) * 0.25)
        super.init()
    }

    /// A preview layer bound to the running capture session, for showing a live
    /// feed in the UI. Mirrored like a selfie view.
    public func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    private func setFaceDetected(_ detected: Bool) {
        guard faceDetectedShadow != detected else { return }
        faceDetectedShadow = detected
        DispatchQueue.main.async {
            self.isFaceDetected = detected
        }
    }

    public func setCameraModeEnabled(_ enabled: Bool) {
        self.isCameraModeEnabled = enabled

        if enabled {
            // Update status immediately so UI doesn't feel stuck
            DispatchQueue.main.async {
                if self.statusMessage != "Camera access was denied." {
                    self.statusMessage = "Starting camera..."
                }
            }
            
            // Perform setup on a background queue to prevent main thread blocking
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.requestAuthorizationAndStart()
            }
            startActivityCheckTimer()
        } else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.stopSession()
            }
            stopActivityCheckTimer()
            resetDetectionState()
            DispatchQueue.main.async {
                self.statusMessage = "Camera tracking is off."
            }
        }
    }

    private func requestAuthorizationAndStart() {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch currentStatus {
        case .authorized:
            DispatchQueue.main.async {
                self.isCameraAuthorized = true
            }
            startSessionIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isCameraAuthorized = granted
                }
                if granted {
                    self.startSessionIfNeeded()
                } else {
                    DispatchQueue.main.async {
                        self.statusMessage = "Camera access was denied."
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.isCameraAuthorized = false
                self.statusMessage = "Camera access is not authorized. Please enable it in System Settings."
            }
        @unknown default:
            DispatchQueue.main.async {
                self.isCameraAuthorized = false
                self.statusMessage = "Camera access is not available."
            }
        }
    }

    private func startSessionIfNeeded() {
        sessionQueue.async {
            if self.session.isRunning {
                return
            }
            
            DispatchQueue.main.async {
                self.statusMessage = "Configuring camera..."
            }

            self.configureSessionIfNeeded()

            guard self.isSessionConfigured else {
                DispatchQueue.main.async {
                    self.statusMessage = "Failed to configure camera session."
                }
                return
            }

            self.session.startRunning()

            DispatchQueue.main.async {
                self.isSessionRunning = true
                self.statusMessage = "Looking for your face..."
            }
        }
    }

    private func configureSessionIfNeeded() {
        if isSessionConfigured {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .low

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video) else {
            session.commitConfiguration()
            return
        }

        // Configure device for better performance
        do {
            try device.lockForConfiguration()

            // Set frame rate to 10 fps for efficiency (matches our window size calculation)
            if let range = device.activeFormat.videoSupportedFrameRateRanges.first {
                let targetFrameRate = CMTime(value: 1, timescale: 10) // 10 fps
                if range.minFrameDuration <= targetFrameRate && targetFrameRate <= range.maxFrameDuration {
                    device.activeVideoMinFrameDuration = targetFrameRate
                    device.activeVideoMaxFrameDuration = targetFrameRate
                }
            }

            device.unlockForConfiguration()
        } catch {
            // Continue with default settings if configuration fails
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            session.commitConfiguration()
            return
        }

        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        // Set video settings for better performance
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        isSessionConfigured = true
        session.commitConfiguration()
    }

    private func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }

            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    private func resetDetectionState() {
        eyeStateWindow.removeAll()
        closedFramesCount = 0
        missedFramesCount = 0
        currentEyeState = false
        consecutiveClosedFrames = 0
        faceDetectedShadow = false
        lastUIUpdateTime = nil
        DispatchQueue.main.async {
            self.isUserAsleep = false
            self.isFaceDetected = false
        }
    }

    private func handleEyeState(closed: Bool) {
        // Track consecutive closed frames to distinguish blinks from sleep
        if closed {
            consecutiveClosedFrames += 1
        } else {
            consecutiveClosedFrames = 0
        }

        // Update cached count when removing old value
        let removedValue: Bool?
        if eyeStateWindow.count >= windowSize {
            removedValue = eyeStateWindow.first
            eyeStateWindow.removeFirst()
        } else {
            removedValue = nil
        }

        // Add current frame state to sliding window
        eyeStateWindow.append(closed)

        // Update cached closed frames count efficiently
        if let removed = removedValue, removed {
            closedFramesCount -= 1 // Removed a closed frame
        }
        if closed {
            closedFramesCount += 1 // Added a closed frame
        }

        // Calculate percentage using cached count
        let closedPercentage = eyeStateWindow.isEmpty ? 0.0 : Double(closedFramesCount) / Double(eyeStateWindow.count)

        // Check for sleep condition:
        // Option 1: Window is full AND meets both criteria (percentage + consecutive)
        // Option 2: Enough consecutive frames even if window not full yet (early detection)
        let windowFull = eyeStateWindow.count >= windowSize
        let hasEnoughConsecutive = consecutiveClosedFrames >= minContinuousClosedFrames
        let hasHighPercentage = closedPercentage >= sleepThresholdPercent

        let shouldTriggerSleep = !isUserAsleep && hasEnoughConsecutive && (hasHighPercentage || !windowFull)

        if shouldTriggerSleep {
            DispatchQueue.main.async {
                self.isUserAsleep = true
                self.statusMessage = "Sleep detected. Starting 30-minute timer."
                if !TimerManager.shared.isTimerActive {
                    TimerManager.shared.startTimer(hours: 0.5)
                }
                // Notify status bar to update icon
                NotificationCenter.default.post(name: NSNotification.Name("CameraModeChanged"), object: nil)
            }
        }

        // Check for wake condition (low percentage of closed frames)
        // Only check if window has enough data
        if isUserAsleep && windowFull && closedPercentage <= wakeThresholdPercent {
            DispatchQueue.main.async {
                self.isUserAsleep = false
                self.statusMessage = "Awake detected. Cancelling timer and resuming tracking."
                if TimerManager.shared.isTimerActive {
                    TimerManager.shared.stopTimer()
                }
                // Notify status bar to update icon
                NotificationCenter.default.post(name: NSNotification.Name("CameraModeChanged"), object: nil)
            }
        }
    }

    private func process(sampleBuffer: CMSampleBuffer) {
        guard isCameraModeEnabled else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Create request with completion handler (reuse request object on next call)
        let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
            guard let self else { return }

            if error != nil {
                DispatchQueue.main.async {
                    self.statusMessage = "Can't analyze video right now."
                }
                return
            }

            guard let observations = request.results as? [VNFaceObservation],
                let face = observations.first,
                let leftEye = face.landmarks?.leftEye,
                let rightEye = face.landmarks?.rightEye else {
                // No face or eyes detected; increment missed frames counter
                self.missedFramesCount += 1

                // Only reset window if we've missed enough consecutive frames
                if self.missedFramesCount >= self.maxMissedFrames {
                    self.eyeStateWindow.removeAll()
                    self.closedFramesCount = 0 // Reset cached count when clearing window
                    self.currentEyeState = false
                    self.consecutiveClosedFrames = 0 // Reset so a lost face can't carry over into early sleep detection
                    self.setFaceDetected(false)
                    DispatchQueue.main.async {
                        if self.isSessionRunning {
                            self.statusMessage = "Looking for your face..."
                        }
                    }
                }
                return
            }

            // Face and eyes found; reset missed frames counter
            self.missedFramesCount = 0
            self.setFaceDetected(true)

            let leftRatio = Self.eyeAspectRatio(for: leftEye)
            let rightRatio = Self.eyeAspectRatio(for: rightEye)

            let averageRatio = (leftRatio + rightRatio) / 2.0

            // Apply hysteresis to prevent flicker for display state
            // If currently open, need to drop below closed threshold to change state
            // If currently closed, need to rise above open threshold to change state
            let isClosed: Bool
            if self.currentEyeState {
                // Currently closed: only open if EAR rises above open threshold
                isClosed = averageRatio < self.earOpenThreshold
            } else {
                // Currently open: only close if EAR drops below closed threshold
                isClosed = averageRatio < self.earClosedThreshold
            }

            self.currentEyeState = isClosed

            // For consecutive frame counting, use strict threshold without hysteresis
            // This ensures blinks (partial eye opening) reset the counter
            let isStrictlyClosed = averageRatio < self.earClosedThreshold
            self.handleEyeState(closed: isStrictlyClosed)

            // Update status message with throttling to reduce UI updates
            let now = Date()
            let shouldUpdateUI = self.lastUIUpdateTime.map { now.timeIntervalSince($0) >= self.uiUpdateInterval } ?? true

            if shouldUpdateUI {
                self.lastUIUpdateTime = now

                DispatchQueue.main.async {
                    // Calculate percentage if we have enough frames
                    if !self.eyeStateWindow.isEmpty {
                        // Use cached count instead of filter
                        let closedPercentage = Double(self.closedFramesCount) / Double(self.eyeStateWindow.count)

                        // Always show percentage of closed eyes
                        let closedPercent = Int(closedPercentage * 100)

                        // Estimate time window (assuming ~10 fps)
                        let timeWindow = self.eyeStateWindow.count / 10

                        // Only update if message actually changed to avoid unnecessary string allocations
                        let newMessage = "Eyes closed \(closedPercent)% for last \(timeWindow) sec"
                        if self.statusMessage != newMessage {
                            self.statusMessage = newMessage
                        }
                    } else {
                        if self.statusMessage != "Tracking eyes" {
                            self.statusMessage = "Tracking eyes"
                        }
                    }
                }
            }
        }

        // Use best revision if available
        if #available(macOS 14.0, *) {
            request.revision = VNDetectFaceLandmarksRequestRevision3
        }

        do {
            // Perform with orientation for better accuracy
            let orientation = CGImagePropertyOrientation.up
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: orientation)
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Can't analyze video right now."
            }
        }
    }

    public static func eyeAspectRatio(for region: VNFaceLandmarkRegion2D) -> Double {
        let points = region.normalizedPoints

        // Vision can return different numbers of points depending on the model and device
        // We'll handle the most common cases with direct indexing

        // Helper function to calculate Euclidean distance
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = a.x - b.x
            let dy = a.y - b.y
            return sqrt(dx * dx + dy * dy)
        }

        // Try direct indexing for known point counts
        if points.count == 8 {
            // 8-point contour (clockwise from outer corner)
            let p1 = points[0]  // Outer corner
            let p4 = points[3]  // Inner corner
            let p2 = points[1]  // Top outer
            let p6 = points[5]  // Bottom outer
            let p3 = points[2]  // Top inner
            let p5 = points[4]  // Bottom inner

            let verticalDist1 = distance(p2, p6)
            let verticalDist2 = distance(p3, p5)
            let horizontalDist = distance(p1, p4)

            guard horizontalDist > 0 else { return 0.0 }
            return Double((verticalDist1 + verticalDist2) / (2.0 * horizontalDist))
        }

        if points.count == 6 {
            // 6-point contour layout (based on actual Vision output):
            // 0: outer corner
            // 1: top eyelid (outer side)
            // 2: top eyelid (inner side)
            // 3: inner corner
            // 4: bottom eyelid (inner side)
            // 5: bottom eyelid (outer side)

            let p1 = points[0]  // Outer corner
            let p4 = points[3]  // Inner corner
            let p2 = points[1]  // Top outer
            let p6 = points[5]  // Bottom outer (NOT 4!)
            let p3 = points[2]  // Top inner
            let p5 = points[4]  // Bottom inner (NOT 5!)

            // Correct vertical distances:
            // - Outer side: top[1] to bottom[5]
            // - Inner side: top[2] to bottom[4]
            let verticalDist1 = distance(p2, p6)  // points[1] to points[5]
            let verticalDist2 = distance(p3, p5)  // points[2] to points[4]
            let horizontalDist = distance(p1, p4)  // points[0] to points[3]

            guard horizontalDist > 0 else { return 0.0 }
            return Double((verticalDist1 + verticalDist2) / (2.0 * horizontalDist))
        }

        if points.count == 12 {
            // 12-point detailed contour (use specific indices for classic 6 points)
            let p1 = points[0]   // Outer corner
            let p4 = points[6]   // Inner corner
            let p2 = points[2]   // Top outer
            let p6 = points[10]  // Bottom outer
            let p3 = points[4]   // Top inner
            let p5 = points[8]   // Bottom inner

            let verticalDist1 = distance(p2, p6)
            let verticalDist2 = distance(p3, p5)
            let horizontalDist = distance(p1, p4)

            guard horizontalDist > 0 else { return 0.0 }
            return Double((verticalDist1 + verticalDist2) / (2.0 * horizontalDist))
        }

        // Fallback: geometric approach for non-standard point counts
        guard points.count >= 6 else {
            return 0.0
        }

        // Find horizontal extremes (corners of the eye)
        let p1 = points.min(by: { $0.x < $1.x }) ?? points[0]  // Leftmost
        let p4 = points.max(by: { $0.x < $1.x }) ?? points[0]  // Rightmost

        // Find center X coordinate
        let centerX = (p1.x + p4.x) / 2.0

        // Split points into left and right halves
        let leftHalf = points.filter { $0.x < centerX }
        let rightHalf = points.filter { $0.x >= centerX }

        // Sort by Y to find top (higher Y in Vision) and bottom (lower Y)
        let leftTop = leftHalf.max(by: { $0.y < $1.y }) ?? p1      // p2 area
        let leftBottom = leftHalf.min(by: { $0.y < $1.y }) ?? p1   // p6 area
        let rightTop = rightHalf.max(by: { $0.y < $1.y }) ?? p4    // p3 area
        let rightBottom = rightHalf.min(by: { $0.y < $1.y }) ?? p4 // p5 area

        // Calculate distances for EAR formula
        let verticalDist1 = distance(leftTop, leftBottom)  // ||p2 - p6||
        let verticalDist2 = distance(rightTop, rightBottom) // ||p3 - p5||
        let horizontalDist = distance(p1, p4) // ||p1 - p4||

        guard horizontalDist > 0 else {
            return 0.0
        }

        // Classic EAR formula
        let ear = (verticalDist1 + verticalDist2) / (2.0 * horizontalDist)

        return Double(ear)
    }

    // MARK: - Activity Check Timer (1.5-hour periodic check)

    private func startActivityCheckTimer() {
        stopActivityCheckTimer()

        activityCheckTimer = Timer.scheduledTimer(withTimeInterval: activityCheckInterval, repeats: true) { [weak self] _ in
            self?.showActivityCheckDialog()
        }
    }

    private func stopActivityCheckTimer() {
        activityCheckTimer?.invalidate()
        activityCheckTimer = nil
    }

    private func showActivityCheckDialog() {
        DispatchQueue.main.async {
            // Bring app to foreground to show alert
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = "Are you asleep?"
            alert.informativeText = "You have been in camera mode for 1.5 hours."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Not Yet")
            alert.addButton(withTitle: "Yes, Sleep Now")

            // Create a custom label for countdown
            let countdownLabel = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 16))
            countdownLabel.isEditable = false
            countdownLabel.isBordered = false
            countdownLabel.backgroundColor = .clear
            countdownLabel.alignment = .center
            countdownLabel.font = NSFont.systemFont(ofSize: 11)
            countdownLabel.textColor = .secondaryLabelColor
            alert.accessoryView = countdownLabel

            // Countdown state
            var remainingSeconds = 30

            // Initial countdown text
            countdownLabel.stringValue = "Auto-sleep in \(remainingSeconds) seconds..."

            // Create a countdown timer on the main run loop
            let countdownTimer = Timer(timeInterval: 1.0, repeats: true) { timer in
                remainingSeconds -= 1

                if remainingSeconds > 0 {
                    countdownLabel.stringValue = "Auto-sleep in \(remainingSeconds) seconds..."
                } else {
                    // Time's up - force sleep
                    timer.invalidate()

                    NSLog("DEBUG: Auto-closing alert after 30 seconds")
                    NSApp.abortModal()
                }
            }

            // Add timer to main run loop so it fires during modal session
            RunLoop.main.add(countdownTimer, forMode: .modalPanel)

            let response = alert.runModal()
            countdownTimer.invalidate()

            // Return to accessory mode
            NSApp.setActivationPolicy(.accessory)

            if response == .alertSecondButtonReturn {
                // User chose "Yes, Sleep Now"
                TimerManager.shared.sleepNow()
            } else if response == .alertFirstButtonReturn {
                // User chose "Not Yet" - restart timer
                self.startActivityCheckTimer()
            } else {
                // Alert was closed by timer (auto-sleep)
                TimerManager.shared.sleepNow()
            }
        }
    }
}

extension SleepDetectionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        process(sampleBuffer: sampleBuffer)
    }
}
