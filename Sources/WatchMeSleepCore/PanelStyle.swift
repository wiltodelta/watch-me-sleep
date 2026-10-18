import SwiftUI

extension Color {
    /// Secondary text on the readable system backing used by panels and Settings.
    /// Contrast also depends on that backing, not just this foreground opacity.
    static let secondaryText = Color.primary.opacity(0.66)
}

extension View {
    /// A control whose visible text is short ("15m", "+5m"): VoiceOver reads the
    /// words, and Voice Control also answers to what is written (UX-15,
    /// WCAG 2.5.3).
    func durationAccessibility(visible: String, spoken: String) -> some View {
        accessibilityLabel(spoken).accessibilityInputLabels([Text(visible), Text(spoken)])
    }

    /// The panel's default action: prominent, and Return presses it.
    @ViewBuilder
    func panelDefaultAction(_ isDefault: Bool) -> some View {
        if isDefault {
            readableProminentAction().keyboardShortcut(.defaultAction)
        } else {
            self
        }
    }

    func readableProminentAction() -> some View {
        modifier(ReadableProminentAction())
    }
}

/// Preserve the user's accent hue while giving white button labels enough
/// contrast. Standard blue with white small text falls below 4.5:1.
private struct ReadableProminentAction: ViewModifier {
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        let accent = Color.accentColor.resolve(in: environment)
        let channels = [Double(accent.red), Double(accent.green), Double(accent.blue)]
        let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        let luminance = zip(linear, [0.2126, 0.7152, 0.0722]).reduce(0) { $0 + $1.0 * $1.1 }
        let scale = min(1, 0.16 / max(luminance, 0.0001))
        let rgb = linear.map { value in
            let scaled = value * scale
            return scaled <= 0.0031308 ? 12.92 * scaled : 1.055 * pow(scaled, 1 / 2.4) - 0.055
        }
        content.buttonStyle(.borderedProminent)
            .tint(Color(.sRGB, red: rgb[0], green: rgb[1], blue: rgb[2]))
            .foregroundStyle(.white)
    }
}
