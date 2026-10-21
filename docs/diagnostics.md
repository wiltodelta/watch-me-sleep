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
| `look.result` | The night watch reads the verdict | `verdict` as used (nobody there before any face reads `unclear`) plus context |
| `look.ignored` | Input, a timer, settings or the watch window made the answer stale | `verdict` and `timerRunning` for decision looks, `kind` for final-minute looks, plus context |
| `arm` | The night watch starts a timer | `minutes`, `reason`, `looksAgain` plus context |
| `quietTimer.overruled` | Media started during the quiet Mac's timer | context |
| `nap` | Watch Now for a Nap starts or ends | `on`, and `why` when bedtime took over |
| `timer.start` | Any timer starts | `minutes`, `stopsOnInput`, `looksInFinalMinute` |
| `timer.finalMinute` | The warning and fade begin | `endsWithDisplayOff` |
| `timer.someoneThere` | Someone is at the Mac in a hand-set timer's final minute | `how` |
| `timer.postponed` | A hand-set timer moves on at zero | `minutes` |
| `timer.stop` | A timer stops before zero | `reason` (`input`, `open eyes`, `media started`, `stopped by hand`, `replaced`, `ran out while the Mac slept`), `remaining` |
| `sleep.request` | The app requests sleep or display off | `command`, `work`, `byHand` |
| `sleep` | The power command exits successfully; the `system` event confirms the OS transition | `command`, `work`, `byHand` |
| `sleep.failed` | The power command cannot launch or exits unsuccessfully; volume is restored | `command`, `error` |
| `system` | macOS sleeps, wakes, or turns the display off or on | `what` |

Context, on night watch events: `idle` (seconds without input at the latest
poll), `media`, `video`, `work`, `nap`, `cameraUsable`, `faceSeen`,
`unclearLooks`, `acted`.

For `camera.look`, `unavailable` also covers a timeout with some frames but
less than the full observation duration. Frame stalls do not count as observed
time and cannot produce an `absent` verdict.

## Read a night

```bash
J=~/Library/Logs/WatchMeSleep/journal.jsonl
# Everything since 9 PM yesterday, one line each
jq -c 'select(.t >= "2026-10-08T21:00")' "$J"
# The camera's numbers, to calibrate the darkness threshold (PresenceCheck.darkLuma)
jq -c 'select(.event == "camera.look") | {t, verdict, meanLuma, faceSeconds, darkSeconds}' "$J"
# How each night ended
jq -c 'select(.event | startswith("sleep") or . == "timer.stop" or . == "system")' "$J"
```
