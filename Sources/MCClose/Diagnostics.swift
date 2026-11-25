import Cocoa

/// "Diagnose Mission Control…" in the menu: records what this Mac's Dock shows while
/// Mission Control is open, so a problem on a macOS version we haven't seen can be fixed
/// from evidence. Writes to the normal log. Window titles are shown only as their length
/// (unless VerboseLog is on), so the log is safe to share.
enum Diagnostics {
    static var isRunning = false

    static func run(watcherActive: @escaping () -> Bool, watcherSource: @escaping () -> String) {
        guard !isRunning else { return }
        let alert = NSAlert()
        alert.messageText = "Diagnose Mission Control"
        alert.informativeText = """
            After you click Start, open Mission Control within 5 seconds \
            (swipe up with three or four fingers, press F3, or press Control-↑) \
            and point at a window. Keep Mission Control open for about 15 seconds, \
            until this window comes back saying the diagnosis is recorded.

            MC Close writes what it sees to its log. Window titles are left out.
            """
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isRunning = true
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        Log.write("diagnose: started (MC Close \(AppState.version), macOS \(os), \(NSScreen.screens.count) display(s): "
                  + NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" }.joined(separator: ", ") + ")")

        for (i, delay) in [5.0, 8.0, 11.0, 14.0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                snapshot(i + 1, active: watcherActive(), source: watcherSource())
                if i == 3 { finish() }
            }
        }
    }

    private static func snapshot(_ n: Int, active: Bool, source: String) {
        let mouse = WindowCloser.mouseLocation()
        let thumbs = WindowCloser.missionControlThumbnails()
        let hit = WindowCloser.thumbnail(at: mouse, in: thumbs)
        var lines = ["diagnose \(n)/4: Mission Control \(active ? "open" : "closed") according to MC Close"
                     + (active ? " (by \(source))" : "")
                     + "; pointer \(Int(mouse.x)),\(Int(mouse.y)); \(thumbs.count) window thumbnails; pointer on "
                     + (hit.map { "one (\(Log.title($0.title)))" } ?? "none")]
        if let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier {
            lines.append("  Dock layout check says: \(MissionControlWatcher.dockLooksLikeMissionControl(pid: pid) ? "open" : "closed")")
            lines += dockTree(pid: pid)
        }
        // Which process draws Mission Control on this macOS? (On macOS 15 it's the Dock.)
        let windows = SystemProbe.windows()
        lines.append("  on-screen windows (owner, pid, layer, frame); normal app windows only counted:")
        lines += SystemProbe.describe(windows).map { "    " + $0 }
        lines.append("  element under the pointer:")
        lines += SystemProbe.elementChain(at: mouse).map { "    " + $0 }
        for pid in SystemProbe.bigOverlayOwners(windows).prefix(2) {
            let name = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)"
            lines.append("  accessibility tree of \(name) (it has a large window above normal windows):")
            lines += SystemProbe.axTree(pid: pid, maxLines: 80).map { "  " + $0 }
        }
        Log.write(lines.joined(separator: "\n"))
    }

    /// The Dock's accessibility tree, without the Dock's icon row.
    private static func dockTree(pid: pid_t) -> [String] {
        let dock = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(dock, 0.3)
        var out: [String] = []
        func walk(_ el: AXUIElement, _ depth: Int) {
            guard depth <= 7, out.count < 120 else { return }
            let role = AX.string(el, kAXRoleAttribute) ?? "?"
            let sub = AX.string(el, kAXSubroleAttribute).map { "/\($0)" } ?? ""
            let children = AX.elements(el, kAXChildrenAttribute)
            if role == "AXList" {
                out.append(String(repeating: "  ", count: depth + 1) + "AXList (Dock icons, \(children.count) skipped)")
                return
            }
            let title = AX.string(el, kAXTitleAttribute).map { " title=\(Log.title($0))" } ?? ""
            let frame = AX.frame(el).map { " \(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? ""
            out.append(String(repeating: "  ", count: depth + 1) + "\(role)\(sub)\(title)\(frame) children=\(children.count)")
            for c in children { walk(c, depth + 1) }
        }
        walk(dock, 0)
        return out
    }

    private static func finish() {
        isRunning = false
        Log.write("diagnose: finished")
        let alert = NSAlert()
        alert.messageText = "Diagnosis recorded"
        alert.informativeText = "Choose Open Log to see it, or run this in Terminal and send the output:\n\ntail -150 ~/Library/Logs/MCClose.log"
        alert.addButton(withTitle: "Open Log")
        alert.addButton(withTitle: "Done")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(Log.url) }
    }
}

