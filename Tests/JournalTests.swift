import XCTest
@testable import WatchMeSleepCore

final class JournalTests: XCTestCase {
    private var directory: URL!
    private var journal: Journal!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        journal = Journal()
        journal.directory = directory
        journal.isEnabled = { true }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func lines(_ url: URL? = nil) throws -> [[String: Any]] {
        journal.flush()
        let text = try String(contentsOf: url ?? journal.fileURL, encoding: .utf8)
        return try text.split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    func testEachEventIsOneJSONLine() throws {
        journal.record("look", ["kind": "decision", "idle": 300])
        journal.record("arm", ["minutes": 5.0, "work": ["caffeinate"]])

        let entries = try lines()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0]["event"] as? String, "look")
        XCTAssertEqual(entries[0]["idle"] as? Int, 300)
        XCTAssertEqual(entries[1]["work"] as? [String], ["caffeinate"])
        XCTAssertNotNil(entries[0]["t"] as? String)
    }

    func testOffWritesNothing() {
        journal.isEnabled = { false }
        journal.record("look")
        journal.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.fileURL.path))
    }

    func testAFullFileMovesAside() throws {
        let filler = String(repeating: "x", count: Journal.maxBytes / 2)
        journal.record("big", ["filler": filler])
        journal.record("big", ["filler": filler])
        journal.record("after")

        XCTAssertEqual(try lines(journal.previousFileURL).count, 1, "The full file moved aside")
        XCTAssertEqual(try lines().map { $0["event"] as? String }, ["big", "after"])
    }
}
