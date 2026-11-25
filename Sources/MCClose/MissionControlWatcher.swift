import Cocoa
import ApplicationServices

/// Detects when Mission Control opens and closes.
///
/// Mission Control is drawn by the Dock process. The Dock posts (undocumented) accessibility
/// notifications when it enters and leaves Mission Control, so we subscribe to those.
/// Not every macOS sends them (none arrived on a user's macOS 27), so as a backup we also
/// look at the Dock's layout about 3 times a second: a few cheap AX queries.
final class MissionControlWatcher {
    private(set) var isActive = false
    var onChange: ((Bool) -> Void)?
    /// How many of the notifications the Dock accepted (shown in the menu, for diagnosis).
    private(set) var subscribed = 0

    private var observer: AXObserver?
    private var pollTimer: Timer?
    private var activeByPoll = false       // the backup check opened it, so it may close it
    private var dockPID: pid_t = 0
    private(set) var lastSource = ""       // "notification" or "layout", for diagnosis
    private var launchObserver: NSObjectProtocol?
    private let notifications = [
        "AXExposeShowAllWindows",   // Mission Control opened
        "AXExposeShowFrontWindows", // App Exposé opened
        "AXExposeShowDesktop",      // Show Desktop
        "AXExposeExit",             // Mission Control closed
    ]

    func start() {
        attachToDock()
        if pollTimer == nil {
            let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(t, forMode: .common)
            pollTimer = t
        }

        // The Dock restarts sometimes (e.g. `killall Dock`). Re-attach when it does.
        guard launchObserver == nil else { return }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == "com.apple.dock" {
                Log.write("Dock relaunched; re-attaching")
                self?.activeByPoll = false
                self?.setActive(false)
                // Give the Dock a moment to finish launching.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.attachToDock() }
            }
        }
    }

    private func attachToDock() {
        if let old = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .commonModes)
            observer = nil
        }
        subscribed = 0
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            Log.write("Dock is not running; can't watch Mission Control")
            return
        }

        let pid = dock.processIdentifier
        dockPID = pid
        let dockElement = AXUIElementCreateApplication(pid)

        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<MissionControlWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.handle(notification as String)
        }

        var newObserver: AXObserver?
        let err = AXObserverCreate(pid, callback, &newObserver)
        guard err == .success, let newObserver else {
            Log.write("could not observe the Dock (AX error \(err.rawValue))")
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var results: [String] = []
        for name in notifications {
            let r = AXObserverAddNotification(newObserver, dockElement, name as CFString, refcon)
            if r == .success { subscribed += 1 }
            results.append("\(name)=\(r == .success ? "ok" : "error \(r.rawValue)")")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        observer = newObserver
        Log.write("watching Dock pid \(pid): " + results.joined(separator: ", "))
    }

    private func handle(_ name: String) {
        // Test setting: behave like a macOS that sends no notifications (CI uses this to
        // check the backup detection on a real Mission Control).
        if UserDefaults.standard.bool(forKey: "IgnoreDockNotifications") {
            Log.write("ignored Dock notification \(name) (IgnoreDockNotifications is on)")
            return
        }
        Log.write("Dock says \(name)")
        activeByPoll = false
        lastSource = "notification"
        setActive(name == "AXExposeShowAllWindows" || name == "AXExposeShowFrontWindows")
    }

    /// The backup check. It only opens what it can see, and only closes what it opened,
    /// so it never fights the Dock's own notifications.
    private func poll() {
        guard dockPID != 0 else { return }
        let open = Self.dockLooksLikeMissionControl(pid: dockPID)
        if open && !isActive {
            Log.write("Dock layout shows Mission Control (no notification from the Dock)")
            activeByPoll = true
            lastSource = "layout"
            setActive(true)
        } else if !open && isActive && activeByPoll {
            Log.write("Dock layout shows Mission Control closed")
            activeByPoll = false
            setActive(false)
        }
    }

    /// The Dock's top two levels: is there a group covering a whole screen?
    static func dockLooksLikeMissionControl(pid: pid_t) -> Bool {
        let dock = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(dock, 0.1)
        var found: [(role: String, frame: CGRect)] = []
        for child in AX.elements(dock, kAXChildrenAttribute) {
            let role = AX.string(child, kAXRoleAttribute) ?? ""
            if role == "AXList" { continue }   // the icon row
            if let f = AX.frame(child) { found.append((role, f)) }
            for grandchild in AX.elements(child, kAXChildrenAttribute) {
                if let r = AX.string(grandchild, kAXRoleAttribute), let f = AX.frame(grandchild) {
                    found.append((r, f))
                }
            }
        }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { Geometry.axRect(fromAppKit: $0.frame, mainScreenHeight: mainHeight) }
        return MissionControlLayout.looksOpen(dockElements: found, screens: screens)
    }

    private func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onChange?(active)
    }
}
