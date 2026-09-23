import SwiftUI
import WatchMeSleepCore

@main
struct WatchMeSleepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The app is a menu-bar accessory; all UI lives in the status-bar panel
        // and a settings window the delegate manages. This scene just satisfies the
        // App requirement; its App-menu item is rerouted so Settings… (⌘,) opens
        // the real settings window, as the HIG expects, not this empty scene.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { openAppSettings() }
                    .keyboardShortcut(",")
            }
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
            NSLog("Watch Me While I Fall Asleep is already running - terminating duplicate instance")
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
            // VoiceOver reads the image-only button by this label (HIG: provide an
            // accessibility label for every icon); the countdown is its value.
            button.setAccessibilityLabel("Watch Me While I Fall Asleep")
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create the arrowless dropdown panel. capture-screenshots.sh finds it by
        // this width.
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
            self?.updateChecker.checkForUpdates(userInitiated: false)
        }
    }

    /// The status item can be hidden by the system or by the person, so relaunching
    /// the app (Finder, Spotlight) must still reach its UI (HIG: avoid relying on
    /// the presence of menu bar extras).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return false
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
            let stop = NSMenuItem(title: "Stop timer", action: #selector(quickStopTimer), keyEquivalent: "")
            stop.target = self
            setMenuSymbol("stop.circle", on: stop)
            menu.addItem(stop)
        } else {
            let startItem = NSMenuItem(title: "Start timer", action: nil, keyEquivalent: "")
            setMenuSymbol("timer", on: startItem)
            let submenu = NSMenu()
            let presets: [(String, Double)] = [
                ("15 minutes", 0.25), ("30 minutes", 0.5), ("1 hour", 1.0), ("1.5 hours", 1.5), ("2 hours", 2.0)
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
        setMenuSymbol("gearshape", on: settings)
        menu.addItem(settings)

        // The standard selector lets macOS 26+ give the item its system icon.
        menu.addItem(NSMenuItem(title: "Quit Watch Me While I Fall Asleep",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    /// macOS 26+ menus show icons for common actions; `terminate:` gets its icon
    /// from the system, so the other top-level items need one to keep the
    /// column aligned. Earlier releases draw menus without icons.
    private func setMenuSymbol(_ name: String, on item: NSMenuItem) {
        if #available(macOS 26.0, *) {
            item.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
    }

    @objc private func quickStartTimer(_ sender: NSMenuItem) {
        guard let hours = sender.representedObject as? Double else { return }
        timerManager.startTimer(hours: hours)
    }

    @objc private func quickStopTimer() {
        timerManager.stopTimer()
    }

    private var settingsWindow: NSWindow?

    @objc private func showSettingsWindow() {
        // Dismiss the dropdown panel so it doesn't linger behind the settings window.
        panel.close()

        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Watch Me While I Fall Asleep Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }

        // Become a regular app while settings are open so the window reliably comes
        // to the front; revert to accessory (no dock icon) when it closes.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateStatusItem() {
        if let button = statusItem.button {
            let iconName: String
            var countdown = ""

            if timerManager.isTimerActive {
                iconName = "MenuIconActive"

                let time = Int(max(0, timerManager.remainingTime))
                let hours = time / 3600
                let minutes = (time % 3600) / 60
                let seconds = time % 60

                if hours > 0 {
                    countdown = String(format: "%d:%02d:%02d", hours, minutes, seconds)
                } else {
                    countdown = String(format: "%02d:%02d", minutes, seconds)
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
            let title = countdown.isEmpty ? "" : " " + countdown
            button.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
            button.imagePosition = .imageLeft
            button.toolTip = statusTooltip()
            button.setAccessibilityValue(countdown.isEmpty ? nil : "\(countdown) remaining")
        }
    }

    private func statusTooltip() -> String {
        if timerManager.isTimerActive {
            return "Watch Me While I Fall Asleep running"
        }
        if autoActivation.isEnabled {
            return String(format: "Auto-start armed: timer when idle after %02d:00", autoActivation.activeAfterHour)
        }
        return "Watch Me While I Fall Asleep"
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
