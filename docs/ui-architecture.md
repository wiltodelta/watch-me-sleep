# UI architecture

Relocated from the repo root `CLAUDE.md`. Read before editing `AppDelegate`, `MenuBarPanel.swift`, or `SettingsView`.

## Settings window

This is a menu-bar `.accessory` app. The SwiftUI `Settings` scene does NOT open reliably from it. `SettingsView` is hosted in a custom `NSWindow` by `AppDelegate`, opened via the `OpenSettings` notification (`openAppSettings()`), toggling `.regular`/`.accessory` activation policy around it.

## Menu-bar dropdown panel

The main dropdown is a custom arrowless borderless `NSPanel` (`MenuBarPanel.swift`), not an `NSPopover` (whose triangular arrow looks dated). Three things there are load-bearing and easy to regress:

- Window height is driven by `host.sizeThatFits(in:)`, NOT `NSHostingController.preferredContentSize`. The latter undercounts tall content and clips the footer in camera mode.
- The `NSVisualEffectView` vibrancy and tint are AppKit siblings *behind* the SwiftUI hosting view, kept out of the measured SwiftUI tree. Embedding the effect inside the self-sizing SwiftUI content recurses through Auto Layout and crashes (stack overflow).
- Content width is pinned via `.frame(width:)`. Without it the greedy `maxWidth: .infinity` content collapses and the panel comes out too narrow. Corner rounding lives on a layer-backed `NSView` with `masksToBounds`; rounding the visual-effect view itself leaves square opaque corners.
