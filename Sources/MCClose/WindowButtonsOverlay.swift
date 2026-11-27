import Cocoa

/// Colours of the window buttons for each theme, like macOS's own window controls.
enum ButtonPalette {
    struct Colors { let fill: NSColor; let rim: NSColor; let glyph: NSColor }

    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    static func graphite(dark: Bool) -> Colors {
        dark ? Colors(fill: hex(0x707075), rim: hex(0x5E5E63), glyph: hex(0x1C1C1E, 0.85))
             : Colors(fill: hex(0xC2C2C6), rim: hex(0xA8A8AD), glyph: hex(0x48484C, 0.9))
    }

    static func colors(_ action: WindowAction, theme: ButtonTheme, dark: Bool) -> Colors {
        if let t = theme.tint {
            let fill = hex(t)
            return Colors(fill: fill, rim: fill.blended(withFraction: 0.18, of: .black) ?? fill,
                          glyph: (fill.blended(withFraction: 0.62, of: .black) ?? .black).withAlphaComponent(0.85))
        }
        if theme == .graphite { return graphite(dark: dark) }
        switch action {   // Multicolor
        case .close:      return Colors(fill: hex(0xFF5F57), rim: hex(0xE0443E), glyph: hex(0x4D0000, 0.8))
        case .minimize:   return Colors(fill: hex(0xFEBC2E), rim: hex(0xDEA123), glyph: hex(0x995700, 0.85))
        case .fullScreen: return Colors(fill: hex(0x28C840), rim: hex(0x1AAB29), glyph: hex(0x006500, 0.85))
        default:          return graphite(dark: dark)   // Zoom, the fourth, is the neutral one
        }
    }
}

/// One transparent, click-through layer per screen. It draws each window's buttons over the
/// miniature of that window's own controls; clicks on them are caught by the event tap
/// (Mission Control would otherwise take them), every other click goes to Mission Control.
private final class ButtonsView: NSView {
    var rows: [[CGRect]] = []            // per thumbnail, in this view's coordinates
    var hoveredGroup: Int?               // row the pointer is over: its symbols show
    var pressed: (thumbnail: Int, button: Int)?
    var optionHeld = false
    var theme: ButtonTheme = .multicolor
    var dark = false
    var actions: [WindowAction] = WindowAction.buttons   // chosen in Settings ▸ Buttons

    override var isFlipped: Bool { true }   // same orientation as the AX coordinates

    override func draw(_ dirtyRect: NSRect) {
        for (t, row) in rows.enumerated() {
            let showSymbols = hoveredGroup == t
            for (b, rect) in row.enumerated() where b < actions.count {
                var symbol = actions[b]
                if symbol == .fullScreen && optionHeld && showSymbols { symbol = .zoom }   // Option-green
                drawButton(actions[b], symbol: symbol, in: rect, symbols: showSymbols,
                           pressed: pressed.map { $0.thumbnail == t && $0.button == b } ?? false)
            }
        }
    }

