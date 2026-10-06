import AppKit
import SwiftUI

/// The warning shown for the timer's final minute, in the top-right corner where
/// notifications appear. It is a panel rather than a notification because the
/// Sleep focus and full-screen video both hide notifications, and that is
/// exactly when this one matters.
///
/// The panel never becomes key, so a video player keeps its keyboard (Space
/// still pauses) while the buttons stay clickable.
public final class SleepWarningController {
    private let panel: NSPanel
    private let width: CGFloat = 320
    /// Gap from the top-right corner of the visible screen, in points.
    private let screenEdgeInset: CGFloat = 12

    public init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.configureAsStatusPanel()
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior.formUnion([.stationary, .ignoresCycle])
        panel.contentViewController = PanelHostController(rootView: SleepWarningView(), width: width)
    }

    /// Show the panel, keeping it pinned to the corner as its height follows the text.
    public func show() {
        if let visibleFrame = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(
                x: visibleFrame.maxX - panel.frame.width - screenEdgeInset,
                y: visibleFrame.maxY - screenEdgeInset
            ))
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    public func close() {
        panel.orderOut(nil)
    }
}

struct SleepWarningView: View {
    @ObservedObject private var timerManager = TimerManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: timerManager.endsWithDisplayOff ? "display" : "moon.zzz.fill")
                    .font(.title2)
                    .foregroundStyle(Color.panelSecondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .monospacedDigit()
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(Color.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                Spacer()
                Button(postponeText) {
                    timerManager.addTime(minutes: TimerManager.postponeMinutes)
                }
                // The panel's "+15m", written and named the same way (UX-08, UX-15).
                .durationAccessibility(visible: postponeText,
                                       spoken: "Add " + DurationFormat.words(minutes: TimerManager.postponeMinutes))
                .accessibilityIdentifier("postponeSleep")

                Button("Sleep Now") {
                    timerManager.sleepNow()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("sleepNow")
            }
            .controlSize(.regular)
        }
        .padding(16)
    }

    private var seconds: Int {
        Int(max(0, timerManager.remainingTime).rounded(.up))
    }

    private var postponeText: String {
        "+" + DurationFormat.compact(minutes: TimerManager.postponeMinutes)
    }

    /// What zero really does (UX-04): with work holding the Mac, only the
    /// display goes off, so the warning must not promise sleep.
    private var title: String {
        timerManager.endsWithDisplayOff
            ? "Turning the display off in \(seconds) s"
            : "Going to sleep in \(seconds) s"
    }

    private var subtitle: String {
        if timerManager.isUserActive {
            return "You are using your Mac, so it stays awake for another "
                + "\(DurationFormat.words(minutes: TimerManager.postponeMinutes))."
        }
        return "Use the mouse or keyboard to keep it awake."
    }
}
