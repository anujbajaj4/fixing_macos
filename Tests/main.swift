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
check(WindowMatcher.pick(thumbnailTitle: "Alpha Beta", from: [w("Alpha"), w("Beta")]) == .ambiguous([0, 1]),
      "two loose matches: refuse")
// Seen on macOS 27 (Preview): the thumbnail and the window title differ a little.
check(WindowMatcher.pick(thumbnailTitle: "Report.pdf", from: [w("Report.pdf — Edited"), w("Other.pdf")]) == .match(0),
      "an Edited ending doesn't matter")
check(WindowMatcher.pick(thumbnailTitle: "report.pdf", from: [w("Report.pdf"), w("Other.pdf")]) == .match(0), "case doesn't matter")
check(WindowMatcher.pick(thumbnailTitle: "Report", from: [w("Report.pdf (page 2 of 9)"), w("Other.pdf")]) == .match(0),
      "a window title that contains the thumbnail's matches")
check(WindowMatcher.pick(thumbnailTitle: "a", from: [w("ab")]) == .none, "one-letter titles don't loosely match")
// Seen on macOS 27: the thumbnail reads "Preview — <file>.pdf" and Preview also has a helper window titled "Preview".
check(WindowMatcher.pick(thumbnailTitle: "Preview — FOS0000.pdf", from: [w("FOS0000.pdf", "Preview"), w("Preview", "Preview"), w("Other.pdf", "Preview")]) == .match(0),
      "a document's name beats a helper window called just the app's name")
check(WindowMatcher.pick(thumbnailTitle: "Report draft notes", from: [w("Report draft"), w("Report")]) == .match(0),
      "the most specific loose title wins")
check(WindowMatcher.pick(thumbnailTitle: "Report draft notes", from: [w("Report draft"), w("draft notes")]) == .ambiguous([0, 1]),
      "two equally specific titles: refuse")
// The thumbnail's shape breaks ties and, within one app, can find the window alone.
func ws(_ t: String, _ wd: CGFloat, _ ht: CGFloat) -> WindowCandidate { WindowCandidate(title: t, appName: "Preview", minimized: false, size: CGSize(width: wd, height: ht)) }
let thumbShape = CGSize(width: 383, height: 251)   // a 600x400 window in Mission Control (1.5 : 1)
check(WindowMatcher.pick(thumbnailTitle: "Untitled", thumbnailSize: thumbShape, from: [ws("Untitled", 600, 400), ws("Untitled", 800, 900)]) == .match(0),
      "same title twice: the one with the thumbnail's shape wins")
check(WindowMatcher.pick(thumbnailTitle: "Untitled", thumbnailSize: thumbShape, from: [ws("Untitled", 600, 400), ws("Untitled", 900, 600)]) == .ambiguous([0, 1]),
      "same title and same shape: refuse")
check(WindowMatcher.pick(thumbnailTitle: "Something else entirely", thumbnailSize: thumbShape, shapeAlone: true,
                         from: [ws("Doc A", 600, 400), ws("Doc B", 500, 700), ws("Doc C", 400, 800)]) == .match(0),
      "within one app, no title fits: the only window with that shape")
check(WindowMatcher.pick(thumbnailTitle: "Something else entirely", thumbnailSize: thumbShape,
                         from: [ws("Doc A", 600, 400), ws("Doc B", 500, 700)]) == .none,
      "across all apps, shape alone never picks a window")
// Seen on macOS 27 (Finder): buttons landed far from the controls, as with the wrong (smaller) window.
check(WindowMatcher.pick(thumbnailTitle: "Searching This Mac", thumbnailSize: thumbShape, from: [ws("Searching This Mac", 400, 700)]) == .none,
      "a title match whose shape clearly disagrees with the thumbnail is refused")
check(WindowMatcher.pick(thumbnailTitle: "Searching This Mac", thumbnailSize: thumbShape, from: [ws("Searching This Mac", 640, 440)]) == .match(0),
      "a title match with the thumbnail's shape (within 10%) is kept")
check(WindowMatcher.pick(thumbnailTitle: "Something else entirely", thumbnailSize: thumbShape, shapeAlone: true,
                         from: [ws("Doc A", 600, 400), ws("Doc B", 300, 200)]) == .ambiguous([0, 1]),
      "two windows with that shape: refuse")
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

