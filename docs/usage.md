# Using Watch Me While I Fall Asleep

The app lives in the menu bar. Click the moon for the main panel, or
right-click it for timer presets, Settings and update checks.

## First run

- The timer and camera-free night watch need no permissions.
- The camera is optional. Turn on **Use the camera** in Settings and the app
  asks for **Camera** access then (System Settings > Privacy & Security >
  Camera); **Camera preview > Show** shows what it sees.

## Night watch

It is on from 9 PM to 8 AM by default. Set bedtime in Settings to any times,
to the minute (10:30 PM to 6:45 AM, or a daytime sleep after a night shift).
During those hours, once you stop using the Mac:

- Nothing playing, nobody at the keyboard: after 20 minutes a 15-minute timer
  starts. The camera stays off: with nothing playing, nobody is watching.
- Something playing: after 5 minutes the camera looks. Closed eyes start a
  5-minute timer, whose final minute looks once more; so does nobody there,
  once the camera has seen you in this stretch. Open eyes mean you are
  watching, and it looks again in 5 minutes. If the picture stays unclear
  (too dark, a face turned away, nobody ever seen), or there is no camera, it
  asks after two hours whether you are still watching.
- Only sound playing, and you chose to keep it: nothing happens; the display
  turns off by itself and the sound plays on.
- Something starts playing during the quiet Mac's timer: the timer stops and
  the camera decides instead.
- After three hours without input it asks anyway: some people sleep with their
  eyes partly open.
- It acts once per stretch of not using the Mac, and starts over when you are
  back. Its timer stops as soon as you are: a touch of the mouse or keyboard
  at any time, or open eyes in the final minute of a timer the camera started.
  A quiet Mac's timer and the three-hour question never use the camera at the
  end, so only you can stop them.

For a nap outside those hours, click **Watch Now for a Nap** in the panel. The
night watch then works as at night until the Mac or its display goes to sleep;
**End Nap** stops it sooner and cancels its automatic timer. Turning off the
night watch also cancels its automatic timer. Choosing to keep sound playing
cancels an automatic timer when only sound is playing, including when video
stops later. These choices leave hand-set timers running.

Camera checks stay within bedtime or an active nap. Turning off the night
watch or camera cancels a pending check and releases its camera use. Ending a
nap, returning to the Mac, or leaving bedtime also cancels an ongoing check.
An open Settings preview keeps its own camera use until you hide it or close
Settings. A stalled or incomplete check cannot establish that nobody is there.

## Timer

1. Click the moon icon.
2. Set a duration with the slider or a preset, then click **Start Timer**. The
   panel offers two hours at first, then the length you chose last.
3. The icon fills in while the timer runs. Click it again to see the remaining
   time, add time, or stop.
4. A minute before the end, a panel in the top-right corner counts down and the
   volume fades. Leave it alone and the Mac sleeps; use the mouse or keyboard
   and it stays awake another 30 minutes. A timer that ran out while the Mac
   was already asleep (lid closed) is dropped on wake.

If the audio output changes during the fade, the previous device's volume is
restored where available and the new output fades from its own volume. Manual
volume changes are preserved.

Right-click the icon for a quick menu that shows what the night watch is doing,
starts a timer with the panel's presets, stops the current one, opens Settings,
or checks for updates. **Help > Watch Me While I Fall Asleep Help** opens the [README](../README.md).

## Settings

Open Settings from **Settings…** in the panel, from the right-click menu, or by
opening the app again from Finder or Spotlight (useful if its menu bar icon is
hidden).

- **Night watch**: on or off, bedtime (any start and end time), and **Use the
  camera**. **Camera
  preview > Show** turns the camera on to check that it sees your face; it goes
  off again with **Hide** or when Settings closes. Check it sitting or lying
  where you usually watch from. **When only sound plays**: stop it once you are asleep, or keep
  it playing.
- **Startup**: launch at login. Changes made in System Settings appear when
  you return to the app or open its Settings again.
- **Updates**: current version, automatic daily checks on or off, and a **Check
  for Updates…** button.

## Updates

The app uses [Sparkle](https://sparkle-project.org) (MIT licensed; its notice
ships in the app bundle) to check once a day for a new release. It never takes
focus from what you are doing: when an update is found, an **Install Update…**
button appears in the panel footer (its tooltip names the version), and the update window opens only when you
choose it or check by hand from Settings > Updates. Updates are signed with an
EdDSA key as well as the Developer ID, and install in place with a relaunch.
Automatic checks can be turned off in Settings.

## Troubleshooting

- **"Watch Me While I Fall Asleep is damaged and can't be opened":** releases
  before 2.1.0 were not notarized. Update to the latest release, or clear the
  quarantine flag with `xattr -cr "/Applications/Watch Me While I Fall Asleep.app"`.
- **Only the display turned off:** work was holding the Mac awake, and the app
  leaves it running. See what with `pmset -g assertions`.
- **The camera never looks:** enable the app under System Settings > Privacy &
  Security > Camera, turn on **Use the camera**, and check in the Settings
  preview that your face is visible and well lit. 2.1.0 is the first release
  signed with a Developer ID, a different signature from earlier builds, so
  macOS asks for camera access once more after the update.
- **No icon in the menu bar:** confirm you are on macOS 15 or later; on macOS 26
  also check System Settings > Menu Bar > Allow in the Menu Bar. Opening the app
  again shows its settings window either way.
- **The night watch did something unexpected:** turn on its diagnostics
  journal with `defaults write com.wiltodelta.watchmesleep Diagnostics.journal
  -bool true`; it records what it saw and did, without images, in
  `~/Library/Logs/WatchMeSleep/` ([diagnostics](diagnostics.md)).

## Uninstall

Quit the app from its panel, then move **Watch Me While I Fall Asleep.app** to
the Trash. To remove its settings too:

```bash
defaults delete com.wiltodelta.watchmesleep
rm -rf ~/Library/Logs/WatchMeSleep
```

Remove it from System Settings > Privacy & Security > Camera and from General >
Login Items as well.
