// Native helpers for capture-screenshots.sh. Compile outside the app targets.
import AppKit
import ApplicationServices
import Darwin
import IOKit
import ScreenCaptureKit

let args = CommandLine.arguments

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

func preflight() {
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    guard root != 0 else { fail("Cannot read the console session.") }
    defer { IOObjectRelease(root) }
    guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString,
                                                    kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]],
          let console = users.first(where: { $0["kCGSSessionOnConsoleKey"] as? Bool == true }),
          console["CGSSessionScreenIsLocked"] as? Bool != true,
          let front = NSWorkspace.shared.frontmostApplication,
          front.bundleIdentifier != "com.apple.loginwindow" else {
        fail("Unlock the Mac before capturing screenshots.")
    }
}

func window(_ pid: Int32, width: Int) -> [String: Any]? {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.first {
        guard $0[kCGWindowOwnerPID as String] as? Int32 == pid,
              let bounds = $0[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
        return Int(bounds["Width"] ?? 0) == width
    }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}

func descendants(_ element: AXUIElement) -> [AXUIElement] {
    [element] + ((attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        .flatMap { descendants($0) }
}

func controls(_ pid: Int32) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    return ((attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []).flatMap { descendants($0) }
}

switch args[1] {
case "preflight":
    preflight()
case "running":
    if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == args[2] }) {
        fail("Quit the development copy before capturing screenshots.")
    }
case "verify-defaults":
    let before = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: args[2])),
                                                          format: nil) as! NSDictionary
    let after = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: args[3])),
                                                         format: nil) as! NSDictionary
    guard before.isEqual(after) else { fail("Development defaults were not restored; keep the backup.") }
case "verify-args":
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, Int32(args[2])!]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { fail("Cannot read launch arguments.") }
    var bytes = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { fail("Cannot read launch arguments.") }
    let argc = bytes.withUnsafeBytes { $0.load(as: Int32.self) }
    var offset = MemoryLayout<Int32>.size
    while offset < size && bytes[offset] != 0 { offset += 1 }
    while offset < size && bytes[offset] == 0 { offset += 1 }
    let argv = bytes[offset..<size].split(separator: 0, omittingEmptySubsequences: false)
        .prefix(Int(argc)).map { String(decoding: $0, as: UTF8.self) }
    guard Array(argv.dropFirst()) == Array(args.dropFirst(3)) else { fail("Launch arguments did not arrive intact.") }
case "press":
    preflight()
    let elements = controls(Int32(args[2])!)
    guard let element = elements.first(where: { attribute($0, "AXIdentifier") as? String == args[3] }) else {
        let identifiers = elements.compactMap { attribute($0, "AXIdentifier") as? String }
        fail("No control named \(args[3]); found \(identifiers)")
    }
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard result == .success else { fail("AXPress failed: \(result.rawValue)") }
case "window":
    if let found = window(Int32(args[2])!, width: Int(args[3])!) {
        print(found[kCGWindowNumber as String]!)
    }
case "backdrop":
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.appearance = NSAppearance(named: args[3] == "dark" ? .darkAqua : .aqua)
    let backdrop = NSWindow(contentRect: NSScreen.screens[0].frame, styleMask: .borderless,
                            backing: .buffered, defer: false)
    backdrop.isOpaque = true
    backdrop.backgroundColor = args[3] == "dark"
        ? NSColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 1)
        : NSColor(srgbRed: 0.90, green: 0.92, blue: 0.95, alpha: 1)
    backdrop.ignoresMouseEvents = true
    backdrop.orderFrontRegardless()
    try String(backdrop.windowNumber).write(toFile: args[2], atomically: true, encoding: .utf8)
    app.run()
case "capture":
    // Capture only these two windows. Other apps and the on-screen notice
    // cannot leak into the result, even if someone changes focus mid-capture.
    Task { @MainActor in
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let target = content.windows.first(where: { $0.windowID == UInt32(args[2])! }),
                  let backdrop = content.windows.first(where: { $0.windowID == UInt32(args[3])! }),
                  let display = content.displays.first(where: { $0.frame.contains(target.frame) }) else {
                fail("The target and backdrop must both be visible on one display.")
            }
            let margin: CGFloat = 20
            let rect = target.frame.insetBy(dx: -margin, dy: -margin)
            let config = SCStreamConfiguration()
            config.sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            let screen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == display.displayID
            }
            let scale = screen?.backingScaleFactor ?? 2
            config.width = Int(rect.width * scale)
            config.height = Int(rect.height * scale)
            config.showsCursor = false
            config.colorSpaceName = CGColorSpace.sRGB
            let filter = SCContentFilter(display: display, including: [backdrop, target])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let rep = NSBitmapImageRep(cgImage: image)
            guard let png = rep.representation(using: .png, properties: [:]) else { fail("Cannot encode screenshot.") }
            try png.write(to: URL(fileURLWithPath: args[4]))
            print("Captured \(args[4]): \(image.width) x \(image.height)")
            exit(0)
        } catch {
            fail("Capture failed: \(error)")
        }
    }
    dispatchMain()
default:
    fail("Unknown screenshot helper command.")
}
