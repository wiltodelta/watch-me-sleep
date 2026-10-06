import SwiftUI
import AppKit
import AVFoundation

/// Requests the settings window from anywhere in the UI.
public func openAppSettings() {
    NotificationCenter.default.post(name: .openSettings, object: nil)
}

/// Settings window content: the night watch, launch at login, and update checks.
public struct SettingsView: View {
    @StateObject private var supervisor = SleepSupervisor.shared
    @StateObject private var launchManager = LaunchAtLoginManager.shared
    @ObservedObject private var updater = Updater.shared
    @State private var cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
    /// The preview runs the camera, so it is shown only on request, never just
    /// because Settings opened.
    @State private var showsPreview = false

    public init() {}

    public var body: some View {
        Form {
            nightWatchSection
            startupSection
            updatesSection
        }
        .formStyle(.grouped)
        // Access can change in System Settings while this window stays alive
        // between openings; coming back brings the app to the front.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshCameraAccess()
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Night watch

    private var nightWatchSection: some View {
        Section {
            Toggle("Sleep the Mac when I fall asleep", isOn: $supervisor.isEnabled)

            if supervisor.isEnabled {
                // Any time to the minute, the way Night Shift schedules: a
                // short list of whole hours left out early sleepers, late
                // risers and day sleepers.
                LabeledContent("Bedtime") {
                    HStack(spacing: 6) {
                        timeField("Bedtime starts", minutes: $supervisor.bedtimeStart)
                        Text("to").foregroundStyle(.secondary)
                        timeField("Bedtime ends", minutes: $supervisor.bedtimeEnd)
                    }
                }
                .accessibilityIdentifier("bedtime")
                // On only where looking can really happen, so the switch never
                // claims a look the missing camera access would skip.
                Toggle("Use the camera", isOn: Binding(
                    get: { cameraOn },
                    set: { setUsesCamera($0) }
                ))
                if cameraOn {
                    LabeledContent("Camera preview") {
                        Button(showsPreview ? "Hide" : "Show") { showsPreview.toggle() }
                            .accessibilityIdentifier("toggleCameraPreview")
                    }
                    if showsPreview {
                        CameraPreviewRow()
                    }
                }
            }
        } header: {
            Text("Night watch")
        } footer: {
            Text(nightWatchFooter)
        }
    }

    /// The camera will really look: chosen, and access given.
    private var cameraOn: Bool {
        supervisor.usesCamera && cameraAccess == .authorized
    }

    private var nightWatchFooter: String {
        let base = bedtimeSummary + " When you stop using your Mac but a film or music keeps it awake, "
            + "it sleeps the Mac after a minute's warning. With work running, only the display turns off."
        guard supervisor.isEnabled, supervisor.usesCamera else { return base }
        if cameraAccess == .denied || cameraAccess == .restricted {
            return base + " Camera access is off in System Settings, so it decides without looking."
        }
        guard cameraOn else { return base }
        return base + " When unsure, it looks with the camera for closed eyes. Nothing is recorded."
    }

    /// "Every day, 8 hr, 30 min." or a note that equal times make no bedtime.
    private var bedtimeSummary: String {
        guard supervisor.bedtimeMinutes > 0 else {
            return "Bedtime starts and ends at the same time, so the night watch never runs."
        }
        return "Every day, \(BedtimeFormat.duration(supervisor.bedtimeMinutes))."
    }

    /// Asks for camera access here, while the person is choosing it, so the
    /// nightly look never has to prompt.
    private func setUsesCamera(_ enabled: Bool) {
        supervisor.usesCamera = enabled
        guard enabled else { return }
        switch cameraAccess {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async { refreshCameraAccess() }
            }
        case .denied, .restricted:
            // The app cannot ask again; the person grants it in System Settings.
            if let url = CameraWatcher.cameraPrivacySettingsURL {
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

    private func timeField(_ label: String, minutes: Binding<Int>) -> some View {
        DatePicker(label, selection: Binding(
            get: { BedtimeFormat.date(minutes.wrappedValue) },
            set: { minutes.wrappedValue = BedtimeFormat.minutes(of: $0) }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
        .datePickerStyle(.field)
    }
}
