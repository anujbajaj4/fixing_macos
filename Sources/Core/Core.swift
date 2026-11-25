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
        case ambiguous(Int)      // number of equally good candidates
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
        if exact.count > 1 { return .ambiguous(exact.count) }
        if loose.count == 1 { return .match(loose[0]) }
        if loose.count > 1 { return .ambiguous(loose.count) }
        return .none
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

    static func isWindowThumbnail(role: String, ancestorTitles: [String]) -> Bool {
        !excludedRoles.contains(role) && !ancestorTitles.contains("Spaces Bar")
    }
}

enum Geometry {
    /// Accessibility frames use a top-left origin on the main display; AppKit
    /// windows use a bottom-left origin. Convert an AX rect to an AppKit rect.
    static func appKitRect(fromAX r: CGRect, mainScreenHeight h: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    /// Where the ✕ goes: centred on the thumbnail's top-left corner (AX coordinates).
    static func closeButtonRect(forThumbnail f: CGRect, size: CGFloat) -> CGRect {
        CGRect(x: f.minX - size / 2, y: f.minY - size / 2, width: size, height: size)
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
    static let keycodeW: Int64 = 13   // kVK_ANSI_W (the key in the W position)

    /// True for ⌘W with no other modifier (so ⌥⌘W and ⇧⌘W keep their usual meaning).
    static func isCommandW(keycode: Int64, flags: UInt64) -> Bool {
        guard keycode == keycodeW else { return false }
        let mods = flags & (command | shift | control | option)
        return mods == command
    }
}
