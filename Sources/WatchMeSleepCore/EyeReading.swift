import CoreImage
import Vision

/// Whether a frame shows open or closed eyes, from two independent detectors.
///
/// Measured on 54 hand-labeled photographs at the camera's 192-px width
/// (`docs/eye-detection.md`): Vision's Eye Aspect Ratio alone below 0.20 took
/// 17 of 46 open-eyed people (smiles, glasses) for closed; Core Image's blink
/// classifier alone, 2. Requiring both to agree on closed kept every closed pair
/// of 8 and misread 2 open ones, upright, turned 90 degrees and in the dark.
enum EyeReading: Equatable {
    case open
    case closed

    /// Below this Eye Aspect Ratio the eyes may be closed. Open eyes measured
    /// live 0.20-0.26 (median 0.234); closed eyes in photos 0.03-0.14.
    static let earClosedThreshold = 0.20

    /// - Parameters:
    ///   - ear: the eyes' average aspect ratio from Vision landmarks, or nil
    ///     when Vision found no face with both eyes.
    ///   - blinkClosed: Core Image's verdict that both eyes are closed, or nil
    ///     when it found no face.
    /// - Returns: nil when neither found a face.
    static func classify(ear: Double?, blinkClosed: Bool?) -> EyeReading? {
        switch (ear, blinkClosed) {
        case (nil, nil):
            return nil
        case let (ear?, nil):
            return ear < earClosedThreshold ? .closed : .open
        case let (nil, closed?):
            return closed ? .closed : .open
        case let (ear?, closed?):
            return ear < earClosedThreshold && closed ? .closed : .open
        }
    }

    /// The Core Image detector both the app and the benchmark use.
    static func makeBlinkDetector() -> CIDetector? {
        CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    }

    /// The Vision request both the app and the benchmark use.
    static func makeLandmarksRequest() -> VNDetectFaceLandmarksRequest {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        return request
    }

    /// One frame: Vision's landmarks (already run) plus, only where its answer
    /// could change the result, Core Image's blink classifier, the costlier of
    /// the two (~61 ms on a 192 px frame against Vision's ~32).
    /// - Parameter deciding: a look is running; without one only whether a
    ///   face is there matters (the Settings preview).
    static func read(faces: [VNFaceObservation]?, image: CIImage, detector: CIDetector?,
                     deciding: Bool) -> EyeReading? {
        let ear = ear(from: faces)
        // Open by Vision is open whatever the classifier says, and a found face
        // is all the preview asks.
        let blinkMatters = ear.map { deciding && $0 < earClosedThreshold } ?? true
        let blink = blinkMatters ? detector.flatMap { blinkClosed(in: image, detector: $0) } : nil
        return classify(ear: ear, blinkClosed: blink)
    }

    /// Vision's eye aspect ratio for the largest face with both eyes, the same
    /// face the blink classifier reads; nil when there is none.
    static func ear(from faces: [VNFaceObservation]?) -> Double? {
        let largest = faces?.max { $0.boundingBox.width < $1.boundingBox.width }
        guard let left = largest?.landmarks?.leftEye, let right = largest?.landmarks?.rightEye else { return nil }
        return (EyeAspectRatio.ratio(for: left) + EyeAspectRatio.ratio(for: right)) / 2
    }

    /// Core Image's blink classifier on one frame: both eyes closed, or nil
    /// when it finds no face. The largest face counts, as the camera mostly
    /// sees one person.
    static func blinkClosed(in image: CIImage, detector: CIDetector) -> Bool? {
        let faces = detector.features(in: image, options: [CIDetectorEyeBlink: true])
            .compactMap { $0 as? CIFaceFeature }
        guard let face = faces.max(by: { $0.bounds.width < $1.bounds.width }) else { return nil }
        return face.leftEyeClosed && face.rightEyeClosed
    }
}
