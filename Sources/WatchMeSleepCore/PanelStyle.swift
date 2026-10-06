import SwiftUI

extension Color {
    /// Secondary text on the glass panels. The system `.secondary` measured
    /// 2.91:1 in light and 3.15:1 in dark there (UX-01), under the 4.5:1 small
    /// text needs; this keeps the softer look at a readable contrast.
    static let panelSecondary = Color.primary.opacity(0.66)
}

extension View {
    /// A control whose visible text is short ("15m", "+5m"): VoiceOver reads the
    /// words, and Voice Control also answers to what is written (UX-15,
    /// WCAG 2.5.3).
    func durationAccessibility(visible: String, spoken: String) -> some View {
        accessibilityLabel(spoken).accessibilityInputLabels([Text(visible), Text(spoken)])
    }
}
