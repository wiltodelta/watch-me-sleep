import AppKit
import Sparkle

// Shared by translate-like-me, watch-me-sleep and rota: change every copy together
// (claude-config docs/macos-apps.md, "Shared files").
//
/// In-place updates through Sparkle: it reads the appcast each release publishes
/// (`SUFeedURL` in Info.plist), checks once a day, verifies the EdDSA signature
/// (`SUPublicEDKey`) and installs the new build on request.
///
/// The app lives in the menu bar, so a scheduled check must not steal focus
/// (Sparkle's gentle reminders): a found update is announced in the app's own
/// menu or panel instead, and Sparkle's window comes forward only when the user
/// chooses it or checks by hand.
@MainActor
public final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    public static let shared = Updater()

    /// The version a scheduled check found and the user has not acted on yet.
    @Published public private(set) var pendingVersion: String?

    /// Set just before Sparkle quits the app to relaunch the installed update.
    public private(set) var relaunchingForUpdate = false

    private var controller: SPUStandardUpdaterController!

    public let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

    override private init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self,
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
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: - SPUUpdaterDelegate

    public nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { relaunchingForUpdate = true }
    }

    // MARK: - SPUStandardUserDriverDelegate

    public nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    public nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Show Sparkle's window only if the app is already in front (Settings is
        // open); otherwise the app's own UI announces it. Sparkle also reports
        // "immediate focus" for a check made right after launch, which for a login
        // item is exactly while the user is typing elsewhere: the window took focus
        // over their app (translate-like-me UX audit 2026-09-28, UX-T01).
        immediateFocus && MainActor.assumeIsolated { NSApp.isActive }
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
