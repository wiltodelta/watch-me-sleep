import XCTest
@testable import WatchMeSleepCore

final class EyeReadingTests: XCTestCase {
    func testBothDetectorsMustAgreeOnClosed() {
        XCTAssertEqual(EyeReading.classify(ear: 0.10, blinkClosed: true), .closed)
        XCTAssertEqual(EyeReading.classify(ear: 0.17, blinkClosed: false), .open,
                       "A smile narrows the eyes under 0.20; the blink classifier still sees them open")
        XCTAssertEqual(EyeReading.classify(ear: 0.23, blinkClosed: true), .open)
    }

    func testOneDetectorAloneDecides() {
        XCTAssertEqual(EyeReading.classify(ear: 0.10, blinkClosed: nil), .closed)
        XCTAssertEqual(EyeReading.classify(ear: 0.20, blinkClosed: nil), .open, "The threshold itself is open")
        XCTAssertEqual(EyeReading.classify(ear: nil, blinkClosed: true), .closed)
        XCTAssertEqual(EyeReading.classify(ear: nil, blinkClosed: false), .open)
    }

    func testNoFaceIsNoReading() {
        XCTAssertNil(EyeReading.classify(ear: nil, blinkClosed: nil))
    }
}
