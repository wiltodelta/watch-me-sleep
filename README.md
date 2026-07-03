# Watch Me While I Fall Asleep

[![Build Watch Me While I Fall Asleep App](https://github.com/wiltodelta/watch-me-sleep/actions/workflows/build.yml/badge.svg)](https://github.com/wiltodelta/watch-me-sleep/actions/workflows/build.yml)

A macOS menu bar app that puts your Mac to sleep on a timer. Set a countdown by
hand, or switch on Camera mode and it starts the timer for you when it sees your
eyes stay closed. Menu bar only, no Dock icon.

<p align="center">
  <img src="screenshots/manual-timer.png" alt="Watch Me While I Fall Asleep - Manual Mode" width="280">
  <img src="screenshots/active-manual-timer.png" alt="Watch Me While I Fall Asleep - Active Timer" width="280">
  <img src="screenshots/camera-mode.png" alt="Watch Me While I Fall Asleep - Camera Mode" width="280">
  <img src="screenshots/settings.png" alt="Watch Me While I Fall Asleep - Settings" width="280">
</p>

## Features

Timer:

- Remaining time shown in the menu bar next to the icon.
- Any duration from 15 minutes to 12 hours, plus one-click presets (15m, 30m,
  1h, 1.5h, 2h, 3h, 4h, 6h).
- Extend a running timer by +5, +15, +30, or +60 minutes.
- Right-click the icon for a quick menu: start a common timer, stop the current
  one, or open Settings.
- Circular progress ring, and a moon icon that fills in while a timer runs.

Camera mode:

- Starts a 30-minute timer on its own when your eyes stay closed for about 15
  seconds, and cancels it if you open them.
- Live preview with a border that turns green once your face is detected.
- After 1.5 hours it asks if you are still awake, and sleeps the Mac if there is
  no response within 30 seconds.
- All processing is on-device with Apple's Vision framework. No video is stored
  or sent anywhere.

Auto-start and system:

- Optionally arm a timer on its own once the Mac sits idle for a set number of
  minutes inside a nightly window, so you never forget to start one.
- Launch at login.
- Adaptive app icon (light/dark), restrained system-style UI.

## Requirements

- macOS 13 (Ventura) or later.
- Apple Silicon or Intel Mac.
- For building from source: Xcode 15 or later.

## Install

### From a release

1. Download the latest `WatchMeSleep-vX.Y.Z-macOS.zip` from the
   [Releases](https://github.com/wiltodelta/watch-me-sleep/releases) page.
2. Unzip it and move **Watch Me While I Fall Asleep.app** to `/Applications`.
3. The build is self-signed for personal use (not notarized), so macOS warns on
   first launch. Either right-click the app and choose **Open** to confirm once,
   or clear the quarantine flag:
   ```bash
   xattr -cr "/Applications/Watch Me While I Fall Asleep.app"
   ```
4. Launch it. A moon icon appears in the menu bar (there is no Dock icon).

The app checks GitHub Releases on launch and tells you when a newer version is
out, so updating later is just steps 1 to 3 again.

### From source

```bash
git clone https://github.com/wiltodelta/watch-me-sleep.git
cd watch-me-sleep
./create-app.sh
mv "Watch Me While I Fall Asleep.app" /Applications/
```

## First run

- Manual timer mode needs no permissions at all.
- Camera mode asks for **Camera** access the first time you open it (System
  Settings > Privacy & Security > Camera). It is optional; the timer works
  without it, and all camera processing stays on-device.

## Usage

### Manual timer

1. Click the moon icon and select **Timer**.
2. Set a duration with the slider or a preset, then click **Start Timer**.
3. The icon fills in while the timer runs. Click it again to see the remaining
   time, add time, or stop.

Right-click the icon for a quick menu that starts a common timer
(15m/30m/1h/1.5h/2h), stops the current one, or opens Settings.

### Camera mode

1. Click the moon icon, select **Camera**, and grant camera access.
2. The preview border turns green once your face is detected.
3. When your eyes stay closed for about 15 seconds, a 30-minute timer starts.
   Open your eyes for a few seconds to cancel it.
4. Every 1.5 hours it asks if you are still awake; no response within 30 seconds
   sleeps the Mac.

### Auto-start when idle

Enable it in Settings, then pick the nightly window (start and end hour), how
many idle minutes should pass, and the timer length. When the Mac sits idle past
that threshold inside the window, a timer arms on its own. It stays out of the
way while a timer is already running or Camera mode is active.

## Settings

Open Settings from the gear in the panel, or from the right-click menu.

- **Auto-start when idle**: the nightly window, idle threshold, and timer length.
- **Startup**: launch at login.
- **Updates**: current version and a "Check for updates…" button.

## Updates

The app checks GitHub Releases a few seconds after launch and offers to open the
download page when a newer version is tagged. You can also check on demand from
Settings > Updates. It is a check-and-notify updater, not a silent installer: you
download the new build and replace the app yourself.

## Troubleshooting

- **"Watch Me While I Fall Asleep is damaged and can't be opened":** Gatekeeper
  blocking a non-notarized app. Clear the quarantine flag with
  `xattr -cr "/Applications/Watch Me While I Fall Asleep.app"`, or right-click
  the app and choose **Open**.
- **The timer doesn't sleep the Mac:** something may be holding a power
  assertion (for example `caffeinate` or a media app). Check with
  `pmset -g assertions`.
- **Camera mode isn't working:** enable the app under System Settings > Privacy
  & Security > Camera, and make sure your face is visible and well-lit.
- **No icon in the menu bar:** confirm you are on macOS 13 or later, then quit
  and relaunch.

## Building and releasing

- `./run.sh` builds and runs for development.
- `./create-app.sh` assembles the signed `.app` bundle.
- `bash maintain.sh` runs SwiftLint, the tests, and a release build.

Releases are automated: the app version comes from the git tag, and pushing a
`vX.Y.Z` tag makes GitHub Actions build the app and publish a Release with the
zip attached.

```bash
git tag -a v1.8.0 -m "Watch Me While I Fall Asleep 1.8.0"
git push origin v1.8.0
```

Local builds report version `dev` and are not meant for distribution.

## License

MIT. See [LICENSE](LICENSE).
