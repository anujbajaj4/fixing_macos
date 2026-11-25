import Cocoa

/// Draws the row of window buttons: close, minimize, full screen, zoom.
/// Dark circles with white glyphs, like the controls macOS shows on a dimmed window.
private final class ButtonStripView: NSView {
    let size: CGFloat
    let gap: CGFloat
    var hovered: Int? { didSet { if hovered != oldValue { needsDisplay = true } } }
    var onClick: ((WindowAction) -> Void)?

    init(size: CGFloat, gap: CGFloat) {
        self.size = size
        self.gap = gap
        let count = CGFloat(WindowAction.buttons.count)
        super.init(frame: NSRect(x: 0, y: 0, width: count * size + (count - 1) * gap, height: size))
        setAccessibilityRole(.group)
        setAccessibilityLabel("Window buttons")
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Normally the event tap catches clicks first (Mission Control would take them);
    // this is a fallback for when clicks do reach the panel.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int(p.x / (size + gap))
        if i >= 0, i < WindowAction.buttons.count, p.x - CGFloat(i) * (size + gap) <= size {
            onClick?(WindowAction.buttons[i])
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, action) in WindowAction.buttons.enumerated() {
            let rect = NSRect(x: CGFloat(i) * (size + gap), y: 0, width: size, height: size).insetBy(dx: 1, dy: 1)
            let circle = NSBezierPath(ovalIn: rect)
            NSColor(white: hovered == i ? 0.42 : 0.22, alpha: 0.94).setFill()
            circle.fill()
            NSColor(white: 1, alpha: 0.28).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            drawGlyph(action, center: CGPoint(x: rect.midX, y: rect.midY), r: size * 0.2)
        }
    }

    private func drawGlyph(_ action: WindowAction, center c: CGPoint, r: CGFloat) {
        NSColor.white.set()
        let path = NSBezierPath()
        path.lineWidth = max(1.6, size / 11)
        path.lineCapStyle = .round
        switch action {
        case .close:
            path.move(to: CGPoint(x: c.x - r, y: c.y - r)); path.line(to: CGPoint(x: c.x + r, y: c.y + r))
            path.move(to: CGPoint(x: c.x - r, y: c.y + r)); path.line(to: CGPoint(x: c.x + r, y: c.y - r))
            path.stroke()
        case .minimize:
            path.move(to: CGPoint(x: c.x - r * 1.1, y: c.y)); path.line(to: CGPoint(x: c.x + r * 1.1, y: c.y))
            path.stroke()
        case .fullScreen:
            // Two triangles pointing to opposite corners, as on the green window button.
            let s = r * 1.05
            let a = NSBezierPath()
            a.move(to: CGPoint(x: c.x - s, y: c.y + s))
            a.line(to: CGPoint(x: c.x + s * 0.45, y: c.y + s))
            a.line(to: CGPoint(x: c.x - s, y: c.y - s * 0.45))
            a.close()
            a.move(to: CGPoint(x: c.x + s, y: c.y - s))
            a.line(to: CGPoint(x: c.x - s * 0.45, y: c.y - s))
            a.line(to: CGPoint(x: c.x + s, y: c.y + s * 0.45))
            a.close()
            a.fill()
        case .zoom:
            // The + that macOS shows on the green button while Option is held.
            path.move(to: CGPoint(x: c.x - r * 1.1, y: c.y)); path.line(to: CGPoint(x: c.x + r * 1.1, y: c.y))
            path.move(to: CGPoint(x: c.x, y: c.y - r * 1.1)); path.line(to: CGPoint(x: c.x, y: c.y + r * 1.1))
            path.stroke()
        case .hideApp, .quitApp:
            break
        }
    }
}

/// Floats close / minimize / full-screen / zoom buttons over the top-left corner of the
/// thumbnail under the pointer, and keeps track of which thumbnail that is (the
/// keyboard shortcuts use it too). Runs only while Mission Control is open.
final class WindowButtonsOverlay: NSObject {
    let size: CGFloat = 22
    let gap: CGFloat = 6
    private lazy var view = ButtonStripView(size: size, gap: gap)
    private lazy var panel: NSPanel = makePanel()
    private var timer: Timer?
    private(set) var current: Thumbnail?
    private var stripAX: CGRect = .zero   // where the buttons are, in AX (top-left) coordinates
    private var loggedOnce = false
    private var thumbnails: [Thumbnail] = []
    private var thumbnailsRead = Date.distantPast

