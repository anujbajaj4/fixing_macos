import Cocoa

/// A button that reacts to the first click even though MC Close is never the active app.
private final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Floats a small ✕ button over the top-left corner of the thumbnail under the pointer.
/// Runs only while Mission Control is open (started/stopped by MissionControlWatcher).
final class CloseButtonOverlay: NSObject {
    private let size: CGFloat = 24
    private lazy var panel: NSPanel = makePanel()
    private var timer: Timer?
    private var current: Thumbnail?
    private var buttonRectAX: CGRect = .zero   // where the ✕ is, in AX (top-left) coordinates
    private var loggedMiss = false
    private var thumbnails: [Thumbnail] = []
    private var thumbnailsRead = Date.distantPast

    /// Turned off from the menu if someone only wants ⌘W.
    var enabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "HideCloseButton") }
        set { UserDefaults.standard.set(!newValue, forKey: "HideCloseButton"); if !newValue { stop() } }
    }

    func start() {
        guard enabled else { return }
        timer?.invalidate()
        loggedMiss = false
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        thumbnails = []
        thumbnailsRead = .distantPast
        current = nil
        buttonRectAX = .zero
        panel.orderOut(nil)
    }

    private func update() {
        let mouse = WindowCloser.mouseLocation()

        // While the pointer is on our own ✕, keep targeting the same thumbnail.
        if panel.isVisible && buttonRectAX.insetBy(dx: -4, dy: -4).contains(mouse) { return }

        // Re-read the thumbnails 5 times a second (they move while Mission Control
        // animates, and after a window closes); hit-test against the cached list in between.
        if Date().timeIntervalSince(thumbnailsRead) > 0.2 {
            thumbnails = WindowCloser.missionControlThumbnails()
            thumbnailsRead = Date()
        }
        guard let thumb = WindowCloser.thumbnail(at: mouse, in: thumbnails) else {
            current = nil
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if !loggedMiss {
            // Once per Mission Control visit, note that finding thumbnails works at all.
            loggedMiss = true
            Log.write("overlay: \(thumbnails.count) window thumbnails; pointer on \(Log.title(thumb.title))")
        }
        current = thumb
        place(onTopLeftOf: thumb.frame)
    }

    private func place(onTopLeftOf thumbFrame: CGRect) {
        let rect = Geometry.closeButtonRect(forThumbnail: thumbFrame, size: size)
        if rect == buttonRectAX && panel.isVisible { return }
        buttonRectAX = rect
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        panel.setFrame(Geometry.appKitRect(fromAX: rect, mainScreenHeight: mainHeight), display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        // Must sit above Mission Control. If the ✕ never appears, try a higher level here.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        // .stationary keeps Mission Control from treating the panel as a window to shuffle.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let button = FirstClickButton(frame: NSRect(x: 0, y: 0, width: size, height: size))
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white, .black.withAlphaComponent(0.75)]))
        button.image = NSImage(systemSymbolName: "xmark.circle.fill",
                               accessibilityDescription: "Close window")?
            .withSymbolConfiguration(config)
        button.imageScaling = .scaleProportionallyUpOrDown
        button.isBordered = false
        button.target = self
        button.action = #selector(closeClicked)
        panel.contentView = button
        return panel
    }

    @objc private func closeClicked() {
        guard let current else { return }
        if WindowCloser.close(current, via: "✕ button") {
            self.current = nil
            buttonRectAX = .zero
            thumbnailsRead = .distantPast   // the layout changes after a close
            panel.orderOut(nil)
        }
    }
}
