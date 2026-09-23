import Foundation

/// Checks GitHub for a newer release and publishes the result for the UI to show
/// inline. It never raises an alert: the HIG says to avoid alerts at app start and
/// alerts that merely inform, so an available update surfaces in the panel footer
/// and the settings window instead.
public class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case skipped(version: String)
        case failed
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/wiltodelta/watch-me-sleep/releases/latest")!
    public let currentVersion: String
    private let skippedVersionKey = "skippedVersion"

    @Published public private(set) var state: State = .idle

    private init() {
        // Read version from Bundle (Info.plist)
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            self.currentVersion = version
        } else {
            // Fallback version if Bundle is not available (e.g., running from CLI)
            self.currentVersion = "dev"
        }
    }

    /// The update the panel footer should offer, if any.
    public var availableUpdate: (version: String, url: URL)? {
        if case let .available(version, url) = state {
            return (version, url)
        }
        return nil
    }

    /// `userInitiated` checks come from the settings window: they report every
    /// outcome and ignore a skipped version. Automatic checks only ever surface an
    /// update that has not been skipped.
    public func checkForUpdates(userInitiated: Bool) {
        guard state != .checking else { return }

        let previous = state
        state = .checking

        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            if let error {
                NSLog("Update check failed: \(error.localizedDescription)")
            }
            let next = Self.resolve(
                data: data,
                userInitiated: userInitiated,
                previous: previous,
                currentVersion: self.currentVersion,
                skippedVersion: UserDefaults.standard.string(forKey: self.skippedVersionKey)
            )
            DispatchQueue.main.async {
                self.state = next
            }
        }.resume()
    }

    /// Hide the offered version until a newer one ships.
    public func skipAvailableVersion() {
        guard let update = availableUpdate else { return }
        UserDefaults.standard.set(update.version, forKey: skippedVersionKey)
        state = .skipped(version: update.version)
    }

    /// Maps a GitHub "latest release" response to the next state. `data` is nil
    /// when the request failed. A failure an automatic check hits keeps the
    /// previous state rather than showing an error nobody asked for.
    static func resolve(
        data: Data?,
        userInitiated: Bool,
        previous: State,
        currentVersion: String,
        skippedVersion: String?
    ) -> State {
        guard let data else { return userInitiated ? .failed : previous }
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            NSLog("Failed to read release info: \(error)")
            return userInitiated ? .failed : previous
        }
        guard let pageURL = URL(string: release.htmlURL) else {
            return userInitiated ? .failed : previous
        }

        let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")
        guard isNewerVersion(latestVersion, than: currentVersion) else {
            return .upToDate
        }
        if !userInitiated, skippedVersion == latestVersion {
            return .skipped(version: latestVersion)
        }
        return .available(version: latestVersion, url: pageURL)
    }

    static func isNewerVersion(_ version1: String, than version2: String) -> Bool {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }

        for index in 0..<max(v1Components.count, v2Components.count) {
            let v1Value = index < v1Components.count ? v1Components[index] : 0
            let v2Value = index < v2Components.count ? v2Components[index] : 0

            if v1Value > v2Value {
                return true
            } else if v1Value < v2Value {
                return false
            }
        }

        return false
    }
}

// MARK: - GitHub API Models

private struct GitHubRelease: Codable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
