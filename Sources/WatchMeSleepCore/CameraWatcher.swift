import AVFoundation
import CoreImage
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
    /// Core Image's face detector, for its blink classifier (`EyeReading`).
    private let blinkDetector = EyeReading.makeBlinkDetector()

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

        let request = EyeReading.makeLandmarksRequest()
        guard (try? sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)) != nil else {
            return
        }

        // Two detectors, because one misreads: Vision's eye aspect ratio took
        // narrow open eyes for closed, and Core Image's blink classifier
        // disagrees with it on exactly those (`EyeReading`).
        let eyes = EyeReading.read(faces: request.results, image: CIImage(cvPixelBuffer: pixelBuffer),
                                   detector: blinkDetector, deciding: presenceCheck != nil)

        setFaceDetected(eyes != nil)
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        // Brightness matters only to a running look, and only where no face was found.
        recordPresence(eyes: eyes, at: time, dark: eyes == nil && presenceCheck != nil && Self.isDark(pixelBuffer))
    }

    /// Mean luma below this, on 0...1, is too dark to find a face in: nearly
    /// black, a dark room or a covered lens. Not measured against real nights
    /// yet; kept low so a sleeper lit by the screen still counts as a picture.
    static let darkLuma = 0.04

    /// Samples the luma plane of a full-range 4:2:0 frame on a coarse grid.
    static func isDark(_ pixelBuffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return false }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0, count = 0
        for row in stride(from: 0, to: height, by: 8) {
            for column in stride(from: 0, to: width, by: 8) {
                sum += Int(luma[row * rowBytes + column])
                count += 1
            }
        }
        guard count > 0 else { return false }
        return Double(sum) / Double(count) / 255 < darkLuma
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
