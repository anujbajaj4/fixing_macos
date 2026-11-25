import Cocoa

/// Listens for ⌘W system-wide, but only acts on it while Mission Control is open.
/// Everywhere else ⌘W passes through untouched.
final class KeyTap {
    /// Return true when we should intercept (i.e. Mission Control is open).
    var shouldHandle: () -> Bool = { false }
    /// Called on the main thread to close the window under the pointer.
    var onClose: () -> Void = {}

    fileprivate var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // A C callback: it can't capture anything, so `self` arrives through refcon.
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()

            // macOS disables slow taps; turn ours back on if that happens.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                Log.write("event tap was disabled by macOS (\(type.rawValue)); re-enabled")
                return Unmanaged.passUnretained(event)
            }

            if type == .keyDown,
               Shortcut.isCommandW(keycode: event.getIntegerValueField(.keyboardEventKeycode),
                                   flags: event.flags.rawValue),
               me.shouldHandle() {
                // Held-down ⌘W repeats: swallow the repeats, act once.
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    // Do the (slower) AX work off the tap callback.
                    DispatchQueue.main.async { me.onClose() }
                }
                return nil
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
            Log.write("could not create the keyboard event tap (Accessibility permission missing?)")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.write("keyboard event tap started")
        return true
    }
}
