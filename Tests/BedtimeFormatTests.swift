import XCTest
@testable import WatchMeSleepCore

final class BedtimeFormatTests: XCTestCase {
    private func formatter(_ locale: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.timeStyle = .short
        return formatter
    }

    func testTimesFollowTheClockStyle() {
        XCTAssertEqual(BedtimeFormat.time(22 * 60 + 30, formatter: formatter("en_GB")), "22:30")
        XCTAssertEqual(BedtimeFormat.time(5 * 60, formatter: formatter("ru_RU")), "05:00")
        XCTAssertTrue(BedtimeFormat.time(22 * 60 + 30, formatter: formatter("en_US")).contains("10:30"))
    }

    func testMinutesRoundTripThroughAPickerDate() {
        for minutes in [0, 7 * 60 + 45, 22 * 60 + 30, 23 * 60 + 59] {
            XCTAssertEqual(BedtimeFormat.minutes(of: BedtimeFormat.date(minutes)), minutes)
        }
    }
}
