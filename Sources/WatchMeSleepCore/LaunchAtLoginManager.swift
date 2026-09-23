import Foundation
import ServiceManagement

public class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()

    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "LaunchAtLogin")
            if isEnabled {
                enableLaunchAtLogin()
            } else {
                disableLaunchAtLogin()
            }
        }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "LaunchAtLogin")
    }

    public func checkStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func enableLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status != .enabled {
                try service.register()
            }
        } catch {
            NSLog("Failed to enable launch at login: \(error.localizedDescription)")
        }
    }

    private func disableLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("Failed to disable launch at login: \(error.localizedDescription)")
        }
    }
}
