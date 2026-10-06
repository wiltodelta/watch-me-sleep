import SwiftUI
import AppKit

/// The panel's first row: what the night watch is doing right now, in words.
struct NightWatchStatusView: View {
    @ObservedObject private var supervisor = SleepSupervisor.shared

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Decorative: the title already says it.
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.panelSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(supervisor.statusTitle)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("nightWatchStatus")
            Spacer(minLength: 0)
            // The way out of "off" is right here, not a trip to Settings (UX-12).
            if supervisor.status == .off {
                Button("Turn On") { supervisor.isEnabled = true }
                    .controlSize(.regular)
                    .accessibilityIdentifier("turnOnNightWatch")
            }
        }
    }

    private var icon: String {
        switch supervisor.status {
        case .off, .noBedtime: return "moon"
        case .looking: return "eye"
        case .watching(_, let mediaPlaying, _): return mediaPlaying ? "play.tv" : "moon.stars"
        default: return "moon.stars"
        }
    }

    private var detail: String {
        switch supervisor.status {
        case .off:
            return "It sleeps the Mac once you fall asleep."
        case .outsideHours:
            return "Until then, set a timer below."
        case .inUse:
            return "It steps in once you stop using your Mac."
        case .timerRunning:
            return "A minute before the end you can keep the Mac awake."
        case let .watching(idleMinutes, _, nextLook):
            // Never "0 min" (UX-07): under a minute says so.
            let idle = idleMinutes < 1
                ? "No input for less than a minute."
                : "No input for \(DurationFormat.words(minutes: idleMinutes))."
            guard let nextLook else { return idle }
            return idle + " The camera looks at \(shortTimeFormatter.string(from: nextLook))."
        case .looking:
            return "Checking whether you are still watching. Nothing is recorded."
        case .done:
            return "The Mac sleeps by itself once the work finishes."
        case .noBedtime:
            return "It starts and ends at the same time. Change it in Settings."
        }
    }
}

/// The camera check in Settings: a thumbnail at the video's own proportions
/// beside what the night watch makes of it, in words, not only color. The
/// camera runs only while this row is on screen.
struct CameraPreviewRow: View {
    @ObservedObject private var camera = CameraWatcher.shared
    /// Big enough to see a face, a form row rather than a stage.
    private static let thumbnailHeight: CGFloat = 96

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            thumbnail
            // The icon sits right next to its title, and the hint starts at
            // the same left edge as the icon. A `Label` here took the form's
            // label style and pushed the title a column away from its icon.
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Color on the symbol only: green text on a light form
                    // fails contrast, and the words carry the state anyway.
                    Image(systemName: statusIcon)
                        .foregroundStyle(camera.isFaceDetected ? Color.green : Color.panelSecondary)
                    Text(statusTitle)
                }
                .font(.callout.weight(.medium))
                Text("Sit where you usually watch from. The light of the screen is enough.")
                    .font(.caption)
                    .foregroundStyle(Color.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .onAppear { camera.setPreviewActive(true) }
        .onDisappear { camera.setPreviewActive(false) }
        .animation(.easeInOut(duration: 0.2), value: camera.isFaceDetected)
    }

    private var thumbnail: some View {
        ZStack {
            Color.black
            CameraPreview()
            if !camera.isSessionRunning {
                ProgressView().controlSize(.small)
            }
        }
        // The camera's own proportions, so the frame neither crops nor pads
        // the video; 4:3 until the first frame says otherwise.
        .frame(width: Self.thumbnailHeight * (camera.videoAspectRatio ?? 4 / 3), height: Self.thumbnailHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        // One labeled image for VoiceOver; `capture-screenshots.sh` also finds
        // the feed by this identifier to blur it before a screenshot is published.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera preview")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("cameraPreview")
    }

    private var statusTitle: String {
        if !camera.isSessionRunning { return "Starting the camera…" }
        return camera.isFaceDetected ? "Your face is visible" : "Looking for your face…"
    }

    private var statusIcon: String {
        if !camera.isSessionRunning { return "camera" }
        return camera.isFaceDetected ? "checkmark.circle.fill" : "eye.slash"
    }
}

/// Live camera feed hosted from the capture session's preview layer.
final class PreviewHostView: NSView {
    let previewLayer = CameraWatcher.shared.makePreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = previewLayer
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> PreviewHostView {
        PreviewHostView(frame: .zero)
    }

    func updateNSView(_ nsView: PreviewHostView, context: Context) {}
}
