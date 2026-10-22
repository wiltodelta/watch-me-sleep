# UI architecture

Relocated from the repo root `CLAUDE.md`. Read before editing `AppDelegate`, `MenuBarPanel.swift`, or `SettingsView`.

## Settings window

This is a menu-bar `.accessory` app. The SwiftUI `Settings` scene does NOT open reliably from it. `SettingsView` is hosted in a custom `NSWindow` by `AppDelegate`, opened via the `OpenSettings` notification (`openAppSettings()`), toggling `.regular`/`.accessory` activation policy around it. `windowWillClose` drops the window, so its SwiftUI views disappear on close: the camera preview (`CameraPreviewRow`) stops the camera in its `onDisappear`, which never fires on a window kept alive between openings.

## Menu-bar dropdown panel

The main dropdown is a custom arrowless borderless `NSPanel` (`MenuBarPanel.swift`), not an `NSPopover` (whose triangular arrow looks dated). Three things there are load-bearing and easy to regress:

- Window height is driven by `host.sizeThatFits(in:)`, NOT `NSHostingController.preferredContentSize`. The latter undercounts tall content and clipped the footer of the former, taller camera mode.
- The backing material stays at the AppKit level, outside the measured SwiftUI tree. On macOS 26+ it is an `NSGlassEffectView` (Liquid Glass) whose `contentView` is the hosting view; before that (macOS 15), an `NSVisualEffectView` with the `.popover` material sits as a sibling *behind* the hosting view. Embedding an effect inside the self-sizing SwiftUI content recurses through Auto Layout and crashes (stack overflow).
- Content width is pinned via `.frame(width:)`. Without it the greedy `maxWidth: .infinity` content collapses and the panel comes out too narrow. Corner rounding lives on a layer-backed `NSView` with `masksToBounds` that holds the backing, on every release. Rounding the visual-effect view itself leaves square opaque corners, and an `NSGlassEffectView` set as the window's root view draws a square rim along its bounds around its own rounded glass; the clip cuts both away.

Animating the height change is an open HIG gap: with `sizingOptions` left on, Auto Layout snaps the window before any `setFrame(animate:)`; turning it off and driving the height from `onGeometryChange` crashed in the window's layout display cycle (2026-09-23).

`NSPanel.configureAsStatusPanel()`, shared by the dropdown and the sleep warning, sets `isFloatingPanel` before `level`: the setter resets the level to `.floating`, which silently dropped the panel from `.statusBar` (25) to 3, under any other floating window.

The hosted content has a nearly opaque `windowBackgroundColor` backing. Glass
tint alone does not bound text contrast in the never-key sleep warning. Keep
the material outside the measured SwiftUI tree, and verify both panels over
black, gray and white backdrops after changing either backing or text colors.
The dropdown closes on key-focus loss or activation of another app, as well as
outside clicks and Escape. Activation of its own app does not dismiss it.

`capture-screenshots.sh` regenerates the README screenshots in both appearances through Accessibility identifiers and ScreenCaptureKit. It composites only the app window and an opaque backdrop, including a 20 pt margin, so Liquid Glass has a real background without capturing other apps. The camera stays off, and the development defaults are restored on exit. See [the screenshot recipe](screenshots.md).

The panel follows the system light/dark appearance. On macOS 26+ the system status-bar menus take the menu bar's appearance instead, so they can be dark while the system is light; do not copy that onto the panel (decided 2026-09-23).

## Right-click menu

`AppDelegate.showQuickMenu` builds an `NSMenu` and shows it as the status item's own menu (`statusItem.menu`, `performClick`, then cleared, so a left click still opens the panel), which lets macOS place it under the icon. A hand-placed `popUp(positioning:at:in:)` opened above the menu bar: clipped, with a scroll arrow over the status line. Its `appearance` is set to `NSApp.effectiveAppearance`, so it follows the system like the panel rather than the menu bar (fixed 2026-10-10); that is the system's only while the app sets no `NSApp.appearance` of its own. Verify it with a region capture, not a window capture, which draws the glass flat gray. The menu answers only to a real right click, so the status button also carries an accessibility custom action, Show Menu, that VoiceOver offers in its Actions rotor (`addShowMenuAction`). macOS 27 hides menu item images unless an item asks for them, so `showQuickMenu` sets `preferredImageVisibility` only for the timer and app-action groups (`showsImage`), the system's Quit icon included. The disabled status row and separators keep the system default.

