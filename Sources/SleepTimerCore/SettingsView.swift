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
            Section("Auto-start when idle") {
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
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchManager.isEnabled)
            }

            Section("Updates") {
                LabeledContent("Version", value: appVersion)
                Button {
                    updateChecker.checkForUpdates(showNoUpdateAlert: true)
                } label: {
                    if updateChecker.isCheckingForUpdates {
                        Text("Checking…")
                    } else {
                        Text("Check for Updates…")
                    }
                }
                .disabled(updateChecker.isCheckingForUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
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
