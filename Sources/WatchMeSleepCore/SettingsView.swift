import SwiftUI
import AppKit
import AVFoundation

/// Requests the settings window from anywhere in the UI.
public func openAppSettings() {
    NotificationCenter.default.post(name: .openSettings, object: nil)
}

/// Settings window content. Hosts the global settings that used to clutter the
/// menu bar panel: idle auto-start, launch at login, and update checks.
public struct SettingsView: View {
    @StateObject private var autoActivation = AutoActivationManager.shared
    @StateObject private var launchManager = LaunchAtLoginManager.shared
    @ObservedObject private var updater = Updater.shared
    @State private var cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)

    private let startHourOptions = [20, 21, 22, 23, 0, 1, 2]
    private let endHourOptions = [5, 6, 7, 8, 9, 10]
    private let idleOptions = [10, 15, 20, 30, 45, 60]
    private let durationOptions: [Double] = [0.5, 1, 1.5, 2, 3]

    public init() {}

    public var body: some View {
        Form {
            autoStartSection
            startupSection
            updatesSection
        }
        .formStyle(.grouped)
        // Access can change in Camera mode or System Settings while this window
        // stays alive between openings; both bring the app back to the front.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshCameraAccess()
        }
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
                // On only where the check can really run, so the switch never
                // claims a look the missing camera access would skip.
                Toggle("Check with the camera first", isOn: Binding(
                    get: { autoActivation.checksWithCamera && cameraAccess == .authorized },
                    set: { setChecksWithCamera($0) }
                ))
            }
        } header: {
            Text("Auto-start when idle")
        } footer: {
            Text(autoStartFooter)
        }
    }

    private var autoStartFooter: String {
        let base = "Automatically start a sleep timer when your Mac sits idle late at night, "
            + "so it powers down even if you forget to start one yourself."
        guard autoActivation.isEnabled, autoActivation.checksWithCamera else { return base }
        if cameraAccess == .denied || cameraAccess == .restricted {
            return base + " Camera access is off in System Settings, so the timer starts without a look."
        }
        guard cameraAccess == .authorized else { return base }
        let timerMinutes = Int(AutoActivationManager.confirmedTimerHours * 60)
        let recheckMinutes = Int(AutoActivationManager.recheckInterval / 60)
        return base + " The camera first takes a short look: if your eyes are closed or nobody is there, "
            + "a \(timerMinutes)-minute timer starts; if you are awake, it looks again in \(recheckMinutes) minutes. "
            + "Nothing is recorded."
    }

    /// Asks for camera access here, while the person is choosing it, so the
    /// nightly check never has to prompt.
    private func setChecksWithCamera(_ enabled: Bool) {
        autoActivation.checksWithCamera = enabled
        guard enabled else { return }
        switch cameraAccess {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async { refreshCameraAccess() }
            }
        case .denied, .restricted:
            // The app cannot ask again; the person grants it in System Settings.
            if let url = SleepDetectionManager.cameraPrivacySettingsURL {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private func refreshCameraAccess() {
        cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
    }

    // MARK: - Startup

    private var startupSection: some View {
        Section {
            // Shows what macOS actually did: a refused change flips back and says why.
            Toggle("Launch at login", isOn: Binding(
                get: { launchManager.isEnabled },
                set: { launchManager.setEnabled($0) }
            ))
        } header: {
            Text("Startup")
        } footer: {
            Text(launchManager.errorMessage.map { "Couldn't change this: \($0)" }
                 ?? "Start Watch Me While I Fall Asleep automatically when you log in to your Mac.")
        }
    }

    // MARK: - Updates

    private var updatesSection: some View {
        Section {
            LabeledContent("Version", value: updater.version)
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecks },
                set: { updater.automaticallyChecks = $0 }
            ))
            // Opens Sparkle's update window, so the title ends with an ellipsis.
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("Checks once a day and installs a new version when you choose to.")
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        HourFormat.label(hour)
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
