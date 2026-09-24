import SwiftUI
import AppKit
import AVFoundation

public struct ContentView: View {
    @StateObject private var timerManager = TimerManager.shared
    @StateObject private var sleepManager = SleepDetectionManager.shared
    @State private var selectedMode: TimerMode = .manual
    @State private var selectedHours: Double = 1.5

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // A text-only segmented control needs no introductory label (HIG).
            Picker("Mode", selection: $selectedMode) {
                Text("Timer").tag(TimerMode.manual)
                Text("Camera").tag(TimerMode.camera)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
            .animation(.easeInOut(duration: 0.12), value: selectedMode)
            .animation(.easeInOut(duration: 0.18), value: timerManager.isTimerActive)

            Divider()

            // Common settings footer
            CommonSettingsView()
        }
        // The panel provides the material backing, so the content stays
        // transparent and lets it show through.
        .onAppear {
            sleepManager.setCameraModeEnabled(selectedMode == .camera)

            // Notify status bar to update icon on launch
            NotificationCenter.default.post(name: .cameraModeChanged, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraModeDisabled)) { _ in
            // Switch back to manual mode when camera mode is disabled externally (e.g., after system wake)
            if selectedMode == .camera {
                selectedMode = .manual
            }
        }
        .onChange(of: selectedMode) { _, newMode in
            // Stop active timer when switching modes
            if timerManager.isTimerActive {
                timerManager.stopTimer()
            }

            sleepManager.setCameraModeEnabled(newMode == .camera)

            // Notify status bar to update icon
            NotificationCenter.default.post(name: .cameraModeChanged, object: nil)
        }
    }
}

enum TimerMode {
    case manual
    case camera
}

struct CommonSettingsView: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        HStack(spacing: 16) {
            // Opens a window, so the title ends with an ellipsis (HIG).
            Button {
                openAppSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .accessibilityIdentifier("openSettings")

            // Sparkle's gentle reminder: a scheduled check found this update.
            if let version = updater.pendingVersion {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Install \(version)…", systemImage: "arrow.down.circle")
                }
                .help("Install version \(version)")
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct InactiveTimerView: View {
    @Binding var selectedHours: Double

    private let presetHours: [Double] = [0.25, 0.5, 1, 1.5, 2, 3, 4, 6]
    private let range: ClosedRange<Double> = 0.25...12

    var body: some View {
        VStack(spacing: 0) {
            // Time display
            VStack(spacing: 12) {
                Text(formatHours(selectedHours))
                    .font(.system(size: 48, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)

                durationSlider
                    .labelsHidden()
                    .accessibilityValue(spokenDuration(hours: selectedHours))
                    .controlSize(.small)

                HStack {
                    Text("15 min")
                    Spacer()
                    Text("12 hours")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .padding(20)
            .padding(.top, 12)

            Divider()

            // Presets
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    ForEach(presetHours.prefix(4), id: \.self) { hours in
                        PresetButton(hours: hours, selectedHours: $selectedHours)
                    }
                }
                GridRow {
                    ForEach(presetHours.suffix(4), id: \.self) { hours in
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
            .accessibilityIdentifier("startTimer")
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    /// Tick marks on whole hours only (HIG: tick marks add clarity). macOS 26
    /// can place them, but a `step` still draws a dot per step, so there the
    /// quarter-hour snapping moves into the binding. Earlier releases draw one
    /// tick per step.
    @ViewBuilder private var durationSlider: some View {
        if #available(macOS 26.0, *) {
            let snapped = Binding(
                get: { selectedHours },
                set: { selectedHours = ($0 * 4).rounded() / 4 }
            )
            Slider(value: snapped, in: range) {
                Text("Timer length")
            } ticks: {
                SliderTickContentForEach((1...12).map(Double.init), id: \.self) { hour in
                    SliderTick(hour)
                }
            }
        } else {
            Slider(value: $selectedHours, in: range, step: 0.25) {
                Text("Timer length")
            }
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
}

struct PresetButton: View {
    let hours: Double
    @Binding var selectedHours: Double

    private var isSelected: Bool { selectedHours == hours }

    var body: some View {
        // The selected preset changes style, not just tint, so the choice does
        // not rely on color alone (HIG); two prominent buttons per view at most.
        Button {
            selectedHours = hours
        } label: {
            Text(formatHoursShort(hours))
                .frame(maxWidth: .infinity)
        }
        .modifier(PresetStyle(isSelected: isSelected))
        .controlSize(.regular)
        .accessibilityLabel(spokenDuration(hours: hours))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

private struct PresetStyle: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

struct ActiveTimerView: View {
    @StateObject private var timerManager = TimerManager.shared

    private var elapsedFraction: Double {
        guard timerManager.totalTime > 0 else { return 0 }
        return 1 - timerManager.remainingTime / timerManager.totalTime
    }

    var body: some View {
        VStack(spacing: 0) {
            // Circular progress: the track fills clockwise as time elapses (HIG).
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 12)

                    Circle()
                        .trim(from: 0, to: elapsedFraction)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text(formatTime(timerManager.remainingTime))
                            .font(.system(.largeTitle, design: .rounded).weight(.medium))
                            .monospacedDigit()
                        Text("remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 140, height: 140)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time remaining")
                .accessibilityValue(formatTime(timerManager.remainingTime))

                Text("Sleep at \(formatTargetTime(timerManager.remainingTime))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .padding(.top, 12)

            Divider()

            // Add time buttons
            HStack(spacing: 12) {
                ForEach([5, 15, 30, 60], id: \.self) { minutes in
                    Button {
                        timerManager.addTime(minutes: minutes)
                    } label: {
                        Text("+\(minutes)m")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .accessibilityLabel("Add \(minutes) minutes")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Stopping a timer destroys no data, so it takes no destructive red (HIG).
            Button("Stop Timer") {
                timerManager.stopTimer()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("stopTimer")
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

    // Created once: the view redraws every second while the timer runs.
    private static let targetTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private func formatTargetTime(_ remainingTime: TimeInterval) -> String {
        Self.targetTimeFormatter.string(from: Date().addingTimeInterval(remainingTime))
    }
}

private let spokenDurationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .full
    return formatter
}()

/// A duration as VoiceOver should read it, e.g. "1 hour, 30 minutes".
func spokenDuration(hours: Double) -> String {
    spokenDurationFormatter.string(from: hours * 3600) ?? ""
}