## Sleep warning panel

`SleepWarningController` (`SleepWarningPanel.swift`) shows the timer's final minute in the top-right corner. It reuses `PanelHostController`, so it carries the same backing and rounding as the dropdown. It is a panel, not a notification, because the Sleep focus and full-screen video hide notifications. It never becomes key (`becomesKeyOnlyIfNeeded`), so a video player keeps its keyboard while the buttons still take a first click. Its buttons draw with `appearsActive = true`, so Sleep Now keeps its accent instead of the inactive gray a non-key window gets. This environment value is supported on the macOS 15 deployment target and replaces the soft-deprecated `controlActiveState` override. A single-window capture of it renders the glass flat gray, as above.

The warning uses its fixed content width when anchoring the first frame;
the window's measured width can still be zero before its first layout. Once
input guarantees postponement, both the warning and timer panel say that the
Mac stays awake instead of promising sleep at the old deadline.

## SDK version stamp

The Tahoe look (Liquid Glass controls, tinted buttons, current form styling) applies only when the binary's `LC_BUILD_VERSION` records a macOS 26+ SDK. SwiftPM's default Swift Build system in Xcode 27 records the deployment target there instead, and macOS then runs the app in its pre-Tahoe compatibility mode, including an empty SwiftUI `Settings` window at launch. `Package.swift` passes `-Xlinker -platform_version macos <deploymentTarget> 26.0` in the executable target's `linkerSettings`, so every build path (`create-app.sh`, `maintain.sh`, CI) gets it. The manifest cannot ask `xcrun` for the installed SDK, so 26.0 is a floor, not the real SDK version; `create-app.sh` fails the build if `vtool -show-build` reports an SDK below 26.

## Motion and status-item lifecycle

The timer-state transition in `ContentView` and face-status transition in
`CameraPreviewRow` read `accessibilityReduceMotion` from their SwiftUI environment.
When it is enabled, the changes are immediate rather than animated.

The status item retains the family's target/action lifecycle. macOS 27's
expanded-interface sessions remain a separate family-level adoption decision;
the availability of that API alone is not a rendering or interaction defect.

## Rendered audit follow-up

The 2026-10-21 audit on macOS 27.0.1 verified both system appearances, the
dropdown at 360 pt, the never-key warning at 320 pt and Settings at 500 pt.
The Liquid Glass slider ends, Increase Contrast and Reduce Transparency were
driven through System Settings. The 96% content backing remains deliberate.
Lower-opacity prototypes reduced the contrast reserve in backdrop composites.

At the Clear end, the native right-click menu measured 3.36:1 for enabled text
over black in light appearance and 2.68:1 over white in dark appearance. The
light case also reproduced with automatic menu appearance and with an
accessibility-high-contrast appearance override. Neither is a verified remedy.
An earlier 5.15:1 prototype measurement was confounded by the global glass
slider returning to 0.5; it must not be cited as a Clear-mode fix. Keep this
native-material limitation open. Text-outline and shadow prototypes were
rejected visually. The release decision is to retain the native menu, including
its system keyboard navigation and submenu behavior, with this Clear limitation.

For the dark menu, the Tinted end measured at least 5.85:1 across black, gray
and white backdrops. At that same slider position, system Increase Contrast
raised the minimum to 9.15:1; also enabling Reduce Transparency gave 15.13:1.
These accessibility measurements used Tinted, not Clear.

Raise the selected opaque backdrop before opening a menu, then composite that
same backdrop and menu. A composition against a different, hidden backdrop
does not independently verify the menu's adaptation to that background.

Icon Composer rendered Default, Dark and Mono previews with design generations
26 and 27. These are six captures of three base appearances, not evidence that
all six system Clear/Tinted combinations were individually exercised.

With Reduce Motion enabled, live timer transitions in both appearances received
`accessibilityReduceMotion = true` and `animation = nil`. A temporary transaction
probe also observed nil in its normal-motion control, so it does not establish
an animation difference between the two settings. Camera-preview layouts were
rendered offscreen in both appearances; no live camera transition was exercised.

After the audit, System Settings visibly returned to Light, glass tint 0.5 and
all three accessibility switches off. Fresh-process flags and full preference
domain comparisons matched the original snapshot without churn. Development
defaults were restored exactly, and the audit's app and backdrop windows closed.
