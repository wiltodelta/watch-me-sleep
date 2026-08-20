# Watch Me While I Fall Asleep

You are a **principal Swift/macOS engineer** maintaining a menu bar app that automatically puts your Mac to sleep with manual timer controls and intelligent camera-based eye-closure detection.

## How to run

- `./run.sh` — build and run for development
- `./create-app.sh` — assemble the standalone .app bundle and re-sign it. The stable signing identity here is "Watch Me While I Fall Asleep Dev"; the TCC grant it preserves is Camera.

## Test and lint

- `bash maintain.sh` — the canonical Swift gate.
- `swiftlint` must be installed for the lint step (`brew install swiftlint`); `maintain.sh` skips linting if it is missing.
- Stale `.build` after the repo moves paths fails with a `SwiftShims ... module cache path` error — fix with `rm -rf .build`.
- The seams the global testing rules require are `TimerManager.sleepHandler` (unoverridden, it runs the real `pmset sleepnow`), the `now: () -> Date` clock plus `tick()` (worked example: `TimerManagerTests.testVeryShortTimer`), and `UserDefaults(suiteName:)`. Reset `now` in `setUp`/`tearDown`, because the manager is a shared singleton and the override outlives the test that set it.

## UI

- This is a menu-bar `.accessory` app. The SwiftUI `Settings` scene does NOT open reliably from it — `SettingsView` is hosted in a custom `NSWindow` by `AppDelegate`, opened via the `OpenSettings` notification (`openAppSettings()`), toggling `.regular`/`.accessory` activation policy around it.
- The main dropdown is a custom arrowless borderless `NSPanel` (`MenuBarPanel.swift`), not an `NSPopover` (whose triangular arrow looks dated). Three things there are load-bearing and easy to regress:
  - Window height is driven by `host.sizeThatFits(in:)`, NOT `NSHostingController.preferredContentSize` — the latter undercounts tall content and clips the footer in camera mode.
  - The `NSVisualEffectView` vibrancy + tint are AppKit siblings *behind* the SwiftUI hosting view, kept out of the measured SwiftUI tree; embedding the effect inside the self-sizing SwiftUI content recurses through Auto Layout and crashes (stack overflow).
  - Content width is pinned via `.frame(width:)`; without it the greedy `maxWidth: .infinity` content collapses and the panel comes out too narrow. Corner rounding lives on a layer-backed `NSView` with `masksToBounds` (rounding the visual-effect view itself leaves square opaque corners).
