import XCTest
@testable import WatchMeSleepCore

final class EyeAspectRatioTests: XCTestCase {
    private let accuracy = 0.0001

    // MARK: - 6/8-point contour layout

    func testOpenEyeSixPoints() {
        // verticals 0.4 each, horizontal width 1.0 -> EAR 0.4 (clearly open)
        let points = [
            CGPoint(x: 0.0, y: 0.5),  // 0: outer corner
            CGPoint(x: 0.3, y: 0.7),  // 1: top outer
            CGPoint(x: 0.7, y: 0.7),  // 2: top inner
            CGPoint(x: 1.0, y: 0.5),  // 3: inner corner
            CGPoint(x: 0.7, y: 0.3),  // 4: bottom inner
            CGPoint(x: 0.3, y: 0.3)   // 5: bottom outer
        ]
        XCTAssertEqual(EyeAspectRatio.ratio(points: points), 0.4, accuracy: accuracy)
    }

    func testClosedEyeSixPoints() {
        // verticals 0.04 each, horizontal width 1.0 -> EAR 0.04 (clearly closed)
        let points = [
            CGPoint(x: 0.0, y: 0.50),
            CGPoint(x: 0.3, y: 0.52),
            CGPoint(x: 0.7, y: 0.52),
            CGPoint(x: 1.0, y: 0.50),
            CGPoint(x: 0.7, y: 0.48),
            CGPoint(x: 0.3, y: 0.48)
        ]
        XCTAssertEqual(EyeAspectRatio.ratio(points: points), 0.04, accuracy: accuracy)
    }

    func testEightPointUsesSameLayoutAsSixPoint() {
        // Indices 6 and 7 are ignored; result must match the 6-point open eye.
        let points = [
            CGPoint(x: 0.0, y: 0.5),
            CGPoint(x: 0.3, y: 0.7),
            CGPoint(x: 0.7, y: 0.7),
            CGPoint(x: 1.0, y: 0.5),
            CGPoint(x: 0.7, y: 0.3),
            CGPoint(x: 0.3, y: 0.3),
            CGPoint(x: 0.9, y: 0.9),  // 6: unused
            CGPoint(x: 0.1, y: 0.1)   // 7: unused
        ]
        XCTAssertEqual(EyeAspectRatio.ratio(points: points), 0.4, accuracy: accuracy)
    }

    // MARK: - 12-point contour layout

    func testTwelvePointContour() {
        var points = Array(repeating: CGPoint.zero, count: 12)
        points[0] = CGPoint(x: 0.0, y: 0.5)   // outer corner
        points[6] = CGPoint(x: 1.0, y: 0.5)   // inner corner
        points[2] = CGPoint(x: 0.3, y: 0.7)   // top outer
        points[10] = CGPoint(x: 0.3, y: 0.3)  // bottom outer
        points[4] = CGPoint(x: 0.7, y: 0.7)   // top inner
        points[8] = CGPoint(x: 0.7, y: 0.3)   // bottom inner
        XCTAssertEqual(EyeAspectRatio.ratio(points: points), 0.4, accuracy: accuracy)
    }

    // MARK: - Geometric fallback (non-standard point counts)

    func testGeometricFallbackSevenPoints() {
        let points = [
            CGPoint(x: 0.0, y: 0.5),   // leftmost (outer corner)
            CGPoint(x: 1.0, y: 0.5),   // rightmost (inner corner)
            CGPoint(x: 0.25, y: 0.7),
            CGPoint(x: 0.25, y: 0.3),
            CGPoint(x: 0.75, y: 0.7),
            CGPoint(x: 0.75, y: 0.3),
            CGPoint(x: 0.5, y: 0.6)
        ]
        XCTAssertEqual(EyeAspectRatio.ratio(points: points), 0.4, accuracy: accuracy)
    }

    // MARK: - Degenerate input

    func testZeroHorizontalDistanceReturnsZero() {
        // All points share an x, so eye width is zero and EAR is undefined -> 0.
        let points = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.5, y: 0.7),
            CGPoint(x: 0.5, y: 0.7),
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.5, y: 0.3),
            CGPoint(x: 0.5, y: 0.3)
        ]
        XCTAssertEqual(EyeAspectRatio.ratio(points: points), 0.0, accuracy: accuracy)
    }

    func testTooFewPointsReturnsZero() {
        let points = [
            CGPoint(x: 0.0, y: 0.5),
            CGPoint(x: 0.5, y: 0.7),
            CGPoint(x: 1.0, y: 0.5),
            CGPoint(x: 0.5, y: 0.3),
            CGPoint(x: 0.25, y: 0.6)
        ]
        XCTAssertEqual(EyeAspectRatio.ratio(points: points), 0.0, accuracy: accuracy)
    }

    func testEmptyPointsReturnsZero() {
        XCTAssertEqual(EyeAspectRatio.ratio(points: []), 0.0, accuracy: accuracy)
    }

    // MARK: - Relationship

    func testOpenEyeRatioExceedsClosedEyeRatio() {
        let open = [
            CGPoint(x: 0.0, y: 0.5), CGPoint(x: 0.3, y: 0.7), CGPoint(x: 0.7, y: 0.7),
            CGPoint(x: 1.0, y: 0.5), CGPoint(x: 0.7, y: 0.3), CGPoint(x: 0.3, y: 0.3)
        ]
        let closed = [
            CGPoint(x: 0.0, y: 0.50), CGPoint(x: 0.3, y: 0.52), CGPoint(x: 0.7, y: 0.52),
            CGPoint(x: 1.0, y: 0.50), CGPoint(x: 0.7, y: 0.48), CGPoint(x: 0.3, y: 0.48)
        ]
        XCTAssertGreaterThan(EyeAspectRatio.ratio(points: open), EyeAspectRatio.ratio(points: closed))
    }
}
