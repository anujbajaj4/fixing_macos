import Foundation
import CoreGraphics

// Pure logic with no AppKit or Accessibility calls, so it can be unit-tested
// on its own (see Tests/main.swift).

/// A real window as seen through the Accessibility API, reduced to what matching needs.
struct WindowCandidate: Equatable {
    let title: String      // the window's AXTitle ("" if it has none)
    let appName: String    // the owning app's localized name
    let minimized: Bool    // minimized windows aren't shown in Mission Control
}

enum WindowMatcher {
    enum Outcome: Equatable {
        case match(Int)          // index into the candidates
        case none
        case ambiguous([Int])    // the equally good candidates
    }

    /// Pick the real window behind a Mission Control thumbnail, by title.
    ///
    /// 1. Exact title match wins, if there is exactly one.
    /// 2. Otherwise a "loose" match: the thumbnail title contains the window title,
    ///    or the window has no title and the thumbnail shows the app's name.
    /// If more than one window fits equally well we refuse: closing the wrong
    /// window is worse than closing nothing.
    static func pick(thumbnailTitle thumb: String, from candidates: [WindowCandidate]) -> Outcome {
        let thumb = thumb.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !thumb.isEmpty else { return .none }

        var exact: [Int] = []
        var loose: [Int] = []
        for (i, c) in candidates.enumerated() where !c.minimized {
            let title = c.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && title == thumb {
                exact.append(i)
            } else if (!title.isEmpty && thumb.contains(title))
                        || (title.isEmpty && !c.appName.isEmpty && thumb == c.appName) {
                loose.append(i)
            }
        }
        if exact.count == 1 { return .match(exact[0]) }
        if exact.count > 1 { return .ambiguous(exact) }
        if loose.count == 1 { return .match(loose[0]) }
        if loose.count > 1 { return .ambiguous(loose) }
        return .none
    }
}

/// What can be done to the window under the pointer in Mission Control.
enum WindowAction: String, CaseIterable {
    case close, minimize, fullScreen, zoom, hideApp, quitApp

    /// The buttons drawn on a thumbnail, left to right: the window's own three controls,
    /// then Zoom, which is what Option-clicking the green button does (its glyph turns into +).
    static let buttons: [WindowAction] = [.close, .minimize, .fullScreen, .zoom]

    /// Acts on the whole app rather than one window.
    var isAppAction: Bool { self == .hideApp || self == .quitApp }

    var label: String {
        switch self {
        case .close: return "Close"
        case .minimize: return "Minimize"
        case .fullScreen: return "Full Screen"
        case .zoom: return "Zoom"
        case .hideApp: return "Hide App"
        case .quitApp: return "Quit App"
        }
    }
}

/// Which titled Dock elements in Mission Control are window thumbnails.
/// Seen on macOS 15: thumbnails are AXButton titled with the window's title, inside an
/// AXGroup "Mission Control". Other titled things must never be targets: Dock icons
/// (AXDockItem "Finder" would loosely match an untitled Finder window), the full-screen
/// "Mission Control" group, the Dock app itself, and the Spaces Bar's desktops.
enum ThumbnailFilter {
    static let excludedRoles: Set<String> = ["AXApplication", "AXGroup", "AXDockItem", "AXWindow", "AXList"]

    /// Stop walking up the moment we reach one of these: the pointer isn't on a thumbnail.
    /// (Untitled groups are walked through; titled ones are rejected by isWindowThumbnail.)
    static func isBoundary(role: String) -> Bool { ["AXApplication", "AXDockItem", "AXList"].contains(role) }

    static func isWindowThumbnail(role: String, ancestorTitles: [String], identifier: String = "") -> Bool {
        !excludedRoles.contains(role) && !ancestorTitles.contains("Spaces Bar")
            && !identifier.hasPrefix("mc.")   // macOS 27: mc.spaces.add and other controls
    }
}

/// Mission Control on macOS 27 (reported by Hammerspoon, Glide and PaperWM developers):
/// its accessibility tree moved from the Dock to WindowManager (com.apple.WindowManager).
/// While it's open, WindowManager has an AXGroup "mc.display" per display; each window
/// thumbnail is an AXButton in it, titled with the window title, with the identifier
/// "<app bundle id>.space.<n>". Desktops sit under "mc.spaces". The Dock no longer posts
/// its Mission Control notifications (and on 27.2.1 has no Mission Control group at all).
enum MissionControl27 {
    static let windowManagerBundleID = "com.apple.WindowManager"

    static func isDisplayGroup(identifier: String) -> Bool { identifier == "mc.display" }

    /// The desktops strip and its controls: never window thumbnails.
    static func isSpacesElement(identifier: String) -> Bool { identifier.hasPrefix("mc.spaces") }

