#!/bin/bash
#
# Regenerate the README screenshots in screenshots/ from a fresh build.
#
# Drives the app only through Accessibility (opening the status item, pressing
# controls by identifier), never with synthetic mouse clicks, so nothing lands on
# other windows or system prompts. The terminal running it needs Accessibility and
# Screen Recording access. Captures follow the current system appearance.
#
# The camera screenshot turns the camera on for a few seconds and blurs the feed
# before saving: the repository is public. The timer screenshot starts a real
# timer; the script always stops it again, including on failure.

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Watch Me While I Fall Asleep"
APP_DIR="$APP_NAME.app"
EXECUTABLE="$PWD/$APP_DIR/Contents/MacOS/WatchMeSleep"
OUT="screenshots"
WORK=$(mktemp -d)

# --- Build ----------------------------------------------------------------------

# CI=1 stamps the version from the latest git tag instead of "dev", so the
# screenshots show a released version that is up to date, not an update prompt.
pkill -f "$EXECUTABLE" 2>/dev/null || true
CI=1 ./create-app.sh >"$WORK/build.log" 2>&1 || { cat "$WORK/build.log"; exit 1; }

# --- Helper: window lookup and blur ---------------------------------------------

cat >"$WORK/helper.swift" <<'SWIFT'
import AppKit
import CoreImage

// window <pid> <width>          -> "id x y w h" of the on-screen window that wide
// named <pid> <title>           -> "id x y w h" of the on-screen window with that title
// menubar                       -> the menu bar height in points
// backdrop <x> <y> <w> <h>      -> show a plain backdrop window there (screen points,
//                                  top-left origin) until killed
// pad <png> <top>               -> add <top> points above the image in its top-left color
// blur <png> <x> <y> <w> <h> <r> -> blur inside that rounded rect (points, top-left)
let args = CommandLine.arguments

/// A mask that is opaque inside a rounded rect (Core Image coordinates).
func roundedMask(extent: CGRect, rect: CGRect, radius: CGFloat) -> CIImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(extent.width), height: Int(extent.height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
    return CIImage(cgImage: ctx.makeImage()!)
}

func load(_ path: String) -> (URL, CIImage, CGFloat, NSBitmapImageRep) {
    let url = URL(fileURLWithPath: path)
    let rep = NSBitmapImageRep(data: try! Data(contentsOf: url))!
    return (url, CIImage(contentsOf: url)!, CGFloat(rep.pixelsWide) / rep.size.width, rep)
}

func save(_ image: CIImage, to url: URL) {
    try! CIContext().writePNGRepresentation(of: image, to: url, format: .RGBA8,
                                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
}
func windows(_ pid: Int32) -> [[String: Any]] {
    let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return all.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
}

func printFrame(_ w: [String: Any]) {
    let b = w[kCGWindowBounds as String] as! [String: CGFloat]
    print(w[kCGWindowNumber as String]!, Int(b["X"]!), Int(b["Y"]!), Int(b["Width"]!), Int(b["Height"]!))
}
switch args[1] {
case "window":
    let widthMatch = windows(Int32(args[2])!).first {
        Int(($0[kCGWindowBounds as String] as! [String: CGFloat])["Width"]!) == Int(args[3])!
    }
    if let w = widthMatch { printFrame(w) }
case "named":
    if let w = windows(Int32(args[2])!).first(where: { ($0[kCGWindowName as String] as? String) == args[3] }) {
        printFrame(w)
    }
case "menubar":
    let screen = NSScreen.screens[0]
    print(Int(screen.frame.maxY - screen.visibleFrame.maxY))
case "backdrop":
    let (x, y, w, h) = (Double(args[2])!, Double(args[3])!, Double(args[4])!, Double(args[5])!)
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let screenHeight = NSScreen.screens[0].frame.height
    let window = NSWindow(contentRect: NSRect(x: x, y: screenHeight - y - h, width: w, height: h),
                          styleMask: .borderless, backing: .buffered, defer: false)
    // Opaque, so nothing behind it shows through, and a shade darker than the
    // panel, so its edge reads against the margin.
    window.isOpaque = true
    NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
        window.backgroundColor = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!
            .blended(withFraction: 0.07, of: .black)!.withAlphaComponent(1)
    }
    window.level = .normal // front of the ordinary app windows, below the status-bar panel
    window.ignoresMouseEvents = true
    window.orderFrontRegardless()
    app.run()
case "pad":
    let (url, image, scale, rep) = load(args[2])
    let top = (CGFloat(Double(args[3])!) * scale).rounded()
    // Sample the captured backdrop rather than recompute its color: the capture
    // passes through the display's color management.
    let fill = rep.colorAt(x: 4, y: 4)!.usingColorSpace(.sRGB)!
    let canvas = CGRect(x: 0, y: 0, width: image.extent.width, height: image.extent.height + top)
    let background = CIImage(color: CIColor(color: fill)!).cropped(to: canvas)
    save(image.composited(over: background), to: url)
case "blur":
    let (url, image, scale, _) = load(args[2])
    let (x, y, w, h, r) = (CGFloat(Double(args[3])!), CGFloat(Double(args[4])!), CGFloat(Double(args[5])!),
                           CGFloat(Double(args[6])!), CGFloat(Double(args[7])!))
    // Core Image's origin is bottom-left.
    let rect = CGRect(x: x * scale, y: image.extent.height - (y + h) * scale, width: w * scale, height: h * scale)
    let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: 40 * scale).cropped(to: image.extent)
    let mask = roundedMask(extent: image.extent, rect: rect, radius: r * scale)
    save(blurred.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask
    ]).cropped(to: image.extent), to: url)
