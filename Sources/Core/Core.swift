import Foundation
import CoreGraphics

// Pure logic with no AppKit or Accessibility calls, so it can be unit-tested
// on its own (see Tests/main.swift).

/// A real window as seen through the Accessibility API, reduced to what matching needs.
struct WindowCandidate: Equatable {
    let title: String      // the window's AXTitle ("" if it has none)
    let appName: String    // the owning app's localized name
    let minimized: Bool    // minimized windows aren't shown in Mission Control
    var size: CGSize? = nil
}

enum WindowMatcher {
    enum Outcome: Equatable {
        case match(Int)          // index into the candidates
        case none
        case ambiguous([Int])    // the equally good candidates
    }

    /// Titles compared loosely: case, spacing and an "— Edited" ending don't matter.
    static func normalize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["— Edited", "– Edited", "- Edited"] where t.lowercased().hasSuffix(suffix.lowercased()) {
            t = String(t.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Mission Control shrinks windows without changing their proportions.
    static func sameShape(_ a: CGSize, _ b: CGSize, tolerance: CGFloat = 0.03) -> Bool {
        guard a.width > 0, a.height > 0, b.width > 0, b.height > 0 else { return false }
        let ra = a.width / a.height, rb = b.width / b.height
        return abs(ra - rb) / rb <= tolerance
    }

    /// Pick the real window behind a Mission Control thumbnail.
    ///
    /// 1. Same title (compared loosely) wins, if exactly one window has it.
    /// 2. Otherwise a "loose" match: one title contains the other, or the window has no
    ///    title and the thumbnail shows the app's name.
    /// 3. When several fit equally well, the one with the thumbnail's shape wins.
    /// 4. With `shapeAlone` (the candidates are already one app's windows, as on macOS 27),
    ///    a window can be picked by shape alone when no title fits.
    /// Anything still ambiguous is refused: closing the wrong window is worse than closing nothing.
    static func pick(thumbnailTitle: String, thumbnailSize: CGSize? = nil, shapeAlone: Bool = false,
                     from candidates: [WindowCandidate]) -> Outcome {
        let thumb = normalize(thumbnailTitle)
        var exact: [Int] = []
        var loose: [Int] = []
        for (i, c) in candidates.enumerated() where !c.minimized && !thumb.isEmpty {
            let title = normalize(c.title)
            if !title.isEmpty && title == thumb {
                exact.append(i)
            } else if (title.count >= 3 && (thumb.contains(title) || title.contains(thumb)))
                        || (title.isEmpty && !c.appName.isEmpty && thumb == normalize(c.appName)) {
                loose.append(i)
            }
        }
        func shaped(_ list: [Int]) -> [Int] {
            guard let ts = thumbnailSize else { return [] }
            return list.filter { candidates[$0].size.map { sameShape($0, ts) } ?? false }
        }
        func decide(_ list: [Int]) -> Outcome? {
            if list.count == 1 { return .match(list[0]) }
            guard list.count > 1 else { return nil }
            let s = shaped(list)
            return s.count == 1 ? .match(s[0]) : .ambiguous(list)
        }
        /// Among loose matches: a title that is only the app's name never wins a tie (a helper
        /// window called "Preview" next to a document), and a title contained in another
        /// candidate's title loses to it ("Report" loses to "Report draft"). Titles that
        /// merely differ in length stay a tie, so MC Close still refuses to guess.
        func mostSpecific(_ list: [Int]) -> [Int] {
            guard list.count > 1 else { return list }
            let named = list.filter { normalize(candidates[$0].title) != normalize(candidates[$0].appName) }
            let pool = named.isEmpty ? list : named
            let titles = pool.map { normalize(candidates[$0].title) }
            return pool.indices.filter { i in
                !titles.indices.contains { j in j != i && titles[j] != titles[i] && titles[j].contains(titles[i]) }
            }.map { pool[$0] }
        }
        /// A match whose shape clearly disagrees with the thumbnail is probably the wrong window.
        func checked(_ o: Outcome) -> Outcome {
            guard case .match(let i) = o, let ts = thumbnailSize, let ws = candidates[i].size else { return o }
            return sameShape(ws, ts, tolerance: 0.1) ? o : .none
        }
        if let o = decide(exact) { return checked(o) }
        if let o = decide(mostSpecific(loose)) { return checked(o) }
        if shapeAlone {
            let s = shaped(candidates.indices.filter { !candidates[$0].minimized })
            if s.count == 1 { return .match(s[0]) }
            if s.count > 1 { return .ambiguous(s) }
        }
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

/// Which buttons appear on each window, and in what order (Settings ▸ Buttons).
/// Stored as a list like ["close", "minimize", "-hideApp", …]: "-" means hidden.
struct ButtonConfig: Equatable {
    struct Item: Equatable { var action: WindowAction; var shown: Bool }
    var items: [Item]

    static let standard = ButtonConfig(items: WindowAction.allCases.map {
        Item(action: $0, shown: WindowAction.buttons.contains($0))
    })

    /// The buttons drawn on each window, left to right.
    var visible: [WindowAction] { items.filter(\.shown).map(\.action) }

    var serialized: [String] { items.map { ($0.shown ? "" : "-") + $0.action.rawValue } }

    /// Reads a stored list; unknown or repeated entries are skipped, and actions missing from
    /// it (e.g. added in a later version) are appended, hidden.
    init(serialized list: [String]?) {
        guard let list, !list.isEmpty else { self = .standard; return }
        var items: [Item] = []
        for entry in list {
            let hidden = entry.hasPrefix("-")
            guard let a = WindowAction(rawValue: hidden ? String(entry.dropFirst()) : entry),
                  !items.contains(where: { $0.action == a }) else { continue }
            items.append(Item(action: a, shown: !hidden))
        }
        for a in WindowAction.allCases where !items.contains(where: { $0.action == a }) {
            items.append(Item(action: a, shown: false))
        }
        self.items = items
    }

    init(items: [Item]) { self.items = items }

    mutating func move(from source: Int, to destination: Int) {
        guard items.indices.contains(source) else { return }
        let item = items.remove(at: source)
        items.insert(item, at: min(max(destination, 0), items.count))
    }

    mutating func setShown(_ action: WindowAction, _ shown: Bool) {
        if let i = items.firstIndex(where: { $0.action == action }) { items[i].shown = shown }
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

    /// "com.apple.TextEdit.space.3" → 3: the Space the window is on (SkyLight's ManagedSpaceID).
    static func spaceID(fromThumbnailIdentifier id: String) -> Int? {
        guard bundleID(fromThumbnailIdentifier: id) != nil,
              let r = id.range(of: ".space.", options: .backwards) else { return nil }
        return Int(id[r.upperBound...])
    }

    /// The thumbnail's attribute holding its window's CGWindowID (seen on 27.2.1).
    static let windowIDAttribute = "wid"
}

/// Which thumbnails Mission Control is actually showing. Measured on macOS 27.2.1:
/// WindowManager's tree holds the layouts of every Space at once, on top of each other, and
/// each thumbnail carries its window's CGWindowID. While Mission Control is open, the windows
/// of the Space it's showing are exactly the ones CGWindowList reports on screen. (From a
/// full-screen app it shows the desktop behind it, so the active Space is no guide.)
enum ShownTiles {
    /// For each thumbnail, is it on screen? One without a window ID (macOS 15's Dock, which
    /// only lists what it shows) always is.
    static func shown(windowIDs: [UInt32?], onscreen: Set<UInt32>) -> [Bool] {
        windowIDs.map { id in id.map(onscreen.contains) ?? true }
    }

    /// The index of the window with `id` among `windowIDs` (nil entries: ID unknown).
    static func index(of id: UInt32, in windowIDs: [UInt32?]) -> Int? {
        windowIDs.firstIndex { $0 == id }
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

/// macOS 27's Mission Control also lists things that aren't drawn as windows (invisible
/// helper windows, placeholders behind real windows). Before drawing buttons, drop the
/// ones that are too small to be a thumbnail, or that sit inside a bigger thumbnail.
enum ThumbnailSanity {
    static let minWidth: CGFloat = 60, minHeight: CGFloat = 40

    enum Verdict: Equatable { case keep, tooSmall, insideAnother }

    /// `identified[i]`: the thumbnail names its window (macOS 27's window ID), so it's a real
    /// window whatever it overlaps: only the size check applies to it.
    static func check(_ frames: [CGRect], identified: [Bool] = []) -> [Verdict] {
        frames.enumerated().map { i, f in
            if f.width < minWidth || f.height < minHeight { return .tooSmall }
            if i < identified.count && identified[i] { return .keep }
            let area = f.width * f.height
            let inside = frames.enumerated().contains { j, g in
                guard j != i, g.width * g.height > area else { return false }
                let overlap = f.intersection(g)
                return !overlap.isNull && overlap.width * overlap.height >= area * 0.8
            }
            return inside ? .insideAnother : .keep
        }
    }
}

/// Where a window's own controls are, measured on the real window (from its AX close and
/// minimize buttons), so ours can be drawn exactly over their miniature in the thumbnail.
struct NativeControls: Equatable {
    var closeCenter: CGPoint   // from the window's top-left corner
    var diameter: CGFloat      // of one control
    var spacing: CGFloat       // centre to centre
    var windowSize: CGSize

    /// macOS's usual window controls, for a window whose own couldn't be measured, so its
    /// buttons are scaled like every other window's instead of drawn full size.
    static func standard(windowSize: CGSize) -> NativeControls {
        NativeControls(closeCenter: CGPoint(x: 20, y: 18), diameter: 13, spacing: 20, windowSize: windowSize)
    }
}

/// Where the buttons sit on each thumbnail. With the window's own controls measured, they
/// sit exactly on top of the thumbnail's miniature controls, at the same scale, with Zoom
/// as a fourth control after green. Without a measurement, a row like macOS's own goes
/// inside the top-left corner. All in AX coordinates (top-left origin).
enum ButtonLayout {
    static let diameter: CGFloat = 13     // default, when the window's controls weren't measured
    static let gap: CGFloat = 7
    static let inset: CGFloat = 8
    static let minDiameter: CGFloat = 9   // smaller than this is too fiddly to click
    static let slop: CGFloat = 3          // extra hit area around each circle

    /// 1 normally; less on thumbnails too narrow for a full-size default row.
    static func scale(forThumbnail f: CGRect, count: Int) -> CGFloat {
        let needed = inset * 2 + CGFloat(count) * diameter + CGFloat(max(count - 1, 0)) * gap
        return min(1, max(0.5, f.width / needed))
    }

    static func rects(forThumbnail f: CGRect, count: Int, native: NativeControls? = nil) -> [CGRect] {
        if let n = native, n.windowSize.width > 0, n.diameter > 0 {
            let s = f.width / n.windowSize.width                     // Mission Control keeps the aspect ratio
            let d = max(n.diameter * s, minDiameter)
            let spacing = max(n.spacing * s, d + 1.5)
            let first = CGPoint(x: f.minX + n.closeCenter.x * s, y: f.minY + n.closeCenter.y * s)
            // Only trust the measurement if it lands in the thumbnail's top-left corner, where a
            // window's controls are; anything else means a bad measurement: use the default row.
            if first.x - f.minX <= f.width * 0.4, first.y - f.minY <= f.height * 0.25,
               first.x >= f.minX, first.y >= f.minY {
                return (0..<count).map { i in
                    CGRect(x: first.x + CGFloat(i) * spacing - d / 2, y: first.y - d / 2, width: d, height: d)
                }
            }
        }
        let k = scale(forThumbnail: f, count: count)
        return (0..<count).map { i in
            CGRect(x: f.minX + inset * k + CGFloat(i) * (diameter + gap) * k, y: f.minY + inset * k,
                   width: diameter * k, height: diameter * k)
        }
    }

    /// The whole row, with slop: hovering it shows the symbols, like on a real window.
    static func groupRect(_ row: [CGRect]) -> CGRect {
        guard let first = row.first, let last = row.last else { return .zero }
        return first.union(last).insetBy(dx: -slop - 2, dy: -slop - 2)
    }

    /// Which button of which row is at `p`, if any.
    static func hit(_ p: CGPoint, rows: [[CGRect]]) -> (thumbnail: Int, button: Int)? {
        for (t, row) in rows.enumerated() {
            for (b, r) in row.enumerated() where r.insetBy(dx: -slop, dy: -slop).contains(p) {
                return (t, b)
            }
        }
        return nil
    }
}

/// Moving the buttons with the windows as Mission Control opens and closes: they start on
/// each window's real controls and ride to its thumbnail (and back on the way out).
enum Motion {
    static let duration: Double = 0.32     // about as long as Mission Control's own animation

    /// Fast start, gentle stop, like macOS's own motion.
    static func easeOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return 1 - pow(1 - x, 3)
    }

    static func lerp(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        let k = CGFloat(t)
        return CGRect(x: a.minX + (b.minX - a.minX) * k, y: a.minY + (b.minY - a.minY) * k,
                      width: a.width + (b.width - a.width) * k, height: a.height + (b.height - a.height) * k)
    }

    /// One row of buttons part-way between where it starts and where it ends.
    static func row(from a: [CGRect], to b: [CGRect], progress t: Double) -> [CGRect] {
        guard a.count == b.count else { return b }
        let e = easeOut(t)
        return zip(a, b).map { lerp($0, $1, e) }
    }
}

/// The colours of the window buttons, mirroring macOS's accent colour choices
/// (System Settings ▸ Appearance). With the Graphite accent, macOS draws window controls
/// grey; with any other accent they stay red, yellow and green.
enum ButtonTheme: String, CaseIterable {
    case system, multicolor, graphite, blue, purple, pink, red, orange, yellow, green

    var label: String {
        switch self {
        case .system: return "Match System"
        case .multicolor: return "Multicolor"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// macOS's accent colours (one tint for every button).
    var tint: UInt32? {
        switch self {
        case .blue: return 0x007AFF
        case .purple: return 0xAF52DE
        case .pink: return 0xFF2D55
        case .red: return 0xFF3B30
        case .orange: return 0xFF9500
        case .yellow: return 0xFFCC00
        case .green: return 0x28CD41
        default: return nil
        }
    }

    /// "Match System": the global AppleAccentColor setting is -1 for Graphite; anything
    /// else (or not set, which is Multicolor) keeps the usual red, yellow and green.
    func resolved(systemAccent: Int?) -> ButtonTheme {
        guard self == .system else { return self }
        return systemAccent == -1 ? .graphite : .multicolor
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

    /// The keys for an action, as shown in Settings.
    static func keys(for action: WindowAction) -> String {
        switch action {
        case .close: return "⌘W"
        case .minimize: return "⌘M"
        case .fullScreen: return "⌃⌘F"
        case .zoom: return "⌥⌘F"
        case .hideApp: return "⌘H"
        case .quitApp: return "⌘Q"
        }
    }

    /// For menus and the welcome window.
    static let summary = "⌘W close · ⌘M minimize · ⌃⌘F full screen · ⌥⌘F zoom · ⌘H hide app · ⌘Q quit app"
}