/// Looks at the whole screen, not just the Dock. No window titles are read (macOS keeps
/// those behind Screen Recording permission anyway); element titles go through Log.title.
enum SystemProbe {
    struct Win { let owner: String; let pid: pid_t; let layer: Int; let frame: CGRect }

    static func windows() -> [Win] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return info.compactMap { d in
            guard let b = d[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: b) else { return nil }
            return Win(owner: d[kCGWindowOwnerName as String] as? String ?? "?",
                       pid: pid_t(d[kCGWindowOwnerPID as String] as? Int ?? 0),
                       layer: d[kCGWindowLayer as String] as? Int ?? 0, frame: frame)
        }
    }

    /// Non-zero layers in full; normal (layer 0) windows as a count per app.
    static func describe(_ wins: [Win]) -> [String] {
        var out = wins.filter { $0.layer != 0 }.sorted { $0.layer > $1.layer }.prefix(40).map {
            "\($0.owner) (\($0.pid)) layer \($0.layer) \(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))"
        }
        let normal = Dictionary(grouping: wins.filter { $0.layer == 0 }, by: \.owner).map { "\($0.key)×\($0.value.count)" }.sorted()
        out.append("layer 0: " + (normal.isEmpty ? "none" : normal.joined(separator: ", ")))
        return out
    }

    /// Processes (not us) with a window above normal windows that covers most of a screen.
    static func bigOverlayOwners(_ wins: [Win]) -> [pid_t] {
        let me = ProcessInfo.processInfo.processIdentifier
        let screens = NSScreen.screens.map(\.frame)
        var seen: [pid_t] = []
        for w in wins.sorted(by: { $0.layer > $1.layer }) where w.layer > 0 && w.pid != me {
            let big = screens.contains { w.frame.width >= $0.width * 0.8 && w.frame.height >= $0.height * 0.8 }
            if big && !seen.contains(w.pid) { seen.append(w.pid) }
        }
        return seen
    }

    /// The accessibility element under `point` and its parents, with the owning app.
    static func elementChain(at point: CGPoint) -> [String] {
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.3)
        var hit: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(sys, Float(point.x), Float(point.y), &hit)
        guard err == .success, var el = hit else { return ["nothing (AX error \(err.rawValue))"] }
        var out: [String] = []
        if let pid = AX.pid(el) {
            let app = NSRunningApplication(processIdentifier: pid)
            out.append("owner: \(app?.bundleIdentifier ?? app?.localizedName ?? "?") (pid \(pid))")
        }
        for depth in 0..<7 {
            let frame = AX.frame(el).map { " \(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? ""
            out.append(String(repeating: "  ", count: depth) + AX.describe(el) + frame)
            guard let parent = AX.element(el, kAXParentAttribute) else { break }
            el = parent
        }
        return out
    }

    static func axTree(pid: pid_t, maxLines: Int) -> [String] {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.3)
        var out: [String] = []
        func walk(_ el: AXUIElement, _ depth: Int) {
            guard depth <= 7, out.count < maxLines else { return }
            let children = AX.elements(el, kAXChildrenAttribute)
            let frame = AX.frame(el).map { " \(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? ""
            out.append(String(repeating: "  ", count: depth + 1) + AX.describe(el) + frame + " children=\(children.count)")
            for c in children { walk(c, depth + 1) }
        }
        walk(root, 0)
        return out
    }
}