default:
    exit(2)
}
SWIFT
swiftc -O "$WORK/helper.swift" -o "$WORK/helper" 2>"$WORK/helper.log" || { cat "$WORK/helper.log"; exit 1; }
helper() { "$WORK/helper" "$@"; }

# --- Accessibility driving -------------------------------------------------------

open "$APP_DIR"
PID=""
for _ in $(seq 1 20); do
    PID=$(pgrep -f "$EXECUTABLE" | head -1 || true)
    [ -n "$PID" ] && break
    sleep 0.5
done
[ -n "$PID" ] || { echo "The app did not start."; exit 1; }
sleep 5 # let the launch-time update check settle

ax() { osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to $1"; }

panel() { helper window "$PID" 360; } # the panel width set in WatchMeSleepApp.swift

open_panel() {
    for _ in 1 2 3 4; do
        if [ -n "$(panel)" ] && [ "$(ax 'count windows')" -ge 1 ]; then return 0; fi
        ax 'click menu bar item 1 of menu bar 2' >/dev/null
        sleep 1.5
    done
    echo "The panel did not open."; return 1
}

# Find the control whose AXIdentifier (or radio button title) matches $1 and
# either press it or print its "x y w h" in screen points ($2: press | frame).
control() {
    osascript <<AS
tell application "System Events" to tell (first process whose unix id is $PID)
    set els to entire contents of window 1
    repeat with e in els
        set hit to false
        try
            set hit to ((value of attribute "AXIdentifier" of e) is "$1")
        end try
        try
            if not hit then set hit to (role of e is "AXRadioButton" and description of e is "$1")
        end try
        if hit then
            if "$2" is "press" then
                perform action "AXPress" of e
                return ""
            end if
            set p to position of e
            set s to size of e
            return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
        end if
    end repeat
    error "No control named $1"
end tell
AS
}
press() { control "$1" press >/dev/null; }
frame_of() { control "$1" frame; }

timer_running() { ax 'get help of menu bar item 1 of menu bar 2' | grep -q "running"; }

BACKDROP_PID=""
cleanup() {
    [ -n "$BACKDROP_PID" ] && kill "$BACKDROP_PID" 2>/dev/null
    # Never leave a timer armed or the camera on.
    if timer_running 2>/dev/null; then open_panel && press stopTimer || true; fi
    open_panel >/dev/null 2>&1 && press Timer >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

# The panel is Liquid Glass: a single-window capture renders it without what sits
# behind it, as flat gray. So every screenshot puts a plain backdrop under the
# window and captures that screen region with a MARGIN of backdrop on each side,
# window shadow included. The panel hangs right under the menu bar, so the top
# margin is taken only down to the menu bar and the rest is filled in the
# backdrop's color. Nothing else on screen reaches the image.
MARGIN=20
MENU_BAR=$(helper menubar)
show_backdrop() {
    "$WORK/helper" backdrop $(($1 - 2 * MARGIN)) $(($2 - 2 * MARGIN)) $(($3 + 4 * MARGIN)) $(($4 + 4 * MARGIN)) &
    BACKDROP_PID=$!
    sleep 1.2
}
# capture_region <name> <x> <y> <w> <h>: the window's frame in screen points.
capture_region() {
    local top=$((MARGIN < $3 - MENU_BAR ? MARGIN : $3 - MENU_BAR))
    screencapture -x -R"$(($2 - MARGIN)),$(($3 - top)),$(($4 + 2 * MARGIN)),$(($5 + top + MARGIN))" "$OUT/$1.png"
    kill "$BACKDROP_PID"; wait "$BACKDROP_PID" 2>/dev/null || true; BACKDROP_PID=""
    [ "$top" -lt "$MARGIN" ] && helper pad "$OUT/$1.png" $((MARGIN - top))
    echo "Captured $OUT/$1.png"
}
capture_panel() {
    open_panel # a press can close it
    read -r _ X Y W H < <(panel)
    show_backdrop "$X" "$Y" "$W" "$H"
    open_panel
    read -r _ X Y W H < <(panel)
    capture_region "$1" "$X" "$Y" "$W" "$H"
}

# --- Screens ---------------------------------------------------------------------

open_panel
press Timer
sleep 1
capture_panel manual-timer

press startTimer
sleep 2
capture_panel active-manual-timer
press stopTimer
sleep 1
if timer_running; then echo "The timer did not stop."; exit 1; fi

press Camera
sleep 5 # camera start-up and face detection
FRAME=""
for _ in $(seq 1 10); do # the feed appears once camera access is confirmed
    open_panel
    FRAME=$(frame_of cameraPreview 2>"$WORK/frame.err" || true)
    [ -n "$FRAME" ] && break
    sleep 1.5
done
[ -n "$FRAME" ] || { cat "$WORK/frame.err"; echo "No camera feed: grant camera access and rerun."; exit 1; }
read -r _ PX PY _ _ < <(panel)
read -r FX FY FW FH <<<"$FRAME"
capture_panel camera-mode
# The whole preview, border included: the video shows through the border's
# antialiased edge. 12 pt matches its corner radius in CameraModeView.
helper blur "$OUT/camera-mode.png" $((FX - PX + MARGIN)) $((FY - PY + MARGIN)) "$FW" "$FH" 12
echo "Blurred the camera feed in $OUT/camera-mode.png"
press Timer
sleep 1

open_panel
press openSettings
sleep 2
read -r SETTINGS_ID SX SY SW SH < <(helper named "$PID" "$APP_NAME Settings")
[ -n "${SETTINGS_ID:-}" ] || { echo "The settings window did not open."; exit 1; }
show_backdrop "$SX" "$SY" "$SW" "$SH"
ax 'set frontmost to true' >/dev/null # above the backdrop, key so controls render active
sleep 1
capture_region settings "$SX" "$SY" "$SW" "$SH"
ax 'click button 1 of window 1' >/dev/null || true
