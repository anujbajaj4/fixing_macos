import Cocoa

/// The look of macOS's own window controls (red, yellow, green), plus a graphite fourth
/// button for Zoom. Symbols appear only while the pointer is over a window's buttons,
/// as on a real window; holding Option turns the green button into +.
private enum Style {
    struct Colors { let fill: NSColor; let rim: NSColor; let glyph: NSColor }
    static func colors(_ action: WindowAction) -> Colors {
        func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: a)
        }
        switch action {
        case .close:      return Colors(fill: c(0xFF5F57), rim: c(0xE0443E), glyph: c(0x4D0000, 0.8))
        case .minimize:   return Colors(fill: c(0xFEBC2E), rim: c(0xDEA123), glyph: c(0x995700, 0.85))
        case .fullScreen: return Colors(fill: c(0x28C840), rim: c(0x1AAB29), glyph: c(0x006500, 0.85))
        case .zoom:       return Colors(fill: c(0xA5A5AA), rim: c(0x8A8A8F), glyph: c(0x2C2C2E, 0.85))
        case .hideApp, .quitApp: return Colors(fill: .clear, rim: .clear, glyph: .clear)
        }
    }
}

/// One transparent, click-through layer per screen. It draws a row of buttons on every
/// window thumbnail; clicks on them are caught by the event tap (Mission Control would
/// otherwise take them), every other click goes to Mission Control as usual.
private final class ButtonsView: NSView {
    var thumbnails: [CGRect] = []        // in this view's coordinates (top-left origin)
    var hoveredGroup: Int?               // thumbnail whose buttons the pointer is over
    var pressed: (thumbnail: Int, button: Int)?
    var optionHeld = false

    override var isFlipped: Bool { true }   // same orientation as the AX coordinates

    override func draw(_ dirtyRect: NSRect) {
        let actions = WindowAction.buttons
        for (t, frame) in thumbnails.enumerated() {
            let showSymbols = hoveredGroup == t
            for (b, rect) in ButtonLayout.rects(forThumbnail: frame, count: actions.count).enumerated() {
                var action = actions[b]
                if action == .fullScreen && optionHeld && showSymbols { action = .zoom }   // Option-green
                drawButton(actions[b], symbol: action, in: rect, symbols: showSymbols,
                           pressed: pressed.map { $0.thumbnail == t && $0.button == b } ?? false)
            }
        }
    }

    private func drawButton(_ kind: WindowAction, symbol: WindowAction, in rect: CGRect, symbols: Bool, pressed: Bool) {
        let colors = Style.colors(kind)
        let circle = NSBezierPath(ovalIn: rect)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 2.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        (pressed ? colors.fill.blended(withFraction: 0.25, of: .black) ?? colors.fill : colors.fill).setFill()
        circle.fill()
        NSGraphicsContext.restoreGraphicsState()

        colors.rim.setStroke()
        let rim = NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25))
        rim.lineWidth = 0.5
        rim.stroke()

        guard symbols else { return }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width * 0.24
        colors.glyph.set()
        let path = NSBezierPath()
        path.lineWidth = max(1.1, rect.width / 11)
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

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// One screen's layer: frosted pills (the macOS HUD material) under the buttons.
private final class ScreenLayer {
    let panel: NSPanel
    let container = FlippedView()
    let view: ButtonsView
    let screen: NSScreen
    var pills: [NSVisualEffectView] = []

    init(panel: NSPanel, view: ButtonsView, screen: NSScreen) {
        self.panel = panel
        self.view = view
        self.screen = screen
    }

    /// One pill per thumbnail, behind its buttons; hides the thumbnail's own tiny controls.
    func layoutPills(_ thumbnails: [CGRect]) {
        while pills.count < thumbnails.count {
            let pill = NSVisualEffectView()
            pill.material = .hudWindow
            pill.blendingMode = .behindWindow
            pill.state = .active
            pill.wantsLayer = true
            pill.layer?.masksToBounds = true
            pill.layer?.borderWidth = 0.5
            pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
            container.addSubview(pill, positioned: .below, relativeTo: view)
            pills.append(pill)
        }
        while pills.count > thumbnails.count { pills.removeLast().removeFromSuperview() }
        for (pill, f) in zip(pills, thumbnails) {
            let r = ButtonLayout.pillRect(forThumbnail: f, count: WindowAction.buttons.count)
            pill.frame = r
            pill.layer?.cornerRadius = r.height / 2
        }
    }
}

/// Shows window buttons on every thumbnail while Mission Control is open, and keeps
/// track of the thumbnails (the keyboard shortcuts use them too).
final class WindowButtonsOverlay: NSObject {
    private var panels: [ScreenLayer] = []
    private var timer: Timer?
    private var thumbnails: [Thumbnail] = []
    private var previousFrames: [CGRect] = []
    private var thumbnailsRead = Date.distantPast
    private var shown = false
    private var loggedOnce = false
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

    func start() {
        timer?.invalidate()
        loggedOnce = false
        shown = false
        previousFrames = []
        buildPanels()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        thumbnails = []
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
        guard timer != nil, shown, showButtons,
              let hit = ButtonLayout.hit(point, thumbnails: thumbnails.map(\.frame),
                                         count: WindowAction.buttons.count) else { return nil }
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
        thumbnailsRead = .distantPast   // the layout changes after a close or minimize
    }

    // MARK: - Internals

    private func refreshThumbnails() {
        thumbnails = WindowCloser.missionControlThumbnails()
        thumbnailsRead = Date()
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
                Log.write("overlay: \(frames.count) window thumbnails")
            }
            if settled && !shown && showButtons { showPanels() }
            if frames.isEmpty && shown { hidePanels(animated: true) }
            for p in panels {
                let local = frames.map { convert($0, to: p.screen) }
                if p.view.thumbnails != local {
                    p.view.thumbnails = local
                    p.layoutPills(local)
                    p.view.needsDisplay = true
                }
            }
        }

        // Symbols appear while the pointer is over a window's buttons.
        let mouse = WindowCloser.mouseLocation()
        let hovered = thumbnails.firstIndex {
            ButtonLayout.groupRect(forThumbnail: $0.frame, count: WindowAction.buttons.count).contains(mouse)
        }
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
            let size = NSRect(origin: .zero, size: screen.frame.size)
            let view = ButtonsView(frame: size)
            let layer = ScreenLayer(panel: panel, view: view, screen: screen)
            layer.container.frame = size
            layer.container.addSubview(view)
            panel.contentView = layer.container
            panel.setFrame(screen.frame, display: false)
            return layer
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
