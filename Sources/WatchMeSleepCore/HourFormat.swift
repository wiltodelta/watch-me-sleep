import Foundation

/// A whole hour in the user's clock style: "10 PM" in the US, "22:00" where a
/// 24-hour clock is the norm or the user chose one.
public enum HourFormat {
    public static func label(_ hour: Int, locale: Locale = .current) -> String {
        // "j" is the locale's preferred hour symbol: "h a" for a 12-hour clock.
        let hourStyle = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(hourStyle.contains("a") ? "j" : "HH:mm")
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(hour: hour)) ?? Date()
        return formatter.string(from: date)
    }
}