    private func drawButton(_ kind: WindowAction, symbol: WindowAction, in rect: CGRect, symbols: Bool, pressed: Bool) {
        let colors = ButtonPalette.colors(kind, theme: theme, dark: dark)
        let fill = pressed ? (colors.fill.blended(withFraction: 0.22, of: .black) ?? colors.fill) : colors.fill
        fill.setFill()
        NSBezierPath(ovalIn: rect).fill()
        colors.rim.setStroke()
        let rim = NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25))
        rim.lineWidth = 0.5
        rim.stroke()

        guard symbols else { return }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width * 0.24
        colors.glyph.set()
        let path = NSBezierPath()
        path.lineWidth = max(1, rect.width / 11)
        path.lineCapStyle = .round
        switch symbol {
        case .close:
            path.move(to: CGPoint(x: c.x - r, y: c.y - r)); path.line(to: CGPoint(x: c.x + r, y: c.y + r))
            path.move(to: CGPoint(x: c.x - r, y: c.y + r)); path.line(to: CGPoint(x: c.x + r, y: c.y - r))
            path.stroke()
        case .minimize:
            path.move(to: CGPoint(x: c.x - r * 1.2, y: c.y)); path.line(to: CGPoint(x: c.x + r * 1.2, y: c.y))
            path.stroke()
        case .fullScreen:
            // Two triangles pointing to opposite corners, as on the green window button.
            let s = r * 1.1
            let p = NSBezierPath()
            p.move(to: CGPoint(x: c.x - s, y: c.y - s))
            p.line(to: CGPoint(x: c.x + s * 0.5, y: c.y - s))
            p.line(to: CGPoint(x: c.x - s, y: c.y + s * 0.5))
            p.close()
            p.move(to: CGPoint(x: c.x + s, y: c.y + s))
            p.line(to: CGPoint(x: c.x - s * 0.5, y: c.y + s))
            p.line(to: CGPoint(x: c.x + s, y: c.y - s * 0.5))
            p.close()
            p.fill()
        case .zoom:
            path.move(to: CGPoint(x: c.x - r * 1.2, y: c.y)); path.line(to: CGPoint(x: c.x + r * 1.2, y: c.y))
            path.move(to: CGPoint(x: c.x, y: c.y - r * 1.2)); path.line(to: CGPoint(x: c.x, y: c.y + r * 1.2))
            path.stroke()
        case .hideApp:
            // An eye with a line through it.
            let eye = NSBezierPath()
            eye.lineWidth = path.lineWidth * 0.85
            eye.move(to: CGPoint(x: c.x - r * 1.3, y: c.y))
            eye.curve(to: CGPoint(x: c.x + r * 1.3, y: c.y), controlPoint1: CGPoint(x: c.x - r * 0.5, y: c.y - r * 1.1),
                      controlPoint2: CGPoint(x: c.x + r * 0.5, y: c.y - r * 1.1))
            eye.curve(to: CGPoint(x: c.x - r * 1.3, y: c.y), controlPoint1: CGPoint(x: c.x + r * 0.5, y: c.y + r * 1.1),
                      controlPoint2: CGPoint(x: c.x - r * 0.5, y: c.y + r * 1.1))
            eye.stroke()
            path.move(to: CGPoint(x: c.x - r * 1.1, y: c.y + r * 1.1)); path.line(to: CGPoint(x: c.x + r * 1.1, y: c.y - r * 1.1))
            path.stroke()
        case .quitApp:
            // A power symbol.
            let arc = NSBezierPath()
            arc.lineWidth = path.lineWidth
            arc.lineCapStyle = .round
            arc.appendArc(withCenter: c, radius: r * 1.1, startAngle: -60, endAngle: 240, clockwise: false)
            arc.stroke()
            path.move(to: CGPoint(x: c.x, y: c.y - r * 1.35)); path.line(to: CGPoint(x: c.x, y: c.y - r * 0.1))
            path.stroke()
        }
    }
}

private final class ScreenLayer {
    let panel: NSPanel
    let view: ButtonsView
    let screen: NSScreen
    init(panel: NSPanel, view: ButtonsView, screen: NSScreen) { self.panel = panel; self.view = view; self.screen = screen }
}

/// Shows window buttons on every window thumbnail while Mission Control is open, and keeps
/// track of the thumbnails (the keyboard shortcuts use them too). The buttons ride with the
/// windows: as Mission Control opens they travel from each window's real controls to its
/// thumbnail, and as it closes they travel back and fade. Mission Control is read on a
/// background queue, so the main thread (and the keyboard/mouse handling on it) stays free.
final class WindowButtonsOverlay: NSObject {
    private struct Verdict { var ok: Bool; var native: NativeControls?; var windowFrame: CGRect? }

    private var panels: [ScreenLayer] = []
    private var timer: Timer?
    private let reader = DispatchQueue(label: "MCClose.thumbnails", qos: .userInteractive)
    private var reading = false
    private var lastRead = Date.distantPast
    private var openedAt = Date.distantPast
    private var leaving: (start: Date, from: [[CGRect]], to: [[CGRect]])?

