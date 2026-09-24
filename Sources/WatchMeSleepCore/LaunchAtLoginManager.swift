import Foundation
import os
import ServiceManagement

/// "Launch at login" through SMAppService, which is the only record of whether it
/// is on (a second copy in the defaults could drift from what macOS does).
@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()

    @Published public private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    /// Why the last change was refused, shown under the toggle; nil when it worked.
    @Published public private(set) var errorMessage: String?

    private let log = Logger.app("login-item")

    private init() {}

    public func checkStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            // Registered, but switched off by the user in Login Items: no error
            // is thrown, so say where to allow it.
            errorMessage = enabled && service.status == .requiresApproval
                ? "allow Watch Me While I Fall Asleep in System Settings > General > Login Items."
                : nil
        } catch {
            log.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        checkStatus()
    }
}
