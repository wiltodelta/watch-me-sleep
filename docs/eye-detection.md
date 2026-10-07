# Eye detection

How the night watch's camera look decides open or closed eyes, and the
measurement behind it. Code: `EyeReading` (per frame), `PresenceCheck` (over a
look), `CameraWatcher` (runs both detectors on each camera frame).

## Rule

A frame counts as closed eyes only when both detectors agree:

- Vision face landmarks (revision 3): the eyes' average aspect ratio (EAR) is
  below 0.20.
- Core Image's face detector with `CIDetectorEyeBlink`: both eyes closed.

Where only one of them finds a face, that one decides. Both read the largest
face in the frame. A look then needs 15 seconds of closed eyes in a row for
asleep; open eyes shorter than 1 second do not break that run, because single
misread frames are detector noise.

## Measurement, 2026-10-06

54 photographs from Wikimedia Commons (46 open eyes, 8 closed), labeled by hand
from the images, not from search terms; paintings, drawings and sculptures were
excluded. Each was scaled to 192 px wide, the width of a `.low` camera frame,
and read by the production code in three conditions.

| Rule | Condition | Open: right / wrong / no face | Closed: right / wrong / no face |
|---|---|---|---|
| EAR below 0.20 alone (3.0) | 192 px | 27 / 17 / 2 | 8 / 0 / 0 |
| Core Image blink alone | 192 px | 42 / 2 / 2 | 8 / 0 / 0 |
| Both must agree (now) | 192 px | 43 / 2 / 1 | 8 / 0 / 0 |
| Both must agree (now) | 192 px, turned 90 degrees | 42 / 3 / 1 | 8 / 0 / 0 |
| Both must agree (now) | 192 px, 2.5 stops darker with noise | 41 / 4 / 1 | 7 / 1 / 0 |

EAR alone took smiles, glasses and narrow eyes for closed: 17 of 46 open-eyed
people would have started a sleep timer. The remaining errors of the combined
rule are faces a few pixels wide in wide shots (a stage, a lectern), smaller
than a face in front of a laptop camera.

Live, on the built-in camera (2026-10-05), open eyes looking at the screen
gave EAR 0.20 to 0.26, median 0.234: under the old rule alone, one bad night
from being read as asleep.

Caveats:

- Only 8 closed-eye photographs: the sample says nothing went wrong, not how
  often it would. Of the photos of sleeping people found, most showed a face
  neither detector could find (lying turned away, covered); those read as no
  face, which the night watch treats like an empty chair once it has seen a
  face in the same stretch, so they still lead to sleep; a look that never
  saw a face counts as unclear instead.
- Stills, not video: the darkness and rotation are simulated.
- Cost: on a 192 px frame the blink classifier takes about 61 ms and Vision
  32 ms. The classifier runs only where its answer can matter: when Vision
  finds no face, or reads closed eyes during a look. Open eyes and the
  Settings preview cost Vision alone. Frames the queue cannot keep up with are
  dropped, and `PresenceCheck` measures time, not frames.

## Rerun

`Tests/EyeDetectionBenchmark.swift` prints the table for the production code.
It is skipped unless `WMS_FACE_DIR` names a folder of JPEGs with a
`labels.csv` (`file,label`, label `open` or `closed`):

```bash
WMS_FACE_DIR=/path/to/photos swift test --filter EyeDetectionBenchmark
```

The photos are not in the repository: they are other people's faces under
assorted licenses. Gather new ones from Wikimedia Commons (searches such as
"portrait face", "headshot", "asleep face", "napping"), and label each one by
looking at it.