    private var thumbnails: [Thumbnail] = []        // the ones that get buttons
    private var targets: [[CGRect]] = []            // their rows on the thumbnails (AX coordinates)
    private var homes: [[CGRect]] = []              // the same rows on the real windows
    private var ridesIn: [Bool] = []                // seen at the start, so they travel in
    private var drawn: [[CGRect]] = []              // what's on screen now
    private var firstSeen: [String: Date] = [:]
    /// Does a thumbnail (by app + title) have exactly one real, visible window behind it, and
    /// where are that window and its own controls? Kept between visits so the buttons are
    /// ready at once, and checked again (off the main thread) on every visit.
    private var verdicts: [String: Verdict] = [:]
    private var rechecked: Set<String> = []
    private var checking = false
    private var shown = false
    private var loggedOnce = false
    private var logged: Set<String> = []
    /// The button pressed in the event tap, waiting for `perform` on the main thread.
    private var armed: (action: WindowAction, thumbnail: Thumbnail)?
    /// The buttons on each window, left to right (Settings ▸ Buttons).
    private var buttons: [WindowAction] = AppState.buttonConfig.visible

    /// Settings changed which buttons show, or their order.
    func reloadButtons() {
        buttons = AppState.buttonConfig.visible
        for p in panels { p.view.actions = buttons; p.view.needsDisplay = true }
        lastRead = .distantPast
    }

