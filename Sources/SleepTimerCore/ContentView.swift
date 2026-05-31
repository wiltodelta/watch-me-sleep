import SwiftUI
import AppKit

public struct ContentView: View {
    @StateObject private var timerManager = TimerManager.shared
    @StateObject private var sleepManager = SleepDetectionManager.shared
    @State private var selectedMode: TimerMode = .manual
    @State private var selectedHours: Double = 1.5

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedMode) {
                Text("Timer").tag(TimerMode.manual)
                Text("Camera").tag(TimerMode.camera)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider()
            Group {
                switch selectedMode {
                case .manual:
                    if timerManager.isTimerActive {
                        ActiveTimerView()
                    } else {
                        InactiveTimerView(selectedHours: $selectedHours)
                    }
                case .camera:
                    CameraModeView()
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedMode)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: timerManager.isTimerActive)

            Divider()

            // Common settings footer
            CommonSettingsView()
        }
        .background(.regularMaterial)
        .onAppear {
            sleepManager.setCameraModeEnabled(selectedMode == .camera)

            // Notify status bar to update icon on launch
            NotificationCenter.default.post(name: NSNotification.Name("CameraModeChanged"), object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CameraModeDisabled"))) { _ in
            // Switch back to manual mode when camera mode is disabled externally (e.g., after system wake)
            if selectedMode == .camera {
                selectedMode = .manual
            }
        }
        .onChange(of: selectedMode) { newMode in
            // Stop active timer when switching modes
            if timerManager.isTimerActive {
                timerManager.stopTimer()
            }

            sleepManager.setCameraModeEnabled(newMode == .camera)

            // Notify status bar to update icon
            NotificationCenter.default.post(name: NSNotification.Name("CameraModeChanged"), object: nil)
        }
    }

    }

enum TimerMode {
    case manual
    case camera
}

