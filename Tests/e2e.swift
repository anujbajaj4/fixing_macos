import Cocoa
import ApplicationServices

// End-to-end test on a real Mac with MC Close running and Accessibility granted
// (GitHub's macOS runners grant it). It drives Mission Control for real:
//   1. opens TextEdit windows e2e-alpha.txt, e2e-beta.txt, e2e-gamma.txt
//   2. opens Mission Control, checks MC Close noticed
//   3. hovers alpha's thumbnail, checks the ✕ appears, presses ⌘W, checks alpha closed
//   4. hovers beta's thumbnail, clicks the ✕, checks beta closed
//   5. leaves Mission Control, checks the ✕ is gone and ⌘W passes through to TextEdit (gamma closes)
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
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.filter { ($0[kCGWindowOwnerName as String] as? String) == "MCClose" }
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

// MARK: - Setup

ok(AXIsProcessTrusted(), "this test process has Accessibility (needed to drive the mouse and keyboard)")
ok(!NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.anujbajaj4.MCClose").isEmpty,
   "MC Close is running")

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcclose-e2e")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for n in ["alpha", "beta", "gamma"] {
    let f = dir.appendingPathComponent("e2e-\(n).txt")
    try? "MC Close end-to-end test: \(n)\n".write(to: f, atomically: true, encoding: .utf8)
}
sh("open -a TextEdit '\(dir.path)/e2e-alpha.txt' '\(dir.path)/e2e-beta.txt' '\(dir.path)/e2e-gamma.txt'")
wait(4)
// Spread the windows out so their thumbnails don't overlap.
sh("""
osascript -e 'tell application "TextEdit"' \
  -e 'set bounds of window "e2e-alpha.txt" to {40, 80, 640, 480}' \
  -e 'set bounds of window "e2e-beta.txt" to {700, 80, 1300, 480}' \
  -e 'set bounds of window "e2e-gamma.txt" to {300, 500, 900, 880}' -e 'end tell' </dev/null 2>/dev/null
""")
wait(1)
let before = textEditWindowTitles()
print("TextEdit windows: \(before)")
ok(before.contains("e2e-alpha.txt") && before.contains("e2e-beta.txt"), "TextEdit test windows are open")
shot("1-windows")

// MARK: - Mission Control

let logBefore = logText().count
sh("open -a 'Mission Control'")
wait(2.5)
shot("2-mission-control")
let newLog = String(logText().dropFirst(logBefore))
ok(newLog.contains("Dock says AXExposeShowAllWindows"), "MC Close noticed Mission Control opening")

let elements = dockElements()
print("Dock elements with a title while Mission Control is open (\(elements.count)):")
for e in elements.prefix(60) {
    print("  \(e.role)\(e.subrole.isEmpty ? "" : "/" + e.subrole)  \"\(e.title)\"  \(Int(e.frame.minX)),\(Int(e.frame.minY)) \(Int(e.frame.width))x\(Int(e.frame.height))")
}

// MARK: ⌘W on alpha
if let alpha = thumbnail("e2e-alpha") {
    move(to: center(alpha)); wait(0.6)
    let ov = overlayFrames()
    shot("3-hover-alpha", inline: true)
    ok(!ov.isEmpty, "✕ button appears when hovering a thumbnail")
    if let b = ov.first {
        ok(abs(b.midX - alpha.minX) < 3 && abs(b.midY - alpha.minY) < 3,
           "✕ sits on the thumbnail's top-left corner (✕ \(b), thumbnail \(alpha))")
    }
    key(13, command: true)   // ⌘W
    wait(1.5)
    shot("4-after-cmd-w")
    ok(!textEditWindowTitles().contains("e2e-alpha.txt"), "⌘W in Mission Control closed the hovered window")
    ok(textEditWindowTitles().contains("e2e-beta.txt"), "…and only that window")
} else {
    ok(false, "found alpha's thumbnail in Mission Control")
}

// MARK: ✕ click on beta
wait(1)   // Mission Control re-lays out after a close
if let beta = thumbnail("e2e-beta") {
    move(to: center(beta)); wait(0.6)
    if let b = overlayFrames().first {
        // Approach the ✕ from the thumbnail so the overlay keeps targeting beta.
        move(to: CGPoint(x: b.midX + 6, y: b.midY + 6)); wait(0.2)
        click(center(b))
        wait(1.5)
        shot("5-after-x-click")
        ok(!textEditWindowTitles().contains("e2e-beta.txt"), "clicking ✕ closed the hovered window")
    } else {
        ok(false, "✕ button appears when hovering beta")
    }
} else {
    ok(false, "found beta's thumbnail in Mission Control")
}

// MARK: Dock icons are not targets
if let dockIcon = dockElements().first(where: { $0.role == "AXDockItem" && $0.title == "TextEdit" }) {
    move(to: center(dockIcon.frame)); wait(0.6)
    ok(overlayFrames().isEmpty, "no ✕ on a Dock icon in Mission Control")
}

// MARK: leaving Mission Control
key(53)   // Escape
wait(2)
shot("6-after-exit")
ok(logText().contains("Dock says AXExposeExit"), "MC Close noticed Mission Control closing")
ok(overlayFrames().isEmpty, "✕ button is gone after leaving Mission Control")

// ⌘W outside Mission Control must reach the app as usual.
sh("osascript -e 'tell application \"TextEdit\" to activate' </dev/null")
wait(1)
if textEditWindowTitles().contains("e2e-gamma.txt") {
    key(13, command: true)
    wait(1.5)
    ok(!textEditWindowTitles().contains("e2e-gamma.txt"), "⌘W outside Mission Control still works in the app (TextEdit closed its window)")
} else {
    ok(false, "gamma window still open before pass-through test")
}

sh("osascript -e 'tell application \"TextEdit\" to quit saving no' </dev/null 2>/dev/null")
print("--- MC Close log during the test ---")
print(String(logText().dropFirst(logBefore)))
print(failures == 0 ? "END-TO-END: all passed" : "END-TO-END: \(failures) failed")
exit(failures == 0 ? 0 : 1)
