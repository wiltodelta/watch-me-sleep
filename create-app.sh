#!/bin/bash
# Build Watch Me While I Fall Asleep and assemble its signed .app bundle.
#   ./create-app.sh              everyday build (Developer ID when available, no timestamp)
#   RELEASE=1 ./create-app.sh    release build: Developer ID with a secure timestamp
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Watch Me While I Fall Asleep"
BUNDLE_ID="com.wiltodelta.watchmesleep"
APP_DIR="$APP_NAME.app"
BIN="WatchMeSleep"

# The latest release tag, as CI builds it, so a local build never reports an
# older version than the release (which Sparkle would then offer over it).
# --abbrev=0: the tag itself, not "2.1.0-5-gabc". CI must have the tag.
VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
if [[ -z "$VERSION" ]]; then
    [[ -n "${GITHUB_ACTIONS:-}" ]] && { echo "error: no git tag to take the version from" >&2; exit 1; }
    VERSION="0.0.0"
fi
echo "Building $APP_NAME $VERSION (release, arm64)..."

# Apple silicon only. The SDK version stamp lives in Package.swift, so every
# build path gets it; the check below fails the build if it ever drops back.
MACOS_MIN="$(sed -n 's/^let deploymentTarget = "\(.*\)"$/\1/p' Package.swift)"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
cp "$BIN_DIR/$BIN" "$APP_DIR/Contents/MacOS/$BIN"
SDK_STAMP="$(vtool -show-build "$APP_DIR/Contents/MacOS/$BIN" | awk '/ sdk /{print $2}')"
if ! [[ "$SDK_STAMP" =~ ^[0-9]+ ]] || (( ${SDK_STAMP%%.*} < 26 )); then
    echo "error: binary is stamped sdk $SDK_STAMP; below 26 macOS runs the pre-Tahoe look" >&2
    exit 1
fi

# Sparkle, found through @rpath: SwiftPM links it with @loader_path only, which
# is the build directory, so the bundle's Frameworks folder is added. Its XPC
# services exist for sandboxed apps; this app is not sandboxed, so Sparkle's
# docs allow removing them. Sparkle is MIT licensed; its notice ships with it.
ditto "$BIN_DIR/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
    "$APP_DIR/Contents/Frameworks/Sparkle.framework/XPCServices"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/$BIN"
cp ".build/artifacts/sparkle/Sparkle/LICENSE" "$APP_DIR/Contents/Resources/Sparkle LICENSE.txt"

# The Icon Composer icon ("App Icon", with Assets.car for macOS 26+ and a flat
# .icns for older releases) and the menu bar template images, in one Assets.car.
# Needs Xcode 26+ on a macOS 26 host. Absolute paths: actool resolves relative
# ones against the working directory of its long-lived agent, which is wherever
# it first started (another checkout, say), not this script's.
xcrun actool "$PWD/App Icon.icon" "$PWD/MenuIcons.xcassets" --compile "$PWD/$APP_DIR/Contents/Resources" \
    --platform macosx --minimum-deployment-target "$MACOS_MIN" --app-icon "App Icon" \
    --output-partial-info-plist "$(mktemp -t wms-icon)" >/dev/null

cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$BIN</string>
	<key>CFBundleIconFile</key>
	<string>App Icon</string>
	<key>CFBundleIconName</key>
	<string>App Icon</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright 2026 Victor Kuznetsov. Licensed under Apache-2.0.</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>$MACOS_MIN</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSCameraUsageDescription</key>
	<string>Watch Me While I Fall Asleep uses your camera to detect when you fall asleep by tracking your eye closure.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>SUFeedURL</key>
	<string>https://github.com/wiltodelta/watch-me-sleep/releases/latest/download/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string>hqKKidqlpRpssnvj1i6i1qY+jYdPjjDKIZHFyOxyGhc=</string>
	<key>SUEnableAutomaticChecks</key>
	<true/>
	<key>SURequireSignedFeed</key>
	<true/>
	<key>SUVerifyUpdateBeforeExtraction</key>
	<true/>
</dict>
</plist>
EOF

# Sign with the team's Developer ID Application identity when the keychain has it:
# its stable designated requirement keeps the Camera (TCC) grant across rebuilds
# and releases, and with the hardened runtime, the camera entitlement and
# (RELEASE=1) a secure timestamp it is what notarization requires (notarize.sh).
# The timestamp needs Apple's server, so everyday builds skip it and still work
# offline. Without the identity (contributors, CI branch builds) the bundle is
# signed ad hoc, which runs but re-prompts for camera access after every rebuild.
TEAM_ID="K2GT9Q4S6U"
ENTITLEMENTS="WatchMeSleep.entitlements"
SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' -v team="($TEAM_ID)" '/Developer ID Application:/ && index($2, team) {print $2; exit}')"
if [[ -n "$SIGN_IDENTITY" ]]; then
    TIMESTAMP="--timestamp=none"
    [[ "${RELEASE:-}" == 1 ]] && TIMESTAMP="--timestamp"
    SIGN=(codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_IDENTITY")
elif [[ "${RELEASE:-}" == 1 ]]; then
    echo "error: RELEASE=1 but no Developer ID Application identity for team $TEAM_ID" >&2
    exit 1
else
    echo "warning: no Developer ID Application identity, signing ad hoc (camera access will re-prompt)"
    SIGN=(codesign --force --sign -)
fi
# Inside out, in the order Sparkle's docs give: its helpers, the framework, then
# the app with its entitlements (no --deep, which would re-sign the helpers
# without their options).
SPARKLE="$APP_DIR/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP_DIR"

echo "Done: $PWD/$APP_DIR"
echo "Launch with: open \"$PWD/$APP_DIR\""
