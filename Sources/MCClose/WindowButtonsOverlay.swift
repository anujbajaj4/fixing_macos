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

    override var isFlipped: Bool { true }   // same orientation as the AX coordinates

    override func draw(_ dirtyRect: NSRect) {
        let actions = WindowAction.buttons
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
        case .hideApp, .quitApp:
            break
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
/// track of the thumbnails (the keyboard shortcuts use them too).
final class WindowButtonsOverlay: NSObject {
    private var panels: [ScreenLayer] = []
    private var timer: Timer?
    private var thumbnails: [Thumbnail] = []        // the ones that get buttons
    private var rows: [[CGRect]] = []               // their buttons, AX coordinates
    private var previousFrames: [CGRect] = []
    private var thumbnailsRead = Date.distantPast
    private var shown = false
    private var loggedOnce = false
    /// Does a thumbnail (by app + title) have exactly one real, visible window behind it, and
    /// where are that window's own controls? Checked off the main thread; no buttons until yes.
    private var verdicts: [String: (ok: Bool, native: NativeControls?)] = [:]
    private var checking = false
    private var logged: Set<String> = []
    /// The button pressed in the event tap, waiting for `perform` on the main thread.
    private var armed: (action: WindowAction, thumbnail: Thumbnail)?

    /// Turned off from the menu if someone only wants the shortcuts.
    var showButtons: Bool {
        get { !UserDefaults.standard.bool(forKey: "HideCloseButton") }
        set {
            UserDefaults.standard.set(!newValue, forKey: "HideCloseButton")
            if !newValue { hidePanels(animated: false) }
        }
    }

    /// The chosen theme ("Match System" unless changed in the menu).
    var theme: ButtonTheme {
        get { ButtonTheme(rawValue: UserDefaults.standard.string(forKey: "ButtonTheme") ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "ButtonTheme"); applyTheme() }
    }

    func start() {
        timer?.invalidate()
        loggedOnce = false
        shown = false
        verdicts = [:]          // windows may have changed since last time
        logged = []
        previousFrames = []
        buildPanels()
        applyTheme()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        thumbnails = []
        rows = []
        previousFrames = []
        thumbnailsRead = .distantPast
        armed = nil
        hidePanels(animated: true)
    }

    /// Is the pointer on a window thumbnail? Decides whether a shortcut is ours.
    func isPointerOnThumbnail() -> Bool {
        guard timer != nil else { return false }
        if Date().timeIntervalSince(thumbnailsRead) > 0.5 { refreshThumbnails() }
        return WindowCloser.thumbnail(at: WindowCloser.mouseLocation(), in: thumbnails) != nil
    }

    /// The button at `point` (AX coordinates), if one is showing there. Called by the event
    /// tap on mouse-down; remembers which window it belongs to for `perform`.
    func button(at point: CGPoint, optionHeld: Bool) -> WindowAction? {
        guard timer != nil, shown, showButtons, let hit = ButtonLayout.hit(point, rows: rows),
              hit.thumbnail < thumbnails.count, hit.button < WindowAction.buttons.count else { return nil }
        var action = WindowAction.buttons[hit.button]
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
        verdicts[Self.key(armed.thumbnail)] = nil   // its size may have changed (zoom): measure again
        thumbnailsRead = .distantPast                // the layout changes after a close or minimize
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

    /// Reads Mission Control's thumbnails and keeps only real windows: big enough, not
    /// tucked inside another thumbnail, and matching exactly one window MC Close can act on.
    private func refreshThumbnails() {
        let all = WindowCloser.missionControlThumbnails()
        thumbnailsRead = Date()
        let sanity = ThumbnailSanity.check(all.map(\.frame))
        var keep: [Thumbnail] = []
        var unknown: [Thumbnail] = []
        for (t, verdict) in zip(all, sanity) {
            let k = Self.key(t)
            if verdict != .keep {
                logOnce(k + "\(verdict)", "overlay: no buttons for \(Log.title(t.title)) "
                    + "(\(verdict == .tooSmall ? "too small to be a window" : "inside another thumbnail"), "
                    + "\(Int(t.frame.width))x\(Int(t.frame.height)) at \(Int(t.frame.minX)),\(Int(t.frame.minY)))")
                continue
            }
            if let v = verdicts[k] {
                if v.ok { var t = t; t.native = v.native; keep.append(t) }
            } else {
                unknown.append(t)
            }
        }
        thumbnails = keep
        rows = keep.map { ButtonLayout.rects(forThumbnail: $0.frame, count: WindowAction.buttons.count, native: $0.native) }
        guard !unknown.isEmpty, !checking else { return }
        checking = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snap = WindowCloser.snapshot()
            let results: [(String, Thumbnail, Bool, NativeControls?)] = unknown.map { t in
                let window = WindowCloser.match(t, in: snap).window
                return (Self.key(t), t, window != nil, window.flatMap(WindowCloser.nativeControls))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                guard self.timer != nil else { return }   // Mission Control closed meanwhile
                for (k, t, ok, native) in results {
                    self.verdicts[k] = (ok, native)
                    if !ok {
                        self.logOnce(k + "nomatch", "overlay: no buttons for \(Log.title(t.title))"
                            + (t.appBundleID.map { " (\($0))" } ?? "") + ": no single visible window of a normal app has that title")
                    }
                }
                self.thumbnailsRead = .distantPast   // redraw with the answers
            }
        }
    }

    private func logOnce(_ key: String, _ line: String) {
        guard !logged.contains(key) else { return }
        logged.insert(key)
        Log.write(line)
    }

    private func update() {
        if Date().timeIntervalSince(thumbnailsRead) > 0.2 {
            refreshThumbnails()
            let frames = thumbnails.map(\.frame)
            // Mission Control animates its windows in; show the buttons once they've settled.
            let settled = !frames.isEmpty && frames == previousFrames
            previousFrames = frames
            if !loggedOnce && !frames.isEmpty {
                loggedOnce = true
                let measured = thumbnails.filter { $0.native != nil }.count
                Log.write("overlay: buttons on \(frames.count) window thumbnails (\(measured) placed over the window's own controls)")
            }
            if settled && !shown && showButtons { showPanels() }
            if frames.isEmpty && shown { hidePanels(animated: true) }
            for p in panels {
                let local = rows.map { $0.map { convert($0, to: p.screen) } }
                if p.view.rows != local { p.view.rows = local; p.view.needsDisplay = true }
            }
        }

        // Symbols appear while the pointer is over a window's buttons.
        let mouse = WindowCloser.mouseLocation()
        let hovered = rows.firstIndex { ButtonLayout.groupRect($0).contains(mouse) }
        let option = NSEvent.modifierFlags.contains(.option)
        for p in panels where p.view.hoveredGroup != hovered || p.view.optionHeld != option {
            p.view.hoveredGroup = hovered
            p.view.optionHeld = option
            p.view.needsDisplay = true
        }
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
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                p.panel.animator().alphaValue = 1
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
