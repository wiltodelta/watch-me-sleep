# UI architecture

Relocated from the repo root `CLAUDE.md`. Read before editing `AppDelegate`, `MenuBarPanel.swift`, or `SettingsView`.

## Settings window

This is a menu-bar `.accessory` app. The SwiftUI `Settings` scene does NOT open reliably from it. `SettingsView` is hosted in a custom `NSWindow` by `AppDelegate`, opened via the `OpenSettings` notification (`openAppSettings()`), toggling `.regular`/`.accessory` activation policy around it. `windowWillClose` drops the window, so its SwiftUI views disappear on close: the camera preview (`CameraPreviewRow`) stops the camera in its `onDisappear`, which never fires on a window kept alive between openings.

## Menu-bar dropdown panel

The main dropdown is a custom arrowless borderless `NSPanel` (`MenuBarPanel.swift`), not an `NSPopover` (whose triangular arrow looks dated). Three things there are load-bearing and easy to regress:

- Window height is driven by `host.sizeThatFits(in:)`, NOT `NSHostingController.preferredContentSize`. The latter undercounts tall content and clipped the footer of the former, taller camera mode.
- The backing material stays at the AppKit level, outside the measured SwiftUI tree. On macOS 26+ it is an `NSGlassEffectView` (Liquid Glass) whose `contentView` is the hosting view; before that (macOS 15), an `NSVisualEffectView` with the `.popover` material sits as a sibling *behind* the hosting view. Embedding an effect inside the self-sizing SwiftUI content recurses through Auto Layout and crashes (stack overflow).
- Content width is pinned via `.frame(width:)`. Without it the greedy `maxWidth: .infinity` content collapses and the panel comes out too narrow. Corner rounding lives on a layer-backed `NSView` with `masksToBounds` that holds the backing, on every release. Rounding the visual-effect view itself leaves square opaque corners, and an `NSGlassEffectView` set as the window's root view draws a square rim along its bounds around its own rounded glass; the clip cuts both away.

Animating the height change is an open HIG gap: with `sizingOptions` left on, Auto Layout snaps the window before any `setFrame(animate:)`; turning it off and driving the height from `onGeometryChange` crashed in the window's layout display cycle (2026-09-23).

`NSPanel.configureAsStatusPanel()`, shared by the dropdown and the sleep warning, sets `isFloatingPanel` before `level`: the setter resets the level to `.floating`, which silently dropped the panel from `.statusBar` (25) to 3, under any other floating window.

The hosted content has a nearly opaque `windowBackgroundColor` backing. Glass
tint alone does not bound text contrast in the never-key sleep warning. Keep
the material outside the measured SwiftUI tree, and verify both panels over
black, gray and white backdrops after changing either backing or text colors.
The dropdown closes on key-focus loss or activation of another app, as well as
outside clicks and Escape. Activation of its own app does not dismiss it.

`capture-screenshots.sh` regenerates the README screenshots. A single-window capture renders Liquid Glass without what sits behind it, as flat gray, so the script puts an opaque backdrop a shade darker than the panel under each window and captures the screen region with a 20 pt margin, shadow included. The panel hangs 1 pt below the menu bar, so the top margin is filled in the backdrop color instead of captured. The backdrop must be opaque: `underPageBackgroundColor` is translucent and let text from the windows behind it into the images. Each region is checked before and after the capture and the image kept only if nothing but the app and the backdrop is in it: a window raised meanwhile would put private content into a public image. It drives the app only through Accessibility identifiers (`startTimer`, `stopTimer`, `openSettings`, `cameraPreview`), never synthetic clicks.

The panel follows the system light/dark appearance. On macOS 26+ the system status-bar menus take the menu bar's appearance instead, so they can be dark while the system is light; do not copy that onto the panel (decided 2026-09-23).

## Right-click menu

`AppDelegate.showQuickMenu` builds an `NSMenu` and shows it as the status item's own menu (`statusItem.menu`, `performClick`, then cleared, so a left click still opens the panel), which lets macOS place it under the icon. A hand-placed `popUp(positioning:at:in:)` opened above the menu bar: clipped, with a scroll arrow over the status line. Its `appearance` is set to `NSApp.effectiveAppearance`, so it follows the system like the panel rather than the menu bar (fixed 2026-10-10); that is the system's only while the app sets no `NSApp.appearance` of its own. Verify it with a region capture, not a window capture, which draws the glass flat gray. The menu answers only to a real right click, so the status button also carries an accessibility custom action, Show Menu, that VoiceOver offers in its Actions rotor (`addShowMenuAction`). macOS 27 hides menu item images unless an item asks for them, so `showQuickMenu` sets `preferredImageVisibility` on every item (`showsImage`), the system's Quit icon included.

## Sleep warning panel

`SleepWarningController` (`SleepWarningPanel.swift`) shows the timer's final minute in the top-right corner. It reuses `PanelHostController`, so it carries the same backing and rounding as the dropdown. It is a panel, not a notification, because the Sleep focus and full-screen video hide notifications. It never becomes key (`becomesKeyOnlyIfNeeded`), so a video player keeps its keyboard while the buttons still take a first click. Its buttons draw with `controlActiveState = .key`, so Sleep Now keeps its accent instead of the inactive gray a non-key window gets, as translate-like-me's popup does (changed 2026-10-11). A single-window capture of it renders the glass flat gray, as above.

The warning uses its fixed content width when anchoring the first frame;
the window's measured width can still be zero before its first layout. Once
input guarantees postponement, both the warning and timer panel say that the
Mac stays awake instead of promising sleep at the old deadline.

## SDK version stamp

The Tahoe look (Liquid Glass controls, tinted buttons, current form styling) applies only when the binary's `LC_BUILD_VERSION` records a macOS 26+ SDK. SwiftPM's default Swift Build system in Xcode 27 records the deployment target there instead, and macOS then runs the app in its pre-Tahoe compatibility mode, including an empty SwiftUI `Settings` window at launch. `Package.swift` passes `-Xlinker -platform_version macos <deploymentTarget> 26.0` in the executable target's `linkerSettings`, so every build path (`create-app.sh`, `maintain.sh`, CI) gets it. The manifest cannot ask `xcrun` for the installed SDK, so 26.0 is a floor, not the real SDK version; `create-app.sh` fails the build if `vtool -show-build` reports an SDK below 26.