    /// No riding in and out: turned off in Settings, or macOS's Reduce motion is on.
    private var reduceMotion: Bool {
        !AppState.moveWithWindows || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Turned off in Settings if someone only wants the shortcuts.
    var showButtons: Bool {
        get { !UserDefaults.standard.bool(forKey: "HideCloseButton") }
        set {
            UserDefaults.standard.set(!newValue, forKey: "HideCloseButton")
            if !newValue { hidePanels(animated: false) }
        }
    }

    /// The chosen theme ("Match System" unless changed in Settings).
    var theme: ButtonTheme {
        get { ButtonTheme(rawValue: UserDefaults.standard.string(forKey: "ButtonTheme") ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "ButtonTheme"); applyTheme() }
    }

    /// Mission Control opened.
    func start() {
        timer?.invalidate()
        openedAt = Date()
        leaving = nil
        loggedOnce = false
        logged = []
        rechecked = []
        firstSeen = [:]
        thumbnails = []; targets = []; homes = []; ridesIn = []; drawn = []
        lastRead = .distantPast
        shown = false
        buildPanels()
        applyTheme()
        reloadButtons()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Mission Control closed: the buttons ride back onto the real windows and fade.
    func leave() {
        guard timer != nil, leaving == nil else { return }
        armed = nil
        if reduceMotion || !shown || drawn.isEmpty { stop(); return }
        leaving = (Date(), drawn, homes.count == drawn.count ? homes : drawn)
        for p in panels { p.view.hoveredGroup = nil; p.view.pressed = nil }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        leaving = nil
        thumbnails = []; targets = []; homes = []; ridesIn = []; drawn = []
        armed = nil
        hidePanels(animated: !reduceMotion)
    }

    /// Is the pointer on a window thumbnail? Decides whether a shortcut is ours. Uses the
    /// list read in the background (at most a fifth of a second old).
    func isPointerOnThumbnail() -> Bool {
        guard timer != nil, leaving == nil else { return false }
        return WindowCloser.thumbnail(at: WindowCloser.mouseLocation(), in: thumbnails) != nil
    }

    /// The button at `point` (AX coordinates), if one is showing there. Called by the event
    /// tap on mouse-down; remembers which window it belongs to for `perform`.
    func button(at point: CGPoint, optionHeld: Bool) -> WindowAction? {
        guard timer != nil, leaving == nil, shown, showButtons, let hit = ButtonLayout.hit(point, rows: targets),
              hit.thumbnail < thumbnails.count, hit.button < buttons.count else { return nil }
        var action = buttons[hit.button]
        if action == .fullScreen && optionHeld { action = .zoom }   // Option-click green, as on a window
        armed = (action, thumbnails[hit.thumbnail])
        for p in panels { p.view.pressed = hit; p.view.needsDisplay = true }
        return action
    }

    func perform(_ action: WindowAction) {
        guard let armed, armed.action == action else { return }
        self.armed = nil
        for p in panels { p.view.pressed = nil; p.view.needsDisplay = true }
        WindowCloser.perform(action, on: armed.thumbnail, via: "button")
        rechecked.remove(Self.key(armed.thumbnail))   // its size may have changed (zoom): measure again
        lastRead = .distantPast                         // the layout changes after a close or minimize
    }

    // MARK: - Internals

    private func applyTheme() {
        let systemAccent = UserDefaults.standard.object(forKey: "AppleAccentColor") as? Int
        let resolved = theme.resolved(systemAccent: systemAccent)
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for p in panels {
            p.view.theme = resolved
            p.view.dark = dark
            p.view.needsDisplay = true
        }
    }

    private static func key(_ t: Thumbnail) -> String { (t.appBundleID ?? "") + "\u{1}" + t.title }

    private func update() {
        let now = Date()

        if let l = leaving {
            let p = now.timeIntervalSince(l.start) / Motion.duration
            if p >= 1 { stop(); return }
            drawn = zip(l.from, l.to).map { Motion.row(from: $0, to: $1, progress: p) }
            push(drawn)
            let fade = max(0, (p - 0.45) / 0.55)            // fade out over the second half
            for layer in panels { layer.panel.alphaValue = CGFloat(1 - fade) }
            return
        }

        // Read Mission Control in the background: often while it animates in, then 5 times a second.
        let interval = now.timeIntervalSince(openedAt) < 0.8 ? 1.0 / 30 : 0.2
        if !reading && now.timeIntervalSince(lastRead) > interval {
            reading = true
            reader.async { [weak self] in
                let all = WindowCloser.missionControlThumbnails()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.reading = false
                    self.lastRead = Date()
                    if self.timer != nil && self.leaving == nil { self.apply(all) }
                }
            }
        }

        // Rows seen at the start ride in from the real windows; later ones just appear.
        let progress = now.timeIntervalSince(openedAt) / Motion.duration
        drawn = targets.indices.map { i in
            guard !reduceMotion, progress < 1, ridesIn[i], i < homes.count else { return targets[i] }
            return Motion.row(from: homes[i], to: targets[i], progress: progress)
        }
        push(drawn)
        if !shown && !drawn.isEmpty && showButtons { showPanels() }
        if shown && drawn.isEmpty { hidePanels(animated: true) }

        // Symbols appear while the pointer is over a window's buttons.
        let mouse = WindowCloser.mouseLocation()
        let hovered = targets.firstIndex { ButtonLayout.groupRect($0).contains(mouse) }
        let option = NSEvent.modifierFlags.contains(.option)
        for p in panels where p.view.hoveredGroup != hovered || p.view.optionHeld != option {
            p.view.hoveredGroup = hovered
            p.view.optionHeld = option
            p.view.needsDisplay = true
        }
    }

    private func push(_ rows: [[CGRect]]) {
        for p in panels {
            let local = rows.map { $0.map { convert($0, to: p.screen) } }
            if p.view.rows != local { p.view.rows = local; p.view.needsDisplay = true }
        }
    }

    /// Keeps only real windows: big enough, not tucked inside another thumbnail, and matching
    /// exactly one window MC Close can act on.
    private func apply(_ all: [Thumbnail]) {
        let now = Date()
        let sanity = ThumbnailSanity.check(all.map(\.frame))
        var keep: [Thumbnail] = []
        var toCheck: [Thumbnail] = []
        for (t, verdict) in zip(all, sanity) {
            let k = Self.key(t)
            if verdict != .keep {
                logOnce(k + "\(verdict)", "overlay: no buttons for \(Log.title(t.title)) "
                    + "(\(verdict == .tooSmall ? "too small to be a window" : "inside another thumbnail"), "
                    + "\(Int(t.frame.width))x\(Int(t.frame.height)) at \(Int(t.frame.minX)),\(Int(t.frame.minY)))")
                continue
            }
            if !rechecked.contains(k) { toCheck.append(t) }
            if let v = verdicts[k], v.ok {
                var t = t
                t.native = v.native
                keep.append(t)
            }
        }
        let count = buttons.count
        thumbnails = keep
        targets = keep.map { ButtonLayout.rects(forThumbnail: $0.frame, count: count, native: $0.native) }
        homes = keep.map { t in
            let frame = verdicts[Self.key(t)]?.windowFrame ?? t.frame
            return ButtonLayout.rects(forThumbnail: frame, count: count, native: t.native)
        }
        ridesIn = keep.map { t in
            let seen = firstSeen[Self.key(t)] ?? now
            firstSeen[Self.key(t)] = seen
            return seen.timeIntervalSince(openedAt) < 0.15
        }
        if !loggedOnce && !keep.isEmpty {
            loggedOnce = true
            Log.write("overlay: buttons on \(keep.count) window thumbnails "
                      + "(\(keep.filter { $0.native != nil }.count) placed over the window's own controls)")
        }
        verify(toCheck)
    }

    /// Checks thumbnails against the real windows, off the main thread.
    private func verify(_ list: [Thumbnail]) {
        guard !list.isEmpty, !checking else { return }
        checking = true
        reader.async { [weak self] in
            let snap = WindowCloser.snapshot()
            let results: [(String, Verdict, String)] = list.map { t in
                var lines: [String] = []
                var window = WindowCloser.match(t, in: snap, trace: { lines.append($0) }).window
                // Only windows with a close button of their own get buttons: floating video
                // tiles, panels and overlays have nothing for MC Close to press.
                if let w = window, AX.element(w, kAXCloseButtonAttribute) == nil {
                    lines.append("window has no close button")
                    window = nil
                }
                let frame = window.flatMap { AX.frame($0) }
                // If its controls can't be measured, assume macOS's standard ones, scaled like
                // every other window's, rather than a full-size row.
                let native = window.flatMap(WindowCloser.nativeControls)
                    ?? frame.map { NativeControls.standard(windowSize: $0.size) }
                // One line per window per visit, so a glitch can be explained (titles stay hidden).
                var detail = "thumbnail \(Int(t.frame.width))x\(Int(t.frame.height)) at \(Int(t.frame.minX)),\(Int(t.frame.minY))"
                    + (t.appBundleID.map { " (\($0))" } ?? "") + "; " + lines.joined(separator: "; ")
                if let f = frame { detail += "; window \(Int(f.width))x\(Int(f.height))" }
                if let n = native {
                    detail += "; controls at \(Int(n.closeCenter.x)),\(Int(n.closeCenter.y)) size \(Int(n.diameter))"
                }
                detail += window == nil ? "; no buttons" : "; buttons on"
                return (Self.key(t), Verdict(ok: window != nil, native: native, windowFrame: frame), detail)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                for (k, v, detail) in results {
                    self.verdicts[k] = v
                    self.rechecked.insert(k)
                    self.logOnce(k + "check", "overlay check: " + detail)
                }
                self.lastRead = .distantPast   // redraw with the answers
            }
        }
    }

    private func logOnce(_ key: String, _ line: String) {
        guard !logged.contains(key) else { return }
        logged.insert(key)
        Log.write(line)
    }

    /// AX (global, top-left origin) to a screen's view (top-left origin).
    private func convert(_ r: CGRect, to screen: NSScreen) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let screenTopAX = mainHeight - screen.frame.maxY
        return CGRect(x: r.minX - screen.frame.minX, y: r.minY - screenTopAX, width: r.width, height: r.height)
    }

    private func buildPanels() {
        for p in panels { p.panel.orderOut(nil) }
        panels = NSScreen.screens.map { screen in
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            // Above Mission Control (checked in CI on macOS 15).
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true      // clicks go to Mission Control; ours are caught by the tap
            panel.hidesOnDeactivate = false
            panel.alphaValue = 0
            let view = ButtonsView(frame: NSRect(origin: .zero, size: screen.frame.size))
            panel.contentView = view
            panel.setFrame(screen.frame, display: false)
            return ScreenLayer(panel: panel, view: view, screen: screen)
        }
    }

    private func showPanels() {
        shown = true
        for p in panels {
            p.panel.orderFrontRegardless()
            if reduceMotion {
                p.panel.alphaValue = 1
            } else {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    p.panel.animator().alphaValue = 1
                }
            }
        }
    }

    private func hidePanels(animated: Bool) {
        shown = false
        for p in panels {
            if animated {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.12
                    p.panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    if self?.shown != true { p.panel.orderOut(nil) }
                })
            } else {
                p.panel.alphaValue = 0
                p.panel.orderOut(nil)
            }
        }
    }
}
