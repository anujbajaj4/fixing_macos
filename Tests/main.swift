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
check(WindowMatcher.pick(thumbnailTitle: "Notes", from: [w("Notes"), w("Notes")]) == .ambiguous([0, 1]),
      "two windows with the same title: refuse")
check(WindowMatcher.pick(thumbnailTitle: "Notes", from: [w("Notes", min: true), w("Notes")]) == .match(1),
      "minimized window with same title is ignored")
check(WindowMatcher.pick(thumbnailTitle: "Safari – Apple", from: [w("Apple"), w("Google")]) == .match(0),
      "loose match: thumbnail title contains window title")
check(WindowMatcher.pick(thumbnailTitle: "Finder", from: [w("", "Finder"), w("Docs", "Finder")]) == .match(0),
      "untitled window matched by app name")
check(WindowMatcher.pick(thumbnailTitle: "Report", from: [w("Report"), w("Re")]) == .match(0),
      "exact beats loose")
check(WindowMatcher.pick(thumbnailTitle: "a b", from: [w("a"), w("b")]) == .ambiguous([0, 1]),
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

// MARK: macOS 27 (Mission Control in WindowManager)
check(MissionControl27.bundleID(fromThumbnailIdentifier: "com.apple.TextEdit.space.3") == "com.apple.TextEdit",
      "macOS 27 thumbnail id gives the app")
check(MissionControl27.bundleID(fromThumbnailIdentifier: "com.mitchellh.ghostty.space.12") == "com.mitchellh.ghostty",
      "…with multi-digit space numbers")
check(MissionControl27.bundleID(fromThumbnailIdentifier: "mc.spaces.add") == nil, "spaces controls aren't apps")
check(MissionControl27.bundleID(fromThumbnailIdentifier: "com.apple.TextEdit.space.") == nil, "missing space number")
check(MissionControl27.bundleID(fromThumbnailIdentifier: "") == nil, "no identifier")
check(MissionControl27.isDisplayGroup(identifier: "mc.display") && !MissionControl27.isDisplayGroup(identifier: "mc.spaces"),
      "mc.display marks Mission Control on macOS 27")
check(MissionControl27.isSpacesElement(identifier: "mc.spaces.list"), "desktops strip is skipped")
check(ThumbnailFilter.isWindowThumbnail(role: "AXButton", ancestorTitles: [], identifier: "com.apple.TextEdit.space.1"),
      "macOS 27 window thumbnail is a target")
check(!ThumbnailFilter.isWindowThumbnail(role: "AXButton", ancestorTitles: [], identifier: "mc.spaces.add"),
      "macOS 27 add-desktop button is not a target")

// MARK: MissionControlLayout (backup detection)
let screens = [CGRect(x: 0, y: 0, width: 1024, height: 768), CGRect(x: 1024, y: 0, width: 1920, height: 1080)]
check(MissionControlLayout.looksOpen(dockElements: [("AXList", CGRect(x: 0, y: 700, width: 900, height: 60)),
                                                    ("AXGroup", CGRect(x: 0, y: 0, width: 1024, height: 768))], screens: screens),
      "full-screen Dock group means Mission Control is open")
check(MissionControlLayout.looksOpen(dockElements: [("AXGroup", CGRect(x: 1024, y: 0, width: 1920, height: 1080))], screens: screens),
      "…on a second display too")
check(!MissionControlLayout.looksOpen(dockElements: [("AXList", CGRect(x: 0, y: 700, width: 900, height: 60))], screens: screens),
      "just the Dock's icon row: closed")
check(!MissionControlLayout.looksOpen(dockElements: [("AXGroup", CGRect(x: 0, y: 600, width: 300, height: 200))], screens: screens),
      "a small Dock group (e.g. a stack) isn't Mission Control")
check(!MissionControlLayout.looksOpen(dockElements: [("AXList", CGRect(x: 0, y: 0, width: 1024, height: 768))], screens: screens),
      "only groups count")

// MARK: Geometry
let ax = CGRect(x: 100, y: 50, width: 24, height: 24)
check(Geometry.appKitRect(fromAX: ax, mainScreenHeight: 1000) == CGRect(x: 100, y: 926, width: 24, height: 24),
      "AX to AppKit flips y")
let strip = Geometry.buttonStripRect(forThumbnail: CGRect(x: 200, y: 300, width: 400, height: 300), size: 22, gap: 6, count: 4)
check(strip == CGRect(x: 189, y: 289, width: 106, height: 22), "button strip: close centred on top-left corner, four buttons wide")
check(Geometry.buttonIndex(at: CGPoint(x: 200, y: 300), inStrip: strip, size: 22, gap: 6, count: 4) == 0, "point on close")
check(Geometry.buttonIndex(at: CGPoint(x: 228, y: 300), inStrip: strip, size: 22, gap: 6, count: 4) == 1, "point on minimize")
check(Geometry.buttonIndex(at: CGPoint(x: 256, y: 300), inStrip: strip, size: 22, gap: 6, count: 4) == 2, "point on full screen")
check(Geometry.buttonIndex(at: CGPoint(x: 284, y: 300), inStrip: strip, size: 22, gap: 6, count: 4) == 3, "point on zoom")
check(Geometry.buttonIndex(at: CGPoint(x: 213, y: 300), inStrip: strip, size: 22, gap: 6, count: 4) == nil, "point in the gap")
check(Geometry.buttonIndex(at: CGPoint(x: 320, y: 300), inStrip: strip, size: 22, gap: 6, count: 4) == nil, "point outside the strip")
check(WindowAction.buttons == [.close, .minimize, .fullScreen, .zoom], "buttons: window controls, then Option-green Zoom")
let visible = CGRect(x: 0, y: 25, width: 1440, height: 800)
check(Geometry.isFilling(CGRect(x: 0, y: 25, width: 1440, height: 800), visible), "window filling the screen counts as zoomed")
check(Geometry.isFilling(CGRect(x: 3, y: 28, width: 1436, height: 796), visible), "a few points of rounding still counts")
check(!Geometry.isFilling(CGRect(x: 100, y: 100, width: 800, height: 600), visible), "smaller window isn't zoomed")
check(Geometry.axRect(fromAppKit: CGRect(x: 0, y: 0, width: 1440, height: 875), mainScreenHeight: 900)
        == CGRect(x: 0, y: 25, width: 1440, height: 875), "AppKit visible frame to AX (menu bar at top)")

// MARK: ButtonLayout (fixed buttons on every thumbnail)
let thumbA = CGRect(x: 100, y: 200, width: 400, height: 300)
let thumbB = CGRect(x: 600, y: 200, width: 400, height: 300)
let r4 = ButtonLayout.rects(forThumbnail: thumbA, count: 4)
check(r4.count == 4 && r4[0] == CGRect(x: 109, y: 209, width: 13, height: 13), "first button inside the top-left corner")
check(r4[1].minX - r4[0].minX == 20 && r4[3].minX == 169, "buttons 20 pt apart, like window controls")
check(ButtonLayout.hit(CGPoint(x: 115, y: 215), thumbnails: [thumbA, thumbB], count: 4).map { $0.thumbnail == 0 && $0.button == 0 } == true, "hit close on first thumbnail")
check(ButtonLayout.hit(CGPoint(x: 675, y: 215), thumbnails: [thumbA, thumbB], count: 4).map { $0.thumbnail == 1 && $0.button == 3 } == true, "hit zoom on second thumbnail")
check(ButtonLayout.hit(CGPoint(x: 107, y: 207), thumbnails: [thumbA], count: 4).map { $0.thumbnail == 0 && $0.button == 0 } == true, "a little slop around a button still hits")
check(ButtonLayout.hit(CGPoint(x: 300, y: 350), thumbnails: [thumbA], count: 4) == nil, "middle of a thumbnail is not a button")
check(ButtonLayout.hit(CGPoint(x: 125.5, y: 215), thumbnails: [thumbA], count: 4) == nil, "the sliver between two buttons is not a button")
check(ButtonLayout.groupRect(forThumbnail: thumbA, count: 4).contains(CGPoint(x: 126, y: 215)), "between buttons still counts as hovering the group")

// MARK: Version
check(Version.isNewer("1.2.10", than: "1.2.9"), "numeric, not string, compare")
check(Version.isNewer("v1.1", than: "1.0.9"), "leading v and short version")
check(!Version.isNewer("1.0.0", than: "1.0.0"), "same version isn't newer")
check(!Version.isNewer("1.0", than: "1.0.0"), "missing part counts as zero")
check(!Version.isNewer("0.9.9", than: "1.0.0"), "older isn't newer")

// MARK: Shortcut
let cmd = Shortcut.command
check(Shortcut.action(keycode: 13, flags: cmd) == .close, "⌘W closes")
check(Shortcut.action(keycode: 13, flags: cmd | 0x100) == .close, "⌘W with non-modifier flag bits")
check(Shortcut.action(keycode: 46, flags: cmd) == .minimize, "⌘M minimizes")
check(Shortcut.action(keycode: 3, flags: cmd | Shortcut.control) == .fullScreen, "⌃⌘F full screen")
check(Shortcut.action(keycode: 4, flags: cmd) == .hideApp, "⌘H hides the app")
check(Shortcut.action(keycode: 12, flags: cmd) == .quitApp, "⌘Q quits the app")
check(Shortcut.action(keycode: 3, flags: cmd | Shortcut.option) == .zoom, "⌥⌘F zooms")
check(Shortcut.action(keycode: 3, flags: cmd) == nil, "⌘F (find) passes through")
check(Shortcut.action(keycode: 13, flags: cmd | Shortcut.shift) == nil, "⇧⌘W passes through")
check(Shortcut.action(keycode: 13, flags: cmd | Shortcut.option) == nil, "⌥⌘W passes through")
check(Shortcut.action(keycode: 4, flags: cmd | Shortcut.option) == nil, "⌥⌘H (hide others) passes through")
check(Shortcut.action(keycode: 13, flags: 0) == nil, "plain W passes through")
check(Shortcut.action(keycode: 0, flags: cmd) == nil, "⌘A passes through")
check(WindowAction.quitApp.isAppAction && !WindowAction.close.isAppAction, "quit acts on the app, close on the window")

print("\(count - failures)/\(count) passed")
exit(failures == 0 ? 0 : 1)
