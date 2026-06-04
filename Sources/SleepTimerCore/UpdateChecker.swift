import Foundation
import AppKit

public class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    private let githubRepo = "wiltodelta/sleep-timer-app"
    private let currentVersion: String
    private let skippedVersionKey = "skippedVersion"

    @Published public var isCheckingForUpdates = false

    private init() {
        // Read version from Bundle (Info.plist)
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            self.currentVersion = version
        } else {
            // Fallback version if Bundle is not available (e.g., running from CLI)
            self.currentVersion = "dev"
        }
    }

    public func checkForUpdates(showNoUpdateAlert: Bool = false) {
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true

        let urlString = "https://api.github.com/repos/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            isCheckingForUpdates = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }

            defer {
                DispatchQueue.main.async {
                    self.isCheckingForUpdates = false
                }
            }

            if let error = error {
                NSLog("Update check failed: \(error.localizedDescription)")
                if showNoUpdateAlert {
                    self.showErrorAlert()
                }
                return
            }

            guard let data = data else {
                if showNoUpdateAlert {
                    self.showErrorAlert()
                }
                return
            }

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                self.handleRelease(release, showNoUpdateAlert: showNoUpdateAlert)
            } catch {
                NSLog("Failed to parse release info: \(error.localizedDescription)")
                if showNoUpdateAlert {
                    self.showErrorAlert()
                }
            }
        }.resume()
    }

    private func handleRelease(_ release: GitHubRelease, showNoUpdateAlert: Bool) {
        let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")

        if Self.isNewerVersion(latestVersion, than: currentVersion) {
            // Honor a previously skipped version, but only for automatic checks.
            // A manual "Check for Updates" always surfaces the available version.
            if !showNoUpdateAlert,
               UserDefaults.standard.string(forKey: skippedVersionKey) == latestVersion {
                return
            }
            DispatchQueue.main.async {
                self.showUpdateAlert(version: latestVersion, url: release.htmlURL, releaseNotes: release.body)
            }
        } else if showNoUpdateAlert {
            DispatchQueue.main.async {
                self.showNoUpdateAvailableAlert()
            }
        }
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

    private func showUpdateAlert(version: String, url: String, releaseNotes: String?) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Sleep Timer \(version) is now available. You have \(currentVersion)."
            + "\n\nWould you like to download it?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Remind Me Later")

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()

        NSApp.setActivationPolicy(.accessory)

        switch response {
        case .alertFirstButtonReturn: // Download
            if let downloadURL = URL(string: url) {
                NSWorkspace.shared.open(downloadURL)
            }
        case .alertSecondButtonReturn: // Skip
            UserDefaults.standard.set(version, forKey: skippedVersionKey)
        default: // Remind Me Later
            break
        }
    }

    private func showNoUpdateAvailableAlert() {
        let alert = NSAlert()
        alert.messageText = "You're up to date!"
        alert.informativeText = "Sleep Timer \(currentVersion) is currently the newest version available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        alert.runModal()

        NSApp.setActivationPolicy(.accessory)
    }

    private func showErrorAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Update Check Failed"
            alert.informativeText = "Could not check for updates. Please try again later or check manually on GitHub."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")

            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            alert.runModal()

            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - GitHub API Models

private struct GitHubRelease: Codable {
    let tagName: String
    let htmlURL: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
    }
}
