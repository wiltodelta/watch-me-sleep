import SwiftUI
import SleepTimerCore

@main
struct SleepTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The app is a menu-bar accessory; all UI lives in the status-bar panel
        // and a settings window the delegate manages. This scene just satisfies the
        // App requirement.
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: MenuBarPanelController!
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
            button.action = #selector(togglePanel)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create the arrowless dropdown panel
        panel = MenuBarPanelController(rootView: ContentView(), size: NSSize(width: 360, height: 420))

        // Update icon when timer changes
        NotificationCenter.default.addObserver(
            forName: .timerUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusItem()
        }

        // Update icon when camera mode changes
        NotificationCenter.default.addObserver(
            forName: .cameraModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusItem()
        }

        // Open the settings window when the panel requests it
        NotificationCenter.default.addObserver(
            forName: .openSettings,
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

    @objc func togglePanel() {
        // Right-click shows a quick-action menu instead of the panel.
        if NSApp.currentEvent?.type == .rightMouseUp {
            panel.close()
            showQuickMenu()
            return
        }

        guard let button = statusItem.button else { return }
        if panel.isShown {
            panel.close()
        } else {
            panel.show(relativeTo: button)
        }
    }

    private func showQuickMenu() {
        guard let button = statusItem.button else { return }

        let menu = NSMenu()

        if timerManager.isTimerActive {
            let stop = NSMenuItem(title: "Stop Timer", action: #selector(quickStopTimer), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        } else {
            let startItem = NSMenuItem(title: "Start Timer", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let presets: [(String, Double)] = [
                ("15 Minutes", 0.25), ("30 Minutes", 0.5), ("1 Hour", 1.0), ("1.5 Hours", 1.5), ("2 Hours", 2.0)
            ]
            for (title, hours) in presets {
                let item = NSMenuItem(title: title, action: #selector(quickStartTimer(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = hours
                submenu.addItem(item)
            }
            menu.addItem(startItem)
            menu.setSubmenu(submenu, for: startItem)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Sleep Timer", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func quickStartTimer(_ sender: NSMenuItem) {
        guard let hours = sender.representedObject as? Double else { return }
        timerManager.startTimer(hours: hours)
    }

    @objc private func quickStopTimer() {
        timerManager.stopTimer()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

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
            button.toolTip = statusTooltip()
        }
    }

    private func statusTooltip() -> String {
        if timerManager.isTimerActive {
            return "Sleep Timer running"
        }
        if autoActivation.isEnabled {
            return String(format: "Auto-start armed: timer when idle after %02d:00", autoActivation.activeAfterHour)
        }
        return "Sleep Timer"
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
