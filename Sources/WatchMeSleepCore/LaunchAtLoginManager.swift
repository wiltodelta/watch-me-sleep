import Foundation
import AppKit
import Combine
import os
import ServiceManagement

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// "Launch at login" through SMAppService, which is the only record of whether it
/// is on (a second copy in the defaults could drift from what macOS does).
@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager(service: SMAppService.mainApp)

    @Published public private(set) var isEnabled: Bool
    /// Why the last change was refused, shown under the toggle; nil when it worked.
    @Published public private(set) var errorMessage: String?

    private let log = Logger.app("login-item")
    private let service: any LoginItemService
    private var statusObservation: AnyCancellable?
    private var awaitingApproval = false

    init(service: any LoginItemService, notificationCenter: NotificationCenter = .default) {
        self.service = service
        isEnabled = service.status == .enabled
        statusObservation = notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                // AppKit delivers activation on the main thread.
                MainActor.assumeIsolated { self?.checkStatus() }
            }
    }

    public func checkStatus() {
        let status = service.status
        isEnabled = status == .enabled
        if awaitingApproval, status != .requiresApproval {
            awaitingApproval = false
            errorMessage = nil
        }
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            // Registered, but switched off by the user in Login Items: no error
            // is thrown, so say where to allow it.
            awaitingApproval = enabled && service.status == .requiresApproval
            errorMessage = awaitingApproval
                ? "allow Watch Me Sleep in System Settings > General > Login Items."
                : nil
        } catch {
            awaitingApproval = false
            log.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        checkStatus()
    }
}
