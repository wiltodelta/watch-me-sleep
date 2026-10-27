# Diagnostics journal

An opt-in diary of what the night watch saw and did, for debugging real
nights afterwards. The unified log cannot do this: the app logs at `.info`,
which macOS does not keep, so `log show` the next morning returns nothing.

## Turn it on

```bash
defaults write com.wiltodelta.watchmesleep Diagnostics.journal -bool true
```

It takes effect at once, without a relaunch; `-bool false` turns it off. It
is off by default, and the app has no switch for it. A development build (any
build without `RELEASE=1`) reads `com.wiltodelta.watchmesleep.dev` instead and
writes to `~/Library/Logs/WatchMeSleep Dev/`.

## Where it goes

`~/Library/Logs/WatchMeSleep/journal.jsonl`, one JSON object per line, with
`event` and the local time `t`. Past 10 MB the file moves to `journal.1.jsonl`,
replacing the one before: about a month of nights.

It holds no images and no camera frames: only numbers, verdicts, settings and
the names of processes holding the Mac awake.

## Events

| `event` | When | Fields |
|---|---|---|
| `launch` | The app starts | version and the settings |
| `settings` | A setting changes | the settings |
| `soundChoice` | The once-only sound question is answered | `keepsSoundPlaying` |
| `status` | The panel's status changes (at most once a minute while watching) | `status` plus the context below |
| `look` | A final-minute camera look starts (a decision look shows as `status` `looking`) | `kind` plus context |
| `look.skipped` | A final-minute look could not run | `looking` (another look was running) plus context |
| `camera.look` | A look ends, measured | `verdict`, `frames`, `seconds`, `faceSeconds`, `openSeconds`, `darkSeconds`, `meanLuma` |
| `camera.cancel` | A pending look is discarded and its camera ownership released; an open preview may keep the session running | none |
| `look.result` | The night watch reads the verdict | `verdict` as used (`asleep`, `absent`, and `unclear` start a timer) plus context |
| `look.ignored` | Input, a timer, settings or the watch window made the answer stale | `verdict` and `timerRunning` for decision looks, `kind` for final-minute looks, plus context |
| `arm` | The night watch starts a timer | `minutes`, `reason`, `looksAgain` plus context |
| `quietTimer.overruled` | Media started during the quiet Mac's timer | context |
| `nap` | Watch Now for a Nap starts or ends | `on`, and `why` when bedtime took over |
| `timer.start` | Any timer starts | `minutes`, `stopsOnInput`, `looksInFinalMinute` |
| `timer.finalMinute` | The warning and fade begin | `endsWithDisplayOff` |
| `timer.someoneThere` | Someone is at the Mac in a hand-set timer's final minute | `how` |
| `timer.postponed` | A hand-set timer moves on at zero | `minutes` |
| `timer.stop` | A timer stops before zero | `reason` (`input`, `open eyes`, `media started`, `stopped by hand`, `replaced`, `ran out while the Mac slept`, `night watch disabled`, `nap ended`, `keeping sound playing`), `remaining` |
| `sleep.request` | The app requests sleep or display off | `command`, `work`, `byHand` |
| `sleep` | The power command exits successfully; the `system` event confirms the OS transition | `command`, `work`, `byHand` |
| `sleep.failed` | The power command cannot launch or exits unsuccessfully; volume is restored | `command`, `error` |
| `system` | macOS sleeps, wakes, or turns the display off or on | `what` |

Context, on night watch events: `idle` (seconds without input at the latest
poll), `media`, `video`, `work`, `nap`, `cameraUsable`, `faceSeen`,
`cameraUnavailable`, `acted`.

For `camera.look`, `unavailable` also covers a timeout with some frames but
less than the full observation duration. Frame stalls do not count as observed
time and cannot produce an `absent` verdict.

## Read a night

```bash
J=~/Library/Logs/WatchMeSleep/journal.jsonl
# Everything since 9 PM yesterday, one line each
jq -c 'select(.t >= "2026-10-08T21:00")' "$J"
# The camera's lighting measurements (diagnostic only)
jq -c 'select(.event == "camera.look") | {t, verdict, meanLuma, faceSeconds, darkSeconds}' "$J"
# How each night ended
jq -c 'select(.event | startswith("sleep") or . == "timer.stop" or . == "system")' "$J"
```

## Interpret the evidence

- `camera.look` records the detector's verdict, not independently verified
  sleep. An `asleep` verdict followed by input or open eyes shows that the
  timer was canceled, but cannot distinguish a detector error from waking up.
  Photo benchmarks do not measure accuracy over real nights.
- Any completed decision look without evidence of wakefulness (`asleep`,
  `absent`, or `unclear`) starts a camera timer, including darkness and a
  hidden face. A previously seen face is not required. `unavailable` means
  there was no complete observation and uses the inactivity fallback instead.
  Open eyes in the final minute or input cancel the timer; other completed
  verdicts let it finish. An unavailable final-minute look also leaves an
  already armed timer running. `faceSeen` is diagnostic only.
- `sleep` means the requested command succeeded. Read `command`:
  `displaysleepnow` turns off the display and leaves the system running.
  Only a subsequent `system` event with `what: "will sleep"` confirms a
  system sleep transition; that event alone does not identify its cause.
- `work` reports the assertion classifier's result. It does not prove that
  a process is doing useful work. Classification matches assertion holders
  and audio players by PID; a browser appearing in `work` needs a live
  assertion and audio-PID investigation before changing the rule.

## Automatic timer cancellation

Disabling the night watch or ending an active nap cancels its running
automatic timer immediately. Choosing to keep sound playing also cancels an
automatic timer when only sound is playing; the same rule applies if a film
becomes sound-only later. A film's timer continues while video is still
playing. Hand-set timers remain independent of these choices.

Cancellation restores faded volume and invalidates any pending final-minute
camera answer. The journal records `timer.stop` with `night watch disabled`,
`nap ended`, or `keeping sound playing`. Watching can resume in the same idle
stretch when enabled again, a new nap starts, or the sound choice is reversed.

`SleepSupervisorTimerCancellationTests` exercises these transitions without
keyboard or mouse input, so input cancellation cannot mask a missing state
transition. The tests replace the sleep handler, camera, volume, defaults and
signal providers; they never run the real sleep command.
