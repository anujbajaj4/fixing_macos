import Cocoa
import ApplicationServices

// End-to-end test on a real Mac with MC Close running and Accessibility granted
// (GitHub's macOS runners grant it). It opens TextEdit windows and Calculator, opens
// Mission Control for real, and checks every button and shortcut on the window under
// the pointer: close (⌘W and button), minimize (⌘M and button), zoom (button, then ⌥⌘F
// to restore), quit app (⌘Q), full screen (button). Then it leaves Mission Control and
// checks the buttons are gone and ⌘W reaches TextEdit as usual.
// Build: swiftc Tests/e2e.swift -o build/e2e ; run: build/e2e <dir for screenshots>

let shots = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory()
let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MCClose.log")
var failures = 0
func ok(_ cond: Bool, _ name: String) {
    print(cond ? "ok   \(name)" : "FAIL \(name)")
    if !cond { failures += 1 }
}
func wait(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
func sh(_ cmd: String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = ["-c", cmd]
    try? p.run(); p.waitUntilExit()
}
func shot(_ name: String, inline: Bool = false) {
    sh("screencapture -x '\(shots)/\(name).png' 2>/dev/null")
    // A small copy in the log, for reviewers who can't download artifacts.
    if inline {
        sh("sips -Z 800 -s format jpeg -s formatOptions 60 '\(shots)/\(name).png' --out '\(shots)/\(name).jpg' >/dev/null 2>&1 && echo \"SCREENSHOT \(name) $(base64 -i '\(shots)/\(name).jpg' | tr -d '\\n')\"")
    }
}
func logText() -> String { (try? String(contentsOf: logURL, encoding: .utf8)) ?? "" }

func attr<T>(_ el: AXUIElement, _ a: String) -> T? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success else { return nil }
    return v as? T
}
func frame(_ el: AXUIElement) -> CGRect? {
    guard let p: AXValue = attr(el, kAXPositionAttribute), let s: AXValue = attr(el, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p, .cgPoint, &pt); AXValueGetValue(s, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}

/// Every Dock element with a title, for finding thumbnails (and for the log, so we learn the shape).
func dockElements() -> [(role: String, subrole: String, title: String, frame: CGRect)] {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [] }
    var out: [(String, String, String, CGRect)] = []
    func walk(_ el: AXUIElement, _ depth: Int) {
        if depth > 10 || out.count > 400 { return }
        let title: String = attr(el, kAXTitleAttribute) ?? ""
        if !title.isEmpty, let f = frame(el) {
            out.append((attr(el, kAXRoleAttribute) ?? "?", attr(el, kAXSubroleAttribute) ?? "", title, f))
        }
        for child in (attr(el, kAXChildrenAttribute) as [AXUIElement]?) ?? [] { walk(child, depth + 1) }
    }
    walk(AXUIElementCreateApplication(dock.processIdentifier), 0)
    return out
}

func textEditWindowTitles() -> [String] {
    guard let te = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else { return [] }
    let app = AXUIElementCreateApplication(te.processIdentifier)
    return ((attr(app, kAXWindowsAttribute) as [AXUIElement]?) ?? []).compactMap { attr($0, kAXTitleAttribute) }
}

