import Foundation

/// The one way the app writes a length of time (UX-08): compact on controls
/// and numbers ("15m", "1h 30m"), whole words inside sentences ("8 hours"),
/// and one countdown shape on every surface ("1:29:54", "29:54").
public enum DurationFormat {
    /// "15m", "1h 30m", "8h", in the person's locale.
    public static func compact(minutes: Int) -> String {
        compactFormatter.string(from: TimeInterval(minutes * 60)) ?? ""
    }

    /// "15 minutes", "1 hour, 30 minutes": for sentences and for VoiceOver.
    public static func words(minutes: Int) -> String {
        wordsFormatter.string(from: TimeInterval(minutes * 60)) ?? ""
    }

    /// The same, for a length given in hours.
    public static func compact(hours: Double) -> String {
        compact(minutes: minutes(hours))
    }

    /// The same, for a length given in hours.
    public static func words(hours: Double) -> String {
        words(minutes: minutes(hours))
    }

    /// Whole minutes in a length given in hours.
    static func minutes(_ hours: Double) -> Int {
        Int((hours * 60).rounded())
    }

    /// "1:29:54" with hours, "29:54" without, for the ring and the menu bar.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let (hours, minutes, secs) = (total / 3600, total % 3600 / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    private static let compactFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let wordsFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        return formatter
    }()
}
