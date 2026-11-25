import Cocoa

/// Watches input system-wide, but only acts while Mission Control is open:
/// - ⌘W closes the window under the pointer.
/// - A click on the ✕ closes that window. Mission Control takes clicks for itself even
///   when our ✕ is drawn on top (seen on macOS 15), so the click is caught here, before
///   Mission Control sees it.
/// Everywhere else every key and click passes through untouched.
final class KeyTap {
    /// Return true when we should intercept (i.e. Mission Control is open).
    var shouldHandle: () -> Bool = { false }
    /// Called on the main thread to close the window under the pointer (⌘W).
    var onClose: () -> Void = {}
    /// Is this point (AX / event coordinates) on the visible ✕?
    var isOnCloseButton: (CGPoint) -> Bool = { _ in false }
    /// Called on the main thread when the ✕ is clicked.
    var onCloseButtonClick: () -> Void = {}

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
                if Shortcut.isCommandW(keycode: event.getIntegerValueField(.keyboardEventKeycode),
                                       flags: event.flags.rawValue),
                   me.shouldHandle() {
                    // Held-down ⌘W repeats: swallow the repeats, act once.
                    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        DispatchQueue.main.async { me.onClose() }   // AX work off the callback
                    }
                    return nil
                }

            case .leftMouseDown:
                if me.shouldHandle(), me.isOnCloseButton(event.location) {
                    me.swallowMouseUp = true
                    DispatchQueue.main.async { me.onCloseButtonClick() }
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
