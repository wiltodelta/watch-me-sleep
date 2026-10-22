# README screenshots

Run `./capture-screenshots.sh` from an unlocked macOS session. It builds and
signs `Watch Me While I Fall Asleep Dev.app`, then captures the idle panel,
running timer and Settings in light and dark appearances. Use `light` or `dark`
as an argument to regenerate one appearance. The terminal needs Accessibility and Screen
Recording access. Leave the Mac alone while the script opens windows.

The script refuses to run if a development copy is already open. The installed
release can remain open: it has a separate bundle identifier. The screenshot
session pins bedtime to 9 PM through 8 AM, a two-hour manual timer, English
labels and camera use off. It suppresses the first-run sound-choice prompt.
`-Screenshot.appearance light|dark` sets the development app's appearance
explicitly for capture; the release build ignores it. These are emulated
app appearances, not changes to the system theme.

`scripts/screenshot-helper.swift` checks that the session is unlocked before
input, verifies launch arguments against the kernel's argv, and captures the
actual windows with ScreenCaptureKit. Only the target window and an opaque
backdrop enter the composite, so other apps cannot leak into the image.
Captures are sRGB PNGs at the display's backing scale, with a 20-point margin.
The camera stays off; no personal camera footage needs to be blurred.

On exit, including failure, the script terminates its own app and backdrop
processes, disarms the timer, restores the development defaults and removes
its temporary files. A theme's three output files are replaced only after all
three states were captured successfully.

| State | Light | Dark |
|---|---|---|
| Choose a timer or start a nap | `screenshots/manual-timer.png` | `screenshots/manual-timer-dark.png` |
| Running timer | `screenshots/active-manual-timer.png` | `screenshots/active-manual-timer-dark.png` |
| Settings | `screenshots/settings.png` | `screenshots/settings-dark.png` |

The README uses `<picture>` sources to select the matching appearance. Keep
both sets and the capture recipe together when updating the interface. Inspect
every image before using it: file names alone do not verify the visible state.
