#!/bin/bash
# Regenerate README screenshots from the signed development bundle.
# Usage: ./capture-screenshots.sh [light|dark|all] (default: all).
# Requires Accessibility and Screen Recording. Uses AX identifiers, never mouse
# coordinates. ScreenCaptureKit composites only the app and a clean backdrop.
# The camera stays off. Appearance overrides apply only to the development app.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-all}"
case "$MODE" in light|dark|all) ;; *) echo "Usage: $0 [light|dark|all]" >&2; exit 2 ;; esac
APP_NAME="Watch Me While I Fall Asleep Dev"
APP_DIR="$PWD/$APP_NAME.app"
DOMAIN="com.wiltodelta.watchmesleep.dev"
EXECUTABLE="$APP_DIR/Contents/MacOS/WatchMeSleep"
WORK=$(mktemp -d)
PID=""
BACKDROP_PID=""
SAVED_DEFAULTS=false
HAD_DEFAULTS=false
stop_app() {
    [ -n "$PID" ] || return 0
    kill "$PID" 2>/dev/null || true
    for _ in $(seq 1 50); do
        if ! kill -0 "$PID" 2>/dev/null; then PID=""; return 0; fi
        sleep 0.1
    done
    echo "Development app did not exit; defaults backup retained at $WORK/defaults.plist" >&2
    return 1
}
cleanup() {
    # Terminating our process disarms its timer and closes its windows.
    stop_app || return 1
    if [ -n "$BACKDROP_PID" ]; then kill "$BACKDROP_PID" 2>/dev/null || true; wait "$BACKDROP_PID" 2>/dev/null || true; fi
    if $SAVED_DEFAULTS; then
        if $HAD_DEFAULTS; then
            defaults import "$DOMAIN" "$WORK/defaults.plist"
            defaults export "$DOMAIN" "$WORK/restored.plist"
            helper verify-defaults "$WORK/defaults.plist" "$WORK/restored.plist"
        else
            defaults delete "$DOMAIN" 2>/dev/null || true
        fi
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
swiftc -O scripts/screenshot-helper.swift -o "$WORK/helper"
helper() { "$WORK/helper" "$@"; }
helper preflight
helper running "$DOMAIN"
if defaults export "$DOMAIN" "$WORK/defaults.plist" 2>/dev/null; then HAD_DEFAULTS=true; fi
SAVED_DEFAULTS=true
./create-app.sh
mkdir -p screenshots

ax() {
    helper preflight
    osascript -e "with timeout of 10 seconds" \
        -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to $1" \
        -e "end timeout"
}
control() { helper press "$PID" "$1"; }

open_panel() {
    for _ in 1 2 3 4; do
        if [ -n "$(helper window "$PID" 360)" ] && [ "$(ax 'count windows')" -ge 1 ]; then return; fi
        ax 'click menu bar item 1 of menu bar 2' >/dev/null
        sleep 0.5
    done
    echo "The panel did not open." >&2; exit 1
}
capture_panel() {
    open_panel
    local id
    id=$(helper window "$PID" 360)
    [ -n "$id" ] || { echo "No panel window." >&2; exit 1; }
    helper capture "$id" "$BACKDROP_ID" "$WORK/$1$SUFFIX.png"
}

for THEME in light dark; do
    [ "$MODE" = all ] || [ "$MODE" = "$THEME" ] || continue
    SUFFIX=""
    if [ "$THEME" = dark ]; then SUFFIX=-dark; fi
    helper backdrop "$WORK/backdrop-id" "$THEME" &
    BACKDROP_PID=$!
    for _ in $(seq 1 30); do [ -s "$WORK/backdrop-id" ] && break; sleep 0.1; done
    BACKDROP_ID=$(cat "$WORK/backdrop-id")
    ARGS=(-Timer.selectedHours 2 -NightWatch.enabled YES
          -NightWatch.bedtimeStart 1260 -NightWatch.bedtimeEnd 480
          -AutoActivation.checksWithCamera NO -NightWatch.soundChoiceAsked YES
          -NightWatch.keepsSoundPlaying NO -Screenshot.appearance "$THEME"
          -AppleLanguages '(en)' -AppleLocale en_US)
    helper preflight
    open "$APP_DIR" --args "${ARGS[@]}"
    for _ in $(seq 1 30); do
        PID=$(pgrep -f "^$EXECUTABLE" || true)
        [ -n "$PID" ] && break
        sleep 0.2
    done
    [ -n "$PID" ] || { echo "The development app did not start." >&2; exit 1; }
    helper verify-args "$PID" "${ARGS[@]}"
    sleep 2
    open_panel
    # Verify that the requested idle state was reached before starting a timer.
    ax 'get help of menu bar item 1 of menu bar 2' | grep -q 'Night watch' || exit 1
    capture_panel manual-timer
    open_panel
    control startTimer
    sleep 1
    ax 'get help of menu bar item 1 of menu bar 2' | grep -q 'running' || exit 1
    capture_panel active-manual-timer
    open_panel
    control stopTimer
    control openSettings
    ax 'set frontmost to true' >/dev/null
    sleep 1
    SETTINGS_ID=$(helper window "$PID" 500)
    [ -n "$SETTINGS_ID" ] || { echo "Settings did not open." >&2; exit 1; }
    helper capture "$SETTINGS_ID" "$BACKDROP_ID" "$WORK/settings$SUFFIX.png"
    stop_app
    kill "$BACKDROP_PID"; wait "$BACKDROP_PID" 2>/dev/null || true; BACKDROP_PID=""
    rm "$WORK/backdrop-id"
    # Publish a complete theme only after every state was captured successfully.
    for NAME in manual-timer active-manual-timer settings; do
        cp "$WORK/$NAME$SUFFIX.png" "screenshots/$NAME$SUFFIX.png"
    done
done
