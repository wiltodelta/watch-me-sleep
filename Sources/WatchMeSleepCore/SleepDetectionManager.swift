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

    // Sliding-window sleep/wake decision logic, extracted for unit testing. Owns the
    // frame window, consecutive-closed counter, hysteresis state, missed-frame
    // tolerance, and the asleep flag; mutated only on `videoOutputQueue`.
    private var tracker = EyeStateTracker()

    // UI update throttling
    private var lastUIUpdateTime: Date?
    private let uiUpdateInterval: TimeInterval = 1.0 // Update UI max 1 time per second

    // Activity check timer (1.5-hour periodic check)
    private var activityCheckTimer: Timer?
    private let activityCheckInterval: TimeInterval = 1.5 * 60 * 60 // 1.5 hours

    private override init() {
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
        tracker.reset()
        faceDetectedShadow = false
        lastUIUpdateTime = nil
        DispatchQueue.main.async {
            self.isUserAsleep = false
            self.isFaceDetected = false
        }
    }

    private func process(sampleBuffer: CMSampleBuffer) {
        guard isCameraModeEnabled,
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
            self?.handleLandmarks(request: request, error: error)
        }

        // Use best revision if available
        if #available(macOS 14.0, *) {
            request.revision = VNDetectFaceLandmarksRequestRevision3
        }

        do {
            // Perform with orientation for better accuracy
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Can't analyze video right now."
            }
        }
    }

    /// Vision landmark-request completion. Runs on `videoOutputQueue`, the only queue
    /// that mutates `tracker`.
    private func handleLandmarks(request: VNRequest, error: Error?) {
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
            handleFaceLost()
            return
        }

        handleFaceFound(leftEye: leftEye, rightEye: rightEye)
    }

    /// No face or eyes this frame. The tracker tolerates a run of missed frames; once
    /// it drops the window we flag the face as lost and prompt the user to reappear.
    private func handleFaceLost() {
        guard tracker.recordMissedFrame() else { return }
        setFaceDetected(false)
        DispatchQueue.main.async {
            if self.isSessionRunning {
                self.statusMessage = "Looking for your face..."
            }
        }
    }

    /// Face and both eyes found. Feed the average EAR to the tracker and translate its
    /// decision into side effects, then refresh the throttled status message.
    private func handleFaceFound(leftEye: VNFaceLandmarkRegion2D, rightEye: VNFaceLandmarkRegion2D) {
        setFaceDetected(true)

        let averageRatio = (EyeAspectRatio.ratio(for: leftEye) + EyeAspectRatio.ratio(for: rightEye)) / 2.0
        applyDecision(tracker.record(ear: averageRatio))

        throttleStatusUpdate()
    }

    /// Turns a tracker decision into user-visible side effects: the sleep/wake flag,
    /// the status message, the 30-minute timer, and the status-bar icon refresh.
    private func applyDecision(_ decision: EyeStateTracker.Decision) {
        switch decision {
        case .sleepDetected:
            DispatchQueue.main.async {
                self.isUserAsleep = true
                self.statusMessage = "Sleep detected. Starting 30-minute timer."
                if !TimerManager.shared.isTimerActive {
                    TimerManager.shared.startTimer(hours: 0.5)
                }
                NotificationCenter.default.post(name: .cameraModeChanged, object: nil)
            }
        case .wakeDetected:
            DispatchQueue.main.async {
                self.isUserAsleep = false
                self.statusMessage = "Awake detected. Cancelling timer and resuming tracking."
                if TimerManager.shared.isTimerActive {
                    TimerManager.shared.stopTimer()
                }
                NotificationCenter.default.post(name: .cameraModeChanged, object: nil)
            }
        case .noChange:
            break
        }
    }

    /// Refreshes the "eyes closed N% for last M sec" status, throttled to at most one
    /// update per `uiUpdateInterval`. Tracker values are read on the video queue and
    /// captured before the string assignment is dispatched to main.
    private func throttleStatusUpdate() {
        let now = Date()
        let shouldUpdateUI = lastUIUpdateTime
            .map { now.timeIntervalSince($0) >= uiUpdateInterval } ?? true
        guard shouldUpdateUI else { return }
        lastUIUpdateTime = now

        guard !tracker.isWindowEmpty else {
            DispatchQueue.main.async {
                if self.statusMessage != "Tracking eyes" {
                    self.statusMessage = "Tracking eyes"
                }
            }
            return
        }

        let closedPercent = Int(tracker.closedPercentage * 100)
        let timeWindow = tracker.windowCount / 10 // ~10 fps
        DispatchQueue.main.async {
            let newMessage = "Eyes closed \(closedPercent)% for last \(timeWindow) sec"
            if self.statusMessage != newMessage {
                self.statusMessage = newMessage
            }
        }
    }
}

// MARK: - Activity Check Timer (1.5-hour periodic check)

// The periodic "are you asleep?" nag is independent of the camera frame pipeline,
// so it lives in its own extension to keep the core detection type focused.
extension SleepDetectionManager {
    private func startActivityCheckTimer() {
        stopActivityCheckTimer()

        activityCheckTimer = Timer.scheduledTimer(
            withTimeInterval: activityCheckInterval,
            repeats: true
        ) { [weak self] _ in
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
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        process(sampleBuffer: sampleBuffer)
    }
}
