import AppKit
import Sparkle

/// Twin of translate-like-me's Updater.swift (same Sparkle setup, different
/// observation wrapper); keep the two in step.
///
/// In-place updates through Sparkle: it reads the appcast each release publishes
/// (`SUFeedURL` in Info.plist), checks once a day, verifies the EdDSA signature
/// (`SUPublicEDKey`) and installs the new build on request.
///
/// The app lives in the menu bar, so a scheduled check must not steal focus
/// (Sparkle's gentle reminders): a found update is announced by the panel footer
/// instead, and Sparkle's window comes forward only when the user chooses it or
/// checks by hand.
@MainActor
public final class Updater: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    public static let shared = Updater()

    /// The version a scheduled check found and the user has not acted on yet.
    @Published public private(set) var pendingVersion: String?

    private var controller: SPUStandardUpdaterController!

    public let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

    override private init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                  userDriverDelegate: self)
    }

    /// Starts the scheduled checks; call once at launch.
    public func start() {
        _ = controller
    }

    public var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// A user-initiated check, or bringing forward the update a scheduled check
    /// found; Sparkle shows its own progress and result window.
    public func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // MARK: - SPUStandardUserDriverDelegate

    public nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    public nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Show Sparkle's window only if the app is already in front (Settings is
        // open); otherwise the panel footer announces it.
        immediateFocus
    }

    public nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        let announce = !handleShowingUpdate && !state.userInitiated
        MainActor.assumeIsolated { pendingVersion = announce ? version : nil }
    }

    public nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { pendingVersion = nil }
    }

    public nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { pendingVersion = nil }
    }
}