// MARK: ThumbnailSanity (no buttons where there's no window)
let big = CGRect(x: 0, y: 0, width: 600, height: 400)
let other = CGRect(x: 650, y: 0, width: 300, height: 200)
let tucked = CGRect(x: 100, y: 80, width: 120, height: 90)      // inside `big`, like the rows inside Activity Monitor
let speck = CGRect(x: 50, y: 500, width: 20, height: 12)         // a zero-ish helper window
let edge = CGRect(x: 550, y: 350, width: 120, height: 100)       // overlaps a corner only
check(ThumbnailSanity.check([big, other, tucked, speck, edge]) == [.keep, .keep, .insideAnother, .tooSmall, .keep],
      "drops tiny placeholders and ones tucked inside a bigger thumbnail, keeps neighbours")
check(ThumbnailSanity.check([big, big]) == [.keep, .keep], "two equal thumbnails don't cancel each other")

// MARK: ButtonLayout (fixed buttons on every thumbnail)
let thumbA = CGRect(x: 100, y: 200, width: 400, height: 300)
let thumbB = CGRect(x: 600, y: 200, width: 400, height: 300)
let r4 = ButtonLayout.rects(forThumbnail: thumbA, count: 4)
check(r4.count == 4 && r4[0] == CGRect(x: 108, y: 208, width: 13, height: 13), "default row inside the top-left corner")
check(r4[1].minX - r4[0].minX == 20 && r4[3].minX == 168, "default buttons 20 pt apart, like window controls")
let rows = [r4, ButtonLayout.rects(forThumbnail: thumbB, count: 4)]
check(ButtonLayout.hit(CGPoint(x: 115, y: 215), rows: rows).map { $0.thumbnail == 0 && $0.button == 0 } == true, "hit close on first thumbnail")
check(ButtonLayout.hit(CGPoint(x: 674, y: 215), rows: rows).map { $0.thumbnail == 1 && $0.button == 3 } == true, "hit zoom on second thumbnail")
check(ButtonLayout.hit(CGPoint(x: 106, y: 206), rows: rows).map { $0.thumbnail == 0 && $0.button == 0 } == true, "a little slop around a button still hits")
check(ButtonLayout.hit(CGPoint(x: 300, y: 350), rows: rows) == nil, "middle of a thumbnail is not a button")
check(ButtonLayout.hit(CGPoint(x: 124.5, y: 215), rows: rows) == nil, "the sliver between two buttons is not a button")
check(ButtonLayout.groupRect(r4).contains(CGPoint(x: 124.5, y: 215)), "between buttons still counts as hovering the group")
let narrow = CGRect(x: 0, y: 0, width: 77, height: 160)   // e.g. Calculator
check(ButtonLayout.scale(forThumbnail: narrow, count: 4) < 1 && ButtonLayout.rects(forThumbnail: narrow, count: 4)[3].maxX <= narrow.maxX,
      "narrow thumbnails get a smaller default row that stays inside")

// Over the window's own controls: a 1000x700 window with controls of 14 pt at (20,20), 20 apart,
// shown as a 500x350 thumbnail (scale 0.5).
let native = NativeControls(closeCenter: CGPoint(x: 20, y: 20), diameter: 14, spacing: 20, windowSize: CGSize(width: 1000, height: 700))
let thumbN = CGRect(x: 100, y: 100, width: 500, height: 350)
let nr = ButtonLayout.rects(forThumbnail: thumbN, count: 4, native: native)
check(abs(nr[0].midX - 110) < 0.01 && abs(nr[0].midY - 110) < 0.01, "close sits exactly on the miniature close button")
check(abs(nr[0].width - 9) < 0.01, "7 pt miniature controls get the 9 pt minimum, centred on them")
check(abs((nr[1].midX - nr[0].midX) - 10.5) < 0.01, "spacing follows the window's, widened just enough to keep a gap")
let offNative = NativeControls(closeCenter: CGPoint(x: 400, y: 600), diameter: 14, spacing: 20, windowSize: CGSize(width: 1000, height: 700))
check(ButtonLayout.rects(forThumbnail: thumbN, count: 4, native: offNative) == ButtonLayout.rects(forThumbnail: thumbN, count: 4),
      "a measurement that wouldn't land in the top-left corner falls back to the default row")
