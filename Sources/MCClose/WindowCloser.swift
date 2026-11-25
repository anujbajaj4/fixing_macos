import Cocoa
import ApplicationServices

// MARK: - Small helpers around the Accessibility (AX) C API

enum AX {
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func bool(_ el: AXUIElement, _ attr: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    /// Frame in global screen coordinates, origin at the TOP-left of the main display.
    static func frame(_ el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    static func pid(_ el: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(el, &pid) == .success ? pid : nil
    }

    /// "AXButton/AXSomething" for the log.
    static func describe(_ el: AXUIElement) -> String {
        let role = string(el, kAXRoleAttribute) ?? "?"
        let sub = string(el, kAXSubroleAttribute).map { "/\($0)" } ?? ""
        let title = string(el, kAXTitleAttribute).map { " title=\(Log.title($0))" } ?? ""
        return "\(role)\(sub)\(title)"
    }
}

// MARK: - Finding and closing the window behind a Mission Control thumbnail

/// A window thumbnail as the Dock exposes it during Mission Control.
struct Thumbnail {
    let element: AXUIElement   // the Dock's (or, on macOS 27, WindowManager's) AXButton for this window
    let title: String
    let frame: CGRect   // top-left–origin global coordinates
    var appBundleID: String? = nil   // macOS 27 tells us the app in the thumbnail's identifier
    var native: NativeControls? = nil // where the window's own controls are, once measured
}

enum WindowCloser {
    private static var dockPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
    }

    /// Mouse position in the same top-left–origin coordinates the AX API uses.
    static func mouseLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Every window thumbnail Mission Control is showing, read from the Dock's AX tree.
    ///
    /// Why not ask "what is under the pointer" (AXUIElementCopyElementAtPosition)? In
    /// Mission Control that looks straight through the thumbnails and returns the real
    /// window underneath (seen on macOS 15), so we list the thumbnails and hit-test ourselves.
    static func missionControlThumbnails() -> [Thumbnail] {
        var found: [Thumbnail] = []

        func walk(_ el: AXUIElement, depth: Int, ancestors: [String]) {
            guard depth < 8, found.count < 300 else { return }
            let role = AX.string(el, kAXRoleAttribute) ?? ""
            if depth > 0 && ThumbnailFilter.isBoundary(role: role) { return }   // the Dock's icon row
            let identifier = AX.string(el, kAXIdentifierAttribute) ?? ""
            if MissionControl27.isSpacesElement(identifier: identifier) { return }   // desktops strip (macOS 27)
            let title = AX.string(el, kAXTitleAttribute) ?? ""
            if title == "Spaces Bar" { return }                                         // desktops strip (macOS 15)
            if depth > 0, !title.isEmpty,
               ThumbnailFilter.isWindowThumbnail(role: role, ancestorTitles: ancestors, identifier: identifier),
               let frame = AX.frame(el), frame.width > 20, frame.height > 20 {
                found.append(Thumbnail(element: el, title: title, frame: frame,
                                       appBundleID: MissionControl27.bundleID(fromThumbnailIdentifier: identifier)))
                return   // nothing to find inside a thumbnail
            }
            let next = title.isEmpty ? ancestors : [title] + ancestors
            for child in AX.elements(el, kAXChildrenAttribute) {
                walk(child, depth: depth + 1, ancestors: next)
            }
        }

        // macOS 15 and earlier: Mission Control lives in the Dock.
        if let dockPID {
            let dock = AXUIElementCreateApplication(dockPID)
            AXUIElementSetMessagingTimeout(dock, 0.25)
            walk(dock, depth: 0, ancestors: [])
        }
        // macOS 27: in WindowManager, one "mc.display" group per display. Only those groups
        // are searched, so Stage Manager's own buttons never count.
        for group in missionControlDisplayGroups() {
            walk(group, depth: 1, ancestors: [])
        }
        return found
    }

    /// WindowManager's "mc.display" groups (present only while Mission Control is open, macOS 27).
    static func missionControlDisplayGroups() -> [AXUIElement] {
        guard let pid = NSRunningApplication.runningApplications(
            withBundleIdentifier: MissionControl27.windowManagerBundleID).first?.processIdentifier else { return [] }
        let wm = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(wm, 0.25)
        return AX.elements(wm, kAXChildrenAttribute).filter {
            MissionControl27.isDisplayGroup(identifier: AX.string($0, kAXIdentifierAttribute) ?? "")
        }
    }

    /// The thumbnail in `thumbnails` under `point`, if any.
    static func thumbnail(at point: CGPoint, in thumbnails: [Thumbnail]) -> Thumbnail? {
        Geometry.index(of: point, in: thumbnails.map(\.frame)).map { thumbnails[$0] }
    }

    /// Match a thumbnail to the app's real window by title.
    /// Returns the window when exactly one fits. When several fit equally well, returns
    /// them all as `ambiguous` (an app-level action can still act if they share one app).
    static func realWindows(for thumb: Thumbnail, trace: ((String) -> Void)? = nil)
        -> (window: AXUIElement?, ambiguous: [AXUIElement]) {
        match(thumb, in: snapshot(), trace: trace)
    }

    /// Every window of every normal, visible app, read once, so many thumbnails can be
    /// checked against it. Safe to call off the main thread.
    struct WindowSnapshot {
        var windows: [AXUIElement] = []
        var candidates: [WindowCandidate] = []
        var bundleIDs: [String?] = []
    }

    static func snapshot() -> WindowSnapshot {
        var snap = WindowSnapshot()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.3) // don't hang on a frozen app
            let appName = app.localizedName ?? ""
            for window in AX.elements(appElement, kAXWindowsAttribute) {
                // Invisible helper windows are often tiny; they're never what a thumbnail shows.
                let frame = AX.frame(window)
                if let f = frame, f.width < 40 || f.height < 30 { continue }
                snap.windows.append(window)
                snap.bundleIDs.append(app.bundleIdentifier)
                snap.candidates.append(WindowCandidate(
                    title: AX.string(window, kAXTitleAttribute) ?? "",
                    appName: appName,
                    minimized: AX.bool(window, kAXMinimizedAttribute) ?? false,
                    size: frame?.size))
            }
        }
        return snap
    }

    /// Where a window's own close/minimize/zoom controls are, relative to its top-left corner,
    /// so ours can be drawn exactly over their miniature in the thumbnail. nil if the window
    /// has no standard controls where expected.
    static func nativeControls(_ window: AXUIElement) -> NativeControls? {
        guard let wf = AX.frame(window), wf.width > 0,
              let close = AX.element(window, kAXCloseButtonAttribute), let cf = AX.frame(close),
              cf.width >= 6, cf.width <= 30 else { return nil }
        let center = CGPoint(x: cf.midX - wf.minX, y: cf.midY - wf.minY)
        guard center.x > 0, center.x < 200, center.y > 0, center.y < 80 else { return nil }   // in the title bar
        var spacing = cf.width * 20 / 14   // Apple's proportions, if minimize can't be measured
        if let m = AX.element(window, kAXMinimizeButtonAttribute), let mf = AX.frame(m),
           mf.midX > cf.midX, mf.midX - cf.midX < cf.width * 3 {
            spacing = mf.midX - cf.midX
        }
        return NativeControls(closeCenter: center, diameter: cf.width, spacing: spacing, windowSize: wf.size)
    }

    /// The one real window behind `thumb`, or the equally good ones if it's ambiguous.
    /// macOS 27 thumbnails name their app, so only that app's windows are considered.
    static func match(_ thumb: Thumbnail, in snap: WindowSnapshot, trace: ((String) -> Void)? = nil)
        -> (window: AXUIElement?, ambiguous: [AXUIElement]) {
        var indices = Array(snap.windows.indices)
        var oneApp = false
        if let bundle = thumb.appBundleID {
            let own = indices.filter { snap.bundleIDs[$0] == bundle }
            if !own.isEmpty { indices = own; oneApp = true; trace?("thumbnail belongs to \(bundle)") }
        }
        // Within one app, the thumbnail's shape can identify the window when titles differ.
        let outcome = WindowMatcher.pick(thumbnailTitle: thumb.title, thumbnailSize: thumb.frame.size,
                                         shapeAlone: oneApp, from: indices.map { snap.candidates[$0] })
        trace?("thumbnail \(Log.title(thumb.title)) vs \(indices.count) windows: \(outcome)")
        switch outcome {
        case .match(let i): return (snap.windows[indices[i]], [])
        case .ambiguous(let list): return (nil, list.map { snap.windows[indices[$0]] })
        case .none: return (nil, [])
        }
    }

    /// Do `action` to the real window behind `thumb`.
    @discardableResult
    static func perform(_ action: WindowAction, on thumb: Thumbnail, via source: String) -> Bool {
        var lines: [String] = []
        let trace: (String) -> Void = { lines.append($0) }
        defer { Log.write("\(source) \(action.rawValue): " + lines.joined(separator: "; ")) }

        let found = realWindows(for: thumb, trace: trace)
        let ok: Bool
        if action.isAppAction {
            // Hide/Quit only need the app: fine even if several of its windows share the title.
            let pids = Set((found.window.map { [$0] } ?? found.ambiguous).compactMap(AX.pid))
            guard pids.count == 1, let pid = pids.first,
                  let app = NSRunningApplication(processIdentifier: pid) else {
                trace(pids.isEmpty ? "no window found, nothing done" : "windows from \(pids.count) apps match, nothing done")
                NSSound.beep()
                return false
            }
            ok = action == .quitApp ? app.terminate() : app.hide()   // terminate lets the app ask to save
            trace("\(action == .quitApp ? "asked the app to quit" : "hid the app"): \(ok ? "ok" : "refused")")
        } else {
            guard let window = found.window else {
                trace("no unique window found, nothing done")
                NSSound.beep()
                return false
            }
            switch action {
            case .close: ok = press(window, kAXCloseButtonAttribute, trace)
            case .minimize: ok = set(window, kAXMinimizedAttribute, true, trace)
                                 || press(window, kAXMinimizeButtonAttribute, trace)
            case .fullScreen: ok = enterFullScreen(window, thumb: thumb, trace)
            case .zoom: ok = zoom(window, trace)
            case .hideApp, .quitApp: ok = false   // handled above
            }
        }
        if !ok { NSSound.beep() }
        return ok
    }

    // MARK: Full screen

    /// macOS ignores a full-screen request while Mission Control is showing (seen in CI on
    /// macOS 15), so first pick the window, as clicking its thumbnail would, which leaves
    /// Mission Control; then take it full screen.
    private static func enterFullScreen(_ window: AXUIElement, thumb: Thumbnail, _ trace: (String) -> Void) -> Bool {
        let r = AXUIElementPerformAction(thumb.element, kAXPressAction as CFString)
        if r == .success {
            trace("picked the window to leave Mission Control; full screen follows")
        } else {
            trace("couldn't pick the thumbnail (AX error \(r.rawValue)); pressing Escape to leave Mission Control")
            let src = CGEventSource(stateID: .hidSystemState)
            CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            var later: [String] = []
            let note: (String) -> Void = { later.append($0) }
            let ok = set(window, "AXFullScreen", true, note)
                || press(window, kAXFullScreenButtonAttribute, note)
                || press(window, kAXZoomButtonAttribute, note)
            Log.write("full screen, after leaving Mission Control: " + later.joined(separator: "; "))
            if !ok { NSSound.beep() }
        }
        return true
    }

    // MARK: Zoom (what Option-clicking the green button does)

    /// Windows we zoomed, with their size before, so a second Zoom restores them.
    private static var framesBeforeZoom: [(window: AXUIElement, frame: CGRect)] = []

    /// Fill the usable part of the window's screen (not the menu bar or Dock), in place,
    /// without a separate full-screen space. If it already fills it, put it back.
    private static func zoom(_ window: AXUIElement, _ trace: (String) -> Void) -> Bool {
        guard let frame = AX.frame(window) else { trace("window has no frame"); return false }
        let visible = visibleFrameAX(around: CGPoint(x: frame.midX, y: frame.midY))
        let saved = framesBeforeZoom.firstIndex { CFEqual($0.window, window) }

        if Geometry.isFilling(frame, visible), let i = saved {
            let old = framesBeforeZoom.remove(at: i).frame
            trace("already zoomed: restoring")
            return setFrame(window, old, trace)
        }
        if let i = saved { framesBeforeZoom.remove(at: i) }
        framesBeforeZoom.append((window, frame))
        if framesBeforeZoom.count > 50 { framesBeforeZoom.removeFirst() }
        return setFrame(window, visible, trace)
    }

    /// The visible frame (minus menu bar and Dock) of the screen containing `point`, in AX coordinates.
    private static func visibleFrameAX(around point: CGPoint) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let screen = NSScreen.screens.first {
            Geometry.axRect(fromAppKit: $0.frame, mainScreenHeight: mainHeight).contains(point)
        } ?? NSScreen.main ?? NSScreen.screens.first
        return Geometry.axRect(fromAppKit: screen?.visibleFrame ?? .zero, mainScreenHeight: mainHeight)
    }

    private static func setFrame(_ window: AXUIElement, _ rect: CGRect, _ trace: (String) -> Void) -> Bool {
        var origin = rect.origin
        var size = rect.size
        guard let pos = AXValueCreate(.cgPoint, &origin), let sz = AXValueCreate(.cgSize, &size) else { return false }
        // Position, size, position again: apps clamp the size to what fits where the window is.
        let r1 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        let r2 = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz)
        _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        let ok = r1 == .success && r2 == .success
        trace(ok ? "set frame to \(Int(rect.width))x\(Int(rect.height)) at \(Int(rect.minX)),\(Int(rect.minY))"
                 : "setting frame failed (AX errors \(r1.rawValue), \(r2.rawValue))")
        return ok
    }

    private static func press(_ window: AXUIElement, _ buttonAttribute: String, _ trace: (String) -> Void) -> Bool {
        guard let button = AX.element(window, buttonAttribute) else {
            trace("window has no \(buttonAttribute)")
            return false
        }
        let r = AXUIElementPerformAction(button, kAXPressAction as CFString)
        trace(r == .success ? "pressed \(buttonAttribute)" : "pressing \(buttonAttribute) failed (AX error \(r.rawValue))")
        return r == .success
    }

    private static func set(_ window: AXUIElement, _ attribute: String, _ value: Bool, _ trace: (String) -> Void) -> Bool {
        let r = AXUIElementSetAttributeValue(window, attribute as CFString, (value ? kCFBooleanTrue! : kCFBooleanFalse!))
        trace(r == .success ? "set \(attribute)=\(value)" : "setting \(attribute) failed (AX error \(r.rawValue))")
        return r == .success
    }

    /// Keyboard shortcuts: act on the thumbnail under the pointer, read fresh.
    @discardableResult
    static func performUnderMouse(_ action: WindowAction) -> Bool {
        let thumbs = missionControlThumbnails()
        let mouse = mouseLocation()
        guard let thumb = thumbnail(at: mouse, in: thumbs) else {
            Log.write("key \(action.rawValue): pointer (\(Int(mouse.x)), \(Int(mouse.y))) is not on any of the \(thumbs.count) window thumbnails")
            NSSound.beep()
            return false
        }
        return perform(action, on: thumb, via: "key")
    }
}