/// MC Close's on-screen windows (the ✕ panel), in top-left global coordinates.
func overlayFrames() -> [CGRect] {
    // Match by process, not name: the window server lists it under the display name "MC Close".
    let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.anujbajaj4.MCClose")
        .map { Int($0.processIdentifier) })
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    // Only the ✕ panel: it sits far above normal windows; the menu-bar icon (layer 25) doesn't.
    return info.filter { pids.contains(($0[kCGWindowOwnerPID as String] as? Int) ?? -1)
                         && (($0[kCGWindowLayer as String] as? Int) ?? 0) >= 1000 }
        .compactMap { d in (d[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
}

let src = CGEventSource(stateID: .hidSystemState)
func move(to p: CGPoint) {
    CGWarpMouseCursorPosition(p)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func click(_ p: CGPoint) {
    move(to: p); wait(0.2)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    wait(0.05)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func key(_ code: CGKeyCode, command: Bool = false) {
    let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
    if command { down?.flags = .maskCommand; up?.flags = .maskCommand }
    down?.post(tap: .cghidEventTap); wait(0.05); up?.post(tap: .cghidEventTap)
}
func center(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
func thumbnail(_ name: String) -> CGRect? {
    dockElements().first { $0.role == "AXButton" && $0.title.contains(name) && $0.frame.width > 40 }?.frame
}

// MARK: - Helpers for this test

let buttonSize: CGFloat = 22, buttonGap: CGFloat = 6   // as in WindowButtonsOverlay
enum Button: Int { case close = 0, minimize, fullScreen, zoom }

func teWindow(_ title: String) -> AXUIElement? {
    guard let te = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else { return nil }
    let app = AXUIElementCreateApplication(te.processIdentifier)
    return ((attr(app, kAXWindowsAttribute) as [AXUIElement]?) ?? []).first { (attr($0, kAXTitleAttribute) as String?) == title }
}
func boolAttr(_ el: AXUIElement?, _ a: String) -> Bool {
    guard let el, let n: NSNumber = attr(el, a) else { return false }
    return n.boolValue
}
/// Point at a window's thumbnail; returns its frame.
@discardableResult
func hover(_ name: String) -> CGRect? {
    wait(0.8)   // Mission Control re-lays out after each action
    var found = thumbnail(name)
    for _ in 0..<4 where found == nil { wait(1); found = thumbnail(name) }   // still animating in
    guard let f = found else {
        print("no thumbnail for \(name); Dock shows: " + dockElements().filter { $0.role != "AXDockItem" }.map { "\($0.role) \"\($0.title)\"" }.joined(separator: ", "))
        return nil
    }
    move(to: center(f)); wait(0.6)
    return f
}
/// Click one of the buttons on the hovered thumbnail.
func clickButton(_ b: Button) -> Bool {
    guard let strip = overlayFrames().first else { return false }
    let p = CGPoint(x: strip.minX + buttonSize / 2 + CGFloat(b.rawValue) * (buttonSize + buttonGap), y: strip.midY)
    // Approach from the thumbnail side so the overlay keeps targeting the same window.
    move(to: CGPoint(x: p.x + 3, y: p.y + 3)); wait(0.2)
    click(p)
    return true
}
func visibleScreenAX() -> CGRect {
    let h = NSScreen.screens.first?.frame.height ?? 0
    let v = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
    return CGRect(x: v.minX, y: h - v.maxY, width: v.width, height: v.height)
}

/// Every on-screen window outside layer 0 (owner, layer, frame), to learn what Mission Control
/// looks like in the window list on this macOS.
func windowSurvey(_ label: String) {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    print("window survey (\(label)):")
    for d in info {
        let layer = d[kCGWindowLayer as String] as? Int ?? 0
        guard layer != 0, let b = d[kCGWindowBounds as String] as? NSDictionary, let f = CGRect(dictionaryRepresentation: b) else { continue }
        print("  \(d[kCGWindowOwnerName as String] as? String ?? "?") layer \(layer) \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))")
    }
}

// MARK: - Setup

let logAtStart = logText().count
ok(AXIsProcessTrusted(), "this test process has Accessibility (needed to drive the mouse and keyboard)")
ok(!NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.anujbajaj4.MCClose").isEmpty,
   "MC Close is running")

let names = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "theta"]
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcclose-e2e")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for n in names {
    try? "MC Close end-to-end test: \(n)\n".write(to: dir.appendingPathComponent("e2e-\(n).txt"), atomically: true, encoding: .utf8)
}
sh("open -a TextEdit " + names.map { "'\(dir.path)/e2e-\($0).txt'" }.joined(separator: " "))
sh("open -a Calculator")
wait(5)
// Different sizes and places, so the thumbnails are easy to tell apart.
let bounds = ["{20, 60, 420, 360}", "{440, 60, 840, 360}", "{860, 60, 1260, 360}", "{20, 380, 420, 680}",
              "{440, 380, 840, 680}", "{100, 120, 600, 520}", "{860, 380, 1260, 680}"]
sh("osascript -e 'tell application \"TextEdit\"' " +
   zip(names, bounds).map { "-e 'set bounds of window \"e2e-\($0).txt\" to \($1)'" }.joined(separator: " ") +
   " -e 'end tell' </dev/null 2>/dev/null")
wait(1)
let before = textEditWindowTitles()
print("TextEdit windows: \(before)")
ok(names.allSatisfy { before.contains("e2e-\($0).txt") }, "TextEdit test windows are open")
let zetaBefore = teWindow("e2e-zeta.txt").flatMap(frame)
shot("1-windows")

// MARK: - Mission Control

// No false alarm: with Mission Control closed, the backup check must not think it's open.
ok(!logText().dropFirst(logAtStart).contains("Dock layout shows Mission Control (no notification"),
   "backup check stays quiet while Mission Control is closed")
let logBefore = logText().count
windowSurvey("Mission Control closed")
sh("open -a 'Mission Control'")
wait(2.5)
shot("2-mission-control")
windowSurvey("Mission Control open")
let opened = String(logText().dropFirst(logBefore))
ok(opened.contains("Dock says AXExposeShowAllWindows") || opened.contains("Dock layout shows Mission Control (no notification"),
   "MC Close noticed Mission Control opening")
print("detected by: \(opened.contains("Dock layout shows") ? "Dock layout (backup)" : "Dock notification")")

let elements = dockElements()
print("Dock elements with a title while Mission Control is open (\(elements.count)):")
for e in elements.prefix(60) where e.role != "AXDockItem" {
    print("  \(e.role)\(e.subrole.isEmpty ? "" : "/" + e.subrole)  \"\(e.title)\"  \(Int(e.frame.minX)),\(Int(e.frame.minY)) \(Int(e.frame.width))x\(Int(e.frame.height))")
}

// MARK: Buttons appear, in the right place
if let alpha = hover("e2e-alpha") {
    let ov = overlayFrames()
    shot("3-hover-alpha", inline: true)
    ok(!ov.isEmpty, "buttons appear when hovering a thumbnail")
    if let b = ov.first {
        ok(abs(b.width - (4 * buttonSize + 3 * buttonGap)) < 2, "four buttons: close, minimize, full screen, zoom (strip \(b))")
        ok(abs(b.minX + buttonSize / 2 - alpha.minX) < 3 && abs(b.midY - alpha.minY) < 3,
           "close button sits on the thumbnail's top-left corner")
    }
    // MARK: ⌘W
    key(13, command: true)
    wait(1.5)
    ok(teWindow("e2e-alpha.txt") == nil, "⌘W closed the hovered window")
    ok(teWindow("e2e-beta.txt") != nil, "…and only that window")
} else { ok(false, "found alpha's thumbnail") }

// MARK: Close button
if hover("e2e-beta") != nil, clickButton(.close) {
    wait(1.5)
    ok(teWindow("e2e-beta.txt") == nil, "close button closed the hovered window")
} else { ok(false, "close button shown on beta") }

// MARK: Minimize button
if hover("e2e-delta") != nil, clickButton(.minimize) {
    wait(1.5)
    ok(boolAttr(teWindow("e2e-delta.txt"), kAXMinimizedAttribute), "minimize button minimized the hovered window")
} else { ok(false, "buttons shown on delta") }

// MARK: ⌘M
if hover("e2e-epsilon") != nil {
    key(46, command: true)
    wait(1.5)
    ok(boolAttr(teWindow("e2e-epsilon.txt"), kAXMinimizedAttribute), "⌘M minimized the hovered window")
} else { ok(false, "found epsilon's thumbnail") }

// MARK: Zoom button, then ⌥⌘F restores
if hover("e2e-zeta") != nil, clickButton(.zoom) {
    wait(1.5)
    let z = teWindow("e2e-zeta.txt").flatMap(frame) ?? .zero
    let v = visibleScreenAX()
    shot("5-after-zoom", inline: true)
    ok(abs(z.width - v.width) < 12 && abs(z.height - v.height) < 12,
       "zoom button made the window fill the screen (window \(z), screen \(v))")
    ok(!boolAttr(teWindow("e2e-zeta.txt"), "AXFullScreen"), "…without going full screen")
    if hover("e2e-zeta") != nil {
        let down = CGEvent(keyboardEventSource: src, virtualKey: 3, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 3, keyDown: false)
        down?.flags = [.maskCommand, .maskAlternate]; up?.flags = [.maskCommand, .maskAlternate]
        down?.post(tap: .cghidEventTap); wait(0.05); up?.post(tap: .cghidEventTap)
        wait(1.5)
        let r = teWindow("e2e-zeta.txt").flatMap(frame) ?? .zero
        if let zb = zetaBefore {
            ok(abs(r.width - zb.width) < 12 && abs(r.height - zb.height) < 12,
               "⌥⌘F on a zoomed window put it back to its size (now \(r), before \(zb))")
        }
    } else { ok(false, "found zeta's thumbnail after zoom") }
} else { ok(false, "buttons shown on zeta") }

// MARK: ⌘Q quits the app under the pointer
if hover("Calculator") != nil {
    key(12, command: true)
    wait(2.5)
    ok(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.calculator").isEmpty,
       "⌘Q quit the app whose window was under the pointer (Calculator)")
    ok(teWindow("e2e-gamma.txt") != nil, "…and left other apps alone")
} else { ok(false, "found Calculator's thumbnail") }

// MARK: Dock icons are not targets
wait(0.8)
if let dockIcon = dockElements().first(where: { $0.role == "AXDockItem" && $0.title == "TextEdit" }) {
    move(to: center(dockIcon.frame)); wait(0.6)
    ok(overlayFrames().isEmpty, "no buttons on a Dock icon in Mission Control")
}

func waitFor(_ seconds: Double, _ cond: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { if cond() { return true }; wait(0.25) }
    return cond()
}

// MARK: leaving Mission Control
func noticedExit(since offset: Int) -> Bool {
    let l = logText().dropFirst(offset)
    return l.contains("Dock says AXExposeExit") || l.contains("Dock layout shows Mission Control closed")
}
key(53)   // Escape
wait(2)
ok(noticedExit(since: logBefore), "MC Close noticed Mission Control closing")
ok(overlayFrames().isEmpty, "buttons are gone after leaving Mission Control")

// ⌘W outside Mission Control must reach the app as usual.
// Bring gamma to the front with Accessibility calls (an AppleScript here hung for 2 minutes in CI).
NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first?.activate()
if let g = teWindow("e2e-gamma.txt") {
    _ = AXUIElementPerformAction(g, kAXRaiseAction as CFString)
    _ = AXUIElementSetAttributeValue(g, kAXMainAttribute as CFString, kCFBooleanTrue)
}
wait(1.5)
if teWindow("e2e-gamma.txt") != nil {
    key(13, command: true)
    ok(waitFor(4) { teWindow("e2e-gamma.txt") == nil },
       "⌘W outside Mission Control still works in the app (TextEdit closed its window)")
} else {
    ok(false, "gamma window still open before pass-through test")
}

// MARK: Full-screen button (last: it leaves Mission Control and changes spaces)
let logBeforeFullScreen = logText().count
sh("open -a 'Mission Control'")
wait(2.5)
if hover("e2e-theta") != nil, clickButton(.fullScreen) {
    let became = waitFor(8) { boolAttr(teWindow("e2e-theta.txt"), "AXFullScreen") }
    shot("6-after-full-screen", inline: true)
    ok(became, "full-screen button left Mission Control and put the hovered window in full screen")
    ok(noticedExit(since: logBeforeFullScreen), "…and MC Close noticed Mission Control closing")
} else { ok(false, "buttons shown on theta") }
if let theta = teWindow("e2e-theta.txt"), boolAttr(theta, "AXFullScreen") {
    _ = AXUIElementSetAttributeValue(theta, "AXFullScreen" as CFString, kCFBooleanFalse)
    _ = waitFor(8) { !boolAttr(teWindow("e2e-theta.txt"), "AXFullScreen") }
    wait(1.5)
}

sh("osascript -e 'tell application \"TextEdit\" to quit saving no' </dev/null 2>/dev/null")
print("--- MC Close log during the test ---")
print(String(logText().dropFirst(logBefore)))
print(failures == 0 ? "END-TO-END: all passed" : "END-TO-END: \(failures) failed")
exit(failures == 0 ? 0 : 1)