    /// Turned off from the menu if someone only wants the shortcuts.
    var showButtons: Bool {
        get { !UserDefaults.standard.bool(forKey: "HideCloseButton") }
        set {
            UserDefaults.standard.set(!newValue, forKey: "HideCloseButton")
            if !newValue { panel.orderOut(nil) }
        }
    }

    func start() {
        timer?.invalidate()
        loggedOnce = false
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        current = nil
        stripAX = .zero
        thumbnails = []
        thumbnailsRead = .distantPast
        view.hovered = nil
        panel.orderOut(nil)
    }

    /// Is the pointer on a window thumbnail (or on our buttons)? Used to decide whether a
    /// shortcut is ours; refreshes the list first if it is stale.
    func isPointerOnThumbnail() -> Bool {
        guard timer != nil else { return false }
        let mouse = WindowCloser.mouseLocation()
        if stripAX.insetBy(dx: -4, dy: -4).contains(mouse) && current != nil { return true }
        if Date().timeIntervalSince(thumbnailsRead) > 0.5 { refreshThumbnails() }
        return WindowCloser.thumbnail(at: mouse, in: thumbnails) != nil
    }

    /// The button at `point` (AX coordinates), if the buttons are showing. Used by the event tap.
    func button(at point: CGPoint) -> WindowAction? {
        guard timer != nil, panel.isVisible, current != nil,
              let i = Geometry.buttonIndex(at: point, inStrip: stripAX, size: size, gap: gap,
                                           count: WindowAction.buttons.count) else { return nil }
        return WindowAction.buttons[i]
    }

    func perform(_ action: WindowAction) {
        guard let current else { return }
        if WindowCloser.perform(action, on: current, via: "button") {
            self.current = nil
            stripAX = .zero
            view.hovered = nil
            panel.orderOut(nil)
            thumbnailsRead = .distantPast   // the layout changes after a close or minimize
        }
    }

    private func refreshThumbnails() {
        thumbnails = WindowCloser.missionControlThumbnails()
        thumbnailsRead = Date()
    }

    private func update() {
        let mouse = WindowCloser.mouseLocation()

        // While the pointer is on our buttons, keep targeting the same thumbnail.
        if panel.isVisible && stripAX.insetBy(dx: -4, dy: -4).contains(mouse) {
            view.hovered = Geometry.buttonIndex(at: mouse, inStrip: stripAX, size: size, gap: gap,
                                                count: WindowAction.buttons.count)
            return
        }
        view.hovered = nil

        // Re-read the thumbnails 5 times a second (they move while Mission Control
        // animates, and after a window closes); hit-test against the cached list in between.
        if Date().timeIntervalSince(thumbnailsRead) > 0.2 { refreshThumbnails() }
        guard let thumb = WindowCloser.thumbnail(at: mouse, in: thumbnails) else {
            current = nil
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if !loggedOnce {
            loggedOnce = true
            Log.write("overlay: \(thumbnails.count) window thumbnails; pointer on \(Log.title(thumb.title))")
        }
        current = thumb
        guard showButtons else { return }
        place(onTopLeftOf: thumb.frame)
    }

    private func place(onTopLeftOf thumbFrame: CGRect) {
        let rect = Geometry.buttonStripRect(forThumbnail: thumbFrame, size: size, gap: gap,
                                            count: WindowAction.buttons.count)
        if rect == stripAX && panel.isVisible { return }
        stripAX = rect
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        panel.setFrame(Geometry.appKitRect(fromAX: rect, mainScreenHeight: mainHeight), display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        // Above Mission Control (checked in CI on macOS 15).
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        // .stationary keeps Mission Control from treating the panel as a window to shuffle.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        view.onClick = { [weak self] action in self?.perform(action) }
        panel.contentView = view
        return panel
    }
}