    /// "com.apple.TextEdit.space.3" → "com.apple.TextEdit"; nil for anything else.
    static func bundleID(fromThumbnailIdentifier id: String) -> String? {
        guard let r = id.range(of: ".space.", options: .backwards) else { return nil }
        let bundle = String(id[..<r.lowerBound])
        let number = id[r.upperBound...]
        guard !bundle.isEmpty, !bundle.hasPrefix("mc."), !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        return bundle
    }
}

/// Backup way to tell that Mission Control is open, for macOS versions where the Dock
/// doesn't post its notifications: while Mission Control (or App Exposé) is showing, the
/// Dock has a group covering a whole screen (seen on macOS 15: AXGroup "Mission Control",
/// 0,0 1024x768). Normally it only has its icon row (an AXList).
enum MissionControlLayout {
    static func looksOpen(dockElements: [(role: String, frame: CGRect)], screens: [CGRect]) -> Bool {
        dockElements.contains { el in
            el.role == "AXGroup" && screens.contains { screen in
                el.frame.width >= screen.width * 0.8 && el.frame.height >= screen.height * 0.8
            }
        }
    }
}

enum Geometry {
    /// Which of `frames` the pointer is on. If several contain it, the smallest wins
    /// (the most specific one). nil if none.
    static func index(of point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.indices
            .filter { frames[$0].contains(point) }
            .min { frames[$0].width * frames[$0].height < frames[$1].width * frames[$1].height }
    }

    /// Accessibility frames use a top-left origin on the main display; AppKit
    /// windows use a bottom-left origin. Convert an AX rect to an AppKit rect.
    static func appKitRect(fromAX r: CGRect, mainScreenHeight h: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    /// The same flip the other way (it is its own inverse).
    static func axRect(fromAppKit r: CGRect, mainScreenHeight h: CGFloat) -> CGRect {
        appKitRect(fromAX: r, mainScreenHeight: h)
    }

    /// Zoom toggles: a window that already fills the usable screen goes back to its
    /// previous size. "Fills" allows a few points of slack, since apps round sizes.
    static func isFilling(_ window: CGRect, _ visible: CGRect, tolerance: CGFloat = 8) -> Bool {
        abs(window.minX - visible.minX) <= tolerance && abs(window.minY - visible.minY) <= tolerance
            && abs(window.width - visible.width) <= tolerance && abs(window.height - visible.height) <= tolerance
    }

    /// The row of window buttons: the first (close) is centred on the thumbnail's
    /// top-left corner and the rest follow along the top edge (AX coordinates).
    static func buttonStripRect(forThumbnail f: CGRect, size: CGFloat, gap: CGFloat, count: Int) -> CGRect {
        CGRect(x: f.minX - size / 2, y: f.minY - size / 2,
               width: CGFloat(count) * size + CGFloat(max(count - 1, 0)) * gap, height: size)
    }

    /// Which button in the strip `point` is on (0-based), or nil for a gap or outside.
    static func buttonIndex(at point: CGPoint, inStrip strip: CGRect, size: CGFloat, gap: CGFloat, count: Int) -> Int? {
        guard strip.contains(point) else { return nil }
        let x = point.x - strip.minX
        let i = Int(x / (size + gap))
        guard i >= 0, i < count, x - CGFloat(i) * (size + gap) <= size else { return nil }
        return i
    }
}

enum Version {
    /// "1.2.10" > "1.2.9"; a leading "v" is ignored; missing parts count as 0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            let trimmed = s.hasPrefix("v") ? String(s.dropFirst()) : s
            return trimmed.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

enum Shortcut {
    // CGEventFlags raw values, repeated here so this file needs no CoreGraphics.
    static let command: UInt64 = 0x0010_0000
    static let shift: UInt64   = 0x0002_0000
    static let control: UInt64 = 0x0004_0000
    static let option: UInt64  = 0x0008_0000

    // Virtual key codes (the key in that position on a US layout).
    static let keyW: Int64 = 13, keyM: Int64 = 46, keyF: Int64 = 3, keyH: Int64 = 4, keyQ: Int64 = 12

    /// The Mission Control shortcut for this key press, if any. Modifiers must match
    /// exactly, so ⇧⌘W, ⌥⌘W, ⌥⌘H and so on keep their usual meaning.
    static func action(keycode: Int64, flags: UInt64) -> WindowAction? {
        let mods = flags & (command | shift | control | option)
        switch (keycode, mods) {
        case (keyW, command): return .close
        case (keyM, command): return .minimize
        case (keyF, command | control): return .fullScreen
        case (keyF, command | option): return .zoom
        case (keyH, command): return .hideApp
        case (keyQ, command): return .quitApp
        default: return nil
        }
    }

    /// For menus and the welcome window.
    static let summary = "⌘W close · ⌘M minimize · ⌃⌘F full screen · ⌥⌘F zoom · ⌘H hide app · ⌘Q quit app"
}
