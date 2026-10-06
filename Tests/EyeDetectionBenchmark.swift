import XCTest
import CoreImage
import ImageIO
import Vision
@testable import WatchMeSleepCore

/// Measures the production eye reading (`EyeReading`) on hand-labeled photos.
/// Skipped unless `WMS_FACE_DIR` names a folder of JPEGs with a `labels.csv`
/// (`file,label`, label `open` or `closed`); see `docs/eye-detection.md`.
/// Prints a table per condition; it measures, it does not gate.
final class EyeDetectionBenchmark: XCTestCase {
    private let context = CIContext()

    func testEyeReadingOnLabeledPhotos() throws {
        let path = ProcessInfo.processInfo.environment["WMS_FACE_DIR"]
        try XCTSkipUnless(path != nil, "Set WMS_FACE_DIR to run this measurement")
        let dir = URL(fileURLWithPath: path!)
        let labels = try String(contentsOf: dir.appendingPathComponent("labels.csv"), encoding: .utf8)
            .split(separator: "\n").dropFirst().map { $0.split(separator: ",").map(String.init) }
        let detector = try XCTUnwrap(EyeReading.makeBlinkDetector())
        var report = "condition | open right/wrong/no face | closed right/wrong/no face\n"
        for condition in ["192 px", "192 px turned 90", "192 px dark"] {
            var tally: [String: [Int]] = ["open": [0, 0, 0], "closed": [0, 0, 0]]
            for row in labels where row.count == 2 {
                guard let source = CGImageSourceCreateWithURL(dir.appendingPathComponent(row[0]) as CFURL, nil),
                    let photo = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
                let image = prepare(CIImage(cgImage: photo), condition: condition)
                let reading = read(image, detector: detector)
                let slot = reading == nil ? 2 : ((reading == .open) == (row[1] == "open") ? 0 : 1)
                tally[row[1], default: [0, 0, 0]][slot] += 1
            }
            let open = tally["open"]!, closed = tally["closed"]!
            report += "\(condition) | \(open.map(String.init).joined(separator: "/"))"
                + " | \(closed.map(String.init).joined(separator: "/"))\n"
        }
        print(report)
        try report.write(to: dir.appendingPathComponent("benchmark.txt"), atomically: true, encoding: .utf8)
    }

    /// The camera's `.low` preset delivers frames about 192 px wide.
    private func prepare(_ image: CIImage, condition: String) -> CIImage {
        let scale = 192 / image.extent.width
        var out = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        if condition.contains("turned") {
            out = out.oriented(.right)
        }
        if condition.contains("dark") {
            // About 2.5 stops under, with sensor-like noise: a room lit by the screen.
            let dim = out.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -2.5])
            let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.04, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.04, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.04, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: -0.02, y: -0.02, z: -0.02, w: 0)
            ])
            out = noise.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: dim])
                .cropped(to: dim.extent)
        }
        // Render, so both detectors see the same pixels a camera frame would give.
        let rendered = context.createCGImage(out, from: out.extent)!
        return CIImage(cgImage: rendered)
    }

    /// The same two detectors `CameraWatcher` runs on each frame.
    private func read(_ image: CIImage, detector: CIDetector) -> EyeReading? {
        let request = EyeReading.makeLandmarksRequest()
        try? VNImageRequestHandler(ciImage: image, orientation: .up).perform([request])
        return EyeReading.read(faces: request.results, image: image, detector: detector, deciding: true)
    }
}
