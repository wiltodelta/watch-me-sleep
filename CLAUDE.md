# Watch Me Sleep

You are a **principal Swift/macOS engineer** maintaining a menu bar app that puts the Mac to sleep once its user falls asleep: one automatic night watch (`SleepSupervisor`) plus a manual timer (`TimerManager`) that every sleep goes through. SwiftPM; the one dependency is Sparkle (in-place updates, `Updater`; packaging and keys in `docs/build-and-release.md`).

Shared rules for our macOS apps: `~/Documents/GitHub/claude-config/docs/macos-apps.md`; this file states only what differs.

## How to run

- `./create-app.sh` builds and signs the bundle; its icon layers come from `scripts/draw-icon.py` (`icon.json` edited in Icon Composer). The signature carries the camera entitlement, without which the hardened runtime blocks the camera; the TCC grant the stable signature preserves is Camera. A local release build is `RELEASE=1 ./create-app.sh && ./notarize.sh` (`docs/build-and-release.md`).
- `./capture-screenshots.sh` rebuilds and regenerates light/dark `screenshots/` with the camera off; it needs Accessibility and Screen Recording for the terminal and an unlocked, idle Mac, and restores the development defaults on exit. Recipe: `docs/screenshots.md`.

## Test and lint

- `bash maintain.sh` is the gate. When SwiftLint's file-length or complexity limit fails it, split by type or extract a helper.
- The dev build (`com.wiltodelta.watchmesleep.dev`) keeps its journal in `~/Library/Logs/WatchMeSleep Dev` and has its own camera grant. Both night watches can act at once: quit one before testing sleep.
- The bare `.build/debug/WatchMeSleep` shows Sparkle's modal "Unable to Check For Updates", whose modal loop stalls the timer's ticks; it and `xctest` hold no Camera grant, so the camera look answers `unavailable`. Exercise the camera path from the signed bundle.
- To debug a real night, read the opt-in diagnostics journal (`Journal`, JSON Lines in `~/Library/Logs/WatchMeSleep/`, on with the `Diagnostics.journal` default; events and `jq` recipes: `docs/diagnostics.md`), and record a new decision there when adding one. Watch live with `/usr/bin/log stream --level info --predicate 'subsystem == "com.wiltodelta.watchmesleep"'`; `.info` is not persisted.
- While the Mac is in use, render a changed view from a throwaway `@testable` test with `ImageRenderer` in both color schemes; it shows layout and text, not the Liquid Glass backing, and draws AppKit-backed controls (a `.switch` toggle) as a yellow placeholder.
- Seams: `TimerManager.sleepHandler` (unoverridden, it runs the real `pmset sleepnow`), the `now: () -> Date` clock plus `tick()` (example: `TimerManagerTests.testVeryShortTimer`), `TimerManager.idleSecondsProvider`, `.volume` and `.workHolders`, `SleepSupervisor`'s `idleSecondsProvider`, `wakeHolders`, `cameraAuthorized`, `checkPresence` (unoverridden, it turns the real camera on) and `timer`, and `UserDefaults(suiteName:)`. Reset `now` in `setUp`/`tearDown`: the manager is a shared singleton and the override outlives the test that set it.
- Tests of `putComputerToSleep` itself must replace `TimerManager.powerCommand` and `showPowerFailure`, since `sleepHandler` bypasses this path; no test runs real `pmset`.

## Night watch

- `NightWatchPolicy` (pure) decides from input idle time, `WakeHolders` and the camera; `SleepSupervisor` runs it on a poll in bedtime and owns one action per idle stretch. Its thresholds are constants, not settings, on purpose. The camera answers only "something plays, nobody touches the Mac"; a quiet Mac never turns it on. Bedtime is minutes after midnight (`bedtimeStart`/`bedtimeEnd`). `watchNow()` runs it outside bedtime for a nap (`isWatchingNow`, not persisted) until `willSleep`, `screensDidSleep` or the start of bedtime.
- Absence is evidence only after a face in the same stretch (`Stretch.faceSeen`); before that, and on mostly black frames (`PresenceCheck.darkLuma`, unmeasured against real nights), it counts as unclear. `WakeHolders.soundOnly` (media without any display hold) plus `keepsSoundPlaying` makes the night watch stand aside; the choice is asked once at launch (`soundChoiceAsked`).
- A timer the night watch starts (`TimerManager.stopsOnInput`) stops at any input since its start, and on open eyes in its final minute, after which the stretch resumes looking; a timer set by hand is an intent and postpones by `postponeMinutes` instead. Only camera-armed timers look in the final minute; a quiet Mac's and the three-hour "still watching?" never do. A test that advances `clock` past a night watch timer's start must advance `idle` with it, or the timer reads the stale idle as input.
- `WakeHolders` sorts power assertions by measured properties, never app names: a display-only assertion or a process in CoreAudio's playing list is media; a process's own system assertion is work, which turns the final action into `pmset displaysleepnow`. Apps (`.app/`) are never daemons, Apple's under `/System/Applications` included. Re-measure with `IOPMCopyAssertionsByProcess` before changing a rule.
- `CameraWatcher` runs the session while any user (the look, the Settings preview) holds it, and never prompts for access. Canceling a look releases only `.look`; queued answers are generation-checked before release or delivery. `CameraWatcherTests` injects authorization and session control, and `SleepSupervisorTestCase` replaces both `checkPresence` and `cancelPresence`. Verify the camera went off from the log (`category == "camera"`: "Camera on for …", "Camera off"); drive the Settings preview through its `toggleCameraPreview` Accessibility identifier.
- A timeout without the full `PresenceCheck.lookSeconds` of frame observation is `unavailable`, even with frames. `SystemVolumeFader` follows output changes with separate original volumes; `VolumeFaderTests` injects every device operation. `LaunchAtLoginManagerTests` uses a fake `LoginItemService` and an isolated notification center, never real login-item registration.
- `PresenceCheck` measures seconds from frame timestamps, never frame counts: the camera's real frame rate differs from the one asked and drops in the dark. `EyeReading` combines Vision's EAR and Core Image's blink classifier: both must agree when both return a result, and a lone result decides otherwise. Change either rule only against `EyeDetectionBenchmark` (skipped without `WMS_FACE_DIR`; method and caveats in `docs/eye-detection.md`). To watch a look live, log from inside `WatchMeSleepCore` (the executable target cannot see internal API) and launch the signed bundle with `open --env`, so TCC asks about the app, not the terminal.

## UI

`#available(macOS 26.0, *)` branches are the Liquid Glass path; the else branches serve macOS 15. `SettingsView` lives in a custom `NSWindow` opened by `AppDelegate`; the three load-bearing `MenuBarPanel` rules (`sizeThatFits` height, material backing kept at the AppKit level, pinned `.frame(width:)` plus layer-backed corner rounding) are in `docs/ui-architecture.md`.

## Personal website

The personal website (`wiltodelta/wiltodelta-app`, page `/projects/watch-me-sleep/`) imports `screenshots/manual-timer.png`, `screenshots/manual-timer-dark.png` and the README section "How it works" from each stable release at its tag. Regenerate those screenshots before tagging a release whose UI changed, never rename or remove them or the section without updating that repository in the same change, and after publishing follow its `docs/product-updates.md`, "What product repositories owe the site".
