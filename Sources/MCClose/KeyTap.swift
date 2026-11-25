import Cocoa

/// Watches input system-wide, but only acts while Mission Control is open:
/// - ⌘W / ⌘M / ⌃⌘F / ⌥⌘F / ⌘H / ⌘Q act on the window (or app) under the pointer, when the
///   pointer is on a window thumbnail. Otherwise the key passes through as usual.
/// - A click on one of the window buttons. Mission Control takes clicks for itself even
///   when our buttons are drawn on top (seen on macOS 15), so the click is caught here,
///   before Mission Control sees it.
/// Outside Mission Control every key and click passes through untouched.
final class KeyTap {
    /// True while Mission Control is open.
    var isActive: () -> Bool = { false }
    /// Is the pointer on a window thumbnail right now?
    var isPointerOnThumbnail: () -> Bool = { false }
    /// Called on the main thread for a shortcut.
    var onShortcut: (WindowAction) -> Void = { _ in }
    /// The window button at this point (AX / event coordinates), if any; the Bool is
    /// whether Option is held (Option-click on green zooms, as on a real window).
    var buttonAt: (CGPoint, Bool) -> WindowAction? = { _, _ in nil }
    /// Called on the main thread when a window button is clicked.
    var onButton: (WindowAction) -> Void = { _ in }

    fileprivate var tap: CFMachPort?
    fileprivate var swallowMouseUp = false
    fileprivate var loggedLostPermission = false
    fileprivate var disabledCount = 0
    /// The tap is only switched on while Mission Control is open, so the rest of the time
    /// MC Close is not in the keyboard and mouse path at all. (A stalled tap that is on
    /// makes every key press and click on the Mac wait for it.)
    fileprivate var wanted = false
    fileprivate var reenables = 0
    private var source: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)

        // A C callback: it can't capture anything, so `self` arrives through refcon.
        // It runs on the main run loop, so reading the overlay's state here is safe.
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()

            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                // macOS disables slow taps; turn ours back on, unless this copy of the app has
                // lost its Accessibility permission (e.g. while an update replaces it).
                guard me.wanted else { return Unmanaged.passUnretained(event) }
                guard AXIsProcessTrusted() else {
                    if !me.loggedLostPermission {
                        me.loggedLostPermission = true
                        Log.write("event tap disabled: this copy no longer has Accessibility permission")
                    }
                    return Unmanaged.passUnretained(event)
                }
                // If macOS keeps having to switch it off, stop: lag is worse than a missed ⌘W.
                me.reenables += 1
                guard me.reenables <= 5 else {
                    if me.reenables == 6 { Log.write("event tap keeps timing out; leaving it off until Mission Control opens again") }
                    return Unmanaged.passUnretained(event)
                }
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                me.disabledCount += 1
                if me.disabledCount <= 3 || me.disabledCount % 50 == 0 {
                    Log.write("event tap was disabled by macOS (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabled (\(me.disabledCount) so far)")
                }

            case .keyDown:
                if me.isActive(),
                   let action = Shortcut.action(keycode: event.getIntegerValueField(.keyboardEventKeycode),
                                                flags: event.flags.rawValue),
                   me.isPointerOnThumbnail() {
                    // Held-down keys repeat: swallow the repeats, act once.
                    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        DispatchQueue.main.async { me.onShortcut(action) }   // AX work off the callback
                    }
                    return nil
                }

            case .leftMouseDown:
                if me.isActive(), let action = me.buttonAt(event.location, event.flags.contains(.maskAlternate)) {
                    me.swallowMouseUp = true
                    DispatchQueue.main.async { me.onButton(action) }
                    return nil
                }

            case .leftMouseUp:
                if me.swallowMouseUp {
                    me.swallowMouseUp = false
                    return nil
                }

            default:
                break
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.write("could not create the event tap (Accessibility permission missing?)")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
        CGEvent.tapEnable(tap: tap, enable: wanted)
        Log.write("event tap started (active only while Mission Control is open)")
        return true
    }

    /// Switch input handling on (Mission Control opened) or off (closed).
    func setEnabled(_ on: Bool) {
        wanted = on
        reenables = 0
        swallowMouseUp = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: on) }
    }

    /// Remove the tap completely (before an update replaces this copy of the app).
    func shutDown() {
        setEnabled(false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        Log.write("event tap removed")
    }
}
