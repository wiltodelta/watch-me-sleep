import AVFoundation
import Foundation
import Vision
import os

/// The camera, shared by its two users: the night watch's short looks
/// (`checkPresence`) and the live preview in Settings. The session runs while
/// either needs it and stops when neither does. Frames are analyzed in memory
/// with Vision; nothing is recorded or sent anywhere.
public final class CameraWatcher: NSObject, ObservableObject {
    public static let shared = CameraWatcher()

    /// System Settings > Privacy & Security > Camera.
    static let cameraPrivacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
    )

    @Published public private(set) var isSessionRunning = false
    @Published public private(set) var isFaceDetected = false
    /// Width over height of the frames the camera delivers, once one arrived.
    @Published public private(set) var videoAspectRatio: CGFloat?

    enum User: Hashable {
        case preview
        case look
    }

    /// Who needs the camera. Touched only on main.
    private var users: Set<User> = []

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "CameraWatcher.Session")
    private var isSessionConfigured = false

    private let videoOutput = AVCaptureVideoDataOutput()
    let videoOutputQueue = DispatchQueue(label: "CameraWatcher.VideoOutput", qos: .userInitiated)
    private let sequenceHandler = VNSequenceRequestHandler()

    /// Shadow of `isFaceDetected` on the video queue, so main hears only flips.
    private var faceDetectedShadow = false
    /// Shadow of `videoAspectRatio` on the video queue, for the same reason.
    private var aspectRatioShadow: CGFloat?

    // The running look and its completion: video queue only. The generation
    // (main only) lets a timeout tell its own look from a later one.
    var presenceCheck: PresenceCheck?
    var presenceCompletion: ((PresenceCheck.Verdict) -> Void)?
    var presenceGeneration = 0

    private override init() {
        super.init()
    }

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// A preview layer bound to the capture session, for the Settings preview.
    public func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        // The whole frame: the preview takes the video's own proportions.
        layer.videoGravity = .resizeAspect
        return layer
    }

    /// The Settings preview appears or goes away.
    public func setPreviewActive(_ active: Bool) {
        if active {
            acquire(.preview)
        } else {
            release(.preview)
        }
    }

    // MARK: - Session ownership

    /// Never prompts: without access there is no session to start.
    func acquire(_ user: User) {
        guard Self.isAuthorized else { return }
        let wasIdle = users.isEmpty
        users.insert(user)
        if wasIdle { startSession() }
    }

    func release(_ user: User) {
        guard users.remove(user) != nil, users.isEmpty else { return }
        stopSession()
    }

    private func startSession() {
        Logger.app("camera").info("Camera on for \(String(describing: self.users), privacy: .public)")
        sessionQueue.async {
            self.configureSessionIfNeeded()
            guard self.isSessionConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.isSessionRunning = true }
        }
    }

    private func stopSession() {
        Logger.app("camera").info("Camera off")
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isSessionRunning = false
                self.isFaceDetected = false
            }
        }
        videoOutputQueue.async { self.faceDetectedShadow = false }
    }

    private func configureSessionIfNeeded() {
        if isSessionConfigured {
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .low

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input) else {
            return
        }

        // 10 fps is enough for eyes and spares Vision work; the camera may not
        // hold it, which is why `PresenceCheck` measures time, not frames.
        if (try? device.lockForConfiguration()) != nil {
            let tenFPS = CMTime(value: 1, timescale: 10)
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameDuration <= tenFPS && tenFPS <= $0.maxFrameDuration
            }) {
                device.activeVideoMinFrameDuration = tenFPS
                device.activeVideoMaxFrameDuration = tenFPS
            }
            device.unlockForConfiguration()
        }

        session.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
        guard session.canAddOutput(videoOutput) else { return }
        session.addOutput(videoOutput)
        isSessionConfigured = true
    }

    // MARK: - Frames (video queue)

    private func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        publishAspectRatio(of: pixelBuffer)

        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        guard (try? sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)) != nil else {
            return
        }

        // One value per frame for every consumer: the eyes' average aspect
        // ratio, or nil when no face with both eyes was found.
        let ear: Double? = (request.results?.first?.landmarks).flatMap { landmarks in
            guard let left = landmarks.leftEye, let right = landmarks.rightEye else { return nil }
            return (EyeAspectRatio.ratio(for: left) + EyeAspectRatio.ratio(for: right)) / 2
        }

        setFaceDetected(ear != nil)
        recordPresence(ear: ear, at: CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)))
    }

    private func publishAspectRatio(of pixelBuffer: CVPixelBuffer) {
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard height > 0 else { return }
        let ratio = CGFloat(CVPixelBufferGetWidth(pixelBuffer)) / CGFloat(height)
        guard aspectRatioShadow != ratio else { return }
        aspectRatioShadow = ratio
        DispatchQueue.main.async { self.videoAspectRatio = ratio }
    }

    private func setFaceDetected(_ detected: Bool) {
        guard faceDetectedShadow != detected else { return }
        faceDetectedShadow = detected
        DispatchQueue.main.async { self.isFaceDetected = detected }
    }
}

extension CameraWatcher: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        process(sampleBuffer: sampleBuffer)
    }
}
