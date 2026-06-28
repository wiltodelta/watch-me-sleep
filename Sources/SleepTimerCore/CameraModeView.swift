import SwiftUI
import AppKit
import AVFoundation

struct CameraModeView: View {
    @StateObject private var sleepManager = SleepDetectionManager.shared
    @StateObject private var timerManager = TimerManager.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 12) {
            introSection
            previewSection
            statusCard
            timerCard
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: sleepManager.isUserAsleep)
        .animation(.easeInOut(duration: 0.18), value: timerManager.isTimerActive)
    }

    @ViewBuilder private var previewSection: some View {
        if sleepManager.isCameraAuthorized {
            ZStack {
                CameraPreview()
                if !sleepManager.isSessionRunning {
                    Color.primary.opacity(0.06)
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        sleepManager.isFaceDetected ? Color.green : Color.primary.opacity(0.12),
                        lineWidth: sleepManager.isFaceDetected ? 2 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: sleepManager.isFaceDetected)
            .animation(.easeInOut(duration: 0.2), value: sleepManager.isSessionRunning)
        }
    }

    private var introSection: some View {
        VStack(spacing: 6) {
            Text("Camera Sleep Mode")
                .font(.headline)

            Text("Sleep Timer gently watches for closed eyes and auto-starts a 30-minute timer. "
                + "Open your eyes for a few seconds to cancel it. "
                + "It will also auto-sleep after 1.5 hours of tracking.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camera tracking")
                .font(.system(size: 13, weight: .semibold))

            statusRow(
                icon: sleepManager.isCameraAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                color: sleepManager.isCameraAuthorized ? Color.green : .orange,
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
                color: sleepManager.isUserAsleep ? Color.green : .secondary,
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
        .card()
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
        .card()
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

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// Live camera feed hosted from the capture session's preview layer.
final class PreviewHostView: NSView {
    let previewLayer = SleepDetectionManager.shared.makePreviewLayer()

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

/// Restrained, system-style card used to group content in the panel.
private struct Card: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private extension View {
    func card() -> some View { modifier(Card()) }
}
