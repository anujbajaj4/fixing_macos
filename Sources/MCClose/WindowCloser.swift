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
    let element: AXUIElement
    let title: String
    let frame: CGRect   // top-left–origin global coordinates
}

enum WindowCloser {
    private static let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, 0.25)
        return el
    }()

    private static var dockPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
    }

    /// Mouse position in the same top-left–origin coordinates the AX API uses.
    static func mouseLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// The Mission Control thumbnail under `point`, if there is one.
    /// `trace` collects what was found, for the log.
    static func thumbnail(at point: CGPoint, trace: ((String) -> Void)? = nil) -> Thumbnail? {
        guard let dockPID else { trace?("Dock is not running"); return nil }
        var hit: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit)
        guard err == .success, var el = hit else { trace?("no element under pointer (AX error \(err.rawValue))"); return nil }
        guard AX.pid(el) == dockPID else {
            trace?("element under pointer belongs to pid \(AX.pid(el) ?? -1), not the Dock: \(AX.describe(el))")
            return nil
        }

        // The hit element may be a child of the thumbnail; walk up to the one with a title.
        for level in 0..<4 {
            trace?("level \(level): \(AX.describe(el))")
            let role = AX.string(el, kAXRoleAttribute) ?? ""
            if ThumbnailFilter.isBoundary(role: role) {
                trace?("not a window thumbnail (\(role))")
                return nil
            }
            if let title = AX.string(el, kAXTitleAttribute), !title.isEmpty,
               let frame = AX.frame(el) {
                guard ThumbnailFilter.isWindowThumbnail(role: role, ancestorTitles: ancestorTitles(of: el)) else {
                    trace?("not a window thumbnail (Spaces Bar)")
                    return nil
                }
                return Thumbnail(element: el, title: title, frame: frame)
            }
            guard let parent = AX.element(el, kAXParentAttribute) else { break }
            el = parent
        }
        return nil
    }

    private static func ancestorTitles(of el: AXUIElement) -> [String] {
        var titles: [String] = []
        var current = el
        for _ in 0..<6 {
            guard let parent = AX.element(current, kAXParentAttribute) else { break }
            if let t = AX.string(parent, kAXTitleAttribute), !t.isEmpty { titles.append(t) }
            current = parent
        }
        return titles
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
        var lines: [String] = []
        guard let thumb = thumbnail(at: mouseLocation(), trace: { lines.append($0) }) else {
            Log.write("⌘W: no thumbnail under pointer; " + lines.joined(separator: "; "))
            NSSound.beep()
            return false
        }
        return close(thumb, via: "⌘W")
    }
}
