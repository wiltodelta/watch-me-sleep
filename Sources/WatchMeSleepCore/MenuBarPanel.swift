import AppKit
import SwiftUI

/// Borderless panel that can take key focus so the hosted SwiftUI controls
/// (sliders, buttons, the Return/Escape default actions) work like they did
/// inside the old popover.
public final class MenuBarPanelWindow: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}

/// Hosts the SwiftUI content over an AppKit rounded backing: Liquid Glass on
/// macOS 26+, the standard popover material before it.
///
/// The backing stays at the AppKit level, deliberately kept out of the measured
/// SwiftUI tree — an `NSVisualEffectView` embedded inside a self-sizing
/// `NSHostingController` recurses through Auto Layout and overflows the stack.
/// The window height is driven from the inner content's exact `sizeThatFits`
/// (its `preferredContentSize` undercounts tall content and clipped the
/// footer), so the panel resizes to fit as the content changes between timer
/// and camera modes.
private final class PanelHostController: NSViewController {
    private let host: NSHostingController<AnyView>
    private let fixedWidth: CGFloat
    private let cornerRadius: CGFloat = 12

    init<Content: View>(rootView: Content, width: CGFloat) {
        // Pin the width so only the height is dynamic; without a fixed width the
        // greedy `maxWidth: .infinity` content collapses to its minimum and the
        // panel comes out too narrow.
        fixedWidth = width
        host = NSHostingController(rootView: AnyView(rootView.frame(width: width)))
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.cornerRadius = cornerRadius
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        view = clip
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(host)
        let layers: [NSView]
        if #available(macOS 26.0, *) {
            // Liquid Glass, as the system menus draw it. Its content view is
            // AppKit-level, so the hosting view stays outside the measured SwiftUI
            // tree. As the window's root view the glass also drew a square rim
            // along its bounds; inside the rounded clip that rim is cut away.
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = host.view
            layers = [glass]
        } else {
            // Pre-Tahoe: the material named for this surface, not one picked for
            // its color (HIG materials), behind the hosting view.
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            layers = [effect, host.view]
        }
        for sub in layers {
            sub.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(sub)
            NSLayoutConstraint.activate([
                sub.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                sub.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                sub.topAnchor.constraint(equalTo: view.topAnchor),
                sub.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
        resizeToFitContent()
    }

    /// Drive the window height from the SwiftUI content's exact fitting size.
    /// `NSHostingController.preferredContentSize` undercounts tall content here
    /// (it clipped the footer in camera mode), so measure explicitly instead.
    override func viewDidLayout() {
        super.viewDidLayout()
        resizeToFitContent()
    }

    private func resizeToFitContent() {
        let target = host.sizeThatFits(
            in: NSSize(width: fixedWidth, height: .greatestFiniteMagnitude)
        )
        // Guard against a feedback loop: only push a genuinely new size.
        if abs(target.height - preferredContentSize.height) > 0.5
            || abs(target.width - preferredContentSize.width) > 0.5 {
            preferredContentSize = target
        }
    }
}

/// Arrowless dropdown anchored under a status-bar item.
///
/// Reproduces `NSPopover.behavior = .transient` (open on click, close on any
/// click outside) without the dated triangular arrow that `NSPopover` always
/// draws. The content is a SwiftUI view hosted in a rounded, material-backed
/// borderless window.
public final class MenuBarPanelController {
    private let panel: MenuBarPanelWindow
    private weak var anchorButton: NSStatusBarButton?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var resizeObserver: NSObjectProtocol?
    /// Screen-space top-left the panel grows down from, so it stays pinned under
    /// the menu bar when the content height changes between modes.
    private var anchorTopLeft: NSPoint?

    /// Gap between the menu bar and the top of the panel, in points.
    private let verticalGap: CGFloat = 6
    /// Minimum inset kept from the screen edges when clamping horizontally.
    private let screenEdgeInset: CGFloat = 8

    public var isShown: Bool { panel.isVisible }

    public init<Content: View>(rootView: Content, size: NSSize) {
        panel = MenuBarPanelWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure(rootView: rootView, size: size)
    }

    private func configure<Content: View>(rootView: Content, size: NSSize) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // `isFloatingPanel` resets the level to `.floating`, so it goes first.
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // A hosting controller (not a bare hosting view) sizes the window to fit
        // the SwiftUI content and keeps it in sync as the content changes between
        // timer and camera modes — the same self-resizing the old popover had.
        // `startObservingResize()` re-pins the top edge under the menu bar.
        panel.setContentSize(size)
        panel.contentViewController = PanelHostController(rootView: rootView, width: size.width)
    }

    public func show(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        anchorButton = button

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let size = panel.frame.size

        var origin = NSPoint(
            x: screenRect.midX - size.width / 2,
            y: screenRect.minY - size.height - verticalGap
        )

        // Keep the panel on screen when the icon sits near a screen edge.
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + screenEdgeInset),
                           visible.maxX - size.width - screenEdgeInset)
        }

        panel.setFrameOrigin(origin)
        anchorTopLeft = NSPoint(x: origin.x, y: origin.y + size.height)
        startObservingResize()

        // A non-activating panel takes key focus (so the SwiftUI sliders, buttons
        // and Return/Escape default actions work) without bringing the whole
        // accessory app to the foreground.
        panel.makeKeyAndOrderFront(nil)
        startMonitoring()
    }

    public func close() {
        stopMonitoring()
        stopObservingResize()
        anchorButton = nil
        panel.orderOut(nil)
    }

    /// Keep the panel's top edge fixed under the menu bar as its height changes.
    private func startObservingResize() {
        stopObservingResize()
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self, let topLeft = self.anchorTopLeft else { return }
            self.panel.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - self.panel.frame.height))
        }
    }

    private func stopObservingResize() {
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            resizeObserver = nil
        }
    }

    // MARK: - Transient dismissal

    private func startMonitoring() {
        stopMonitoring()

        // Clicks in other apps (or on the desktop) close the panel.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.close()
        }

        // Clicks in our own app close the panel unless they land inside it or on
        // the status item itself (the button action handles its own toggle).
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.window != self.panel, event.window != self.anchorButton?.window {
                self.close()
            }
            return event
        }
    }

    private func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
