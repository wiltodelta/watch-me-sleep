# Watch Me While I Fall Asleep

You are a **principal Swift/macOS engineer** maintaining a menu bar app that automatically puts your Mac to sleep with manual timer controls and intelligent camera-based eye-closure detection.

## How to run

- `./run.sh` - build and run for development
- `./create-app.sh` - assemble the standalone .app bundle and re-sign it with the team's Developer ID (hardened runtime plus the camera entitlement; the hardened runtime blocks the camera without it). The TCC grant the stable signature preserves is Camera. Releases: `RELEASE=1 ./create-app.sh && ./notarize.sh` locally, or a `vX.Y.Z` tag, which CI signs and notarizes from repository secrets (README, "Building and releasing").
- `./capture-screenshots.sh` - rebuild and regenerate `screenshots/` through Accessibility identifiers; needs Accessibility and Screen Recording for the terminal, turns the camera on briefly and blurs it. Quit an installed copy first, or the single-instance check quits the fresh build.
- `Package.swift` stamps a macOS 26 SDK version into the executable through `linkerSettings`; without it Xcode 27's Swift Build records the deployment target there and macOS runs the pre-Tahoe compatibility look. Check a binary with `vtool -show-build`: `docs/ui-architecture.md`.

## Test and lint

- `bash maintain.sh` - the canonical Swift gate.
- `swiftlint` must be installed for the lint step (`brew install swiftlint`); `maintain.sh` skips linting if it is missing.
- The app quits on launch if another instance with its bundle id runs; test a second copy beside the installed one under a different `CFBundleIdentifier` (and remove its TCC rows afterwards).
- "Launch at login" registers whichever bundle is running, so toggling it in a dev build points the login item at the repo copy; check with `sfltool dumpbtm`.
- Stale `.build` after the repo moves paths fails with a `SwiftShims ... module cache path` error - fix with `rm -rf .build`.
- The seams the global testing rules require are `TimerManager.sleepHandler` (unoverridden, it runs the real `pmset sleepnow`), the `now: () -> Date` clock plus `tick()` (worked example: `TimerManagerTests.testVeryShortTimer`), and `UserDefaults(suiteName:)`. Reset `now` in `setUp`/`tearDown`, because the manager is a shared singleton and the override outlives the test that set it.

## UI

Supports the three latest macOS releases (currently 14+) on Apple silicon only, and follows Apple's HIG; `#available(macOS 26.0, *)` branches are the Liquid Glass path, the else branches serve 14 and 15.

Menu-bar `.accessory` app: `SettingsView` lives in a custom `NSWindow` opened by `AppDelegate`, and the dropdown is a custom borderless `NSPanel` (`MenuBarPanel.swift`), not an `NSPopover`. The three load-bearing panel rules (`sizeThatFits` height, material backing kept at the AppKit level, pinned `.frame(width:)` plus layer-backed corner rounding): `docs/ui-architecture.md`.
