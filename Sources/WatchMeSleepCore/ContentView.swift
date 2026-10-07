import SwiftUI
import AppKit

public struct ContentView: View {
    @StateObject private var timerManager = TimerManager.shared
    @ObservedObject private var supervisor = SleepSupervisor.shared
    /// The last length chosen, so the panel offers it again; two hours, about
    /// a film, until then.
    @AppStorage("Timer.selectedHours") private var selectedHours: Double = 2

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            NightWatchStatusView(timerStopsOnInput: timerManager.stopsOnInput)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

            Divider()
            Group {
                if timerManager.isTimerActive {
                    ActiveTimerView()
                } else {
                    // "Turn On Night Watch" is the default action while the watch is off.
                    InactiveTimerView(selectedHours: $selectedHours,
                                      isDefaultAction: supervisor.status != .off)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: timerManager.isTimerActive)

            Divider()

            CommonSettingsView()
        }
        // The panel provides the material backing, so the content stays
        // transparent and lets it show through.
    }
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
                    .footerTarget()
            }
            .accessibilityIdentifier("openSettings")

            // Sparkle's gentle reminder: a scheduled check found this update.
            if let version = updater.pendingVersion {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Install \(version)…", systemImage: "arrow.down.circle")
                        .footerTarget()
                }
                .help("Install version \(version)")
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit").footerTarget()
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.panelSecondary)
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct InactiveTimerView: View {
    @Binding var selectedHours: Double
    let isDefaultAction: Bool

    private let range: ClosedRange<Double> = 0.25...12

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Or sleep after a set time")
                    .font(.headline)
                Spacer()
                Text(DurationFormat.compact(hours: selectedHours))
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
            }
            durationSlider
                .labelsHidden()
                .accessibilityValue(DurationFormat.words(hours: selectedHours))
                .controlSize(.small)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    ForEach(TimerManager.presetHours.prefix(4), id: \.self) { hours in
                        PresetButton(hours: hours, selectedHours: $selectedHours)
                    }
                }
                GridRow {
                    ForEach(TimerManager.presetHours.suffix(4), id: \.self) { hours in
                        PresetButton(hours: hours, selectedHours: $selectedHours)
                    }
                }
            }
            Button("Start Timer") {
                TimerManager.shared.startTimer(hours: selectedHours)
            }
            .panelDefaultAction(isDefaultAction)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("startTimer")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
            Text(DurationFormat.compact(hours: hours))
                .frame(maxWidth: .infinity)
        }
        .modifier(PresetStyle(isSelected: isSelected))
        .controlSize(.regular)
        .durationAccessibility(visible: DurationFormat.compact(hours: hours),
                               spoken: DurationFormat.words(hours: hours))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                        Text(DurationFormat.countdown(timerManager.remainingTime))
                            .font(.system(.largeTitle, design: .rounded).weight(.medium))
                            .monospacedDigit()
                        Text("remaining")
                            .font(.caption)
                            .foregroundStyle(Color.panelSecondary)
                    }
                }
                .frame(width: 140, height: 140)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time remaining")
                .accessibilityValue(DurationFormat.countdown(timerManager.remainingTime))

                // What zero really does (UX-04): with work holding the Mac,
                // only the display goes off.
                Text("\(timerManager.endsWithDisplayOff ? "Display off" : "Sleep") at "
                     + formatTargetTime(timerManager.remainingTime))
                    .font(.callout)
                    .foregroundStyle(Color.panelSecondary)
            }
            .padding(20)
            .padding(.top, 12)

            Divider()

            // Add time buttons
            HStack(spacing: 12) {
                ForEach([5, 15, 30, 60], id: \.self) { minutes in
                    let label = "+" + DurationFormat.compact(minutes: minutes)
                    Button {
                        timerManager.addTime(minutes: minutes)
                    } label: {
                        Text(label)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .durationAccessibility(visible: label, spoken: "Add " + DurationFormat.words(minutes: minutes))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Stopping a timer destroys no data, so it takes no destructive red (HIG).
            // No Escape shortcut (UX-03): Escape closes the panel, and a timer
            // that would let the Mac sleep tonight is not cancelled by a reflex.
            Button("Stop Timer") {
                timerManager.stopTimer()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("stopTimer")
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func formatTargetTime(_ remainingTime: TimeInterval) -> String {
        shortTimeFormatter.string(from: Date().addingTimeInterval(remainingTime))
    }
}

/// A clock time as the person's settings write it, e.g. "23:40" or "11:40 PM".
/// Created once: the panel redraws every second while a timer runs.
let shortTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter
}()

private extension View {
    /// A footer action at least 28 pt tall, the default control height on macOS;
    /// the bare label was 15 pt, under the 20 pt minimum (UX-02).
    func footerTarget() -> some View {
        padding(.vertical, 6)
            .padding(.horizontal, 4)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
    }
}
