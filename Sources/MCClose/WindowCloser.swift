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
    let element: AXUIElement   // the Dock's AXButton for this window
    let title: String
    let frame: CGRect   // top-left–origin global coordinates
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
        guard let dockPID else { return [] }
        let dock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dock, 0.25)
        var found: [Thumbnail] = []

        func walk(_ el: AXUIElement, depth: Int, ancestors: [String]) {
            guard depth < 8, found.count < 300 else { return }
            let role = AX.string(el, kAXRoleAttribute) ?? ""
            if depth > 0 && ThumbnailFilter.isBoundary(role: role) { return }   // the Dock's icon row
            let title = AX.string(el, kAXTitleAttribute) ?? ""
            if title == "Spaces Bar" { return }
            if depth > 0, !title.isEmpty,
               ThumbnailFilter.isWindowThumbnail(role: role, ancestorTitles: ancestors),
               let frame = AX.frame(el), frame.width > 20, frame.height > 20 {
                found.append(Thumbnail(element: el, title: title, frame: frame))
                return   // nothing to find inside a thumbnail
            }
            let next = title.isEmpty ? ancestors : [title] + ancestors
            for child in AX.elements(el, kAXChildrenAttribute) {
                walk(child, depth: depth + 1, ancestors: next)
            }
        }
        walk(dock, depth: 0, ancestors: [])
        return found
    }

    /// The thumbnail in `thumbnails` under `point`, if any.
    static func thumbnail(at point: CGPoint, in thumbnails: [Thumbnail]) -> Thumbnail? {
        Geometry.index(of: point, in: thumbnails.map(\.frame)).map { thumbnails[$0] }
    }

    /// Match a thumbnail to the app's real window by title.
    /// If the match is ambiguous we return nil — better to do nothing than close the wrong window.
    static func realWindow(for thumb: Thumbnail, trace: ((String) -> Void)? = nil) -> AXUIElement? {
        var windows: [AXUIElement] = []
        var candidates: [WindowCandidate] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.3) // don't hang on a frozen app
            let appName = app.localizedName ?? ""
            for window in AX.elements(appElement, kAXWindowsAttribute) {
                windows.append(window)
                candidates.append(WindowCandidate(
                    title: AX.string(window, kAXTitleAttribute) ?? "",
                    appName: appName,
                    minimized: AX.bool(window, kAXMinimizedAttribute) ?? false))
            }
        }
        let outcome = WindowMatcher.pick(thumbnailTitle: thumb.title, from: candidates)
        trace?("thumbnail \(Log.title(thumb.title)) vs \(candidates.count) windows: \(outcome)")
        if case .match(let i) = outcome { return windows[i] }
        return nil
    }

    /// Press the real window's red close button.
    @discardableResult
    static func close(_ thumb: Thumbnail, via source: String) -> Bool {
        var lines: [String] = []
        let trace: (String) -> Void = { lines.append($0) }
        defer { Log.write("\(source): " + lines.joined(separator: "; ")) }

        guard let window = realWindow(for: thumb, trace: trace) else {
            trace("no unique window found, nothing closed")
            NSSound.beep()
            return false
        }
        guard let closeButton = AX.element(window, kAXCloseButtonAttribute) else {
            trace("window has no close button")
            NSSound.beep()
            return false
        }
        let result = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        trace(result == .success ? "pressed close button" : "close press failed (AX error \(result.rawValue))")
        return result == .success
    }

    @discardableResult
    static func closeWindowUnderMouse() -> Bool {
        let thumbs = missionControlThumbnails()
        let mouse = mouseLocation()
        guard let thumb = thumbnail(at: mouse, in: thumbs) else {
            Log.write("⌘W: pointer (\(Int(mouse.x)), \(Int(mouse.y))) is not on any of the \(thumbs.count) window thumbnails")
            NSSound.beep()
            return false
        }
        return close(thumb, via: "⌘W")
    }
}
