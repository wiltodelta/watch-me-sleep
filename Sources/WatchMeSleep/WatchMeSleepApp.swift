import Combine
import os
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
            // The default item opened "Help isn’t available" (UX-09); the
            // README is the app's documentation.
            CommandGroup(replacing: .help) {
                Button("Watch Me While I Fall Asleep Help") {
                    if let url = URL(string: "https://github.com/wiltodelta/watch-me-sleep#readme") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: MenuBarPanelController!
    /// Built for the final minute only: hidden, its view would still re-render
    /// on every tick of a timer that may run for hours.
    private var sleepWarning: SleepWarningController?
    private var timerManager = TimerManager.shared
    private var supervisor = SleepSupervisor.shared
    private var statusObservation: AnyCancellable?

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
            Logger.app("app").info("Another instance is running; quitting this one")
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
            self?.updateSleepWarning()
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

        // The night watch: sleep the Mac once nobody is using it at bedtime.
        supervisor.startMonitoring()
        // The tooltip says what the panel's status says, so it follows it.
        statusObservation = supervisor.$status.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateStatusItem()
        }

        // Sparkle's daily checks (Updater).
        Updater.shared.start()
    }

    private func updateSleepWarning() {
        if timerManager.isInFinalPhase {
            if sleepWarning == nil { sleepWarning = SleepWarningController() }
            sleepWarning?.show()
        } else if let warning = sleepWarning {
            warning.close()
            sleepWarning = nil
        }
    }

    /// Quitting drops the timer; put back any volume its final minute lowered.
    func applicationWillTerminate(_ notification: Notification) {
        timerManager.stopTimer()
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

        // What the night watch is doing, as on the panel (UX-11).
        let status = NSMenuItem(title: supervisor.statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if timerManager.isTimerActive {
            let stop = NSMenuItem(title: "Stop Timer", action: #selector(quickStopTimer), keyEquivalent: "")
            stop.target = self
            setMenuSymbol("stop.circle", on: stop)
            menu.addItem(stop)
        } else {
            let startItem = NSMenuItem(title: "Start Timer", action: nil, keyEquivalent: "")
            setMenuSymbol("timer", on: startItem)
            let submenu = NSMenu()
            // The panel's presets, written the same way (UX-08, UX-11).
            for hours in TimerManager.presetHours {
                let title = DurationFormat.compact(hours: hours)
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
        // AppKit would focus the first editable control, the bedtime field, so a
        // stray key could change bedtime; start with nothing focused instead.
        settingsWindow?.makeFirstResponder(nil)
    }

    private func updateStatusItem() {
        if let button = statusItem.button {
            let iconName: String
            var countdown = ""

            if timerManager.isTimerActive {
                iconName = "MenuIconActive"

                countdown = DurationFormat.countdown(timerManager.remainingTime)
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
            // The panel's status title (UX-10): one sentence for the same state.
            button.toolTip = supervisor.statusTitle
            button.setAccessibilityValue(countdown.isEmpty ? nil : "\(countdown) remaining")
        }
    }

}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // When the settings window closes, hide the dock icon again, and let
        // the window go: its views disappear with it, which turns a camera
        // preview off, and the next opening starts fresh.
        if notification.object as? NSWindow === settingsWindow {
            NSApp.setActivationPolicy(.accessory)
            settingsWindow = nil
        }
    }
}
