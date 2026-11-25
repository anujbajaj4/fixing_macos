import Foundation
import CoreGraphics

// A tiny test runner (no XCTest needed, so it builds with just the Command Line Tools):
//   swiftc Sources/Core/Core.swift Tests/main.swift -o build/tests && build/tests

var failures = 0
var count = 0
func check(_ ok: Bool, _ name: String, line: Int = #line) {
    count += 1
    if ok { print("ok   \(name)") } else { failures += 1; print("FAIL \(name) (line \(line))") }
}
func w(_ title: String, _ app: String = "App", min: Bool = false) -> WindowCandidate {
    WindowCandidate(title: title, appName: app, minimized: min)
}

// MARK: WindowMatcher
check(WindowMatcher.pick(thumbnailTitle: "Notes", from: [w("Notes"), w("Other")]) == .match(0),
      "exact title match")
check(WindowMatcher.pick(thumbnailTitle: "Notes", from: [w("Notes"), w("Notes")]) == .ambiguous(2),
      "two windows with the same title: refuse")
check(WindowMatcher.pick(thumbnailTitle: "Notes", from: [w("Notes", min: true), w("Notes")]) == .match(1),
      "minimized window with same title is ignored")
check(WindowMatcher.pick(thumbnailTitle: "Safari – Apple", from: [w("Apple"), w("Google")]) == .match(0),
      "loose match: thumbnail title contains window title")
check(WindowMatcher.pick(thumbnailTitle: "Finder", from: [w("", "Finder"), w("Docs", "Finder")]) == .match(0),
      "untitled window matched by app name")
check(WindowMatcher.pick(thumbnailTitle: "Report", from: [w("Report"), w("Re")]) == .match(0),
      "exact beats loose")
check(WindowMatcher.pick(thumbnailTitle: "a b", from: [w("a"), w("b")]) == .ambiguous(2),
      "two loose matches: refuse")
check(WindowMatcher.pick(thumbnailTitle: "Nothing", from: [w("Else")]) == .none, "no match")
check(WindowMatcher.pick(thumbnailTitle: "   ", from: [w("")]) == .none, "blank thumbnail title")
check(WindowMatcher.pick(thumbnailTitle: " Notes ", from: [w("Notes")]) == .match(0), "whitespace trimmed")
check(WindowMatcher.pick(thumbnailTitle: "Finder", from: [w("", "")]) == .none,
      "untitled window of nameless app doesn't match")

// MARK: ThumbnailFilter (shapes seen in Mission Control on macOS 15)
check(ThumbnailFilter.isWindowThumbnail(role: "AXButton", ancestorTitles: ["Mission Control", "Dock"]),
      "window thumbnail is a target")
check(!ThumbnailFilter.isWindowThumbnail(role: "AXDockItem", ancestorTitles: ["Dock"]),
      "Dock icon is never a target")
check(!ThumbnailFilter.isWindowThumbnail(role: "AXGroup", ancestorTitles: ["Dock"]),
      "the Mission Control group itself is not a target")
check(!ThumbnailFilter.isWindowThumbnail(role: "AXButton", ancestorTitles: ["Spaces Bar", "Mission Control", "Dock"]),
      "desktops in the Spaces Bar are not targets")
check(ThumbnailFilter.isBoundary(role: "AXDockItem") && !ThumbnailFilter.isBoundary(role: "AXButton"),
      "walking up stops at Dock items")
check(!ThumbnailFilter.isBoundary(role: "AXGroup"), "walking up passes through untitled groups")

// MARK: Geometry
let ax = CGRect(x: 100, y: 50, width: 24, height: 24)
check(Geometry.appKitRect(fromAX: ax, mainScreenHeight: 1000) == CGRect(x: 100, y: 926, width: 24, height: 24),
      "AX to AppKit flips y")
check(Geometry.closeButtonRect(forThumbnail: CGRect(x: 200, y: 300, width: 400, height: 300), size: 24)
        == CGRect(x: 188, y: 288, width: 24, height: 24),
      "close button centred on top-left corner")

// MARK: Version
check(Version.isNewer("1.2.10", than: "1.2.9"), "numeric, not string, compare")
check(Version.isNewer("v1.1", than: "1.0.9"), "leading v and short version")
check(!Version.isNewer("1.0.0", than: "1.0.0"), "same version isn't newer")
check(!Version.isNewer("1.0", than: "1.0.0"), "missing part counts as zero")
check(!Version.isNewer("0.9.9", than: "1.0.0"), "older isn't newer")

// MARK: Shortcut
let cmd = Shortcut.command
check(Shortcut.isCommandW(keycode: 13, flags: cmd), "⌘W")
check(Shortcut.isCommandW(keycode: 13, flags: cmd | 0x100), "⌘W with non-modifier flag bits")
check(!Shortcut.isCommandW(keycode: 13, flags: cmd | Shortcut.shift), "⇧⌘W passes through")
check(!Shortcut.isCommandW(keycode: 13, flags: cmd | Shortcut.option), "⌥⌘W passes through")
check(!Shortcut.isCommandW(keycode: 13, flags: 0), "plain W passes through")
check(!Shortcut.isCommandW(keycode: 12, flags: cmd), "⌘Q passes through")

print("\(count - failures)/\(count) passed")
exit(failures == 0 ? 0 : 1)
