import XCTest
@testable import SleepTimerCore

final class UpdateCheckerTests: XCTestCase {
    // MARK: - Newer versions

    func testNewerMajor() {
        XCTAssertTrue(UpdateChecker.isNewerVersion("2.0.0", than: "1.9.9"))
    }

    func testNewerMinor() {
        XCTAssertTrue(UpdateChecker.isNewerVersion("1.3.0", than: "1.2.9"))
    }

    func testNewerPatch() {
        XCTAssertTrue(UpdateChecker.isNewerVersion("1.2.4", than: "1.2.3"))
    }

    // MARK: - Numeric, not lexicographic, ordering

    func testComparisonIsNumericNotLexicographic() {
        // Lexicographically "10" < "2", but 1.10.0 is newer than 1.2.0.
        XCTAssertTrue(UpdateChecker.isNewerVersion("1.10.0", than: "1.2.0"))
        XCTAssertFalse(UpdateChecker.isNewerVersion("1.2.0", than: "1.10.0"))
    }

    // MARK: - Equal and older

    func testEqualIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewerVersion("1.2.3", than: "1.2.3"))
    }

    func testOlderIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewerVersion("1.2.0", than: "1.3.0"))
    }

    // MARK: - Missing components treated as zero

    func testMissingComponentsTreatedAsZero() {
        XCTAssertFalse(UpdateChecker.isNewerVersion("1.2", than: "1.2.0"))
        XCTAssertTrue(UpdateChecker.isNewerVersion("1.2.1", than: "1.2"))
    }

    // MARK: - Non-numeric versions

    func testNonNumericVersionIsNeverNewer() {
        // "dev" has no numeric components, so it never counts as newer,
        // and any real version counts as newer than "dev".
        XCTAssertFalse(UpdateChecker.isNewerVersion("dev", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewerVersion("1.0.0", than: "dev"))
    }
}
