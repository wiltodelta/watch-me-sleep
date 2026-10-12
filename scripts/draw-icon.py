#!/usr/bin/env python3
"""Draw the app icon's glass layers: Lucide's "moon-star" (ISC) on its 24-point
grid, scaled into the 1024-point Icon Composer canvas. Writes the two layer SVGs
in `App Icon.icon/Assets`; icon.json (the gradient fill and glass settings) is
edited in Icon Composer. Regenerate the layers here, never by hand.

The glyph fills about 60% of the canvas, the weight shared with the other apps'
icons (claude-config docs/macos-apps.md, "Icons")."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App Icon.icon" / "Assets"
SIZE = 1024
GRID = 24
SCALE = 31  # points per grid unit
OFFSET = SIZE / 2 - GRID / 2 * SCALE  # centres the grid on the canvas
STROKE = 1.5  # the plus's stroke on the grid

MOON = ("M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803"
        "a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401Z")


def svg(comment, body):
    return (f'<svg width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}" fill="none" '
            f'xmlns="http://www.w3.org/2000/svg">\n  <!-- {comment} -->\n  {body}\n</svg>\n')


def bar(x, y, width, height):
    """A grid-space rounded bar as a canvas-space rect."""
    s, r = SCALE, STROKE * SCALE / 2
    return (f'<rect x="{OFFSET + x * s - r:g}" y="{OFFSET + y * s - r:g}" width="{width * s + 2 * r:g}" '
            f'height="{height * s + 2 * r:g}" rx="{r:g}" fill="white"/>')


def main():
    moon = svg("The moon-star's moon. The background is the icon's fill, not part of a layer, "
               "so the system can restyle it per appearance.",
               f'<g transform="translate({OFFSET:g} {OFFSET:g}) scale({SCALE})">\n'
               f'    <path d="{MOON}" fill="white" stroke="white" stroke-width="0.5"/>\n  </g>')
    # The plus (M18 5h4, M20 3v4) as filled bars: the macOS 26 Icon Composer
    # renderer fills a stroked open path across its chord.
    sparkle = svg("The moon-star's plus as filled bars.",
                  bar(18, 5, 4, 0) + "\n  " + bar(20, 3, 0, 4))
    (ASSETS / "moon.svg").write_text(moon)
    (ASSETS / "sparkle.svg").write_text(sparkle)


if __name__ == "__main__":
    main()