let bigThumb = CGRect(x: 0, y: 0, width: 800, height: 560)   // scale 0.8
let nb = ButtonLayout.rects(forThumbnail: bigThumb, count: 4, native: native)
check(abs(nb[0].width - 11.2) < 0.01 && abs((nb[1].midX - nb[0].midX) - 16) < 0.01 && abs(nb[2].midX - 48) < 0.01,
      "at a larger scale the buttons match the miniature controls exactly")

// MARK: Motion (buttons ride with the windows)
check(Motion.easeOut(0) == 0 && Motion.easeOut(1) == 1 && Motion.easeOut(2) == 1 && Motion.easeOut(-1) == 0, "easing starts at 0, ends at 1")
check(Motion.easeOut(0.5) > 0.5, "ease-out moves fast first")
let home = [CGRect(x: 1000, y: 500, width: 14, height: 14)]
let there = [CGRect(x: 100, y: 100, width: 7, height: 7)]
check(Motion.row(from: home, to: there, progress: 0) == home && Motion.row(from: home, to: there, progress: 1) == there,
      "rows start on the real controls and end on the thumbnail")
let mid = Motion.row(from: home, to: there, progress: 0.5)[0]
check(mid.minX < 1000 && mid.minX > 100 && mid.width < 14 && mid.width > 7, "part-way, the row is between, shrinking")
check(Motion.row(from: home + home, to: there, progress: 0.5) == there, "mismatched rows jump straight to the end")

// MARK: ButtonConfig (choose and order the buttons)
check(ButtonConfig.standard.visible == [.close, .minimize, .fullScreen, .zoom], "standard: the window's controls plus zoom")
check(ButtonConfig(serialized: nil) == .standard && ButtonConfig(serialized: []) == .standard, "nothing stored: standard")
let stored = ButtonConfig(serialized: ["zoom", "close", "-minimize", "quitApp", "bogus", "close"])
check(stored.visible == [.zoom, .close, .quitApp], "stored order and choices are kept; junk and repeats skipped")
check(stored.items.count == WindowAction.allCases.count && stored.items.suffix(2).allSatisfy { !$0.shown },
      "actions missing from the stored list are added, hidden")
check(ButtonConfig(serialized: stored.serialized) == stored, "saving and loading round-trips")
var cfg = ButtonConfig.standard
cfg.move(from: 3, to: 0)
check(cfg.visible == [.zoom, .close, .minimize, .fullScreen], "drag zoom to the front")
cfg.setShown(.minimize, false); cfg.setShown(.hideApp, true)
check(cfg.visible == [.zoom, .close, .fullScreen, .hideApp], "hide minimize, add Hide App")
cfg.move(from: 0, to: 99)
check(cfg.items.last?.action == .zoom, "moving past the end puts it last")

// MARK: ButtonTheme
check(ButtonTheme.system.resolved(systemAccent: -1) == .graphite, "Match System on a Graphite Mac draws grey buttons")
check(ButtonTheme.system.resolved(systemAccent: nil) == .multicolor, "Match System on a Multicolor Mac draws red, yellow, green")
check(ButtonTheme.system.resolved(systemAccent: 4) == .multicolor, "a blue accent still has red, yellow, green window controls")
check(ButtonTheme.blue.resolved(systemAccent: -1) == .blue, "a chosen theme wins over the system")
check(ButtonTheme.allCases.count == 10 && ButtonTheme.graphite.label == "Graphite" && ButtonTheme.system.label == "Match System",
      "all macOS accent choices, named as in System Settings")

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
check(WindowAction.allCases.allSatisfy { a in
        let k = Shortcut.keys(for: a)
        return Shortcut.summary.contains(k)
      }, "Settings shows the same keys as the menu")
check(WindowAction.quitApp.isAppAction && !WindowAction.close.isAppAction, "quit acts on the app, close on the window")

print("\(count - failures)/\(count) passed")
exit(failures == 0 ? 0 : 1)
