# Watch Me While I Fall Asleep

You are a **principal Swift/macOS engineer** maintaining a menu bar app that automatically puts your Mac to sleep with manual timer controls and intelligent camera-based eye-closure detection.

## How to run

- `./run.sh` - build and run for development
- `./create-app.sh` - assemble the standalone .app bundle and re-sign it. The stable signing identity here is "Watch Me While I Fall Asleep Dev"; the TCC grant it preserves is Camera.

## Test and lint

- `bash maintain.sh` - the canonical Swift gate.
- `swiftlint` must be installed for the lint step (`brew install swiftlint`); `maintain.sh` skips linting if it is missing.
- Stale `.build` after the repo moves paths fails with a `SwiftShims ... module cache path` error - fix with `rm -rf .build`.
- The seams the global testing rules require are `TimerManager.sleepHandler` (unoverridden, it runs the real `pmset sleepnow`), the `now: () -> Date` clock plus `tick()` (worked example: `TimerManagerTests.testVeryShortTimer`), and `UserDefaults(suiteName:)`. Reset `now` in `setUp`/`tearDown`, because the manager is a shared singleton and the override outlives the test that set it.

## UI

Menu-bar `.accessory` app: `SettingsView` lives in a custom `NSWindow` opened by `AppDelegate`, and the dropdown is a custom borderless `NSPanel` (`MenuBarPanel.swift`), not an `NSPopover`. The three load-bearing panel rules (`sizeThatFits` height, `NSVisualEffectView` as an AppKit sibling, pinned `.frame(width:)` plus layer-backed corner rounding): `docs/ui-architecture.md`.
