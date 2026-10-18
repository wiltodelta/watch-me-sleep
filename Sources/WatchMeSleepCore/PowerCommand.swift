import Foundation

/// Runs pmset away from the main actor and drains stderr before waiting, so
/// an unsuccessful command reports its exit status without blocking the UI.
enum PowerCommand {
    struct Failure: Error, Sendable {
        let message: String
    }

    static func run(
        _ command: String, executable: URL = URL(fileURLWithPath: "/usr/bin/pmset")
    ) async -> Result<Void, Failure> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = executable
                task.arguments = [command]
                let errors = Pipe()
                task.standardError = errors
                task.standardOutput = FileHandle.nullDevice
                do {
                    try task.run()
                    let data = errors.fileHandleForReading.readDataToEndOfFile()
                    task.waitUntilExit()
                    let detail = (String(data: data, encoding: .utf8) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if task.terminationReason == .exit, task.terminationStatus == 0 {
                        continuation.resume(returning: .success(()))
                    } else {
                        let status = "The power command exited with status \(task.terminationStatus)."
                        let message = detail.isEmpty ? status : status + " " + detail
                        continuation.resume(returning: .failure(Failure(message: message)))
                    }
                } catch {
                    continuation.resume(returning: .failure(Failure(message: error.localizedDescription)))
                }
            }
        }
    }
}
