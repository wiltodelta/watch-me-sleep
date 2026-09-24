# UI architecture

Relocated from the repo root `CLAUDE.md`. Read before editing `AppDelegate`, `MenuBarPanel.swift`, or `SettingsView`.

## Settings window

This is a menu-bar `.accessory` app. The SwiftUI `Settings` scene does NOT open reliably from it. `SettingsView` is hosted in a custom `NSWindow` by `AppDelegate`, opened via the `OpenSettings` notification (`openAppSettings()`), toggling `.regular`/`.accessory` activation policy around it.

## Menu-bar dropdown panel

The main dropdown is a custom arrowless borderless `NSPanel` (`MenuBarPanel.swift`), not an `NSPopover` (whose triangular arrow looks dated). Three things there are load-bearing and easy to regress:

- Window height is driven by `host.sizeThatFits(in:)`, NOT `NSHostingController.preferredContentSize`. The latter undercounts tall content and clips the footer in camera mode.
- The backing material stays at the AppKit level, outside the measured SwiftUI tree. On macOS 26+ it is an `NSGlassEffectView` (Liquid Glass) whose `contentView` is the hosting view; before that (macOS 14 and 15), an `NSVisualEffectView` with the `.popover` material sits as a sibling *behind* the hosting view. Embedding an effect inside the self-sizing SwiftUI content recurses through Auto Layout and crashes (stack overflow).
- Content width is pinned via `.frame(width:)`. Without it the greedy `maxWidth: .infinity` content collapses and the panel comes out too narrow. Corner rounding lives on a layer-backed `NSView` with `masksToBounds` that holds the backing, on every release. Rounding the visual-effect view itself leaves square opaque corners, and an `NSGlassEffectView` set as the window's root view draws a square rim along its bounds around its own rounded glass; the clip cuts both away.

Animating the height change is an open HIG gap: with `sizingOptions` left on, Auto Layout snaps the window before any `setFrame(animate:)`; turning it off and driving the height from `onGeometryChange` crashed in the window's layout display cycle (2026-09-23).

`configure()` sets `isFloatingPanel` before `level`: the setter resets the level to `.floating`, which silently dropped the panel from `.statusBar` (25) to 3, under any other floating window.

`capture-screenshots.sh` regenerates the README screenshots. A single-window capture renders Liquid Glass without what sits behind it, as flat gray, so the script puts an opaque backdrop a shade darker than the panel under each window and captures the screen region with a 20 pt margin, shadow included. The panel hangs 1 pt below the menu bar, so the top margin is filled in the backdrop color instead of captured. The backdrop must be opaque: `underPageBackgroundColor` is translucent and let text from the windows behind it into the images. Each region is checked before and after the capture and the image kept only if nothing but the app and the backdrop is in it: a window raised meanwhile would put private content into a public image. It drives the app only through Accessibility identifiers (`startTimer`, `stopTimer`, `openSettings`, `cameraPreview`), never synthetic clicks.

The panel follows the system light/dark appearance. On macOS 26+ the system status-bar menus take the menu bar's appearance instead, so they can be dark while the system is light; do not copy that onto the panel (decided 2026-09-23).

## SDK version stamp

The Tahoe look (Liquid Glass controls, tinted buttons, current form styling) applies only when the binary's `LC_BUILD_VERSION` records a macOS 26+ SDK. SwiftPM's default Swift Build system in Xcode 27 records the deployment target there instead, and macOS then runs the app in its pre-Tahoe compatibility mode, including an empty SwiftUI `Settings` window at launch. `Package.swift` passes `-Xlinker -platform_version macos <deploymentTarget> 26.0` in the executable target's `linkerSettings`, so every build path (`create-app.sh`, `maintain.sh`, CI) gets it. The manifest cannot ask `xcrun` for the installed SDK, so 26.0 is a floor, not the real SDK version; `create-app.sh` fails the build if `vtool -show-build` reports an SDK below 26.
