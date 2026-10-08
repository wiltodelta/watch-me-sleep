import AppKit
import Foundation
import os

/// An opt-in diary of what the night watch saw and did, one JSON object per
/// line, for debugging a real night afterwards (`docs/diagnostics.md`). Off
/// unless `defaults write com.wiltodelta.watchmesleep Diagnostics.journal -bool true`.
/// It holds no images, only numbers, verdicts and the names of processes
/// holding the Mac awake.
public final class Journal {
    public static let shared = Journal()

    static let enabledKey = "Diagnostics.journal"
    /// Past this size the file moves to `journal.1.jsonl`, replacing the one
    /// before: about a month of nights at a few hundred lines each.
    static let maxBytes = 10 * 1024 * 1024

    // Seams for tests.
    var isEnabled: () -> Bool = { UserDefaults.standard.bool(forKey: Journal.enabledKey) }
    var directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/WatchMeSleep", isDirectory: true)

    var fileURL: URL { directory.appendingPathComponent("journal.jsonl") }
    var previousFileURL: URL { directory.appendingPathComponent("journal.1.jsonl") }

    private let queue = DispatchQueue(label: "Journal", qos: .utility)
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        // Local time with its offset: a night reads as the clock showed it.
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init() {}

    /// One line: `event`, the time `t`, and `fields`, which must be JSON values
    /// (strings, numbers, booleans, arrays and dictionaries of them).
    public func record(_ event: String, _ fields: [String: Any] = [:]) {
        guard isEnabled() else { return }
        var entry = fields
        entry["event"] = event
        entry["t"] = formatter.string(from: Date())
        guard JSONSerialization.isValidJSONObject(entry),
            let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else {
            Logger.app("journal").error("Not a JSON entry: \(event, privacy: .public)")
            return
        }
        // Where the journal points now, not when the queue gets to it.
        let (file, previous) = (fileURL, previousFileURL)
        queue.async { self.append(data + Data([0x0A]), to: file, previous: previous) }
    }

    /// Waits for the lines recorded so far to reach the file.
    func flush() {
        queue.sync {}
    }

    /// The system's own sleep and wake, so a night reads in order with them.
    public func observeSystem() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [(Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, "will sleep"),
            (NSWorkspace.didWakeNotification, "did wake"),
            (NSWorkspace.screensDidSleepNotification, "display off"),
            (NSWorkspace.screensDidWakeNotification, "display on")
        ]
        for (name, what) in names {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.record("system", ["what": what])
            }
        }
    }

    private func append(_ line: Data, to fileURL: URL, previous previousFileURL: URL) {
        let files = FileManager.default
        do {
            try files.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let size = (try? files.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            if size + line.count > Self.maxBytes {
                try? files.removeItem(at: previousFileURL)
                try files.moveItem(at: fileURL, to: previousFileURL)
            }
            guard files.fileExists(atPath: fileURL.path) else {
                return try line.write(to: fileURL)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            Logger.app("journal").error("Journal write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
