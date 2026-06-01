import SwiftUI
import SleepTimerCore

@main
struct SleepTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The app is a menu-bar accessory; all UI lives in the status-bar popover
        // and a settings window the delegate manages. This scene just satisfies the
        // App requirement.
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var timerManager = TimerManager.shared
    private var sleepManager = SleepDetectionManager.shared
    private var updateChecker = UpdateChecker.shared
    private var autoActivation = AutoActivationManager.shared

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return false
        }

        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)

        // More than one instance means another is already running
        return instances.count > 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent multiple instances
        if isAnotherInstanceRunning() {
            NSLog("Sleep Timer is already running - terminating duplicate instance")
            NSApp.terminate(nil)
            return
        }

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Check launch at login status
        LaunchAtLoginManager.shared.checkStatus()

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let originalImage = NSImage(named: "MenuIcon"),
               let image = originalImage.copy() as? NSImage {
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            }
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.behavior = .transient
        popover.animates = false // instant show/resize so mode switches feel snappy
        popover.contentViewController = NSHostingController(rootView: ContentView())
        popover.delegate = self

        // Update icon when timer changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TimerUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusItem()
        }

        // Update icon when camera mode changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CameraModeChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusItem()
        }

        // Open the settings window when the popover requests it
        NotificationCenter.default.addObserver(
            forName: openSettingsNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showSettingsWindow()
        }

        updateStatusItem()

        // Start watching for idle time to auto-arm the timer at night
        autoActivation.startMonitoring()

        // Check for updates on launch (after 3 seconds delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.updateChecker.checkForUpdates(showNoUpdateAlert: false)
        }
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                stopMonitoringStatusBarPosition()
                popover.performClose(nil)
            } else {
                // Always reposition popover relative to current button bounds
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()

                // Start monitoring for status item position changes
                startMonitoringStatusBarPosition()
            }
        }
    }

    private var positionMonitorTimer: Timer?
    private var settingsWindow: NSWindow?

    @objc private func showSettingsWindow() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Sleep Timer Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }

        // Become a regular app while settings are open so the window reliably comes
        // to the front; revert to accessory (no dock icon) when it closes.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func startMonitoringStatusBarPosition() {
        stopMonitoringStatusBarPosition()

        positionMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self,
                  self.popover.isShown,
                  let button = self.statusItem.button else {
                self?.stopMonitoringStatusBarPosition()
                return
            }

            // Reposition popover to follow the button
            self.popover.positioningRect = button.bounds
        }
    }

    private func stopMonitoringStatusBarPosition() {
        positionMonitorTimer?.invalidate()
        positionMonitorTimer = nil
    }

    private func updateStatusItem() {
        if let button = statusItem.button {
            let iconName: String
            var titleText = ""

            if timerManager.isTimerActive {
                iconName = "MenuIconActive"

                let time = Int(max(0, timerManager.remainingTime))
                let hours = time / 3600
                let minutes = (time % 3600) / 60
                let seconds = time % 60

                if hours > 0 {
                    titleText = String(format: " %d:%02d:%02d", hours, minutes, seconds)
                } else {
                    titleText = String(format: " %02d:%02d", minutes, seconds)
                }
            } else {
                iconName = "MenuIcon"
            }

            if let originalImage = NSImage(named: iconName),
               let image = originalImage.copy() as? NSImage {
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            }

            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.attributedTitle = NSAttributedString(string: titleText, attributes: [.font: font])
            button.imagePosition = .imageLeft
        }
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        stopMonitoringStatusBarPosition()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // When the settings window closes, hide the dock icon again.
        if notification.object as? NSWindow === settingsWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}