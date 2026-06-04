import Foundation

/// App-internal notification names, centralized so posters and observers share a
/// single source of truth instead of repeating raw string literals across files.
public extension Notification.Name {
    /// Posted whenever the timer starts, stops, or ticks, so the menu bar item can refresh.
    static let timerUpdated = Notification.Name("TimerUpdated")

    /// Posted when camera mode is toggled or sleep/wake is detected, so the icon updates.
    static let cameraModeChanged = Notification.Name("CameraModeChanged")

    /// Posted right before sleep so the UI switches back from camera mode to manual mode.
    static let cameraModeDisabled = Notification.Name("CameraModeDisabled")

    /// Posted by the popover to ask the app delegate to open the settings window.
    /// A menu-bar `.accessory` app cannot rely on the SwiftUI `Settings` scene, so the
    /// delegate hosts `SettingsView` in its own window in response to this.
    static let openSettings = Notification.Name("OpenSettings")
}
