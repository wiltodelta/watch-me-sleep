import XCTest
@testable import WatchMeSleepCore

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

    // MARK: - Resolving a release response

    private let releasePage = URL(string: "https://github.com/wiltodelta/watch-me-sleep/releases/tag/v2.0.0")!

    private func release(_ tag: String) -> Data {
        Data("""
        {"tag_name": "\(tag)", "html_url": "\(releasePage.absoluteString)"}
        """.utf8)
    }

    private func resolve(
        _ data: Data?,
        userInitiated: Bool,
        previous: UpdateChecker.State = .idle,
        current: String = "1.7.0",
        skipped: String? = nil
    ) -> UpdateChecker.State {
        UpdateChecker.resolve(
            data: data, userInitiated: userInitiated, previous: previous,
            currentVersion: current, skippedVersion: skipped
        )
    }

    func testNewerReleaseIsOffered() {
        XCTAssertEqual(resolve(release("v2.0.0"), userInitiated: false),
                       .available(version: "2.0.0", url: releasePage))
    }

    func testSameReleaseIsUpToDate() {
        XCTAssertEqual(resolve(release("v1.7.0"), userInitiated: false), .upToDate)
        XCTAssertEqual(resolve(release("v1.7.0"), userInitiated: true), .upToDate)
    }

    func testSkippedReleaseStaysHiddenOnAutomaticCheck() {
        XCTAssertEqual(resolve(release("v2.0.0"), userInitiated: false, skipped: "2.0.0"),
                       .skipped(version: "2.0.0"))
    }

    func testManualCheckOffersASkippedRelease() {
        XCTAssertEqual(resolve(release("v2.0.0"), userInitiated: true, skipped: "2.0.0"),
                       .available(version: "2.0.0", url: releasePage))
    }

    func testSkippingOneVersionDoesNotHideANewerOne() {
        XCTAssertEqual(resolve(release("v2.1.0"), userInitiated: false, skipped: "2.0.0"),
                       .available(version: "2.1.0", url: releasePage))
    }

    func testFailedManualCheckReportsFailure() {
        XCTAssertEqual(resolve(nil, userInitiated: true), .failed)
        XCTAssertEqual(resolve(Data("not json".utf8), userInitiated: true), .failed)
    }

    func testFailedAutomaticCheckKeepsPreviousState() {
        // A background failure must not replace what the settings window shows.
        XCTAssertEqual(resolve(nil, userInitiated: false, previous: .upToDate), .upToDate)
        XCTAssertEqual(resolve(Data("{}".utf8), userInitiated: false, previous: .idle), .idle)
    }
}
