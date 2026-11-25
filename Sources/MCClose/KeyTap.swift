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
    /// The window button at this point (AX / event coordinates), if any.
    var buttonAt: (CGPoint) -> WindowAction? = { _ in nil }
    /// Called on the main thread when a window button is clicked.
    var onButton: (WindowAction) -> Void = { _ in }

    fileprivate var tap: CFMachPort?
    fileprivate var swallowMouseUp = false
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
                // macOS disables slow taps; turn ours back on.
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                Log.write("event tap was disabled by macOS (\(type.rawValue)); re-enabled")

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
                if me.isActive(), let action = me.buttonAt(event.location) {
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
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.write("event tap started")
        return true
    }
}
