# Sleep Timer

You are a **principal Swift/macOS engineer** maintaining a menu bar app that automatically puts your Mac to sleep with manual timer controls and intelligent camera-based eye-closure detection.

## How to run

- `./run.sh` — build and run for development
- `./create-app.sh` — create standalone .app bundle

## Test and lint

- `bash maintain.sh` — swiftlint lint --fix, swift test, swift build -c release
- `swift test` requires full Xcode (XCTest is absent from Command Line Tools); `swift build`/`./create-app.sh` work on CLT alone.
- Stale `.build` after the repo moves paths fails with a `SwiftShims ... module cache path` error — fix with `rm -rf .build`.
- Tests must override the manager seams (e.g. `TimerManager.sleepHandler`) — otherwise `swift test` runs the real `pmset sleepnow` and sleeps the Mac. Managers inject closures + `UserDefaults(suiteName:)` for testability.

## UI

- This is a menu-bar `.accessory` app. The SwiftUI `Settings` scene does NOT open reliably from it — `SettingsView` is hosted in a custom `NSWindow` by `AppDelegate`, opened via the `OpenSettings` notification (`openAppSettings()`), toggling `.regular`/`.accessory` activation policy around it.
