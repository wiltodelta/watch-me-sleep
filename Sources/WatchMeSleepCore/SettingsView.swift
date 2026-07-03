import SwiftUI
import AppKit

/// Requests the settings window from anywhere in the UI.
public func openAppSettings() {
    NotificationCenter.default.post(name: .openSettings, object: nil)
}

/// Preferences window content. Hosts the global settings that used to clutter the
/// menu bar panel: idle auto-start, launch at login, and update checks.
public struct SettingsView: View {
    @StateObject private var autoActivation = AutoActivationManager.shared
    @StateObject private var launchManager = LaunchAtLoginManager.shared
    @StateObject private var updateChecker = UpdateChecker.shared

    private let startHourOptions = [20, 21, 22, 23, 0, 1, 2]
    private let endHourOptions = [5, 6, 7, 8, 9, 10]
    private let idleOptions = [10, 15, 20, 30, 45, 60]
    private let durationOptions: [Double] = [0.5, 1, 1.5, 2, 3]

    public init() {}

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    public var body: some View {
        Form {
            autoStartSection
            startupSection
            updatesSection
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Auto-start

    private var autoStartSection: some View {
        Section {
            Toggle("Start a timer when the Mac is idle at night", isOn: $autoActivation.isEnabled)

            if autoActivation.isEnabled {
                Picker("Active from", selection: $autoActivation.activeAfterHour) {
                    ForEach(startHourOptions, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                Picker("Until", selection: $autoActivation.windowEndHour) {
                    ForEach(endHourOptions, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                Picker("Idle for", selection: $autoActivation.idleMinutes) {
                    ForEach(idleOptions, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Picker("Timer length", selection: $autoActivation.timerHours) {
                    ForEach(durationOptions, id: \.self) { Text(durationLabel($0)).tag($0) }
                }
            }
        } header: {
            Text("Auto-start when idle")
        } footer: {
            Text("Automatically start a sleep timer when your Mac sits idle late at night, "
                 + "so it powers down even if you forget to start one yourself.")
        }
    }

    // MARK: - Startup

    private var startupSection: some View {
        Section {
            Toggle("Launch at login", isOn: $launchManager.isEnabled)
        } header: {
            Text("Startup")
        } footer: {
            Text("Start Watch Me While I Fall Asleep automatically when you log in to your Mac.")
        }
    }

    // MARK: - Updates

    private var updatesSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
            Button {
                updateChecker.checkForUpdates(showNoUpdateAlert: true)
            } label: {
                Text(updateChecker.isCheckingForUpdates ? "Checking…" : "Check for updates…")
            }
            .disabled(updateChecker.isCheckingForUpdates)
        } header: {
            Text("Updates")
        } footer: {
            Text("Checks GitHub for a newer version on launch and offers to open the download page.")
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private func durationLabel(_ hours: Double) -> String {
        if hours < 1 {
            return "\(Int(hours * 60)) minutes"
        }
        if hours == floor(hours) {
            return Int(hours) == 1 ? "1 hour" : "\(Int(hours)) hours"
        }
        let whole = Int(hours)
        let minutes = Int((hours - Double(whole)) * 60)
        return "\(whole)h \(minutes)m"
    }
}
