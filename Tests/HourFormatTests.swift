import XCTest
@testable import WatchMeSleepCore

final class HourFormatTests: XCTestCase {
    func testTwelveHourLocaleShowsPeriod() {
        let label = HourFormat.label(22, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(label.hasPrefix("10"), label)
        XCTAssertTrue(label.contains("PM"), label)
    }

    func testTwentyFourHourLocaleShowsMinutes() {
        XCTAssertEqual(HourFormat.label(22, locale: Locale(identifier: "en_GB")), "22:00")
        XCTAssertEqual(HourFormat.label(5, locale: Locale(identifier: "ru_RU")), "05:00")
    }
}