struct CommonSettingsView: View {
    var body: some View {
        HStack(spacing: 16) {
            Button {
                openAppSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct InactiveTimerView: View {
    @Binding var selectedHours: Double

    private let presetHours: [Double] = [0.25, 0.5, 1, 1.5, 2, 3, 4, 6]

    var body: some View {
        VStack(spacing: 0) {
            // Time display
            VStack(spacing: 12) {
                Text(formatHours(selectedHours))
                    .font(.system(size: 48, weight: .regular, design: .rounded))
                    .foregroundColor(.primary)

                Slider(value: $selectedHours, in: 0.25...12, step: 0.25)
                    .controlSize(.small)

                HStack {
                    Text("15 min")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("12 hours")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
            .padding(.top, 12)

            Divider()

                // Presets
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(Array(presetHours.prefix(4)), id: \.self) { hours in
                            PresetButton(hours: hours, selectedHours: $selectedHours)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(Array(presetHours.suffix(4)), id: \.self) { hours in
                            PresetButton(hours: hours, selectedHours: $selectedHours)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider()

            // Start button
            Button("Start Timer") {
                TimerManager.shared.startTimer(hours: selectedHours)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func formatHours(_ hours: Double) -> String {
        if hours < 1 {
            let minutes = Int(hours * 60)
            return "\(minutes) min"
        } else if hours == floor(hours) {
            let h = Int(hours)
            return h == 1 ? "1 hour" : "\(h) hours"
        } else {
            let h = Int(hours)
            let m = Int((hours - Double(h)) * 60)
            if m == 0 {
                return h == 1 ? "1 hour" : "\(h) hours"
            }
            return "\(h)h \(m)m"
        }
    }

    private func formatHoursShort(_ hours: Double) -> String {
        if hours < 1 {
            return "\(Int(hours * 60))m"
        } else if hours == floor(hours) {
            return "\(Int(hours))h"
        } else {
            let h = Int(hours)
            let m = Int((hours - Double(h)) * 60)
            return "\(h)h \(m)m"
        }
    }
}

struct PresetButton: View {
    let hours: Double
    @Binding var selectedHours: Double

    var body: some View {
        Button(action: {
            selectedHours = hours
        }) {
            Text(formatHoursShort(hours))
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
        }
        .buttonStyle(.bordered)
        .tint(selectedHours == hours ? .accentColor : .gray)
        .controlSize(.small)
    }

    private func formatHoursShort(_ hours: Double) -> String {
        if hours < 1 {
            return "\(Int(hours * 60))m"
        } else if hours == floor(hours) {
            return "\(Int(hours))h"
        } else {
            let h = Int(hours)
            let m = Int((hours - Double(h)) * 60)
            return "\(h)h \(m)m"
        }
    }
}

struct ActiveTimerView: View {
    @StateObject private var timerManager = TimerManager.shared

    
    var body: some View {
        VStack(spacing: 0) {
            // Circular progress
            VStack(spacing: 16) {
                ZStack {
                    // Background circle with material
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 150, height: 150)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)

                    Circle()
                        .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 12)
                        .frame(width: 140, height: 140)

                    Circle()
                        .trim(from: 0, to: CGFloat(timerManager.remainingTime / timerManager.totalTime))
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 3)

                    VStack(spacing: 2) {
                        Text(formatTime(timerManager.remainingTime))
                            .font(.system(size: 26, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        Text("remaining")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                VStack(spacing: 2) {
                    Text("Sleep at \(formatTargetTime(timerManager.remainingTime))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
            .padding(.top, 12)

            Divider()

            // Add time buttons
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach([5, 15, 30, 60], id: \.self) { minutes in
                        Button("+\(minutes)m") {
                            timerManager.addTime(minutes: minutes)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Cancel button
            Button("Stop Timer") {
                timerManager.stopTimer()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) % 3600 / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func formatTargetTime(_ remainingTime: TimeInterval) -> String {
        let targetDate = Date().addingTimeInterval(remainingTime)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: targetDate)
    }
}

struct CameraModeView: View {
    @StateObject private var sleepManager = SleepDetectionManager.shared
    @StateObject private var timerManager = TimerManager.shared
    @Environment(\.openURL) private var openURL

    
    var body: some View {
        ZStack {
            // Subtle background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.accentColor.opacity(0.02),
                    Color.clear
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                introSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
                statusCard
                    timerCard
                    Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sleepManager.isUserAsleep)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: timerManager.isTimerActive)
    }

    private var introSection: some View {
        VStack(spacing: 10) {
            Text("Camera Sleep Mode")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Text("Sleep Timer gently watches for closed eyes and auto-starts a 30-minute timer. Open your eyes for a few seconds to cancel it. It will also auto-sleep after 1.5 hours of tracking.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
        )
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camera tracking")
                .font(.system(size: 13, weight: .semibold))

            statusRow(
                icon: sleepManager.isCameraAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                color: sleepManager.isCameraAuthorized ? Color(red: 0.152, green: 0.772, blue: 0.357) : .orange,
                title: "Camera access",
                detail: sleepManager.isCameraAuthorized
                    ? "Permission granted."
                    : "Allow Sleep Timer to use the camera in System Settings."
            )

            statusRow(
                icon: sleepManager.isSessionRunning ? "video.fill" : "camera.metering.partial",
                color: sleepManager.isSessionRunning ? .accentColor : .orange,
                title: "Video feed",
                detail: sleepManager.isSessionRunning ? "Camera is active." : "Waiting for camera…"
            )

            statusRow(
                icon: sleepManager.isUserAsleep ? "moon.zzz.fill" : "eye",
                color: sleepManager.isUserAsleep ? Color(red: 0.152, green: 0.772, blue: 0.357) : .secondary,
                title: "Sleep detection",
                detail: sleepManager.statusMessage
            )

            if !sleepManager.isCameraAuthorized {
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.02)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.05)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep timer")
                .font(.system(size: 13, weight: .semibold))

            if timerManager.isTimerActive {
                Text("Timer is active.")
                    .font(.system(size: 12))
                Text("Time remaining: \(formatTime(timerManager.remainingTime))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text("Timer is waiting for closed eyes.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.02)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.05)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private func statusRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusTitle: String {
        if !sleepManager.isCameraAuthorized {
            return "Camera tracking unavailable"
        }
        if !sleepManager.isSessionRunning {
            return "Camera tracking paused"
        }
        if sleepManager.isUserAsleep {
            return "Camera tracking"
        }
        return "Camera tracking"
    }

    private var statusColor: Color {
        if !sleepManager.isCameraAuthorized {
            return .red
        }
        if !sleepManager.isSessionRunning {
            return .orange
        }
        let standardGreen = Color(red: 0.152, green: 0.772, blue: 0.357)
        return sleepManager.isUserAsleep ? standardGreen : standardGreen.opacity(0.8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
