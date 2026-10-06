import Foundation

/// App-internal notification names, centralized so posters and observers share a
/// single source of truth instead of repeating raw string literals across files.
public extension Notification.Name {
    /// Posted whenever the timer starts, stops, or ticks, so the menu bar item can refresh.
    static let timerUpdated = Notification.Name("TimerUpdated")

    /// Posted by the panel to ask the app delegate to open the settings window.
    /// A menu-bar `.accessory` app cannot rely on the SwiftUI `Settings` scene, so the
    /// delegate hosts `SettingsView` in its own window in response to this.
    static let openSettings = Notification.Name("OpenSettings")
}
