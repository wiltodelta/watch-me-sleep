import Foundation

/// Minutes after midnight as people read them, and back.
enum BedtimeFormat {
    /// "10:30 PM" or "22:30", by the person's clock setting.
    static func time(_ minutes: Int, formatter: DateFormatter = shortTimeFormatter) -> String {
        formatter.string(from: date(minutes))
    }

    /// Today at that time of day, for a time picker to show.
    static func date(_ minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    /// The time of day a picker chose, in minutes after midnight.
    static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
