# Sleep Timer

You are a **principal Swift/macOS engineer** maintaining a menu bar app that automatically puts your Mac to sleep with manual timer controls and intelligent camera-based eye-closure detection.

## How to run

- `./run.sh` — build and run for development
- `./create-app.sh` — create standalone .app bundle (assembles the bundle, then ad-hoc re-signs it; `swift build` signs only the executable, so adding Info.plist/Resources afterwards invalidates the signature and the bundle must be re-signed or Gatekeeper rejects Finder launches)

## Test and lint

- `bash maintain.sh` — swiftlint lint --fix, swift test, swift build -c release
- `swiftlint` must be installed for the lint step (`brew install swiftlint`); `maintain.sh` skips linting if it is missing.
- `swift test` requires full Xcode (XCTest is absent from Command Line Tools); `swift build`/`./create-app.sh` work on CLT alone.
- Stale `.build` after the repo moves paths fails with a `SwiftShims ... module cache path` error — fix with `rm -rf .build`.
- Tests must override the manager seams (e.g. `TimerManager.sleepHandler`) — otherwise `swift test` runs the real `pmset sleepnow` and sleeps the Mac. Managers inject closures + `UserDefaults(suiteName:)` for testability.

## UI

- This is a menu-bar `.accessory` app. The SwiftUI `Settings` scene does NOT open reliably from it — `SettingsView` is hosted in a custom `NSWindow` by `AppDelegate`, opened via the `OpenSettings` notification (`openAppSettings()`), toggling `.regular`/`.accessory` activation policy around it.
- The main dropdown is a custom arrowless borderless `NSPanel` (`MenuBarPanel.swift`), not an `NSPopover` (whose triangular arrow looks dated). Three things there are load-bearing and easy to regress:
  - Window height is driven by `host.sizeThatFits(in:)`, NOT `NSHostingController.preferredContentSize` — the latter undercounts tall content and clips the footer in camera mode.
  - The `NSVisualEffectView` vibrancy + tint are AppKit siblings *behind* the SwiftUI hosting view, kept out of the measured SwiftUI tree; embedding the effect inside the self-sizing SwiftUI content recurses through Auto Layout and crashes (stack overflow).
  - Content width is pinned via `.frame(width:)`; without it the greedy `maxWidth: .infinity` content collapses and the panel comes out too narrow. Corner rounding lives on a layer-backed `NSView` with `masksToBounds` (rounding the visual-effect view itself leaves square opaque corners).
