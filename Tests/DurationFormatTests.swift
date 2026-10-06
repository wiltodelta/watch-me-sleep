import XCTest
@testable import WatchMeSleepCore

/// One way to write a length of time on every surface (UX-08).
final class DurationFormatTests: XCTestCase {
    func testCountdownHasOneShape() {
        XCTAssertEqual(DurationFormat.countdown(1 * 3600 + 29 * 60 + 54), "1:29:54")
        XCTAssertEqual(DurationFormat.countdown(14 * 60 + 59), "14:59")
        XCTAssertEqual(DurationFormat.countdown(59), "0:59")
        XCTAssertEqual(DurationFormat.countdown(-3), "0:00")
    }

    func testCompactAndWordsAgreeOnTheAmount() throws {
        try XCTSkipUnless(Locale.current.language.languageCode?.identifier == "en", "English formatter output")
        XCTAssertEqual(DurationFormat.compact(minutes: 15), "15m")
        XCTAssertEqual(DurationFormat.compact(minutes: 90), "1h 30m")
        XCTAssertEqual(DurationFormat.compact(minutes: 12 * 60), "12h")
        XCTAssertEqual(DurationFormat.words(minutes: 90), "1 hour, 30 minutes")
        XCTAssertEqual(DurationFormat.words(minutes: 8 * 60), "8 hours")
    }
}
