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
            and point at a window. Stay there for about 10 seconds.

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
